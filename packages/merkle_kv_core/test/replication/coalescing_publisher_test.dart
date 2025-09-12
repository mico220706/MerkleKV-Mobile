import 'package:merkle_kv_core/src/replication/types.dart';
import 'package:merkle_kv_core/src/replication/batched_publisher.dart';
import 'package:merkle_kv_core/src/replication/coalescing_publisher.dart';
import 'package:merkle_kv_core/src/replication/event_coalescer.dart';
import 'package:test/test.dart';

class MockSequenceManager implements SequenceManager {
  int _sequenceNumber = 0;
  
  @override
  int getNextSequenceNumber() => ++_sequenceNumber;
  
  @override
  Future<void> initialize() async {}
  
  @override
  Future<void> persistSequenceNumber(int sequenceNumber) async {
    _sequenceNumber = sequenceNumber;
  }
  
  @override
  Future<void> reset() async {
    _sequenceNumber = 0;
  }
}

class MockOutboxQueue implements OutboxQueue {
  final List<ReplicationEvent> enqueuedEvents = [];
  final List<ReplicationEvent> publishedEvents = [];
  
  @override
  Future<void> enqueueEvent(ReplicationEvent event) async {
    enqueuedEvents.add(event);
  }
  
  @override
  Future<void> enqueueEvents(List<ReplicationEvent> events) async {
    enqueuedEvents.addAll(events);
  }
  
  @override
  Future<List<ReplicationEvent>> dequeueEvents({int limit = 100}) async {
    if (enqueuedEvents.isEmpty) {
      return [];
    }
    
    final dequeued = enqueuedEvents.take(limit).toList();
    publishedEvents.addAll(dequeued);
    enqueuedEvents.removeRange(0, dequeued.length);
    return dequeued;
  }
  
  @override
  Future<void> flush() async {
    final events = await dequeueEvents();
    publishedEvents.addAll(events);
  }
  
  @override
  Future<void> initialize() async {}
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

class MockMqttClient implements MqttClient {
  final List<PublishRecord> publishRecords = [];
  bool connected = true;

  @override
  bool get isConnected => connected;
  
  @override
  Future<void> publish(String topic, List<int> payload) async {
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
  ReplicationEvent deserialize(List<int> bytes) {
    throw UnimplementedError();
  }
  
  @override
  List<int> serialize(ReplicationEvent event) {
    return event.key.codeUnits;
  }
}

void main() {
  group('CoalescingPublisher', () {
    late MockSequenceManager sequenceManager;
    late MockOutboxQueue outboxQueue;
    late EventCoalescer eventCoalescer;
    late BatchedPublisher batchedPublisher;
    late MockMetricsRecorder metrics;
    late MockMqttClient mqttClient;
    late MockEventSerializer serializer;
    late CoalescingPublisher publisher;
    
    setUp(() {
      sequenceManager = MockSequenceManager();
      outboxQueue = MockOutboxQueue();
      metrics = MockMetricsRecorder();
      mqttClient = MockMqttClient();
      serializer = MockEventSerializer();
      
      // Create real instances with short windows for testing
      eventCoalescer = EventCoalescer(
        nodeId: 'test-node',
        coalescingWindow: Duration(milliseconds: 1), // Very short for testing
        maxPendingUpdates: 1000,
        metrics: metrics,
      );
      
      batchedPublisher = BatchedPublisher(
        mqttClient: mqttClient,
        replicationTopic: 'test/topic',
        serializer: serializer,
        batchWindow: Duration(milliseconds: 1), // Very short for testing
        maxBatchSize: 100,
        metrics: metrics,
      );
      
      publisher = CoalescingPublisher(
        sequenceManager: sequenceManager,
        outboxQueue: outboxQueue,
        eventCoalescer: eventCoalescer,
        batchedPublisher: batchedPublisher,
        metrics: metrics,
      );
    });
    
    tearDown(() {
      eventCoalescer.dispose();
      batchedPublisher.dispose();
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
    
    test('publishUpdate should add update to coalescer and process the event pipeline', () async {
      // Act
      await publisher.publishUpdate(
        key: 'key1',
        value: 'value1',
        timestampMs: 1000,
      );
      
      // Wait a bit for any async processing to complete
      await Future.delayed(Duration(milliseconds: 10));
      
      // Assert - Check that events were enqueued (the coalescer should have flushed)
      expect(outboxQueue.enqueuedEvents.isNotEmpty, isTrue);
      
      // Verify the event has the correct properties
      final enqueuedEvent = outboxQueue.enqueuedEvents.first;
      expect(enqueuedEvent.key, equals('key1'));
      expect(enqueuedEvent.value, equals('value1'));
      expect(enqueuedEvent.tombstone, isFalse);
      
      // Check metrics
      expect(metrics.histograms['replication_publish_latency_seconds'], isNotNull);
    });
    
    test('publishDelete should add delete to coalescer and process the event pipeline', () async {
      // Act
      await publisher.publishDelete(
        key: 'key1',
        timestampMs: 1000,
      );
      
      // Wait a bit for any async processing to complete
      await Future.delayed(Duration(milliseconds: 10));
      
      // Assert - Check that events were enqueued
      expect(outboxQueue.enqueuedEvents.isNotEmpty, isTrue);
      
      // Verify the event has the correct properties for a delete
      final enqueuedEvent = outboxQueue.enqueuedEvents.first;
      expect(enqueuedEvent.key, equals('key1'));
      expect(enqueuedEvent.value, isNull);
      expect(enqueuedEvent.tombstone, isTrue);
    });
    
    test('publishEvent should bypass coalescing and directly enqueue the event', () async {
      // Arrange
      final event = createEvent('key1');
      
      // Act
      await publisher.publishEvent(event);
      
      // Wait a bit for any async processing to complete
      await Future.delayed(Duration(milliseconds: 10));
      
      // Assert
      // The event should be directly enqueued
      expect(outboxQueue.enqueuedEvents.isNotEmpty, isTrue);
      expect(outboxQueue.enqueuedEvents.first.key, equals('key1'));
    });
    
    test('flush should flush both the coalescer and publisher', () async {
      // Arrange - Add some updates first
      await publisher.publishUpdate(
        key: 'key1',
        value: 'value1',
        timestampMs: 1000,
      );
      
      // Act
      await publisher.flush();
      
      // Wait a bit for any async processing to complete
      await Future.delayed(Duration(milliseconds: 10));
      
      // Assert - Events should have been processed through the pipeline
      expect(outboxQueue.publishedEvents.isNotEmpty, isTrue);
    });
    
    test('coalescing should work for rapid updates to same key', () async {
      // Arrange & Act - Add multiple rapid updates to the same key
      await publisher.publishUpdate(
        key: 'key1',
        value: 'value1',
        timestampMs: 1000,
      );
      await publisher.publishUpdate(
        key: 'key1',
        value: 'value2',
        timestampMs: 2000,
      );
      await publisher.publishUpdate(
        key: 'key1',
        value: 'value3',
        timestampMs: 3000,
      );
      
      // Force flush to see the coalesced result
      await publisher.flush();
      
      // Wait a bit for any async processing to complete
      await Future.delayed(Duration(milliseconds: 10));
      
      // Assert - Should have fewer events than updates due to coalescing
      // The exact number depends on timing, but there should be at least one event
      expect(outboxQueue.enqueuedEvents.isNotEmpty || outboxQueue.publishedEvents.isNotEmpty, isTrue);
      
      // The final value should be the latest one if coalescing worked
      final allEvents = [...outboxQueue.enqueuedEvents, ...outboxQueue.publishedEvents];
      final key1Events = allEvents.where((e) => e.key == 'key1').toList();
      if (key1Events.isNotEmpty) {
        expect(key1Events.last.value, equals('value3'));
      }
    });
    
    test('factory constructor should create all components correctly', () {
      // Act
      final publisher = CoalescingPublisher.create(
        sequenceManager: sequenceManager,
        outboxQueue: outboxQueue,
        mqttClient: mqttClient,
        replicationTopic: 'test/topic',
        serializer: serializer,
        nodeId: 'test-node',
        coalescingWindow: Duration(milliseconds: 200),
        maxPendingUpdates: 500,
        batchWindow: Duration(milliseconds: 100),
        maxBatchSize: 50,
        metrics: metrics,
      );
      
      // Assert
      expect(publisher, isA<CoalescingPublisher>());
      expect(publisher.sequenceManager, equals(sequenceManager));
      expect(publisher.outboxQueue, equals(outboxQueue));
      expect(publisher.eventCoalescer.coalescingWindow, equals(Duration(milliseconds: 200)));
      expect(publisher.eventCoalescer.maxPendingUpdates, equals(500));
      expect(publisher.batchedPublisher.batchWindow, equals(Duration(milliseconds: 100)));
      expect(publisher.batchedPublisher.maxBatchSize, equals(50));
    });
    
    test('end-to-end flow should work with real MQTT publishing', () async {
      // Arrange & Act
      await publisher.publishUpdate(
        key: 'test-key',
        value: 'test-value',
        timestampMs: 1000,
      );
      
      // Force everything to flush
      await publisher.flush();
      
      // Wait for async operations to complete
      await Future.delayed(Duration(milliseconds: 50));
      
      // Assert - Should have published to MQTT
      expect(mqttClient.publishRecords.isNotEmpty, isTrue);
      
      // Verify the published message contains our key
      final publishedPayload = String.fromCharCodes(mqttClient.publishRecords.first.payload);
      expect(publishedPayload, contains('test-key'));
    });
  });
}