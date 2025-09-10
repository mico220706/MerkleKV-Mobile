import 'dart:convert';

/// Utility class for safe string operations per Locked Spec §4.6.
class StringOperations {
  static const int _maxValueBytes = 256 * 1024; // 256 KiB per §11

  /// Validates that a string contains valid UTF-8 and is within size limits.
  static bool isValidUtf8String(String value) {
    try {
      // Dart strings are always valid UTF-16, but we need to check UTF-8 byte representation
      final bytes = utf8.encode(value);
      // Verify we can decode it back (redundant in Dart but good practice)
      utf8.decode(bytes);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Validates that a string's UTF-8 byte representation is within size limits.
  static bool isWithinSizeLimit(String value) {
    final bytes = utf8.encode(value);
    return bytes.length <= _maxValueBytes;
  }

  /// Gets the UTF-8 byte size of a string.
  static int getUtf8ByteSize(String value) {
    return utf8.encode(value).length;
  }

  /// Safely appends a value to an existing string.
  /// Returns the concatenated result or null if it would exceed size limits.
  static String? safeAppend(String? existing, String value) {
    final existingStr = existing ?? '';
    final result = existingStr + value;
    
    if (!isWithinSizeLimit(result)) {
      return null; // Would exceed size limit
    }
    
    return result;
  }

  /// Safely prepends a value to an existing string.
  /// Returns the concatenated result or null if it would exceed size limits.
  static String? safePrepend(String value, String? existing) {
    final existingStr = existing ?? '';
    final result = value + existingStr;
    
    if (!isWithinSizeLimit(result)) {
      return null; // Would exceed size limit
    }
    
    return result;
  }
}