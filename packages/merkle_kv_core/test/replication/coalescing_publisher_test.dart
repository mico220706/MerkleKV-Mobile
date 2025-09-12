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
    print('MockOutboxQueue: Enqueued single event: ${event.key}');
  }
  
  @override
  Future<void> enqueueEvents(List<ReplicationEvent> events) async {
    enqueuedEvents.addAll(events);
    print('MockOutboxQueue: Enqueued ${events.length} events');
  }
  
  @override
  Future<List<ReplicationEvent>> dequeueEvents({int limit = 100}) async {
    if (enqueuedEvents.isEmpty) {
      return [];
    }
    
    final dequeued = enqueuedEvents.take(limit).toList();
    publishedEvents.addAll(dequeued);
    enqueuedEvents.removeRange(0, dequeued.length);
    print('MockOutboxQueue: Dequeued ${dequeued.length} events');
    return dequeued;
  }
  
  @override
  Future<void> flush() async {
    final events = await dequeueEvents();
    publishedEvents.addAll(events);
    print('MockOutboxQueue: Flushed ${events.length} events');
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
      
      // Create real instances
      eventCoalescer = EventCoalescer(
        nodeId: 'test-node',
        coalescingWindow: Duration(milliseconds: 100),
        maxPendingUpdates: 1000,
        metrics: metrics,
      );
      
      batchedPublisher = BatchedPublisher(
        mqttClient: mqttClient,
        replicationTopic: 'test/topic',
        serializer: serializer,
        batchWindow: Duration(milliseconds: 50),
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
      print('=== Starting publishUpdate test ===');
      
      // Act
      await publisher.publishUpdate(
        key: 'key1',
        value: 'value1',
        timestampMs: 1000,
      );
      
      print('After publishUpdate - enqueuedEvents: ${outboxQueue.enqueuedEvents.length}');
      print('Pending updates in coalescer: ${eventCoalescer.pendingUpdatesCount}');
      
      // The issue is that EventCoalescer doesn't automatically flush!
      // We need to manually flush or wait for the timer or trigger max pending
      
      // Force flush by calling flush on the publisher
      await publisher.flush();
      
      print('After flush - enqueuedEvents: ${outboxQueue.enqueuedEvents.length}');
      print('Published events: ${outboxQueue.publishedEvents.length}');
      
      // Assert - Check that events were processed somewhere
      final totalEvents = outboxQueue.enqueuedEvents.length + outboxQueue.publishedEvents.length;
      expect(totalEvents > 0, isTrue, reason: 'Expected events to be processed through the pipeline');
      
      // Check metrics
      expect(metrics.histograms['replication_publish_latency_seconds'], isNotNull);
    });
    
    test('publishDelete should add delete to coalescer and process the event pipeline', () async {
      print('=== Starting publishDelete test ===');
      
      // Act
      await publisher.publishDelete(
        key: 'key1',
        timestampMs: 1000,
      );
      
      // Force flush to see the result
      await publisher.flush();
      
      print('After flush - enqueuedEvents: ${outboxQueue.enqueuedEvents.length}');
      print('Published events: ${outboxQueue.publishedEvents.length}');
      
      // Assert - Check that events were processed
      final totalEvents = outboxQueue.enqueuedEvents.length + outboxQueue.publishedEvents.length;
      expect(totalEvents > 0, isTrue, reason: 'Expected delete event to be processed');
      
      // Verify it's a tombstone if we can find the event
      final allEvents = [...outboxQueue.enqueuedEvents, ...outboxQueue.publishedEvents];
      if (allEvents.isNotEmpty) {
        final deleteEvent = allEvents.firstWhere((e) => e.key == 'key1');
        expect(deleteEvent.tombstone, isTrue);
        expect(deleteEvent.value, isNull);
      }
    });
    
    test('publishEvent should bypass coalescing and directly enqueue the event', () async {
      print('=== Starting publishEvent test ===');
      
      // Arrange
      final event = createEvent('key1');
      
      // Act
      await publisher.publishEvent(event);
      
      print('After publishEvent - enqueuedEvents: ${outboxQueue.enqueuedEvents.length}');
      
      // This should directly enqueue, so we should see it immediately
      expect(outboxQueue.enqueuedEvents.length > 0, isTrue, 
             reason: 'Expected event to be directly enqueued, bypassing coalescing');
      
      expect(outboxQueue.enqueuedEvents.first.key, equals('key1'));
    });
    
    test('flush should process any pending updates', () async {
      // Arrange - Add some updates first
      await publisher.publishUpdate(
        key: 'key1',
        value: 'value1',
        timestampMs: 1000,
      );
      
      print('Before flush - pending updates: ${eventCoalescer.pendingUpdatesCount}');
      
      // Act
      await publisher.flush();
      
      print('After flush - enqueuedEvents: ${outboxQueue.enqueuedEvents.length}');
      print('After flush - publishedEvents: ${outboxQueue.publishedEvents.length}');
      
      // Assert - Events should have been processed
      final totalEvents = outboxQueue.enqueuedEvents.length + outboxQueue.publishedEvents.length;
      expect(totalEvents > 0, isTrue, reason: 'Flush should process pending updates');
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
    
    test('coalescing behavior should work correctly', () async {
      // Test the EventCoalescer directly to make sure it works
      eventCoalescer.addUpdate(
        key: 'test-key',
        value: 'value1',
        timestampMs: 1000,
        tombstone: false,
        operation: UpdateOperation.set,
      );
      
      expect(eventCoalescer.pendingUpdatesCount, equals(1));
      
      // Manually flush the coalescer
      final events = eventCoalescer.flushPending(() => sequenceManager.getNextSequenceNumber());
      
      expect(events.length, equals(1));
      expect(events.first.key, equals('test-key'));
      expect(events.first.value, equals('value1'));
    });
  });
}