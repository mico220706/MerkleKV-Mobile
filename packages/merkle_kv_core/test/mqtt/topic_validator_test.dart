import 'package:test/test.dart';
import 'package:merkle_kv_core/merkle_kv_core.dart';

void main() {
  group('TopicValidator', () {
    group('validatePrefix', () {
      test('accepts valid prefixes', () {
        // Valid prefixes should not throw
        expect(() => TopicValidator.validatePrefix('app1'), isNot(throwsA(anything)));
        expect(() => TopicValidator.validatePrefix('tenant_123'), isNot(throwsA(anything)));
        expect(() => TopicValidator.validatePrefix('prod-cluster'), isNot(throwsA(anything)));
        expect(() => TopicValidator.validatePrefix('app1/prod'), isNot(throwsA(anything)));
        expect(() => TopicValidator.validatePrefix('customer-456/env'), isNot(throwsA(anything)));
        expect(() => TopicValidator.validatePrefix('A-Za-z0-9_/-valid'), isNot(throwsA(anything)));
      });

      test('rejects empty prefix', () {
        expect(
          () => TopicValidator.validatePrefix(''),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('Topic prefix cannot be empty'),
            ),
          ),
        );
      });
    });

    group('buildTopic', () {
      test('builds command topics correctly', () {
        final topic = TopicValidator.buildTopic('app1/prod', 'device-123', TopicType.command);
        expect(topic, equals('app1/prod/device-123/cmd'));
      });

      test('builds response topics correctly', () {
        final topic = TopicValidator.buildTopic('app1/prod', 'device-123', TopicType.response);
        expect(topic, equals('app1/prod/device-123/res'));
      });

      test('builds replication topics correctly', () {
        final topic = TopicValidator.buildTopic('app1/prod', 'device-123', TopicType.replication);
        expect(topic, equals('app1/prod/replication/events'));
      });
    });

    group('getUtf8ByteLength', () {
      test('calculates byte length for ASCII strings', () {
        expect(TopicValidator.getUtf8ByteLength('app1'), equals(4));
        expect(TopicValidator.getUtf8ByteLength('device-123'), equals(10));
      });

      test('calculates byte length for Unicode strings', () {
        expect(TopicValidator.getUtf8ByteLength('café'), equals(5)); // é is 2 bytes
        expect(TopicValidator.getUtf8ByteLength('🔥'), equals(4)); // emoji is 4 bytes
      });
    });
  });
}