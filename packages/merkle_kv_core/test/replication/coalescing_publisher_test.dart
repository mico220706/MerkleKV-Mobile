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

class MockBatchedPublisher {
  final List<ReplicationEvent> publishedEvents = [];
  
  Duration batchWindow = Duration(milliseconds: 50);
  int maxBatchSize = 100;
  
  void dispose() {}
  
  Future<void> flushPending() async {}
  
  Future<void> schedulePublish(List<ReplicationEvent> events) async {
    publishedEvents.addAll(events);
  }
}

class MockEventCoalescer {
  final List<ReplicationEvent> eventsToReturn = [];
  bool addUpdateCalled = false;
  String? lastKey;
  String? lastValue;
  bool? lastTombstone;
  int? lastTimestampMs;
  UpdateOperation? lastOperation;
  
  Duration get coalescingWindow => Duration(milliseconds: 100);
  double get coalescingEffectiveness => 0.5;
  int get maxPendingUpdates => 1000;
  String get nodeId => 'test-node';
  int get pendingUpdatesCount => 0;
  
  bool addUpdate({
    required String key,
    String? value,
    required bool tombstone,
    required int timestampMs,
    required UpdateOperation operation,
  }) {
    addUpdateCalled = true;
    lastKey = key;
    lastValue = value;
    lastTombstone = tombstone;
    lastTimestampMs = timestampMs;
    lastOperation = operation;
    return false;
  }
  
  void dispose() {}
  
  List<ReplicationEvent> flushPending(int Function() sequenceProvider) {
    return eventsToReturn;
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
  group('CoalescingPublisher', () {
    late MockSequenceManager sequenceManager;
    late MockOutboxQueue outboxQueue;
    late MockEventCoalescer eventCoalescer;
    late MockBatchedPublisher batchedPublisher;
    late MockMetricsRecorder metrics;
    late CoalescingPublisher publisher;
    
    setUp(() {
      sequenceManager = MockSequenceManager();
      outboxQueue = MockOutboxQueue();
      eventCoalescer = MockEventCoalescer();
      batchedPublisher = MockBatchedPublisher();
      metrics = MockMetricsRecorder();
      
      // Create real instances since we can't use the mocks directly
      final realEventCoalescer = EventCoalescer(
        nodeId: 'test-node',
        coalescingWindow: Duration(milliseconds: 100),
        maxPendingUpdates: 1000,
        metrics: metrics,
      );
      
      final realBatchedPublisher = BatchedPublisher(
        mqttClient: MockMqttClient(),
        replicationTopic: 'test/topic',
        serializer: MockEventSerializer(),
        batchWindow: Duration(milliseconds: 50),
        maxBatchSize: 100,
        metrics: metrics,
      );
      
      publisher = CoalescingPublisher(
        sequenceManager: sequenceManager,
        outboxQueue: outboxQueue,
        eventCoalescer: realEventCoalescer,
        batchedPublisher: realBatchedPublisher,
        metrics: metrics,
      );
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
      
      // Assert - Since we're using real EventCoalescer, it will handle the updates
      expect(outboxQueue.enqueuedEvents.isNotEmpty, isTrue);
      
      // Check metrics
      expect(metrics.histograms['replication_publish_latency_seconds'], isNotNull);
    });
    
    test('publishDelete should add delete to coalescer and process the event pipeline', () async {
      // Act
      await publisher.publishDelete(
        key: 'key1',
        timestampMs: 1000,
      );
      
      // Assert - Since we're using real EventCoalescer, it will handle the updates
      expect(outboxQueue.enqueuedEvents.isNotEmpty, isTrue);
    });
    
    test('publishEvent should bypass coalescing and directly enqueue the event', () async {
      // Arrange
      final event = createEvent('key1');
      
      // Act
      await publisher.publishEvent(event);
      
      // Assert
      // The event should be directly enqueued
      expect(outboxQueue.enqueuedEvents, contains(event));
    });
    
    test('flush should flush both the coalescer and publisher', () async {
      // Act
      await publisher.flush();
      
      // Assert - No events should be pending after flush
      expect(outboxQueue.enqueuedEvents.isEmpty, isTrue);
    });
    
    test('factory constructor should create all components correctly', () {
      // Act
      final publisher = CoalescingPublisher.create(
        sequenceManager: sequenceManager,
        outboxQueue: outboxQueue,
        mqttClient: MockMqttClient(),
        replicationTopic: 'test/topic',
        serializer: MockEventSerializer(),
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
  });
}

class MockMqttClient implements MqttClient {
  @override
  bool get isConnected => true;
  
  @override
  Future<void> publish(String topic, List<int> payload) async {}
}

class MockEventSerializer implements EventSerializer {
  @override
  ReplicationEvent deserialize(List<int> bytes) {
    throw UnimplementedError();
  }
  
  @override
  List<int> serialize(ReplicationEvent event) {
    return [];
  }
}