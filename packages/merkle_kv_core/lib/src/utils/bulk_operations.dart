import 'dart:convert';

/// Utility class for bulk operation validation per Locked Spec §4.7-4.8.
class BulkOperations {
  static const int _maxMgetKeys = 256;      // §4.7
  static const int _maxMsetPairs = 100;     // §4.8
  static const int _maxPayloadBytes = 512 * 1024; // 512 KiB per §11

  /// Validates MGET key count limits.
  static bool isValidMgetKeyCount(int keyCount) {
    return keyCount > 0 && keyCount <= _maxMgetKeys;
  }

  /// Validates MSET pair count limits.
  static bool isValidMsetPairCount(int pairCount) {
    return pairCount > 0 && pairCount <= _maxMsetPairs;
  }

  /// Validates that a payload is within size limits.
  static bool isPayloadWithinSizeLimit(String jsonPayload) {
    final bytes = utf8.encode(jsonPayload);
    return bytes.length <= _maxPayloadBytes;
  }

  /// Gets the byte size of a JSON payload.
  static int getPayloadByteSize(String jsonPayload) {
    return utf8.encode(jsonPayload).length;
  }

  /// Validates key list for MGET operation.
  static String? validateMgetKeys(List<String>? keys) {
    if (keys == null || keys.isEmpty) {
      return 'MGET requires at least one key';
    }
    
    if (keys.length > _maxMgetKeys) {
      return 'MGET supports maximum $_maxMgetKeys keys, got: ${keys.length}';
    }

    // Check for duplicate keys
    final uniqueKeys = keys.toSet();
    if (uniqueKeys.length != keys.length) {
      return 'MGET keys must be unique';
    }

    return null; // Valid
  }

  /// Validates key-value pairs for MSET operation.
  static String? validateMsetPairs(Map<String, dynamic>? keyValues) {
    if (keyValues == null || keyValues.isEmpty) {
      return 'MSET requires at least one key-value pair';
    }
    
    if (keyValues.length > _maxMsetPairs) {
      return 'MSET supports maximum $_maxMsetPairs pairs, got: ${keyValues.length}';
    }

    return null; // Valid
  }
}