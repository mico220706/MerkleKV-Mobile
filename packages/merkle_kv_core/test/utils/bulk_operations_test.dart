import 'package:test/test.dart';
import '../../lib/src/utils/bulk_operations.dart';

void main() {
  group('BulkOperations', () {
    group('MGET validation', () {
      test('accepts valid key counts', () {
        expect(BulkOperations.isValidMgetKeyCount(1), isTrue);
        expect(BulkOperations.isValidMgetKeyCount(256), isTrue);
      });

      test('rejects invalid key counts', () {
        expect(BulkOperations.isValidMgetKeyCount(0), isFalse);
        expect(BulkOperations.isValidMgetKeyCount(257), isFalse);
      });

      test('validates key lists correctly', () {
        expect(BulkOperations.validateMgetKeys(['key1', 'key2']), isNull);
        expect(BulkOperations.validateMgetKeys([]), isNotNull);
        expect(BulkOperations.validateMgetKeys(['key1', 'key1']), isNotNull); // Duplicates
        
        final tooManyKeys = List.generate(257, (i) => 'key$i');
        expect(BulkOperations.validateMgetKeys(tooManyKeys), isNotNull);
      });
    });

    group('MSET validation', () {
      test('accepts valid pair counts', () {
        expect(BulkOperations.isValidMsetPairCount(1), isTrue);
        expect(BulkOperations.isValidMsetPairCount(100), isTrue);
      });

      test('rejects invalid pair counts', () {
        expect(BulkOperations.isValidMsetPairCount(0), isFalse);
        expect(BulkOperations.isValidMsetPairCount(101), isFalse);
      });

      test('validates key-value pairs correctly', () {
        expect(BulkOperations.validateMsetPairs({'key1': 'value1'}), isNull);
        expect(BulkOperations.validateMsetPairs({}), isNotNull);
        
        final tooManyPairs = <String, String>{};
        for (int i = 0; i <= 100; i++) {
          tooManyPairs['key$i'] = 'value$i';
        }
        expect(BulkOperations.validateMsetPairs(tooManyPairs), isNotNull);
      });
    });

    group('payload size validation', () {
      test('accepts payloads within 512KiB limit', () {
        final smallPayload = '{"small": "payload"}';
        expect(BulkOperations.isPayloadWithinSizeLimit(smallPayload), isTrue);
        
        // Test exactly at limit
        final atLimit = '{"data": "${'x' * (512 * 1024 - 20)}"}';
        expect(BulkOperations.isPayloadWithinSizeLimit(atLimit), isTrue);
      });

      test('rejects oversized payloads', () {
        final oversized = '{"data": "${'x' * (512 * 1024)}"}';
        expect(BulkOperations.isPayloadWithinSizeLimit(oversized), isFalse);
      });
    });
  });
}