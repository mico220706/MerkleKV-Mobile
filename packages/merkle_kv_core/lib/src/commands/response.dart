import 'dart:convert';
import '../models/key_value_result.dart';

/// Error codes for MerkleKV responses per Locked Spec §3.2.
class ErrorCode {
  static const int invalidRequest = 100;
  static const int timeout = 101;
  static const int notFound = 102;
  static const int payloadTooLarge = 103;
  static const int rangeOverflow = 104;
  static const int invalidType = 105;
  static const int idempotentReplay =
      110; // Special case for idempotent operations
  static const int internalError = 199;

  /// Returns human-readable description of error code.
  static String describe(int code) {
    switch (code) {
      case invalidRequest:
        return 'Invalid request format or parameters';
      case timeout:
        return 'Request timeout';
      case notFound:
        return 'Key not found';
      case payloadTooLarge:
        return 'Payload exceeds maximum size limit';
      case rangeOverflow:
        return 'Numeric operation resulted in overflow';
      case invalidType:
        return 'Value is not a valid integer for numeric operation';
      case idempotentReplay:
        return 'Idempotent replay of cached response';
      case internalError:
        return 'Internal server error';
      default:
        return 'Unknown error code: $code';
    }
  }
}

/// Response status enumeration.
enum ResponseStatus {
  ok('OK'),
  error('ERROR');

  const ResponseStatus(this.value);

  final String value;

  static ResponseStatus fromString(String value) {
    switch (value.toUpperCase()) {
      case 'OK':
        return ResponseStatus.ok;
      case 'ERROR':
        return ResponseStatus.error;
      default:
        throw FormatException('Invalid response status: $value');
    }
  }
}

/// Represents a response from MerkleKV operations.
///
/// Responses follow the Locked Spec §3.2 format with required fields:
/// - id: Original request ID for correlation
/// - status: Operation result (OK or ERROR)
/// - value: Result value (for successful operations)
/// - error: Error message (for failed operations)
/// - errorCode: Numeric error code (for failed operations)
class Response {
  /// Original request ID for correlation
  final String id;

  /// Operation result status
  final ResponseStatus status;

  /// Result value for successful operations
  final dynamic value;

  /// Error message for failed operations
  final String? error;

  /// Numeric error code for failed operations
  final int? errorCode;

  /// Additional response metadata
  final Map<String, dynamic>? metadata;

  /// Results for bulk operations (MGET/MSET)  
  final List<KeyValueResult>? results;

  const Response({
    required this.id,
    required this.status,
    this.value,
    this.error,
    this.errorCode,
    this.metadata,
    this.results,
  });

  /// Creates a successful response.
  factory Response.ok({
    required String id,
    dynamic value,
    Map<String, dynamic>? metadata,
  }) {
    return Response(
      id: id,
      status: ResponseStatus.ok,
      value: value,
      metadata: metadata,
    );
  }

  /// Creates an error response.
  factory Response.error({
    required String id,
    required String error,
    required int errorCode,
    Map<String, dynamic>? metadata,
  }) {
    return Response(
      id: id,
      status: ResponseStatus.error,
      error: error,
      errorCode: errorCode,
      metadata: metadata,
    );
  }

  /// Creates a timeout error response.
  factory Response.timeout(String id) {
    return Response.error(
      id: id,
      error: ErrorCode.describe(ErrorCode.timeout),
      errorCode: ErrorCode.timeout,
    );
  }

  /// Creates an invalid request error response.
  factory Response.invalidRequest(String id, String message) {
    return Response.error(
      id: id,
      error: message,
      errorCode: ErrorCode.invalidRequest,
    );
  }

  /// Creates a payload too large error response.
  factory Response.payloadTooLarge(String id) {
    return Response.error(
      id: id,
      error: ErrorCode.describe(ErrorCode.payloadTooLarge),
      errorCode: ErrorCode.payloadTooLarge,
    );
  }

  /// Creates a not found error response.
  factory Response.notFound(String id) {
    return Response.error(
      id: id,
      error: ErrorCode.describe(ErrorCode.notFound),
      errorCode: ErrorCode.notFound,
    );
  }

  /// Creates a range overflow error response.
  factory Response.rangeOverflow(String id, String message) {
    return Response.error(
      id: id,
      error: message,
      errorCode: ErrorCode.rangeOverflow,
    );
  }

  /// Creates an invalid type error response.
  factory Response.invalidType(String id, String message) {
    return Response.error(
      id: id,
      error: message,
      errorCode: ErrorCode.invalidType,
    );
  }

  /// Creates a bulk operation response. 
  factory Response.bulk({
    required String id,
    required List<KeyValueResult> results,
    Map<String, dynamic>? metadata,
  }) {
    return Response(
      id: id,
      status: ResponseStatus.ok,
      results: results,
      metadata: metadata,
    );
  }

  /// Returns true if this response is a bulk operation response. 
  bool get isBulkResponse => results != null;

  /// Creates an idempotent replay response.
  factory Response.idempotentReplay(String id, dynamic value) {
    return Response(
      id: id,
      status: ResponseStatus.ok,
      value: value,
      errorCode: ErrorCode.idempotentReplay,
    );
  }

  /// Creates an internal error response.
  factory Response.internalError(String id, String message) {
    return Response.error(
      id: id,
      error: message,
      errorCode: ErrorCode.internalError,
    );
  }

  /// Creates a Response from JSON object.
  ///
  /// Validates required fields and throws [FormatException] for invalid format.
  factory Response.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final status = json['status'];

    if (id == null || id is! String) {
      throw const FormatException('Missing or invalid "id" field');
    }

    if (status == null || status is! String) {
      throw const FormatException('Missing or invalid "status" field');
    }

    final responseStatus = ResponseStatus.fromString(status);

    // ADD THIS: Handle bulk results
    List<KeyValueResult>? results;
    if (json['results'] != null) {
      results = (json['results'] as List)
          .map((r) => KeyValueResult.fromJson(r as Map<String, dynamic>))
          .toList();
    }

    return Response(
      id: id,
      status: responseStatus,
      value: json['value'],
      error: json['error'] as String?,
      errorCode: json['errorCode'] as int?,
      metadata: (json['metadata'] as Map?)?.cast<String, dynamic>(),
      results: results,  // ADD THIS
    );
  }

/// Converts Response to JSON object for serialization.
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'id': id,
      'status': status.value,
    };

    if (value != null) json['value'] = value;
    if (error != null) json['error'] = error;
    if (errorCode != null) json['errorCode'] = errorCode;
    if (metadata != null) json['metadata'] = metadata;
    // ADD THIS: Include bulk results
    if (results != null) {
      json['results'] = results!.map((r) => r.toJson()).toList();
    }

    return json;
  }

  /// Serializes Response to JSON string.
  String toJsonString() => jsonEncode(toJson());

  /// Creates Response from JSON string.
  ///
  /// Throws [FormatException] for malformed JSON or invalid structure.
  factory Response.fromJsonString(String jsonString) {
    try {
      final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
      return Response.fromJson(decoded);
    } catch (e) {
      throw FormatException('Invalid JSON format: $e');
    }
  }

  /// Returns true if this response indicates success.
  bool get isSuccess =>
      status == ResponseStatus.ok && errorCode != ErrorCode.idempotentReplay;

  /// Returns true if this response indicates an error.
  bool get isError => status == ResponseStatus.error;

  /// Returns true if this response is from an idempotent replay.
  bool get isIdempotentReplay => errorCode == ErrorCode.idempotentReplay;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Response &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          status == other.status &&
          value == other.value &&
          error == other.error &&
          errorCode == other.errorCode &&
          _mapEquals(metadata, other.metadata) &&
          _listEquals(results, other.results);  

  @override
  int get hashCode =>
      id.hashCode ^
      status.hashCode ^
      value.hashCode ^
      error.hashCode ^
      errorCode.hashCode ^
      _mapHashCode(metadata) ^
      _listHashCode(results);  

  // Helper method for list equality
  bool _listEquals(List? a, List? b) {
    if (a == null) return b == null;
    if (b == null || a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // Helper method for list hash code
  int _listHashCode(List? list) {
    if (list == null) return 0;
    int hash = 0;
    for (final item in list) {
      hash ^= item.hashCode;
    }
    return hash;
  }

  @override
  String toString() =>
      'Response(id: $id, status: ${status.value}, error: $error)';

  // Helper methods for equality comparison
  bool _mapEquals(Map? a, Map? b) {
    if (a == null) return b == null;
    if (b == null || a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || a[key] != b[key]) return false;
    }
    return true;
  }

  int _mapHashCode(Map? map) {
    if (map == null) return 0;
    int hash = 0;
    for (final entry in map.entries) {
      hash ^= entry.key.hashCode ^ entry.value.hashCode;
    }
    return hash;
  }
}
