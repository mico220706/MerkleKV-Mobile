import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:merkle_kv_core/src/config/merkle_kv_config.dart';
import 'package:merkle_kv_core/src/storage/in_memory_storage.dart';
import 'package:merkle_kv_core/src/storage/storage_entry.dart';

void main() {
  group('InMemoryStorage', () {
    late InMemoryStorage storage;
    late MerkleKVConfig config;

    setUp(() {
      config = MerkleKVConfig.create(
        mqttHost: 'test-host',
        clientId: 'test-client',
        nodeId: 'test-node',
        persistenceEnabled: false,
      );
      storage = InMemoryStorage(config);
    });

    tearDown(() async {
      await storage.dispose();

      // Clean up persistence files if they exist
      final storageDir = Directory('./storage');
      if (await storageDir.exists()) {
        await storageDir.delete(recursive: true);
      }
    });

    group('Initialization', () {
      test('initializes successfully without persistence', () async {
        await storage.initialize();
        // Should not throw
      });

      test('throws StateError when not initialized', () async {
        expect(
          () => storage.get('key'),
          throwsA(isA<StateError>()),
        );
      });
    });

    group('Basic Operations', () {
      setUp(() async {
        await storage.initialize();
      });

      test('stores and retrieves entry', () async {
        final entry = StorageEntry.value(
          key: 'test-key',
          value: 'test-value',
          timestampMs: 1000,
          nodeId: 'node1',
          seq: 1,
        );

        await storage.put('test-key', entry);
        final retrieved = await storage.get('test-key');

        expect(retrieved, equals(entry));
      });

      test('returns null for non-existent key', () async {
        final result = await storage.get('non-existent');
        expect(result, isNull);
      });

      test('returns null for tombstone', () async {
        final tombstone = StorageEntry.tombstone(
          key: 'deleted-key',
          timestampMs: 1000,
          nodeId: 'node1',
          seq: 1,
        );

        await storage.put('deleted-key', tombstone);
        final result = await storage.get('deleted-key');

        expect(result, isNull);
      });

      test('delete creates tombstone', () async {
        // First store a value
        final entry = StorageEntry.value(
          key: 'key-to-delete',
          value: 'value',
          timestampMs: 1000,
          nodeId: 'node1',
          seq: 1,
        );
        await storage.put('key-to-delete', entry);

        // Verify it exists
        expect(await storage.get('key-to-delete'), isNotNull);

        // Delete it
        await storage.delete('key-to-delete', 2000, 'node1', 2);

        // Should return null for get
        expect(await storage.get('key-to-delete'), isNull);

        // But should appear in getAllEntries as tombstone
        final allEntries = await storage.getAllEntries();
        final tombstone =
            allEntries.firstWhere((e) => e.key == 'key-to-delete');
        expect(tombstone.isTombstone, isTrue);
        expect(tombstone.timestampMs, equals(2000));
      });
    });

    group('Last-Write-Wins Resolution', () {
      setUp(() async {
        await storage.initialize();
      });

      test('newer entry overwrites older entry', () async {
        final older = StorageEntry.value(
          key: 'lww-key',
          value: 'old-value',
          timestampMs: 1000,
          nodeId: 'node1',
          seq: 1,
        );

        final newer = StorageEntry.value(
          key: 'lww-key',
          value: 'new-value',
          timestampMs: 2000,
          nodeId: 'node1',
          seq: 2,
        );

        await storage.put('lww-key', older);
        await storage.put('lww-key', newer);

        final result = await storage.get('lww-key');
        expect(result?.value, equals('new-value'));
        expect(result?.timestampMs, equals(2000));
      });

      test('older entry is ignored when newer exists', () async {
        final newer = StorageEntry.value(
          key: 'lww-key',
          value: 'new-value',
          timestampMs: 2000,
          nodeId: 'node1',
          seq: 2,
        );

        final older = StorageEntry.value(
          key: 'lww-key',
          value: 'old-value',
          timestampMs: 1000,
          nodeId: 'node1',
          seq: 1,
        );

        await storage.put('lww-key', newer);
        await storage.put('lww-key', older); // Should be ignored

        final result = await storage.get('lww-key');
        expect(result?.value, equals('new-value'));
        expect(result?.timestampMs, equals(2000));
      });

      test('nodeId tiebreaker works correctly', () async {
        final entryA = StorageEntry.value(
          key: 'tiebreaker-key',
          value: 'value-from-nodeA',
          timestampMs: 1000,
          nodeId: 'nodeA',
          seq: 1,
        );

        final entryZ = StorageEntry.value(
          key: 'tiebreaker-key',
          value: 'value-from-nodeZ',
          timestampMs: 1000, // Same timestamp
          nodeId: 'nodeZ', // Higher lexicographically
          seq: 1,
        );

        await storage.put('tiebreaker-key', entryA);
        await storage.put('tiebreaker-key', entryZ);

        final result = await storage.get('tiebreaker-key');
        expect(result?.value, equals('value-from-nodeZ'));
        expect(result?.nodeId, equals('nodeZ'));
      });

      test('duplicate version vector is ignored', () async {
        final entry1 = StorageEntry.value(
          key: 'duplicate-key',
          value: 'first-value',
          timestampMs: 1000,
          nodeId: 'node1',
          seq: 1,
        );

        final entry2 = StorageEntry.value(
          key: 'duplicate-key',
          value: 'second-value', // Different value
          timestampMs: 1000, // Same version vector
          nodeId: 'node1',
          seq: 1,
        );

        await storage.put('duplicate-key', entry1);
        await storage.put('duplicate-key', entry2); // Should be ignored

        final result = await storage.get('duplicate-key');
        expect(result?.value, equals('first-value')); // First entry wins
      });

      test('delete with older timestamp is ignored', () async {
        final entry = StorageEntry.value(
          key: 'protected-key',
          value: 'protected-value',
          timestampMs: 2000,
          nodeId: 'node1',
          seq: 2,
        );

        await storage.put('protected-key', entry);

        // Try to delete with older timestamp
        await storage.delete('protected-key', 1000, 'node1', 1);

        // Entry should still exist
        final result = await storage.get('protected-key');
        expect(result?.value, equals('protected-value'));
      });
    });

    group('Size Validation', () {
      setUp(() async {
        await storage.initialize();
      });

      test('rejects key longer than 256 bytes UTF-8', () async {
        // Create a key that's exactly 257 bytes UTF-8
        final longKey = 'a' * 257;
        final keyBytes = utf8.encode(longKey);
        expect(keyBytes.length, equals(257));

        final entry = StorageEntry.value(
          key: longKey,
          value: 'value',
          timestampMs: 1000,
          nodeId: 'node1',
          seq: 1,
        );

        expect(
          () => storage.put(longKey, entry),
          throwsA(isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('Key exceeds maximum size'),
          )),
        );
      });

      test('accepts key exactly 256 bytes UTF-8', () async {
        // Create a key that's exactly 256 bytes UTF-8
        final maxKey = 'a' * 256;
        final keyBytes = utf8.encode(maxKey);
        expect(keyBytes.length, equals(256));

        final entry = StorageEntry.value(
          key: maxKey,
          value: 'value',
          timestampMs: 1000,
          nodeId: 'node1',
          seq: 1,
        );

        // Should not throw
        await storage.put(maxKey, entry);
        final result = await storage.get(maxKey);
        expect(result?.value, equals('value'));
      });

      test('rejects value longer than 256KiB UTF-8', () async {
        // Create a value that's exactly 256KiB + 1 byte
        const maxValueBytes = 256 * 1024;
        final longValue = 'a' * (maxValueBytes + 1);
        final valueBytes = utf8.encode(longValue);
        expect(valueBytes.length, equals(maxValueBytes + 1));

        final entry = StorageEntry.value(
          key: 'key',
          value: longValue,
          timestampMs: 1000,
          nodeId: 'node1',
          seq: 1,
        );

        expect(
          () => storage.put('key', entry),
          throwsA(isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('Value exceeds maximum size'),
          )),
        );
      });

      test('accepts value exactly 256KiB UTF-8', () async {
        // Create a value that's exactly 256KiB bytes
        const maxValueBytes = 256 * 1024;
        final maxValue = 'a' * maxValueBytes;
        final valueBytes = utf8.encode(maxValue);
        expect(valueBytes.length, equals(maxValueBytes));

        final entry = StorageEntry.value(
          key: 'key',
          value: maxValue,
          timestampMs: 1000,
          nodeId: 'node1',
          seq: 1,
        );

        // Should not throw
        await storage.put('key', entry);
        final result = await storage.get('key');
        expect(result?.value, equals(maxValue));
      });

      test('handles multi-byte UTF-8 characters in key', () async {
        // Create key with multi-byte UTF-8 characters that's exactly 256 bytes
        // Each € character is 3 bytes in UTF-8
        final euroKey = '€' * 85 + 'a'; // 85 * 3 + 1 = 256 bytes
        final keyBytes = utf8.encode(euroKey);
        expect(keyBytes.length, equals(256));

        final entry = StorageEntry.value(
          key: euroKey,
          value: 'value',
          timestampMs: 1000,
          nodeId: 'node1',
          seq: 1,
        );

        // Should not throw
        await storage.put(euroKey, entry);
        final result = await storage.get(euroKey);
        expect(result?.value, equals('value'));
      });
    });

    group('Garbage Collection', () {
      setUp(() async {
        await storage.initialize();
      });

      test('removes expired tombstones', () async {
        final now = DateTime.now().millisecondsSinceEpoch;
        const twentyFiveHours = 25 * 60 * 60 * 1000;

        // Create an expired tombstone
        final expiredTombstone = StorageEntry.tombstone(
          key: 'expired-key',
          timestampMs: now - twentyFiveHours,
          nodeId: 'node1',
          seq: 1,
        );

        // Create a fresh tombstone
        final freshTombstone = StorageEntry.tombstone(
          key: 'fresh-key',
          timestampMs: now,
          nodeId: 'node1',
          seq: 2,
        );

        // Create a regular entry
        final regularEntry = StorageEntry.value(
          key: 'regular-key',
          value: 'value',
          timestampMs: now - twentyFiveHours, // Old but not a tombstone
          nodeId: 'node1',
          seq: 3,
        );

        await storage.put('expired-key', expiredTombstone);
        await storage.put('fresh-key', freshTombstone);
        await storage.put('regular-key', regularEntry);

        // Verify all entries exist before GC
        final entriesBeforeGC = await storage.getAllEntries();
        expect(entriesBeforeGC.length, equals(3));

        // Run garbage collection
        final removedCount = await storage.garbageCollectTombstones();

        // Should have removed 1 expired tombstone
        expect(removedCount, equals(1));

        // Verify entries after GC
        final entriesAfterGC = await storage.getAllEntries();
        expect(entriesAfterGC.length, equals(2));

        final remainingKeys = entriesAfterGC.map((e) => e.key).toSet();
        expect(remainingKeys, contains('fresh-key'));
        expect(remainingKeys, contains('regular-key'));
        expect(remainingKeys, isNot(contains('expired-key')));
      });

      test('returns zero when no tombstones to collect', () async {
        final entry = StorageEntry.value(
          key: 'regular-key',
          value: 'value',
          timestampMs: 1000,
          nodeId: 'node1',
          seq: 1,
        );

        await storage.put('regular-key', entry);

        final removedCount = await storage.garbageCollectTombstones();
        expect(removedCount, equals(0));
      });
    });

    group('Entry Validation', () {
      setUp(() async {
        await storage.initialize();
      });

      test('rejects entry with mismatched key', () async {
        final entry = StorageEntry.value(
          key: 'entry-key',
          value: 'value',
          timestampMs: 1000,
          nodeId: 'node1',
          seq: 1,
        );

        expect(
          () => storage.put('different-key', entry),
          throwsA(isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains(
                'Entry key "entry-key" does not match provided key "different-key"'),
          )),
        );
      });
    });

    group('Persistence (Minimal)', () {
      late InMemoryStorage persistentStorage;
      late MerkleKVConfig persistentConfig;

      setUp(() {
        persistentConfig = MerkleKVConfig.create(
          mqttHost: 'test-host',
          clientId: 'test-client',
          nodeId: 'test-node',
          persistenceEnabled: true,
        );
        persistentStorage = InMemoryStorage(persistentConfig);
      });

      tearDown(() async {
        await persistentStorage.dispose();
      });

      test('persists and loads entries across restarts', () async {
        // Initialize and store some entries
        await persistentStorage.initialize();

        final entry1 = StorageEntry.value(
          key: 'persistent-key-1',
          value: 'persistent-value-1',
          timestampMs: 1000,
          nodeId: 'node1',
          seq: 1,
        );

        final entry2 = StorageEntry.tombstone(
          key: 'persistent-key-2',
          timestampMs: 2000,
          nodeId: 'node1',
          seq: 2,
        );

        await persistentStorage.put('persistent-key-1', entry1);
        await persistentStorage.put('persistent-key-2', entry2);

        // Dispose to trigger persistence
        await persistentStorage.dispose();

        // Create new storage instance and initialize
        final newStorage = InMemoryStorage(persistentConfig);
        await newStorage.initialize();

        try {
          // Verify entries were loaded
          final loadedEntry1 = await newStorage.get('persistent-key-1');
          expect(loadedEntry1, equals(entry1));

          final loadedEntry2 = await newStorage.get('persistent-key-2');
          expect(loadedEntry2, isNull); // Tombstone should return null

          // But tombstone should exist in getAllEntries
          final allEntries = await newStorage.getAllEntries();
          final tombstone =
              allEntries.firstWhere((e) => e.key == 'persistent-key-2');
          expect(tombstone.isTombstone, isTrue);
        } finally {
          await newStorage.dispose();
        }
      });

      test('applies LWW resolution during loading', () async {
        // Initialize storage and manually create persistence file with conflicting entries
        await persistentStorage.initialize();
        await persistentStorage.dispose();

        // Manually create persistence file with entries that conflict
        final storageDir = Directory('./storage');
        await storageDir.create(recursive: true);
        final persistenceFile = File('./storage/merkle_kv_storage.jsonl');

        final olderEntry = StorageEntry.value(
          key: 'conflict-key',
          value: 'older-value',
          timestampMs: 1000,
          nodeId: 'node1',
          seq: 1,
        );

        final newerEntry = StorageEntry.value(
          key: 'conflict-key',
          value: 'newer-value',
          timestampMs: 2000,
          nodeId: 'node1',
          seq: 2,
        );

        // Write both entries to file (older first, then newer)
        final tempStorage = InMemoryStorage(persistentConfig);
        await tempStorage.initialize();
        await tempStorage.put('conflict-key', olderEntry);
        await tempStorage.put('conflict-key', newerEntry);
        await tempStorage.dispose();

        // Now create new storage and load - should have newer entry
        final newStorage = InMemoryStorage(persistentConfig);
        await newStorage.initialize();

        try {
          final result = await newStorage.get('conflict-key');
          expect(result?.value, equals('newer-value'));
          expect(result?.timestampMs, equals(2000));
        } finally {
          await newStorage.dispose();
        }
      });
    });
  });
}
