import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:merkle_kv_core/src/api/api_validator.dart';
import 'package:merkle_kv_core/src/errors/merkle_kv_exception.dart';

void main() {
  group('ApiValidator', () {
    group('validateKey', () {
      test('accepts valid ASCII key', () {
        expect(() => ApiValidator.validateKey('test_key'), returnsNormally);
      });

      test('accepts valid UTF-8 key with international characters', () {
        expect(() => ApiValidator.validateKey('café'), returnsNormally);
        expect(() => ApiValidator.validateKey('привет'), returnsNormally);
        expect(() => ApiValidator.validateKey('测试'), returnsNormally);
      });

      test('accepts empty key', () {
        expect(() => ApiValidator.validateKey(''), returnsNormally);
      });

      test('accepts key at maximum length (256 bytes)', () {
        final key256Bytes = 'a' * 256;
        expect(() => ApiValidator.validateKey(key256Bytes), returnsNormally);
      });

      test('throws ValidationException for key over 256 bytes', () {
        final key257Bytes = 'a' * 257;
        expect(
          () => ApiValidator.validateKey(key257Bytes),
          throwsA(isA<ValidationException>()
              .having((e) => e.message, 'message', contains('Key size'))
              .having((e) => e.message, 'message', contains('257'))
              .having((e) => e.message, 'message', contains('256'))),
        );
      });

      test('throws ValidationException for key with multi-byte UTF-8 over limit', () {
        // Each café is 5 bytes (é is 2 bytes)
        final multiByteKey = 'café' * 65; // 5 * 65 = 325 bytes
        expect(
          () => ApiValidator.validateKey(multiByteKey),
          throwsA(isA<ValidationException>()
              .having((e) => e.message, 'message', contains('Key size'))),
        );
      });

      test('accepts key with multi-byte UTF-8 within limit', () {
        // Each café is 5 bytes
        final multiByteKey = 'café' * 51; // 5 * 51 = 255 bytes
        expect(() => ApiValidator.validateKey(multiByteKey), returnsNormally);
      });
    });

    group('validateValue', () {
      test('accepts valid ASCII value', () {
        expect(() => ApiValidator.validateValue('test_value'), returnsNormally);
      });

      test('accepts valid UTF-8 value with international characters', () {
        expect(() => ApiValidator.validateValue('café'), returnsNormally);
        expect(() => ApiValidator.validateValue('привет'), returnsNormally);
        expect(() => ApiValidator.validateValue('测试'), returnsNormally);
      });

      test('accepts empty value', () {
        expect(() => ApiValidator.validateValue(''), returnsNormally);
      });

      test('accepts value at maximum length (256 KiB)', () {
        final value256KiB = 'a' * (256 * 1024);
        expect(() => ApiValidator.validateValue(value256KiB), returnsNormally);
      });

      test('throws ValidationException for value over 256 KiB', () {
        final valueOver256KiB = 'a' * (256 * 1024 + 1);
        expect(
          () => ApiValidator.validateValue(valueOver256KiB),
          throwsA(isA<ValidationException>()
              .having((e) => e.message, 'message', contains('Value size'))
              .having((e) => e.message, 'message', contains('262145'))
              .having((e) => e.message, 'message', contains('262144'))),
        );
      });

      test('throws ValidationException for value with multi-byte UTF-8 over limit', () {
        // Create a string that exceeds 256 KiB when encoded as UTF-8
        final multiByteValue = 'café' * 53000; // Should exceed 256 KiB
        expect(
          () => ApiValidator.validateValue(multiByteValue),
          throwsA(isA<ValidationException>()
              .having((e) => e.message, 'message', contains('Value size'))),
        );
      });

      test('accepts value with multi-byte UTF-8 within limit', () {
        final multiByteValue = 'café' * 52000; // Should be under 256 KiB
        expect(() => ApiValidator.validateValue(multiByteValue), returnsNormally);
      });
    });

    group('validateBulkOperation', () {
      test('accepts bulk operation within 512 KiB limit', () {
        final operations = <String, String>{
          'key1': 'value1',
          'key2': 'value2',
          'key3': 'value3',
        };
        expect(() => ApiValidator.validateBulkOperation(operations), returnsNormally);
      });

      test('accepts empty bulk operation', () {
        expect(() => ApiValidator.validateBulkOperation({}), returnsNormally);
      });

      test('throws ValidationException for bulk operation over 512 KiB', () {
        // Create a bulk operation that exceeds 512 KiB
        final operations = <String, String>{};
        for (int i = 0; i < 100; i++) {
          operations['key$i'] = 'a' * 6000; // Large values
        }
        expect(
          () => ApiValidator.validateBulkOperation(operations),
          throwsA(isA<ValidationException>()
              .having((e) => e.message, 'message', contains('Bulk operation size'))
              .having((e) => e.message, 'message', contains('524288'))),
        );
      });

      test('validates individual keys and values in bulk operation', () {
        final operations = <String, String>{
          'a' * 257: 'value', // Invalid key (too long)
        };
        expect(
          () => ApiValidator.validateBulkOperation(operations),
          throwsA(isA<ValidationException>()
              .having((e) => e.message, 'message', contains('Key size'))),
        );
      });

      test('validates individual values in bulk operation', () {
        final operations = <String, String>{
          'key': 'a' * (256 * 1024 + 1), // Invalid value (too long)
        };
        expect(
          () => ApiValidator.validateBulkOperation(operations),
          throwsA(isA<ValidationException>()
              .having((e) => e.message, 'message', contains('Value size'))),
        );
      });

      test('calculates UTF-8 byte size correctly for bulk operations', () {
        final operations = <String, String>{
          'café': 'café', // 5 bytes each
          'test': 'test', // 4 bytes each
        };
        // Total: (4 + 4) + (4 + 4) = 16 bytes - well within limit
        expect(() => ApiValidator.validateBulkOperation(operations), returnsNormally);
      });
    });

    group('validateBulkKeys', () {
      test('accepts valid bulk keys within limits', () {
        final keys = ['key1', 'key2', 'key3'];
        expect(() => ApiValidator.validateBulkKeys(keys), returnsNormally);
      });

      test('accepts empty key list', () {
        expect(() => ApiValidator.validateBulkKeys([]), returnsNormally);
      });

      test('validates individual keys in bulk operation', () {
        final keys = ['key1', 'a' * 257, 'key3']; // Invalid key in middle
        expect(
          () => ApiValidator.validateBulkKeys(keys),
          throwsA(isA<ValidationException>()
              .having((e) => e.message, 'message', contains('Key size'))),
        );
      });

      test('throws ValidationException for bulk keys over 512 KiB total', () {
        final keys = List.generate(2000, (i) => 'a' * 256); // 2000 * 256 bytes
        expect(
          () => ApiValidator.validateBulkKeys(keys),
          throwsA(isA<ValidationException>()
              .having((e) => e.message, 'message', contains('Bulk keys size'))
              .having((e) => e.message, 'message', contains('524288'))),
        );
      });

      test('calculates UTF-8 byte size correctly for bulk keys', () {
        final keys = ['café', 'test', 'привет']; // Mixed UTF-8
        expect(() => ApiValidator.validateBulkKeys(keys), returnsNormally);
      });
    });

    group('UTF-8 edge cases', () {
      test('handles null bytes correctly', () {
        final keyWithNull = 'test\x00key';
        expect(() => ApiValidator.validateKey(keyWithNull), returnsNormally);
      });

      test('handles high Unicode codepoints', () {
        final emojiKey = 'test🚀key';
        final emojiValue = 'Hello 🌍 World!';
        expect(() => ApiValidator.validateKey(emojiKey), returnsNormally);
        expect(() => ApiValidator.validateValue(emojiValue), returnsNormally);
      });

      test('handles combining characters correctly', () {
        final combiningKey = 'café'; // Using combining accent
        expect(() => ApiValidator.validateKey(combiningKey), returnsNormally);
      });

      test('calculates byte size for mixed character sets', () {
        // Mix of ASCII (1 byte), Latin-1 (2 bytes), and CJK (3 bytes)
        final mixedKey = 'abc' + 'café' + '测试'; // 3 + 5 + 6 = 14 bytes
        expect(() => ApiValidator.validateKey(mixedKey), returnsNormally);
      });
    });

    group('error messages', () {
      test('ValidationException includes actual and limit sizes for keys', () {
        final longKey = 'a' * 300;
        try {
          ApiValidator.validateKey(longKey);
          fail('Expected ValidationException');
        } catch (e) {
          expect(e, isA<ValidationException>());
          final exception = e as ValidationException;
          expect(exception.message, contains('300'));
          expect(exception.message, contains('256'));
          expect(exception.message, contains('Key size'));
        }
      });

      test('ValidationException includes actual and limit sizes for values', () {
        final longValue = 'a' * (300 * 1024);
        try {
          ApiValidator.validateValue(longValue);
          fail('Expected ValidationException');
        } catch (e) {
          expect(e, isA<ValidationException>());
          final exception = e as ValidationException;
          expect(exception.message, contains('Value size'));
          expect(exception.message, contains('307200'));
          expect(exception.message, contains('262144'));
        }
      });

      test('ValidationException includes actual and limit sizes for bulk operations', () {
        final operations = <String, String>{};
        for (int i = 0; i < 200; i++) {
          operations['key$i'] = 'a' * 3000; // Create large bulk operation
        }
        
        try {
          ApiValidator.validateBulkOperation(operations);
          fail('Expected ValidationException');
        } catch (e) {
          expect(e, isA<ValidationException>());
          final exception = e as ValidationException;
          expect(exception.message, contains('Bulk operation size'));
          expect(exception.message, contains('524288'));
        }
      });
    });
  });
}