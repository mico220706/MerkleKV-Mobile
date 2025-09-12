import 'dart:async';
import 'dart:collection';
import 'package:logging/logging.dart';
import 'retry_policy.dart';

/// Represents a queued operation for retry
class RetryOperation {
  /// Unique identifier for the operation
  final String requestId;
  
  /// Function to execute when retrying the operation
  final Future<void> Function() operation;
  
  /// Current retry attempt (0-based)
  int attempts;
  
  /// Error that caused the operation to fail
  final Object? lastError;
  
  RetryOperation({
    required this.requestId,
    required this.operation,
    this.attempts = 0,
    this.lastError,
  });
}

/// Manages queue of operations to be retried
class RetryQueue {
  static final Logger _logger = Logger('RetryQueue');
  
  /// Maximum number of operations in the queue
  final int maxQueueSize;
  
  /// Retry policy to use for calculating delays
  final RetryPolicy retryPolicy;
  
  /// Internal queue of operations
  final Queue<RetryOperation> _queue = Queue<RetryOperation>();
  
  /// Map of request IDs to queued operations for quick lookup
  final Map<String, RetryOperation> _operationsMap = {};
  
  /// Callback for permanent failures
  final void Function(String requestId, Object error)? onPermanentFailure;
  
  /// Metrics for queue operations
  int _totalDropped = 0;
  int _totalRetried = 0;
  int _totalSucceeded = 0;
  int _totalPermanentFailures = 0;
  
  /// Connection state
  bool _isConnected = false;
  Timer? _retryTimer;

  RetryQueue({
    this.maxQueueSize = 1000,
    required this.retryPolicy,
    this.onPermanentFailure,
  });

  /// Gets the current size of the retry queue
  int get size => _queue.length;
  
  /// Gets the number of dropped operations due to queue overflow
  int get totalDropped => _totalDropped;
  
  /// Gets the total number of retry attempts
  int get totalRetried => _totalRetried;
  
  /// Gets the total number of eventually successful operations
  int get totalSucceeded => _totalSucceeded;
  
  /// Gets the total number of permanent failures
  int get totalPermanentFailures => _totalPermanentFailures;

  /// Updates the connection state and processes the queue if connected
  set isConnected(bool value) {
    final wasConnected = _isConnected;
    _isConnected = value;
    
    if (!wasConnected && _isConnected && _queue.isNotEmpty) {
      _logger.info('Connection restored. Processing ${_queue.length} queued operations');
      _processQueue();
    }
    
    if (!_isConnected) {
      // Cancel any pending retries when disconnected
      _cancelRetryTimer();
    }
  }

  /// Adds an operation to the retry queue
  /// 
  /// [requestId] - Unique identifier for the operation
  /// [operation] - Function to execute when retrying
  /// [attempts] - Current number of retry attempts (0 for first retry)
  /// [error] - Error that caused the operation to fail
  void enqueue(
    String requestId,
    Future<void> Function() operation,
    {int attempts = 0, Object? error}
  ) {
    // If operation is already in queue, update attempts and error
    if (_operationsMap.containsKey(requestId)) {
      final existing = _operationsMap[requestId]!;
      existing.attempts = attempts;
      _logger.fine('Updated existing operation $requestId in retry queue (attempt: $attempts)');
      return;
    }
    
    // Create new retry operation
    final retryOp = RetryOperation(
      requestId: requestId,
      operation: operation,
      attempts: attempts,
      lastError: error,
    );
    
    // Check if queue is at capacity
    if (_queue.length >= maxQueueSize) {
      // Drop oldest operation
      final dropped = _queue.removeFirst();
      _operationsMap.remove(dropped.requestId);
      _totalDropped++;
      _logger.warning(
        'Retry queue overflow. Dropped oldest operation ${dropped.requestId} ' 
        'after ${dropped.attempts} attempts'
      );
    }
    
    // Add new operation to queue
    _queue.add(retryOp);
    _operationsMap[requestId] = retryOp;
    _logger.fine('Added operation $requestId to retry queue (attempt: $attempts)');
    
    // If connected, process the queue
    if (_isConnected) {
      _processQueue();
    }
  }
  
  /// Removes an operation from the retry queue
  /// 
  /// [requestId] - Unique identifier for the operation to remove
  /// Returns true if operation was found and removed
  bool remove(String requestId) {
    final operation = _operationsMap.remove(requestId);
    if (operation != null) {
      _queue.remove(operation);
      _logger.fine('Removed operation $requestId from retry queue');
      return true;
    }
    return false;
  }
  
  /// Processes the next operation in the queue
  Future<void> _processQueue() async {
    _cancelRetryTimer();
    
    if (_queue.isEmpty || !_isConnected) {
      return;
    }
    
    final operation = _queue.first;
    _queue.removeFirst();
    _operationsMap.remove(operation.requestId);
    
    try {
      // Check if we've exceeded max retry attempts
      final exception = operation.lastError is Exception 
        ? operation.lastError as Exception 
        : Exception(operation.lastError?.toString() ?? 'Unknown error');
        
      if (!retryPolicy.shouldRetry(exception, operation.attempts + 1)) {
        _totalPermanentFailures++;
        _logger.warning(
          'Max retry attempts (${retryPolicy.maxAttempts}) reached for operation ' 
          '${operation.requestId}. Giving up.'
        );
        onPermanentFailure?.call(
          operation.requestId,
          operation.lastError ?? Exception('Max retry attempts reached')
        );
        return;
      }
      
      // Calculate delay for this attempt
      final delay = retryPolicy.calculateDelay(operation.attempts);
      _logger.fine(
        'Scheduling retry for operation ${operation.requestId} ' 
        '(attempt: ${operation.attempts + 1}) in ${delay.inMilliseconds}ms'
      );
      
      // Schedule retry after delay
      _retryTimer = Timer(delay, () async {
        _retryTimer = null;
        _totalRetried++;
        
        try {
          _logger.fine(
            'Executing retry for operation ${operation.requestId} ' 
            '(attempt: ${operation.attempts + 1})'
          );
          await operation.operation();
          
          // Operation succeeded
          _totalSucceeded++;
          _logger.info(
            'Successfully completed operation ${operation.requestId} ' 
            'after ${operation.attempts + 1} attempt(s)'
          );
        } catch (e) {
          _logger.warning(
            'Retry failed for operation ${operation.requestId} ' 
            '(attempt: ${operation.attempts + 1}): $e'
          );
          
          // Re-queue for another retry with incremented attempt count
          enqueue(
            operation.requestId,
            operation.operation,
            attempts: operation.attempts + 1,
            error: e,
          );
        }
        
        // Process next operation in queue
        _processQueue();
      });
    } catch (e) {
      _logger.severe('Error processing retry queue: $e');
      // Continue with next operation if there was an error
      _processQueue();
    }
  }
  
  /// Cancels any pending retry timer
  void _cancelRetryTimer() {
    if (_retryTimer != null && _retryTimer!.isActive) {
      _retryTimer!.cancel();
      _retryTimer = null;
    }
  }
  
  /// Clears the queue and cancels any pending retries
  void clear() {
    _cancelRetryTimer();
    _queue.clear();
    _operationsMap.clear();
    _logger.info('Retry queue cleared');
  }
  
  /// Cleans up resources
  void dispose() {
    _cancelRetryTimer();
    _queue.clear();
    _operationsMap.clear();
  }
}