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

  int get eventsPublished => _eventsPublished;
  int get publishErrors => _publishErrors;
  int get outboxSize => _outboxSize;
  int get currentSequence => _currentSequence;
  int get sequenceGaps => _sequenceGaps;
  List<int> get publishLatencies => List.unmodifiable(_publishLatencies);
  List<int> get flushDurations => List.unmodifiable(_flushDurations);

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

  /// Reset all metrics (useful for testing)
  void reset() {
    _eventsPublished = 0;
    _publishErrors = 0;
    _outboxSize = 0;
    _currentSequence = 0;
    _sequenceGaps = 0;
    _publishLatencies.clear();
    _flushDurations.clear();
  }

  @override
  String toString() {
    final avgLatency = _publishLatencies.isEmpty 
        ? 0 
        : _publishLatencies.reduce((a, b) => a + b) / _publishLatencies.length;
    
    return 'InMemoryReplicationMetrics('
        'eventsPublished: $_eventsPublished, '
        'publishErrors: $_publishErrors, '
        'outboxSize: $_outboxSize, '
        'currentSequence: $_currentSequence, '
        'sequenceGaps: $_sequenceGaps, '
        'avgLatency: ${avgLatency.toStringAsFixed(1)}ms'
        ')';
  }
}
