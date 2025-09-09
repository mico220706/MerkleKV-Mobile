import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'command.dart';
import 'response.dart';

/// UUIDv4 generator using cryptographically secure random numbers.
class UuidGenerator {
  static final Random _random = Random.secure();

  /// Generates a canonical UUIDv4 string (36 characters).
  ///
  /// Format: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
  /// where x is any hexadecimal digit and y is one of 8, 9, A, or B.
  static String generate() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));

    // Set version to 4 (UUID version 4)
    bytes[6] = (bytes[6] & 0x0f) | 0x40;

    // Set variant to 10 (RFC 4122)
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
  }

  /// Validates that a string is a canonical UUIDv4 format.
  ///
  /// Returns true if the ID is 36 characters and matches UUIDv4 pattern.
  static bool isValidUuid(String id) {
    if (id.length != 36) return false;

    final regex = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      caseSensitive: false,
    );

    return regex.hasMatch(id);
  }

  /// Validates ID length per Locked Spec (1-64 characters allowed).
  static bool isValidIdLength(String id) {
    return id.length >= 1 && id.length <= 64;
  }
}

/// Entry in the deduplication cache.
class _CacheEntry {
  final Response response;
  final DateTime expiresAt;

  const _CacheEntry(this.response, this.expiresAt);

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// Pending request awaiting response.
class _PendingRequest {
  final Command command;
  final Completer<Response> completer;
  final Stopwatch stopwatch;
  final Timer timeoutTimer;

  _PendingRequest({
    required this.command,
    required this.completer,
    required this.stopwatch,
    required this.timeoutTimer,
  });

  void dispose() {
    timeoutTimer.cancel();
  }
}

/// Structured log entry for request lifecycle.
class _LogEntry {
  final String requestId;
  final String op;
  final int sizeBytes;
  final String phase;
  final int durationMs;
  final String result;
  final int? errorCode;

  const _LogEntry({
    required this.requestId,
    required this.op,
    required this.sizeBytes,
    required this.phase,
    required this.durationMs,
    required this.result,
    this.errorCode,
  });

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'request_id': requestId,
      'op': op,
      'size_bytes': sizeBytes,
      'phase': phase,
      'duration_ms': durationMs,
      'result': result,
    };

    if (errorCode != null) {
      json['error_code'] = errorCode;
    }

    return json;
  }

  @override
  String toString() => jsonEncode(toJson());
}

/// CommandCorrelator manages request/response correlation, timeouts, and deduplication.
///
/// Features:
/// - UUIDv4 ID generation and validation
/// - Request/response correlation by ID
/// - Monotonic timeout handling with operation-specific timeouts
/// - Deduplication cache with TTL and LRU eviction
/// - Payload size validation (512 KiB limit)
/// - Structured logging of request lifecycle
/// - Async/await API over MQTT publish/subscribe
class CommandCorrelator {
  static const int _maxPayloadSizeBytes = 512 * 1024; // 512 KiB
  static const Duration _cacheTimeout = Duration(minutes: 10);
  static const int _maxCacheSize = 1000; // LRU eviction limit

  final Map<String, _PendingRequest> _pendingRequests = {};
  final Map<String, _CacheEntry> _deduplicationCache = {};
  final List<String> _cacheAccessOrder = []; // For LRU tracking

  /// Function to publish commands via MQTT
  final Future<void> Function(String jsonPayload) _publishCommand;

  /// Optional structured logging callback
  final void Function(_LogEntry entry)? _logger;

  CommandCorrelator({
    required Future<void> Function(String jsonPayload) publishCommand,
    void Function(_LogEntry entry)? logger,
  })  : _publishCommand = publishCommand,
        _logger = logger;

  /// Sends a command and returns a Future that completes with the response.
  ///
  /// Generates UUIDv4 ID if not provided, validates payload size,
  /// handles deduplication, and manages timeouts.
  Future<Response> send(Command command) async {
    final stopwatch = Stopwatch()..start();

    // Generate ID if not provided, validate if provided
    String commandId = command.id;
    if (commandId.isEmpty) {
      commandId = UuidGenerator.generate();
    } else {
      if (!UuidGenerator.isValidIdLength(commandId)) {
        throw ArgumentError('Command ID length must be 1-64 characters');
      }
      // If ID is provided and looks like UUID, validate format
      if (commandId.length == 36 && !UuidGenerator.isValidUuid(commandId)) {
        throw ArgumentError('Invalid UUIDv4 format for command ID');
      }
    }

    // Create command with validated ID
    final commandWithId = Command(
      id: commandId,
      op: command.op,
      key: command.key,
      keys: command.keys,
      value: command.value,
      keyValues: command.keyValues,
      amount: command.amount,
      params: command.params,
    );

    // Validate payload size
    final jsonPayload = commandWithId.toJsonString();
    final payloadSizeBytes = utf8.encode(jsonPayload).length;

    if (payloadSizeBytes > _maxPayloadSizeBytes) {
      final response = Response.payloadTooLarge(commandId);
      _log(_LogEntry(
        requestId: commandId,
        op: command.op,
        sizeBytes: payloadSizeBytes,
        phase: 'validation',
        durationMs: stopwatch.elapsedMilliseconds,
        result: 'error',
        errorCode: response.errorCode,
      ));
      return response;
    }

    // Check if request is already pending (after validation)
    final existingRequest = _pendingRequests[commandId];
    if (existingRequest != null) {
      return existingRequest.completer.future;
    }

    // Check deduplication cache (only if no pending request exists)
    final cachedEntry = _deduplicationCache[commandId];
    if (cachedEntry != null) {
      if (!cachedEntry.isExpired) {
        final response =
            Response.idempotentReplay(commandId, cachedEntry.response.value);
        _updateCacheAccessOrder(commandId);
        _log(_LogEntry(
          requestId: commandId,
          op: command.op,
          sizeBytes: payloadSizeBytes,
          phase: 'cache_hit',
          durationMs: stopwatch.elapsedMilliseconds,
          result: 'idempotent_replay',
          errorCode: ErrorCode.idempotentReplay,
        ));
        return response;
      } else {
        // Remove expired entry
        _removeFromCache(commandId);
      }
    }

    // Create pending request with timeout (race-safe)
    final completer = Completer<Response>();
    final timeout = commandWithId.expectedTimeout;

    final timeoutTimer = Timer(timeout, () {
      _handleTimeout(commandId, stopwatch);
    });

    final pendingRequest = _PendingRequest(
      command: commandWithId,
      completer: completer,
      stopwatch: stopwatch,
      timeoutTimer: timeoutTimer,
    );

    // Insert the pending request
    _pendingRequests[commandId] = pendingRequest;

    _log(_LogEntry(
      requestId: commandId,
      op: command.op,
      sizeBytes: payloadSizeBytes,
      phase: 'request_start',
      durationMs: stopwatch.elapsedMilliseconds,
      result: 'pending',
    ));

    try {
      // Publish command via MQTT
      await _publishCommand(jsonPayload);

      _log(_LogEntry(
        requestId: commandId,
        op: command.op,
        sizeBytes: payloadSizeBytes,
        phase: 'request_sent',
        durationMs: stopwatch.elapsedMilliseconds,
        result: 'sent',
      ));
    } catch (e) {
      // Failed to publish - clean up and return error
      pendingRequest.dispose();
      _pendingRequests.remove(commandId);

      final response =
          Response.internalError(commandId, 'Failed to publish command: $e');
      _log(_LogEntry(
        requestId: commandId,
        op: command.op,
        sizeBytes: payloadSizeBytes,
        phase: 'publish_error',
        durationMs: stopwatch.elapsedMilliseconds,
        result: 'error',
        errorCode: response.errorCode,
      ));

      return response;
    }

    return completer.future;
  }

  /// Handles incoming response from MQTT.
  ///
  /// Correlates response to pending request by ID, caches successful responses
  /// for deduplication, and completes the corresponding Future.
  void onResponse(String jsonString) {
    try {
      final response = Response.fromJsonString(jsonString);
      final requestId = response.id;

      final pendingRequest = _pendingRequests[requestId];
      if (pendingRequest != null) {
        // Complete pending request
        pendingRequest.dispose();
        _pendingRequests.remove(requestId);

        // Cache successful responses for deduplication
        if (response.isSuccess || response.isIdempotentReplay) {
          _addToCache(requestId, response);
        }

        _log(_LogEntry(
          requestId: requestId,
          op: pendingRequest.command.op,
          sizeBytes: utf8.encode(jsonString).length,
          phase: 'response_received',
          durationMs: pendingRequest.stopwatch.elapsedMilliseconds,
          result: response.isSuccess ? 'success' : 'error',
          errorCode: response.errorCode,
        ));

        pendingRequest.completer.complete(response);
      } else {
        // Late response - check if it's within dedup window and cache it
        if (response.isSuccess || response.isIdempotentReplay) {
          _addToCache(requestId, response);
        }

        _log(_LogEntry(
          requestId: requestId,
          op: 'unknown',
          sizeBytes: utf8.encode(jsonString).length,
          phase: 'late_response',
          durationMs: 0,
          result: 'ignored',
        ));
      }
    } catch (e) {
      // Malformed response - log but don't crash
      _log(_LogEntry(
        requestId: 'unknown',
        op: 'unknown',
        sizeBytes: utf8.encode(jsonString).length,
        phase: 'response_parse_error',
        durationMs: 0,
        result: 'error',
        errorCode: ErrorCode.invalidRequest,
      ));
    }
  }

  /// Handles request timeout.
  void _handleTimeout(String requestId, Stopwatch stopwatch) {
    final pendingRequest = _pendingRequests[requestId];
    if (pendingRequest != null) {
      _pendingRequests.remove(requestId);

      final response = Response.timeout(requestId);

      _log(_LogEntry(
        requestId: requestId,
        op: pendingRequest.command.op,
        sizeBytes: utf8.encode(pendingRequest.command.toJsonString()).length,
        phase: 'timeout',
        durationMs: stopwatch.elapsedMilliseconds,
        result: 'timeout',
        errorCode: ErrorCode.timeout,
      ));

      pendingRequest.completer.complete(response);
    }
  }

  /// Adds response to deduplication cache with LRU eviction.
  void _addToCache(String requestId, Response response) {
    final expiresAt = DateTime.now().add(_cacheTimeout);
    _deduplicationCache[requestId] = _CacheEntry(response, expiresAt);
    _updateCacheAccessOrder(requestId);

    // LRU eviction if cache is too large
    while (_deduplicationCache.length > _maxCacheSize) {
      final oldestKey = _cacheAccessOrder.removeAt(0);
      _deduplicationCache.remove(oldestKey);
    }

    // Clean expired entries periodically
    _cleanExpiredEntries();
  }

  /// Updates cache access order for LRU tracking.
  void _updateCacheAccessOrder(String requestId) {
    _cacheAccessOrder.remove(requestId);
    _cacheAccessOrder.add(requestId);
  }

  /// Removes entry from cache and access order.
  void _removeFromCache(String requestId) {
    _deduplicationCache.remove(requestId);
    _cacheAccessOrder.remove(requestId);
  }

  /// Removes expired cache entries.
  void _cleanExpiredEntries() {
    final expiredKeys = <String>[];

    for (final entry in _deduplicationCache.entries) {
      if (entry.value.isExpired) {
        expiredKeys.add(entry.key);
      }
    }

    for (final key in expiredKeys) {
      _removeFromCache(key);
    }
  }

  /// Logs structured entry if logger is provided.
  void _log(_LogEntry entry) {
    _logger?.call(entry);
  }

  /// Returns the number of pending requests (for testing/monitoring).
  int get pendingRequestCount => _pendingRequests.length;

  /// Returns the number of cached responses (for testing/monitoring).
  int get cacheSize => _deduplicationCache.length;

  /// Cancels all pending requests and clears cache.
  void dispose() {
    for (final request in _pendingRequests.values) {
      request.dispose();
      request.completer.complete(Response.internalError(
        request.command.id,
        'CommandCorrelator disposed',
      ));
    }

    _pendingRequests.clear();
    _deduplicationCache.clear();
    _cacheAccessOrder.clear();
  }
}
