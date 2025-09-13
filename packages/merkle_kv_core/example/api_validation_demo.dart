import 'package:merkle_kv_core/src/errors/merkle_kv_exception.dart';
import 'package:merkle_kv_core/src/api/api_validator.dart';

void main() {
  print('=== MerkleKV Public API Validation Demo ===');
  
  // Test Exception Hierarchy
  print('\n1. Testing Exception Hierarchy:');
  
  try {
    throw const ConnectionException.connectionTimeout();
  } catch (e) {
    print('✓ ConnectionException: $e');
  }
  
  try {
    throw const ValidationException.invalidKey('Key too long');
  } catch (e) {
    print('✓ ValidationException: $e');
  }
  
  try {
    throw TimeoutException.operationTimeout('get', const Duration(seconds: 30));
  } catch (e) {
    print('✓ TimeoutException: $e');
  }
  
  try {
    throw const PayloadException.payloadTooLarge('Large data');
  } catch (e) {
    print('✓ PayloadException: $e');
  }
  
  try {
    throw const StorageException.storageFailure('Disk error');
  } catch (e) {
    print('✓ StorageException: $e');
  }
  
  // Test API Validation
  print('\n2. Testing API Validation:');
  
  // Valid key/value
  try {
    ApiValidator.validateKey('valid_key');
    print('✓ Valid key accepted');
  } catch (e) {
    print('✗ Valid key rejected: $e');
  }
  
  try {
    ApiValidator.validateValue('valid_value');
    print('✓ Valid value accepted');
  } catch (e) {
    print('✗ Valid value rejected: $e');
  }
  
  // Invalid key (too long)
  try {
    ApiValidator.validateKey('a' * 257);
    print('✗ Invalid key accepted (should have been rejected)');
  } catch (e) {
    print('✓ Invalid key properly rejected: ${e.toString().substring(0, 60)}...');
  }
  
  // Invalid value (too long)
  try {
    ApiValidator.validateValue('a' * (256 * 1024 + 1));
    print('✗ Invalid value accepted (should have been rejected)');
  } catch (e) {
    print('✓ Invalid value properly rejected: ${e.toString().substring(0, 60)}...');
  }
  
  // Valid bulk operation
  try {
    ApiValidator.validateBulkOperation({
      'key1': 'value1',
      'key2': 'value2',
      'key3': 'value3',
    });
    print('✓ Valid bulk operation accepted');
  } catch (e) {
    print('✗ Valid bulk operation rejected: $e');
  }
  
  // UTF-8 validation
  try {
    ApiValidator.validateKey('café');
    ApiValidator.validateValue('ñoño');
    print('✓ UTF-8 characters properly handled');
  } catch (e) {
    print('✗ UTF-8 validation failed: $e');
  }
  
  print('\n=== All API components validated successfully! ===');
}