// Add missing interfaces and imports directly
abstract class MetricsRecorder {
  void incrementCounter(String name, {int increment = 1});
  void setGauge(String name, double value);
  void recordHistogramValue(String name, double value);
}

abstract class MqttClient {
  bool get isConnected;
  Future<void> publish(String topic, List<int> payload);
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

abstract class EventSerializer {
  List<int> serialize(ReplicationEvent event);
  ReplicationEvent deserialize(List<int> bytes);
}

abstract class SequenceManager {
  Future<void> initialize();
  int getNextSequenceNumber();
  Future<void> persistSequenceNumber(int sequenceNumber);
  Future<void> reset();
}

abstract class OutboxQueue {
  Future<void> initialize();
  Future<void> enqueueEvent(ReplicationEvent event);
  Future<void> enqueueEvents(List<ReplicationEvent> events);
  Future<List<ReplicationEvent>> dequeueEvents({int limit = 100});
  Future<void> flush();
}

abstract class ReplicationEventPublisher {
  Future<void> publishUpdate({
    required String key,
    required String value,
    required int timestampMs,
  });
  Future<void> publishDelete({
    required String key,
    required int timestampMs,
  });
  Future<void> publishEvent(ReplicationEvent event);
  Future<void> flush();
}

enum UpdateOperation {
  set,
  delete,
}

// Include the EventCoalescer and BatchedPublisher classes here or import them
// For now, let's create minimal interfaces
abstract class EventCoalescer {
  Duration get coalescingWindow;
  int get maxPendingUpdates;
  String get nodeId;
  int get pendingUpdatesCount;
  double get coalescingEffectiveness;
  
  bool addUpdate({
    required String key,
    String? value,
    required bool tombstone,
    required int timestampMs,
    required UpdateOperation operation,
  });
  
  List<ReplicationEvent> flushPending(int Function() sequenceProvider);
  void dispose();
}

abstract class BatchedPublisher {
  Duration get batchWindow;
  int get maxBatchSize;
  MqttClient get mqttClient;
  String get replicationTopic;
  EventSerializer get serializer;
  
  Future<void> schedulePublish(List<ReplicationEvent> events);
  Future<void> flushPending();
  void dispose();
}

/// A [ReplicationEventPublisher] implementation that combines coalescing and batching
/// to efficiently publish replication events while maintaining the protocol requirement
/// of one CBOR event per MQTT publish.
///
/// This class integrates the [EventCoalescer] for pre-serialization coalescing of rapid
/// updates to the same key and the [BatchedPublisher] for efficient publication while
/// maintaining the one-event-per-publish requirement.
class CoalescingPublisher implements ReplicationEventPublisher {
  /// Manager for assigning sequence numbers to events.
  final SequenceManager sequenceManager;

  /// Queue for buffering events during offline periods.
  final OutboxQueue outboxQueue;

  /// Coalescer for combining rapid updates to the same key.
  final EventCoalescer eventCoalescer;

  /// Publisher for batching the publication process.
  final BatchedPublisher batchedPublisher;

  /// Metrics recorder for monitoring performance.
  final MetricsRecorder? _metrics;

  /// Creates a [CoalescingPublisher] with the specified components.
  CoalescingPublisher({
    required this.sequenceManager,
    required this.outboxQueue,
    required this.eventCoalescer,
    required this.batchedPublisher,
    MetricsRecorder? metrics,
  }) : _metrics = metrics;

  @override
  Future<void> publishUpdate({
    required String key,
    required String value,
    required int timestampMs,
  }) async {
    final stopwatch = Stopwatch()..start();

    try {
      // Add to coalescer
      eventCoalescer.addUpdate(
        key: key,
        value: value,
        tombstone: false,
        timestampMs: timestampMs,
        operation: UpdateOperation.set,
      );

      // Flush coalescer and get events
      final events = eventCoalescer.flushPending(
        () => sequenceManager.getNextSequenceNumber(),
      );

      // Add events to outbox queue
      await outboxQueue.enqueueEvents(events);

      // Schedule publication of events from the outbox
      await _tryPublishFromOutbox();
    } finally {
      stopwatch.stop();
      _recordPublishLatency(stopwatch.elapsedMicroseconds / 1000000.0);
    }
  }

  @override
  Future<void> publishDelete({
    required String key,
    required int timestampMs,
  }) async {
    final stopwatch = Stopwatch()..start();

    try {
      // Add to coalescer
      eventCoalescer.addUpdate(
        key: key,
        value: null,
        tombstone: true,
        timestampMs: timestampMs,
        operation: UpdateOperation.delete,
      );

      // Flush coalescer and get events
      final events = eventCoalescer.flushPending(
        () => sequenceManager.getNextSequenceNumber(),
      );

      // Add events to outbox queue
      await outboxQueue.enqueueEvents(events);

      // Schedule publication of events from the outbox
      await _tryPublishFromOutbox();
    } finally {
      stopwatch.stop();
      _recordPublishLatency(stopwatch.elapsedMicroseconds / 1000000.0);
    }
  }

  @override
  Future<void> publishEvent(ReplicationEvent event) async {
    final stopwatch = Stopwatch()..start();

    try {
      // Add to outbox queue directly, bypassing coalescing
      await outboxQueue.enqueueEvent(event);

      // Schedule publication
      await _tryPublishFromOutbox();
    } finally {
      stopwatch.stop();
      _recordPublishLatency(stopwatch.elapsedMicroseconds / 1000000.0);
    }
  }

  @override
  Future<void> flush() async {
    // Flush both the coalescer and the batched publisher
    final events = eventCoalescer.flushPending(
      () => sequenceManager.getNextSequenceNumber(),
    );

    if (events.isNotEmpty) {
      await outboxQueue.enqueueEvents(events);
    }

    await batchedPublisher.flushPending();
    await outboxQueue.flush();
  }

  /// Attempts to publish events from the outbox queue if the MQTT client is connected.
  Future<void> _tryPublishFromOutbox() async {
    final events = await outboxQueue.dequeueEvents(limit: batchedPublisher.maxBatchSize);
    if (events.isNotEmpty) {
      await batchedPublisher.schedulePublish(events);
    }
  }

  /// Records latency metrics for a publish operation.
  void _recordPublishLatency(double durationSeconds) {
    _metrics?.recordHistogramValue(
      'replication_publish_latency_seconds',
      durationSeconds,
    );
  }
}