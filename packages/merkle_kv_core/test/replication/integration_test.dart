import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:test/test.dart';
import 'package:merkle_kv_core/merkle_kv_core.dart';

/// A. Ensure broker is reachable (CI/local)
Future<void> waitForBroker(String host, int port, {Duration timeout = const Duration(seconds: 30)}) async {
  final deadline = DateTime.now().add(timeout);
  Object? lastErr;
  
  while (DateTime.now().isBefore(deadline)) {
    try {
      final sock = await Socket.connect(host, port, timeout: const Duration(seconds: 2));
      await sock.close();
      return;
    } catch (e) { 
      lastErr = e; 
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  throw TimeoutException('MQTT broker not reachable at $host:$port ($lastErr)', timeout);
}

/// B. Wait for adapter to report connected
Future<void> waitForConnected(MqttClientInterface mqtt, {Duration timeout = const Duration(seconds: 20)}) async {
  final deadline = DateTime.now().add(timeout);
  
  while (DateTime.now().isBefore(deadline)) {
    final state = mqtt.connectionState;
    if (state == ConnectionState.connected) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw TimeoutException('MQTT client did not connect within timeout', timeout);
}

/// C. Subscription + probe message (retained message test)
Future<void> subscribeAndProbe({
  required MqttClientInterface listener,
  required String topic,
  required MqttClientInterface prober,
  Duration timeout = const Duration(seconds: 15),
}) async {
  bool subscribed = false;
  
  // Subscribe first
  await listener.subscribe(topic, (topic, payload) {
    if (payload.contains('__probe__')) {
      subscribed = true;
    }
  });
  
  // Small delay for subscription to propagate
  await Future<void>.delayed(const Duration(milliseconds: 100));
  
  // Send probe message
  await prober.publish('$topic/__probe__', '__probe__', forceRetainFalse: false);
  
  // Wait for probe to be received
  final deadline = DateTime.now().add(timeout);
  while (!subscribed && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  
  if (!subscribed) {
    throw TimeoutException('Subscription probe failed for topic: $topic', timeout);
  }
}

/// D. Wait for outbox to drain
Future<void> waitForOutboxDrained(ReplicationEventPublisherImpl publisher, {Duration timeout = const Duration(seconds: 30)}) async {
  final deadline = DateTime.now().add(timeout);
  
  while (DateTime.now().isBefore(deadline)) {
    final status = await publisher.outboxStatus.first;
    if (status.pendingEvents == 0) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw TimeoutException('Outbox did not drain within timeout', timeout);
}

/// E. Collect messages with timeout
Future<List<String>> collectMessages(
  MqttClientInterface mqtt,
  String topic,
  int expectedCount, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final messages = <String>[];
  final completer = Completer<List<String>>();
  
  void messageHandler(String topic, String payload) {
    if (!payload.contains('__probe__')) {
      messages.add(payload);
      if (messages.length >= expectedCount) {
        completer.complete(messages);
      }
    }
  }
  
  await mqtt.subscribe(topic, messageHandler);
  
  // Set timeout
  Timer(timeout, () {
    if (!completer.isCompleted) {
      completer.complete(messages);
    }
  });
  
  return completer.future;
}

/// Generate unique test ID for topic prefixes
String _generateTestId() {
  return '${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(10000)}';
}

/// Integration tests for replication event publishing with real MQTT broker
/// 
/// Environment variables:
/// - MQTT_HOST: MQTT broker host (default: 127.0.0.1)
/// - MQTT_PORT: MQTT broker port (default: 1883)
void main() {
  group('Replication Event Publisher Integration Tests', () {
    late String mqttHost;
    late int mqttPort;
    
    setUpAll(() {
      mqttHost = Platform.environment['MQTT_HOST'] ?? '127.0.0.1';
      mqttPort = int.tryParse(Platform.environment['MQTT_PORT'] ?? '') ?? 1883;
      
      // Try to connect to broker, skip all tests if not available
      return () async {
        try {
          await waitForBroker(mqttHost, mqttPort, timeout: const Duration(seconds: 10));
        } catch (_) {
          print('MQTT broker not reachable at $mqttHost:$mqttPort; skipping integration tests.');
          // Rethrow to fail setUpAll and skip the group
          rethrow;
        }
      }();
    });

    group('should publish events to real MQTT broker', () {
      test('single event publication', () async {
        final testId = _generateTestId();
        final topicPrefix = 'test/$testId';
        late Directory tempDir;
        late MqttClientInterface publisherMqtt;
        late MqttClientInterface listenerMqtt;
        late ReplicationEventPublisherImpl publisher;
        late InMemoryReplicationMetrics metrics;
        
        try {
          // Setup
          tempDir = await Directory.systemTemp.createTemp('integration_test_');
          
          final config = MerkleKVConfig(
            mqttHost: mqttHost,
            mqttPort: mqttPort,
            nodeId: 'test-node-$testId',
            clientId: 'test-publisher-$testId',
            topicPrefix: topicPrefix,
            storagePath: '${tempDir.path}/test.storage',
            persistenceEnabled: true,
          );
          
          publisherMqtt = MqttClientImpl(config);
          listenerMqtt = MqttClientImpl(config.copyWith(clientId: 'test-listener-$testId'));
          metrics = InMemoryReplicationMetrics();
          
          // Connect both clients
          await publisherMqtt.connect();
          await waitForConnected(publisherMqtt);
          
          await listenerMqtt.connect();
          await waitForConnected(listenerMqtt);
          
          // Set up subscription and probe
          final replicationTopic = '$topicPrefix/replication/events';
          await subscribeAndProbe(
            listener: listenerMqtt, 
            topic: replicationTopic, 
            prober: publisherMqtt
          );
          
          // Create publisher
          final topicScheme = TopicScheme.create(config.topicPrefix, config.clientId);
          publisher = ReplicationEventPublisherImpl(
            config: config,
            mqttClient: publisherMqtt,
            topicScheme: topicScheme,
            metrics: metrics,
          );
          
          await publisher.initialize();
          await publisher.ready();
          
          // Collect incoming messages
          final receivedMessages = <String>[];
          void messageHandler(String topic, String payload) {
            if (topic.contains('/replication/events') && !topic.contains('__probe__')) {
              receivedMessages.add(payload);
            }
          }
          
          await listenerMqtt.subscribe(replicationTopic, messageHandler);
          
          // Publish test events
          const eventCount = 3;
          for (int i = 0; i < eventCount; i++) {
            final event = ReplicationEvent.value(
              key: 'test-key-$i',
              nodeId: config.nodeId,
              seq: i + 1,
              timestampMs: DateTime.now().millisecondsSinceEpoch,
              value: 'test-value-$i',
            );
            
            await publisher.publishEvent(event);
          }
          
          // Wait for outbox to drain
          await waitForOutboxDrained(publisher);
          
          // Give some time for messages to arrive
          await Future.delayed(const Duration(milliseconds: 500));
          
          // Verify results
          expect(receivedMessages.length, equals(eventCount));
          expect(metrics.eventsPublished, equals(eventCount));
          expect(metrics.publishErrors, equals(0));
          
          print('✓ Successfully published $eventCount events to real MQTT broker');
          print('  Topic prefix: $topicPrefix');
          print('  Received messages: ${receivedMessages.length}');
          
        } finally {
          // Cleanup
          try { await publisher.dispose(); } catch (_) {}
          try { await listenerMqtt.disconnect(); } catch (_) {}
          try { await publisherMqtt.disconnect(); } catch (_) {}
          try { await tempDir.delete(recursive: true); } catch (_) {}
        }
      }, timeout: const Timeout(Duration(seconds: 40)));
    });

    group('offline queuing and reconnection', () {
      test('queue events while offline then publish on reconnect', () async {
        final testId = _generateTestId();
        final topicPrefix = 'test/$testId';
        late Directory tempDir;
        late MqttClientInterface publisherMqtt;
        late MqttClientInterface listenerMqtt;
        late ReplicationEventPublisherImpl publisher;
        late InMemoryReplicationMetrics metrics;
        
        try {
          // Setup
          tempDir = await Directory.systemTemp.createTemp('integration_test_');
          
          final config = MerkleKVConfig(
            mqttHost: mqttHost,
            mqttPort: mqttPort,
            nodeId: 'test-node-$testId',
            clientId: 'test-publisher-$testId',
            topicPrefix: topicPrefix,
            storagePath: '${tempDir.path}/test.storage',
            persistenceEnabled: true,
          );
          
          publisherMqtt = MqttClientImpl(config);
          listenerMqtt = MqttClientImpl(config.copyWith(clientId: 'test-listener-$testId'));
          metrics = InMemoryReplicationMetrics();
          
          // Create publisher (start disconnected)
          final topicScheme = TopicScheme.create(config.topicPrefix, config.clientId);
          publisher = ReplicationEventPublisherImpl(
            config: config,
            mqttClient: publisherMqtt,
            topicScheme: topicScheme,
            metrics: metrics,
          );
          
          await publisher.initialize();
          await publisher.ready();
          
          // Emit events while offline
          const eventCount = 5;
          for (int i = 0; i < eventCount; i++) {
            final event = ReplicationEvent.value(
              key: 'offline-key-$i',
              nodeId: config.nodeId,
              seq: i + 1,
              timestampMs: DateTime.now().millisecondsSinceEpoch,
              value: 'offline-value-$i',
            );
            
            await publisher.publishEvent(event);
          }
          
          // Verify events are queued
          final status = await publisher.outboxStatus.first;
          expect(status.pendingEvents, equals(eventCount));
          
          // Connect both clients
          await publisherMqtt.connect();
          await waitForConnected(publisherMqtt);
          
          await listenerMqtt.connect();
          await waitForConnected(listenerMqtt);
          
          // Set up subscription
          final replicationTopic = '$topicPrefix/replication/events';
          await subscribeAndProbe(
            listener: listenerMqtt, 
            topic: replicationTopic, 
            prober: publisherMqtt
          );
          
          // Collect incoming messages
          final receivedMessages = <String>[];
          void messageHandler(String topic, String payload) {
            if (topic.contains('/replication/events') && !topic.contains('__probe__')) {
              receivedMessages.add(payload);
            }
          }
          
          await listenerMqtt.subscribe(replicationTopic, messageHandler);
          
          // Flush outbox
          await publisher.flushOutbox();
          await waitForOutboxDrained(publisher);
          
          // Give time for messages to arrive
          await Future.delayed(const Duration(milliseconds: 500));
          
          // Verify results
          expect(receivedMessages.length, equals(eventCount));
          expect(metrics.eventsPublished, equals(eventCount));
          
          print('✓ Successfully handled offline queuing and reconnection');
          print('  Events queued: $eventCount');
          print('  Events received: ${receivedMessages.length}');
          
        } finally {
          // Cleanup
          try { await publisher.dispose(); } catch (_) {}
          try { await listenerMqtt.disconnect(); } catch (_) {}
          try { await publisherMqtt.disconnect(); } catch (_) {}
          try { await tempDir.delete(recursive: true); } catch (_) {}
        }
      }, timeout: const Timeout(Duration(seconds: 60)));
    });

    group('large event volumes', () {
      test('publish and receive many events', () async {
        final testId = _generateTestId();
        final topicPrefix = 'test/$testId';
        late Directory tempDir;
        late MqttClientInterface publisherMqtt;
        late MqttClientInterface listenerMqtt;
        late ReplicationEventPublisherImpl publisher;
        late InMemoryReplicationMetrics metrics;
        
        try {
          // Setup
          tempDir = await Directory.systemTemp.createTemp('integration_test_');
          
          final config = MerkleKVConfig(
            mqttHost: mqttHost,
            mqttPort: mqttPort,
            nodeId: 'test-node-$testId',
            clientId: 'test-publisher-$testId',
            topicPrefix: topicPrefix,
            storagePath: '${tempDir.path}/test.storage',
            persistenceEnabled: true,
          );
          
          publisherMqtt = MqttClientImpl(config);
          listenerMqtt = MqttClientImpl(config.copyWith(clientId: 'test-listener-$testId'));
          metrics = InMemoryReplicationMetrics();
          
          // Connect both clients
          await publisherMqtt.connect();
          await waitForConnected(publisherMqtt);
          
          await listenerMqtt.connect();
          await waitForConnected(listenerMqtt);
          
          // Set up subscription
          final replicationTopic = '$topicPrefix/replication/events';
          await subscribeAndProbe(
            listener: listenerMqtt, 
            topic: replicationTopic, 
            prober: publisherMqtt
          );
          
          // Create publisher
          final topicScheme = TopicScheme.create(config.topicPrefix, config.clientId);
          publisher = ReplicationEventPublisherImpl(
            config: config,
            mqttClient: publisherMqtt,
            topicScheme: topicScheme,
            metrics: metrics,
          );
          
          await publisher.initialize();
          await publisher.ready();
          
          // Collect incoming messages
          final receivedMessages = <String>[];
          void messageHandler(String topic, String payload) {
            if (topic.contains('/replication/events') && !topic.contains('__probe__')) {
              receivedMessages.add(payload);
            }
          }
          
          await listenerMqtt.subscribe(replicationTopic, messageHandler);
          
          // Publish many events with yielding
          const eventCount = 100; // Reduced for faster test execution
          final startTime = DateTime.now();
          
          for (int i = 0; i < eventCount; i++) {
            final event = ReplicationEvent.value(
              key: 'volume-key-$i',
              nodeId: config.nodeId,
              seq: i + 1,
              timestampMs: DateTime.now().millisecondsSinceEpoch,
              value: 'volume-value-$i',
            );
            
            await publisher.publishEvent(event);
            
            // Yield every 20 events
            if (i % 20 == 0) {
              await Future<void>.delayed(const Duration(milliseconds: 1));
            }
          }
          
          // Wait for outbox to drain
          await waitForOutboxDrained(publisher);
          
          // Give extra time for all messages to arrive
          await Future.delayed(const Duration(seconds: 2));
          
          final duration = DateTime.now().difference(startTime);
          final throughput = eventCount / duration.inMilliseconds * 1000;
          
          // Verify results
          expect(metrics.eventsPublished, equals(eventCount));
          expect(metrics.publishErrors, equals(0));
          expect(receivedMessages.length, equals(eventCount));
          
          print('✓ Successfully handled large event volume');
          print('  Events published: ${metrics.eventsPublished}');
          print('  Events received: ${receivedMessages.length}');
          print('  Duration: ${duration.inMilliseconds}ms');
          print('  Throughput: ${throughput.toStringAsFixed(1)} events/sec');
          
        } finally {
          // Cleanup
          try { await publisher.dispose(); } catch (_) {}
          try { await listenerMqtt.disconnect(); } catch (_) {}
          try { await publisherMqtt.disconnect(); } catch (_) {}
          try { await tempDir.delete(recursive: true); } catch (_) {}
        }
      }, timeout: const Timeout(Duration(minutes: 2)));
    });
  });
}
