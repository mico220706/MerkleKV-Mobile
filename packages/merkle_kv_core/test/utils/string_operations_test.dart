import 'package:test/test.dart';
import '../../lib/src/utils/string_operations.dart';

void main() {
  group('StringOperations', () {
    group('isValidUtf8String', () {
      test('accepts valid UTF-8 strings', () {
        expect(StringOperations.isValidUtf8String('hello'), isTrue);
        expect(StringOperations.isValidUtf8String('こんにちは'), isTrue);
        expect(StringOperations.isValidUtf8String('🚀'), isTrue);
        expect(StringOperations.isValidUtf8String(''), isTrue);
      });
    });

    group('isWithinSizeLimit', () {
      test('accepts strings within 256KiB limit', () {
        expect(StringOperations.isWithinSizeLimit('small'), isTrue);
        
        // Test exactly at limit (256KiB = 262144 bytes)
        final atLimit = 'x' * 262144;
        expect(StringOperations.isWithinSizeLimit(atLimit), isTrue);
        
        // Test just over limit
        final overLimit = 'x' * 262145;
        expect(StringOperations.isWithinSizeLimit(overLimit), isFalse);
      });

      test('handles multi-byte UTF-8 characters correctly', () {
        // 'こ' is 3 bytes in UTF-8
        final multiByteChar = 'こ';
        expect(StringOperations.getUtf8ByteSize(multiByteChar), equals(3));
        
        // Fill exactly to limit with multi-byte chars
        final count = 262144 ~/ 3; // 87381 chars * 3 bytes = 262143 bytes
        final nearLimit = multiByteChar * count;
        expect(StringOperations.isWithinSizeLimit(nearLimit), isTrue);
        
        // One more char should exceed
        final overLimit = multiByteChar * (count + 1);
        expect(StringOperations.isWithinSizeLimit(overLimit), isFalse);
      });
    });

    group('safeAppend', () {
      test('appends to existing string', () {
        expect(StringOperations.safeAppend('hello', ' world'), equals('hello world'));
        expect(StringOperations.safeAppend('', 'test'), equals('test'));
      });

      test('treats null existing as empty string', () {
        expect(StringOperations.safeAppend(null, 'hello'), equals('hello'));
      });

      test('returns null when result would exceed size limit', () {
        final large = 'x' * 200000; // 200KB
        final addition = 'x' * 70000; // 70KB - total would be 270KB > 256KB
        expect(StringOperations.safeAppend(large, addition), isNull);
      });

      test('handles empty append value', () {
        expect(StringOperations.safeAppend('hello', ''), equals('hello'));
      });
    });

    group('safePrepend', () {
      test('prepends to existing string', () {
        expect(StringOperations.safePrepend('hello ', 'world'), equals('hello world'));
        expect(StringOperations.safePrepend('test', ''), equals('test'));
      });

      test('treats null existing as empty string', () {
        expect(StringOperations.safePrepend('hello', null), equals('hello'));
      });

      test('returns null when result would exceed size limit', () {
        final large = 'x' * 200000; // 200KB
        final addition = 'x' * 70000; // 70KB - total would be 270KB > 256KB
        expect(StringOperations.safePrepend(addition, large), isNull);
      });

      test('handles empty prepend value', () {
        expect(StringOperations.safePrepend('', 'hello'), equals('hello'));
      });
    });

    group('getUtf8ByteSize', () {
      test('calculates correct byte sizes', () {
        expect(StringOperations.getUtf8ByteSize(''), equals(0));
        expect(StringOperations.getUtf8ByteSize('hello'), equals(5));
        expect(StringOperations.getUtf8ByteSize('こんにちは'), equals(15)); // 5 chars * 3 bytes each
        expect(StringOperations.getUtf8ByteSize('🚀'), equals(4)); // Emoji is 4 bytes
      });
    });
  });
}