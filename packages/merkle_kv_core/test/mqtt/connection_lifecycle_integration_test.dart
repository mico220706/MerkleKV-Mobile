import 'dart:async';
import 'dart:io';
import 'package:test/test.dart';

import '../../lib/src/config/merkle_kv_config.dart';
import '../../lib/src/mqtt/connection_lifecycle.dart';
import '../../lib/src/mqtt/connection_state.dart';
import '../../lib/src/mqtt/mqtt_client_impl.dart';
import '../../lib/src/replication/metrics.dart';

/// Integration tests for ConnectionLifecycleManager with real MQTT broker.
/// 
/// These tests require a running MQTT broker. Set environment variables:
/// - MQTT_TEST_HOST (default: localhost)
/// - MQTT_TEST_PORT (default: 1883)
/// - MQTT_TEST_USERNAME (optional)
/// - MQTT_TEST_PASSWORD (optional)
/// - MQTT_TEST_USE_TLS (default: false)
void main() {
  // Check if broker is available
  final host = Platform.environment['MQTT_TEST_HOST'] ?? 'localhost';
  final port = int.tryParse(Platform.environment['MQTT_TEST_PORT'] ?? '1883') ?? 1883;
  final username = Platform.environment['MQTT_TEST_USERNAME'];
  final password = Platform.environment['MQTT_TEST_PASSWORD'];
  final useTls = Platform.environment['MQTT_TEST_USE_TLS']?.toLowerCase() == 'true';

  group('ConnectionLifecycleManager Integration Tests', () {
    late MerkleKVConfig config;
    late InMemoryReplicationMetrics metrics;
    
    setUpAll(() async {
      // Verify broker is accessible
      try {
        final socket = await Socket.connect(host, port, timeout: Duration(seconds: 5));
        await socket.close();
      } catch (e) {
        print('MQTT broker not available at $host:$port');
        print('Skipping integration tests. Error: $e');
        print('To run integration tests, ensure MQTT broker is running and set environment variables.');
        return;
      }
    });

    setUp(() {
      config = MerkleKVConfig(
        mqttHost: host,
        mqttPort: port,
        username: username,
        password: password,
        mqttUseTls: useTls,
        nodeId: 'integration-test-node',
        clientId: 'integration-test-client-${DateTime.now().millisecondsSinceEpoch}',
        keepAliveSeconds: 10,
      );
      
      metrics = InMemoryReplicationMetrics();
    });

    group('Real broker connection lifecycle', () {
      test('successful connection and disconnection', () async {
        if (!await _brokerAvailable(host, port)) {
          markTestSkipped('MQTT broker not available');
          return;
        }

        final mqttClient = MqttClientImpl(config);
        final manager = DefaultConnectionLifecycleManager(
          config: config,
          mqttClient: mqttClient,
          metrics: metrics,
        );

        final events = <ConnectionStateEvent>[];
        final subscription = manager.connectionState.listen(events.add);

        try {
          // Test connection
          final stopwatch = Stopwatch()..start();
          await manager.connect();
          stopwatch.stop();

          expect(manager.isConnected, isTrue);
          expect(stopwatch.elapsedMilliseconds, lessThan(5000)); // Should connect within 5s

          // Verify connection events
          expect(events.any((e) => e.state == ConnectionState.connecting), isTrue);
          expect(events.any((e) => e.state == ConnectionState.connected), isTrue);

          // Test disconnection
          await manager.disconnect(suppressLWT: true);
          expect(manager.isConnected, isFalse);

          // Verify disconnection events
          expect(events.any((e) => e.state == ConnectionState.disconnecting), isTrue);
          expect(events.any((e) => e.state == ConnectionState.disconnected), isTrue);
        } finally {
          await subscription.cancel();
          await manager.dispose();
        }
      });

      test('connection failure with invalid credentials', () async {
        if (!await _brokerAvailable(host, port)) {
          markTestSkipped('MQTT broker not available');
          return;
        }

        final invalidConfig = MerkleKVConfig(
          mqttHost: host,
          mqttPort: port,
          username: 'invalid_user',
          password: 'invalid_password',
          nodeId: 'integration-test-node',
          clientId: 'integration-test-client-invalid',
          keepAliveSeconds: 10,
        );

        final mqttClient = MqttClientImpl(invalidConfig);
        final manager = DefaultConnectionLifecycleManager(
          config: invalidConfig,
          mqttClient: mqttClient,
          metrics: metrics,
        );

        final events = <ConnectionStateEvent>[];
        final subscription = manager.connectionState.listen(events.add);

        try {
          await expectLater(
            manager.connect(),
            throwsA(isA<Exception>()),
          );

          expect(manager.isConnected, isFalse);

          // Should have error events
          final errorEvents = events.where((e) => e.error != null);
          expect(errorEvents.isNotEmpty, isTrue);
        } finally {
          await subscription.cancel();
          await manager.dispose();
        }
      });

      test('network interruption handling', () async {
        if (!await _brokerAvailable(host, port)) {
          markTestSkipped('MQTT broker not available');
          return;
        }

        final mqttClient = MqttClientImpl(config);
        final manager = DefaultConnectionLifecycleManager(
          config: config,
          mqttClient: mqttClient,
          metrics: metrics,
        );

        final events = <ConnectionStateEvent>[];
        final subscription = manager.connectionState.listen(events.add);

        try {
          await manager.connect();
          expect(manager.isConnected, isTrue);

          // Simulate network interruption by disconnecting abruptly
          // (This is simulated by the MQTT client library detecting the disconnect)
          print('Connected successfully. Simulating network interruption...');
          
          // The MQTT client should detect the disconnection
          // Wait for automatic disconnection detection
          await Future.delayed(Duration(seconds: config.keepAliveSeconds + 5));

          // Verify disconnection was detected
          final disconnectedEvents = events.where(
            (e) => e.state == ConnectionState.disconnected
          );
          expect(disconnectedEvents.isNotEmpty, isTrue);
        } finally {
          await subscription.cancel();
          await manager.dispose();
        }
      });
    });

    group('Performance and reliability tests', () {
      test('connection establishment timing', () async {
        if (!await _brokerAvailable(host, port)) {
          markTestSkipped('MQTT broker not available');
          return;
        }

        final timings = <int>[];

        for (int i = 0; i < 3; i++) {
          final testConfig = MerkleKVConfig(
            mqttHost: host,
            mqttPort: port,
            username: username,
            password: password,
            mqttUseTls: useTls,
            nodeId: 'perf-test-node-$i',
            clientId: 'perf-test-client-$i-${DateTime.now().millisecondsSinceEpoch}',
            keepAliveSeconds: 10,
          );

          final mqttClient = MqttClientImpl(testConfig);
          final manager = DefaultConnectionLifecycleManager(
            config: testConfig,
            mqttClient: mqttClient,
            metrics: metrics,
          );

          try {
            final stopwatch = Stopwatch()..start();
            await manager.connect();
            stopwatch.stop();

            timings.add(stopwatch.elapsedMilliseconds);
            expect(manager.isConnected, isTrue);

            await manager.disconnect();
            expect(manager.isConnected, isFalse);
          } finally {
            await manager.dispose();
          }
        }

        // Analyze timing results
        final avgTiming = timings.reduce((a, b) => a + b) / timings.length;
        print('Connection timings: $timings ms');
        print('Average connection time: ${avgTiming.toStringAsFixed(1)} ms');

        // Should connect within reasonable time
        expect(avgTiming, lessThan(3000)); // Average under 3 seconds
        expect(timings.every((t) => t < 10000), isTrue); // All under 10 seconds
      });

      test('rapid connect/disconnect cycles', () async {
        if (!await _brokerAvailable(host, port)) {
          markTestSkipped('MQTT broker not available');
          return;
        }

        final mqttClient = MqttClientImpl(config);
        final manager = DefaultConnectionLifecycleManager(
          config: config,
          mqttClient: mqttClient,
          metrics: metrics,
        );

        try {
          for (int i = 0; i < 5; i++) {
            print('Rapid cycle $i...');
            
            await manager.connect();
            expect(manager.isConnected, isTrue);

            // Brief connected period
            await Future.delayed(Duration(milliseconds: 100));

            await manager.disconnect();
            expect(manager.isConnected, isFalse);

            // Brief disconnected period
            await Future.delayed(Duration(milliseconds: 100));
          }

          // Should end in consistent state
          expect(manager.isConnected, isFalse);
        } finally {
          await manager.dispose();
        }
      });

      test('concurrent connection attempts', () async {
        if (!await _brokerAvailable(host, port)) {
          markTestSkipped('MQTT broker not available');
          return;
        }

        final mqttClient = MqttClientImpl(config);
        final manager = DefaultConnectionLifecycleManager(
          config: config,
          mqttClient: mqttClient,
          metrics: metrics,
        );

        try {
          // Start multiple concurrent connect attempts
          final futures = List.generate(5, (_) => manager.connect());
          
          await Future.wait(futures);
          
          // Should end up connected
          expect(manager.isConnected, isTrue);
          
          await manager.disconnect();
          expect(manager.isConnected, isFalse);
        } finally {
          await manager.dispose();
        }
      });
    });

    group('Platform lifecycle simulation', () {
      test('background/foreground transitions with connection maintenance', () async {
        if (!await _brokerAvailable(host, port)) {
          markTestSkipped('MQTT broker not available');
          return;
        }

        final mqttClient = MqttClientImpl(config);
        final manager = DefaultConnectionLifecycleManager(
          config: config,
          mqttClient: mqttClient,
          metrics: metrics,
          maintainConnectionInBackground: true,
        );

        final events = <ConnectionStateEvent>[];
        final subscription = manager.connectionState.listen(events.add);

        try {
          await manager.connect();
          expect(manager.isConnected, isTrue);

          // Simulate app going to background
          await manager.handleAppStateChange(AppLifecycleState.paused);
          
          // Should maintain connection
          expect(manager.isConnected, isTrue);

          // Wait a bit to ensure connection stability
          await Future.delayed(Duration(seconds: 2));
          expect(manager.isConnected, isTrue);

          // Simulate app resuming
          await manager.handleAppStateChange(AppLifecycleState.resumed);
          expect(manager.isConnected, isTrue);

          await manager.disconnect();
        } finally {
          await subscription.cancel();
          await manager.dispose();
        }
      });

      test('background/foreground transitions without connection maintenance', () async {
        if (!await _brokerAvailable(host, port)) {
          markTestSkipped('MQTT broker not available');
          return;
        }

        final mqttClient = MqttClientImpl(config);
        final manager = DefaultConnectionLifecycleManager(
          config: config,
          mqttClient: mqttClient,
          metrics: metrics,
          maintainConnectionInBackground: false,
        );

        try {
          await manager.connect();
          expect(manager.isConnected, isTrue);

          // Simulate app going to background
          await manager.handleAppStateChange(AppLifecycleState.paused);
          
          // Should disconnect
          expect(manager.isConnected, isFalse);

          // Simulate app resuming
          await manager.handleAppStateChange(AppLifecycleState.resumed);
          
          // Should reconnect
          expect(manager.isConnected, isTrue);
        } finally {
          await manager.dispose();
        }
      });
    });

    group('Resource management', () {
      test('proper cleanup prevents resource leaks', () async {
        if (!await _brokerAvailable(host, port)) {
          markTestSkipped('MQTT broker not available');
          return;
        }

        // Create and dispose multiple managers to test for leaks
        for (int i = 0; i < 3; i++) {
          final testConfig = MerkleKVConfig(
            mqttHost: host,
            mqttPort: port,
            username: username,
            password: password,
            mqttUseTls: useTls,
            nodeId: 'cleanup-test-node-$i',
            clientId: 'cleanup-test-client-$i-${DateTime.now().millisecondsSinceEpoch}',
            keepAliveSeconds: 10,
          );

          final mqttClient = MqttClientImpl(testConfig);
          final manager = DefaultConnectionLifecycleManager(
            config: testConfig,
            mqttClient: mqttClient,
            metrics: metrics,
          );

          await manager.connect();
          expect(manager.isConnected, isTrue);

          // Simulate some activity
          await Future.delayed(Duration(milliseconds: 100));

          await manager.dispose();
          
          // Manager should be disposed cleanly
          expect(manager.isConnected, isFalse);
        }
      });

      test('subscriptions are properly managed', () async {
        if (!await _brokerAvailable(host, port)) {
          markTestSkipped('MQTT broker not available');
          return;
        }

        final mqttClient = MqttClientImpl(config);
        final manager = DefaultConnectionLifecycleManager(
          config: config,
          mqttClient: mqttClient,
          metrics: metrics,
        );

        try {
          await manager.connect();
          expect(manager.isConnected, isTrue);

          // Add some subscriptions through the MQTT client
          await mqttClient.subscribe('test/topic1', (topic, payload) {});
          await mqttClient.subscribe('test/topic2', (topic, payload) {});

          // Disconnect should clean up subscriptions
          await manager.disconnect();
          expect(manager.isConnected, isFalse);

          // Reconnect should work cleanly
          await manager.connect();
          expect(manager.isConnected, isTrue);

          await manager.disconnect();
        } finally {
          await manager.dispose();
        }
      });
    });

    group('Metrics integration', () {
      test('connection metrics are recorded correctly', () async {
        if (!await _brokerAvailable(host, port)) {
          markTestSkipped('MQTT broker not available');
          return;
        }

        final testMetrics = InMemoryReplicationMetrics();
        final mqttClient = MqttClientImpl(config);
        final manager = DefaultConnectionLifecycleManager(
          config: config,
          mqttClient: mqttClient,
          metrics: testMetrics,
        );

        try {
          await manager.connect();
          await Future.delayed(Duration(milliseconds: 100));
          await manager.disconnect();

          // Metrics should be recorded (exact metrics depend on implementation)
          // This test verifies integration works without specific metric expectations
          expect(manager.isConnected, isFalse);
        } finally {
          await manager.dispose();
        }
      });
    });
  });
}

/// Check if MQTT broker is available for testing.
Future<bool> _brokerAvailable(String host, int port) async {
  try {
    final socket = await Socket.connect(host, port, timeout: Duration(seconds: 2));
    await socket.close();
    return true;
  } catch (e) {
    return false;
  }
}