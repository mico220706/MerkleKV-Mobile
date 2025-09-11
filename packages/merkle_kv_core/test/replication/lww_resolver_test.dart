import 'package:test/test.dart';
import '../../lib/src/replication/lww_resolver.dart';
import '../../lib/src/storage/storage_entry.dart';

void main() {
  group('LWWResolver', () {
    late LWWResolver resolver;

    setUp(() {
      resolver = LWWResolverImpl();
    });

    group('compare', () {
      test('local wins with newer timestamp', () {
        final local = StorageEntry.value(
          key: 'test',
          value: 'local',
          timestampMs: 2000,
          nodeId: 'node1',
          seq: 1,
        );
        final remote = StorageEntry.value(
          key: 'test',
          value: 'remote',
          timestampMs: 1000,
          nodeId: 'node2',
          seq: 1,
        );

        final result = resolver.compare(local, remote);
        expect(result, ComparisonResult.localWins);
      });

      test('remote wins with newer timestamp', () {
        final local = StorageEntry.value(
          key: 'test',
          value: 'local',
          timestampMs: 1000,
          nodeId: 'node1',
          seq: 1,
        );
        final remote = StorageEntry.value(
          key: 'test',
          value: 'remote',
          timestampMs: 2000,
          nodeId: 'node2',
          seq: 1,
        );

        final result = resolver.compare(local, remote);
        expect(result, ComparisonResult.remoteWins);
      });

      test('uses node_id as tiebreaker when timestamps equal', () {
        final local = StorageEntry.value(
          key: 'test',
          value: 'local',
          timestampMs: 1000,
          nodeId: 'node2',
          seq: 1,
        );
        final remote = StorageEntry.value(
          key: 'test',
          value: 'remote',
          timestampMs: 1000,
          nodeId: 'node1',
          seq: 1,
        );

        final result = resolver.compare(local, remote);
        expect(result, ComparisonResult.localWins); // node2 > node1
      });

      test('detects duplicate entries', () {
        final local = StorageEntry.value(
          key: 'test',
          value: 'same_value',
          timestampMs: 1000,
          nodeId: 'node1',
          seq: 1,
        );
        final remote = StorageEntry.value(
          key: 'test',
          value: 'same_value',
          timestampMs: 1000,
          nodeId: 'node1',
          seq: 1,
        );

        final result = resolver.compare(local, remote);
        expect(result, ComparisonResult.duplicate);
      });
    });

    group('selectWinner', () {
      test('returns local when local wins', () {
        final local = StorageEntry.value(
          key: 'test',
          value: 'local',
          timestampMs: 2000,
          nodeId: 'node1',
          seq: 1,
        );
        final remote = StorageEntry.value(
          key: 'test',
          value: 'remote',
          timestampMs: 1000,
          nodeId: 'node2',
          seq: 1,
        );

        final winner = resolver.selectWinner(local, remote);
        expect(winner, local);
      });

      test('returns remote when remote wins', () {
        final local = StorageEntry.value(
          key: 'test',
          value: 'local',
          timestampMs: 1000,
          nodeId: 'node1',
          seq: 1,
        );
        final remote = StorageEntry.value(
          key: 'test',
          value: 'remote',
          timestampMs: 2000,
          nodeId: 'node2',
          seq: 1,
        );

        final winner = resolver.selectWinner(local, remote);
        expect(winner, remote);
      });
    });

    group('clampTimestamp', () {
      test('clamps future timestamps to 5 minutes max', () {
        final now = DateTime.now().millisecondsSinceEpoch;
        final farFuture = now + (10 * 60 * 1000); // 10 minutes in future
        
        final clamped = resolver.clampTimestamp(farFuture);
        final maxAllowed = now + (5 * 60 * 1000); // 5 minutes max
        
        expect(clamped, lessThanOrEqualTo(maxAllowed));
      });

      test('preserves past and near-future timestamps', () {
        final now = DateTime.now().millisecondsSinceEpoch;
        final nearFuture = now + (2 * 60 * 1000); // 2 minutes in future
        
        final clamped = resolver.clampTimestamp(nearFuture);
        expect(clamped, nearFuture);
      });

      test('preserves past timestamps', () {
        final now = DateTime.now().millisecondsSinceEpoch;
        final past = now - (60 * 1000); // 1 minute ago
        
        final clamped = resolver.clampTimestamp(past);
        expect(clamped, past);
      });
    });
  });
}
