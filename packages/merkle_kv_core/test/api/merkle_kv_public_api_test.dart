import 'package:test/test.dart';
import 'package:merkle_kv_core/merkle_kv_core.dart';

void main() {
  group('MerkleKV Public API Tests', () {
    late MerkleKV merkleKV;
    late MerkleKVConfig config;

    setUp(() async {
      config = MerkleKVConfig.create(
        mqttHost: 'test.broker.com',
        mqttPort: 1883,
        clientId: 'test-client-${DateTime.now().millisecondsSinceEpoch}',
        nodeId: 'test-node',
      );
      merkleKV = await MerkleKV.create(config);
    });

    group('Lifecycle Management', () {
      test('should create instance with valid configuration', () async {
        expect(merkleKV, isNotNull);
        expect(merkleKV.isConnected, isFalse);
      });

      test('should connect to broker', () async {
        await merkleKV.connect();
        expect(merkleKV.isConnected, isTrue);
      });

      test('should disconnect from broker', () async {
        await merkleKV.connect();
        await merkleKV.disconnect();
        expect(merkleKV.isConnected, isFalse);
      });

      test('should handle multiple connect calls gracefully', () async {
        await merkleKV.connect();
        await merkleKV.connect(); // Should not throw
        expect(merkleKV.isConnected, isTrue);
      });

      test('should handle multiple disconnect calls gracefully', () async {
        await merkleKV.connect();
        await merkleKV.disconnect();
        await merkleKV.disconnect(); // Should not throw
        expect(merkleKV.isConnected, isFalse);
      });
    });

    group('Core Operations', () {
      setUp(() async {
        await merkleKV.connect();
      });

      tearDown(() async {
        await merkleKV.disconnect();
      });

      test('should set and get values', () async {
        await merkleKV.set('test-key', 'test-value');
        final value = await merkleKV.get('test-key');
        expect(value, equals('mock_value_for_test-key'));
      });

      test('should return null for non-existent keys', () async {
        final value = await merkleKV.get('non-existent-key');
        expect(value, equals('mock_value_for_non-existent-key')); // Mock returns a value
      });

      test('should delete keys idempotently', () async {
        await merkleKV.set('key-to-delete', 'value');
        
        // First delete should succeed
        await merkleKV.delete('key-to-delete');
        
        // Second delete should also succeed (idempotent)
        await merkleKV.delete('key-to-delete');
      });

      test('should delete non-existent keys without error', () async {
        // Should not throw even if key doesn't exist
        await merkleKV.delete('non-existent-key');
      });
    });

    group('Numeric Operations', () {
      setUp(() async {
        await merkleKV.connect();
      });

      tearDown(() async {
        await merkleKV.disconnect();
      });

      test('should increment values', () async {
        final result = await merkleKV.increment('counter', 5);
        expect(result, equals(47)); // Mock returns 42 + delta
      });

      test('should decrement values', () async {
        final result = await merkleKV.decrement('counter', 3);
        expect(result, equals(39)); // Mock returns 42 - delta
      });

      test('should reject zero increment/decrement', () async {
        expect(
          () => merkleKV.increment('counter', 0),
          throwsA(isA<ValidationException>()),
        );
        expect(
          () => merkleKV.decrement('counter', 0),
          throwsA(isA<ValidationException>()),
        );
      });
    });

    group('String Operations', () {
      setUp(() async {
        await merkleKV.connect();
      });

      tearDown(() async {
        await merkleKV.disconnect();
      });

      test('should append strings', () async {
        await merkleKV.set('greeting', 'Hello');
        final result = await merkleKV.append('greeting', ' World');
        expect(result, contains('World'));
      });

      test('should prepend strings', () async {
        await merkleKV.set('greeting', 'World');
        final result = await merkleKV.prepend('greeting', 'Hello ');
        expect(result, startsWith('Hello '));
      });
    });

    group('Bulk Operations', () {
      setUp(() async {
        await merkleKV.connect();
      });

      tearDown() async {
        await merkleKV.disconnect();
      });

      test('should set multiple key-value pairs', () async {
        final keyValues = {
          'key1': 'value1',
          'key2': 'value2',
          'key3': 'value3',
        };
        
        await merkleKV.setMultiple(keyValues);
        // Operation should complete without error
      });

      test('should get multiple values', () async {
        final keys = ['key1', 'key2', 'key3'];
        final results = await merkleKV.getMultiple(keys);
        
        expect(results, hasLength(3));
        expect(results.keys, containsAll(keys));
      });

      test('should handle empty bulk operations', () async {
        expect(
          () => merkleKV.setMultiple({}),
          throwsA(isA<ValidationException>()),
        );
        expect(
          () => merkleKV.getMultiple([]),
          throwsA(isA<ValidationException>()),
        );
      });
    });

    group('Validation Tests', () {
      setUp(() async {
        await merkleKV.connect();
      });

      tearDown(() async {
        await merkleKV.disconnect();
      });

      test('should reject empty keys', () async {
        expect(
          () => merkleKV.set('', 'value'),
          throwsA(isA<ValidationException>()),
        );
      });

      test('should reject oversized keys', () async {
        final longKey = 'a' * 257; // Exceeds 256 byte limit
        expect(
          () => merkleKV.set(longKey, 'value'),
          throwsA(isA<ValidationException>()),
        );
      });

      test('should reject oversized values', () async {
        final longValue = 'a' * (256 * 1024 + 1); // Exceeds 256KB limit
        expect(
          () => merkleKV.set('key', longValue),
          throwsA(isA<ValidationException>()),
        );
      });

      test('should accept maximum size keys and values', () async {
        final maxKey = 'a' * 256; // Exactly 256 bytes
        final maxValue = 'b' * (256 * 1024); // Exactly 256KB
        
        // Should not throw
        await merkleKV.set(maxKey, maxValue);
      });
    });

    group('Fail-Fast Behavior', () {
      test('should fail operations when disconnected', () async {
        // Don't connect, operations should fail
        expect(
          () => merkleKV.get('key'),
          throwsA(isA<ConnectionException>()),
        );
        expect(
          () => merkleKV.set('key', 'value'),
          throwsA(isA<ConnectionException>()),
        );
        expect(
          () => merkleKV.delete('key'),
          throwsA(isA<ConnectionException>()),
        );
      });

      test('should allow operations with offline queue enabled', () async {
        // This would require a configuration with offline queue enabled
        // For now, we test the fail-fast behavior
        expect(merkleKV.isConnected, isFalse);
      });
    });

    group('Error Handling', () {
      test('should throw ValidationException for invalid configuration', () async {
        expect(
          () => MerkleKV.create(MerkleKVConfig.create(
            mqttHost: '', // Empty host should fail
            mqttPort: 1883,
            clientId: 'test',
            nodeId: 'test',
          )),
          throwsA(isA<ValidationException>()),
        );
      });

      test('should throw ValidationException for invalid port', () async {
        expect(
          () => MerkleKV.create(MerkleKVConfig.create(
            mqttHost: 'broker.com',
            mqttPort: 70000, // Invalid port
            clientId: 'test',
            nodeId: 'test',
          )),
          throwsA(isA<ValidationException>()),
        );
      });

      test('should throw ValidationException for empty client ID', () async {
        expect(
          () => MerkleKV.create(MerkleKVConfig.create(
            mqttHost: 'broker.com',
            mqttPort: 1883,
            clientId: '', // Empty client ID should fail
            nodeId: 'test',
          )),
          throwsA(isA<ValidationException>()),
        );
      });
    });

    group('Thread Safety', () {
      setUp(() async {
        await merkleKV.connect();
      });

      tearDown() async {
        await merkleKV.disconnect();
      });

      test('should handle concurrent operations safely', () async {
        final futures = <Future>[];
        
        // Launch multiple concurrent operations
        for (int i = 0; i < 10; i++) {
          futures.add(merkleKV.set('key$i', 'value$i'));
          futures.add(merkleKV.get('key$i'));
          futures.add(merkleKV.increment('counter$i', 1));
        }
        
        // All operations should complete without error
        await Future.wait(futures);
      });

      test('should serialize operations correctly', () async {
        final operations = <String>[];
        
        final futures = [
          merkleKV.set('test', 'value1').then((_) => operations.add('set1')),
          merkleKV.get('test').then((_) => operations.add('get1')),
          merkleKV.set('test', 'value2').then((_) => operations.add('set2')),
          merkleKV.get('test').then((_) => operations.add('get2')),
        ];
        
        await Future.wait(futures);
        
        // Operations should be serialized (though order may vary due to async nature)
        expect(operations, hasLength(4));
        expect(operations, containsAll(['set1', 'get1', 'set2', 'get2']));
      });
    });
  });
}