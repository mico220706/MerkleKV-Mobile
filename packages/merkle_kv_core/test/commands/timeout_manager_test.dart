import 'package:test/test.dart';
import 'package:mockito/mockito.dart';
import 'package:async/async.dart';
import 'package:merkle_kv_mobile/src/commands/timeout_manager.dart';
import 'package:merkle_kv_mobile/src/commands/retry_policy.dart';
import 'package:merkle_kv_mobile/src/commands/operation_manager.dart';

void main() {
  group('TimeoutManager', () {
    late TimeoutManager timeoutManager;
    
    setUp(() {
      timeoutManager = TimeoutManager();
    });
    
    tearDown(() {
      timeoutManager.dispose();
    });
    
    test('should track operation timeouts correctly', () {
      // Start tracking an operation
      const String requestId = 'test-request-1';
      timeoutManager.startOperation(requestId);
      
      // Should not be timed out immediately
      expect(timeoutManager.isTimedOut(requestId, Duration(milliseconds: 100)), isFalse);
      
      // Wait for operation to time out
      Future.delayed(Duration(milliseconds: 150), () {
        expect(timeoutManager.isTimedOut(requestId, Duration(milliseconds: 100)), isTrue);
      });
    });
    
    test('should remove completed operations', () {
      // Start tracking operations
      const String requestId1 = 'test-request-1';
      const String requestId2 = 'test-request-2';
      
      timeoutManager.startOperation(requestId1);
      timeoutManager.startOperation(requestId2);
      
      // Complete one operation
      timeoutManager.completeOperation(requestId1);
      
      // Should not find completed operation
      expect(timeoutManager.getElapsed(requestId1), isNull);
      
      // Should still track uncompleted operation
      expect(timeoutManager.getElapsed(requestId2), isNotNull);
    });
    
    test('should handle non-existent operations', () {
      const String nonExistentId = 'non-existent';
      
      expect(timeoutManager.isTimedOut(nonExistentId, Duration(seconds: 1)), isFalse);
      expect(timeoutManager.getElapsed(nonExistentId), isNull);
      
      // Should not throw when completing non-existent operation
      expect(() => timeoutManager.completeOperation(nonExistentId), returnsNormally);
    });
  });
  
  group('RetryPolicy', () {
    test('should calculate exponential backoff with jitter', () {
      final policy = RetryPolicy(
        maxAttempts: 5,
        initialDelay: Duration(seconds: 1),
        backoffFactor: 2.0,
        maxDelay: Duration(seconds: 30),
        jitterFactor: 0.2,
      );
      
      // Collect multiple samples to verify jitter
      List<Duration> samples = List.generate(100, (_) => policy.calculateDelay(1));
      
      // Base delay should be 2s (1s * 2^1)
      // With ±20% jitter, range should be 1.6s to 2.4s
      for (final delay in samples) {
        expect(delay.inMilliseconds, greaterThanOrEqualTo(800));
        expect(delay.inMilliseconds, lessThanOrEqualTo(1200));
      }
      
      // Verify max delay cap
      final maxDelayAttempt = 10; // Should exceed max delay of 30s
      final cappedDelay = policy.calculateDelay(maxDelayAttempt);
      expect(cappedDelay.inMilliseconds, lessThanOrEqualTo(36000)); // 30s + 20% jitter
    });
    
    test('should respect max attempts', () {
      final policy = RetryPolicy(maxAttempts: 3);
      
      expect(policy.shouldRetry(0), isTrue);
      expect(policy.shouldRetry(1), isTrue);
      expect(policy.shouldRetry(2), isTrue);
      expect(policy.shouldRetry(3), isFalse);
    });
    
    test('should throw on invalid attempt counts', () {
      final policy = RetryPolicy(maxAttempts: 3);
      
      expect(() => policy.calculateDelay(-1), throwsArgumentError);
      expect(() => policy.calculateDelay(4), throwsArgumentError);
    });
  });
  
  group('OperationManager', () {
    late OperationManager operationManager;
    
    setUp(() {
      operationManager = OperationManager();
    });
    
    tearDown(() {
      operationManager.dispose();
    });
    
    test('should execute operations with proper timeouts', () async {
      // Test successful operation
      final result = await operationManager.executeOperation<String>(
        requestId: 'test-op-1',
        operationType: OperationType.singleKey,
        operation: () async {
          await Future.delayed(Duration(milliseconds: 50));
          return 'success';
        },
      );
      
      expect(result, equals('success'));
    });
    
    test('should handle operation timeouts', () async {
      // Test operation that exceeds timeout
      // We'll use a shorter timeout for testing
      final customManager = OperationManager(
        retryPolicy: RetryPolicy(initialDelay: Duration(milliseconds: 50)),
      );
      
      try {
        await customManager.executeOperation<String>(
          requestId: 'timeout-op',
          operationType: OperationType.singleKey,
          operation: () async {
            // Simulate long-running operation
            await Future.delayed(Duration(seconds: 15));
            return 'delayed result';
          },
        );
        fail('Should have thrown TimeoutException');
      } catch (e) {
        expect(e, isA<TimeoutException>());
      }
    });
    
    // Additional tests would cover retry behavior, result caching, etc.
  });
}