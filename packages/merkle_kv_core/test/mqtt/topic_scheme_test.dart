import 'package:test/test.dart';
import 'package:merkle_kv_core/src/config/invalid_config_exception.dart';
import 'package:merkle_kv_core/src/mqtt/topic_scheme.dart';

void main() {
  group('TopicScheme', () {
    group('topic generation', () {
      test('generates correct topics for standard case', () {
        final scheme = TopicScheme.create('prod/cluster-a', 'device-123');

        expect(scheme.commandTopic, equals('prod/cluster-a/device-123/cmd'));
        expect(scheme.responseTopic, equals('prod/cluster-a/device-123/res'));
        expect(
          scheme.replicationTopic,
          equals('prod/cluster-a/replication/events'),
        );
      });

      test('generates correct topics with simple prefix', () {
        final scheme = TopicScheme.create('mkv', 'client-1');

        expect(scheme.commandTopic, equals('mkv/client-1/cmd'));
        expect(scheme.responseTopic, equals('mkv/client-1/res'));
        expect(scheme.replicationTopic, equals('mkv/replication/events'));
      });

      test('generates correct topics with complex prefix', () {
        final scheme = TopicScheme.create(
          'enterprise/region-us-east/env-prod',
          'sensor-abc123',
        );

        expect(
          scheme.commandTopic,
          equals('enterprise/region-us-east/env-prod/sensor-abc123/cmd'),
        );
        expect(
          scheme.responseTopic,
          equals('enterprise/region-us-east/env-prod/sensor-abc123/res'),
        );
        expect(
          scheme.replicationTopic,
          equals('enterprise/region-us-east/env-prod/replication/events'),
        );
      });
    });

    group('prefix normalization', () {
      test('trims whitespace from prefix', () {
        final scheme = TopicScheme.create('  test-prefix  ', 'client-1');
        expect(scheme.prefix, equals('test-prefix'));
      });

      test('removes leading slashes from prefix', () {
        final scheme = TopicScheme.create('//test/prefix', 'client-1');
        expect(scheme.prefix, equals('test/prefix'));
      });

      test('removes trailing slashes from prefix', () {
        final scheme = TopicScheme.create('test/prefix//', 'client-1');
        expect(scheme.prefix, equals('test/prefix'));
      });

      test('removes both leading and trailing slashes', () {
        final scheme = TopicScheme.create('//test/prefix//', 'client-1');
        expect(scheme.prefix, equals('test/prefix'));
      });

      test('uses default prefix when empty after normalization', () {
        final scheme = TopicScheme.create('  //  ', 'client-1');
        expect(scheme.prefix, equals('mkv'));
      });

      test('uses default prefix when completely empty', () {
        final scheme = TopicScheme.create('', 'client-1');
        expect(scheme.prefix, equals('mkv'));
      });
    });

    group('prefix validation', () {
      test('rejects prefix containing + wildcard', () {
        expect(
          () => TopicScheme.create('test/+/prefix', 'client-1'),
          throwsA(
            isA<InvalidConfigException>()
                .having((e) => e.parameter, 'parameter', 'prefix')
                .having(
                  (e) => e.message,
                  'message',
                  contains('MQTT wildcard \'+\''),
                ),
          ),
        );
      });

      test('rejects prefix containing # wildcard', () {
        expect(
          () => TopicScheme.create('test/#', 'client-1'),
          throwsA(
            isA<InvalidConfigException>()
                .having((e) => e.parameter, 'parameter', 'prefix')
                .having(
                  (e) => e.message,
                  'message',
                  contains('MQTT wildcard \'#\''),
                ),
          ),
        );
      });

      test('rejects prefix that is too long', () {
        final longPrefix = 'a' * 51; // 51 UTF-8 bytes
        expect(
          () => TopicScheme.create(longPrefix, 'client-1'),
          throwsA(
            isA<InvalidConfigException>()
                .having((e) => e.parameter, 'parameter', 'prefix')
                .having(
                  (e) => e.message,
                  'message',
                  contains('51 UTF-8 bytes. Maximum allowed: 50 bytes'),
                ),
          ),
        );
      });

      test('accepts prefix with allowed characters', () {
        final scheme = TopicScheme.create(
          'Test_Prefix-123/sub-topic',
          'client-1',
        );
        expect(scheme.prefix, equals('Test_Prefix-123/sub-topic'));
      });

      test('rejects prefix with invalid characters', () {
        expect(
          () => TopicScheme.create('test@prefix', 'client-1'),
          throwsA(
            isA<InvalidConfigException>()
                .having((e) => e.parameter, 'parameter', 'prefix')
                .having(
                  (e) => e.message,
                  'message',
                  contains('invalid characters'),
                ),
          ),
        );
      });

      test('accepts prefix at maximum length (50 UTF-8 bytes)', () {
        final maxPrefix = 'a' * 50;
        final scheme = TopicScheme.create(maxPrefix, 'client-1');
        expect(scheme.prefix, equals(maxPrefix));
      });
    });

    group('clientId validation', () {
      test('rejects empty clientId', () {
        expect(
          () => TopicScheme.create('test', ''),
          throwsA(
            isA<InvalidConfigException>()
                .having((e) => e.parameter, 'parameter', 'clientId')
                .having(
                  (e) => e.message,
                  'message',
                  contains('cannot be empty'),
                ),
          ),
        );
      });

      test('rejects clientId longer than 128 UTF-8 bytes', () {
        final longClientId = 'a' * 129;
        expect(
          () => TopicScheme.create('test', longClientId),
          throwsA(
            isA<InvalidConfigException>()
                .having((e) => e.parameter, 'parameter', 'clientId')
                .having(
                  (e) => e.message,
                  'message',
                  contains('129 UTF-8 bytes. Maximum allowed: 128 bytes'),
                ),
          ),
        );
      });

      test('accepts clientId at maximum length (128 UTF-8 bytes)', () {
        final maxClientId = 'a' * 128;
        final scheme = TopicScheme.create('test', maxClientId);
        expect(scheme.clientId, equals(maxClientId));
      });

      test('rejects clientId containing forward slash', () {
        expect(
          () => TopicScheme.create('test', 'client/123'),
          throwsA(
            isA<InvalidConfigException>()
                .having((e) => e.parameter, 'parameter', 'clientId')
                .having(
                  (e) => e.message,
                  'message',
                  contains('forward slash (/)'),
                ),
          ),
        );
      });

      test('rejects clientId containing + wildcard', () {
        expect(
          () => TopicScheme.create('test', 'client+123'),
          throwsA(
            isA<InvalidConfigException>()
                .having((e) => e.parameter, 'parameter', 'clientId')
                .having(
                  (e) => e.message,
                  'message',
                  contains('MQTT wildcard \'+\''),
                ),
          ),
        );
      });

      test('rejects clientId containing # wildcard', () {
        expect(
          () => TopicScheme.create('test', 'client#123'),
          throwsA(
            isA<InvalidConfigException>()
                .having((e) => e.parameter, 'parameter', 'clientId')
                .having(
                  (e) => e.message,
                  'message',
                  contains('MQTT wildcard \'#\''),
                ),
          ),
        );
      });

      test('accepts valid clientId with allowed characters', () {
        final scheme = TopicScheme.create('test', 'device-123_ABC');
        expect(scheme.clientId, equals('device-123_ABC'));
      });
    });

    group('equality and toString', () {
      test('two schemes with same values are equal', () {
        final scheme1 = TopicScheme.create('test', 'client-1');
        final scheme2 = TopicScheme.create('test', 'client-1');

        expect(scheme1, equals(scheme2));
        expect(scheme1.hashCode, equals(scheme2.hashCode));
      });

      test('two schemes with different values are not equal', () {
        final scheme1 = TopicScheme.create('test1', 'client-1');
        final scheme2 = TopicScheme.create('test2', 'client-1');

        expect(scheme1, isNot(equals(scheme2)));
      });

      test('toString contains prefix and clientId', () {
        final scheme = TopicScheme.create('test-prefix', 'test-client');
        final str = scheme.toString();

        expect(str, contains('test-prefix'));
        expect(str, contains('test-client'));
      });
    });

    group('edge cases', () {
      test('handles single character prefix and clientId', () {
        final scheme = TopicScheme.create('a', 'b');

        expect(scheme.commandTopic, equals('a/b/cmd'));
        expect(scheme.responseTopic, equals('a/b/res'));
        expect(scheme.replicationTopic, equals('a/replication/events'));
      });

      test('handles numeric prefix and clientId', () {
        final scheme = TopicScheme.create('123', '456');

        expect(scheme.commandTopic, equals('123/456/cmd'));
        expect(scheme.responseTopic, equals('123/456/res'));
        expect(scheme.replicationTopic, equals('123/replication/events'));
      });

      test('handles underscore and hyphen characters', () {
        final scheme = TopicScheme.create('test_prefix-1', 'client_id-2');

        expect(scheme.commandTopic, equals('test_prefix-1/client_id-2/cmd'));
        expect(scheme.responseTopic, equals('test_prefix-1/client_id-2/res'));
        expect(
          scheme.replicationTopic,
          equals('test_prefix-1/replication/events'),
        );
      });
    });
  });
}
