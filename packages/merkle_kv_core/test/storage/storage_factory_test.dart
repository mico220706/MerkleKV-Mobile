import 'package:test/test.dart';
import 'package:merkle_kv_core/src/config/merkle_kv_config.dart';
import 'package:merkle_kv_core/src/storage/storage_factory.dart';
import 'package:merkle_kv_core/src/storage/in_memory_storage.dart';

void main() {
  group('StorageFactory', () {
    test('creates InMemoryStorage with persistence disabled', () {
      final config = MerkleKVConfig.create(
        mqttHost: 'test-host',
        clientId: 'test-client',
        nodeId: 'test-node',
        persistenceEnabled: false,
      );

      final storage = StorageFactory.create(config);

      expect(storage, isA<InMemoryStorage>());
    });

    test('creates InMemoryStorage with persistence enabled', () {
      final config = MerkleKVConfig.create(
        mqttHost: 'test-host',
        clientId: 'test-client',
        nodeId: 'test-node',
        persistenceEnabled: true,
      );

      final storage = StorageFactory.create(config);

      expect(storage, isA<InMemoryStorage>());
    });
  });
}
