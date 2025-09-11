import 'dart:async';
import 'package:logging/logging.dart';
import 'timeout_manager.dart';
import 'retry_policy.dart';
import 'retry_queue.dart';
import 'error_classifier.dart';

/// Type of operation for timeout determination
enum OperationType {
  singleKey,
  multiKey,
  sync
}

/// Result of an operation attempt
class OperationResult<T> {
  final T? data;
  final Object? error;
  final bool success;
  
  OperationResult.success(this.data)
      : error = null,
        success = true;
  
  OperationResult.error(this.error)
      : data = null,
        success = false;
}

/// Manager for operation execution with timeout and retry handling
class OperationManager {
  static final Logger _logger = Logger('OperationManager');
  
  final TimeoutManager _timeoutManager = TimeoutManager();
  final RetryPolicy _retryPolicy;
  final RetryQueue _retryQueue;
  
  /// Cache for operation results to handle idempotent retries
  final Map<String, OperationResult> _resultCache = {};
  
  /// Maximum size of the result cache
  final int _maxCacheSize;
  
  /// Connection status
  bool _isConnected = true;
  
  OperationManager({
    RetryPolicy? retryPolicy,
    int maxQueueSize = 1000,
    int maxCacheSize = 1000,
  }) : _retryPolicy = retryPolicy ?? RetryPolicy(),
       _retryQueue = RetryQueue(
         maxQueueSize: maxQueueSize,
         retryPolicy: retryPolicy ?? RetryPolicy(),
         onPermanentFailure: (requestId, error) {
           _logger.severe('Permanent failure for operation $requestId: $error');
           // Could emit metrics or notify listeners here
         },
       ),
       _maxCacheSize = maxCacheSize;
  
  /// Updates the connection status
  set connectionStatus(bool isConnected) {
    _isConnected = isConnected;
    _retryQueue.isConnected = isConnected;
  }
  
  /// Executes an operation with timeout and retry handling
  /// 
  /// [requestId] - Unique identifier for the operation
  /// [operationType] - Type of operation for determining timeout
  /// [operation] - The operation to execute
  /// Returns a future that completes with the operation result
  Future<T> executeOperation<T>({
    required String requestId,
    required OperationType operationType,
    required Future<T> Function() operation,
  }) async {
    // Check cache for previous result (idempotency)
    final cachedResult = _resultCache[requestId];
    if (cachedResult != null) {
      _logger.fine('Found cached result for operation $requestId');
      if (cachedResult.success) {
        return cachedResult.data as T;
      } else {
        throw cachedResult.error!;
      }
    }
    
    // Get appropriate timeout for operation type
    final timeout = _getTimeoutForOperation(operationType);
    
    // Start tracking operation time
    _timeoutManager.startOperation(requestId);
    
    try {
      // Create a completer for the operation
      final completer = Completer<T>();
      
      // Execute operation with timeout
      Timer? timeoutTimer;
      timeoutTimer = Timer(timeout, () {
        if (!completer.isCompleted) {
          final elapsed = _timeoutManager.getElapsed(requestId);
          _logger.warning('Operation $requestId timed out after ${elapsed?.inMilliseconds}ms');
          completer.completeError(
            TimeoutException('Operation timed out', timeout)
          );
        }
      });
      
      // Execute the actual operation
      operation().then((result) {
        if (!completer.isCompleted) {
          timeoutTimer?.cancel();
          completer.complete(result);
        }
      }).catchError((error) {
        if (!completer.isCompleted) {
          timeoutTimer?.cancel();
          completer.completeError(error);
        }
      });
      
      // Wait for operation to complete (either success or timeout)
      final result = await completer.future;
      
      // Cache successful result
      _cacheResult(requestId, OperationResult<T>.success(result));
      
      return result;
    } catch (error) {
      // Handle error and determine if retriable
      if (!_isConnected || ErrorClassifier.isRetriable(error)) {
        _logger.info('Operation $requestId failed with retriable error: $error');
        
        // Queue for retry
        final retryFuture = Completer<T>();
        _retryQueue.enqueue(
          requestId,
          () async {
            try {
              // Re-execute operation on retry
              final result = await executeOperation<T>(
                requestId: requestId,
                operationType: operationType,
                operation: operation,
              );
              retryFuture.complete(result);
            } catch (e) {
              retryFuture.completeError(e);
            }
          },
          error: error,
        );
        
        // Cache error result for non-connected state
        _cacheResult(requestId, OperationResult<T>.error(error));
        
        // Rethrow the original error
        throw error;
      } else {
        // Non-retriable error
        _logger.warning('Operation $requestId failed with non-retriable error: $error');
        _cacheResult(requestId, OperationResult<T>.error(error));
        throw error;
      }
    } finally {
      // Stop tracking operation time
      _timeoutManager.completeOperation(requestId);
    }
  }
  
  /// Gets the appropriate timeout for an operation type
  Duration _getTimeoutForOperation(OperationType type) {
    switch (type) {
      case OperationType.singleKey:
        return TimeoutManager.singleKeyTimeout;
      case OperationType.multiKey:
        return TimeoutManager.multiKeyTimeout;
      case OperationType.sync:
        return TimeoutManager.syncTimeout;
    }
  }
  
  /// Caches an operation result
  void _cacheResult(String requestId, OperationResult result) {
    // Manage cache size
    if (_resultCache.length >= _maxCacheSize) {
      // Remove oldest entry (simple implementation)
      final oldestKey = _resultCache.keys.first;
      _resultCache.remove(oldestKey);
    }
    
    // Store result in cache
    _resultCache[requestId] = result;
  }
  
  /// Clears the operation result cache
  void clearCache() {
    _resultCache.clear();
  }
  
  /// Cleans up resources
  void dispose() {
    _timeoutManager.dispose();
    _retryQueue.dispose();
    _resultCache.clear();
  }
}

/// Extension for Completer to check if it's already completed
extension CompleterExtension<T> on Completer<T> {
  bool get isCompleted => future.isDone;
}

/// Extension for Future to check if it's already completed
extension FutureExtension<T> on Future<T> {
  bool get isDone {
    bool done = false;
    then((_) => done = true).catchError((_) => done = true);
    return done;
  }
}