import 'package:merkle_kv_core/src/metrics/metrics_recorder.dart';
import 'package:merkle_kv_core/src/replication/event_coalescer.dart';
import 'package:merkle_kv_core/src/replication/replication_event.dart';
import 'package:test/test.dart';

class MockMetricsRecorder implements MetricsRecorder {
  final Map<String, int> counters = {};
  final Map<String, double> gauges = {};
  final Map<String, List<double>> histograms = {};

  @override
  void incrementCounter(String name, {int increment = 1}) {
    counters[name] = (counters[name] ?? 0) + increment;
  }

  @override
  void recordHistogramValue(String name, double value) {
    histograms.putIfAbsent(name, () => []).add(value);
  }

  @override
  void setGauge(String name, double value) {
    gauges[name] = value;
  }
}

void main() {
  group('EventCoalescer', () {
    late EventCoalescer coalescer;
    late MockMetricsRecorder metrics;
    const String nodeId = 'test-node';

    setUp(() {
      metrics = MockMetricsRecorder();
      coalescer = EventCoalescer(
        nodeId: nodeId,
        coalescingWindow: Duration(milliseconds: 100),
        maxPendingUpdates: 10,
        metrics: metrics,
      );
    });

    tearDown(() {
      coalescer.dispose();
    });

    test('should create a new pending update when key does not exist', () {
      // Act
      final wasCoalesced = coalescer.addUpdate(
        key: 'key1',
        value: 'value1',
        tombstone: false,
        timestampMs: 1000,
        operation: UpdateOperation.set,
      );

      // Assert
      expect(wasCoalesced, isFalse);
      expect(coalescer.pendingUpdatesCount, equals(1));
    });

    test('should coalesce updates to the same key with newer timestamp', () {
      // Arrange
      coalescer.addUpdate(
        key: 'key1',
        value: 'value1',
        tombstone: false,
        timestampMs: 1000,
        operation: UpdateOperation.set,
      );

      // Act
      final wasCoalesced = coalescer.addUpdate(
        key: 'key1',
        value: 'value2',
        tombstone: false,
        timestampMs: 2000,
        operation: UpdateOperation.set,
      );

      // Assert
      expect(wasCoalesced, isTrue);
      expect(coalescer.pendingUpdatesCount, equals(1));
      expect(metrics.counters['replication_events_coalesced_total'], equals(1));
    });

    test('should not coalesce updates to the same key with older timestamp', () {
      // Arrange
      coalescer.addUpdate(
        key: 'key1',
        value: 'value2',
        tombstone: false,
        timestampMs: 2000,
        operation: UpdateOperation.set,
      );

      // Act
      final wasCoalesced = coalescer.addUpdate(
        key: 'key1',
        value: 'value1',
        tombstone: false,
        timestampMs: 1000,
        operation: UpdateOperation.set,
      );

      // Assert
      expect(wasCoalesced, isFalse);
      expect(coalescer.pendingUpdatesCount, equals(1));
      expect(metrics.counters['replication_events_coalesced_total'], isNull);
    });

    test('should flush pending updates and return replication events', () {
      // Arrange
      coalescer.addUpdate(
        key: 'key1',
        value: 'value1',
        tombstone: false,
        timestampMs: 1000,
        operation: UpdateOperation.set,
      );
      coalescer.addUpdate(
        key: 'key2',
        value: 'value2',
        tombstone: false,
        timestampMs: 2000,
        operation: UpdateOperation.set,
      );

      // Act
      int sequenceNumber = 0;
      final events = coalescer.flushPending(() => ++sequenceNumber);

      // Assert
      expect(events.length, equals(2));
      expect(events[0].key, equals('key1'));
      expect(events[0].value, equals('value1'));
      expect(events[0].sequenceNumber, equals(1));
      expect(events[0].nodeId, equals(nodeId));
      expect(events[0].timestampMs, equals(1000));
      expect(events[0].tombstone, isFalse);

      expect(events[1].key, equals('key2'));
      expect(events[1].value, equals('value2'));
      expect(events[1].sequenceNumber, equals(2));
      expect(events[1].nodeId, equals(nodeId));
      expect(events[1].timestampMs, equals(2000));
      expect(events[1].tombstone, isFalse);

      // Check metrics
      expect(metrics.counters['replication_coalescing_flushes_total'], equals(1));
      expect(metrics.histograms['replication_coalescing_flush_size']?.first, equals(2));
    });

    test('should coalesce tombstone operations', () {
      // Arrange
      coalescer.addUpdate(
        key: 'key1',
        value: 'value1',
        tombstone: false,
        timestampMs: 1000,
        operation: UpdateOperation.set,
      );

      // Act
      final wasCoalesced = coalescer.addUpdate(
        key: 'key1',
        value: null,
        tombstone: true,
        timestampMs: 2000,
        operation: UpdateOperation.delete,
      );

      // Assert
      expect(wasCoalesced, isTrue);
      expect(coalescer.pendingUpdatesCount, equals(1));

      // Verify the tombstone is correctly set in the flushed event
      int sequenceNumber = 0;
      final events = coalescer.flushPending(() => ++sequenceNumber);
      expect(events.length, equals(1));
      expect(events[0].key, equals('key1'));
      expect(events[0].value, isNull);
      expect(events[0].tombstone, isTrue);
    });

    test('should force flush when max pending updates is reached', () {
      // Arrange & Act
      for (int i = 0; i < 10; i++) {
        coalescer.addUpdate(
          key: 'key$i',
          value: 'value$i',
          tombstone: false,
          timestampMs: 1000 + i,
          operation: UpdateOperation.set,
        );
      }

      // Assert
      // The 11th update should trigger a flush
      int sequenceNumber = 0;
      coalescer.addUpdate(
        key: 'key11',
        value: 'value11',
        tombstone: false,
        timestampMs: 2000,
        operation: UpdateOperation.set,
      );

      // Only the 11th update should remain after the forced flush
      expect(coalescer.pendingUpdatesCount, equals(1));
    });

    test('should calculate coalescing effectiveness', () {
      // Arrange
      coalescer.addUpdate(
        key: 'key1',
        value: 'value1',
        tombstone: false,
        timestampMs: 1000,
        operation: UpdateOperation.set,
      );
      coalescer.addUpdate(
        key: 'key1',
        value: 'value2',
        tombstone: false,
        timestampMs: 2000,
        operation: UpdateOperation.set,
      );
      coalescer.addUpdate(
        key: 'key2',
        value: 'value3',
        tombstone: false,
        timestampMs: 3000,
        operation: UpdateOperation.set,
      );

      // Act & Assert
      // Total updates: 3, Coalesced: 1
      expect(coalescer.coalescingEffectiveness, equals(1.0 / 3.0));
    });
  });
}