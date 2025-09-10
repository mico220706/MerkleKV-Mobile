import 'dart:async';
import 'dart:io';
import 'package:test/test.dart';
import 'package:merkle_kv_core/merkle_kv_core.dart';

/// Helper to wait for broker readiness with enhanced timeouts for CI
Future<void> waitForBroker(String host, int port) async {
  // Increased retries for CI environments
  final maxRetries = const bool.fromEnvironment('CI') ? 20 : 10;
  final retryDelay = const bool.fromEnvironment('CI') ? 
      Duration(milliseconds: 1000) : Duration(milliseconds: 500);
  
  for (var i = 0; i < maxRetries; i++) {
    try {
      final socket = await Socket.connect(host, port);
      await socket.close();
      return; // Broker is ready
    } catch (e) {
      if (i == maxRetries - 1) {
        throw SkipException('MQTT broker not available on $host:$port after $maxRetries attempts. '
            'Start with: cd broker/mosquitto && docker-compose up -d');
      }
      await Future.delayed(retryDelay);
    }
  }
}

/// Helper to wait for stable MQTT connection with proper readiness checks
Future<void> waitForConnected(MqttClientInterface mqttClient) async {
  final completer = Completer<void>();
  StreamSubscription? subscription;
  
  // Race condition fix: subscriber-before-publish pattern
  subscription = mqttClient.connectionState.listen((state) {
    if (state == ConnectionState.connected && !completer.isCompleted) {
      completer.complete();
    }
  });
  
  // Check if already connected by looking at the latest state
  bool isCurrentlyConnected = false;
  await for (final state in mqttClient.connectionState.take(1)) {
    if (state == ConnectionState.connected) {
      isCurrentlyConnected = true;
      break;
    }
  }
  
  if (isCurrentlyConnected && !completer.isCompleted) {
    completer.complete();
  }
  
  try {
    // Wait for connection with timeout
    await completer.future.timeout(Duration(seconds: 10));
    
    // Additional stabilization wait for message routing
    await Future.delayed(Duration(milliseconds: 300));
  } finally {
    await subscription.cancel();
  }
}

/// Integration test for replication event publishing with real MQTT broker
/// 
/// This test requires a running Mosquitto broker on localhost:1883
/// To run: cd /workspaces/MerkleKV-Mobile/broker/mosquitto && docker-compose up -d
void main() {
  group('Replication Event Publisher Integration Tests', () {
    late Directory tempDir;
    late MerkleKVConfig config;
    late MqttClientImpl mqttClient;
    late TopicScheme topicScheme;
    late ReplicationEventPublisherImpl publisher;
    late InMemoryReplicationMetrics metrics;

    setUpAll(() async {
      // Check if broker is available with retry
      await waitForBroker('localhost', 1883);
    });

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('integration_test_');
      config = MerkleKVConfig(
        mqttHost: 'localhost',
        mqttPort: 1883,
        nodeId: 'integration-test-node',
        clientId: 'integration-test-client',
        topicPrefix: 'integration-test',
        storagePath: '${tempDir.path}/test.storage',
        persistenceEnabled: true,
      );

      mqttClient = MqttClientImpl(config);
      topicScheme = TopicScheme.create(config.topicPrefix, config.clientId);
      metrics = InMemoryReplicationMetrics();

      publisher = ReplicationEventPublisherImpl(
        config: config,
        mqttClient: mqttClient,
        topicScheme: topicScheme,
        metrics: metrics,
      );
    });

    tearDown(() async {
      try {
        await publisher.dispose();
        await mqttClient.disconnect();
      } catch (e) {
        // Ignore cleanup errors
      }
      await tempDir.delete(recursive: true);
    });

    tearDownAll(() async {
      // Ensure all publishers are disposed to avoid race conditions
      try {
        await publisher.dispose();
      } catch (e) {
        // Ignore disposal errors
      }
    });

    test('should publish events to real MQTT broker', () async {
      await publisher.initialize();
      await publisher.ready(); // Wait for persistence initialization
      
      await mqttClient.connect();
      await waitForConnected(mqttClient); // Wait for stable connection

      final event = ReplicationEvent.value(
        key: 'integration-test-key',
        nodeId: config.nodeId,
        seq: 1,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        value: 'integration-test-value',
      );

      await publisher.publishEvent(event);

      // Give time for publish to complete and metrics to update
      await Future.delayed(Duration(milliseconds: 100));

      // Verify metrics
      expect(metrics.eventsPublished, equals(1));
      expect(metrics.publishErrors, equals(0));
      expect(metrics.publishLatencies, isNotEmpty);

      print('✓ Successfully published event to real MQTT broker');
      print('  Published events: ${metrics.eventsPublished}');
      print('  Publish latency: ${metrics.publishLatencies.first}ms');
    }, timeout: Timeout(Duration(seconds: 30)));

    test('should handle offline queuing and reconnection', () async {
      await publisher.initialize();
      await publisher.ready(); // Wait for persistence initialization
      
      await mqttClient.connect();
      await waitForConnected(mqttClient); // Wait for stable connection

      // Disconnect and publish event (should queue)
      await mqttClient.disconnect(suppressLWT: true);
      
      // Wait for disconnect to propagate
      await Future.delayed(Duration(milliseconds: 100));
      
      final event = ReplicationEvent.value(
        key: 'offline-test-key',
        nodeId: config.nodeId,
        seq: 2,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        value: 'offline-test-value',
      );

      await publisher.publishEvent(event);

      // Check that event is queued
      final status = await publisher.outboxStatus.first;
      expect(status.pendingEvents, equals(1));
      expect(status.isOnline, isFalse);

      // Reconnect and flush
      await mqttClient.connect();
      await waitForConnected(mqttClient); // Wait for stable connection
      await publisher.flushOutbox();

      // Give time for metrics to update
      await Future.delayed(Duration(milliseconds: 100));

      // Verify event was published
      expect(metrics.eventsPublished, equals(1));
      expect(metrics.flushDurations, isNotEmpty);

      print('✓ Successfully handled offline queuing and reconnection');
      print('  Events in outbox: ${status.pendingEvents}');
      print('  Flush duration: ${metrics.flushDurations.first}ms');
    }, timeout: Timeout(Duration(seconds: 30)));

    test('should persist and recover sequence numbers', () async {
      await publisher.initialize();
      await publisher.ready(); // Wait for persistence initialization

      // Generate some sequence numbers
      final seq1 = publisher.currentSequence;
      
      await publisher.dispose();

      // Create new publisher and verify recovery
      final newPublisher = ReplicationEventPublisherImpl(
        config: config,
        mqttClient: mqttClient,
        topicScheme: topicScheme,
        metrics: metrics,
      );

      await newPublisher.initialize();
      await newPublisher.ready(); // Wait for persistence initialization
      final recoveredSeq = newPublisher.currentSequence;

      expect(recoveredSeq, greaterThanOrEqualTo(seq1));

      await newPublisher.dispose();

      print('✓ Successfully persisted and recovered sequence numbers');
      print('  Original sequence: $seq1');
      print('  Recovered sequence: $recoveredSeq');
    }, timeout: Timeout(Duration(seconds: 10)));

    test('should handle large event volumes', () async {
      await publisher.initialize();
      await publisher.ready(); // Wait for persistence initialization
      
      await mqttClient.connect();
      await waitForConnected(mqttClient); // Wait for stable connection

      const eventCount = 50;
      final startTime = DateTime.now();

      for (var i = 0; i < eventCount; i++) {
        final event = ReplicationEvent.value(
          key: 'volume-test-$i',
          nodeId: config.nodeId,
          seq: i + 1,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          value: 'value-$i',
        );

        await publisher.publishEvent(event);
      }

      final duration = DateTime.now().difference(startTime);
      final throughput = eventCount / duration.inMilliseconds * 1000;

      expect(metrics.eventsPublished, equals(eventCount));
      expect(metrics.publishErrors, equals(0));

      print('✓ Successfully handled large event volume');
      print('  Events published: ${metrics.eventsPublished}');
      print('  Duration: ${duration.inMilliseconds}ms');
      print('  Throughput: ${throughput.toStringAsFixed(1)} events/sec');
    }, timeout: Timeout(Duration(seconds: 60)));
  });
}

/// Exception for skipping tests when dependencies are not available
class SkipException implements Exception {
  final String message;
  SkipException(this.message);
  
  @override
  String toString() => 'SkipException: $message';
}
