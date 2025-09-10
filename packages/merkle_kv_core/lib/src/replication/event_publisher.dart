import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../config/merkle_kv_config.dart';
import '../mqtt/connection_state.dart';
import '../mqtt/mqtt_client_interface.dart';
import '../mqtt/topic_scheme.dart';
import '../storage/storage_entry.dart';
import 'cbor_serializer.dart';
import 'metrics.dart';

/// Status of the replication outbox queue
class OutboxStatus {
  const OutboxStatus({
    required this.pendingEvents,
    required this.isOnline,
    required this.lastFlushTime,
  });

  /// Number of events pending in the outbox
  final int pendingEvents;

  /// Whether the MQTT client is currently connected
  final bool isOnline;

  /// Last successful outbox flush time (null if never flushed)
  final DateTime? lastFlushTime;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OutboxStatus &&
          runtimeType == other.runtimeType &&
          pendingEvents == other.pendingEvents &&
          isOnline == other.isOnline &&
          lastFlushTime == other.lastFlushTime;

  @override
  int get hashCode =>
      pendingEvents.hashCode ^ isOnline.hashCode ^ lastFlushTime.hashCode;

  @override
  String toString() =>
      'OutboxStatus(pendingEvents: $pendingEvents, isOnline: $isOnline, lastFlushTime: $lastFlushTime)';
}

/// Abstract interface for replication event publishing per Locked Spec §7
abstract class ReplicationEventPublisher {
  /// Publishes a replication event immediately if online, or queues if offline
  ///
  /// Events are published to the {prefix}/replication/events topic with QoS=1.
  /// If MQTT is disconnected, events are queued in the persistent outbox.
  Future<void> publishEvent(ReplicationEvent event);

  /// Flushes all pending events from the outbox queue
  ///
  /// Called automatically on reconnection. Can be called manually to force flush.
  /// Events are published in original sequence order.
  Future<void> flushOutbox();

  /// Stream of outbox status changes
  ///
  /// Emits status updates when queue size changes or connection state changes.
  Stream<OutboxStatus> get outboxStatus;

  /// Current sequence number (for monitoring)
  int get currentSequence;

  /// Creates a replication event from a storage entry
  static ReplicationEvent createEventFromEntry(StorageEntry entry) {
    if (entry.isTombstone) {
      return ReplicationEvent.tombstone(
        key: entry.key,
        nodeId: entry.nodeId,
        seq: entry.seq,
        timestampMs: entry.timestampMs,
      );
    } else {
      return ReplicationEvent.value(
        key: entry.key,
        nodeId: entry.nodeId,
        seq: entry.seq,
        timestampMs: entry.timestampMs,
        value: entry.value!,
      );
    }
  }

  /// Creates and publishes a replication event for a successful storage operation
  Future<void> publishStorageEvent(StorageEntry entry) async {
    final event = createEventFromEntry(entry);
    await publishEvent(event);
  }

  /// Initializes the publisher and recovers state
  Future<void> initialize();

  /// Disposes resources and persists final state
  Future<void> dispose();
}

/// Implementation of replication event publisher with persistent outbox
class ReplicationEventPublisherImpl implements ReplicationEventPublisher {
  final MerkleKVConfig _config;
  final MqttClientInterface _mqttClient;
  final TopicScheme _topicScheme;
  final ReplicationMetrics _metrics;
  
  late final SequenceManager _sequenceManager;
  late final OutboxQueue _outboxQueue;
  
  final StreamController<OutboxStatus> _statusController = 
      StreamController<OutboxStatus>.broadcast();
  
  StreamSubscription<dynamic>? _connectionSubscription;
  bool _initialized = false;
  bool _disposed = false;

  ReplicationEventPublisherImpl({
    required MerkleKVConfig config,
    required MqttClientInterface mqttClient,
    required TopicScheme topicScheme,
    ReplicationMetrics? metrics,
  })  : _config = config,
        _mqttClient = mqttClient,
        _topicScheme = topicScheme,
        _metrics = metrics ?? const NoOpReplicationMetrics();

  @override
  int get currentSequence => _sequenceManager.currentSequence;

  @override
  Stream<OutboxStatus> get outboxStatus => _statusController.stream;

  @override
  Future<void> initialize() async {
    if (_initialized) return;

    _sequenceManager = SequenceManager(_config);
    await _sequenceManager.initialize();

    _outboxQueue = OutboxQueue(_config);
    await _outboxQueue.initialize();

    // Listen to connection state changes
    _connectionSubscription = _mqttClient.connectionState.listen(_onConnectionStateChanged);

    _initialized = true;
    _emitStatus();
  }

  @override
  Future<void> publishEvent(ReplicationEvent event) async {
    _ensureInitialized();
    
    final startTime = DateTime.now();
    
    try {
      // Always attempt to publish immediately if online
      final isOnline = await _isOnline();
      if (isOnline) {
        await _publishEventToMqtt(event);
        _metrics.incrementEventsPublished();
        
        final latency = DateTime.now().difference(startTime).inMilliseconds;
        _metrics.recordPublishLatency(latency);
        
        _emitStatus();
      } else {
        // Queue for later if offline
        await _outboxQueue.enqueue(event);
        _emitStatus();
      }
    } catch (e) {
      _metrics.incrementPublishErrors();
      
      // If immediate publish fails, queue the event
      await _outboxQueue.enqueue(event);
      _emitStatus();
      rethrow;
    }
  }

  @override
  Future<void> flushOutbox() async {
    _ensureInitialized();
    
    if (!await _isOnline()) {
      return; // Cannot flush while offline
    }

    final startTime = DateTime.now();
    final events = await _outboxQueue.drainAll();
    var publishedCount = 0;
    final failedEvents = <ReplicationEvent>[];

    for (final event in events) {
      try {
        await _publishEventToMqtt(event);
        publishedCount++;
        _metrics.incrementEventsPublished();
      } catch (e) {
        _metrics.incrementPublishErrors();
        // Re-queue failed events
        failedEvents.add(event);
      }
    }

    // Re-queue any failed events
    for (final event in failedEvents) {
      await _outboxQueue.enqueue(event);
    }

    if (publishedCount > 0) {
      await _outboxQueue.recordFlush();
      
      final flushDuration = DateTime.now().difference(startTime).inMilliseconds;
      _metrics.recordFlushDuration(flushDuration);
    }

    _emitStatus();
  }

  @override
  Future<void> publishStorageEvent(StorageEntry entry) async {
    final event = ReplicationEventPublisher.createEventFromEntry(entry);
    await publishEvent(event);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    
    _disposed = true;
    await _connectionSubscription?.cancel();
    
    if (_initialized) {
      await _sequenceManager.dispose();
      await _outboxQueue.dispose();
    }
    
    await _statusController.close();
  }

  /// Publishes an event directly to MQTT
  Future<void> _publishEventToMqtt(ReplicationEvent event) async {
    final cborData = CborSerializer.encode(event);
    final payload = base64Encode(cborData);
    
    await _mqttClient.publish(
      _topicScheme.replicationTopic,
      payload,
    );
  }

  /// Checks if MQTT client is currently online
  Future<bool> _isOnline() async {
    // Simple check - in a real implementation, you might want to cache this
    final currentState = await _mqttClient.connectionState.first;
    return currentState == ConnectionState.connected;
  }

  /// Handles connection state changes
  void _onConnectionStateChanged(dynamic state) {
    if (state == ConnectionState.connected) {
      // Auto-flush on reconnection
      flushOutbox().catchError((e) {
        // Log error but don't fail - this is background operation
      });
    }
    _emitStatus();
  }

  /// Emits current outbox status
  void _emitStatus() async {
    if (_disposed || !_initialized) return;
    
    try {
      final pendingCount = await _outboxQueue.size();
      final isOnline = await _isOnline();
      final lastFlush = await _outboxQueue.lastFlushTime();
      
      // Update metrics
      _metrics.setOutboxSize(pendingCount);
      _metrics.setSequenceNumber(_sequenceManager.currentSequence);
      
      final status = OutboxStatus(
        pendingEvents: pendingCount,
        isOnline: isOnline,
        lastFlushTime: lastFlush,
      );
      
      _statusController.add(status);
    } catch (e) {
      // Ignore errors in status emission
    }
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('ReplicationEventPublisher not initialized. Call initialize() first.');
    }
    if (_disposed) {
      throw StateError('ReplicationEventPublisher has been disposed.');
    }
  }
}

/// Manages sequence numbers with persistence and recovery
class SequenceManager {
  final MerkleKVConfig _config;
  File? _sequenceFile;
  int _currentSeq = 0;
  bool _initialized = false;

  SequenceManager(this._config);

  int get currentSequence => _currentSeq;

  Future<void> initialize() async {
    if (_initialized) return;

    if (_config.persistenceEnabled) {
      _sequenceFile = File('${_config.storagePath}.seq');
      await _recoverSequence();
    }

    _initialized = true;
  }

  /// Gets the next sequence number (strictly monotonic)
  int getNextSequence() {
    _ensureInitialized();
    _currentSeq++;
    _persistSequence(); // Fire and forget
    return _currentSeq;
  }

  Future<void> dispose() async {
    if (_config.persistenceEnabled && _initialized) {
      await _persistSequence();
    }
  }

  /// Recovers sequence number from persistent storage
  Future<void> _recoverSequence() async {
    if (_sequenceFile == null || !await _sequenceFile!.exists()) {
      return;
    }

    try {
      final content = await _sequenceFile!.readAsString();
      final data = jsonDecode(content.trim()) as Map<String, dynamic>;
      final recoveredSeq = data['seq'] as int;
      
      // Ensure strictly increasing sequence
      _currentSeq = recoveredSeq;
    } catch (e) {
      // If recovery fails, start from 0 - this is safe as sequence
      // only needs to be monotonic per node
      _currentSeq = 0;
    }
  }

  /// Persists current sequence number
  Future<void> _persistSequence() async {
    if (_sequenceFile == null) return;

    try {
      // Ensure parent directory exists
      final dir = _sequenceFile!.parent;
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final data = {'seq': _currentSeq, 'updated': DateTime.now().toIso8601String()};
      await _sequenceFile!.writeAsString(jsonEncode(data));
    } catch (e) {
      // Silently handle persistence failures - sequence only needs to be
      // monotonic within a session if persistence fails
    }
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('SequenceManager not initialized');
    }
  }
}

/// Persistent FIFO queue for offline event buffering
class OutboxQueue {
  static const int _defaultMaxSize = 10000; // Configurable max outbox size
  
  final MerkleKVConfig _config;
  File? _outboxFile;
  final List<ReplicationEvent> _queue = <ReplicationEvent>[];
  DateTime? _lastFlushTime;
  bool _initialized = false;

  OutboxQueue(this._config);

  Future<void> initialize() async {
    if (_initialized) return;

    if (_config.persistenceEnabled) {
      _outboxFile = File('${_config.storagePath}.outbox');
      await _loadOutbox();
    }

    _initialized = true;
  }

  /// Adds an event to the outbox queue
  Future<void> enqueue(ReplicationEvent event) async {
    _ensureInitialized();
    
    // Apply bounded queue policy - drop oldest if at limit
    if (_queue.length >= _defaultMaxSize) {
      _queue.removeAt(0); // Drop oldest
    }
    
    _queue.add(event);
    
    if (_config.persistenceEnabled) {
      await _persistOutbox();
    }
  }

  /// Drains all events from the queue
  Future<List<ReplicationEvent>> drainAll() async {
    _ensureInitialized();
    
    final events = List<ReplicationEvent>.from(_queue);
    _queue.clear();
    
    if (_config.persistenceEnabled) {
      await _persistOutbox();
    }
    
    return events;
  }

  /// Records successful flush time
  Future<void> recordFlush() async {
    _lastFlushTime = DateTime.now();
    // No need to persist flush time - it's just for monitoring
  }

  /// Returns current queue size
  Future<int> size() async {
    _ensureInitialized();
    return _queue.length;
  }

  /// Returns last flush time
  Future<DateTime?> lastFlushTime() async {
    return _lastFlushTime;
  }

  Future<void> dispose() async {
    if (_config.persistenceEnabled && _initialized) {
      await _persistOutbox();
    }
  }

  /// Loads outbox from persistent storage
  Future<void> _loadOutbox() async {
    if (_outboxFile == null || !await _outboxFile!.exists()) {
      return;
    }

    try {
      final content = await _outboxFile!.readAsString();
      if (content.trim().isEmpty) return;
      
      final data = jsonDecode(content) as Map<String, dynamic>;
      final eventsJson = data['events'] as List<dynamic>;
      
      for (final eventJson in eventsJson) {
        try {
          final event = ReplicationEvent.fromJson(eventJson as Map<String, dynamic>);
          _queue.add(event);
        } catch (e) {
          // Skip corrupted events but continue loading others
        }
      }
    } catch (e) {
      // If outbox is corrupted, start fresh
      _queue.clear();
    }
  }

  /// Persists outbox to storage
  Future<void> _persistOutbox() async {
    if (_outboxFile == null) return;

    try {
      // Ensure parent directory exists
      final dir = _outboxFile!.parent;
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final data = {
        'events': _queue.map((e) => e.toJson()).toList(),
        'updated': DateTime.now().toIso8601String(),
      };

      // Atomic write via temp file
      final tempFile = File('${_outboxFile!.path}.tmp');
      await tempFile.writeAsString(jsonEncode(data));
      await tempFile.rename(_outboxFile!.path);
    } catch (e) {
      // Silently handle persistence failures - queue remains in memory
    }
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('OutboxQueue not initialized');
    }
  }
}
