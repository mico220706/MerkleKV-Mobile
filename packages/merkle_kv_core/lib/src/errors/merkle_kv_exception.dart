/// Base exception class for all MerkleKV errors
class MerkleKVException implements Exception {
  final String message;
  final Exception? cause;
  
  const MerkleKVException(this.message, [this.cause]);
  
  @override
  String toString() => 'MerkleKVException: $message';
}

/// Connection-related errors (broker connectivity, authentication, timeouts)
class ConnectionException extends MerkleKVException {
  const ConnectionException(super.message, [super.cause]);
  
  const ConnectionException.connectionTimeout() 
      : super('Connection timeout - unable to connect to broker within timeout period');
  
  const ConnectionException.brokerUnreachable(String broker) 
      : super('Broker unreachable: $broker');
  
  const ConnectionException.authenticationFailed() 
      : super('Authentication failed - invalid credentials');
  
  const ConnectionException.notConnected() 
      : super('Not connected - operation requires active connection');
  
  const ConnectionException.connectionLost() 
      : super('Connection lost unexpectedly');
  
  @override
  String toString() => 'ConnectionException: $message';
}

/// Validation errors (key/value size limits, UTF-8 validation, configuration)
class ValidationException extends MerkleKVException {
  const ValidationException(super.message, [super.cause]);
  
  const ValidationException.invalidKey(String details) 
      : super('Invalid key: $details');
  
  const ValidationException.invalidValue(String details) 
      : super('Invalid value: $details');
  
  const ValidationException.invalidConfiguration(String details) 
      : super('Invalid configuration: $details');
  
  const ValidationException.invalidOperation(String details) 
      : super('Invalid operation: $details');
  
  @override
  String toString() => 'ValidationException: $message';
}

/// Timeout errors (command timeouts, response timeouts)
class TimeoutException extends MerkleKVException {
  const TimeoutException(super.message, [super.cause]);
  
  TimeoutException.operationTimeout(String operation, Duration timeout) 
      : super('Operation timeout: $operation took longer than ${timeout.inMilliseconds}ms');
  
  TimeoutException.commandTimeout(String command, Duration timeout) 
      : super('Command timeout: $command took longer than ${timeout.inMilliseconds}ms');
  
  const TimeoutException.responseTimeout() 
      : super('Response timeout - no response received within timeout period');
  
  @override
  String toString() => 'TimeoutException: $message';
}

/// Payload-related errors (size limits, serialization/deserialization)
class PayloadException extends MerkleKVException {
  const PayloadException(super.message, [super.cause]);
  
  const PayloadException.payloadTooLarge(String details) 
      : super('Payload too large: $details');
  
  const PayloadException.serializationFailed(String details) 
      : super('Serialization failed: $details');
  
  const PayloadException.deserializationFailed(String details) 
      : super('Deserialization failed: $details');
  
  const PayloadException.invalidFormat(String details) 
      : super('Invalid format: $details');
  
  @override
  String toString() => 'PayloadException: $message';
}

/// Storage-related errors (I/O failures, corruption, insufficient space)
class StorageException extends MerkleKVException {
  const StorageException(super.message, [super.cause]);
  
  const StorageException.storageFailure(String details) 
      : super('Storage failure: $details');
  
  const StorageException.keyNotFound(String key) 
      : super('Key not found: $key');
  
  const StorageException.storageCorruption(String details) 
      : super('Storage corruption: $details');
  
  const StorageException.insufficientSpace(String details) 
      : super('Insufficient space: $details');
  
  @override
  String toString() => 'StorageException: $message';
}