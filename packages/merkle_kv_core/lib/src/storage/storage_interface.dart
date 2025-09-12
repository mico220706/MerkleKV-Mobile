import 'storage_entry.dart';

/// Abstract storage interface for MerkleKV Mobile per Locked Spec §8.
///
/// Provides in-memory key-value operations with version vector tracking,
/// Last-Write-Wins conflict resolution per §5.1, tombstone management
/// per §5.6, and optional persistence to local storage.
abstract class StorageInterface {
  /// Retrieves an entry by key.
  ///
  /// Returns null if the key doesn't exist or has been deleted (tombstone).
  /// Only returns non-tombstone entries to maintain read-your-writes consistency.
  /// Tombstone entries are still stored internally and can be accessed via [getAllEntries()],
  /// but are filtered out from [get()] operations.
  Future<StorageEntry?> get(String key);

  /// Stores an entry with LWW conflict resolution.
  ///
  /// If an entry with the same key exists, applies Last-Write-Wins resolution
  /// using (timestampMs, nodeId) ordering per §5.1. If the existing entry
  /// wins, the put operation is ignored (no overwrite).
  ///
  /// Validates key and value size constraints per §11:
  /// - Key: ≤256 bytes UTF-8
  /// - Value: ≤256KiB bytes UTF-8
  ///
  /// Throws [ArgumentError] if size constraints are violated.
  Future<void> put(String key, StorageEntry entry);

  /// Stores an entry during reconciliation with loop prevention.
  ///
  /// Same as [put] but marks the operation as reconciliation to prevent
  /// generating replication events, avoiding synchronization loops.
  /// Used by anti-entropy protocol during SYNC_KEYS operations.
  Future<void> putWithReconciliation(String key, StorageEntry entry);

  /// Creates a tombstone for the specified key.
  ///
  /// Writes a tombstone entry with the given version vector.
  /// The tombstone will be garbage collected after 24 hours per §5.6.
  ///
  /// Applies LWW conflict resolution - if existing entry is newer,
  /// the delete operation is ignored.
  Future<void> delete(String key, int timestampMs, String nodeId, int seq);

  /// Returns all entries including tombstones.
  ///
  /// Used for replication and Merkle tree construction.
  /// Includes both regular entries and tombstones for complete state.
  Future<List<StorageEntry>> getAllEntries();

  /// Removes expired tombstones older than 24 hours.
  ///
  /// Performs garbage collection of tombstones per §5.6.
  /// Should be called periodically to prevent unbounded growth.
  ///
  /// Returns the number of tombstones removed.
  Future<int> garbageCollectTombstones();

  /// Initializes the storage backend.
  ///
  /// For persistent storage, loads existing data from storage medium.
  /// Must be called before using other storage operations.
  Future<void> initialize();

  /// Disposes of storage resources and persists data if needed.
  ///
  /// Should be called when the storage is no longer needed.
  Future<void> dispose();
}
