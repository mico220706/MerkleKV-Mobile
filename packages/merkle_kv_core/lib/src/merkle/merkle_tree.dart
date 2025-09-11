import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:cbor/cbor.dart';

import '../storage/storage_interface.dart';
import '../storage/storage_entry.dart';
import '../replication/metrics.dart';

/// Represents a change in storage for incremental Merkle tree updates
class StorageChange {
  final String key;
  final StorageEntry? oldEntry;
  final StorageEntry? newEntry;
  final StorageChangeType type;

  const StorageChange({
    required this.key,
    this.oldEntry,
    this.newEntry,
    required this.type,
  });

  factory StorageChange.insert(String key, StorageEntry entry) {
    return StorageChange(
      key: key,
      oldEntry: null,
      newEntry: entry,
      type: StorageChangeType.insert,
    );
  }

  factory StorageChange.update(String key, StorageEntry oldEntry, StorageEntry newEntry) {
    return StorageChange(
      key: key,
      oldEntry: oldEntry,
      newEntry: newEntry,
      type: StorageChangeType.update,
    );
  }

  factory StorageChange.delete(String key, StorageEntry oldEntry) {
    return StorageChange(
      key: key,
      oldEntry: oldEntry,
      newEntry: null,
      type: StorageChangeType.delete,
    );
  }
}

enum StorageChangeType { insert, update, delete }

/// A node in the Merkle tree
class MerkleNode {
  final String path;
  final Uint8List hash;
  final bool isLeaf;
  final List<MerkleNode>? children;
  final int leafCount;

  const MerkleNode({
    required this.path,
    required this.hash,
    required this.isLeaf,
    this.children,
    required this.leafCount,
  });

  /// Creates a leaf node
  factory MerkleNode.leaf({
    required String key,
    required Uint8List valueHash,
    ReplicationMetrics? metrics,
  }) {
    metrics?.incrementMerkleHashComputations();
    
    // Leaf hash = SHA256(encode(["leaf", key, valueHash]))
    final leafData = cbor.encode(CborList([
      CborString("leaf"),
      CborString(key),
      CborBytes(valueHash),
    ]));
    final hash = Uint8List.fromList(sha256.convert(leafData).bytes);
    
    return MerkleNode(
      path: key,
      hash: hash,
      isLeaf: true,
      children: null,
      leafCount: 1,
    );
  }

  /// Creates an internal node from two children
  factory MerkleNode.internal({
    required String path,
    required MerkleNode left,
    required MerkleNode right,
    ReplicationMetrics? metrics,
  }) {
    metrics?.incrementMerkleHashComputations();
    
    // Internal node hash = SHA256(left.hash || right.hash)
    final combinedHash = Uint8List(64);
    combinedHash.setRange(0, 32, left.hash);
    combinedHash.setRange(32, 64, right.hash);
    final hash = Uint8List.fromList(sha256.convert(combinedHash).bytes);
    
    return MerkleNode(
      path: path,
      hash: hash,
      isLeaf: false,
      children: [left, right],
      leafCount: left.leafCount + right.leafCount,
    );
  }

  @override
  String toString() {
    final hashHex = hash.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return 'MerkleNode(path: $path, isLeaf: $isLeaf, leafCount: $leafCount, hash: ${hashHex.substring(0, 16)}...)';
  }
}

/// Value hasher that produces deterministic hashes for typed values per Spec §9
class ValueHasher {
  /// Hash a storage entry value using canonical CBOR encoding
  static Uint8List hashValue(StorageEntry entry, [ReplicationMetrics? metrics]) {
    metrics?.incrementMerkleHashComputations();
    
    if (entry.isTombstone) {
      // Tombstones: encode as ["del", ver_ts, ver_node]
      final tombstoneData = cbor.encode(CborList([
        CborString("del"),
        CborSmallInt(entry.timestampMs),
        CborString(entry.nodeId),
      ]));
      return Uint8List.fromList(sha256.convert(tombstoneData).bytes);
    } else {
      // Regular values: encode as [1, value] for strings
      final valueData = cbor.encode(CborList([
        CborSmallInt(1),
        CborString(entry.value!),
      ]));
      return Uint8List.fromList(sha256.convert(valueData).bytes);
    }
  }

  /// Hash a raw string value (for testing)
  static Uint8List hashString(String value, [ReplicationMetrics? metrics]) {
    metrics?.incrementMerkleHashComputations();
    
    final valueData = cbor.encode(CborList([
      CborSmallInt(1),
      CborString(value),
    ]));
    return Uint8List.fromList(sha256.convert(valueData).bytes);
  }

  /// Hash typed values for future extensibility
  static Uint8List hashTypedValue(dynamic value) {
    late CborValue cborValue;
    
    if (value is String) {
      cborValue = CborList([CborSmallInt(1), CborString(value)]);
    } else if (value is Uint8List) {
      cborValue = CborList([CborSmallInt(0), CborBytes(value)]);
    } else if (value is int) {
      cborValue = CborList([CborSmallInt(2), CborSmallInt(value)]);
    } else if (value is double) {
      // Normalize NaN and infinity
      final normalizedValue = value.isNaN ? double.nan : 
                             value.isInfinite ? (value.isNegative ? double.negativeInfinity : double.infinity) : 
                             value;
      cborValue = CborList([CborSmallInt(3), CborFloat(normalizedValue)]);
    } else if (value is bool) {
      cborValue = CborList([CborSmallInt(4), CborBool(value)]);
    } else if (value == null) {
      cborValue = CborList([CborSmallInt(5)]);
    } else if (value is List) {
      final list = value.map((item) => _toCborValue(item)).toList();
      cborValue = CborList([CborSmallInt(7), CborList(list)]);
    } else if (value is Map) {
      // Sort keys by canonical CBOR byte order
      final sortedEntries = value.entries.toList();
      sortedEntries.sort((a, b) {
        final aBytes = cbor.encode(_toCborValue(a.key));
        final bBytes = cbor.encode(_toCborValue(b.key));
        for (int i = 0; i < min(aBytes.length, bBytes.length); i++) {
          final cmp = aBytes[i].compareTo(bBytes[i]);
          if (cmp != 0) return cmp;
        }
        return aBytes.length.compareTo(bBytes.length);
      });
      
      final map = CborMap({});
      for (final entry in sortedEntries) {
        map[_toCborValue(entry.key)] = _toCborValue(entry.value);
      }
      cborValue = CborList([CborSmallInt(6), map]);
    } else {
      throw ArgumentError('Unsupported value type: ${value.runtimeType}');
    }

    final encoded = cbor.encode(cborValue);
    return Uint8List.fromList(sha256.convert(encoded).bytes);
  }

  static CborValue _toCborValue(dynamic value) {
    if (value is String) return CborString(value);
    if (value is int) return CborSmallInt(value);
    if (value is double) return CborFloat(value);
    if (value is bool) return CborBool(value);
    if (value is Uint8List) return CborBytes(value);
    if (value == null) return CborNull();
    if (value is List) return CborList(value.map(_toCborValue).toList());
    if (value is Map) {
      final map = CborMap({});
      for (final entry in value.entries) {
        map[_toCborValue(entry.key)] = _toCborValue(entry.value);
      }
      return map;
    }
    throw ArgumentError('Unsupported value type: ${value.runtimeType}');
  }
}

/// Abstract interface for Merkle tree operations
abstract class MerkleTree {
  /// Get the current root hash of the tree
  Future<Uint8List> getRootHash();

  /// Rebuild the entire tree from storage
  Future<void> rebuildFromStorage();

  /// Apply incremental changes to the tree
  Future<void> applyStorageDelta(List<StorageChange> changes);

  /// Get a specific node at the given path (for debugging)
  Future<MerkleNode?> getNodeAt(String path);

  /// Stream of root hash changes
  Stream<Uint8List> get rootHashChanges;

  /// Get tree depth (for metrics)
  int get depth;

  /// Get number of leaf nodes (for metrics)
  int get leafCount;
}

/// Leaf entry for the Merkle tree
class _LeafEntry {
  final String key;
  final Uint8List valueHash;

  const _LeafEntry(this.key, this.valueHash);
}

/// Implementation of Merkle tree with incremental updates
class MerkleTreeImpl implements MerkleTree {
  final StorageInterface _storage;
  final ReplicationMetrics _metrics;
  final StreamController<Uint8List> _rootHashController = StreamController<Uint8List>.broadcast();
  
  List<_LeafEntry> _leaves = [];
  MerkleNode? _root;
  Uint8List? _cachedRootHash;

  MerkleTreeImpl(this._storage, [ReplicationMetrics? metrics]) 
      : _metrics = metrics ?? const NoOpReplicationMetrics();

  @override
  Stream<Uint8List> get rootHashChanges => _rootHashController.stream;

  @override
  int get depth {
    if (_root == null) return 0;
    return _calculateDepth(_root!);
  }

  @override
  int get leafCount => _leaves.length;

  int _calculateDepth(MerkleNode node) {
    if (node.isLeaf) return 1;
    if (node.children == null || node.children!.isEmpty) return 1;
    return 1 + node.children!.map(_calculateDepth).reduce(max);
  }

  @override
  Future<Uint8List> getRootHash() async {
    if (_cachedRootHash == null) {
      await _rebuildTree();
    }
    return _cachedRootHash!;
  }

  @override
  Future<void> rebuildFromStorage() async {
    final stopwatch = Stopwatch()..start();
    await _rebuildTree();
    stopwatch.stop();
    _metrics.recordMerkleTreeBuildDuration(stopwatch.elapsedMicroseconds);
  }

  Future<void> _rebuildTree() async {
    final entries = await _storage.getAllEntries();
    
    // Sort entries by key for deterministic ordering
    entries.sort((a, b) => a.key.compareTo(b.key));
    
    // Convert to leaf entries
    _leaves = entries
        .map((entry) => _LeafEntry(entry.key, ValueHasher.hashValue(entry, _metrics)))
        .toList();
    
    // Build tree
    _root = _buildTreeFromLeaves(_leaves);
    
    // Update metrics
    _metrics.setMerkleTreeLeafCount(_leaves.length);
    _metrics.setMerkleTreeDepth(depth);
    
    // Update cached root hash
    final newRootHash = _root?.hash ?? _getEmptyRootHash();
    if (_cachedRootHash == null || !_hashesEqual(_cachedRootHash!, newRootHash)) {
      _cachedRootHash = newRootHash;
      _metrics.incrementMerkleRootHashChanges();
      _rootHashController.add(_cachedRootHash!);
    }
  }

  Uint8List _getEmptyRootHash() {
    _metrics.incrementMerkleHashComputations();
    
    // Empty tree root = SHA256(encode(["empty"]))
    final emptyData = cbor.encode(CborList([CborString("empty")]));
    return Uint8List.fromList(sha256.convert(emptyData).bytes);
  }

  bool _hashesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  MerkleNode? _buildTreeFromLeaves(List<_LeafEntry> leaves) {
    if (leaves.isEmpty) return null;
    if (leaves.length == 1) {
      return MerkleNode.leaf(
        key: leaves[0].key,
        valueHash: leaves[0].valueHash,
        metrics: _metrics,
      );
    }

    // Build balanced binary tree
    final nodes = leaves
        .map((leaf) => MerkleNode.leaf(
              key: leaf.key, 
              valueHash: leaf.valueHash,
              metrics: _metrics,
            ))
        .toList();
    
    return _buildBalancedTree(nodes);
  }

  MerkleNode _buildBalancedTree(List<MerkleNode> nodes) {
    if (nodes.length == 1) return nodes[0];
    
    final nextLevel = <MerkleNode>[];
    for (int i = 0; i < nodes.length; i += 2) {
      if (i + 1 < nodes.length) {
        // Pair of nodes
        final left = nodes[i];
        final right = nodes[i + 1];
        final path = _getCommonPrefix(left.path, right.path);
        nextLevel.add(MerkleNode.internal(
          path: path,
          left: left,
          right: right,
          metrics: _metrics,
        ));
      } else {
        // Odd node out - promote to next level
        nextLevel.add(nodes[i]);
      }
    }
    
    return _buildBalancedTree(nextLevel);
  }

  String _getCommonPrefix(String a, String b) {
    int i = 0;
    while (i < a.length && i < b.length && a[i] == b[i]) {
      i++;
    }
    return a.substring(0, i);
  }

  @override
  Future<void> applyStorageDelta(List<StorageChange> changes) async {
    if (changes.isEmpty) return;

    final stopwatch = Stopwatch()..start();
    
    // For simplicity in this implementation, we rebuild the entire tree
    // A more sophisticated implementation would perform incremental updates
    await _rebuildTree();
    
    stopwatch.stop();
    _metrics.recordMerkleTreeUpdateDuration(stopwatch.elapsedMicroseconds);
  }

  @override
  Future<MerkleNode?> getNodeAt(String path) async {
    if (_root == null) {
      await _rebuildTree();
    }
    return _findNodeByPath(_root, path);
  }

  MerkleNode? _findNodeByPath(MerkleNode? node, String path) {
    if (node == null) return null;
    if (node.path == path) return node;
    
    if (node.isLeaf) return null;
    
    if (node.children != null) {
      for (final child in node.children!) {
        final result = _findNodeByPath(child, path);
        if (result != null) return result;
      }
    }
    
    return null;
  }

  /// Dispose resources
  void dispose() {
    _rootHashController.close();
  }
}
