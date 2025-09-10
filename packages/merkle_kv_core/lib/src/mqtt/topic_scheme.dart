import '../config/invalid_config_exception.dart';

/// Canonical topic scheme per Locked Spec §2.
///
/// Provides standardized topic generation for commands, responses, and
/// replication with strict validation and normalization.
class TopicScheme {
  /// Normalized topic prefix (no leading/trailing '/', no '+' '#').
  final String prefix;

  /// Client identifier (1..128 chars; disallow '/', '+', '#').
  final String clientId;

  /// Creates a TopicScheme with validated and normalized values.
  const TopicScheme._({required this.prefix, required this.clientId});

  /// Command topic for this client: `{prefix}/{clientId}/cmd`
  String get commandTopic => '$prefix/$clientId/cmd';

  /// Response topic for this client: `{prefix}/{clientId}/res`
  String get responseTopic => '$prefix/$clientId/res';

  /// Replication topic for all devices: `{prefix}/replication/events`
  String get replicationTopic => '$prefix/replication/events';

  /// Creates a TopicScheme with normalization and validation.
  ///
  /// Normalizes [rawPrefix] by trimming whitespace and removing leading/trailing
  /// slashes. Validates both prefix and clientId according to MQTT topic rules.
  ///
  /// Throws [InvalidConfigException] if validation fails.
  static TopicScheme create(String rawPrefix, String rawClientId) {
    // Normalize prefix
    final normalizedPrefix = _normalizePrefix(rawPrefix);

    // Validate prefix
    _validatePrefix(normalizedPrefix);

    // Validate clientId
    validateClientId(rawClientId);

    return TopicScheme._(prefix: normalizedPrefix, clientId: rawClientId);
  }

  /// Normalizes prefix by trimming and removing leading/trailing slashes.
  static String _normalizePrefix(String rawPrefix) {
    String normalized = rawPrefix.trim();

    // Remove leading slashes
    while (normalized.startsWith('/')) {
      normalized = normalized.substring(1);
    }

    // Remove trailing slashes
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }

    // Return default if empty after normalization
    if (normalized.isEmpty) {
      return 'mkv';
    }

    return normalized;
  }

  /// Validates prefix according to MQTT topic rules.
  static void _validatePrefix(String prefix) {
    if (prefix.isEmpty) {
      throw const InvalidConfigException(
        'Topic prefix cannot be empty after normalization',
        'prefix',
      );
    }

    // Check length (approximately 100 bytes)
    if (prefix.length > 100) {
      throw const InvalidConfigException(
        'Topic prefix cannot exceed 100 characters',
        'prefix',
      );
    }

    // Check for invalid characters
    if (prefix.contains('+')) {
      throw const InvalidConfigException(
        'Topic prefix cannot contain wildcard character \'+\'',
        'prefix',
      );
    }

    if (prefix.contains('#')) {
      throw const InvalidConfigException(
        'Topic prefix cannot contain wildcard character \'#\'',
        'prefix',
      );
    }

    // Check allowed charset: [A-Za-z0-9_/-]
    final allowedPattern = RegExp(r'^[A-Za-z0-9_/-]+$');
    if (!allowedPattern.hasMatch(prefix)) {
      throw const InvalidConfigException(
        'Topic prefix contains invalid characters. Only [A-Za-z0-9_/-] are allowed',
        'prefix',
      );
    }
  }

  /// Validates clientId according to MQTT client identifier rules.
  static void validateClientId(String clientId) {
    if (clientId.isEmpty) {
      throw const InvalidConfigException(
        'Client ID cannot be empty',
        'clientId',
      );
    }

    if (clientId.length > 128) {
      throw const InvalidConfigException(
        'Client ID cannot exceed 128 characters',
        'clientId',
      );
    }

    // Check for invalid characters
    if (clientId.contains('/')) {
      throw const InvalidConfigException(
        'Client ID cannot contain \'/\' character',
        'clientId',
      );
    }

    if (clientId.contains('+')) {
      throw const InvalidConfigException(
        'Client ID cannot contain wildcard character \'+\'',
        'clientId',
      );
    }

    if (clientId.contains('#')) {
      throw const InvalidConfigException(
        'Client ID cannot contain wildcard character \'#\'',
        'clientId',
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TopicScheme &&
          runtimeType == other.runtimeType &&
          prefix == other.prefix &&
          clientId == other.clientId;

  @override
  int get hashCode => prefix.hashCode ^ clientId.hashCode;

  @override
  String toString() => 'TopicScheme(prefix: $prefix, clientId: $clientId)';
}
