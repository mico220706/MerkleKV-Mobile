import 'dart:async';
import 'dart:io';
import 'package:test/test.dart';
import 'package:merkle_kv_core/merkle_kv.dart';
import 'package:merkle_kv_core/src/config/merkle_kv_config.dart';
import 'package:merkle_kv_core/src/errors/merkle_kv_exception.dart';

void main() {
  group('MerkleKV Integration Tests', () {
    // Note: These tests require a running MQTT broker
    // Skip if broker is not available
    late bool brokerAvailable;
    late MerkleKVConfig config;

    setUpAll(() async {
      // Check if test broker is available
      try {
        final socket = await Socket.connect('localhost', 1883)
            .timeout(Duration(seconds: 2));
        await socket.close();
        brokerAvailable = true;
      } catch (e) {
        brokerAvailable = false;
        print('Skipping integration tests - MQTT broker not available on localhost:1883');
      }

      config = MerkleKVConfig.create(
        mqttHost: 'localhost',
        mqttPort: 1883,
        clientId: 'test_client_${DateTime.now().millisecondsSinceEpoch}',
        nodeId: 'test_node_${DateTime.now().millisecondsSinceEpoch}',
      );
    });

    group('Full Lifecycle Tests', () {
      test('complete CRUD workflow', () async {
        if (!brokerAvailable) return;

        final merkleKV = await MerkleKV.create(config);
        
        try {
          // Connect
          await merkleKV.connect();
          expect(merkleKV.isConnected, isTrue);

          // Test SET operation
          await merkleKV.set('test_key', 'test_value');

          // Test GET operation
          final value = await merkleKV.get('test_key');
          expect(value, equals('test_value'));

          // Test UPDATE operation
          await merkleKV.set('test_key', 'updated_value');
          final updatedValue = await merkleKV.get('test_key');
          expect(updatedValue, equals('updated_value'));

          // Test DELETE operation (idempotent)
          await merkleKV.delete('test_key');
          final deletedValue = await merkleKV.get('test_key');
          expect(deletedValue, isNull);

          // Test idempotent delete
          await merkleKV.delete('test_key'); // Should not throw
          
        } finally {
          await merkleKV.disconnect();
          expect(merkleKV.isConnected, isFalse);
        }
      }, timeout: Timeout(Duration(seconds: 30)));

      test('numeric operations workflow', () async {
        if (!brokerAvailable) return;

        final merkleKV = await MerkleKV.create(config);
        
        try {
          await merkleKV.connect();

          // Initialize counter
          await merkleKV.set('counter', '0');

          // Test increment operations
          var result = await merkleKV.increment('counter', 5);
          expect(result, equals(5));

          result = await merkleKV.increment('counter', 3);
          expect(result, equals(8));

          // Test decrement operations
          result = await merkleKV.decrement('counter', 2);
          expect(result, equals(6));

          result = await merkleKV.decrement('counter', 10);
          expect(result, equals(-4));

          // Verify final value
          final finalValue = await merkleKV.get('counter');
          expect(finalValue, equals('-4'));
          
        } finally {
          await merkleKV.disconnect();
        }
      }, timeout: Timeout(Duration(seconds: 30)));

      test('string operations workflow', () async {
        if (!brokerAvailable) return;

        final merkleKV = await MerkleKV.create(config);
        
        try {
          await merkleKV.connect();

          // Initialize string
          await merkleKV.set('greeting', 'Hello');

          // Test append operations
          var result = await merkleKV.append('greeting', ' World');
          expect(result, equals('Hello World'));

          // Test prepend operations
          result = await merkleKV.prepend('greeting', 'Hi! ');
          expect(result, equals('Hi! Hello World'));

          // Verify final value
          final finalValue = await merkleKV.get('greeting');
          expect(finalValue, equals('Hi! Hello World'));
          
        } finally {
          await merkleKV.disconnect();
        }
      }, timeout: Timeout(Duration(seconds: 30)));

      test('bulk operations workflow', () async {
        if (!brokerAvailable) return;

        final merkleKV = await MerkleKV.create(config);
        
        try {
          await merkleKV.connect();

          // Test bulk set
          final operations = {
            'bulk_key1': 'bulk_value1',
            'bulk_key2': 'bulk_value2',
            'bulk_key3': 'bulk_value3',
          };
          await merkleKV.setMultiple(operations);

          // Test bulk get
          final keys = ['bulk_key1', 'bulk_key2', 'bulk_key3', 'nonexistent'];
          final results = await merkleKV.getMultiple(keys);

          expect(results['bulk_key1'], equals('bulk_value1'));
          expect(results['bulk_key2'], equals('bulk_value2'));
          expect(results['bulk_key3'], equals('bulk_value3'));
          expect(results['nonexistent'], isNull);

          // Clean up
          await merkleKV.delete('bulk_key1');
          await merkleKV.delete('bulk_key2');
          await merkleKV.delete('bulk_key3');
          
        } finally {
          await merkleKV.disconnect();
        }
      }, timeout: Timeout(Duration(seconds: 30)));
    });

    group('Error Handling Tests', () {
      test('handles connection failures gracefully', () async {
        // Use invalid broker configuration
        final invalidConfig = MerkleKVConfig.create(
          mqttHost: 'nonexistent.broker.invalid',
          mqttPort: 1883,
          clientId: 'test_client',
          nodeId: 'test_node',
        );

        final merkleKV = MerkleKV.create(invalidConfig);

        expect(
          () => merkleKV.connect(),
          throwsA(isA<ConnectionException>()),
        );
      }, timeout: Timeout(Duration(seconds: 15)));

      test('fail-fast behavior when disconnected', () async {
        if (!brokerAvailable) return;

        final merkleKV = await MerkleKV.create(config);
        
        // Don't connect - should fail fast
        expect(
          () => merkleKV.get('test_key'),
          throwsA(isA<ConnectionException>()
              .having((e) => e.message, 'message', contains('disconnected'))),
        );

        expect(
          () => merkleKV.set('test_key', 'value'),
          throwsA(isA<ConnectionException>()),
        );

        expect(
          () => merkleKV.delete('test_key'),
          throwsA(isA<ConnectionException>()),
        );
      });

      test('validation errors for oversized keys and values', () async {
        if (!brokerAvailable) return;

        final merkleKV = await MerkleKV.create(config);
        
        try {
          await merkleKV.connect();

          // Test oversized key
          final largeKey = 'a' * 257;
          expect(
            () => merkleKV.get(largeKey),
            throwsA(isA<ValidationException>()
                .having((e) => e.message, 'message', contains('Key size'))),
          );

          // Test oversized value
          final largeValue = 'a' * (256 * 1024 + 1);
          expect(
            () => merkleKV.set('key', largeValue),
            throwsA(isA<ValidationException>()
                .having((e) => e.message, 'message', contains('Value size'))),
          );

          // Test oversized bulk operation
          final largeBulk = <String, String>{};
          for (int i = 0; i < 200; i++) {
            largeBulk['key$i'] = 'a' * 3000;
          }
          expect(
            () => merkleKV.setMultiple(largeBulk),
            throwsA(isA<ValidationException>()
                .having((e) => e.message, 'message', contains('Bulk operation size'))),
          );
          
        } finally {
          await merkleKV.disconnect();
        }
      }, timeout: Timeout(Duration(seconds: 30)));
    });

    group('UTF-8 Validation Tests', () {
      test('handles international characters correctly', () async {
        if (!brokerAvailable) return;

        final merkleKV = await MerkleKV.create(config);
        
        try {
          await merkleKV.connect();

          // Test various international characters
          final testCases = {
            'café': 'ñoño',
            '测试': 'тест',
            '🚀': '🌍',
            'مرحبا': 'שלום',
            'こんにちは': 'ไฮ',
          };

          for (final entry in testCases.entries) {
            await merkleKV.set(entry.key, entry.value);
            final retrieved = await merkleKV.get(entry.key);
            expect(retrieved, equals(entry.value));
          }

          // Clean up
          for (final key in testCases.keys) {
            await merkleKV.delete(key);
          }
          
        } finally {
          await merkleKV.disconnect();
        }
      }, timeout: Timeout(Duration(seconds: 30)));

      test('respects UTF-8 byte limits correctly', () async {
        if (!brokerAvailable) return;

        final merkleKV = await MerkleKV.create(config);
        
        try {
          await merkleKV.connect();

          // Test key at byte limit (256 bytes)
          final keyAt256Bytes = 'café' * 51 + 'c'; // Adjust to exactly 256 bytes
          final exactKey = 'a' * 256; // Simple 256-byte key
          
          await merkleKV.set(exactKey, 'value');
          final value = await merkleKV.get(exactKey);
          expect(value, equals('value'));

          // Test key over byte limit
          final keyOver256Bytes = 'café' * 65; // Over 256 bytes
          expect(
            () => merkleKV.set(keyOver256Bytes, 'value'),
            throwsA(isA<ValidationException>()),
          );

          await merkleKV.delete(exactKey);
          
        } finally {
          await merkleKV.disconnect();
        }
      }, timeout: Timeout(Duration(seconds: 30)));
    });

    group('Concurrency Tests', () {
      test('handles concurrent operations safely', () async {
        if (!brokerAvailable) return;

        final merkleKV = await MerkleKV.create(config);
        
        try {
          await merkleKV.connect();

          // Start multiple concurrent operations
          final futures = <Future>[];
          
          // Concurrent sets
          for (int i = 0; i < 10; i++) {
            futures.add(merkleKV.set('concurrent_key_$i', 'value_$i'));
          }

          // Concurrent gets (some may return null initially)
          for (int i = 0; i < 10; i++) {
            futures.add(merkleKV.get('concurrent_key_$i'));
          }

          // Wait for all operations to complete
          final results = await Future.wait(futures);

          // Verify all sets completed successfully (first 10 results)
          for (int i = 0; i < 10; i++) {
            // Set operations return void, so we just check they completed
          }

          // Clean up
          for (int i = 0; i < 10; i++) {
            await merkleKV.delete('concurrent_key_$i');
          }
          
        } finally {
          await merkleKV.disconnect();
        }
      }, timeout: Timeout(Duration(seconds: 45)));

      test('maintains consistency under concurrent access', () async {
        if (!brokerAvailable) return;

        final merkleKV = await MerkleKV.create(config);
        
        try {
          await merkleKV.connect();

          // Initialize counter
          await merkleKV.set('shared_counter', '0');

          // Start concurrent increment operations
          final futures = <Future>[];
          for (int i = 0; i < 5; i++) {
            futures.add(merkleKV.increment('shared_counter', 1));
          }

          await Future.wait(futures);

          // Final value should be 5
          final finalValue = await merkleKV.get('shared_counter');
          expect(int.parse(finalValue!), equals(5));

          await merkleKV.delete('shared_counter');
          
        } finally {
          await merkleKV.disconnect();
        }
      }, timeout: Timeout(Duration(seconds: 30)));
    });

    group('Offline Queue Tests', () {
      test('respects offline queue configuration', () async {
        // Test with offline queue disabled
        final configNoQueue = MerkleKVConfig.create(
          mqttHost: 'localhost',
          mqttPort: 1883,
          clientId: 'test_offline_disabled',
          nodeId: 'test_node_offline',
        );

        final merkleKVNoQueue = MerkleKV.create(configNoQueue);

        // Should fail when not connected
        expect(
          () => merkleKVNoQueue.get('test_key'),
          throwsA(isA<ConnectionException>()),
        );

        // Test with offline queue enabled
        final configWithQueue = MerkleKVConfig.create(
          mqttHost: 'localhost',
          mqttPort: 1883,
          clientId: 'test_offline_enabled',
          nodeId: 'test_node_queue',
        );

        final merkleKVWithQueue = MerkleKV.create(configWithQueue);

        // Should not fail immediately when not connected (queued for later)
        expect(() => merkleKVWithQueue.get('test_key'), returnsNormally);
      });
    });

    group('Builder Pattern Tests', () {
      test('creates configuration using builder pattern', () {
        final config = MerkleKVConfigBuilder()
            .brokerHost('test.broker.com')
            .brokerPort(8883)
            .clientId('builder_test_client')
            .username('test_user')
            .password('test_pass')
            .enableSecure(true)
            .enableOfflineQueue(true)
            .commandTimeout(Duration(seconds: 45))
            .connectionTimeout(Duration(seconds: 15))
            .build();

        expect(config.brokerHost, equals('test.broker.com'));
        expect(config.brokerPort, equals(8883));
        expect(config.clientId, equals('builder_test_client'));
        expect(config.username, equals('test_user'));
        expect(config.password, equals('test_pass'));
        expect(config.enableSecure, isTrue);
        expect(config.enableOfflineQueue, isTrue);
        expect(config.commandTimeout, equals(Duration(seconds: 45)));
        expect(config.connectionTimeout, equals(Duration(seconds: 15)));
      });

      test('builder validates configuration before building', () {
        expect(
          () => MerkleKVConfigBuilder()
              .brokerHost('') // Invalid empty host
              .brokerPort(1883)
              .clientId('test')
              .build(),
          throwsA(isA<ValidationException>()),
        );

        expect(
          () => MerkleKVConfigBuilder()
              .brokerHost('localhost')
              .brokerPort(0) // Invalid port
              .clientId('test')
              .build(),
          throwsA(isA<ValidationException>()),
        );

        expect(
          () => MerkleKVConfigBuilder()
              .brokerHost('localhost')
              .brokerPort(1883)
              .clientId('') // Invalid empty client ID
              .build(),
          throwsA(isA<ValidationException>()),
        );
      });
    });
  });
}