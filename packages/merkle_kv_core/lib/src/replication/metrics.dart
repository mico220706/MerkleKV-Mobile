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
  
  /// Increment the total number of events applied to storage
  void incrementEventsApplied() {}
  
  /// Increment the total number of events rejected (older, invalid, etc.)
  void incrementEventsRejected() {}
  
  /// Increment the total number of duplicate events detected
  void incrementEventsDuplicate() {}
  
  /// Increment the total number of conflicts resolved via LWW
  void incrementConflictsResolved() {}
  
  /// Increment the total number of events with clamped timestamps
  void incrementEventsClamped() {}
  
  /// Record application latency in milliseconds
  void recordApplicationLatency(int milliseconds) {}
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
  final List<int> _publishLatencies = <int>[];
  final List<int> _flushDurations = <int>[];
  final List<int> _applicationLatencies = <int>[];

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
  List<int> get publishLatencies => List.unmodifiable(_publishLatencies);
  List<int> get flushDurations => List.unmodifiable(_flushDurations);
  List<int> get applicationLatencies => List.unmodifiable(_applicationLatencies);

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
    _publishLatencies.clear();
    _flushDurations.clear();
    _applicationLatencies.clear();
  }

  @override
  String toString() {
    final avgPublishLatency = _publishLatencies.isEmpty 
        ? 0 
        : _publishLatencies.reduce((a, b) => a + b) / _publishLatencies.length;
    
    final avgApplicationLatency = _applicationLatencies.isEmpty 
        ? 0 
        : _applicationLatencies.reduce((a, b) => a + b) / _applicationLatencies.length;
    
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
        'avgPublishLatency: ${avgPublishLatency.toStringAsFixed(1)}ms, '
        'avgApplicationLatency: ${avgApplicationLatency.toStringAsFixed(1)}ms'
        ')';
  }
}
