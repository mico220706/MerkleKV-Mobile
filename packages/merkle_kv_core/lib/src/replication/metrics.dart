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

  // Event application metrics (for issue #14)
  void incrementEventsApplied();
  void incrementEventsRejected();
  void incrementEventsDuplicate();
  void incrementConflictsResolved();
  void incrementEventsClamped();
  void recordApplicationLatency(int milliseconds);

  // LWW conflict resolution metrics (for issue #15)
  void incrementLWWComparisons();
  void incrementLWWLocalWins();
  void incrementLWWRemoteWins();
  void incrementLWWDuplicates();
  void incrementLWWTimestampClamps();
  void incrementLWWAnomalies();

  // Merkle tree metrics (for issue #16)
  void setMerkleTreeDepth(int depth);
  void setMerkleTreeLeafCount(int count);
  void incrementMerkleRootHashChanges();
  void recordMerkleTreeBuildDuration(int microseconds);
  void recordMerkleTreeUpdateDuration(int microseconds);
  void incrementMerkleHashComputations();
  void incrementMerkleHashCacheHits();

  // Payload optimization metrics
  void recordPayloadOptimization(int originalBytes, int optimizedBytes);
  void recordOptimizationEffectiveness(double reductionPercent);
  void incrementSizeLimitExceeded();
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
  int _eventsApplied = 0;
  int _eventsRejected = 0;
  int _eventsDuplicate = 0;
  int _conflictsResolved = 0;
  int _eventsClamped = 0;
  int _lwwComparisons = 0;
  int _lwwLocalWins = 0;
  int _lwwRemoteWins = 0;
  int _lwwDuplicates = 0;
  int _lwwTimestampClamps = 0;
  int _lwwAnomalies = 0;
  int _merkleTreeDepth = 0;
  int _merkleTreeLeafCount = 0;
  int _merkleRootHashChanges = 0;
  int _merkleHashComputations = 0;
  int _merkleHashCacheHits = 0;
  int _payloadOptimizedOriginalSize = 0;
  int _payloadOptimizedReducedSize = 0;
  double _optimizationEffectiveness = 0.0;
  int _sizeLimitExceededCount = 0;
  final List<int> _publishLatencies = <int>[];
  final List<int> _flushDurations = <int>[];
  final List<int> _applicationLatencies = <int>[];
  final List<int> _merkleTreeBuildDurations = <int>[];
  final List<int> _merkleTreeUpdateDurations = <int>[];

  // Getters for accessing private fields in tests
  int get eventsPublished => _eventsPublished;
  int get publishErrors => _publishErrors;
  int get outboxSize => _outboxSize;
  int get currentSequence => _currentSequence;
  int get sequenceGaps => _sequenceGaps;
  int get eventsApplied => _eventsApplied;
  int get eventsRejected => _eventsRejected;
  int get eventsDuplicate => _eventsDuplicate;
  int get conflictsResolved => _conflictsResolved;
  int get eventsClamped => _eventsClamped;
  int get lwwComparisons => _lwwComparisons;
  int get lwwLocalWins => _lwwLocalWins;
  int get lwwRemoteWins => _lwwRemoteWins;
  int get lwwDuplicates => _lwwDuplicates;
  int get lwwTimestampClamps => _lwwTimestampClamps;
  int get lwwAnomalies => _lwwAnomalies;
  int get merkleTreeDepth => _merkleTreeDepth;
  int get merkleTreeLeafCount => _merkleTreeLeafCount;
  int get merkleRootHashChanges => _merkleRootHashChanges;
  int get merkleHashComputations => _merkleHashComputations;
  int get merkleHashCacheHits => _merkleHashCacheHits;
  int get payloadOptimizedOriginalSize => _payloadOptimizedOriginalSize;
  int get payloadOptimizedReducedSize => _payloadOptimizedReducedSize;
  double get optimizationEffectiveness => _optimizationEffectiveness;
  int get sizeLimitExceededCount => _sizeLimitExceededCount;
  List<int> get publishLatencies => List.unmodifiable(_publishLatencies);
  List<int> get flushDurations => List.unmodifiable(_flushDurations);
  List<int> get applicationLatencies => List.unmodifiable(_applicationLatencies);
  List<int> get merkleTreeBuildDurations => List.unmodifiable(_merkleTreeBuildDurations);
  List<int> get merkleTreeUpdateDurations => List.unmodifiable(_merkleTreeUpdateDurations);

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
  void incrementEventsApplied() {
    _eventsApplied++;
  }

  @override
  void incrementEventsRejected() {
    _eventsRejected++;
  }

  @override
  void incrementEventsDuplicate() {
    _eventsDuplicate++;
  }

  @override
  void incrementConflictsResolved() {
    _conflictsResolved++;
  }

  @override
  void incrementEventsClamped() {
    _eventsClamped++;
  }

  @override
  void recordApplicationLatency(int milliseconds) {
    _applicationLatencies.add(milliseconds);
  }

  @override
  void incrementLWWComparisons() {
    _lwwComparisons++;
  }

  @override
  void incrementLWWLocalWins() {
    _lwwLocalWins++;
  }

  @override
  void incrementLWWRemoteWins() {
    _lwwRemoteWins++;
  }

  @override
  void incrementLWWDuplicates() {
    _lwwDuplicates++;
  }

  @override
  void incrementLWWTimestampClamps() {
    _lwwTimestampClamps++;
  }

  @override
  void incrementLWWAnomalies() {
    _lwwAnomalies++;
  }

  @override
  void setMerkleTreeDepth(int depth) {
    _merkleTreeDepth = depth;
  }

  @override
  void setMerkleTreeLeafCount(int count) {
    _merkleTreeLeafCount = count;
  }

  @override
  void incrementMerkleRootHashChanges() {
    _merkleRootHashChanges++;
  }

  @override
  void recordMerkleTreeBuildDuration(int microseconds) {
    _merkleTreeBuildDurations.add(microseconds);
  }

  @override
  void recordMerkleTreeUpdateDuration(int microseconds) {
    _merkleTreeUpdateDurations.add(microseconds);
  }

  @override
  void incrementMerkleHashComputations() {
    _merkleHashComputations++;
  }

  @override
  void incrementMerkleHashCacheHits() {
    _merkleHashCacheHits++;
  }

  @override
  void recordPayloadOptimization(int originalBytes, int optimizedBytes) {
    _payloadOptimizedOriginalSize += originalBytes;
    _payloadOptimizedReducedSize += optimizedBytes;
  }

  @override
  void recordOptimizationEffectiveness(double reductionPercent) {
    _optimizationEffectiveness += reductionPercent;
  }

  @override
  void incrementSizeLimitExceeded() {
    _sizeLimitExceededCount++;
  }

  @override
  void recordSizeEstimationAccuracy(int estimatedBytes, int actualBytes) {
    // Implement accuracy tracking logic here
  }

  /// Reset all metrics (useful for testing)
  void reset() {
    _eventsPublished = 0;
    _publishErrors = 0;
    _outboxSize = 0;
    _currentSequence = 0;
    _sequenceGaps = 0;
    _eventsApplied = 0;
    _eventsRejected = 0;
    _eventsDuplicate = 0;
    _conflictsResolved = 0;
    _eventsClamped = 0;
    _lwwComparisons = 0;
    _lwwLocalWins = 0;
    _lwwRemoteWins = 0;
    _lwwDuplicates = 0;
    _lwwTimestampClamps = 0;
    _lwwAnomalies = 0;
    _merkleTreeDepth = 0;
    _merkleTreeLeafCount = 0;
    _merkleRootHashChanges = 0;
    _merkleHashComputations = 0;
    _merkleHashCacheHits = 0;
    _payloadOptimizedOriginalSize = 0;
    _payloadOptimizedReducedSize = 0;
    _optimizationEffectiveness = 0.0;
    _sizeLimitExceededCount = 0;
    _publishLatencies.clear();
    _flushDurations.clear();
    _applicationLatencies.clear();
    _merkleTreeBuildDurations.clear();
    _merkleTreeUpdateDurations.clear();
  }

  @override
  String toString() {
    final avgPublishLatency = _publishLatencies.isEmpty
        ? 0
        : _publishLatencies.reduce((a, b) => a + b) / _publishLatencies.length;

    final avgApplicationLatency = _applicationLatencies.isEmpty
        ? 0
        : _applicationLatencies.reduce((a, b) => a + b) /
            _applicationLatencies.length;

    final avgMerkleBuildDuration = _merkleTreeBuildDurations.isEmpty
        ? 0
        : _merkleTreeBuildDurations.reduce((a, b) => a + b) /
            _merkleTreeBuildDurations.length;

    final avgMerkleUpdateDuration = _merkleTreeUpdateDurations.isEmpty
        ? 0
        : _merkleTreeUpdateDurations.reduce((a, b) => a + b) /
            _merkleTreeUpdateDurations.length;

    return 'InMemoryReplicationMetrics('
        'eventsPublished: $_eventsPublished, '
        'publishErrors: $_publishErrors, '
        'outboxSize: $_outboxSize, '
        'currentSequence: $_currentSequence, '
        'sequenceGaps: $_sequenceGaps, '
        'eventsApplied: $_eventsApplied, '
        'eventsRejected: $_eventsRejected, '
        'eventsDuplicate: $_eventsDuplicate, '
        'conflictsResolved: $_conflictsResolved, '
        'eventsClamped: $_eventsClamped, '
        'lwwComparisons: $_lwwComparisons, '
        'lwwLocalWins: $_lwwLocalWins, '
        'lwwRemoteWins: $_lwwRemoteWins, '
        'lwwDuplicates: $_lwwDuplicates, '
        'lwwTimestampClamps: $_lwwTimestampClamps, '
        'lwwAnomalies: $_lwwAnomalies, '
        'merkleTreeDepth: $_merkleTreeDepth, '
        'merkleTreeLeafCount: $_merkleTreeLeafCount, '
        'merkleRootHashChanges: $_merkleRootHashChanges, '
        'merkleHashComputations: $_merkleHashComputations, '
        'merkleHashCacheHits: $_merkleHashCacheHits, '
        'payloadOptimizedOriginalSize: $_payloadOptimizedOriginalSize, '
        'payloadOptimizedReducedSize: $_payloadOptimizedReducedSize, '
        'optimizationEffectiveness: $_optimizationEffectiveness, '
        'sizeLimitExceededCount: $_sizeLimitExceededCount, '
        'avgPublishLatency: ${avgPublishLatency.toStringAsFixed(1)}ms, '
        'avgApplicationLatency: ${avgApplicationLatency.toStringAsFixed(1)}ms, '
        'avgMerkleBuildDuration: ${avgMerkleBuildDuration.toStringAsFixed(1)}µs, '
        'avgMerkleUpdateDuration: ${avgMerkleUpdateDuration.toStringAsFixed(1)}µs'
        ')';
  }
}