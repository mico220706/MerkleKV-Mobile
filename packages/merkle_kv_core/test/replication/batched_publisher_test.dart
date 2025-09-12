import 'dart:async';

import 'package:merkle_kv_core/src/metrics/metrics_recorder.dart';
import 'package:merkle_kv_core/src/replication/batched_publisher.dart';
import 'package:merkle_kv_core/src/replication/mqtt/mqtt_client.dart';
import 'package:merkle_kv_core/src/replication/replication_event.dart';
import 'package:merkle_kv_core/src/replication/serialization/event_serializer.dart';
import 'package:test/test.dart';

class MockMqttClient implements MqttClient {
  final List<PublishRecord> publishRecords = [];
  bool connected = true;
  bool throwOnPublish = false;

  @override
  bool get isConnected => connected;

  @override
  Future<void> publish(String topic, List<int> payload) async {
    if (throwOnPublish) {
      throw Exception('Failed to publish');
    }
    publishRecords.add(PublishRecord(topic, payload));
  }
}

class PublishRecord {
  final String topic;
  final List<int> payload;

  PublishRecord(this.topic, this.payload);
}

class MockEventSerializer implements EventSerializer {
  @override
  List<int> serialize(ReplicationEvent event) {
    // Simple mock serialization: just convert the key to bytes
    return event.key.codeUnits;
  }

  @override
  ReplicationEvent deserialize(List<int> bytes) {
    throw UnimplementedError();
  }
}

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
  group('BatchedPublisher', () {
    late BatchedPublisher publisher;
    late MockMqttClient mqttClient;
    late MockEventSerializer serializer;
    late MockMetricsRecorder metrics;
    const String topic = 'test/topic';

    setUp(() {
      mqttClient = MockMqttClient();
      serializer = MockEventSerializer();
      metrics = MockMetricsRecorder();
      publisher = BatchedPublisher(
        mqttClient: mqttClient,
        replicationTopic: topic,
        serializer: serializer,
        batchWindow: Duration(milliseconds: 50),
        maxBatchSize: 5,
        metrics: metrics,
      );
    });

    tearDown(() {
      publisher.dispose();
    });

    ReplicationEvent createEvent(String key, {int sequenceNumber = 1}) {
      return ReplicationEvent(
        key: key,
        value: 'value',
        nodeId: 'node1',
        sequenceNumber: sequenceNumber,
        timestampMs: 1000,
        tombstone: false,
      );
    }

    test('should publish events as separate MQTT messages', () async {
      // Arrange
      final events = [
        createEvent('key1'),
        createEvent('key2'),
        createEvent('key3'),
      ];

      // Act
      await publisher.schedulePublish(events);
      await publisher.flushPending(); // Force immediate publishing

      // Assert
      expect(mqttClient.publishRecords.length, equals(3));
      expect(mqttClient.publishRecords[0].topic, equals(topic));
      expect(mqttClient.publishRecords[0].payload, equals('key1'.codeUnits));
      expect(mqttClient.publishRecords[1].topic, equals(topic));
      expect(mqttClient.publishRecords[1].payload, equals('key2'.codeUnits));
      expect(mqttClient.publishRecords[2].topic, equals(topic));
      expect(mqttClient.publishRecords[2].payload, equals('key3'.codeUnits));
    });

    test('should publish immediately when max batch size is reached', () async {
      // Arrange
      final events = List.generate(6, (i) => createEvent('key$i'));

      // Act
      await publisher.schedulePublish(events);
      
      // Wait a bit to allow publishing to complete
      await Future.delayed(Duration(milliseconds: 10));

      // Assert - should have published at least 5 events immediately
      expect(mqttClient.publishRecords.length, greaterThanOrEqualTo(5));
    });

    test('should publish after batch window elapses', () async {
      // Arrange
      final events = [createEvent('key1'), createEvent('key2')];

      // Act
      await publisher.schedulePublish(events);
      
      // Wait for the batch window to elapse
      await Future.delayed(Duration(milliseconds: 60));

      // Assert
      expect(mqttClient.publishRecords.length, equals(2));
    });

    test('should record metrics for successful publishes', () async {
      // Arrange
      final events = [createEvent('key1'), createEvent('key2')];

      // Act
      await publisher.schedulePublish(events);
      await publisher.flushPending();

      // Assert
      expect(metrics.counters['replication_events_published_total'], equals(2));
      expect(metrics.counters['replication_batches_published_total'], equals(1));
      expect(metrics.histograms['replication_batch_size_distribution']?.first, equals(2));
      expect(metrics.gauges['replication_events_per_publish_ratio'], equals(1.0));
    });

    test('should handle publish errors gracefully', () async {
      // Arrange
      mqttClient.throwOnPublish = true;
      final events = [createEvent('key1'), createEvent('key2')];

      // Act & Assert
      await publisher.schedulePublish(events);
      await publisher.flushPending();
      
      expect(metrics.counters['replication_batch_publish_errors_total'], equals(2));
    });

    test('should process multiple batches in sequence', () async {
      // Arrange
      final batch1 = List.generate(3, (i) => createEvent('batch1_key$i'));
      final batch2 = List.generate(3, (i) => createEvent('batch2_key$i'));

      // Act
      await publisher.schedulePublish(batch1);
      await publisher.flushPending();
      await publisher.schedulePublish(batch2);
      await publisher.flushPending();

      // Assert
      expect(mqttClient.publishRecords.length, equals(6));
      for (int i = 0; i < 3; i++) {
        expect(mqttClient.publishRecords[i].payload, equals('batch1_key$i'.codeUnits));
        expect(mqttClient.publishRecords[i + 3].payload, equals('batch2_key$i'.codeUnits));
      }
    });
  });
}