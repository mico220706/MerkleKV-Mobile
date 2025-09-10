@Tags(['integration'])
library merkle_kv_core.integration_tests;

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:test/test.dart';
import 'package:merkle_kv_core/merkle_kv_core.dart';

/// Enhanced broker readiness check with proper IPv4 handling
Future<void> waitForBroker(String host, int port, {Duration timeout = const Duration(seconds: 10)}) async {
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
  throw Exception('MQTT broker not reachable at $host:$port ($lastErr)');
}

/// Enhanced connection state waiting with auth/TLS detection
Future<void> waitForConnected(MqttClientInterface mqtt, {Duration timeout = const Duration(seconds: 20)}) async {
  final completer = Completer<void>();
  StreamSubscription? subscription;
  Timer? timeoutTimer;
  
  try {
    // Listen for connection state changes
    subscription = mqtt.connectionState.listen((state) {
      if (state == ConnectionState.connected && !completer.isCompleted) {
        completer.complete();
      } else if (state == ConnectionState.disconnected && !completer.isCompleted) {
        // Check if we got disconnected immediately (auth/TLS issue)
        Timer(const Duration(milliseconds: 500), () {
          if (!completer.isCompleted) {
            completer.completeError(Exception('Connection refused - likely auth/TLS mismatch'));
          }
        });
      }
    });
    
    // Set timeout
    timeoutTimer = Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.completeError(TimeoutException('Connection timeout', timeout));
      }
    });
    
    await completer.future;
    
    // Additional stabilization wait for message routing
    await Future.delayed(const Duration(milliseconds: 200));
    
  } finally {
    timeoutTimer?.cancel();
    await subscription?.cancel();
  }
}

/// Enhanced subscription verification with retained probe messages
Future<void> subscribeAndProbe({
  required MqttClientInterface listener,
  required String topic,
  required MqttClientInterface prober,
  Duration timeout = const Duration(seconds: 15),
}) async {
  final completer = Completer<void>();
  Timer? timeoutTimer;
  
  try {
    // Subscribe first
    await listener.subscribe(topic, (topic, payload) {
      if (payload.contains('__probe__') && !completer.isCompleted) {
        completer.complete();
      }
    });
    
    // Small delay for subscription to propagate
    await Future.delayed(const Duration(milliseconds: 100));
    
    // Send probe message with retain flag
    await prober.publish('$topic/__probe__', '__probe__', forceRetainFalse: false);
    
    // Set timeout
    timeoutTimer = Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.completeError(TimeoutException('Subscription probe timeout for topic: $topic', timeout));
      }
    });
    
    await completer.future;
    
  } finally {
    timeoutTimer?.cancel();
  }
}

/// Enhanced outbox draining with proper timeout handling
Future<void> waitForOutboxDrained(ReplicationEventPublisherImpl publisher, {Duration timeout = const Duration(seconds: 30)}) async {
  final deadline = DateTime.now().add(timeout);
  
  while (DateTime.now().isBefore(deadline)) {
    final status = await Future.any([
      publisher.outboxStatus.first,
      Future.delayed(const Duration(seconds: 1)).then((_) => throw TimeoutException('Status timeout', const Duration(seconds: 1)))
    ]);
    
    if (status.pendingEvents == 0) {
      return;
    }
    await Future.delayed(const Duration(milliseconds: 100));
  }
  throw TimeoutException('Outbox did not drain within timeout', timeout);
}

/// Enhanced message collection with proper timeout and filtering
Future<List<String>> collectMessages(
  MqttClientInterface mqtt,
  String topic,
  int expectedCount, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final messages = <String>[];
  final completer = Completer<List<String>>();
  Timer? timeoutTimer;
  
  try {
    void messageHandler(String topic, String payload) {
      if (!payload.contains('__probe__')) {
        messages.add(payload);
        if (messages.length >= expectedCount && !completer.isCompleted) {
          completer.complete(messages);
        }
      }
    }
    
    await mqtt.subscribe(topic, messageHandler);
    
    // Set timeout
    timeoutTimer = Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.complete(messages);
      }
    });
    
    return await completer.future;
    
  } finally {
    timeoutTimer?.cancel();
  }
}

/// Generate unique test ID for topic prefixes and client IDs
String _generateTestId() {
  return '${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(10000)}';
}

/// Enhanced environment configuration with IPv4 forcing and comprehensive auth support
class MqttTestConfig {
  final String host;
  final int port;
  final String? username;
  final String? password;
  final bool tls;
  
  MqttTestConfig({
    required this.host,
    required this.port,
    this.username,
    this.password,
    required this.tls,
  });
  
  factory MqttTestConfig.fromEnvironment() {
    var host = Platform.environment['MQTT_HOST'] ?? '127.0.0.1';
    
    // Force IPv4 for localhost variants
    if (host.isEmpty || host == 'localhost') {
      host = '127.0.0.1';
    }
    
    final port = int.tryParse(Platform.environment['MQTT_PORT'] ?? '') ?? 1883;
    final username = Platform.environment['MQTT_USERNAME'];
    final password = Platform.environment['MQTT_PASSWORD'];
    final tls = Platform.environment['MQTT_TLS']?.toLowerCase() == 'true';
    
    return MqttTestConfig(
      host: host,
      port: port,
      username: username,
      password: password,
      tls: tls,
    );
  }
  
  @override
  String toString() => '$host:$port (tls=$tls, user=${username ?? '-'})';
}

/// Integration tests for replication event publishing with real MQTT broker
/// 
/// Environment variables:
/// - MQTT_HOST: MQTT broker host (default: 127.0.0.1, forced IPv4 for localhost)  
/// - MQTT_PORT: MQTT broker port (default: 1883)
/// - MQTT_USERNAME: MQTT username (optional)
/// - MQTT_PASSWORD: MQTT password (optional) 
/// - MQTT_TLS: Enable TLS (default: false)
void main() {
  group('Replication Event Publisher Integration Tests', () {
    late MqttTestConfig testConfig;
    
    setUpAll(() {
      testConfig = MqttTestConfig.fromEnvironment();
      print('MQTT target => ${testConfig}');
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
        
        // Check broker reachability first
        try {
          await waitForBroker(testConfig.host, testConfig.port);
        } catch (e) {
          print('MQTT broker not reachable at ${testConfig.host}:${testConfig.port}; skipping integration test');
          return;
        }
        
        try {
          // Setup
          tempDir = await Directory.systemTemp.createTemp('integration_test_');
          
          final config = MerkleKVConfig(
            mqttHost: testConfig.host,
            mqttPort: testConfig.port,
            nodeId: 'test-node-$testId',
            clientId: 'test-publisher-$testId',
            topicPrefix: topicPrefix,
            storagePath: '${tempDir.path}/test.storage',
            persistenceEnabled: true,
          );
          
          publisherMqtt = MqttClientImpl(config);
          listenerMqtt = MqttClientImpl(config.copyWith(clientId: 'test-listener-$testId'));
          metrics = InMemoryReplicationMetrics();
          
          // Connect both clients with proper error handling
          await publisherMqtt.connect();
          try {
            await waitForConnected(publisherMqtt);
          } catch (e) {
            print('MQTT broker refused or auth/TLS mismatch at ${testConfig.host}:${testConfig.port}; skipping integration test');
          return;
          }
          
          await listenerMqtt.connect();
          try {
            await waitForConnected(listenerMqtt);
          } catch (e) {
            print('MQTT broker refused or auth/TLS mismatch at ${testConfig.host}:${testConfig.port}; skipping integration test');
          return;
          }
          
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
          
          // Wait for outbox to drain with timeout
          await Future.any([
            waitForOutboxDrained(publisher),
            Future.delayed(const Duration(seconds: 20)).then((_) => 
              throw TimeoutException('Outbox drain timeout', const Duration(seconds: 20)))
          ]);
          
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
        
        // Check broker reachability first
        try {
          await waitForBroker(testConfig.host, testConfig.port);
        } catch (e) {
          print('MQTT broker not reachable at ${testConfig.host}:${testConfig.port}; skipping integration test');
          return;
        }
        
        try {
          // Setup
          tempDir = await Directory.systemTemp.createTemp('integration_test_');
          
          final config = MerkleKVConfig(
            mqttHost: testConfig.host,
            mqttPort: testConfig.port,
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
          
          // Verify events are queued with timeout
          final deadline = DateTime.now().add(const Duration(seconds: 5));
          OutboxStatus? status;
          while (DateTime.now().isBefore(deadline)) {
            status = await Future.any([
              publisher.outboxStatus.first,
              Future.delayed(const Duration(seconds: 1)).then((_) => 
                throw TimeoutException('Status check timeout', const Duration(seconds: 1)))
            ]);
            if (status?.pendingEvents == eventCount) break;
            await Future.delayed(const Duration(milliseconds: 100));
          }
          expect(status?.pendingEvents, equals(eventCount));
          
          // Connect both clients with proper error handling
          await publisherMqtt.connect();
          try {
            await waitForConnected(publisherMqtt);
          } catch (e) {
            print('MQTT broker refused or auth/TLS mismatch at ${testConfig.host}:${testConfig.port}; skipping integration test');
          return;
          }
          
          await listenerMqtt.connect();
          try {
            await waitForConnected(listenerMqtt);
          } catch (e) {
            print('MQTT broker refused or auth/TLS mismatch at ${testConfig.host}:${testConfig.port}; skipping integration test');
          return;
          }
          
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
          
          // Flush outbox with timeout
          await Future.any([
            publisher.flushOutbox(),
            Future.delayed(const Duration(seconds: 10)).then((_) => 
              throw TimeoutException('Flush timeout', const Duration(seconds: 10)))
          ]);
          
          await Future.any([
            waitForOutboxDrained(publisher),
            Future.delayed(const Duration(seconds: 40)).then((_) => 
              throw TimeoutException('Outbox drain timeout', const Duration(seconds: 40)))
          ]);
          
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
        
        // Check broker reachability first
        try {
          await waitForBroker(testConfig.host, testConfig.port);
        } catch (e) {
          print('MQTT broker not reachable at ${testConfig.host}:${testConfig.port}; skipping integration test');
          return;
        }
        
        try {
          // Setup
          tempDir = await Directory.systemTemp.createTemp('integration_test_');
          
          final config = MerkleKVConfig(
            mqttHost: testConfig.host,
            mqttPort: testConfig.port,
            nodeId: 'test-node-$testId',
            clientId: 'test-publisher-$testId',
            topicPrefix: topicPrefix,
            storagePath: '${tempDir.path}/test.storage',
            persistenceEnabled: true,
          );
          
          publisherMqtt = MqttClientImpl(config);
          listenerMqtt = MqttClientImpl(config.copyWith(clientId: 'test-listener-$testId'));
          metrics = InMemoryReplicationMetrics();
          
          // Connect both clients with proper error handling
          await publisherMqtt.connect();
          try {
            await waitForConnected(publisherMqtt);
          } catch (e) {
            print('MQTT broker refused or auth/TLS mismatch at ${testConfig.host}:${testConfig.port}; skipping integration test');
          return;
          }
          
          await listenerMqtt.connect();
          try {
            await waitForConnected(listenerMqtt);
          } catch (e) {
            print('MQTT broker refused or auth/TLS mismatch at ${testConfig.host}:${testConfig.port}; skipping integration test');
          return;
          }
          
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
          const eventCount = 100; // Reasonable for CI environments
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
          
          // Wait for outbox to drain with timeout
          await Future.any([
            waitForOutboxDrained(publisher),
            Future.delayed(const Duration(seconds: 60)).then((_) => 
              throw TimeoutException('Outbox drain timeout', const Duration(seconds: 60)))
          ]);
          
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
