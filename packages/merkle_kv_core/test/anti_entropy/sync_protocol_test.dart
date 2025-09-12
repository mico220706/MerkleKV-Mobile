import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:merkle_kv_core/merkle_kv_core.dart';

void main() {
  group('PayloadValidator', () {
    test('validates SYNC_KEYS payload within 512KiB limit', () {
      final keys = ['key1', 'key2', 'key3'];
      final entries = <String, StorageEntry>{
        'key1': StorageEntry.value(
          key: 'key1', value: 'value1', timestampMs: 1000, nodeId: 'node1', seq: 1,
        ),
        'key2': StorageEntry.value(
          key: 'key2', value: 'value2', timestampMs: 2000, nodeId: 'node1', seq: 2,
        ),
        'key3': StorageEntry.value(
          key: 'key3', value: 'value3', timestampMs: 3000, nodeId: 'node1', seq: 3,
        ),
      };

      expect(PayloadValidator.validateSyncKeysPayload(keys, entries), isTrue);
    });

    test('rejects SYNC_KEYS payload exceeding 512KiB limit', () {
      final keys = <String>[];
      final entries = <String, StorageEntry>{};
      
      // Create entries that exceed 512KiB
      final largeValue = 'x' * (100 * 1024); // 100KB per entry
      for (int i = 0; i < 10; i++) { // 10 * 100KB = 1MB > 512KiB
        final key = 'key$i';
        keys.add(key);
        entries[key] = StorageEntry.value(
          key: key, value: largeValue, timestampMs: 1000, nodeId: 'node1', seq: i + 1,
        );
      }

      expect(PayloadValidator.validateSyncKeysPayload(keys, entries), isFalse);
    });

    test('calculates total size correctly', () {
      final keys = ['test'];
      final entries = <String, StorageEntry>{
        'test': StorageEntry.value(
          key: 'test', value: 'value', timestampMs: 1000, nodeId: 'node1', seq: 1,
        ),
      };

      final size = PayloadValidator.calculateTotalSize(keys, entries);
      expect(size, greaterThan(0));
      expect(size, lessThan(1024)); // Should be small for this test data
    });

    test('validates individual request payload', () {
      final smallRequest = {
        'requestId': 'test',
        'sourceNodeId': 'node1',
        'keys': ['key1'],
      };

      expect(() => PayloadValidator.validatePayload(smallRequest, 'TEST'), 
             returnsNormally);
    });

    test('rejects oversized individual request payload', () {
      final largeRequest = {
        'requestId': 'test',
        'sourceNodeId': 'node1',
        'keys': List.generate(50000, (i) => 'very_long_key_name_$i' * 10),
      };

      expect(() => PayloadValidator.validatePayload(largeRequest, 'TEST'),
             throwsA(isA<SyncException>()
                 .having((e) => e.code, 'code', SyncErrorCode.payloadTooLarge)));
    });
  });

  group('RateLimiter', () {
    test('allows requests within rate limit', () {
      final limiter = RateLimiter(requestsPerSecond: 10.0);

      // Should allow several requests immediately
      expect(limiter.tryConsume(), isTrue);
      expect(limiter.tryConsume(), isTrue);
      expect(limiter.tryConsume(), isTrue);
    });

    test('blocks requests exceeding rate limit', () {
      final limiter = RateLimiter(requestsPerSecond: 1.0, bucketCapacity: 2);

      // Consume all tokens
      expect(limiter.tryConsume(), isTrue);
      expect(limiter.tryConsume(), isTrue);
      
      // Should be blocked now
      expect(limiter.tryConsume(), isFalse);
    });

    test('refills tokens over time', () async {
      final limiter = RateLimiter(requestsPerSecond: 10.0, bucketCapacity: 1);

      // Consume token
      expect(limiter.tryConsume(), isTrue);
      expect(limiter.tryConsume(), isFalse);

      // Wait for token refill
      await Future.delayed(Duration(milliseconds: 150)); // > 100ms = 1 token at 10/sec

      expect(limiter.tryConsume(), isTrue);
    });

    test('reports available tokens correctly', () {
      final limiter = RateLimiter(requestsPerSecond: 5.0, bucketCapacity: 10);
      
      expect(limiter.availableTokens, equals(10.0));
      
      limiter.tryConsume();
      expect(limiter.availableTokens, equals(9.0));
    });
  });

  group('SyncResult', () {
    test('creates successful result', () {
      final result = SyncResult.success(
        remoteNodeId: 'node2',
        keysExamined: 100,
        keysSynced: 5,
        rounds: 2,
        duration: Duration(milliseconds: 500),
      );

      expect(result.success, isTrue);
      expect(result.remoteNodeId, equals('node2'));
      expect(result.keysExamined, equals(100));
      expect(result.keysSynced, equals(5));
      expect(result.rounds, equals(2));
      expect(result.duration.inMilliseconds, equals(500));
      expect(result.errorCode, isNull);
    });

    test('creates failure result', () {
      final result = SyncResult.failure(
        remoteNodeId: 'node2',
        errorCode: SyncErrorCode.timeout,
        errorMessage: 'Connection timeout',
        duration: Duration(milliseconds: 30000),
      );

      expect(result.success, isFalse);
      expect(result.errorCode, equals(SyncErrorCode.timeout));
      expect(result.errorMessage, equals('Connection timeout'));
      expect(result.keysExamined, equals(0));
      expect(result.keysSynced, equals(0));
    });

    test('toString includes relevant information', () {
      final result = SyncResult.success(
        remoteNodeId: 'node2',
        keysExamined: 50,
        keysSynced: 3,
        rounds: 1,
        duration: Duration(milliseconds: 200),
      );

      final str = result.toString();
      expect(str, contains('success: true'));
      expect(str, contains('remoteNode: node2'));
      expect(str, contains('keysExamined: 50'));
      expect(str, contains('keysSynced: 3'));
      expect(str, contains('200ms'));
    });
  });

  group('SyncRequest/Response serialization', () {
    test('SyncRequest serializes and deserializes correctly', () {
      final original = SyncRequest(
        requestId: 'req123',
        sourceNodeId: 'node1',
        rootHash: Uint8List.fromList([1, 2, 3, 4]),
        timestamp: DateTime.fromMillisecondsSinceEpoch(1000000),
        timeoutMs: 15000,
      );

      final map = original.toMap();
      final deserialized = SyncRequest.fromMap(map);

      expect(deserialized.requestId, equals(original.requestId));
      expect(deserialized.sourceNodeId, equals(original.sourceNodeId));
      expect(deserialized.rootHash, equals(original.rootHash));
      expect(deserialized.timestamp, equals(original.timestamp));
      expect(deserialized.timeoutMs, equals(original.timeoutMs));
    });

    test('SyncResponse serializes and deserializes correctly', () {
      final original = SyncResponse(
        requestId: 'req123',
        responseNodeId: 'node2',
        rootHash: Uint8List.fromList([5, 6, 7, 8]),
        hashesMatch: false,
        divergentPaths: ['path1', 'path2'],
        timestamp: DateTime.fromMillisecondsSinceEpoch(2000000),
      );

      final map = original.toMap();
      final deserialized = SyncResponse.fromMap(map);

      expect(deserialized.requestId, equals(original.requestId));
      expect(deserialized.responseNodeId, equals(original.responseNodeId));
      expect(deserialized.rootHash, equals(original.rootHash));
      expect(deserialized.hashesMatch, equals(original.hashesMatch));
      expect(deserialized.divergentPaths, equals(original.divergentPaths));
      expect(deserialized.timestamp, equals(original.timestamp));
    });

    test('SyncKeysRequest serializes and deserializes correctly', () {
      final entries = <String, StorageEntry>{
        'key1': StorageEntry.value(
          key: 'key1', value: 'value1', timestampMs: 1000, nodeId: 'node1', seq: 1,
        ),
      };

      final original = SyncKeysRequest(
        requestId: 'req456',
        sourceNodeId: 'node1',
        keys: ['key1', 'key2'],
        entries: entries,
        timestamp: DateTime.fromMillisecondsSinceEpoch(3000000),
      );

      final map = original.toMap();
      final deserialized = SyncKeysRequest.fromMap(map);

      expect(deserialized.requestId, equals(original.requestId));
      expect(deserialized.sourceNodeId, equals(original.sourceNodeId));
      expect(deserialized.keys, equals(original.keys));
      expect(deserialized.entries.length, equals(1));
      expect(deserialized.entries['key1']!.value, equals('value1'));
      expect(deserialized.timestamp, equals(original.timestamp));
    });

    test('SyncKeysResponse serializes and deserializes correctly', () {
      final entries = <String, StorageEntry>{
        'key1': StorageEntry.value(
          key: 'key1', value: 'updated_value', timestampMs: 2000, nodeId: 'node2', seq: 1,
        ),
      };

      final original = SyncKeysResponse(
        requestId: 'req456',
        responseNodeId: 'node2',
        entries: entries,
        notFoundKeys: ['key2'],
        timestamp: DateTime.fromMillisecondsSinceEpoch(4000000),
      );

      final map = original.toMap();
      final deserialized = SyncKeysResponse.fromMap(map);

      expect(deserialized.requestId, equals(original.requestId));
      expect(deserialized.responseNodeId, equals(original.responseNodeId));
      expect(deserialized.entries.length, equals(1));
      expect(deserialized.entries['key1']!.value, equals('updated_value'));
      expect(deserialized.notFoundKeys, equals(['key2']));
      expect(deserialized.timestamp, equals(original.timestamp));
    });
  });

  group('SyncException', () {
    test('creates exception with error code and message', () {
      final exception = SyncException(
        SyncErrorCode.payloadTooLarge,
        'Payload exceeds 512KiB limit',
      );

      expect(exception.code, equals(SyncErrorCode.payloadTooLarge));
      expect(exception.message, equals('Payload exceeds 512KiB limit'));
      expect(exception.cause, isNull);
    });

    test('creates exception with cause', () {
      final cause = ArgumentError('Invalid argument');
      final exception = SyncException(
        SyncErrorCode.invalidRequest,
        'Request validation failed',
        cause,
      );

      expect(exception.code, equals(SyncErrorCode.invalidRequest));
      expect(exception.message, equals('Request validation failed'));
      expect(exception.cause, equals(cause));
    });

    test('toString includes error code and message', () {
      final exception = SyncException(
        SyncErrorCode.timeout,
        'Operation timed out',
      );

      final str = exception.toString();
      expect(str, contains('timeout'));
      expect(str, contains('Operation timed out'));
    });
  });
}