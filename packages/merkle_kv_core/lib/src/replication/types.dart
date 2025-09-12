// Shared types and interfaces for replication system

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