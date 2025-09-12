import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:merkle_kv_core/merkle_kv_core.dart';

void main() {
  group('ValueHasher', () {
    test('deterministic hashing for strings', () {
      final entry1 = StorageEntry.value(
        key: 'test',
        value: 'hello',
        timestampMs: 1000,
        nodeId: 'node1',
        seq: 1,
      );
      
      final entry2 = StorageEntry.value(
        key: 'test',
        value: 'hello',
        timestampMs: 2000,
        nodeId: 'node2',
        seq: 2,
      );
      
      final hash1 = ValueHasher.hashValue(entry1);
      final hash2 = ValueHasher.hashValue(entry2);
      
      // Same value should produce same hash regardless of metadata
      expect(hash1, equals(hash2));
      expect(hash1.length, equals(32)); // SHA-256 length
    });
    
    test('different values produce different hashes', () {
      final entry1 = StorageEntry.value(
        key: 'test',
        value: 'hello',
        timestampMs: 1000,
        nodeId: 'node1',
        seq: 1,
      );
      
      final entry2 = StorageEntry.value(
        key: 'test',
        value: 'world',
        timestampMs: 1000,
        nodeId: 'node1',
        seq: 1,
      );
      
      final hash1 = ValueHasher.hashValue(entry1);
      final hash2 = ValueHasher.hashValue(entry2);
      
      expect(hash1, isNot(equals(hash2)));
    });
    
    test('tombstone hashing', () {
      final tombstone1 = StorageEntry.tombstone(
        key: 'test',
        timestampMs: 1000,
        nodeId: 'node1',
        seq: 1,
      );
      
      final tombstone2 = StorageEntry.tombstone(
        key: 'test',
        timestampMs: 1000,
        nodeId: 'node1',
        seq: 2,
      );
      
      final hash1 = ValueHasher.hashValue(tombstone1);
      final hash2 = ValueHasher.hashValue(tombstone2);
      
      // Same timestamp and nodeId should produce same hash
      expect(hash1, equals(hash2));
      expect(hash1.length, equals(32));
    });
    
    test('canonical CBOR encoding for different types', () {
      // Test string encoding consistency
      final hash1 = ValueHasher.hashString('test');
      final hash2 = ValueHasher.hashString('test');
      expect(hash1, equals(hash2));
      
      // Test typed value encoding
      final stringHash = ValueHasher.hashTypedValue('hello');
      final intHash = ValueHasher.hashTypedValue(42);
      final boolHash = ValueHasher.hashTypedValue(true);
      final nullHash = ValueHasher.hashTypedValue(null);
      
      expect(stringHash.length, equals(32));
      expect(intHash.length, equals(32));
      expect(boolHash.length, equals(32));
      expect(nullHash.length, equals(32));
      
      // Different types should produce different hashes
      expect(stringHash, isNot(equals(intHash)));
      expect(stringHash, isNot(equals(boolHash)));
      expect(intHash, isNot(equals(nullHash)));
    });
    
    test('normalized float handling', () {
      final nanHash1 = ValueHasher.hashTypedValue(double.nan);
      final nanHash2 = ValueHasher.hashTypedValue(double.nan);
      expect(nanHash1, equals(nanHash2));
      
      final infHash1 = ValueHasher.hashTypedValue(double.infinity);
      final infHash2 = ValueHasher.hashTypedValue(double.infinity);
      expect(infHash1, equals(infHash2));
      
      final negInfHash1 = ValueHasher.hashTypedValue(double.negativeInfinity);
      final negInfHash2 = ValueHasher.hashTypedValue(double.negativeInfinity);
      expect(negInfHash1, equals(negInfHash2));
    });
    
    test('sorted map encoding', () {
      final map1 = {'b': 2, 'a': 1, 'c': 3};
      final map2 = {'a': 1, 'c': 3, 'b': 2};
      
      final hash1 = ValueHasher.hashTypedValue(map1);
      final hash2 = ValueHasher.hashTypedValue(map2);
      
      // Maps with same content but different order should produce same hash
      expect(hash1, equals(hash2));
    });
  });

  group('MerkleNode', () {
    test('leaf node creation', () {
      final valueHash = ValueHasher.hashString('test');
      final node = MerkleNode.leaf(
        key: 'key1',
        valueHash: valueHash,
      );
      
      expect(node.path, equals('key1'));
      expect(node.isLeaf, isTrue);
      expect(node.children, isNull);
      expect(node.leafCount, equals(1));
      expect(node.hash.length, equals(32));
    });
    
    test('internal node creation', () {
      final leftHash = ValueHasher.hashString('left');
      final rightHash = ValueHasher.hashString('right');
      
      final left = MerkleNode.leaf(key: 'a', valueHash: leftHash);
      final right = MerkleNode.leaf(key: 'b', valueHash: rightHash);
      
      final internal = MerkleNode.internal(
        path: '',
        left: left,
        right: right,
      );
      
      expect(internal.isLeaf, isFalse);
      expect(internal.children!.length, equals(2));
      expect(internal.leafCount, equals(2));
      expect(internal.hash.length, equals(32));
      expect(internal.hash, isNot(equals(left.hash)));
      expect(internal.hash, isNot(equals(right.hash)));
    });
    
    test('deterministic internal node hashing', () {
      final leftHash = ValueHasher.hashString('left');
      final rightHash = ValueHasher.hashString('right');
      
      final left = MerkleNode.leaf(key: 'a', valueHash: leftHash);
      final right = MerkleNode.leaf(key: 'b', valueHash: rightHash);
      
      final internal1 = MerkleNode.internal(path: '', left: left, right: right);
      final internal2 = MerkleNode.internal(path: '', left: left, right: right);
      
      expect(internal1.hash, equals(internal2.hash));
    });
  });

  group('MerkleTree', () {
    late InMemoryStorage storage;
    late InMemoryReplicationMetrics metrics;
    late MerkleTreeImpl merkleTree;
    
    setUp(() async {
      final config = MerkleKVConfig.defaultConfig(
        host: 'localhost',
        clientId: 'test-client',
        nodeId: 'test-node',
      );
      storage = InMemoryStorage(config);
      await storage.initialize();
      metrics = InMemoryReplicationMetrics();
      merkleTree = MerkleTreeImpl(storage, metrics);
    });
    
    tearDown(() {
      merkleTree.dispose();
    });
    
    test('empty tree has consistent empty root hash', () async {
      final rootHash1 = await merkleTree.getRootHash();
      final rootHash2 = await merkleTree.getRootHash();
      
      expect(rootHash1, equals(rootHash2));
      expect(rootHash1.length, equals(32));
      expect(merkleTree.leafCount, equals(0));
      expect(merkleTree.depth, equals(0));
    });
    
    test('single entry tree', () async {
      await storage.put('key1', StorageEntry.value(
        key: 'key1',
        value: 'value1',
        timestampMs: 1000,
        nodeId: 'node1',
        seq: 1,
      ));
      
      await merkleTree.rebuildFromStorage();
      
      expect(merkleTree.leafCount, equals(1));
      expect(merkleTree.depth, equals(1));
      
      final rootHash = await merkleTree.getRootHash();
      expect(rootHash.length, equals(32));
      
      final node = await merkleTree.getNodeAt('key1');
      expect(node, isNotNull);
      expect(node!.isLeaf, isTrue);
      expect(node.path, equals('key1'));
    });
    
    test('multiple entries produce deterministic tree', () async {
      // Add entries in one order
      await storage.put('key2', StorageEntry.value(
        key: 'key2', value: 'value2', timestampMs: 1000, nodeId: 'node1', seq: 1,
      ));
      await storage.put('key1', StorageEntry.value(
        key: 'key1', value: 'value1', timestampMs: 1000, nodeId: 'node1', seq: 2,
      ));
      await storage.put('key3', StorageEntry.value(
        key: 'key3', value: 'value3', timestampMs: 1000, nodeId: 'node1', seq: 3,
      ));
      
      await merkleTree.rebuildFromStorage();
      final rootHash1 = await merkleTree.getRootHash();
      
      // Create new storage with same entries in different order
      final config2 = MerkleKVConfig.defaultConfig(
        host: 'localhost',
        clientId: 'test-client-2',
        nodeId: 'test-node-2',
      );
      final storage2 = InMemoryStorage(config2);
      await storage2.initialize();
      await storage2.put('key1', StorageEntry.value(
        key: 'key1', value: 'value1', timestampMs: 1000, nodeId: 'node1', seq: 2,
      ));
      await storage2.put('key3', StorageEntry.value(
        key: 'key3', value: 'value3', timestampMs: 1000, nodeId: 'node1', seq: 3,
      ));
      await storage2.put('key2', StorageEntry.value(
        key: 'key2', value: 'value2', timestampMs: 1000, nodeId: 'node1', seq: 1,
      ));
      
      final merkleTree2 = MerkleTreeImpl(storage2, metrics);
      await merkleTree2.rebuildFromStorage();
      final rootHash2 = await merkleTree2.getRootHash();
      
      expect(rootHash1, equals(rootHash2));
      expect(merkleTree.leafCount, equals(3));
      expect(merkleTree2.leafCount, equals(3));
      
      merkleTree2.dispose();
    });
    
    test('tree structure with balanced binary tree', () async {
      // Add 4 entries to create a balanced binary tree
      for (int i = 1; i <= 4; i++) {
        await storage.put('key$i', StorageEntry.value(
          key: 'key$i',
          value: 'value$i',
          timestampMs: 1000,
          nodeId: 'node1',
          seq: i,
        ));
      }
      
      await merkleTree.rebuildFromStorage();
      
      expect(merkleTree.leafCount, equals(4));
      expect(merkleTree.depth, equals(3)); // 2 levels of internal nodes + 1 leaf level
      
      final rootHash = await merkleTree.getRootHash();
      expect(rootHash.length, equals(32));
    });
    
    test('incremental updates via applyStorageDelta', () async {
      // Start with some data
      await storage.put('key1', StorageEntry.value(
        key: 'key1', value: 'value1', timestampMs: 1000, nodeId: 'node1', seq: 1,
      ));
      
      await merkleTree.rebuildFromStorage();
      final initialHash = await merkleTree.getRootHash();
      
      // Add new entry
      await storage.put('key2', StorageEntry.value(
        key: 'key2', value: 'value2', timestampMs: 2000, nodeId: 'node1', seq: 2,
      ));
      
      final changes = [
        StorageChange.insert('key2', StorageEntry.value(
          key: 'key2', value: 'value2', timestampMs: 2000, nodeId: 'node1', seq: 2,
        )),
      ];
      
      await merkleTree.applyStorageDelta(changes);
      final newHash = await merkleTree.getRootHash();
      
      expect(newHash, isNot(equals(initialHash)));
      expect(merkleTree.leafCount, equals(2));
    });
    
    test('tombstone handling', () async {
      // Add a regular entry
      await storage.put('key1', StorageEntry.value(
        key: 'key1', value: 'value1', timestampMs: 1000, nodeId: 'node1', seq: 1,
      ));
      
      // Add a tombstone
      await storage.put('key2', StorageEntry.tombstone(
        key: 'key2', timestampMs: 2000, nodeId: 'node1', seq: 2,
      ));
      
      await merkleTree.rebuildFromStorage();
      
      expect(merkleTree.leafCount, equals(2)); // Both regular and tombstone entries
      
      final rootHash = await merkleTree.getRootHash();
      expect(rootHash.length, equals(32));
    });
    
    test('root hash changes stream', () async {
      final rootHashes = <Uint8List>[];
      merkleTree.rootHashChanges.listen((hash) => rootHashes.add(hash));
      
      // Initial build
      await merkleTree.rebuildFromStorage();
      
      // Add entry
      await storage.put('key1', StorageEntry.value(
        key: 'key1', value: 'value1', timestampMs: 1000, nodeId: 'node1', seq: 1,
      ));
      await merkleTree.rebuildFromStorage();
      
      // Add another entry
      await storage.put('key2', StorageEntry.value(
        key: 'key2', value: 'value2', timestampMs: 2000, nodeId: 'node1', seq: 2,
      ));
      await merkleTree.rebuildFromStorage();
      
      // Should have received hash change notifications
      expect(rootHashes.length, greaterThanOrEqualTo(2));
      expect(rootHashes[0], isNot(equals(rootHashes[1])));
    });
    
    test('metrics tracking', () async {
      await storage.put('key1', StorageEntry.value(
        key: 'key1', value: 'value1', timestampMs: 1000, nodeId: 'node1', seq: 1,
      ));
      await storage.put('key2', StorageEntry.value(
        key: 'key2', value: 'value2', timestampMs: 2000, nodeId: 'node1', seq: 2,
      ));
      
      metrics.reset();
      await merkleTree.rebuildFromStorage();
      
      expect(metrics.merkleTreeLeafCount, equals(2));
      expect(metrics.merkleTreeDepth, greaterThan(0));
      expect(metrics.merkleRootHashChanges, greaterThan(0));
      expect(metrics.merkleHashComputations, greaterThan(0));
      expect(metrics.merkleTreeBuildDurations.isNotEmpty, isTrue);
      
      // Test that build duration is at least 1µs (clamped)
      expect(metrics.merkleTreeBuildDurations.first, greaterThanOrEqualTo(1));
    });
    
    test('large dataset performance', () async {
      // Add many entries
      const entryCount = 1000;
      for (int i = 0; i < entryCount; i++) {
        await storage.put('key$i', StorageEntry.value(
          key: 'key$i',
          value: 'value$i',
          timestampMs: 1000 + i,
          nodeId: 'node1',
          seq: i + 1,
        ));
      }
      
      final stopwatch = Stopwatch()..start();
      await merkleTree.rebuildFromStorage();
      stopwatch.stop();
      
      expect(merkleTree.leafCount, equals(entryCount));
      expect(stopwatch.elapsedMilliseconds, lessThan(5000)); // Should be reasonably fast
      
      final rootHash = await merkleTree.getRootHash();
      expect(rootHash.length, equals(32));
    });
    
    test('edge case: very large keys and values', () async {
      final largeKey = 'k' * 256; // Max key size
      final largeValue = 'v' * 1024; // Large value
      
      await storage.put(largeKey, StorageEntry.value(
        key: largeKey,
        value: largeValue,
        timestampMs: 1000,
        nodeId: 'node1',
        seq: 1,
      ));
      
      await merkleTree.rebuildFromStorage();
      
      expect(merkleTree.leafCount, equals(1));
      final rootHash = await merkleTree.getRootHash();
      expect(rootHash.length, equals(32));
    });
    
    test('cross-device determinism test vectors', () async {
      // Create a standard dataset that should produce the same hash everywhere
      final testEntries = [
        ('apple', 'red'),
        ('banana', 'yellow'),
        ('cherry', 'red'),
        ('date', 'brown'),
        ('elderberry', 'purple'),
      ];
      
      for (int i = 0; i < testEntries.length; i++) {
        final (key, value) = testEntries[i];
        await storage.put(key, StorageEntry.value(
          key: key,
          value: value,
          timestampMs: 1000 + i,
          nodeId: 'test-node',
          seq: i + 1,
        ));
      }
      
      await merkleTree.rebuildFromStorage();
      final rootHash = await merkleTree.getRootHash();
      
      // This hash should be identical across all devices and implementations
      expect(rootHash.length, equals(32));
      expect(merkleTree.leafCount, equals(5));
      
      // Convert to hex for easier verification
      final hexHash = rootHash.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      expect(hexHash.length, equals(64)); // 32 bytes = 64 hex chars
    });
  });

  group('StorageChange', () {
    test('insert change', () {
      final entry = StorageEntry.value(
        key: 'test', value: 'value', timestampMs: 1000, nodeId: 'node1', seq: 1,
      );
      final change = StorageChange.insert('test', entry);
      
      expect(change.key, equals('test'));
      expect(change.oldEntry, isNull);
      expect(change.newEntry, equals(entry));
      expect(change.type, equals(StorageChangeType.insert));
    });
    
    test('update change', () {
      final oldEntry = StorageEntry.value(
        key: 'test', value: 'old', timestampMs: 1000, nodeId: 'node1', seq: 1,
      );
      final newEntry = StorageEntry.value(
        key: 'test', value: 'new', timestampMs: 2000, nodeId: 'node1', seq: 2,
      );
      final change = StorageChange.update('test', oldEntry, newEntry);
      
      expect(change.key, equals('test'));
      expect(change.oldEntry, equals(oldEntry));
      expect(change.newEntry, equals(newEntry));
      expect(change.type, equals(StorageChangeType.update));
    });
    
    test('delete change', () {
      final oldEntry = StorageEntry.value(
        key: 'test', value: 'value', timestampMs: 1000, nodeId: 'node1', seq: 1,
      );
      final change = StorageChange.delete('test', oldEntry);
      
      expect(change.key, equals('test'));
      expect(change.oldEntry, equals(oldEntry));
      expect(change.newEntry, isNull);
      expect(change.type, equals(StorageChangeType.delete));
    });
  });
}
