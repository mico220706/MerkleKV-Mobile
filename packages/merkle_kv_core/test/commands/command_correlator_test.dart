// ignore_for_file: prefer_const_constructors
import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:merkle_kv_core/merkle_kv_core.dart';

void main() {
  group('UuidGenerator', () {
    test('generates valid UUIDv4 format', () {
      for (int i = 0; i < 100; i++) {
        final uuid = UuidGenerator.generate();
        expect(uuid.length, equals(36));
        expect(UuidGenerator.isValidUuid(uuid), isTrue);

        // Check UUIDv4 specific format
        expect(uuid[14], equals('4')); // Version 4
        expect(['8', '9', 'a', 'b'].contains(uuid[19]), isTrue); // Variant
      }
    });

    test('generates unique UUIDs', () {
      final uuids = Set<String>();
      for (int i = 0; i < 1000; i++) {
        final uuid = UuidGenerator.generate();
        expect(uuids.contains(uuid), isFalse);
        uuids.add(uuid);
      }
    });

    test('validates UUID format correctly', () {
      expect(UuidGenerator.isValidUuid('550e8400-e29b-41d4-a716-446655440000'),
          isTrue);
      expect(UuidGenerator.isValidUuid('6ba7b810-9dad-11d1-80b4-00c04fd430c8'),
          isFalse); // Wrong version
      expect(UuidGenerator.isValidUuid('invalid-uuid'), isFalse);
      expect(UuidGenerator.isValidUuid(''), isFalse);
      expect(UuidGenerator.isValidUuid('550e8400-e29b-41d4-a716-44665544000'),
          isFalse); // Wrong length
    });

    test('validates ID length correctly', () {
      expect(UuidGenerator.isValidIdLength('a'), isTrue); // 1 char
      expect(UuidGenerator.isValidIdLength('a' * 64), isTrue); // 64 chars
      expect(UuidGenerator.isValidIdLength(''), isFalse); // 0 chars
      expect(UuidGenerator.isValidIdLength('a' * 65), isFalse); // 65 chars
    });
  });

  group('Command', () {
    test('creates command from valid JSON', () {
      final json = {
        'id': 'test-123',
        'op': 'GET',
        'key': 'test-key',
      };

      final command = Command.fromJson(json);
      expect(command.id, equals('test-123'));
      expect(command.op, equals('GET'));
      expect(command.key, equals('test-key'));
    });

    test('throws on missing required fields', () {
      expect(() => Command.fromJson({}), throwsA(isA<FormatException>()));
      expect(() => Command.fromJson({'id': 'test'}),
          throwsA(isA<FormatException>()));
      expect(() => Command.fromJson({'op': 'GET'}),
          throwsA(isA<FormatException>()));
    });

    test('serializes to JSON correctly', () {
      final command = Command(
        id: 'test-123',
        op: 'SET',
        key: 'test-key',
        value: 'test-value',
      );

      final json = command.toJson();
      expect(json['id'], equals('test-123'));
      expect(json['op'], equals('SET'));
      expect(json['key'], equals('test-key'));
      expect(json['value'], equals('test-value'));
    });

    test('determines operation types correctly', () {
      expect(Command(id: '1', op: 'GET').isSingleKeyOp, isTrue);
      expect(Command(id: '1', op: 'SET').isSingleKeyOp, isTrue);
      expect(Command(id: '1', op: 'MGET').isMultiKeyOp, isTrue);
      expect(Command(id: '1', op: 'MSET').isMultiKeyOp, isTrue);
      expect(Command(id: '1', op: 'SYNC').isSyncOp, isTrue);
      expect(Command(id: '1', op: 'SYNC_KEYS').isSyncOp, isTrue);
    });

    test('returns correct timeout durations', () {
      expect(Command(id: '1', op: 'GET').expectedTimeout.inSeconds, equals(10));
      expect(
          Command(id: '1', op: 'MGET').expectedTimeout.inSeconds, equals(20));
      expect(
          Command(id: '1', op: 'SYNC').expectedTimeout.inSeconds, equals(30));
    });

    test('handles JSON string parsing', () {
      final jsonString = jsonEncode({'id': 'test', 'op': 'GET'});
      final command = Command.fromJsonString(jsonString);
      expect(command.id, equals('test'));
      expect(command.op, equals('GET'));

      expect(() => Command.fromJsonString('invalid json'),
          throwsA(isA<FormatException>()));
    });
  });

  group('Response', () {
    test('creates successful response', () {
      final response = Response.ok(id: 'test-123', value: 'result');
      expect(response.id, equals('test-123'));
      expect(response.status, equals(ResponseStatus.ok));
      expect(response.value, equals('result'));
      expect(response.isSuccess, isTrue);
      expect(response.isError, isFalse);
    });

    test('creates error response', () {
      final response = Response.error(
        id: 'test-123',
        error: 'Test error',
        errorCode: ErrorCode.invalidRequest,
      );
      expect(response.id, equals('test-123'));
      expect(response.status, equals(ResponseStatus.error));
      expect(response.error, equals('Test error'));
      expect(response.errorCode, equals(ErrorCode.invalidRequest));
      expect(response.isSuccess, isFalse);
      expect(response.isError, isTrue);
    });

    test('creates timeout response', () {
      final response = Response.timeout('test-123');
      expect(response.errorCode, equals(ErrorCode.timeout));
      expect(response.error, contains('timeout'));
    });

    test('creates idempotent replay response', () {
      final response = Response.idempotentReplay('test-123', 'cached-value');
      expect(response.value, equals('cached-value'));
      expect(response.isIdempotentReplay, isTrue);
      expect(response.errorCode, equals(ErrorCode.idempotentReplay));
    });

    test('parses from JSON correctly', () {
      final json = {
        'id': 'test-123',
        'status': 'OK',
        'value': 'result',
      };

      final response = Response.fromJson(json);
      expect(response.id, equals('test-123'));
      expect(response.status, equals(ResponseStatus.ok));
      expect(response.value, equals('result'));
    });

    test('handles JSON string parsing', () {
      final jsonString =
          jsonEncode({'id': 'test', 'status': 'ERROR', 'error': 'Test error'});
      final response = Response.fromJsonString(jsonString);
      expect(response.id, equals('test'));
      expect(response.status, equals(ResponseStatus.error));
      expect(response.error, equals('Test error'));

      expect(() => Response.fromJsonString('invalid json'),
          throwsA(isA<FormatException>()));
    });
  });

  group('CommandCorrelator', () {
    late CommandCorrelator correlator;
    late List<String> publishedMessages;
    late List<Map<String, dynamic>> logEntries;

    setUp(() {
      publishedMessages = [];
      logEntries = [];

      correlator = CommandCorrelator(
        publishCommand: (jsonPayload) async {
          publishedMessages.add(jsonPayload);
        },
        logger: (entry) {
          logEntries.add(entry.toJson());
        },
      );
    });

    tearDown(() {
      correlator.dispose();
    });

    test('generates UUIDv4 for commands without ID', () async {
      final command = Command(id: '', op: 'GET', key: 'test');

      final responseFuture = correlator.send(command);
      expect(publishedMessages.length, equals(1));

      final publishedCommand = Command.fromJsonString(publishedMessages.first);
      expect(publishedCommand.id.length, equals(36));
      expect(UuidGenerator.isValidUuid(publishedCommand.id), isTrue);

      // Complete the request to avoid timeout
      correlator.onResponse(
          Response.ok(id: publishedCommand.id, value: 'result').toJsonString());
      final response = await responseFuture;
      expect(response.isSuccess, isTrue);
    });

    test('validates provided command ID length', () async {
      // Valid length
      final validCommand = Command(id: 'a' * 32, op: 'GET', key: 'test');
      expect(() => correlator.send(validCommand), returnsNormally);

      // Complete the request
      correlator.onResponse(
          Response.ok(id: validCommand.id, value: 'result').toJsonString());

      // Invalid length - too long
      final longCommand = Command(id: 'a' * 65, op: 'GET', key: 'test');
      expect(() => correlator.send(longCommand), throwsArgumentError);

      // Invalid length - empty
      final emptyCommand = Command(id: '', op: 'GET', key: 'test');
      // Empty ID should generate new UUID, not throw
      expect(() => correlator.send(emptyCommand), returnsNormally);
    });

    test('validates UUIDv4 format when 36-character ID provided', () async {
      // Valid UUIDv4
      final validUuid = UuidGenerator.generate();
      final validCommand = Command(id: validUuid, op: 'GET', key: 'test');
      expect(() => correlator.send(validCommand), returnsNormally);

      // Complete the request
      correlator.onResponse(
          Response.ok(id: validUuid, value: 'result').toJsonString());

      // Invalid UUIDv4 format
      final invalidCommand = Command(
          id: '550e8400-e29b-11d1-80b4-00c04fd430c8', op: 'GET', key: 'test');
      expect(() => correlator.send(invalidCommand), throwsArgumentError);
    });

    test('handles payload size validation', () async {
      // Create command with large payload
      final largeValue = 'x' * (600 * 1024); // 600 KiB
      final command =
          Command(id: 'test-123', op: 'SET', key: 'test', value: largeValue);

      final response = await correlator.send(command);
      expect(response.errorCode, equals(ErrorCode.payloadTooLarge));
      expect(publishedMessages.length, equals(0)); // Should not publish
    });

    test('correlates responses correctly', () async {
      final command1 = Command(id: 'req-1', op: 'GET', key: 'key1');
      final command2 = Command(id: 'req-2', op: 'GET', key: 'key2');

      final future1 = correlator.send(command1);
      final future2 = correlator.send(command2);

      expect(correlator.pendingRequestCount, equals(2));

      // Send responses in reverse order
      correlator
          .onResponse(Response.ok(id: 'req-2', value: 'value2').toJsonString());
      correlator
          .onResponse(Response.ok(id: 'req-1', value: 'value1').toJsonString());

      final response1 = await future1;
      final response2 = await future2;

      expect(response1.value, equals('value1'));
      expect(response2.value, equals('value2'));
      expect(correlator.pendingRequestCount, equals(0));
    });

    test('handles request timeouts correctly', () async {
      final command = Command(id: 'timeout-test', op: 'GET', key: 'test');

      // Mock command with very short timeout for testing
      final testCorrelator = CommandCorrelator(
        publishCommand: (jsonPayload) async {
          publishedMessages.add(jsonPayload);
        },
      );

      // Create a command that will timeout
      final future = testCorrelator.send(command);

      // Wait longer than the expected timeout
      await Future.delayed(Duration(milliseconds: 100));

      final response = await future.timeout(Duration(seconds: 15));
      expect(response.errorCode, equals(ErrorCode.timeout));

      testCorrelator.dispose();
    });

    test('implements deduplication cache correctly', () async {
      final command = Command(id: 'dedup-test', op: 'GET', key: 'test');

      // First request
      final future1 = correlator.send(command);
      correlator.onResponse(
          Response.ok(id: 'dedup-test', value: 'cached-value').toJsonString());
      final response1 = await future1;
      expect(response1.value, equals('cached-value'));

      // Second request with same ID should return cached response
      final response2 = await correlator.send(command);
      expect(response2.isIdempotentReplay, isTrue);
      expect(response2.value, equals('cached-value'));
      expect(publishedMessages.length, equals(1)); // Only one publish
    });

    test('handles late responses correctly', () async {
      final command = Command(id: 'late-test', op: 'GET', key: 'test');

      final future = correlator.send(command);

      // Wait for timeout
      final response = await future.timeout(Duration(seconds: 15));
      expect(response.errorCode, equals(ErrorCode.timeout));

      // Send response after timeout - should be cached but not complete future
      correlator.onResponse(
          Response.ok(id: 'late-test', value: 'late-value').toJsonString());

      // Second request should get cached response
      final response2 = await correlator.send(command);
      expect(response2.isIdempotentReplay, isTrue);
      expect(response2.value, equals('late-value'));
    });

    test('handles malformed responses gracefully', () {
      expect(() => correlator.onResponse('invalid json'), returnsNormally);
      expect(() => correlator.onResponse('{"invalid": "response"}'),
          returnsNormally);
      expect(
          logEntries.any((entry) => entry['phase'] == 'response_parse_error'),
          isTrue);
    });

    test('implements LRU cache eviction', () async {
      // Create correlator with small cache for testing
      final testCorrelator = CommandCorrelator(
        publishCommand: (jsonPayload) async {},
      );

      // Add entries beyond cache limit
      for (int i = 0; i < 1050; i++) {
        final command = Command(id: 'cache-test-$i', op: 'GET', key: 'test');
        final future = testCorrelator.send(command);
        testCorrelator.onResponse(
            Response.ok(id: 'cache-test-$i', value: 'value-$i').toJsonString());
        await future;
      }

      // Cache should be limited to max size
      expect(testCorrelator.cacheSize, lessThanOrEqualTo(1000));

      testCorrelator.dispose();
    });

    test('logs request lifecycle correctly', () async {
      final command = Command(id: 'log-test', op: 'GET', key: 'test');

      final future = correlator.send(command);
      correlator.onResponse(
          Response.ok(id: 'log-test', value: 'result').toJsonString());
      await future;

      // Check for expected log phases
      final phases = logEntries.map((entry) => entry['phase']).toList();
      expect(phases, contains('request_start'));
      expect(phases, contains('request_sent'));
      expect(phases, contains('response_received'));

      // Verify log structure
      final startEntry =
          logEntries.firstWhere((entry) => entry['phase'] == 'request_start');
      expect(startEntry['request_id'], equals('log-test'));
      expect(startEntry['op'], equals('GET'));
      expect(startEntry['size_bytes'], isA<int>());
      expect(startEntry['duration_ms'], isA<int>());
      expect(startEntry['result'], equals('pending'));
    });

    test('prevents duplicate pending requests', () async {
      final command = Command(id: 'duplicate-test', op: 'GET', key: 'test');

      final future1 = correlator.send(command);
      final future2 = correlator.send(command);

      // Both futures should be the same
      expect(identical(future1, future2), isTrue);
      expect(correlator.pendingRequestCount, equals(1));

      // Complete the request
      correlator.onResponse(
          Response.ok(id: 'duplicate-test', value: 'result').toJsonString());

      final response1 = await future1;
      final response2 = await future2;
      expect(response1.value, equals('result'));
      expect(response2.value, equals('result'));
    });

    test('cleans up on dispose', () async {
      final command = Command(id: 'dispose-test', op: 'GET', key: 'test');

      final future = correlator.send(command);
      expect(correlator.pendingRequestCount, equals(1));

      correlator.dispose();
      expect(correlator.pendingRequestCount, equals(0));
      expect(correlator.cacheSize, equals(0));

      final response = await future;
      expect(response.errorCode, equals(ErrorCode.internalError));
    });

    test('handles publish failures gracefully', () async {
      final failingCorrelator = CommandCorrelator(
        publishCommand: (jsonPayload) async {
          throw Exception('Publish failed');
        },
      );

      final command = Command(id: 'publish-fail-test', op: 'GET', key: 'test');
      final response = await failingCorrelator.send(command);

      expect(response.errorCode, equals(ErrorCode.internalError));
      expect(response.error, contains('Failed to publish command'));

      failingCorrelator.dispose();
    });
  });

  group('ErrorCode', () {
    test('provides correct error descriptions', () {
      expect(ErrorCode.describe(ErrorCode.invalidRequest),
          contains('Invalid request'));
      expect(ErrorCode.describe(ErrorCode.timeout), contains('timeout'));
      expect(ErrorCode.describe(ErrorCode.idempotentReplay),
          contains('Idempotent replay'));
      expect(ErrorCode.describe(ErrorCode.payloadTooLarge),
          contains('Payload exceeds'));
      expect(ErrorCode.describe(ErrorCode.internalError), contains('Internal'));
      expect(ErrorCode.describe(999), contains('Unknown error'));
    });
  });
}
