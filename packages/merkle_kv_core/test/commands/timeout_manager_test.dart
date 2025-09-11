import 'dart:async';
import 'dart:math';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';
import 'package:merkle_kv_core/src/commands/timeout_manager.dart';
import 'package:merkle_kv_core/src/commands/retry_policy.dart';
import 'package:merkle_kv_core/src/commands/operation_manager.dart';

class MockRandom extends Mock implements Random {
  double nextDouble() => super.noSuchMethod(
    Invocation.method(#nextDouble, []),
    returnValue: 0.5,
  );
}

void main() {
  group('TimeoutManager', () {
    late TimeoutManager timeoutManager;

    setUp(() {
      timeoutManager = TimeoutManager();
    });

    test('starts tracking operation correctly', () {
      const String requestId = 'test-request-1';
      timeoutManager.startOperation(requestId);
      expect(timeoutManager.getElapsedTime(requestId), isNot(Duration.zero));
    });

    test('stops tracking operation correctly', () {
      const String requestId = 'test-request-2';
      timeoutManager.startOperation(requestId);
      timeoutManager.stopOperation(requestId);
      expect(timeoutManager.getElapsedTime(requestId), Duration.zero);
    });

    test('detects timeout based on operation type', () async {
      const String requestId = 'test-request-3';
      timeoutManager.startOperation(requestId);
      
      // Wait to ensure timeout check will pass
      await Future.delayed(const Duration(milliseconds: 50));
      
      // Manually override timeout to smaller value for testing
      final testTimeout = Duration(milliseconds: 10);
      expect(timeoutManager.isTimedOut(requestId, testTimeout), isTrue);
    });

    test('returns correct timeout duration per operation type', () {
      expect(timeoutManager.getTimeoutForType(OperationType.singleKey), TimeoutManager.singleKeyTimeout);
      expect(timeoutManager.getTimeoutForType(OperationType.multiKey), TimeoutManager.multiKeyTimeout);
      expect(timeoutManager.getTimeoutForType(OperationType.sync), TimeoutManager.syncTimeout);
    });

    test('throws TimeoutException when operation times out', () {
      const String requestId = 'test-request-4';
      timeoutManager.startOperation(requestId);
      
      // Manually set timeout to a short value for testing
      final testTimeout = Duration(milliseconds: 5);
      
      // Ensure enough time has passed
      expect(() => timeoutManager.checkTimeout(requestId, OperationType.singleKey),
          throwsA(isA<TimeoutException>()));
    });

    test('cleanup stale operations', () async {
      const String requestId = 'test-request-5';
      timeoutManager.startOperation(requestId);
      
      // Wait to ensure operation is considered stale
      await Future.delayed(const Duration(milliseconds: 50));
      
      // Run cleanup
      timeoutManager.cleanupStaleOperations();
      
      // The operation should have been removed
      expect(timeoutManager.getElapsedTime(requestId), Duration.zero);
    });
  });

  group('RetryPolicy', () {
    test('calculates exponential backoff with jitter', () {
      final policy = RetryPolicy(
        initialDelay: const Duration(milliseconds: 100),
        backoffFactor: 2.0,
        jitterFactor: 0.2,
        random: MockRandom(),
      );
      
      final delay1 = policy.calculateDelay(1);
      final delay2 = policy.calculateDelay(2);
      final delay3 = policy.calculateDelay(3);
      
      // With backoffFactor 2.0:
      // - First attempt: 100ms
      // - Second attempt: 200ms
      // - Third attempt: 400ms
      
      // With a mock random that always returns 0.5, jitter factor will be 0
      // so delays will be exactly as calculated
      expect(delay1.inMilliseconds, 100);
      expect(delay2.inMilliseconds, 200);
      expect(delay3.inMilliseconds, 400);
    });

    test('respects maximum delay cap', () {
      final policy = RetryPolicy(
        initialDelay: const Duration(seconds: 1),
        backoffFactor: 10.0,
        maxDelay: const Duration(seconds: 5),
        random: MockRandom(),
      );
      
      // With backoffFactor 10.0:
      // - Attempt 1: 1s
      // - Attempt 2: 10s (capped to 5s)
      
      final delay1 = policy.calculateDelay(1);
      final delay2 = policy.calculateDelay(2);
      
      expect(delay1.inSeconds, 1);
      expect(delay2.inSeconds, 5); // Capped at maxDelay
    });

    test('determines if error is retriable', () {
      final policy = RetryPolicy(maxAttempts: 3);
      
      // Retriable errors
      final timeoutError = TimeoutException('request-id', Duration(seconds: 1));
      final networkError = Exception('Network connection lost');
      final brokerError = Exception('Broker disconnected');
      
      // Non-retriable errors
      final validationError = Exception('Invalid request format');
      final authError = Exception('Authentication failed');
      
      // Should retry network-related errors
      expect(policy.shouldRetry(timeoutError, 1), isTrue);
      expect(policy.shouldRetry(networkError, 1), isTrue);
      expect(policy.shouldRetry(brokerError, 1), isTrue);
      
      // Should not retry validation or auth errors
      expect(policy.shouldRetry(validationError, 1), isFalse);
      expect(policy.shouldRetry(authError, 1), isFalse);
    });

    test('stops retrying after max attempts', () {
      final policy = RetryPolicy(maxAttempts: 3);
      final error = TimeoutException('request-id', Duration(seconds: 1));
      
      expect(policy.shouldRetry(error, 1), isTrue);
      expect(policy.shouldRetry(error, 2), isTrue);
      expect(policy.shouldRetry(error, 3), isFalse); // Max attempts reached
    });
  });

  group('OperationManager', () {
    late OperationManager operationManager;

    setUp(() {
      operationManager = OperationManager();
    });

    test('executes operation with retry on failure', () async {
      int attempts = 0;
      bool succeeded = false;
      
      await operationManager.executeWithRetry(
        requestId: 'test-op',
        operationType: OperationType.singleKey,
        operation: () async {
          attempts++;
          
          if (attempts < 2) {
            throw Exception('Temporary network error');
          }
          
          succeeded = true;
          return 'success';
        },
      );
      
      expect(attempts, 2);
      expect(succeeded, isTrue);
    });

    test('uses custom retry policy when specified', () async {
      final customManager = OperationManager(
        retryPolicy: RetryPolicy(initialDelay: Duration(milliseconds: 50)),
      );
      
      int attempts = 0;
      
      await customManager.executeWithRetry(
        requestId: 'custom-policy-test',
        operationType: OperationType.singleKey,
        operation: () async {
          attempts++;
          
          if (attempts < 3) {
            throw Exception('Temporary failure');
          }
          
          return 'success';
        },
      );
      
      expect(attempts, 3);
    });

    test('times out operations that take too long', () async {
      final String requestId = 'timeout-test';
      
      expect(() async {
        await operationManager.executeWithRetry(
          requestId: requestId,
          operationType: OperationType.singleKey,
          operation: () async {
            // Override operation timeout for testing purposes
            await Future.delayed(Duration(seconds: 11));
            return 'success';
          },
        );
      }, throwsA(isA<TimeoutException>()));
    });

    test('queues failed operations for retry', () async {
      final operation = RetriableOperation(
        requestId: 'retry-test',
        executeOperation: () async {
          throw Exception('Network error');
        },
      );
      
      await operationManager.queueForRetry(operation);
      
      expect(operationManager.retryQueueSize, 1);
    });

    test('enforces queue size limit', () async {
      for (int i = 0; i < OperationManager.maxQueueSize + 10; i++) {
        final operation = RetriableOperation(
          requestId: 'queue-test-$i',
          executeOperation: () async {},
        );
        
        await operationManager.queueForRetry(operation);
      }
      
      // Queue should be capped at max size, oldest operations dropped
      expect(operationManager.retryQueueSize, OperationManager.maxQueueSize);
    });

    test('processes retry queue on reconnection', () async {
      int successCount = 0;
      
      // Add some operations that will succeed
      for (int i = 0; i < 5; i++) {
        final operation = RetriableOperation(
          requestId: 'reconnect-test-$i',
          executeOperation: () async {
            successCount++;
            return;
          },
        );
        
        await operationManager.queueForRetry(operation);
      }
      
      // Simulate reconnection
      operationManager.setConnectionState(true);
      
      // Allow time for queue processing
      await Future.delayed(Duration(milliseconds: 100));
      
      expect(successCount, 5);
      expect(operationManager.retryQueueSize, 0);
    });
  });
}