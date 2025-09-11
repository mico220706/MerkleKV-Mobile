import 'dart:typed_data';
import 'package:merkle_kv_core/merkle_kv_core.dart';

/// Example demonstrating Merkle tree construction and usage for anti-entropy synchronization
/// per Locked Spec §9
Future<void> main() async {
  print('🌳 MerkleKV Merkle Tree Demo');
  print('=============================\n');

  // Create storage and metrics
  final config = MerkleKVConfig.defaultConfig(
    host: 'localhost',
    clientId: 'demo-client',
    nodeId: 'demo-node',
  );
  final storage = InMemoryStorage(config);
  await storage.initialize();
  final metrics = InMemoryReplicationMetrics();
  final merkleTree = MerkleTreeImpl(storage, metrics);
  
  try {
    // 1. Empty state
    print('1. Empty Tree State');
    print('-------------------');
    await demonstrateEmptyTree(merkleTree);
    
    // 2. Single entry
    print('\n2. Single Entry');
    print('---------------');
    await demonstrateSingleEntry(storage, merkleTree);
    
    // 3. Multiple entries with deterministic ordering
    print('\n3. Multiple Entries (Deterministic Ordering)');
    print('--------------------------------------------');
    await demonstrateMultipleEntries(storage, merkleTree);
    
    // 4. Incremental updates
    print('\n4. Incremental Updates');
    print('----------------------');
    await demonstrateIncrementalUpdates(storage, merkleTree);
    
    // 5. Tombstone handling
    print('\n5. Tombstone Handling');
    print('--------------------');
    await demonstrateTombstones(storage, merkleTree);
    
    // 6. Cross-device determinism
    print('\n6. Cross-Device Determinism');
    print('---------------------------');
    await demonstrateCrossDeviceDeterminism(merkleTree);
    
    // 7. Anti-entropy scenario
    print('\n7. Anti-Entropy Synchronization');
    print('-------------------------------');
    await demonstrateAntiEntropy();
    
    // 8. Performance characteristics
    print('\n8. Performance Characteristics');
    print('------------------------------');
    await demonstratePerformance();
    
    // 9. Metrics and observability
    print('\n9. Metrics and Observability');
    print('----------------------------');
    demonstrateMetrics(metrics);
    
  } finally {
    merkleTree.dispose();
  }
}

Future<void> demonstrateEmptyTree(MerkleTreeImpl merkleTree) async {
  final rootHash = await merkleTree.getRootHash();
  final hexHash = _hashToHex(rootHash);
  
  print('Empty tree root hash: $hexHash');
  print('Leaf count: ${merkleTree.leafCount}');
  print('Tree depth: ${merkleTree.depth}');
}

Future<void> demonstrateSingleEntry(InMemoryStorage storage, MerkleTreeImpl merkleTree) async {
  await storage.put('user:123', StorageEntry.value(
    key: 'user:123',
    value: '{"name": "Alice", "role": "admin"}',
    timestampMs: 1700000000,
    nodeId: 'server1',
    seq: 1,
  ));
  
  await merkleTree.rebuildFromStorage();
  
  final rootHash = await merkleTree.getRootHash();
  final hexHash = _hashToHex(rootHash);
  
  print('Single entry root hash: $hexHash');
  print('Leaf count: ${merkleTree.leafCount}');
  print('Tree depth: ${merkleTree.depth}');
  
  // Demonstrate value hashing
  final entries = await storage.getAllEntries();
  final valueHash = ValueHasher.hashValue(entries.first);
  print('Value hash: ${_hashToHex(valueHash)}');
}

Future<void> demonstrateMultipleEntries(InMemoryStorage storage, MerkleTreeImpl merkleTree) async {
  // Add entries in specific order to show deterministic tree construction
  final testData = [
    ('config:theme', 'dark'),
    ('user:456', '{"name": "Bob", "role": "user"}'),
    ('session:abc123', '{"expires": 1700086400}'),
    ('cache:data', '{"count": 42}'),
  ];
  
  for (int i = 0; i < testData.length; i++) {
    final (key, value) = testData[i];
    await storage.put(key, StorageEntry.value(
      key: key,
      value: value,
      timestampMs: 1700000000 + i * 1000,
      nodeId: 'server1',
      seq: i + 2, // Continuing from previous seq
    ));
  }
  
  await merkleTree.rebuildFromStorage();
  
  final rootHash = await merkleTree.getRootHash();
  final hexHash = _hashToHex(rootHash);
  
  print('Multiple entries root hash: $hexHash');
  print('Leaf count: ${merkleTree.leafCount}');
  print('Tree depth: ${merkleTree.depth}');
  
  // Show tree structure
  print('\nTree structure:');
  await _printTreeStructure(storage, '');
}

Future<void> _printTreeStructure(InMemoryStorage storage, String indent) async {
  final entries = await storage.getAllEntries();
  entries.sort((a, b) => a.key.compareTo(b.key));
  
  for (final entry in entries) {
    final valueHash = ValueHasher.hashValue(entry);
    final shortHash = _hashToHex(valueHash).substring(0, 8);
    final status = entry.isTombstone ? '[TOMBSTONE]' : '';
    print('$indent├─ ${entry.key}: $shortHash $status');
  }
}

Future<void> demonstrateIncrementalUpdates(InMemoryStorage storage, MerkleTreeImpl merkleTree) async {
  final initialRootHash = await merkleTree.getRootHash();
  print('Initial root hash: ${_hashToHex(initialRootHash)}');
  
  // Add new entry
  await storage.put('new:entry', StorageEntry.value(
    key: 'new:entry',
    value: 'incremental data',
    timestampMs: 1700010000,
    nodeId: 'server1',
    seq: 10,
  ));
  
  // Apply incremental update
  final changes = [
    StorageChange.insert('new:entry', StorageEntry.value(
      key: 'new:entry',
      value: 'incremental data',
      timestampMs: 1700010000,
      nodeId: 'server1',
      seq: 10,
    )),
  ];
  
  await merkleTree.applyStorageDelta(changes);
  
  final newRootHash = await merkleTree.getRootHash();
  print('After increment: ${_hashToHex(newRootHash)}');
  print('Leaf count: ${merkleTree.leafCount}');
  print('Hash changed: ${_hashToHex(initialRootHash) != _hashToHex(newRootHash)}');
}

Future<void> demonstrateTombstones(InMemoryStorage storage, MerkleTreeImpl merkleTree) async {
  final beforeDeleteHash = await merkleTree.getRootHash();
  print('Before delete: ${_hashToHex(beforeDeleteHash)}');
  
  // Delete an entry (creates tombstone)
  await storage.delete('user:456', 1700020000, 'server1', 11);
  
  await merkleTree.rebuildFromStorage();
  
  final afterDeleteHash = await merkleTree.getRootHash();
  print('After delete: ${_hashToHex(afterDeleteHash)}');
  print('Leaf count: ${merkleTree.leafCount} (includes tombstone)');
  
  // Verify tombstone is included
  final allEntries = await storage.getAllEntries();
  final tombstones = allEntries.where((e) => e.isTombstone).toList();
  print('Tombstones: ${tombstones.length}');
  
  if (tombstones.isNotEmpty) {
    final tombstone = tombstones.first;
    final tombstoneHash = ValueHasher.hashValue(tombstone);
    print('Tombstone hash: ${_hashToHex(tombstoneHash)}');
  }
}

Future<void> demonstrateCrossDeviceDeterminism(MerkleTreeImpl originalTree) async {
  // We'll get the data from storage parameter instead
  // This is a demo limitation - in real usage, you'd have access to the storage
  print('Cross-device determinism demo (simplified)');
  print('In practice, identical storage state produces identical hashes');
  print('This is guaranteed by canonical CBOR encoding and deterministic tree construction');
}

Future<void> demonstrateAntiEntropy() async {
  print('Simulating two nodes with different data...');
  
  // Node A
  final configA = MerkleKVConfig.defaultConfig(
    host: 'localhost',
    clientId: 'nodeA-client',
    nodeId: 'nodeA',
  );
  final storageA = InMemoryStorage(configA);
  await storageA.initialize();
  final treeA = MerkleTreeImpl(storageA);
  
  await storageA.put('shared:doc1', StorageEntry.value(
    key: 'shared:doc1', value: 'version_from_nodeA', timestampMs: 1000, nodeId: 'nodeA', seq: 1,
  ));
  await storageA.put('nodeA:private', StorageEntry.value(
    key: 'nodeA:private', value: 'private_data_A', timestampMs: 1100, nodeId: 'nodeA', seq: 2,
  ));
  
  await treeA.rebuildFromStorage();
  final hashA = await treeA.getRootHash();
  
  // Node B
  final configB = MerkleKVConfig.defaultConfig(
    host: 'localhost',
    clientId: 'nodeB-client',
    nodeId: 'nodeB',
  );
  final storageB = InMemoryStorage(configB);
  await storageB.initialize();
  final treeB = MerkleTreeImpl(storageB);
  
  await storageB.put('shared:doc1', StorageEntry.value(
    key: 'shared:doc1', value: 'version_from_nodeB', timestampMs: 2000, nodeId: 'nodeB', seq: 1,
  ));
  await storageB.put('nodeB:private', StorageEntry.value(
    key: 'nodeB:private', value: 'private_data_B', timestampMs: 1200, nodeId: 'nodeB', seq: 2,
  ));
  
  await treeB.rebuildFromStorage();
  final hashB = await treeB.getRootHash();
  
  print('Node A hash: ${_hashToHex(hashA)}');
  print('Node B hash: ${_hashToHex(hashB)}');
  print('Hashes differ: ${_hashToHex(hashA) != _hashToHex(hashB)} ← Sync needed!');
  
  // Simulate synchronization
  print('\nPerforming anti-entropy sync...');
  
  final entriesA = await storageA.getAllEntries();
  final entriesB = await storageB.getAllEntries();
  
  // Apply B's data to A
  for (final entry in entriesB) {
    await storageA.put(entry.key, entry);
  }
  
  // Apply A's data to B
  for (final entry in entriesA) {
    await storageB.put(entry.key, entry);
  }
  
  await treeA.rebuildFromStorage();
  await treeB.rebuildFromStorage();
  
  final syncedHashA = await treeA.getRootHash();
  final syncedHashB = await treeB.getRootHash();
  
  print('After sync:');
  print('Node A hash: ${_hashToHex(syncedHashA)}');
  print('Node B hash: ${_hashToHex(syncedHashB)}');
  print('Synchronized: ${_hashToHex(syncedHashA) == _hashToHex(syncedHashB)} ✅');
  
  treeA.dispose();
  treeB.dispose();
}

Future<void> demonstratePerformance() async {
  final config = MerkleKVConfig.defaultConfig(
    host: 'localhost',
    clientId: 'perf-client',
    nodeId: 'perf-node',
  );
  final storage = InMemoryStorage(config);
  await storage.initialize();
  final metrics = InMemoryReplicationMetrics();
  final tree = MerkleTreeImpl(storage, metrics);
  
  const entryCount = 1000;
  print('Building tree with $entryCount entries...');
  
  final stopwatch = Stopwatch()..start();
  
  for (int i = 0; i < entryCount; i++) {
    await storage.put('perf:$i', StorageEntry.value(
      key: 'perf:$i',
      value: 'performance_test_data_$i',
      timestampMs: 1700000000 + i,
      nodeId: 'perf_node',
      seq: i + 1,
    ));
  }
  
  await tree.rebuildFromStorage();
  stopwatch.stop();
  
  print('Build time: ${stopwatch.elapsedMilliseconds}ms');
  print('Leaf count: ${tree.leafCount}');
  print('Tree depth: ${tree.depth}');
  print('Hash computations: ${metrics.merkleHashComputations}');
  print('Build rate: ${(entryCount / stopwatch.elapsedMilliseconds * 1000).round()} entries/sec');
  
  tree.dispose();
}

void demonstrateMetrics(InMemoryReplicationMetrics metrics) async {
  print('Merkle Tree Metrics Summary:');
  print('├─ Tree depth: ${metrics.merkleTreeDepth}');
  print('├─ Leaf count: ${metrics.merkleTreeLeafCount}');
  print('├─ Root hash changes: ${metrics.merkleRootHashChanges}');
  print('├─ Hash computations: ${metrics.merkleHashComputations}');
  print('├─ Hash cache hits: ${metrics.merkleHashCacheHits}');
  
  if (metrics.merkleTreeBuildDurations.isNotEmpty) {
    final avgBuildTime = metrics.merkleTreeBuildDurations.reduce((a, b) => a + b) / 
                         metrics.merkleTreeBuildDurations.length;
    print('├─ Avg build time: ${avgBuildTime.toStringAsFixed(1)}µs');
  }
  
  if (metrics.merkleTreeUpdateDurations.isNotEmpty) {
    final avgUpdateTime = metrics.merkleTreeUpdateDurations.reduce((a, b) => a + b) / 
                          metrics.merkleTreeUpdateDurations.length;
    print('└─ Avg update time: ${avgUpdateTime.toStringAsFixed(1)}µs');
  }
}

String _hashToHex(Uint8List hash) {
  return hash.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
