import 'dart:math';

/// Manages retry policies for failed operations
class RetryPolicy {
  /// Maximum number of retry attempts
  final int maxAttempts;
  
  /// Initial delay before first retry
  final Duration initialDelay;
  
  /// Multiplier for exponential backoff
  final double backoffFactor;
  
  /// Maximum delay between retries
  final Duration maxDelay;
  
  /// Jitter factor to randomize retry delays (±20%)
  final double jitterFactor;
  
  /// Random number generator for jitter calculation
  final Random _random = Random();

  /// Creates a retry policy with the specified parameters
  RetryPolicy({
    this.maxAttempts = 5,
    this.initialDelay = const Duration(seconds: 1),
    this.backoffFactor = 2.0,
    this.maxDelay = const Duration(seconds: 30),
    this.jitterFactor = 0.2,
  });

  /// Calculates delay for the current retry attempt with jitter
  /// 
  /// [attempt] - Current retry attempt number (0-based)
  /// Returns the duration to wait before next retry
  Duration calculateDelay(int attempt) {
    if (attempt < 0) {
      throw ArgumentError('Attempt count must be non-negative');
    }
    
    if (attempt >= maxAttempts) {
      throw ArgumentError('Attempt count exceeds maximum attempts');
    }
    
    // Calculate base delay with exponential backoff
    final baseDelayMs = initialDelay.inMilliseconds * pow(backoffFactor, attempt);
    
    // Cap the delay at maxDelay
    final cappedDelayMs = min(baseDelayMs, maxDelay.inMilliseconds);
    
    // Apply jitter: random value between -jitterFactor and +jitterFactor
    final jitter = (_random.nextDouble() - 0.5) * 2 * jitterFactor;
    
    // Calculate final delay with jitter
    final delayMs = (cappedDelayMs * (1 + jitter)).round();
    
    return Duration(milliseconds: delayMs);
  }
  
  /// Checks if operation should be retried based on current attempt
  /// 
  /// [attempt] - Current retry attempt number (0-based)
  /// Returns true if another retry should be attempted
  bool shouldRetry(int attempt) {
    return attempt < maxAttempts;
  }
}