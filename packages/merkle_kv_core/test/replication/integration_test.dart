@Tags(['integration'])
library merkle_kv_core.integration_tests;

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:test/test.dart';
import 'package:merkle_kv_core/merkle_kv_core.dart';

typedef AsyncBody = Future<void> Function();

class ItAssumptions {
  final String host;
  final int port;
  final bool reachable;
  final bool connectable; // broker accepts CONNECT/auth/tls
  final String reasonIfSkip;
  
  ItAssumptions({
    required this.host,
    required this.port,
    required this.reachable,
    required this.connectable,
    required this.reasonIfSkip,
  });
}

Future<ItAssumptions> computeItAssumptions() async {
  final cfg = MqttTestConfig.fromEnv();
  final host = (cfg.host.isEmpty || cfg.host == 'localhost') ? '127.0.0.1' : cfg.host;
  final port = cfg.port;

  // 1) Reachability (TCP)
  final reachable = await _tryReach(host, port, const Duration(seconds: 5));

  if (!reachable) {
    return ItAssumptions(
      host: host,
      port: port,
      reachable: false,
      connectable: false,
      reasonIfSkip: 'MQTT broker not reachable at $host:$port',
    );
  }

  // 2) Connectability (MQTT CONNECT/CONNACK success with current auth/TLS)
  final ok = await _tryConnectOnce(host, port, cfg, const Duration(seconds: 8));
  return ItAssumptions(
    host: host,
    port: port,
    reachable: true,
    connectable: ok,
    reasonIfSkip: ok
        ? ''
        : 'MQTT broker refused or auth/TLS mismatch at $host:$port (skipping integration tests)',
  );
}

Future<bool> _tryReach(String host, int port, Duration timeout) async {
  try {
    final s = await Socket.connect(host, port, timeout: timeout);
    await s.close();
    return true;
  } catch (_) {
    return false;
  }
}

Future<bool> _tryConnectOnce(String host, int port, MqttTestConfig cfg, Duration timeout) async {
  final client = MqttClientImpl(
    MerkleKVConfig(
      mqttHost: host,
      mqttPort: port,
      username: cfg.username,
      password: cfg.password,
      mqttUseTls: cfg.tls,
      nodeId: 'probe-node',
      clientId: 'it-probe-${DateTime.now().millisecondsSinceEpoch}',
      topicPrefix: 'probe',
      storagePath: '',
      persistenceEnabled: false,
    ),
  );
  try {
    unawaited(client.connect());
    await waitForConnected(client, timeout: timeout);
    return true;
  } catch (_) {
    return false;
  } finally {
    try { await client.disconnect(); } catch (_) {}
  }
}

// At top of integration_test.dart (replace previous globals)
Future<ItAssumptions>? _assumptionsFuture;

Future<ItAssumptions> _getAssumptions() {
  _assumptionsFuture ??= computeItAssumptions();
  return _assumptionsFuture!;
}

// New guardedTest that computes assumptions at runtime (no top-level access)
void guardedTest(
  String name,
  Future<void> Function(ItAssumptions a) body, {
  Duration? timeout,
}) {
  test(
    name,
    () async {
      final a = await _getAssumptions();
      final require = Platform.environment['IT_REQUIRE_BROKER'] == '1';

      // If broker not usable: either fail early (when required) or return early (runtime skip)
      if (!a.reachable || !a.connectable) {
        if (require) {
          fail('Broker required for integration tests: ${a.reasonIfSkip}');
        }
        // Runtime skip: do not fail, do not hang
        // (We intentionally avoid `skip:` param to keep registration-time pure.)
        // Optionally log:
        // print('SKIP[integration]: ${a.reasonIfSkip}');
        return;
      }

      await body(a);
    },
    timeout: timeout != null ? Timeout(timeout) : null,
  );
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
  
  factory MqttTestConfig.fromEnv() {
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
    guardedTest('single event publication', (it) async {
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
          mqttHost: it.host,
          mqttPort: it.port,
          nodeId: 'test-node-$testId',
          clientId: 'test-publisher-$testId',
          topicPrefix: topicPrefix,
          storagePath: '${tempDir.path}/test.storage',
          persistenceEnabled: true,
        );
        
        publisherMqtt = MqttClientImpl(config);
        listenerMqtt = MqttClientImpl(config.copyWith(clientId: 'test-listener-$testId'));
        metrics = InMemoryReplicationMetrics();
        
        // Connect both clients with timeout
        await publisherMqtt.connect();
        await waitForConnected(publisherMqtt, timeout: const Duration(seconds: 20));
        
        await listenerMqtt.connect();
        await waitForConnected(listenerMqtt, timeout: const Duration(seconds: 20));
        
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
    });

    guardedTest('queue events while offline then publish on reconnect', (it) async {
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
          mqttHost: it.host,
          mqttPort: it.port,
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
        
        // Connect both clients with timeout
        await publisherMqtt.connect();
        await waitForConnected(publisherMqtt, timeout: const Duration(seconds: 20));
        
        await listenerMqtt.connect();
        await waitForConnected(listenerMqtt, timeout: const Duration(seconds: 20));
        
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
    });

    guardedTest('publish and receive many events', (it) async {
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
          mqttHost: it.host,
          mqttPort: it.port,
          nodeId: 'test-node-$testId',
          clientId: 'test-publisher-$testId',
          topicPrefix: topicPrefix,
          storagePath: '${tempDir.path}/test.storage',
          persistenceEnabled: true,
        );
        
        publisherMqtt = MqttClientImpl(config);
        listenerMqtt = MqttClientImpl(config.copyWith(clientId: 'test-listener-$testId'));
        metrics = InMemoryReplicationMetrics();
        
        // Connect both clients with timeout
        await publisherMqtt.connect();
        await waitForConnected(publisherMqtt, timeout: const Duration(seconds: 20));
        
        await listenerMqtt.connect();
        await waitForConnected(listenerMqtt, timeout: const Duration(seconds: 20));
        
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
        
        // Publish many events with batching and yielding
        const eventCount = 100;
        final startTime = DateTime.now();
        
        for (int batch = 0; batch < eventCount ~/ 10; batch++) {
          for (int i = 0; i < 10; i++) {
            final eventIndex = batch * 10 + i;
            final event = ReplicationEvent.value(
              key: 'bulk-key-$eventIndex',
              nodeId: config.nodeId,
              seq: eventIndex + 1,
              timestampMs: DateTime.now().millisecondsSinceEpoch,
              value: 'bulk-value-$eventIndex',
            );
            
            await publisher.publishEvent(event);
          }
          
          // Yield to event loop every batch
          await Future.delayed(Duration.zero);
          
          // Wait for partial drain periodically
          if (batch % 3 == 0) {
            await Future.any([
              waitForOutboxDrained(publisher, timeout: const Duration(seconds: 5)),
              Future.delayed(const Duration(seconds: 5))
            ]);
          }
        }
        
        // Final drain with generous timeout
        await Future.any([
          waitForOutboxDrained(publisher),
          Future.delayed(const Duration(seconds: 60)).then((_) => 
            throw TimeoutException('Final outbox drain timeout', const Duration(seconds: 60)))
        ]);
        
        // Wait for message collection to complete
        await collectMessages(listenerMqtt, replicationTopic, eventCount, 
            timeout: const Duration(seconds: 40));
        
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
    });

    tearDownAll(() async {
      // Ensure cleanup never throws
    });
  });
}
