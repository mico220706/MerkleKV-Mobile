import 'dart:async';
import 'package:test/test.dart';
import 'package:merkle_kv_core/merkle_kv.dart';
import 'package:merkle_kv_core/src/config/merkle_kv_config.dart';
import 'package:merkle_kv_core/src/config/invalid_config_exception.dart';
import 'package:merkle_kv_core/src/errors/merkle_kv_exception.dart';

void main() {
  group('MerkleKV', () {
    late MerkleKVConfig config;

    setUp(() {
      config = MerkleKVConfig.create(
        mqttHost: 'localhost',
        mqttPort: 1883,
        clientId: 'test_client',
        nodeId: 'test_node',
        username: 'test_user',
        password: 'test_pass',
        mqttUseTls: true, // Enable TLS when using credentials
      );
    });

    group('Configuration Tests', () {
      test('creates instance with valid configuration', () async {
        expect(() => MerkleKV.create(config), returnsNormally);
      });

      test('throws ValidationException for invalid configuration', () {
        expect(
          () => MerkleKVConfig.create(
            mqttHost: '', // Invalid empty host
            mqttPort: 1883,
            clientId: 'test_client',
            nodeId: 'test_node',
          ),
          throwsA(isA<InvalidConfigException>()),
        );
      });

      test('creates instance with minimal configuration', () async {
        final minimalConfig = MerkleKVConfig.create(
          mqttHost: 'test.broker.com',
          mqttPort: 1883,
          clientId: 'minimal_client',
          nodeId: 'minimal_node',
        );
        
        expect(() => MerkleKV.create(minimalConfig), returnsNormally);
      });
    });

    group('Basic Functionality Tests', () {
      test('instance creation is async', () async {
        final future = MerkleKV.create(config);
        expect(future, isA<Future<MerkleKV>>());
        
        final instance = await future;
        expect(instance, isA<MerkleKV>());
      });

      test('multiple instances can be created', () async {
        final config1 = MerkleKVConfig.create(
          mqttHost: 'localhost',
          mqttPort: 1883,
          clientId: 'client1',
          nodeId: 'node1',
        );
        
        final config2 = MerkleKVConfig.create(
          mqttHost: 'localhost',
          mqttPort: 1883,
          clientId: 'client2',
          nodeId: 'node2',
        );
        
        final instance1 = await MerkleKV.create(config1);
        final instance2 = await MerkleKV.create(config2);
        
        expect(instance1, isA<MerkleKV>());
        expect(instance2, isA<MerkleKV>());
        expect(instance1, isNot(same(instance2)));
      });
    });
  });
}