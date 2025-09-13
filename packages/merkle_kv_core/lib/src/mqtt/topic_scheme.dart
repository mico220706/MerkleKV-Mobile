import '../config/invalid_config_exception.dart';
import 'topic_validator.dart';

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
  /// slashes. Validates both prefix and clientId according to enhanced multi-tenant
  /// isolation requirements with UTF-8 byte length validation.
  ///
  /// Throws [InvalidConfigException] if validation fails.
  static TopicScheme create(String rawPrefix, String rawClientId) {
    // Normalize prefix using enhanced validation
    final normalizedPrefix = TopicValidator.normalizePrefix(rawPrefix);

    // Validate prefix using enhanced multi-tenant validation
    try {
      TopicValidator.validatePrefix(normalizedPrefix);
    } catch (e) {
      throw InvalidConfigException(
        'Topic prefix validation failed: ${e.toString().replaceFirst('ArgumentError: ', '')}',
        'prefix',
      );
    }

    // Validate clientId using enhanced validation
    try {
      TopicValidator.validateClientId(rawClientId);
    } catch (e) {
      throw InvalidConfigException(
        'Client ID validation failed: ${e.toString().replaceFirst('ArgumentError: ', '')}',
        'clientId',
      );
    }

    return TopicScheme._(prefix: normalizedPrefix, clientId: rawClientId);
  }

  /// Validates clientId according to enhanced multi-tenant requirements.
  ///
  /// This method is maintained for backward compatibility and delegates
  /// to TopicValidator.validateClientId() for consistent validation.
  static void validateClientId(String clientId) {
    try {
      TopicValidator.validateClientId(clientId);
    } catch (e) {
      throw InvalidConfigException(
        'Client ID validation failed: ${e.toString().replaceFirst('ArgumentError: ', '')}',
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
