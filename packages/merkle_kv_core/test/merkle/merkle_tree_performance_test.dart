import 'dart:math';
import 'package:test/test.dart';
import 'package:merkle_kv_core/merkle_kv_core.dart';

void main() {
  group('Merkle Tree Performance Tests', () {
    late InMemoryStorage storage;
    late InMemoryReplicationMetrics metrics;
    late MerkleTreeImpl merkleTree;
    
    setUp(() async {
      final config = MerkleKVConfig.defaultConfig(
        host: 'localhost',
        clientId: 'perf-client',
        nodeId: 'perf-node',
      );
      storage = InMemoryStorage(config);
      await storage.initialize();
      metrics = InMemoryReplicationMetrics();
      merkleTree = MerkleTreeImpl(storage, metrics);
    });
    
    tearDown(() {
      merkleTree.dispose();
    });
    
    test('build performance with 10k entries', () async {
      const entryCount = 10000;
      
      // Generate test data
      for (int i = 0; i < entryCount; i++) {
        await storage.put('key${i.toString().padLeft(5, '0')}', StorageEntry.value(
          key: 'key${i.toString().padLeft(5, '0')}',
          value: 'value_$i',
          timestampMs: 1000000 + i,
          nodeId: 'node1',
          seq: i + 1,
        ));
      }
      
      final stopwatch = Stopwatch()..start();
      await merkleTree.rebuildFromStorage();
      stopwatch.stop();
      
      expect(merkleTree.leafCount, equals(entryCount));
      expect(stopwatch.elapsedMilliseconds, lessThan(10000)); // Should complete in under 10s
      
      print('Built tree with $entryCount entries in ${stopwatch.elapsedMilliseconds}ms');
      print('Tree depth: ${merkleTree.depth}');
      print('Hash computations: ${metrics.merkleHashComputations}');
      
      final rootHash = await merkleTree.getRootHash();
      expect(rootHash.length, equals(32));
    });
    
    test('incremental update performance', () async {
      const initialCount = 1000;
      const updateCount = 100;
      
      // Build initial tree
      for (int i = 0; i < initialCount; i++) {
        await storage.put('key$i', StorageEntry.value(
          key: 'key$i',
          value: 'value_$i',
          timestampMs: 1000000 + i,
          nodeId: 'node1',
          seq: i + 1,
        ));
      }
      
      await merkleTree.rebuildFromStorage();
      final initialRootHash = await merkleTree.getRootHash();
      
      // Measure incremental updates
      final updateTimes = <int>[];
      
      for (int i = 0; i < updateCount; i++) {
        await storage.put('new_key$i', StorageEntry.value(
          key: 'new_key$i',
          value: 'new_value_$i',
          timestampMs: 2000000 + i,
          nodeId: 'node1',
          seq: initialCount + i + 1,
        ));
        
        final stopwatch = Stopwatch()..start();
        final changes = [
          StorageChange.insert('new_key$i', StorageEntry.value(
            key: 'new_key$i',
            value: 'new_value_$i',
            timestampMs: 2000000 + i,
            nodeId: 'node1',
            seq: initialCount + i + 1,
          )),
        ];
        await merkleTree.applyStorageDelta(changes);
        stopwatch.stop();
        
        updateTimes.add(stopwatch.elapsedMicroseconds);
      }
      
      final avgUpdateTime = updateTimes.reduce((a, b) => a + b) / updateTimes.length;
      print('Average incremental update time: ${avgUpdateTime.toStringAsFixed(1)}µs');
      print('Total updates: $updateCount');
      
      expect(avgUpdateTime, lessThan(50000)); // Should be under 50ms per update
      expect(merkleTree.leafCount, equals(initialCount + updateCount));
      
      final finalRootHash = await merkleTree.getRootHash();
      expect(finalRootHash, isNot(equals(initialRootHash)));
    });
    
    test('memory usage with large dataset', () async {
      const entryCount = 100000;
      
      // Add many entries with varying sizes
      final random = Random(42); // Fixed seed for reproducibility
      for (int i = 0; i < entryCount; i++) {
        final keyLength = 10 + random.nextInt(50);
        final valueLength = 20 + random.nextInt(200);
        
        final key = 'key_${i.toString().padLeft(6, '0')}_${'x' * keyLength}';
        final value = 'value_$i${'y' * valueLength}';
        
        await storage.put(key, StorageEntry.value(
          key: key,
          value: value,
          timestampMs: 1000000 + i,
          nodeId: 'node1',
          seq: i + 1,
        ));
        
        // Periodically check if we can still build the tree
        if (i % 10000 == 0 && i > 0) {
          await merkleTree.rebuildFromStorage();
          expect(merkleTree.leafCount, equals(i + 1));
        }
      }
      
      final finalStopwatch = Stopwatch()..start();
      await merkleTree.rebuildFromStorage();
      finalStopwatch.stop();
      
      expect(merkleTree.leafCount, equals(entryCount));
      print('Final build with $entryCount entries: ${finalStopwatch.elapsedMilliseconds}ms');
      print('Tree depth: ${merkleTree.depth}');
      
      // Verify the tree is still functional
      final rootHash = await merkleTree.getRootHash();
      expect(rootHash.length, equals(32));
    });
    
    test('hash computation performance', () async {
      const hashCount = 10000;
      
      final stopwatch = Stopwatch()..start();
      
      for (int i = 0; i < hashCount; i++) {
        final entry = StorageEntry.value(
          key: 'key$i',
          value: 'value_with_some_content_$i',
          timestampMs: 1000000 + i,
          nodeId: 'node1',
          seq: i + 1,
        );
        
        final hash = ValueHasher.hashValue(entry, metrics);
        expect(hash.length, equals(32));
      }
      
      stopwatch.stop();
      
      final avgTimePerHash = stopwatch.elapsedMicroseconds / hashCount;
      print('Hash computations: $hashCount');
      print('Total time: ${stopwatch.elapsedMilliseconds}ms');
      print('Average time per hash: ${avgTimePerHash.toStringAsFixed(1)}µs');
      print('Hashes per second: ${(hashCount / stopwatch.elapsedMilliseconds * 1000).round()}');
      
      expect(avgTimePerHash, lessThan(1000)); // Should be under 1ms per hash
      expect(metrics.merkleHashComputations, equals(hashCount));
    });
    
    test('deterministic performance across runs', () async {
      const entryCount = 1000;
      final buildTimes = <int>[];
      
      // Run multiple builds to check consistency
      for (int run = 0; run < 5; run++) {
        final config = MerkleKVConfig.defaultConfig(
          host: 'localhost',
          clientId: 'perf-client-$run',
          nodeId: 'perf-node-$run',
        );
        storage = InMemoryStorage(config);
        merkleTree.dispose();
        merkleTree = MerkleTreeImpl(storage, metrics);
        
        // Add same dataset each time
        for (int i = 0; i < entryCount; i++) {
          await storage.put('key$i', StorageEntry.value(
            key: 'key$i',
            value: 'value_$i',
            timestampMs: 1000000 + i,
            nodeId: 'test_node',
            seq: i + 1,
          ));
        }
        
        final stopwatch = Stopwatch()..start();
        await merkleTree.rebuildFromStorage();
        stopwatch.stop();
        
        buildTimes.add(stopwatch.elapsedMicroseconds);
        
        // Verify deterministic output
        final rootHash = await merkleTree.getRootHash();
        expect(rootHash.length, equals(32));
        expect(merkleTree.leafCount, equals(entryCount));
      }
      
      final avgBuildTime = buildTimes.reduce((a, b) => a + b) / buildTimes.length;
      final maxDeviation = buildTimes.map((t) => (t - avgBuildTime).abs()).reduce(max);
      
      print('Build times (µs): $buildTimes');
      print('Average: ${avgBuildTime.toStringAsFixed(1)}µs');
      print('Max deviation: ${maxDeviation.toStringAsFixed(1)}µs');
      
      // Performance should be reasonably consistent
      expect(maxDeviation / avgBuildTime, lessThan(0.5)); // Within 50% variance
    });
    
    test('concurrent operations simulation', () async {
      const batchSize = 100;
      const batchCount = 10;
      
      // Simulate multiple batches of updates
      for (int batch = 0; batch < batchCount; batch++) {
        final changes = <StorageChange>[];
        
        // Add batch of entries to storage
        for (int i = 0; i < batchSize; i++) {
          final key = 'batch${batch}_key$i';
          final entry = StorageEntry.value(
            key: key,
            value: 'batch_${batch}_value_$i',
            timestampMs: 1000000 + batch * 1000 + i,
            nodeId: 'node1',
            seq: batch * batchSize + i + 1,
          );
          
          await storage.put(key, entry);
          changes.add(StorageChange.insert(key, entry));
        }
        
        // Apply batch update to tree
        final stopwatch = Stopwatch()..start();
        await merkleTree.applyStorageDelta(changes);
        stopwatch.stop();
        
        print('Batch $batch: ${changes.length} changes in ${stopwatch.elapsedMicroseconds}µs');
        
        expect(merkleTree.leafCount, equals((batch + 1) * batchSize));
        expect(stopwatch.elapsedMilliseconds, lessThan(1000)); // Under 1s per batch
      }
      
      final finalRootHash = await merkleTree.getRootHash();
      expect(finalRootHash.length, equals(32));
      expect(merkleTree.leafCount, equals(batchSize * batchCount));
    });
    
    test('stress test with mixed operations', () async {
      const operationCount = 5000;
      final random = Random(123); // Fixed seed for reproducibility
      
      var currentSeq = 1;
      // var totalEntries = 0; // Tracked but not used in output
      
      for (int i = 0; i < operationCount; i++) {
        final operation = random.nextInt(3); // 0=insert, 1=update, 2=delete
        final key = 'stress_key_${random.nextInt(1000)}';
        
        switch (operation) {
          case 0: // Insert
            final entry = StorageEntry.value(
              key: key,
              value: 'stress_value_$i',
              timestampMs: 1000000 + i,
              nodeId: 'stress_node',
              seq: currentSeq++,
            );
            await storage.put(key, entry);
            // totalEntries++; // Tracked but not used in output
            break;
            
          case 1: // Update (if key exists)
            final existing = await storage.get(key);
            if (existing != null) {
              final entry = StorageEntry.value(
                key: key,
                value: 'updated_value_$i',
                timestampMs: 1000000 + i,
                nodeId: 'stress_node',
                seq: currentSeq++,
              );
              await storage.put(key, entry);
            }
            break;
            
          case 2: // Delete (tombstone)
            final existing = await storage.get(key);
            if (existing != null) {
              await storage.delete(key, 1000000 + i, 'stress_node', currentSeq++);
            }
            break;
        }
        
        // Periodically rebuild tree to ensure it stays consistent
        if (i % 500 == 0) {
          final stopwatch = Stopwatch()..start();
          await merkleTree.rebuildFromStorage();
          stopwatch.stop();
          
          if (i > 0) {
            print('Rebuild after $i ops: ${stopwatch.elapsedMicroseconds}µs, ${merkleTree.leafCount} leaves');
          }
        }
      }
      
      // Final rebuild and verification
      final finalStopwatch = Stopwatch()..start();
      await merkleTree.rebuildFromStorage();
      finalStopwatch.stop();
      
      print('Final stress test rebuild: ${finalStopwatch.elapsedMicroseconds}µs');
      print('Total operations: $operationCount');
      print('Final leaf count: ${merkleTree.leafCount}');
      print('Tree depth: ${merkleTree.depth}');
      
      final rootHash = await merkleTree.getRootHash();
      expect(rootHash.length, equals(32));
      expect(merkleTree.leafCount, greaterThan(0));
    });
  });
}
