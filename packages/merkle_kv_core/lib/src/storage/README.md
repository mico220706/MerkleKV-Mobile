# Storage Layer

This directory contains the storage engine implementation for MerkleKV Mobile, providing in-memory key-value operations with optional persistence per Locked Spec §8.

## Components

### StorageEntry (`storage_entry.dart`)
- Represents a key-value pair with version vector for LWW conflict resolution
- Contains (timestampMs, nodeId, seq) version vector per §5.1
- Supports both regular entries and tombstones per §5.6
- Implements LWW comparison logic and tombstone expiration (24h)

### StorageInterface (`storage_interface.dart`)
- Abstract interface defining storage operations
- Provides get, put, delete, getAllEntries, and garbageCollectTombstones methods
- Specifies LWW conflict resolution behavior
- Documents size constraints per §11: keys ≤256 bytes UTF-8, values ≤256KiB UTF-8

### InMemoryStorage (`in_memory_storage.dart`)
- Concurrent-safe in-memory implementation using Map<String, StorageEntry>
- Enforces size validation per §11
- Implements LWW conflict resolution with (timestampMs, nodeId) ordering
- Provides tombstone management with 24-hour retention and garbage collection
- Optional persistence to append-only JSON file with SHA-256 integrity checksums
- Supports corruption recovery by skipping bad records

### StorageFactory (`storage_factory.dart`)
- Factory for creating storage instances based on MerkleKVConfig
- Returns InMemoryStorage with or without persistence based on configuration

## Features

### Last-Write-Wins (LWW) Conflict Resolution
Implements §5.1 ordering:
1. Compare `timestampMs` (higher wins)
2. If equal, compare `nodeId` lexicographically (higher wins)
3. If both equal, treat as duplicate (no overwrite)

### Tombstone Management
Per §5.6:
- Delete operations create tombstones (value=null, isTombstone=true)
- Tombstones older than 24 hours are garbage collected
- Tombstones return null for get() but appear in getAllEntries()

### Size Validation
Per §11:
- Keys: maximum 256 bytes UTF-8 encoded
- Values: maximum 256 KiB bytes UTF-8 encoded
- Validation includes multi-byte UTF-8 character handling

### Optional Persistence
When MerkleKVConfig.persistenceEnabled=true:
- Append-only JSON Lines format with SHA-256 checksums
- Atomic file replacement for compaction
- Corruption recovery during load (skip bad records)
- LWW resolution applied during loading

## Usage Example

```dart
import 'package:merkle_kv_core/merkle_kv_core.dart';

// Create configuration
final config = MerkleKVConfig(
  mqttHost: 'broker.example.com',
  clientId: 'mobile-client-1',
  nodeId: 'node-uuid',
  persistenceEnabled: true,
  storagePath: '/path/to/storage',
);

// Create storage
final storage = StorageFactory.create(config);
await storage.initialize();

// Store entry
final entry = StorageEntry.value(
  key: 'user:123',
  value: 'John Doe',
  timestampMs: DateTime.now().millisecondsSinceEpoch,
  nodeId: config.nodeId,
  seq: 1,
);

await storage.put('user:123', entry);

// Retrieve entry
final retrieved = await storage.get('user:123');
print(retrieved?.value); // "John Doe"

// Delete entry (creates tombstone)
await storage.delete('user:123', DateTime.now().millisecondsSinceEpoch, config.nodeId, 2);

// Garbage collect expired tombstones
final removedCount = await storage.garbageCollectTombstones();
print('Removed $removedCount expired tombstones');

// Clean up
await storage.dispose();
```

## Testing

The storage implementation includes comprehensive tests covering:
- LWW resolution edge cases (timestamp ordering, nodeId tiebreaker, duplicates)
- Tombstone lifecycle and garbage collection
- Size validation with UTF-8 multi-byte characters
- Persistence round-trip and corruption recovery
- JSON serialization/deserialization
- Error handling and validation

Tests are located in `test/storage/` and can be run with:
```bash
dart test test/storage/
```

## Performance Considerations

- In-memory operations are O(1) for get/put/delete
- getAllEntries() is O(n) where n is number of stored entries
- Garbage collection is O(n) but only processes tombstones
- Persistence operations are append-only for writes, full scan for loads
- File compaction happens during GC when persistence is enabled

## Security

- Uses SHA-256 checksums for persistence integrity
- Validates all input sizes to prevent memory exhaustion
- Clears sensitive data where possible (implementation dependent)
- File operations use atomic replacement to prevent corruption
