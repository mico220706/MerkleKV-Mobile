import '../config/merkle_kv_config.dart';
import 'in_memory_storage.dart';
import 'storage_interface.dart';

/// Factory for creating storage instances based on configuration.
///
/// Provides a simple way to create storage backends with or without
/// persistence based on MerkleKVConfig.persistenceEnabled.
class StorageFactory {
  /// Creates a storage instance based on the provided configuration.
  ///
  /// If [config.persistenceEnabled] is true, creates InMemoryStorage with
  /// persistence to local file storage. Otherwise, creates pure in-memory storage.
  ///
  /// The returned storage instance must be initialized by calling initialize()
  /// before use.
  static StorageInterface create(MerkleKVConfig config) {
    return InMemoryStorage(config);
  }
}
