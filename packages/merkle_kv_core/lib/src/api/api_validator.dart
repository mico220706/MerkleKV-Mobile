import 'dart:convert';
import '../errors/merkle_kv_exception.dart';

/// API validation utilities for UTF-8 validation per Locked Spec §11
class ApiValidator {
  // Size limits per Locked Spec §11
  static const int maxKeyBytes = 256;           // 256 bytes
  static const int maxValueBytes = 256 * 1024; // 256 KiB  
  static const int maxBulkPayloadBytes = 512 * 1024; // 512 KiB
  
  /// Validates key size and UTF-8 encoding
  static void validateKey(String key) {
    if (key.isEmpty) {
      throw const ValidationException.invalidKey('Key cannot be empty');
    }
    
    final bytes = getUtf8ByteLength(key);
    if (bytes > maxKeyBytes) {
      throw ValidationException.invalidKey(
        'Key exceeds maximum size: $bytes bytes > $maxKeyBytes bytes'
      );
    }
  }
  
  /// Validates value size and UTF-8 encoding  
  static void validateValue(String value) {
    final bytes = getUtf8ByteLength(value);
    if (bytes > maxValueBytes) {
      throw ValidationException.invalidValue(
        'Value exceeds maximum size: $bytes bytes > $maxValueBytes bytes'
      );
    }
  }
  
  /// Validates bulk operation total size and individual keys/values
  static void validateBulkOperation(Map<String, String> keyValues) {
    if (keyValues.isEmpty) {
      throw const ValidationException.invalidOperation('Bulk operation cannot be empty');
    }
    
    int totalBytes = 0;
    
    for (final entry in keyValues.entries) {
      validateKey(entry.key);
      validateValue(entry.value);
      
      totalBytes += getUtf8ByteLength(entry.key);
      totalBytes += getUtf8ByteLength(entry.value);
    }
    
    if (totalBytes > maxBulkPayloadBytes) {
      throw ValidationException.invalidOperation(
        'Bulk operation exceeds maximum size: $totalBytes bytes > $maxBulkPayloadBytes bytes'
      );
    }
  }
  
  /// Validates bulk keys total size
  static void validateBulkKeys(List<String> keys) {
    if (keys.isEmpty) {
      throw const ValidationException.invalidOperation('Bulk keys cannot be empty');
    }
    
    int totalBytes = 0;
    
    for (final key in keys) {
      validateKey(key);
      totalBytes += getUtf8ByteLength(key);
    }
    
    if (totalBytes > maxBulkPayloadBytes) {
      throw ValidationException.invalidOperation(
        'Bulk keys exceed maximum size: $totalBytes bytes > $maxBulkPayloadBytes bytes'
      );
    }
  }
  
  /// Validates increment/decrement amounts
  static void validateIncrementAmount(int amount) {
    if (amount == 0) {
      throw const ValidationException.invalidOperation('Increment/decrement amount cannot be zero');
    }
  }
  
  /// Gets UTF-8 byte length for size calculations
  static int getUtf8ByteLength(String str) {
    return utf8.encode(str).length;
  }
}