import 'dart:async';

/// Manages operation timeouts according to Locked Spec §11
class TimeoutManager {
  /// Timeout for single-key operations (10 seconds)
  static const Duration singleKeyTimeout = Duration(seconds: 10);
  
  /// Timeout for multi-key operations (20 seconds)
  static const Duration multiKeyTimeout = Duration(seconds: 20);
  
  /// Timeout for sync operations (30 seconds)
  static const Duration syncTimeout = Duration(seconds: 30);

  /// Map to track active operations with their start times
  final Map<String, Stopwatch> _activeOperations = {};
  
  /// Starts tracking a new operation
  /// 
  /// [requestId] - Unique identifier for the operation
  void startOperation(String requestId) {
    final stopwatch = Stopwatch()..start();
    _activeOperations[requestId] = stopwatch;
  }

  /// Stops tracking an operation
  /// 
  /// [requestId] - Unique identifier for the operation
  void completeOperation(String requestId) {
    _activeOperations.remove(requestId);
  }
  
  /// Checks if an operation has timed out
  /// 
  /// [requestId] - Unique identifier for the operation
  /// [timeout] - Timeout duration for this operation type
  /// Returns true if operation has exceeded its timeout
  bool isTimedOut(String requestId, Duration timeout) {
    final stopwatch = _activeOperations[requestId];
    return stopwatch != null && stopwatch.elapsed > timeout;
  }
  
  /// Get elapsed time for an operation
  /// 
  /// [requestId] - Unique identifier for the operation
  /// Returns elapsed duration or null if operation not found
  Duration? getElapsed(String requestId) {
    final stopwatch = _activeOperations[requestId];
    return stopwatch?.elapsed;
  }
  
  /// Cleans up any lingering operations
  void dispose() {
    _activeOperations.clear();
  }
}