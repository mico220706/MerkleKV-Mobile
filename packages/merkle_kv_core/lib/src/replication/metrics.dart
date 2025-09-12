/// Simple metrics interface for replication event publishing
///
/// Provides basic counters and gauges for monitoring replication
/// publishing performance and status.
abstract class ReplicationMetrics {
  /// Increment the total number of events published
  void incrementEventsPublished();

  /// Increment the total number of publish errors
  void incrementPublishErrors();

  /// Set the current outbox size
  void setOutboxSize(int size);

  /// Record publish latency in milliseconds
  void recordPublishLatency(int milliseconds);

  /// Record outbox flush duration
  void recordFlushDuration(int milliseconds);

  /// Set current sequence number
  void setSequenceNumber(int sequence);

  /// Increment sequence gaps detected during recovery
  void incrementSequenceGaps();

  /// Increment the total number of events applied to storage
  void incrementEventsApplied();

  /// Increment the total number of events rejected (older, invalid, etc.)
  void incrementEventsRejected();

  /// Increment the total number of duplicate events detected
  void incrementEventsDuplicate();

  /// Increment the total number of conflicts resolved via LWW
  void incrementConflictsResolved();

  /// Increment the total number of events with clamped timestamps
  void incrementEventsClamped();

  /// Record application latency in milliseconds
  void recordApplicationLatency(int milliseconds);

  /// Increment the total number of LWW comparisons performed
  void incrementLWWComparisons();

  /// Increment the total number of LWW conflicts where local entry wins
  void incrementLWWLocalWins();

  /// Increment the total number of LWW conflicts where remote entry wins
  void incrementLWWRemoteWins();

  /// Increment the total number of LWW duplicates detected
  void incrementLWWDuplicates();

  /// Increment the total number of timestamps clamped due to clock skew
  void incrementLWWTimestampClamps();

  /// Increment the total number of timestamp anomalies detected
  void incrementLWWAnomalies();

  /// Set the current Merkle tree depth
  void setMerkleTreeDepth(int depth);

  /// Set the current number of leaf nodes in the Merkle tree
  void setMerkleTreeLeafCount(int count);

  /// Increment the total number of root hash changes
  void incrementMerkleRootHashChanges();

  /// Record Merkle tree build duration in microseconds
  void recordMerkleTreeBuildDuration(int microseconds);

  /// Record Merkle tree update duration in microseconds
  void recordMerkleTreeUpdateDuration(int microseconds);

  /// Increment the total number of hash computations performed
  void incrementMerkleHashComputations();

  /// Increment the total number of hash cache hits
  void incrementMerkleHashCacheHits();

  /// Record original and optimized payload sizes
  void recordPayloadOptimization(int originalBytes, int optimizedBytes);

  /// Record optimization effectiveness percentage
  void recordOptimizationEffectiveness(double reductionPercent);

  /// Increment count of payloads that exceeded size limit and were rejected
  void incrementSizeLimitExceeded();

  /// Record size estimation accuracy (estimated vs actual)
  void recordSizeEstimationAccuracy(int estimatedBytes, int actualBytes);
}

/// No-op implementation for when metrics are disabled
class NoOpReplicationMetrics implements ReplicationMetrics {
  const NoOpReplicationMetrics();

  @override
  void incrementEventsPublished() {}

  @override
  void incrementPublishErrors() {}

  @override
  void setOutboxSize(int size) {}

  @override
  void recordPublishLatency(int milliseconds) {}

  @override
  void recordFlushDuration(int milliseconds) {}

  @override
  void setSequenceNumber(int sequence) {}

  @override
  void incrementSequenceGaps() {}

  @override
  void incrementEventsApplied() {}

  @override
  void incrementEventsRejected() {}

  @override
  void incrementEventsDuplicate() {}

  @override
  void incrementConflictsResolved() {}

  @override
  void incrementEventsClamped() {}

  @override
  void recordApplicationLatency(int milliseconds) {}

  @override
  void incrementLWWComparisons() {}

  @override
  void incrementLWWLocalWins() {}

  @override
  void incrementLWWRemoteWins() {}

  @override
  void incrementLWWDuplicates() {}

  @override
  void incrementLWWTimestampClamps() {}

  @override
  void incrementLWWAnomalies() {}

  @override
  void setMerkleTreeDepth(int depth) {}

  @override
  void setMerkleTreeLeafCount(int count) {}

  @override
  void incrementMerkleRootHashChanges() {}

  @override
  void recordMerkleTreeBuildDuration(int microseconds) {}

  @override
  void recordMerkleTreeUpdateDuration(int microseconds) {}

  @override
  void incrementMerkleHashComputations() {}

  @override
  void incrementMerkleHashCacheHits() {}

  @override
  void recordPayloadOptimization(int originalBytes, int optimizedBytes) {}

  @override
  void recordOptimizationEffectiveness(double reductionPercent) {}

  @override
  void incrementSizeLimitExceeded() {}

  @override
  void recordSizeEstimationAccuracy(int estimatedBytes, int actualBytes) {}
}

/// Simple in-memory metrics implementation for testing/debugging
class InMemoryReplicationMetrics implements ReplicationMetrics {
  int _eventsPublished = 0;
  int _publishErrors = 0;
  int _outboxSize = 0;
  int _currentSequence = 0;
  int _sequenceGaps = 0;
  final List<int> _publishLatencies = <int>[];
  final List<int> _flushDurations = <int>[];

  @override
  void incrementEventsPublished() {
    _eventsPublished++;
  }

  @override
  void incrementPublishErrors() {
    _publishErrors++;
  }

  @override
  void setOutboxSize(int size) {
    _outboxSize = size;
  }

  @override
  void recordPublishLatency(int milliseconds) {
    _publishLatencies.add(milliseconds);
  }

  @override
  void recordFlushDuration(int milliseconds) {
    _flushDurations.add(milliseconds);
  }

  @override
  void setSequenceNumber(int sequence) {
    _currentSequence = sequence;
  }

  @override
  void incrementSequenceGaps() {
    _sequenceGaps++;
  }

  @override
  void incrementEventsApplied() {}

  @override
  void incrementEventsRejected() {}

  @override
  void incrementEventsDuplicate() {}

  @override
  void incrementConflictsResolved() {}

  @override
  void incrementEventsClamped() {}

  @override
  void recordApplicationLatency(int milliseconds) {}

  @override
  void incrementLWWComparisons() {}

  @override
  void incrementLWWLocalWins() {}

  @override
  void incrementLWWRemoteWins() {}

  @override
  void incrementLWWDuplicates() {}

  @override
  void incrementLWWTimestampClamps() {}

  @override
  void incrementLWWAnomalies() {}

  @override
  void setMerkleTreeDepth(int depth) {}

  @override
  void setMerkleTreeLeafCount(int count) {}

  @override
  void incrementMerkleRootHashChanges() {}

  @override
  void recordMerkleTreeBuildDuration(int microseconds) {}

  @override
  void recordMerkleTreeUpdateDuration(int microseconds) {}

  @override
  void incrementMerkleHashComputations() {}

  @override
  void incrementMerkleHashCacheHits() {}

  @override
  void recordPayloadOptimization(int originalBytes, int optimizedBytes) {}

  @override
  void recordOptimizationEffectiveness(double reductionPercent) {}

  @override
  void incrementSizeLimitExceeded() {}

  @override
  void recordSizeEstimationAccuracy(int estimatedBytes, int actualBytes) {}
}