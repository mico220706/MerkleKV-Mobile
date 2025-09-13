# MerkleKV Public API Implementation Summary

## Issue #21: Public API Surface for MerkleKV Mobile

This document summarizes the complete implementation of Issue #21, which adds a comprehensive public API surface for MerkleKV Mobile with proper error handling, validation, and fail-fast behavior.

## Implementation Overview

### 1. Error Hierarchy (/src/errors/merkle_kv_exception.dart)

Created a complete exception hierarchy per Locked Spec §12:

```dart
/// Base exception class for all MerkleKV errors
class MerkleKVException implements Exception {
  final String message;
  final Exception? cause;
  const MerkleKVException(this.message, [this.cause]);
}

/// Connection-related errors (broker connectivity, authentication, timeouts)
class ConnectionException extends MerkleKVException {
  const ConnectionException.connectionTimeout();
  const ConnectionException.brokerUnreachable(String broker);
  const ConnectionException.authenticationFailed();
  const ConnectionException.notConnected();
  const ConnectionException.connectionLost();
}

/// Validation errors (key/value size limits, UTF-8 validation, configuration)
class ValidationException extends MerkleKVException {
  const ValidationException.invalidKey(String details);
  const ValidationException.invalidValue(String details);
  const ValidationException.invalidConfiguration(String details);
  const ValidationException.invalidOperation(String details);
}

/// Timeout errors (command timeouts, response timeouts)
class TimeoutException extends MerkleKVException {
  const TimeoutException.operationTimeout(String operation);
  const TimeoutException.commandTimeout(String command, Duration timeout);
  const TimeoutException.responseTimeout();
}

/// Payload-related errors (size limits, serialization/deserialization)
class PayloadException extends MerkleKVException {
  const PayloadException.payloadTooLarge(String details);
  const PayloadException.serializationFailed(String details);
  const PayloadException.deserializationFailed(String details);
  const PayloadException.invalidFormat(String details);
}

/// Storage-related errors (I/O failures, corruption, insufficient space)
class StorageException extends MerkleKVException {
  const StorageException.storageFailure(String details);
  const StorageException.keyNotFound(String key);
  const StorageException.storageCorruption(String details);
  const StorageException.insufficientSpace(String details);
}
```

### 2. API Validation (/src/api/api_validator.dart)

Created UTF-8 validation utilities per Locked Spec §11:

```dart
class ApiValidator {
  static const int maxKeyBytes = 256;           // 256 bytes
  static const int maxValueBytes = 256 * 1024; // 256 KiB
  static const int maxBulkPayloadBytes = 512 * 1024; // 512 KiB
  
  /// Validates key size and UTF-8 encoding
  static void validateKey(String key);
  
  /// Validates value size and UTF-8 encoding
  static void validateValue(String value);
  
  /// Validates bulk operation total size and individual keys/values
  static void validateBulkOperation(Map<String, String> keyValues);
  
  /// Validates bulk keys total size
  static void validateBulkKeys(List<String> keys);
  
  /// Validates increment/decrement amounts
  static void validateIncrementAmount(int amount);
  
  /// Gets UTF-8 byte length for size calculations
  static int getUtf8ByteLength(String str);
}
```

### 3. Main Public API Class (/lib/merkle_kv.dart)

Created the primary MerkleKV class with all required operations:

```dart
class MerkleKV {
  /// Lifecycle Management
  static Future<MerkleKV> create(MerkleKVConfig config);
  Future<void> connect();
  Future<void> disconnect();
  bool get isConnected;
  
  /// Core Operations
  Future<String?> get(String key);
  Future<void> set(String key, String value);
  Future<void> delete(String key); // Idempotent
  
  /// Numeric Operations
  Future<int> increment(String key, int delta);
  Future<int> decrement(String key, int delta);
  
  /// String Operations
  Future<String> append(String key, String suffix);
  Future<String> prepend(String key, String prefix);
  
  /// Bulk Operations
  Future<Map<String, String?>> getMultiple(List<String> keys);
  Future<void> setMultiple(Map<String, String> keyValues);
}
```

Key Features:
- **Fail-fast behavior**: Operations fail immediately when disconnected (unless offline queue enabled)
- **UTF-8 validation**: All inputs validated per Locked Spec §11
- **Thread-safety**: Synchronization mechanisms for concurrent operations
- **Idempotent delete**: Delete operations succeed even if key doesn't exist
- **Structured error handling**: All errors use the exception hierarchy

### 4. Configuration Builder Pattern

Enhanced MerkleKVConfig with builder pattern:

```dart
class MerkleKVConfigBuilder {
  MerkleKVConfigBuilder brokerHost(String host);
  MerkleKVConfigBuilder brokerPort(int port);
  MerkleKVConfigBuilder clientId(String id);
  MerkleKVConfigBuilder username(String user);
  MerkleKVConfigBuilder password(String pass);
  MerkleKVConfigBuilder enableSecure(bool secure);
  MerkleKVConfigBuilder enableOfflineQueue(bool enable);
  MerkleKVConfigBuilder commandTimeout(Duration timeout);
  MerkleKVConfigBuilder connectionTimeout(Duration timeout);
  MerkleKVConfig build(); // Validates configuration
}
```

### 5. Library Exports (/lib/merkle_kv_core.dart)

Updated to export new public API components:

```dart
// Public API
export 'merkle_kv.dart';

// Error handling
export 'src/errors/merkle_kv_exception.dart';

// Configuration
export 'src/config/merkle_kv_config.dart';
// ... other existing exports
```

### 6. Comprehensive Test Suite

Created extensive test coverage:

#### API Validator Tests (/test/api/api_validator_test.dart)
- UTF-8 key/value validation
- Size limit enforcement
- Bulk operation validation
- Edge cases and error messages

#### MerkleKV API Tests (/test/api/merkle_kv_test.dart)
- Lifecycle management
- All operation types
- Error handling
- Thread-safety
- Fail-fast behavior
- Idempotency

#### Exception Tests (/test/errors/merkle_kv_exception_test.dart)
- Exception hierarchy
- Factory constructors
- Message formatting
- Cause chaining

#### Integration Tests (/test/integration/merkle_kv_integration_test.dart)
- Full CRUD workflows
- Numeric and string operations
- Bulk operations
- UTF-8 validation integration
- Concurrency testing
- Offline queue behavior

### 7. API Usage Examples

#### Basic Usage
```dart
final config = MerkleKVConfig.create(
  mqttHost: 'broker.example.com',
  mqttPort: 1883,
  clientId: 'mobile-app-1',
  nodeId: 'node-1',
);

final merkleKV = await MerkleKV.create(config);
await merkleKV.connect();

// Core operations
await merkleKV.set('user:123', 'John Doe');
final value = await merkleKV.get('user:123');
await merkleKV.delete('user:123');

// Numeric operations
await merkleKV.set('counter', '0');
await merkleKV.increment('counter', 5);
await merkleKV.decrement('counter', 2);

// String operations
await merkleKV.set('greeting', 'Hello');
await merkleKV.append('greeting', ' World');

// Bulk operations
await merkleKV.setMultiple({
  'key1': 'value1',
  'key2': 'value2',
  'key3': 'value3',
});

final results = await merkleKV.getMultiple(['key1', 'key2', 'key3']);

await merkleKV.disconnect();
```

#### Builder Pattern
```dart
final config = MerkleKVConfigBuilder()
    .brokerHost('secure.broker.com')
    .brokerPort(8883)
    .clientId('mobile-client')
    .username('user')
    .password('pass')
    .enableSecure(true)
    .enableOfflineQueue(true)
    .commandTimeout(Duration(seconds: 30))
    .build();
```

#### Error Handling
```dart
try {
  await merkleKV.set('a' * 257, 'value'); // Key too long
} on ValidationException catch (e) {
  print('Validation error: ${e.message}');
}

try {
  await merkleKV.get('key'); // When disconnected
} on ConnectionException catch (e) {
  print('Connection error: ${e.message}');
}
```

## Compliance with Issue Requirements

✅ **Public MerkleKV class**: Complete implementation with all operation types
✅ **Error hierarchy**: Full exception hierarchy per Locked Spec §12
✅ **UTF-8 validation**: Complete validation per Locked Spec §11
✅ **Fail-fast behavior**: Operations fail immediately when disconnected
✅ **Idempotency**: Delete operations are idempotent
✅ **Builder pattern**: Configuration builder with fluent interface
✅ **Thread-safety**: Synchronization mechanisms for concurrent operations
✅ **Observability**: Structured logging and error reporting
✅ **Comprehensive tests**: Unit, integration, and concurrency tests
✅ **Documentation**: API examples and usage patterns

## Size Limits (Locked Spec §11)

- **Key**: ≤ 256 bytes UTF-8
- **Value**: ≤ 256 KiB UTF-8
- **Bulk Operations**: ≤ 512 KiB total UTF-8
- **Bulk Keys**: ≤ 512 KiB total UTF-8

## Error Categories (Locked Spec §12)

1. **ConnectionException**: Broker connectivity, authentication
2. **ValidationException**: Input validation, configuration
3. **TimeoutException**: Command and response timeouts
4. **PayloadException**: Size limits, serialization
5. **StorageException**: I/O failures, corruption

## Implementation Status

The complete public API surface has been implemented according to Issue #21 specifications. All components work together to provide a robust, validated, and thread-safe interface for MerkleKV Mobile operations.

**Next Steps**: Create PR to AI-Decenter repository with this implementation.