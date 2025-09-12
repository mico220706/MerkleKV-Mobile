import '../storage/storage_entry.dart';

/// Comparison result for Last-Write-Wins conflict resolution
enum ComparisonResult {
  localWins,   // Local entry wins the conflict
  remoteWins,  // Remote entry wins the conflict
  duplicate,   // Entries are identical (timestamp_ms, node_id)
}

/// Abstract interface for Last-Write-Wins conflict resolution
/// Implements LWW ordering per Locked Spec §5.1 and §5.7
abstract class LWWResolver {
  /// Compares two storage entries using LWW semantics
  /// 
  /// Uses (timestamp_ms, node_id) lexicographic ordering with timestamp clamping
  /// for local comparison while preserving original timestamps for replication.
  ComparisonResult compare(StorageEntry a, StorageEntry b);

  /// Selects the winner between local and remote entries
  /// 
  /// Returns the entry that should be kept based on LWW comparison.
  StorageEntry selectWinner(StorageEntry local, StorageEntry remote);

  /// Clamps timestamp for local comparison to mitigate clock skew
  /// 
  /// Limits future timestamps to now + 5 minutes per §5.7.
  /// Original timestamps are preserved unchanged for replication propagation.
  int clampTimestamp(int timestampMs);
}

/// Default implementation of LWW conflict resolution
class LWWResolverImpl implements LWWResolver {
  static const int _maxSkewMs = 5 * 60 * 1000; // 5 minutes in milliseconds

  @override
  ComparisonResult compare(StorageEntry a, StorageEntry b) {
    // Apply timestamp clamping for local comparison only
    final aTimestamp = clampTimestamp(a.timestampMs);
    final bTimestamp = clampTimestamp(b.timestampMs);
    
    // Primary comparison: clamped timestamp
    if (aTimestamp != bTimestamp) {
      return aTimestamp > bTimestamp ? ComparisonResult.localWins : ComparisonResult.remoteWins;
    }
    
    // Secondary comparison: node_id lexicographic ordering
    final nodeComparison = a.nodeId.compareTo(b.nodeId);
    if (nodeComparison != 0) {
      return nodeComparison > 0 ? ComparisonResult.localWins : ComparisonResult.remoteWins;
    }
    
    // Identical (timestamp_ms, node_id) - check for true duplicate
    if (a.timestampMs == b.timestampMs) {
      return ComparisonResult.duplicate;
    }
    
    // Different original timestamps but same clamped timestamp and node_id
    // This is a rare edge case - use original timestamp as tiebreaker
    return a.timestampMs > b.timestampMs ? ComparisonResult.localWins : ComparisonResult.remoteWins;
  }

  @override
  StorageEntry selectWinner(StorageEntry local, StorageEntry remote) {
    final result = compare(local, remote);
    switch (result) {
      case ComparisonResult.localWins:
      case ComparisonResult.duplicate:
        return local;
      case ComparisonResult.remoteWins:
        return remote;
    }
  }

  @override
  int clampTimestamp(int timestampMs) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final maxAllowed = now + _maxSkewMs;
    
    // Only clamp future timestamps that exceed the allowed skew
    return timestampMs > maxAllowed ? maxAllowed : timestampMs;
  }

  /// Checks if a timestamp was clamped (useful for metrics)
  bool wasTimestampClamped(int originalTimestampMs) {
    return clampTimestamp(originalTimestampMs) != originalTimestampMs;
  }
}
