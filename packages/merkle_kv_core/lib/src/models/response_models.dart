/// Response models for MerkleKV operations
library response_models;

/// Status enumeration for operation responses
enum OperationStatus { ok, notFound, error, timeout }

/// Response from a key-value operation
class OperationResponse {
  /// Request ID that corresponds to this response
  final String id;

  /// Operation status
  final OperationStatus status;

  /// Value returned by the operation (for GET, INCR, DECR, etc.)
  final String? value;

  /// Multiple values returned (for MGET operations)
  final Map<String, String?>? values;

  /// Error message if status is error
  final String? error;

  /// Timestamp when the response was generated
  final DateTime timestamp;

  /// Operation that was performed
  final String? operation;

  /// Key that was operated on
  final String? key;

  const OperationResponse({
    required this.id,
    required this.status,
    this.value,
    this.values,
    this.error,
    required this.timestamp,
    this.operation,
    this.key,
  });

  /// Create a successful response
  factory OperationResponse.success({
    required String id,
    String? value,
    Map<String, String?>? values,
    String? operation,
    String? key,
  }) {
    return OperationResponse(
      id: id,
      status: OperationStatus.ok,
      value: value,
      values: values,
      timestamp: DateTime.now().toUtc(),
      operation: operation,
      key: key,
    );
  }

  /// Create a not found response
  factory OperationResponse.notFound({
    required String id,
    String? key,
    String? operation,
  }) {
    return OperationResponse(
      id: id,
      status: OperationStatus.notFound,
      timestamp: DateTime.now().toUtc(),
      operation: operation,
      key: key,
    );
  }

  /// Create an error response
  factory OperationResponse.error({
    required String id,
    required String error,
    String? operation,
    String? key,
  }) {
    return OperationResponse(
      id: id,
      status: OperationStatus.error,
      error: error,
      timestamp: DateTime.now().toUtc(),
      operation: operation,
      key: key,
    );
  }

  /// Create a timeout response
  factory OperationResponse.timeout({
    required String id,
    String? operation,
    String? key,
  }) {
    return OperationResponse(
      id: id,
      status: OperationStatus.timeout,
      error: 'Operation timed out',
      timestamp: DateTime.now().toUtc(),
      operation: operation,
      key: key,
    );
  }

  /// Create from JSON map
  factory OperationResponse.fromJson(Map<String, dynamic> json) {
    final statusString = json['status'] as String;
    final status = OperationStatus.values.firstWhere(
      (s) => s.name.toUpperCase() == statusString.toUpperCase(),
      orElse: () => OperationStatus.error,
    );

    return OperationResponse(
      id: json['id'] as String,
      status: status,
      value: json['value'] as String?,
      values: json['values'] != null
          ? Map<String, String?>.from(json['values'] as Map)
          : null,
      error: json['error'] as String?,
      timestamp: json['timestamp'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              json['timestamp'] as int,
              isUtc: true,
            )
          : DateTime.now().toUtc(),
      operation: json['operation'] as String?,
      key: json['key'] as String?,
    );
  }

  /// Convert to JSON map
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'status': status.name.toUpperCase(),
      if (value != null) 'value': value,
      if (values != null) 'values': values,
      if (error != null) 'error': error,
      'timestamp': timestamp.millisecondsSinceEpoch,
      if (operation != null) 'operation': operation,
      if (key != null) 'key': key,
    };
  }

  /// Check if the operation was successful
  bool get isSuccess => status == OperationStatus.ok;

  /// Check if the operation failed
  bool get isError =>
      status == OperationStatus.error || status == OperationStatus.timeout;

  /// Check if the key was not found
  bool get isNotFound => status == OperationStatus.notFound;

  /// Check if the operation timed out
  bool get isTimeout => status == OperationStatus.timeout;

  @override
  String toString() {
    final buffer = StringBuffer('OperationResponse{');
    buffer.write('id: $id, ');
    buffer.write('status: ${status.name}, ');
    if (value != null) buffer.write('value: $value, ');
    if (values != null) buffer.write('values: $values, ');
    if (error != null) buffer.write('error: $error, ');
    buffer.write('timestamp: $timestamp');
    if (operation != null) buffer.write(', operation: $operation');
    if (key != null) buffer.write(', key: $key');
    buffer.write('}');
    return buffer.toString();
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! OperationResponse) return false;

    return id == other.id &&
        status == other.status &&
        value == other.value &&
        _mapEquals(values, other.values) &&
        error == other.error &&
        timestamp == other.timestamp &&
        operation == other.operation &&
        key == other.key;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      status,
      value,
      values,
      error,
      timestamp,
      operation,
      key,
    );
  }

  static bool _mapEquals(Map<String, String?>? a, Map<String, String?>? b) {
    if (a == null) return b == null;
    if (b == null) return false;
    if (a.length != b.length) return false;

    for (final key in a.keys) {
      if (!b.containsKey(key) || a[key] != b[key]) return false;
    }

    return true;
  }
}

/// Batch operation response for multiple operations
class BatchOperationResponse {
  /// Request ID that corresponds to this response
  final String id;

  /// Individual operation responses
  final List<OperationResponse> responses;

  /// Overall status of the batch operation
  final OperationStatus status;

  /// Error message if the entire batch failed
  final String? error;

  /// Timestamp when the batch response was generated
  final DateTime timestamp;

  const BatchOperationResponse({
    required this.id,
    required this.responses,
    required this.status,
    this.error,
    required this.timestamp,
  });

  /// Create a successful batch response
  factory BatchOperationResponse.success({
    required String id,
    required List<OperationResponse> responses,
  }) {
    return BatchOperationResponse(
      id: id,
      responses: responses,
      status: OperationStatus.ok,
      timestamp: DateTime.now().toUtc(),
    );
  }

  /// Create an error batch response
  factory BatchOperationResponse.error({
    required String id,
    required String error,
    List<OperationResponse>? responses,
  }) {
    return BatchOperationResponse(
      id: id,
      responses: responses ?? [],
      status: OperationStatus.error,
      error: error,
      timestamp: DateTime.now().toUtc(),
    );
  }

  /// Create from JSON map
  factory BatchOperationResponse.fromJson(Map<String, dynamic> json) {
    final statusString = json['status'] as String;
    final status = OperationStatus.values.firstWhere(
      (s) => s.name.toUpperCase() == statusString.toUpperCase(),
      orElse: () => OperationStatus.error,
    );

    final responseList = json['responses'] as List<dynamic>? ?? [];
    final responses = responseList
        .map((r) => OperationResponse.fromJson(r as Map<String, dynamic>))
        .toList();

    return BatchOperationResponse(
      id: json['id'] as String,
      responses: responses,
      status: status,
      error: json['error'] as String?,
      timestamp: json['timestamp'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              json['timestamp'] as int,
              isUtc: true,
            )
          : DateTime.now().toUtc(),
    );
  }

  /// Convert to JSON map
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'responses': responses.map((r) => r.toJson()).toList(),
      'status': status.name.toUpperCase(),
      if (error != null) 'error': error,
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
  }

  /// Check if all operations were successful
  bool get isSuccess =>
      status == OperationStatus.ok && responses.every((r) => r.isSuccess);

  /// Check if any operation failed
  bool get hasErrors =>
      status == OperationStatus.error || responses.any((r) => r.isError);

  /// Get the number of successful operations
  int get successCount => responses.where((r) => r.isSuccess).length;

  /// Get the number of failed operations
  int get errorCount => responses.where((r) => r.isError).length;

  @override
  String toString() {
    return 'BatchOperationResponse{'
        'id: $id, '
        'status: ${status.name}, '
        'responses: ${responses.length}, '
        'success: $successCount, '
        'errors: $errorCount'
        '}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! BatchOperationResponse) return false;

    return id == other.id &&
        _listEquals(responses, other.responses) &&
        status == other.status &&
        error == other.error &&
        timestamp == other.timestamp;
  }

  @override
  int get hashCode {
    return Object.hash(id, Object.hashAll(responses), status, error, timestamp);
  }

  static bool _listEquals(
    List<OperationResponse> a,
    List<OperationResponse> b,
  ) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
