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

      test('creates base exception with null cause', () {
        final exception = MerkleKVException('Test error', null);
        expect(exception.message, equals('Test error'));
        expect(exception.cause, isNull);
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

      test('connection exception is subclass of MerkleKVException', () {
        final exception = ConnectionException.connectionTimeout();
        expect(exception, isA<MerkleKVException>());
      });

      test('connection exception with cause', () {
        final cause = Exception('Network error');
        final exception = ConnectionException('Connection failed', cause);
        expect(exception.cause, equals(cause));
        expect(exception.toString(), contains('Network error'));
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

      test('creates generic validation exception', () {
        final exception = ValidationException('Custom validation error');
        expect(exception, isA<ValidationException>());
        expect(exception.message, equals('Custom validation error'));
      });

      test('validation exception is subclass of MerkleKVException', () {
        final exception = ValidationException.invalidKey('test');
        expect(exception, isA<MerkleKVException>());
      });

      test('validation exception with cause', () {
        final cause = FormatException('Invalid format');
        final exception = ValidationException('Validation failed', cause);
        expect(exception.cause, equals(cause));
        expect(exception.toString(), contains('Invalid format'));
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

      test('creates generic timeout exception', () {
        final exception = TimeoutException('Custom timeout error');
        expect(exception, isA<TimeoutException>());
        expect(exception.message, equals('Custom timeout error'));
      });

      test('timeout exception is subclass of MerkleKVException', () {
        final exception = TimeoutException.operationTimeout('test');
        expect(exception, isA<MerkleKVException>());
      });

      test('timeout exception with cause', () {
        final cause = Exception('Network timeout');
        final exception = TimeoutException('Timeout occurred', cause);
        expect(exception.cause, equals(cause));
        expect(exception.toString(), contains('Network timeout'));
      });
    });

    group('PayloadException', () {
      test('creates payload too large exception', () {
        final exception = PayloadException.payloadTooLarge('Test payload');
        expect(exception, isA<PayloadException>());
        expect(exception.message, contains('Payload too large'));
        expect(exception.message, contains('Test payload'));
      });

      test('creates serialization failed exception', () {
        final exception = PayloadException.serializationFailed('Invalid JSON');
        expect(exception, isA<PayloadException>());
        expect(exception.message, contains('Serialization failed'));
        expect(exception.message, contains('Invalid JSON'));
      });

      test('creates deserialization failed exception', () {
        final exception = PayloadException.deserializationFailed('Corrupted data');
        expect(exception, isA<PayloadException>());
        expect(exception.message, contains('Deserialization failed'));
        expect(exception.message, contains('Corrupted data'));
      });

      test('creates invalid format exception', () {
        final exception = PayloadException.invalidFormat('Expected CBOR');
        expect(exception, isA<PayloadException>());
        expect(exception.message, contains('Invalid payload format'));
        expect(exception.message, contains('Expected CBOR'));
      });

      test('creates generic payload exception', () {
        final exception = PayloadException('Custom payload error');
        expect(exception, isA<PayloadException>());
        expect(exception.message, equals('Custom payload error'));
      });

      test('payload exception is subclass of MerkleKVException', () {
        final exception = PayloadException.payloadTooLarge('test');
        expect(exception, isA<MerkleKVException>());
      });

      test('payload exception with cause', () {
        final cause = FormatException('JSON error');
        final exception = PayloadException('Payload error', cause);
        expect(exception.cause, equals(cause));
        expect(exception.toString(), contains('JSON error'));
      });
    });

    group('StorageException', () {
      test('creates storage failure exception', () {
        final exception = StorageException.storageFailure('Disk full');
        expect(exception, isA<StorageException>());
        expect(exception.message, contains('Storage operation failed'));
        expect(exception.message, contains('Disk full'));
      });

      test('creates key not found exception', () {
        final exception = StorageException.keyNotFound('missing_key');
        expect(exception, isA<StorageException>());
        expect(exception.message, contains('Key not found'));
        expect(exception.message, contains('missing_key'));
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

      test('creates generic storage exception', () {
        final exception = StorageException('Custom storage error');
        expect(exception, isA<StorageException>());
        expect(exception.message, equals('Custom storage error'));
      });

      test('storage exception is subclass of MerkleKVException', () {
        final exception = StorageException.storageFailure('test');
        expect(exception, isA<MerkleKVException>());
      });

      test('storage exception with cause', () {
        final cause = Exception('IO error');
        final exception = StorageException('Storage error', cause);
        expect(exception.cause, equals(cause));
        expect(exception.toString(), contains('IO error'));
      });
    });

    group('Exception Hierarchy', () {
      test('all exceptions extend MerkleKVException', () {
        expect(ConnectionException('test'), isA<MerkleKVException>());
        expect(ValidationException('test'), isA<MerkleKVException>());
        expect(TimeoutException('test'), isA<MerkleKVException>());
        expect(PayloadException('test'), isA<MerkleKVException>());
        expect(StorageException('test'), isA<MerkleKVException>());
      });

      test('exceptions maintain proper inheritance chain', () {
        final exception = ConnectionException.connectionTimeout();
        expect(exception, isA<ConnectionException>());
        expect(exception, isA<MerkleKVException>());
        expect(exception, isA<Exception>());
      });

      test('different exception types are distinguishable', () {
        final connection = ConnectionException('test');
        final validation = ValidationException('test');
        final timeout = TimeoutException('test');
        final payload = PayloadException('test');
        final storage = StorageException('test');

        expect(connection, isNot(isA<ValidationException>()));
        expect(validation, isNot(isA<ConnectionException>()));
        expect(timeout, isNot(isA<PayloadException>()));
        expect(payload, isNot(isA<StorageException>()));
        expect(storage, isNot(isA<TimeoutException>()));
      });
    });

    group('toString Implementation', () {
      test('base exception toString format', () {
        final exception = MerkleKVException('Test message');
        expect(exception.toString(), equals('MerkleKVException: Test message'));
      });

      test('subclass exception toString format', () {
        final exception = ConnectionException('Connection failed');
        expect(exception.toString(), equals('ConnectionException: Connection failed'));
      });

      test('exception with cause toString format', () {
        final cause = Exception('Root cause');
        final exception = ValidationException('Validation failed', cause);
        final result = exception.toString();
        
        expect(result, contains('ValidationException: Validation failed'));
        expect(result, contains('Caused by: Exception: Root cause'));
      });

      test('nested cause toString format', () {
        final rootCause = FormatException('Invalid format');
        final intermediateCause = Exception('Processing error');
        final exception = PayloadException('Payload error', intermediateCause);
        
        final result = exception.toString();
        expect(result, contains('PayloadException: Payload error'));
        expect(result, contains('Caused by: Exception: Processing error'));
      });
    });

    group('Factory Constructor Validation', () {
      test('factory constructors create correct exception types', () {
        expect(ConnectionException.connectionTimeout(), isA<ConnectionException>());
        expect(ValidationException.invalidKey('test'), isA<ValidationException>());
        expect(TimeoutException.operationTimeout('test'), isA<TimeoutException>());
        expect(PayloadException.payloadTooLarge('test'), isA<PayloadException>());
        expect(StorageException.storageFailure('test'), isA<StorageException>());
      });

      test('factory constructors preserve message content', () {
        final conn = ConnectionException.brokerUnreachable('host:1883');
        expect(conn.message, contains('host:1883'));

        final val = ValidationException.invalidValue('too long');
        expect(val.message, contains('too long'));

        final timeout = TimeoutException.commandTimeout('get', Duration(seconds: 5));
        expect(timeout.message, contains('get'));
        expect(timeout.message, contains('5 seconds'));

        final payload = PayloadException.serializationFailed('bad json');
        expect(payload.message, contains('bad json'));

        final storage = StorageException.keyNotFound('missing');
        expect(storage.message, contains('missing'));
      });
    });
  });
}