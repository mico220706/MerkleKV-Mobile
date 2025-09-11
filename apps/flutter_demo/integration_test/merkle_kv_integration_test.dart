import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:merkle_kv_core/merkle_kv_core.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('MerkleKV Mobile Integration Tests', () {
    late MerkleKVConfig config;
    late MerkleKVMobile merkleKV1;
    late MerkleKVMobile merkleKV2;
    
    setUpAll(() async {
      // Configure test environment
      config = MerkleKVConfig(
        nodeId: 'test-node-${Random().nextInt(1000)}',
        mqttBrokerHost: 'test.mosquitto.org', // Public test broker
        mqttBrokerPort: 1883,
        mqttClientId: 'test-client-${Random().nextInt(1000)}',
        storageType: StorageType.inMemory,
      );
    });

    tearDownAll(() async {
      await merkleKV1.disconnect();
      await merkleKV2.disconnect();
    });

    testWidgets('Basic Key-Value Operations', (WidgetTester tester) async {
      merkleKV1 = MerkleKVMobile(config);
      await merkleKV1.connect();
      
      // Test SET operation
      final setResponse = await merkleKV1.set('test-key', 'test-value');
      expect(setResponse.success, isTrue);
      expect(setResponse.message, contains('SET'));
      
      // Test GET operation
      final getResponse = await merkleKV1.get('test-key');
      expect(getResponse.success, isTrue);
      expect(getResponse.value, equals('test-value'));
      
      // Test non-existent key
      final notFoundResponse = await merkleKV1.get('non-existent-key');
      expect(notFoundResponse.success, isFalse);
      expect(notFoundResponse.message, contains('not found'));
    });

    testWidgets('Multi-Node Replication Test', (WidgetTester tester) async {
      // Create two nodes with different IDs
      final config1 = config.copyWith(
        nodeId: 'node-1-${Random().nextInt(1000)}',
        mqttClientId: 'client-1-${Random().nextInt(1000)}',
      );
      final config2 = config.copyWith(
        nodeId: 'node-2-${Random().nextInt(1000)}',
        mqttClientId: 'client-2-${Random().nextInt(1000)}',
      );

      merkleKV1 = MerkleKVMobile(config1);
      merkleKV2 = MerkleKVMobile(config2);

      await merkleKV1.connect();
      await merkleKV2.connect();

      // Wait for connection establishment
      await Future.delayed(Duration(seconds: 2));

      // Set value on node 1
      final key = 'replication-test-${Random().nextInt(1000)}';
      await merkleKV1.set(key, 'value-from-node-1');

      // Wait for replication
      await Future.delayed(Duration(seconds: 3));

      // Check if replicated to node 2
      final replicatedResponse = await merkleKV2.get(key);
      expect(replicatedResponse.success, isTrue);
      expect(replicatedResponse.value, equals('value-from-node-1'));
    });

    testWidgets('LWW Conflict Resolution Test', (WidgetTester tester) async {
      // Create two nodes
      final config1 = config.copyWith(
        nodeId: 'lww-node-1-${Random().nextInt(1000)}',
        mqttClientId: 'lww-client-1-${Random().nextInt(1000)}',
      );
      final config2 = config.copyWith(
        nodeId: 'lww-node-2-${Random().nextInt(1000)}',
        mqttClientId: 'lww-client-2-${Random().nextInt(1000)}',
      );

      merkleKV1 = MerkleKVMobile(config1);
      merkleKV2 = MerkleKVMobile(config2);

      await merkleKV1.connect();
      await merkleKV2.connect();

      // Wait for connection
      await Future.delayed(Duration(seconds: 2));

      final key = 'lww-test-${Random().nextInt(1000)}';

      // Set initial value on node 1
      await merkleKV1.set(key, 'initial-value');
      await Future.delayed(Duration(seconds: 1));

      // Concurrent updates (later timestamp should win)
      await Future.wait([
        merkleKV1.set(key, 'value-from-node-1'),
        merkleKV2.set(key, 'value-from-node-2'),
      ]);

      // Wait for conflict resolution
      await Future.delayed(Duration(seconds: 3));

      // Both nodes should have the same value (LWW resolution)
      final response1 = await merkleKV1.get(key);
      final response2 = await merkleKV2.get(key);

      expect(response1.success, isTrue);
      expect(response2.success, isTrue);
      expect(response1.value, equals(response2.value));
      
      // The value should be from one of the nodes
      expect([
        'value-from-node-1',
        'value-from-node-2'
      ].contains(response1.value), isTrue);
    });

    testWidgets('Network Partition Recovery Test', (WidgetTester tester) async {
      final config1 = config.copyWith(
        nodeId: 'partition-node-1-${Random().nextInt(1000)}',
        mqttClientId: 'partition-client-1-${Random().nextInt(1000)}',
      );
      final config2 = config.copyWith(
        nodeId: 'partition-node-2-${Random().nextInt(1000)}',
        mqttClientId: 'partition-client-2-${Random().nextInt(1000)}',
      );

      merkleKV1 = MerkleKVMobile(config1);
      merkleKV2 = MerkleKVMobile(config2);

      await merkleKV1.connect();
      await merkleKV2.connect();
      await Future.delayed(Duration(seconds: 2));

      final key = 'partition-test-${Random().nextInt(1000)}';

      // Set value on both nodes while connected
      await merkleKV1.set(key, 'connected-value');
      await Future.delayed(Duration(seconds: 2));

      // Simulate partition by disconnecting node 2
      await merkleKV2.disconnect();

      // Update on node 1 while node 2 is disconnected
      await merkleKV1.set(key, 'updated-while-partitioned');
      await Future.delayed(Duration(seconds: 1));

      // Reconnect node 2 (partition recovery)
      await merkleKV2.connect();
      await Future.delayed(Duration(seconds: 3));

      // Both nodes should eventually converge
      final response1 = await merkleKV1.get(key);
      final response2 = await merkleKV2.get(key);

      expect(response1.success, isTrue);
      expect(response2.success, isTrue);
      expect(response1.value, equals(response2.value));
    });

    testWidgets('Stress Test - Multiple Operations', (WidgetTester tester) async {
      merkleKV1 = MerkleKVMobile(config);
      await merkleKV1.connect();
      await Future.delayed(Duration(seconds: 1));

      const operationCount = 50;
      final keys = List.generate(operationCount, (i) => 'stress-key-$i');
      final values = List.generate(operationCount, (i) => 'stress-value-$i');

      // Perform multiple SET operations
      final setFutures = <Future>[];
      for (int i = 0; i < operationCount; i++) {
        setFutures.add(merkleKV1.set(keys[i], values[i]));
      }
      
      final setResults = await Future.wait(setFutures);
      
      // Verify all SET operations succeeded
      for (final result in setResults) {
        expect(result.success, isTrue);
      }

      // Perform multiple GET operations
      final getFutures = <Future>[];
      for (int i = 0; i < operationCount; i++) {
        getFutures.add(merkleKV1.get(keys[i]));
      }

      final getResults = await Future.wait(getFutures);

      // Verify all GET operations succeeded
      for (int i = 0; i < operationCount; i++) {
        expect(getResults[i].success, isTrue);
        expect(getResults[i].value, equals(values[i]));
      }
    });

    testWidgets('Metrics Collection Test', (WidgetTester tester) async {
      merkleKV1 = MerkleKVMobile(config);
      await merkleKV1.connect();
      await Future.delayed(Duration(seconds: 1));

      // Perform operations that should generate metrics
      await merkleKV1.set('metrics-test-1', 'value1');
      await merkleKV1.set('metrics-test-2', 'value2');
      await merkleKV1.get('metrics-test-1');
      await merkleKV1.get('non-existent-key');

      // Note: Actual metrics verification would depend on 
      // exposing metrics through the public API
      // For now, we just verify operations completed successfully
      final response = await merkleKV1.get('metrics-test-1');
      expect(response.success, isTrue);
      expect(response.value, equals('value1'));
    });
  });
}

extension MerkleKVConfigExtension on MerkleKVConfig {
  MerkleKVConfig copyWith({
    String? nodeId,
    String? mqttBrokerHost,
    int? mqttBrokerPort,
    String? mqttClientId,
    StorageType? storageType,
  }) {
    return MerkleKVConfig(
      nodeId: nodeId ?? this.nodeId,
      mqttBrokerHost: mqttBrokerHost ?? this.mqttBrokerHost,
      mqttBrokerPort: mqttBrokerPort ?? this.mqttBrokerPort,
      mqttClientId: mqttClientId ?? this.mqttClientId,
      storageType: storageType ?? this.storageType,
    );
  }
}
