import 'package:test/test.dart';
import 'package:merkle_kv_core/src/storage/storage_entry.dart';

void main() {
  group('StorageEntry', () {
    group('Construction', () {
      test('creates regular entry with value', () {
        final entry = StorageEntry.value(
          key: 'test-key',
          value: 'test-value',
          timestampMs: 1000,
          nodeId: 'node1',
          seq: 1,
        );

        expect(entry.key, equals('test-key'));
        expect(entry.value, equals('test-value'));
        expect(entry.timestampMs, equals(1000));
        expect(entry.nodeId, equals('node1'));
        expect(entry.seq, equals(1));
        expect(entry.isTombstone, isFalse);
      });

      test('creates tombstone entry', () {
        final entry = StorageEntry.tombstone(
          key: 'deleted-key',
          timestampMs: 2000,
          nodeId: 'node2',
          seq: 5,
        );

        expect(entry.key, equals('deleted-key'));
        expect(entry.value, isNull);
        expect(entry.timestampMs, equals(2000));
        expect(entry.nodeId, equals('node2'));
        expect(entry.seq, equals(5));
        expect(entry.isTombstone, isTrue);
      });
    });

    group('Last-Write-Wins Resolution', () {
      test('newer timestamp wins', () {
        final older = StorageEntry.value(
          key: 'key',
          value: 'old',
          timestampMs: 1000,
          nodeId: 'node1',
          seq: 1,
        );

        final newer = StorageEntry.value(
          key: 'key',
          value: 'new',
          timestampMs: 2000,
          nodeId: 'node1',
          seq: 2,
        );

        expect(newer.winsOver(older), isTrue);
        expect(older.winsOver(newer), isFalse);
        expect(newer.compareVersions(older), greaterThan(0));
        expect(older.compareVersions(newer), lessThan(0));
      });

      test('nodeId tiebreaker when timestamps equal', () {
        final entryA = StorageEntry.value(
          key: 'key',
          value: 'valueA',
          timestampMs: 1000,
          nodeId: 'nodeA',
          seq: 1,
        );

        final entryZ = StorageEntry.value(
          key: 'key',
          value: 'valueZ',
          timestampMs: 1000,
          nodeId: 'nodeZ',
          seq: 1,
        );

        // nodeZ > nodeA lexicographically
        expect(entryZ.winsOver(entryA), isTrue);
        expect(entryA.winsOver(entryZ), isFalse);
        expect(entryZ.compareVersions(entryA), greaterThan(0));
        expect(entryA.compareVersions(entryZ), lessThan(0));
      });

      test('equivalent version vectors are detected', () {
        final entry1 = StorageEntry.value(
          key: 'key',
          value: 'value1',
          timestampMs: 1000,
          nodeId: 'node1',
          seq: 1,
        );

        final entry2 = StorageEntry.value(
          key: 'key',
          value: 'value2', // Different value but same version vector
          timestampMs: 1000,
          nodeId: 'node1',
          seq: 1,
        );

        expect(entry1.isEquivalentTo(entry2), isTrue);
        expect(entry2.isEquivalentTo(entry1), isTrue);
        expect(entry1.compareVersions(entry2), equals(0));
        expect(entry2.compareVersions(entry1), equals(0));
        expect(entry1.winsOver(entry2), isFalse);
        expect(entry2.winsOver(entry1), isFalse);
      });
    });

    group('Tombstone Management', () {
      test('fresh tombstone is not expired', () {
        final now = DateTime.now().millisecondsSinceEpoch;
        final tombstone = StorageEntry.tombstone(
          key: 'key',
          timestampMs: now,
          nodeId: 'node1',
          seq: 1,
        );

        expect(tombstone.isExpiredTombstone(), isFalse);
      });

      test('old tombstone is expired', () {
        final now = DateTime.now().millisecondsSinceEpoch;
        const twentyFiveHours = 25 * 60 * 60 * 1000; // 25 hours in ms
        final oldTimestamp = now - twentyFiveHours;

        final tombstone = StorageEntry.tombstone(
          key: 'key',
          timestampMs: oldTimestamp,
          nodeId: 'node1',
          seq: 1,
        );

        expect(tombstone.isExpiredTombstone(), isTrue);
      });

      test('regular entry is never expired tombstone', () {
        final now = DateTime.now().millisecondsSinceEpoch;
        const twentyFiveHours = 25 * 60 * 60 * 1000;
        final oldTimestamp = now - twentyFiveHours;

        final entry = StorageEntry.value(
          key: 'key',
          value: 'value',
          timestampMs: oldTimestamp,
          nodeId: 'node1',
          seq: 1,
        );

        expect(entry.isExpiredTombstone(), isFalse);
      });
    });

    group('JSON Serialization', () {
      test('serializes and deserializes regular entry', () {
        final original = StorageEntry.value(
          key: 'test-key',
          value: 'test-value',
          timestampMs: 1234567890,
          nodeId: 'node-123',
          seq: 42,
        );

        final json = original.toJson();
        final restored = StorageEntry.fromJson(json);

        expect(restored, equals(original));
        expect(restored.key, equals(original.key));
        expect(restored.value, equals(original.value));
        expect(restored.timestampMs, equals(original.timestampMs));
        expect(restored.nodeId, equals(original.nodeId));
        expect(restored.seq, equals(original.seq));
        expect(restored.isTombstone, equals(original.isTombstone));
      });

      test('serializes and deserializes tombstone entry', () {
        final original = StorageEntry.tombstone(
          key: 'deleted-key',
          timestampMs: 9876543210,
          nodeId: 'node-xyz',
          seq: 99,
        );

        final json = original.toJson();
        final restored = StorageEntry.fromJson(json);

        expect(restored, equals(original));
        expect(restored.key, equals(original.key));
        expect(restored.value, isNull);
        expect(restored.timestampMs, equals(original.timestampMs));
        expect(restored.nodeId, equals(original.nodeId));
        expect(restored.seq, equals(original.seq));
        expect(restored.isTombstone, isTrue);
      });
    });

    group('Equality and Hash Code', () {
      test('entries with same values are equal', () {
        final entry1 = StorageEntry.value(
          key: 'key',
          value: 'value',
          timestampMs: 1000,
          nodeId: 'node1',
          seq: 1,
        );

        final entry2 = StorageEntry.value(
          key: 'key',
          value: 'value',
          timestampMs: 1000,
          nodeId: 'node1',
          seq: 1,
        );

        expect(entry1, equals(entry2));
        expect(entry1.hashCode, equals(entry2.hashCode));
      });

      test('entries with different values are not equal', () {
        final entry1 = StorageEntry.value(
          key: 'key',
          value: 'value1',
          timestampMs: 1000,
          nodeId: 'node1',
          seq: 1,
        );

        final entry2 = StorageEntry.value(
          key: 'key',
          value: 'value2',
          timestampMs: 1000,
          nodeId: 'node1',
          seq: 1,
        );

        expect(entry1, isNot(equals(entry2)));
      });
    });
  });
}
