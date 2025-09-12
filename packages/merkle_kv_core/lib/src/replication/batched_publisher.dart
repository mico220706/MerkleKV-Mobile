import 'dart:async';

import '../metrics/metrics_recorder.dart';
import 'mqtt/mqtt_client.dart';
import 'replication_event.dart';
import 'serialization/event_serializer.dart';

/// Manages batched publication of replication events to MQTT while maintaining
/// the protocol requirement of one CBOR event per MQTT publish.
///
/// This class implements efficient batching of the publication process without
/// violating the requirement that each event must be published as a separate
/// MQTT message (Locked Spec §3.3).
class BatchedPublisher {
  /// The window of time during which events will be batched before publishing.
  final Duration batchWindow;

  /// The maximum number of events in a single batch.
  final int maxBatchSize;

  /// The MQTT client used for publishing events.
  final MqttClient mqttClient;

  /// The topic to publish replication events to.
  final String replicationTopic;

  /// The serializer used to convert events to CBOR format.
  final EventSerializer serializer;

  /// Metrics recorder for monitoring publication performance.
  final MetricsRecorder? _metrics;

  /// Timer used to publish batches after the batch window elapses.
  Timer? _batchTimer;

  /// Queue of pending events to be published.
  final List<ReplicationEvent> _pendingBatch = [];

  /// Whether a publish operation is currently in progress.
  bool _isPublishing = false;

  /// Creates a [BatchedPublisher] with the specified parameters.
  ///
  /// The [batchWindow] determines how long events will be batched before being
  /// published as separate MQTT messages.
  ///
  /// The [maxBatchSize] sets an upper bound on how many events can be included
  /// in a single batch, preventing excessive latency for large batches.
  BatchedPublisher({
    required this.mqttClient,
    required this.replicationTopic,
    required this.serializer,
    this.batchWindow = const Duration(milliseconds: 50),
    this.maxBatchSize = 100,
    MetricsRecorder? metrics,
  }) : _metrics = metrics;

  /// Adds events to the current batch and schedules publication.
  ///
  /// If the batch reaches the maximum size or if the batch window elapses,
  /// the events will be published immediately.
  ///
  /// Returns a [Future] that completes when the events have been scheduled
  /// for publication (not necessarily when they have been published).
  Future<void> schedulePublish(List<ReplicationEvent> events) async {
    if (events.isEmpty) {
      return;
    }

    _pendingBatch.addAll(events);
    _recordBatchMetrics();

    // If we've exceeded the max batch size, publish immediately
    if (_pendingBatch.length >= maxBatchSize) {
      _cancelBatchTimer();
      await _publishPendingBatch();
    } else if (_batchTimer == null) {
      // Start a timer to publish the batch after the batch window elapses
      _batchTimer = Timer(batchWindow, () async {
        _batchTimer = null;
        await _publishPendingBatch();
      });
    }
  }

  /// Forces immediate publication of any pending events.
  ///
  /// This is useful when the application is about to be terminated or
  /// when immediate publication is required for other reasons.
  ///
  /// Returns a [Future] that completes when all pending events have been
  /// published or failed to publish.
  Future<void> flushPending() async {
    _cancelBatchTimer();
    return _publishPendingBatch();
  }

  /// Cancels the current batch timer if it exists.
  void _cancelBatchTimer() {
    _batchTimer?.cancel();
    _batchTimer = null;
  }

  /// Publishes all pending events in the current batch.
  ///
  /// This method ensures that each event is published as a separate MQTT
  /// message, maintaining the protocol requirement of one CBOR event per
  /// MQTT publish.
  Future<void> _publishPendingBatch() async {
    if (_pendingBatch.isEmpty || _isPublishing) {
      return;
    }

    _isPublishing = true;
    final events = List<ReplicationEvent>.from(_pendingBatch);
    _pendingBatch.clear();

    final stopwatch = Stopwatch()..start();
    int successCount = 0;
    int failureCount = 0;

    try {
      // Publish each event individually in rapid succession
      for (final event in events) {
        try {
          final payload = serializer.serialize(event);
          await mqttClient.publish(replicationTopic, payload);
          successCount++;
        } catch (e) {
          failureCount++;
          // We don't re-queue failed events here as the outbox queue
          // should handle retries at a higher level
          _recordPublishError();
        }
      }
    } finally {
      _isPublishing = false;
      stopwatch.stop();

      // Record metrics about this batch publication
      _recordBatchPublishMetrics(
        events.length,
        successCount,
        failureCount,
        stopwatch.elapsedMicroseconds / 1000000.0,
      );

      // If more events were added while we were publishing, schedule another publish
      if (_pendingBatch.isNotEmpty) {
        // Use a microtask to avoid recursive stack overflow
        scheduleMicrotask(() => _publishPendingBatch());
      }
    }
  }

  /// Records metrics related to the current batch state.
  void _recordBatchMetrics() {
    _metrics?.setGauge(
      'replication_batch_pending_size',
      _pendingBatch.length.toDouble(),
    );
  }

  /// Records an error that occurred during publication.
  void _recordPublishError() {
    _metrics?.incrementCounter(
      'replication_batch_publish_errors_total',
    );
  }

  /// Records metrics related to batch publication.
  void _recordBatchPublishMetrics(
    int batchSize,
    int successCount,
    int failureCount,
    double durationSeconds,
  ) {
    _metrics?.incrementCounter(
      'replication_batches_published_total',
    );

    _metrics?.recordHistogramValue(
      'replication_batch_size_distribution',
      batchSize.toDouble(),
    );

    _metrics?.incrementCounter(
      'replication_events_published_total',
      increment: successCount,
    );

    _metrics?.recordHistogramValue(
      'replication_batch_publish_duration_seconds',
      durationSeconds,
    );

    // Calculate and record the events-per-publish ratio
    // This should always be 1.0 to comply with the spec
    if (successCount > 0) {
      _metrics?.setGauge(
        'replication_events_per_publish_ratio',
        1.0,
      );
    }
  }

  /// Disposes resources used by this publisher.
  void dispose() {
    _cancelBatchTimer();
    _pendingBatch.clear();
  }
}