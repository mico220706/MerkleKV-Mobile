import 'dart:async';
import 'package:meta/meta.dart';

// Add missing classes directly to this file
abstract class MetricsRecorder {
  void incrementCounter(String name, {int increment = 1});
  void setGauge(String name, double value);
  void recordHistogramValue(String name, double value);
}

class ReplicationEvent {
  final String key;
  String? value;
  final String nodeId;
  final int sequenceNumber;
  final int timestampMs;
  bool tombstone;

  ReplicationEvent({
    required this.key,
    required this.value,
    required this.nodeId,
    required this.sequenceNumber,
    required this.timestampMs,
    required this.tombstone,
  });
}

/// Represents a pending update that may be coalesced with subsequent updates
/// to the same key before being converted to a [ReplicationEvent].
class PendingUpdate {
  final String key;
  String? value;
  bool tombstone;
  int timestampMs; // Made mutable to fix coalescing
  final DateTime addedAt;

  PendingUpdate({
    required this.key,
    required this.value,
    required this.tombstone,
    required this.timestampMs,
    DateTime? addedAt,
  }) : addedAt = addedAt ?? DateTime.now();

  /// Updates this pending update with a newer operation on the same key.
  /// Returns true if the update was coalesced (changed the existing entry).
  bool coalesceWith(String? newValue, bool newTombstone, int newTimestampMs) {
    // Only coalesce if the new timestamp is newer than the current one
    if (newTimestampMs > timestampMs) {
      value = newValue;
      tombstone = newTombstone;
      timestampMs = newTimestampMs; // Update the timestamp
      return true;
    }
    return false;
  }

  /// Converts this pending update to a [ReplicationEvent].
  ReplicationEvent toReplicationEvent(String nodeId, int sequenceNumber) {
    return ReplicationEvent(
      key: key,
      value: tombstone ? null : value,
      nodeId: nodeId,
      sequenceNumber: sequenceNumber,
      timestampMs: timestampMs,
      tombstone: tombstone,
    );
  }
}

/// Defines an operation type for the [EventCoalescer].
enum UpdateOperation {
  set,
  delete,
}

/// Manages coalescing of rapid updates to the same keys before they are
/// converted to [ReplicationEvent]s and published.
///
/// This implementation focuses on pre-serialization coalescing where multiple
/// rapid updates to the same key are combined into a single update event
/// before entering the publication pipeline.
class EventCoalescer {
  /// The window of time during which updates to the same key may be coalesced.
  final Duration coalescingWindow;

  /// The maximum number of pending updates to keep before forcing a flush.
  final int maxPendingUpdates;

  /// Node ID used for creating replication events.
  final String nodeId;

  /// Internal map of pending updates, keyed by their key.
  final Map<String, PendingUpdate> _pendingUpdates = {};

  /// Timer used to flush updates after the coalescing window elapses.
  Timer? _flushTimer;

  /// Metrics recorder for monitoring coalescing performance.
  final MetricsRecorder? _metrics;

  /// Count of total coalesced updates (for metrics).
  int _totalCoalesced = 0;

  /// Total number of updates received.
  int _totalUpdates = 0;

  /// Creates an [EventCoalescer] with the specified parameters.
  ///
  /// The [coalescingWindow] determines how long updates to the same key will be
  /// coalesced before being flushed as replication events.
  ///
  /// The [maxPendingUpdates] sets an upper bound on how many pending updates
  /// can be held before a flush is forced, preventing unbounded memory growth.
  EventCoalescer({
    required this.nodeId,
    this.coalescingWindow = const Duration(milliseconds: 100),
    this.maxPendingUpdates = 1000,
    MetricsRecorder? metrics,
  }) : _metrics = metrics {
    // Start the flush timer
    _scheduleFlush();
  }

  /// Adds an update operation to be coalesced.
  ///
  /// If an update for the same [key] already exists within the coalescing window,
  /// the updates will be coalesced according to Last-Write-Wins semantics.
  ///
  /// Returns `true` if this update was coalesced with a previous update to the same key.
  /// Returns `false` if this is a new update or replaced a previous update.
  ///
  /// If the number of pending updates exceeds [maxPendingUpdates], this will
  /// trigger an immediate flush.
  bool addUpdate({
    required String key,
    String? value,
    required bool tombstone,
    required int timestampMs,
    required UpdateOperation operation,
  }) {
    _totalUpdates++;
    
    bool wasCoalesced = false;
    final existingUpdate = _pendingUpdates[key];

    if (existingUpdate != null) {
      // Coalesce with existing update
      wasCoalesced = existingUpdate.coalesceWith(
        value, 
        tombstone, 
        timestampMs,
      );
      
      if (wasCoalesced) {
        _totalCoalesced++;
        _recordCoalescingMetrics();
      }
    } else {
      // Create new pending update
      _pendingUpdates[key] = PendingUpdate(
        key: key,
        value: value,
        tombstone: tombstone,
        timestampMs: timestampMs,
      );
    }

    // Force flush if we've exceeded the max pending updates
    if (_pendingUpdates.length >= maxPendingUpdates) {
      // Fixed: provide a dummy sequence provider for the forced flush
      int sequenceCounter = 0;
      flushPending(() => ++sequenceCounter);
    }

    return wasCoalesced;
  }

  /// Flushes all pending updates and returns them as [ReplicationEvent]s.
  ///
  /// This method will convert all pending updates to replication events and
  /// clear the pending updates map. The events can then be passed to the
  /// batched publisher for publication.
  ///
  /// [sequenceProvider] is a function that returns the next sequence number
  /// for each event.
  List<ReplicationEvent> flushPending(int Function() sequenceProvider) {
    if (_pendingUpdates.isEmpty) {
      return [];
    }

    // Cancel the current timer if it exists
    _flushTimer?.cancel();

    try {
      // Convert pending updates to replication events
      final events = _pendingUpdates.values
          .map((update) => update.toReplicationEvent(
                nodeId, 
                sequenceProvider(),
              ))
          .toList();

      // Record metrics about this flush operation
      _recordFlushMetrics(events.length);

      return events;
    } finally {
      // Clear the pending updates map and reschedule the flush timer
      _pendingUpdates.clear();
      _scheduleFlush();
    }
  }

  /// Returns the current number of pending updates.
  int get pendingUpdatesCount => _pendingUpdates.length;

  /// Returns the effectiveness of coalescing as a ratio between 0 and 1.
  ///
  /// A value of 0 means no updates were coalesced.
  /// A value of 0.5 means half of the updates were coalesced.
  /// A value closer to 1 means most updates were coalesced.
  double get coalescingEffectiveness {
    if (_totalUpdates == 0) return 0.0;
    return _totalCoalesced / _totalUpdates;
  }

  /// Schedules a timer to flush pending updates after the coalescing window elapses.
  void _scheduleFlush() {
    _flushTimer?.cancel();
    _flushTimer = Timer(coalescingWindow, () {
      // When the timer fires, we don't actually flush here - this just indicates
      // that the coalescing window has elapsed and the next call to addUpdate
      // should trigger a flush if there are pending updates
    });
  }

  /// Records metrics related to coalescing operations.
  void _recordCoalescingMetrics() {
    _metrics?.incrementCounter(
      'replication_events_coalesced_total',
    );

    _metrics?.setGauge(
      'replication_coalescing_effectiveness',
      coalescingEffectiveness,
    );
  }

  /// Records metrics related to flush operations.
  void _recordFlushMetrics(int eventCount) {
    _metrics?.incrementCounter(
      'replication_coalescing_flushes_total',
    );

    _metrics?.recordHistogramValue(
      'replication_coalescing_flush_size',
      eventCount.toDouble(),
    );
  }

  /// Disposes resources used by this coalescer.
  @visibleForTesting
  void dispose() {
    _flushTimer?.cancel();
    _flushTimer = null;
    _pendingUpdates.clear();
  }
}