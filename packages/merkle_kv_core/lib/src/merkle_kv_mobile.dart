import 'dart:async';
import 'dart:convert';
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

import 'config/merkle_kv_config.dart';
import 'mqtt/mqtt_client.dart';
import 'mqtt/message_handler.dart';
import 'storage/storage_interface.dart';
import 'storage/memory_storage.dart';
import 'storage/persistent_storage.dart';
import 'commands/command_processor.dart';
import 'replication/replication_manager.dart';
import 'models/response_models.dart';
import 'models/event_models.dart';
import 'utils/logger.dart';

/// Main client interface for MerkleKV Mobile
/// 
/// Provides a high-level API for key-value operations over MQTT
/// with automatic replication and conflict resolution.
class MerkleKVMobile {
  static final Logger _logger = Logger('MerkleKVMobile');
  
  final MerkleKVConfig _config;
  late final MerkleKVMqttClient _mqttClient;
  late final MessageHandler _messageHandler;
  late final StorageInterface _storage;
  late final CommandProcessor _commandProcessor;
  late final ReplicationManager _replicationManager;
  
  final Map<String, Completer<OperationResponse>> _pendingRequests = {};
  final StreamController<ConnectionState> _connectionStateController = 
      StreamController<ConnectionState>.broadcast();
  
  bool _isConnected = false;
  bool _isDisposed = false;
  
  /// Creates a new MerkleKV Mobile client instance
  MerkleKVMobile(this._config) {
    LoggerSetup.setup(_config.logLevel);
    _logger.info('Initializing MerkleKV Mobile client');
    
    _initializeComponents();
  }
  
  /// Stream of connection state changes
  Stream<ConnectionState> get connectionState => 
      _connectionStateController.stream;
  
  /// Current connection status
  bool get isConnected => _isConnected;
  
  /// Client configuration
  MerkleKVConfig get config => _config;
  
  void _initializeComponents() {
    // Initialize storage
    _storage = _config.persistenceEnabled
        ? PersistentStorage(_config.storagePath)
        : MemoryStorage();
    
    // Initialize MQTT client
    _mqttClient = MerkleKVMqttClient(_config);
    
    // Initialize message handler
    _messageHandler = MessageHandler(_config, _onResponseReceived, _onReplicationEvent);
    
    // Initialize command processor
    _commandProcessor = CommandProcessor(_storage, _config);
    
    // Initialize replication manager
    _replicationManager = ReplicationManager(_config, _storage, _mqttClient);
    
    // Setup MQTT client event handlers
    _mqttClient.onConnectionStateChanged = _onConnectionStateChanged;
    _mqttClient.onMessageReceived = _messageHandler.handleMessage;
  }
  
  /// Connect to the MQTT broker and initialize the client
  Future<void> connect() async {
    if (_isDisposed) {
      throw StateError('Client has been disposed');
    }
    
    _logger.info('Connecting to MQTT broker: ${_config.mqttBroker}:${_config.mqttPort}');
    
    try {
      await _mqttClient.connect();
      await _storage.initialize();
      await _replicationManager.initialize();
      
      _logger.info('Successfully connected and initialized');
    } catch (e) {
      _logger.severe('Failed to connect: $e');
      rethrow;
    }
  }
  
  /// Disconnect from the MQTT broker
  Future<void> disconnect() async {
    _logger.info('Disconnecting from MQTT broker');
    
    try {
      await _replicationManager.dispose();
      await _mqttClient.disconnect();
      await _storage.dispose();
      
      _isConnected = false;
      _connectionStateController.add(ConnectionState.disconnected);
      
      _logger.info('Successfully disconnected');
    } catch (e) {
      _logger.warning('Error during disconnect: $e');
    }
  }
  
  /// Dispose of all resources
  Future<void> dispose() async {
    if (_isDisposed) return;
    
    _isDisposed = true;
    
    await disconnect();
    await _connectionStateController.close();
    
    // Cancel all pending requests
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('Client disposed'));
      }
    }
    _pendingRequests.clear();
  }
  
  /// Get a value by key
  Future<OperationResponse> get(String key) async {
    return _executeCommand('GET', key: key);
  }
  
  /// Set a key-value pair
  Future<OperationResponse> set(String key, String value) async {
    return _executeCommand('SET', key: key, value: value);
  }
  
  /// Delete a key
  Future<OperationResponse> delete(String key) async {
    return _executeCommand('DEL', key: key);
  }
  
  /// Increment a numeric value
  Future<OperationResponse> incr(String key, [int amount = 1]) async {
    return _executeCommand('INCR', key: key, amount: amount);
  }
  
  /// Decrement a numeric value
  Future<OperationResponse> decr(String key, [int amount = 1]) async {
    return _executeCommand('DECR', key: key, amount: amount);
  }
  
  /// Append to a string value
  Future<OperationResponse> append(String key, String value) async {
    return _executeCommand('APPEND', key: key, value: value);
  }
  
  /// Prepend to a string value
  Future<OperationResponse> prepend(String key, String value) async {
    return _executeCommand('PREPEND', key: key, value: value);
  }
  
  /// Get multiple keys
  Future<OperationResponse> mget(List<String> keys) async {
    return _executeCommand('MGET', keys: keys);
  }
  
  /// Set multiple key-value pairs
  Future<OperationResponse> mset(Map<String, String> keyValues) async {
    return _executeCommand('MSET', keyValues: keyValues);
  }
  
  Future<OperationResponse> _executeCommand(
    String operation, {
    String? key,
    String? value,
    int? amount,
    List<String>? keys,
    Map<String, String>? keyValues,
  }) async {
    if (!_isConnected) {
      throw StateError('Not connected to MQTT broker');
    }
    
    if (_isDisposed) {
      throw StateError('Client has been disposed');
    }
    
    final requestId = const Uuid().v4();
    final completer = Completer<OperationResponse>();
    
    _pendingRequests[requestId] = completer;
    
    // Set timeout
    Timer(_config.requestTimeout, () {
      if (_pendingRequests.containsKey(requestId)) {
        _pendingRequests.remove(requestId);
        if (!completer.isCompleted) {
          completer.completeError(TimeoutException(
            'Request timeout after ${_config.requestTimeout.inMilliseconds}ms',
            _config.requestTimeout,
          ));
        }
      }
    });
    
    try {
      final command = {
        'id': requestId,
        'op': operation,
        if (key != null) 'key': key,
        if (value != null) 'value': value,
        if (amount != null) 'amount': amount,
        if (keys != null) 'keys': keys,
        if (keyValues != null) 'keyValues': keyValues,
      };
      
      final topic = '${_config.topicPrefix}/${_config.clientId}/cmd';
      await _mqttClient.publish(topic, jsonEncode(command));
      
      return await completer.future;
    } catch (e) {
      _pendingRequests.remove(requestId);
      rethrow;
    }
  }
  
  void _onConnectionStateChanged(ConnectionState state) {
    _isConnected = state == ConnectionState.connected;
    _connectionStateController.add(state);
    
    if (state == ConnectionState.connected) {
      _logger.info('MQTT connection established');
    } else if (state == ConnectionState.disconnected) {
      _logger.warning('MQTT connection lost');
      
      // Complete all pending requests with error
      for (final completer in _pendingRequests.values) {
        if (!completer.isCompleted) {
          completer.completeError(StateError('Connection lost'));
        }
      }
      _pendingRequests.clear();
    }
  }
  
  void _onResponseReceived(Map<String, dynamic> response) {
    final requestId = response['id'] as String?;
    if (requestId == null) {
      _logger.warning('Received response without request ID');
      return;
    }
    
    final completer = _pendingRequests.remove(requestId);
    if (completer == null) {
      _logger.warning('Received response for unknown request: $requestId');
      return;
    }
    
    if (completer.isCompleted) {
      _logger.warning('Completer already completed for request: $requestId');
      return;
    }
    
    try {
      final operationResponse = OperationResponse.fromJson(response);
      completer.complete(operationResponse);
    } catch (e) {
      _logger.severe('Error parsing response: $e');
      completer.completeError(e);
    }
  }
  
  void _onReplicationEvent(ReplicationEvent event) {
    // Handle incoming replication events
    _replicationManager.handleIncomingEvent(event);
  }
}

/// Connection state enumeration
enum ConnectionState {
  connecting,
  connected,
  disconnected,
  reconnecting,
}
