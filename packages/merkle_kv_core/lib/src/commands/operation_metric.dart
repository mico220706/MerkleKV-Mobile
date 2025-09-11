import 'dart:async';

/// Metrics collector for operation timeout and retry statistics
class OperationMetrics {
  int _operationTimeoutsTotal = 0;
  int _operationRetriesTotal = 0;
  int _operationSuccessTotal = 0;
  int _operationFailureTotal = 0;
  int _retryQueueDrops = 0;
  
  final Map<String, int> _timeoutsByOperationType = {};
  final Map<int, int> _retryAttemptDistribution = {};
  final List<int> _retryBackoffTimes = [];
  
  /// Stream controllers for metric events
  final _timeoutController = StreamController<OperationTimeoutEvent>.broadcast();
  final _retryController = StreamController<OperationRetryEvent>.broadcast();
  final _successController = StreamController<OperationSuccessEvent>.broadcast();
  
  /// Stream of timeout events
  Stream<OperationTimeoutEvent> get timeoutEvents => _timeoutController.stream;
  
  /// Stream of retry events
  Stream<OperationRetryEvent> get retryEvents => _retryController.stream;
  
  /// Stream of success events
  Stream<OperationSuccessEvent> get successEvents => _successController.stream;
  
  /// Records a timeout event
  void recordTimeout(String operationType, Duration elapsed) {
    _operationTimeoutsTotal++;
    _timeoutsByOperationType.update(
      operationType,
      (value) => value + 1,
      ifAbsent: () => 1,
    );
    
    _timeoutController.add(
      OperationTimeoutEvent(
        operationType: operationType,
        elapsedMs: elapsed.inMilliseconds,
      ),
    );
  }
  
  /// Records a retry event
  void recordRetry(String requestId, int attempt, Duration backoffDelay) {
    _operationRetriesTotal++;
    _retryAttemptDistribution.update(
      attempt,
      (value) => value + 1,
      ifAbsent: () => 1,
    );
    _retryBackoffTimes.add(backoffDelay.inMilliseconds);
    
    _retryController.add(
      OperationRetryEvent(
        requestId: requestId,
        attempt: attempt,
        backoffDelayMs: backoffDelay.inMilliseconds,
      ),
    );
  }
  
  /// Records a successful operation
  void recordSuccess(String requestId, int attempts, Duration totalDuration) {
    _operationSuccessTotal++;
    
    _successController.add(
      OperationSuccessEvent(
        requestId: requestId,
        attempts: attempts,
        totalDurationMs: totalDuration.inMilliseconds,
      ),
    );
  }
  
  /// Records a failed operation
  void recordFailure() {
    _operationFailureTotal++;
  }
  
  /// Records a retry queue drop
  void recordRetryQueueDrop() {
    _retryQueueDrops++;
  }
  
  /// Gets the total number of operation timeouts
  int get operationTimeoutsTotal => _operationTimeoutsTotal;
  
  /// Gets the total number of operation retries
  int get operationRetriesTotal => _operationRetriesTotal;
  
  /// Gets the total number of successful operations
  int get operationSuccessTotal => _operationSuccessTotal;
  
  /// Gets the total number of failed operations
  int get operationFailureTotal => _operationFailureTotal;
  
  /// Gets the total number of retry queue drops
  int get retryQueueDrops => _retryQueueDrops;
  
  /// Gets the timeout count by operation type
  Map<String, int> get timeoutsByOperationType => Map.unmodifiable(_timeoutsByOperationType);
  
  /// Gets the distribution of retry attempts
  Map<int, int> get retryAttemptDistribution => Map.unmodifiable(_retryAttemptDistribution);
  
  /// Gets the success rate after retries (percentage)
  double get eventualSuccessRate {
    final total = _operationSuccessTotal + _operationFailureTotal;
    if (total == 0) return 0.0;
    return (_operationSuccessTotal / total) * 100;
  }
  
  /// Gets statistics about retry backoff times
  RetryBackoffStats get retryBackoffStats {
    if (_retryBackoffTimes.isEmpty) {
      return RetryBackoffStats(
        minMs: 0,
        maxMs: 0,
        averageMs: 0,
      );
    }
    
    _retryBackoffTimes.sort();
    final min = _retryBackoffTimes.first;
    final max = _retryBackoffTimes.last;
    final average = _retryBackoffTimes.fold(0, (sum, time) => sum + time) / _retryBackoffTimes.length;
    
    return RetryBackoffStats(
      minMs: min,
      maxMs: max,
      averageMs: average,
    );
  }
  
  /// Resets all metrics
  void reset() {
    _operationTimeoutsTotal = 0;
    _operationRetriesTotal = 0;
    _operationSuccessTotal = 0;
    _operationFailureTotal = 0;
    _retryQueueDrops = 0;
    _timeoutsByOperationType.clear();
    _retryAttemptDistribution.clear();
    _retryBackoffTimes.clear();
  }
  
  /// Disposes resources
  void dispose() {
    _timeoutController.close();
    _retryController.close();
    _successController.close();
  }
}

/// Event for operation timeouts
class OperationTimeoutEvent {
  final String operationType;
  final int elapsedMs;
  
  OperationTimeoutEvent({
    required this.operationType,
    required this.elapsedMs,
  });
}

/// Event for operation retries
class OperationRetryEvent {
  final String requestId;
  final int attempt;
  final int backoffDelayMs;
  
  OperationRetryEvent({
    required this.requestId,
    required this.attempt,
    required this.backoffDelayMs,
  });
}

/// Event for successful operations
class OperationSuccessEvent {
  final String requestId;
  final int attempts;
  final int totalDurationMs;
  
  OperationSuccessEvent({
    required this.requestId,
    required this.attempts,
    required this.totalDurationMs,
  });
}

/// Statistics about retry backoff times
class RetryBackoffStats {
  final int minMs;
  final int maxMs;
  final double averageMs;
  
  RetryBackoffStats({
    required this.minMs,
    required this.maxMs,
    required this.averageMs,
  });
}