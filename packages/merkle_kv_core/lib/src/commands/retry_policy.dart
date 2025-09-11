import 'dart:math';
import 'dart:async';

/// Policy for retrying failed operations
///
/// Implements exponential backoff with jitter to avoid retry storms:
/// - Base delay between retries (configurable, defaults to 1 second)
/// - Exponential backoff factor (configurable, defaults to 2.0)
/// - Maximum number of retry attempts (configurable, defaults to 3)
/// - Maximum delay cap (configurable, defaults to 30 seconds)
/// - Random jitter factor of ±20% to prevent retry storms
class RetryPolicy {
  /// Maximum number of retry attempts
  final int maxAttempts;
  
  /// Initial delay for first retry attempt
  final Duration initialDelay;
  
  /// Factor by which delay increases after each attempt
  final double backoffFactor;
  
  /// Maximum delay cap to prevent excessive waits
  final Duration maxDelay;
  
  /// Jitter factor (±20% by default)
  final double jitterFactor;
  
  /// Random generator for jitter calculations
  final Random _random;
  
  /// Creates a new retry policy with configurable parameters
  RetryPolicy({
    this.maxAttempts = 3,
    this.initialDelay = const Duration(seconds: 1),
    this.backoffFactor = 2.0,
    this.maxDelay = const Duration(seconds: 30),
    this.jitterFactor = 0.2,
    Random? random,
  }) : _random = random ?? Random();
  
  /// Calculates delay for a specific attempt with exponential backoff and jitter
  Duration calculateDelay(int attempt) {
    if (attempt <= 0) {
      return Duration.zero;
    }
    
    // Apply exponential backoff
    final double delayMillis = initialDelay.inMilliseconds * pow(backoffFactor, attempt - 1).toDouble();
    
    // Apply maximum delay cap
    final double cappedDelayMillis = min(delayMillis, maxDelay.inMilliseconds.toDouble());
    
    // Apply jitter: random value between -jitterFactor and +jitterFactor
    final double jitter = (_random.nextDouble() - 0.5) * 2 * jitterFactor;
    final int finalDelayMillis = (cappedDelayMillis * (1 + jitter)).round();
    
    // Ensure we never return a negative delay
    return Duration(milliseconds: max(1, finalDelayMillis));
  }
  
  /// Determines if an operation should be retried based on the error
  bool shouldRetry(Exception error, int currentAttempt) {
    // We've reached the maximum attempts
    if (currentAttempt >= maxAttempts) {
      return false;
    }
    
    // Check if the error is retriable
    return _isRetriableError(error);
  }
  
  /// Determines if an error type is retriable
  bool _isRetriableError(Exception error) {
    // Network errors, timeouts, and broker disconnections are retriable
    // Validation and authentication errors are not retriable
    
    // Check for common network/timeout errors
    if (error is TimeoutException) {
      return true;
    }
    
    // For other types of errors, check the error type or message
    // This would need to be customized based on your error hierarchy
    final String errorString = error.toString().toLowerCase();
    return errorString.contains('network') ||
           errorString.contains('connection') ||
           errorString.contains('timeout') ||
           errorString.contains('broker') ||
           errorString.contains('disconnected');
  }
}

/// Class representing a retriable operation for queue management
class RetriableOperation {
  /// Unique identifier for the operation (reused on retry)
  final String requestId;
  
  /// Number of attempts made so far
  int attemptCount = 0;
  
  /// Time when the operation was first attempted
  final DateTime firstAttemptTime;
  
  /// Time when the operation was last attempted
  DateTime lastAttemptTime;
  
  /// Function to execute the operation
  final Future<void> Function() executeOperation;
  
  RetriableOperation({
    required this.requestId,
    required this.executeOperation,
    DateTime? firstAttempt,
    DateTime? lastAttempt,
  }) : firstAttemptTime = firstAttempt ?? DateTime.now(),
       lastAttemptTime = lastAttempt ?? DateTime.now();
  
  /// Records a retry attempt
  void incrementAttempt() {
    attemptCount++;
    lastAttemptTime = DateTime.now();
  }
}