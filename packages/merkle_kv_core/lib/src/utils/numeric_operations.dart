/// Utility class for safe numeric operations per Locked Spec §4.5.
class NumericOperations {
  static const int _maxSafeInteger = 9223372036854775807;  // 2^63 - 1
  static const int _minSafeInteger = -9223372036854775808; // -2^63
  static const int _maxAmount = 9000000000000000;          // 9e15
  static const int _minAmount = -9000000000000000;         // -9e15

  /// Validates amount parameter range per Locked Spec §3.1.
  static bool isValidAmount(int amount) {
    return amount >= _minAmount && amount <= _maxAmount;
  }

  /// Parse string value as signed 64-bit integer.
  /// Returns null for invalid formats.
  static int? parseInteger(String? value) {
    if (value == null || value.isEmpty) return null;
    
    try {
      final parsed = int.parse(value, radix: 10);
      // Verify the parsed value is in int64 range
      if (parsed > _maxSafeInteger || parsed < _minSafeInteger) {
        throw FormatException('Integer overflow: $value');
      }
      return parsed;
    } on FormatException catch (_) {
      // Invalid integer format
      return null;
    }
  }

  /// Format integer to canonical string (no leading zeros except "0").
  static String formatCanonical(int value) {
    return value.toString(); // Dart's toString() already produces canonical form
  }

  /// Safe increment with overflow detection.
  static int safeIncrement(int current, int amount) {
    // Check for overflow before performing operation
    if (amount > 0 && current > _maxSafeInteger - amount) {
      throw _NumericOverflowException('Integer overflow: $current + $amount');
    }
    if (amount < 0 && current < _minSafeInteger - amount) {
      throw _NumericOverflowException('Integer underflow: $current + $amount');
    }
    
    return current + amount;
  }

  /// Safe decrement with underflow detection.
  static int safeDecrement(int current, int amount) {
    // Decrement is increment by negative amount
    return safeIncrement(current, -amount);
  }
}

/// Exception thrown when numeric operations would overflow int64 bounds.
class _NumericOverflowException implements Exception {
  final String message;
  const _NumericOverflowException(this.message);
  
  @override
  String toString() => 'NumericOverflowException: $message';
}