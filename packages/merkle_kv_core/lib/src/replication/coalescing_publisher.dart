import 'types.dart';
import 'event_coalescer.dart';
import 'batched_publisher.dart';

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

  /// Creates a [CoalescingPublisher] with default components based on the provided parameters.
  factory CoalescingPublisher.create({
    required SequenceManager sequenceManager,
    required OutboxQueue outboxQueue,
    required MqttClient mqttClient,
    required String replicationTopic,
    required EventSerializer serializer,
    required String nodeId,
    Duration coalescingWindow = const Duration(milliseconds: 100),
    int maxPendingUpdates = 1000,
    Duration batchWindow = const Duration(milliseconds: 50),
    int maxBatchSize = 100,
    MetricsRecorder? metrics,
  }) {
    final eventCoalescer = EventCoalescer(
      nodeId: nodeId,
      coalescingWindow: coalescingWindow,
      maxPendingUpdates: maxPendingUpdates,
      metrics: metrics,
    );

    final batchedPublisher = BatchedPublisher(
      mqttClient: mqttClient,
      replicationTopic: replicationTopic,
      serializer: serializer,
      batchWindow: batchWindow,
      maxBatchSize: maxBatchSize,
      metrics: metrics,
    );

    return CoalescingPublisher(
      sequenceManager: sequenceManager,
      outboxQueue: outboxQueue,
      eventCoalescer: eventCoalescer,
      batchedPublisher: batchedPublisher,
      metrics: metrics,
    );
  }

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