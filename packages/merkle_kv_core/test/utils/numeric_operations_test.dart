import 'package:test/test.dart';
import '../../lib/src/utils/numeric_operations.dart';

void main() {
  group('NumericOperations', () {
    group('isValidAmount', () {
      test('accepts valid amounts', () {
        expect(NumericOperations.isValidAmount(1), isTrue);
        expect(NumericOperations.isValidAmount(-1), isTrue);
        expect(
          NumericOperations.isValidAmount(9000000000000000),
          isTrue,
        ); // 9e15
        expect(
          NumericOperations.isValidAmount(-9000000000000000),
          isTrue,
        ); // -9e15
      });

      test('rejects invalid amounts', () {
        expect(
          NumericOperations.isValidAmount(9000000000000001),
          isFalse,
        ); // > 9e15
        expect(
          NumericOperations.isValidAmount(-9000000000000001),
          isFalse,
        ); // < -9e15
      });
    });

    group('parseInteger', () {
      test('parses valid integers correctly', () {
        expect(NumericOperations.parseInteger('42'), equals(42));
        expect(NumericOperations.parseInteger('-42'), equals(-42));
        expect(NumericOperations.parseInteger('0'), equals(0));
      });

      test('handles leading zeros correctly', () {
        expect(NumericOperations.parseInteger('0000123'), equals(123));
        expect(NumericOperations.parseInteger('-000456'), equals(-456));
      });

      test('returns null for invalid formats', () {
        expect(NumericOperations.parseInteger('not_a_number'), isNull);
        expect(NumericOperations.parseInteger('12.34'), isNull);
        expect(NumericOperations.parseInteger(''), isNull);
        expect(NumericOperations.parseInteger(null), isNull);
      });
    });

    group('safeIncrement', () {
      test('performs normal increment', () {
        expect(NumericOperations.safeIncrement(10, 5), equals(15));
        expect(NumericOperations.safeIncrement(-5, 3), equals(-2));
      });

      test('throws on overflow', () {
        expect(
          () => NumericOperations.safeIncrement(9223372036854775807, 1),
          throwsException,
        );
      });

      test('throws on underflow with negative amount', () {
        expect(
          () => NumericOperations.safeIncrement(-9223372036854775808, -1),
          throwsException,
        );
      });
    });

    group('formatCanonical', () {
      test('formats integers canonically', () {
        expect(NumericOperations.formatCanonical(123), equals('123'));
        expect(NumericOperations.formatCanonical(-456), equals('-456'));
        expect(NumericOperations.formatCanonical(0), equals('0'));
      });
    });
  });
}
