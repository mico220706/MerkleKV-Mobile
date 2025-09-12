import 'package:test/test.dart';
import 'package:merkle_kv_core/src/errors/merkle_kv_exception.dart';

void main() {
  group('MerkleKVException', () {
    group('Base Exception', () {
      test('creates base exception with message', () {
        final exception = MerkleKVException('Test error');
        expect(exception.message, equals('Test error'));
        expect(exception.toString(), equals('MerkleKVException: Test error'));
      });

      test('creates base exception with message and cause', () {
        final cause = Exception('Root cause');
        final exception = MerkleKVException('Test error', cause);
        expect(exception.message, equals('Test error'));
        expect(exception.cause, equals(cause));
        expect(exception.toString(), contains('Test error'));
        expect(exception.toString(), contains('Root cause'));
      });
    });

    group('ConnectionException', () {
      test('creates connection timeout exception', () {
        final exception = ConnectionException.connectionTimeout();
        expect(exception, isA<ConnectionException>());
        expect(exception.message, contains('Connection timed out'));
      });

      test('creates broker unreachable exception', () {
        final exception = ConnectionException.brokerUnreachable('localhost:1883');
        expect(exception, isA<ConnectionException>());
        expect(exception.message, contains('Broker unreachable'));
        expect(exception.message, contains('localhost:1883'));
      });

      test('creates authentication failed exception', () {
        final exception = ConnectionException.authenticationFailed();
        expect(exception, isA<ConnectionException>());
        expect(exception.message, contains('Authentication failed'));
      });

      test('creates not connected exception', () {
        final exception = ConnectionException.notConnected();
        expect(exception, isA<ConnectionException>());
        expect(exception.message, contains('Not connected'));
      });

      test('creates connection lost exception', () {
        final exception = ConnectionException.connectionLost();
        expect(exception, isA<ConnectionException>());
        expect(exception.message, contains('Connection lost'));
      });

      test('creates generic connection exception', () {
        final exception = ConnectionException('Custom connection error');
        expect(exception, isA<ConnectionException>());
        expect(exception.message, equals('Custom connection error'));
      });
    });

    group('ValidationException', () {
      test('creates invalid key exception', () {
        final exception = ValidationException.invalidKey('Key too long');
        expect(exception, isA<ValidationException>());
        expect(exception.message, contains('Invalid key'));
        expect(exception.message, contains('Key too long'));
      });

      test('creates invalid value exception', () {
        final exception = ValidationException.invalidValue('Value too long');
        expect(exception, isA<ValidationException>());
        expect(exception.message, contains('Invalid value'));
        expect(exception.message, contains('Value too long'));
      });

      test('creates invalid configuration exception', () {
        final exception = ValidationException.invalidConfiguration('Invalid host');
        expect(exception, isA<ValidationException>());
        expect(exception.message, contains('Invalid configuration'));
        expect(exception.message, contains('Invalid host'));
      });

      test('creates invalid operation exception', () {
        final exception = ValidationException.invalidOperation('Cannot delete');
        expect(exception, isA<ValidationException>());
        expect(exception.message, contains('Invalid operation'));
        expect(exception.message, contains('Cannot delete'));
      });
    });

    group('TimeoutException', () {
      test('creates operation timeout exception', () {
        final exception = TimeoutException.operationTimeout('get');
        expect(exception, isA<TimeoutException>());
        expect(exception.message, contains('Operation timed out'));
        expect(exception.message, contains('get'));
      });

      test('creates command timeout exception', () {
        final exception = TimeoutException.commandTimeout('set', Duration(seconds: 30));
        expect(exception, isA<TimeoutException>());
        expect(exception.message, contains('Command timed out'));
        expect(exception.message, contains('set'));
        expect(exception.message, contains('30 seconds'));
      });

      test('creates response timeout exception', () {
        final exception = TimeoutException.responseTimeout();
        expect(exception, isA<TimeoutException>());
        expect(exception.message, contains('Response timed out'));
      });
    });

    group('PayloadException', () {
      test('creates payload too large exception', () {
        final exception = PayloadException.payloadTooLarge('Test payload');
        expect(exception, isA<PayloadException>());
        expect(exception.message, contains('Payload too large'));
        expect(exception.message, contains('Test payload'));
      });

      test('creates invalid format exception', () {
        final exception = PayloadException.invalidFormat('Expected CBOR');
        expect(exception, isA<PayloadException>());
        expect(exception.message, contains('Invalid payload format'));
        expect(exception.message, contains('Expected CBOR'));
      });
    });

    group('StorageException', () {
      test('creates storage failure exception', () {
        final exception = StorageException.storageFailure('Disk full');
        expect(exception, isA<StorageException>());
        expect(exception.message, contains('Storage operation failed'));
        expect(exception.message, contains('Disk full'));
      });

      test('creates storage corruption exception', () {
        final exception = StorageException.storageCorruption('Checksum mismatch');
        expect(exception, isA<StorageException>());
        expect(exception.message, contains('Storage corruption detected'));
        expect(exception.message, contains('Checksum mismatch'));
      });

      test('creates insufficient space exception', () {
        final exception = StorageException.insufficientSpace('Need 1GB');
        expect(exception, isA<StorageException>());
        expect(exception.message, contains('Insufficient storage space'));
        expect(exception.message, contains('Need 1GB'));
      });
    });
  });
}