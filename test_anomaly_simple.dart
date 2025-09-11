import 'packages/merkle_kv_core/lib/src/replication/event_applicator.dart';
import 'packages/merkle_kv_core/lib/src/replication/metrics.dart';
import 'packages/merkle_kv_core/lib/src/storage/in_memory_storage.dart';
import 'packages/merkle_kv_core/lib/src/replication/lww_resolver.dart';
import 'packages/merkle_kv_core/lib/src/replication/event_applicator.dart';
import 'packages/merkle_kv_core/lib/src/models/response_models.dart';

void main() async {
  // Setup
  final storage = InMemoryStorage();
  final metrics = InMemoryReplicationMetrics();
  final lwwResolver = LWWResolverImpl();
  final applicator = ReplicationEventApplicator(
    storage: storage,
    metrics: metrics,
    lwwResolver: lwwResolver,
  );

  print('Testing timestamp anomaly detection...');

  // Test case: same timestamp + nodeId but different content
  final event1 = ReplicationEvent.value(
    key: 'test-key',
    nodeId: 'node-1',
    seq: 1,
    timestampMs: 1000,
    value: 'value1',
  );
  await applicator.applyEvent(event1);
  print('Event 1 applied. Applied: ${metrics.eventsApplied}, Conflicts: ${metrics.conflictsResolved}');

  final event2 = ReplicationEvent.value(
    key: 'test-key',
    nodeId: 'node-1',
    seq: 2,
    timestampMs: 1000, // Same timestamp
    value: 'value2', // Different content
  );
  await applicator.applyEvent(event2);
  print('Event 2 applied. Applied: ${metrics.eventsApplied}, Conflicts: ${metrics.conflictsResolved}');

  final stored = await storage.get('test-key');
  print('Final stored value: ${stored?.value}');
  print('Expected conflicts resolved: 1, Actual: ${metrics.conflictsResolved}');
  
  if (metrics.conflictsResolved == 1) {
    print('✅ TEST PASSED: Timestamp anomaly correctly detected!');
  } else {
    print('❌ TEST FAILED: Expected 1 conflict, got ${metrics.conflictsResolved}');
  }
}
