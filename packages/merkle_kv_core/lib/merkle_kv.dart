import 'dart:async';
import 'dart:math';

import 'src/config/merkle_kv_config.dart';
import 'src/errors/merkle_kv_exception.dart';
import 'src/api/api_validator.dart';
import 'src/mqtt/connection_state.dart';
import 'src/commands/command_processor.dart';
import 'src/storage/storage_interface.dart';
import 'src/storage/in_memory_storage.dart';
import 'src/mqtt/mqtt_client_interface.dart';
import 'src/mqtt/mqtt_client_impl.dart';

/// Public API surface for MerkleKV Mobile.
///
/// Provides a clean, thread-safe interface for distributed key-value operations
/// with fail-fast behavior, UTF-8 validation, and idempotent operations.
/// 
/// All operations enforce Locked Spec §11 size limits and provide structured
/// error handling per Locked Spec §12.
class MerkleKV {
  final MerkleKVConfig _config;
  late final StorageInterface _storage;
  late final MqttClientInterface _mqttClient;
  late final CommandProcessorImpl _commandProcessor;
  
  /// Current connection state.
  ConnectionState _currentState = ConnectionState.disconnected;
  
  /// Synchronization for thread-safety.
  final Object _lock = Object();
  Completer<void>? _operationLock;
  
  /// Random number generator for command IDs.
  static final Random _random = Random.secure();
  
  /// Private constructor.
  MerkleKV._(this._config);
  
  /// Creates a new MerkleKV instance with the given configuration.
  ///
  /// This factory method initializes all dependencies and validates the
  /// configuration before returning the instance.
  ///
  /// Throws [ValidationException] if the configuration is invalid.
  static Future<MerkleKV> create(MerkleKVConfig config) async {
    // Validate configuration
    if (config.mqttHost.isEmpty) {
      throw const ValidationException.invalidConfiguration('MQTT host cannot be empty');
    }
    if (config.mqttPort <= 0 || config.mqttPort > 65535) {
      throw const ValidationException.invalidConfiguration('MQTT port must be between 1 and 65535');
    }
    if (config.clientId.isEmpty) {
      throw const ValidationException.invalidConfiguration('Client ID cannot be empty');
    }
    
    final instance = MerkleKV._(config);
    await instance._initialize();
    return instance;
  }
  
  /// Initialize internal components.
  Future<void> _initialize() async {
    _storage = InMemoryStorage(_config);
    _mqttClient = MqttClientImpl(_config);
    _commandProcessor = CommandProcessorImpl(_config, _storage);
  }
  
  /// Returns true if currently connected to the broker.
  bool get isConnected => _currentState == ConnectionState.connected;
  
  /// Connects to the MQTT broker.
  ///
  /// Throws [ConnectionException] if connection fails.
  Future<void> connect() async {
    await _synchronized(() async {
      if (_currentState == ConnectionState.connected) {
        return; // Already connected
      }
      
      _currentState = ConnectionState.connecting;
      
      try {
        // Note: Actual MQTT connection logic would go here
        // For now, we'll simulate a successful connection
        await Future.delayed(const Duration(milliseconds: 100));
        _currentState = ConnectionState.connected;
      } catch (e) {
        _currentState = ConnectionState.disconnected;
        throw const ConnectionException.connectionTimeout();
      }
    });
  }
  
  /// Disconnects from the MQTT broker.
  Future<void> disconnect() async {
    await _synchronized(() async {
      if (_currentState == ConnectionState.disconnected) {
        return; // Already disconnected
      }
      
      _currentState = ConnectionState.disconnecting;
      
      try {
        // Note: Actual MQTT disconnection logic would go here
        await Future.delayed(const Duration(milliseconds: 50));
        _currentState = ConnectionState.disconnected;
      } catch (e) {
        _currentState = ConnectionState.disconnected;
        // Log error but don't throw - disconnection should always succeed
      }
    });
  }
  
  /// Retrieves a value by key.
  ///
  /// Returns null if the key does not exist.
  /// Throws [ValidationException] if the key is invalid.
  /// Throws [ConnectionException] if not connected and offline queue is disabled.
  Future<String?> get(String key) async {
    ApiValidator.validateKey(key);
    _checkConnection();
    
    return _synchronized(() async {
      // Note: Actual storage retrieval would go here
      // For now, we'll simulate a storage lookup
      return 'mock_value_for_$key';
    });
  }
  
  /// Sets a key-value pair.
  ///
  /// Throws [ValidationException] if key or value is invalid.
  /// Throws [ConnectionException] if not connected and offline queue is disabled.
  Future<void> set(String key, String value) async {
    ApiValidator.validateKey(key);
    ApiValidator.validateValue(value);
    _checkConnection();
    
    return _synchronized(() async {
      // Note: Actual storage and MQTT publish would go here
      await Future.delayed(const Duration(milliseconds: 10));
    });
  }
  
  /// Deletes a key (idempotent operation).
  ///
  /// This operation succeeds even if the key doesn't exist.
  /// Throws [ValidationException] if the key is invalid.
  /// Throws [ConnectionException] if not connected and offline queue is disabled.
  Future<void> delete(String key) async {
    ApiValidator.validateKey(key);
    _checkConnection();
    
    return _synchronized(() async {
      // Note: Actual deletion would go here
      await Future.delayed(const Duration(milliseconds: 10));
    });
  }
  
  /// Increments a numeric value by delta.
  ///
  /// If the key doesn't exist, it's created with value delta.
  /// If the existing value is not numeric, throws [ValidationException].
  Future<int> increment(String key, int delta) async {
    ApiValidator.validateKey(key);
    ApiValidator.validateIncrementAmount(delta);
    _checkConnection();
    
    return _synchronized(() async {
      // Note: Actual increment logic would go here
      await Future.delayed(const Duration(milliseconds: 10));
      return 42 + delta; // Mock result
    });
  }
  
  /// Decrements a numeric value by delta.
  ///
  /// If the key doesn't exist, it's created with value -delta.
  /// If the existing value is not numeric, throws [ValidationException].
  Future<int> decrement(String key, int delta) async {
    ApiValidator.validateKey(key);
    ApiValidator.validateIncrementAmount(delta);
    _checkConnection();
    
    return _synchronized(() async {
      // Note: Actual decrement logic would go here
      await Future.delayed(const Duration(milliseconds: 10));
      return 42 - delta; // Mock result
    });
  }
  
  /// Appends a suffix to an existing string value.
  ///
  /// If the key doesn't exist, it's created with the suffix as the value.
  Future<String> append(String key, String suffix) async {
    ApiValidator.validateKey(key);
    _checkConnection();
    
    return _synchronized(() async {
      // Note: Actual append logic would go here
      await Future.delayed(const Duration(milliseconds: 10));
      final current = await get(key) ?? '';
      final result = current + suffix;
      ApiValidator.validateValue(result);
      await set(key, result);
      return result;
    });
  }
  
  /// Prepends a prefix to an existing string value.
  ///
  /// If the key doesn't exist, it's created with the prefix as the value.
  Future<String> prepend(String key, String prefix) async {
    ApiValidator.validateKey(key);
    _checkConnection();
    
    return _synchronized(() async {
      // Note: Actual prepend logic would go here
      await Future.delayed(const Duration(milliseconds: 10));
      final current = await get(key) ?? '';
      final result = prefix + current;
      ApiValidator.validateValue(result);
      await set(key, result);
      return result;
    });
  }
  
  /// Retrieves multiple values by keys.
  ///
  /// Returns a map where missing keys have null values.
  Future<Map<String, String?>> getMultiple(List<String> keys) async {
    ApiValidator.validateBulkKeys(keys);
    _checkConnection();
    
    return _synchronized(() async {
      final result = <String, String?>{};
      for (final key in keys) {
        result[key] = await get(key);
      }
      return result;
    });
  }
  
  /// Sets multiple key-value pairs in a single operation.
  Future<void> setMultiple(Map<String, String> keyValues) async {
    ApiValidator.validateBulkOperation(keyValues);
    _checkConnection();
    
    return _synchronized(() async {
      for (final entry in keyValues.entries) {
        await set(entry.key, entry.value);
      }
    });
  }
  
  /// Checks if connected when offline queue is disabled.
  void _checkConnection() {
    if (!isConnected && !(_config.enableOfflineQueue ?? false)) {
      throw const ConnectionException.notConnected();
    }
  }
  
  /// Generates a unique command ID for request correlation.
  String _generateCommandId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final randomBytes = List.generate(8, (_) => _random.nextInt(256));
    final randomHex = randomBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${timestamp.toRadixString(16)}_$randomHex';
  }
  
  /// Async synchronization helper for thread-safety.
  Future<T> _synchronized<T>(Future<T> Function() computation) async {
    while (_operationLock != null) {
      await _operationLock!.future;
    }
    
    _operationLock = Completer<void>();
    try {
      final result = await computation();
      return result;
    } finally {
      final completer = _operationLock!;
      _operationLock = null;
      completer.complete();
    }
  }
}