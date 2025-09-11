import 'dart:async';
import 'dart:collection';

import 'retry_policy.dart';
import 'timeout_manager.dart';

/// Exception thrown when the retry queue is full
class RetryQueueFullException implements Exception {
  final String message;
  
  RetryQueueFullException([this.message = 'Retry queue is full']);
  
  @override
  String toString() => 'RetryQueueFullException: $message';
}

/// Manages operations with timeout tracking and retry logic
class OperationManager {
  /// Maximum size of the retry queue
  static const int maxQueueSize = 1000;
  
  /// Manager for operation timeouts
  final TimeoutManager _timeoutManager;
  
  /// Policy for retry attempts
  final RetryPolicy _retryPolicy;
  
  /// Queue of operations waiting to be retried
  final Queue<RetriableOperation> _retryQueue = Queue<RetriableOperation>();
  
  /// Whether retry processing is currently active
  bool _isProcessingRetries = false;
  
  /// Whether the system is currently connected to the broker
  bool _isConnected = false;
  
  /// Creates a new operation manager
  OperationManager({
    TimeoutManager? timeoutManager,
    RetryPolicy? retryPolicy,
  }) : _timeoutManager = timeoutManager ?? TimeoutManager(),
       _retryPolicy = retryPolicy ?? RetryPolicy();
  
  /// Starts tracking an operation with timeout monitoring
  void startOperation(String requestId, OperationType operationType) {
    _timeoutManager.startOperation(requestId);
  }
  
  /// Completes an operation and stops timeout tracking
  void completeOperation(String requestId) {
    _timeoutManager.stopOperation(requestId);
  }
  
    /// Executes an operation with timeout monitoring and retry logic
    Future<T> executeWithRetry<T>({
        required String requestId,
        required OperationType operationType,
        required Future<T> Function() operation,
        RetryPolicy? customRetryPolicy,
        }) async {
        final retryPolicy = customRetryPolicy ?? _retryPolicy;
        int attempts = 0;
        
        while (true) {
            attempts++;
            _timeoutManager.startOperation(requestId);
            
            try {
            // Check timeout before executing
            _timeoutManager.checkTimeout(requestId, operationType);
            
            // Execute the operation with timeout
            final timeout = _timeoutManager.getTimeoutForType(operationType);
            final result = await operation().timeout(timeout, onTimeout: () {
                throw TimeoutException(requestId, _timeoutManager.getElapsedTime(requestId));
            });
            
            // Operation succeeded, stop the timer
            _timeoutManager.stopOperation(requestId);
            return result;
            } catch (e) {
            // Stop timing on error
            _timeoutManager.stopOperation(requestId);
            
            // Determine if we should retry
            if (e is Exception && retryPolicy.shouldRetry(e, attempts)) {
                // Calculate delay for this attempt
                final delay = retryPolicy.calculateDelay(attempts);
                
                // Wait before retrying
                await Future.delayed(delay);
                continue;
            }
            
            // Either not retriable or max attempts reached
            rethrow;
            }
        }
    }
  
  /// Queues a failed operation for retry when reconnected
  Future<void> queueForRetry(RetriableOperation operation) async {
    if (_retryQueue.length >= maxQueueSize) {
      // Apply overflow policy: drop oldest
      _retryQueue.removeFirst();
    }
    
    _retryQueue.add(operation);
    
    // If connected, try processing the retry queue
    if (_isConnected) {
      _processRetryQueue();
    }
  }
  
  /// Processes the retry queue
  Future<void> _processRetryQueue() async {
    if (_isProcessingRetries || !_isConnected || _retryQueue.isEmpty) {
      return;
    }
    
    _isProcessingRetries = true;
    
    try {
      while (_isConnected && _retryQueue.isNotEmpty) {
        final operation = _retryQueue.first;
        
        try {
          operation.incrementAttempt();
          await operation.executeOperation();
          _retryQueue.removeFirst(); // Success, remove from queue
        } catch (e) {
          if (e is Exception && _retryPolicy.shouldRetry(e, operation.attemptCount)) {
            // Move to the end of the queue for later retry
            _retryQueue.removeFirst();
            _retryQueue.add(operation);
            
            // Pause before processing next operation
            await Future.delayed(_retryPolicy.calculateDelay(operation.attemptCount));
          } else {
            // Not retriable or max attempts reached, remove from queue
            _retryQueue.removeFirst();
          }
        }
      }
    } finally {
      _isProcessingRetries = false;
    }
  }
  
  /// Updates connection state and processes retry queue if connected
  void setConnectionState(bool isConnected) {
    _isConnected = isConnected;
    
    if (isConnected) {
      // Process retry queue when connection is established
      _processRetryQueue();
    }
  }
  
  /// Gets the current size of the retry queue
  int get retryQueueSize => _retryQueue.length;
  
  /// Checks if an operation has exceeded its timeout
  void checkOperationTimeout(String requestId, OperationType operationType) {
    _timeoutManager.checkTimeout(requestId, operationType);
  }
}