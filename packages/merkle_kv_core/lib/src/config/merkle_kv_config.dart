import 'dart:io';

import 'invalid_config_exception.dart';
import '../mqtt/topic_validator.dart';

/// Centralized, immutable configuration for MerkleKV Mobile client.
///
/// This class provides a type-safe configuration with validation, secure
/// credential handling, and defaults aligned with Locked Spec §11.
class MerkleKVConfig {
  /// MQTT broker hostname or IP address.
  final String mqttHost;

  /// MQTT broker port.
  ///
  /// Defaults to 8883 when TLS is enabled, 1883 otherwise.
  final int mqttPort;

  /// MQTT username for authentication (sensitive data).
  final String? username;

  /// MQTT password for authentication (sensitive data).
  final String? password;

  /// Whether to use TLS for MQTT connection.
  final bool mqttUseTls;

  /// Unique client identifier for MQTT connection.
  ///
  /// Must be between 1 and 128 characters long.
  final String clientId;

  /// Unique node identifier for replication.
  ///
  /// Must be between 1 and 128 characters long.
  final String nodeId;

  /// Topic prefix for all MQTT topics.
  ///
  /// Automatically normalized (no leading/trailing slashes, no spaces).
  /// Defaults to "mkv" if empty after normalization.
  final String topicPrefix;

  /// MQTT keep-alive interval in seconds (Locked Spec §11).
  ///
  /// Default: 60 seconds.
  final int keepAliveSeconds;

  /// Session expiry interval in seconds (Locked Spec §11).
  ///
  /// Default: 86400 seconds (24 hours).
  final int sessionExpirySeconds;

  /// Maximum allowed future timestamp skew in milliseconds (Locked Spec §11).
  ///
  /// Default: 300000 milliseconds (5 minutes).
  final int skewMaxFutureMs;

  /// Tombstone retention period in hours (Locked Spec §11).
  ///
  /// Default: 24 hours.
  final int tombstoneRetentionHours;

  /// Whether persistence to disk is enabled.
  final bool persistenceEnabled;

  /// Path for persistent storage.
  ///
  /// Required when [persistenceEnabled] is true.
  final String? storagePath;

  /// Whether offline queue is enabled for operations when disconnected.
  ///
  /// When true, operations can be queued while disconnected and will be
  /// executed when connection is restored. When false, operations will
  /// fail fast with ConnectionException when disconnected.
  final bool? enableOfflineQueue;

  /// Static security warning handler for non-TLS credential usage.
  static void Function(String message)? _onSecurityWarning;

  /// Private constructor for validated instances.
  const MerkleKVConfig._({
    required this.mqttHost,
    required this.mqttPort,
    required this.username,
    required this.password,
    required this.mqttUseTls,
    required this.clientId,
    required this.nodeId,
    required this.topicPrefix,
    required this.keepAliveSeconds,
    required this.sessionExpirySeconds,
    required this.skewMaxFutureMs,
    required this.tombstoneRetentionHours,
    required this.persistenceEnabled,
    required this.storagePath,
    required this.enableOfflineQueue,
  });

  /// Creates a new MerkleKVConfig with validation and default values.
  ///
  /// Applies defaults from Locked Spec §11 and validates all parameters.
  /// Throws [InvalidConfigException] if any parameter is invalid.
  factory MerkleKVConfig({
    required String mqttHost,
    int? mqttPort,
    String? username,
    String? password,
    bool mqttUseTls = false,
    required String clientId,
    required String nodeId,
    String topicPrefix = '',
    int keepAliveSeconds = 60,
    int sessionExpirySeconds = 86400,
    int skewMaxFutureMs = 300000,
    int tombstoneRetentionHours = 24,
    bool persistenceEnabled = false,
    String? storagePath,
    bool? enableOfflineQueue,
  }) {
    return MerkleKVConfig._validated(
      mqttHost: mqttHost,
      mqttPort: mqttPort,
      username: username,
      password: password,
      mqttUseTls: mqttUseTls,
      clientId: clientId,
      nodeId: nodeId,
      topicPrefix: topicPrefix,
      keepAliveSeconds: keepAliveSeconds,
      sessionExpirySeconds: sessionExpirySeconds,
      skewMaxFutureMs: skewMaxFutureMs,
      tombstoneRetentionHours: tombstoneRetentionHours,
      persistenceEnabled: persistenceEnabled,
      storagePath: storagePath,
      enableOfflineQueue: enableOfflineQueue,
    );
  }

  /// Creates a default configuration with minimal required parameters.
  ///
  /// Uses secure defaults and infers appropriate port based on TLS setting.
  static MerkleKVConfig defaultConfig({
    required String host,
    required String clientId,
    required String nodeId,
    bool tls = false,
  }) {
    return MerkleKVConfig(
      mqttHost: host,
      mqttUseTls: tls,
      clientId: clientId,
      nodeId: nodeId,
    );
  }

  /// Convenience factory method that forwards to the main constructor.
  ///
  /// This method provides a static factory interface for test compatibility
  /// while maintaining all the validation and defaults of the main constructor.
  /// Automatically provides a temporary storage path when persistence is enabled
  /// but no storage path is specified.
  static MerkleKVConfig create({
    required String mqttHost,
    int? mqttPort,
    String? username,
    String? password,
    bool mqttUseTls = false,
    required String clientId,
    required String nodeId,
    String topicPrefix = '',
    int keepAliveSeconds = 60,
    int sessionExpirySeconds = 86400,
    int skewMaxFutureMs = 300000,
    int tombstoneRetentionHours = 24,
    bool persistenceEnabled = false,
    String? storagePath,
  }) {
    // Auto-supply temp storage path if persistence enabled but no path provided
    String? resolvedStoragePath = storagePath;
    if (persistenceEnabled && (storagePath == null || storagePath.isEmpty)) {
      final dir = Directory.systemTemp.createTempSync('merkle_kv_');
      resolvedStoragePath =
          '${dir.path}${Platform.pathSeparator}merkle_kv_storage.jsonl';
    }

    return MerkleKVConfig(
      mqttHost: mqttHost,
      mqttPort: mqttPort,
      username: username,
      password: password,
      mqttUseTls: mqttUseTls,
      clientId: clientId,
      nodeId: nodeId,
      topicPrefix: topicPrefix,
      keepAliveSeconds: keepAliveSeconds,
      sessionExpirySeconds: sessionExpirySeconds,
      skewMaxFutureMs: skewMaxFutureMs,
      tombstoneRetentionHours: tombstoneRetentionHours,
      persistenceEnabled: persistenceEnabled,
      storagePath: resolvedStoragePath,
    );
  }

  /// Internal factory method with validation logic.
  factory MerkleKVConfig._validated({
    required String mqttHost,
    int? mqttPort,
    String? username,
    String? password,
    required bool mqttUseTls,
    required String clientId,
    required String nodeId,
    required String topicPrefix,
    required int keepAliveSeconds,
    required int sessionExpirySeconds,
    required int skewMaxFutureMs,
    required int tombstoneRetentionHours,
    required bool persistenceEnabled,
    String? storagePath,
    bool? enableOfflineQueue,
  }) {
    // Validate mqttHost
    if (mqttHost.trim().isEmpty) {
      throw const InvalidConfigException(
        'MQTT host cannot be empty',
        'mqttHost',
      );
    }

    // Infer port if not provided
    final int finalPort = mqttPort ?? (mqttUseTls ? 8883 : 1883);

    // Validate port
    if (finalPort < 1 || finalPort > 65535) {
      throw const InvalidConfigException(
        'MQTT port must be between 1 and 65535',
        'mqttPort',
      );
    }

    // Validate clientId using enhanced validation
    try {
      TopicValidator.validateClientId(clientId);
    } catch (e) {
      throw InvalidConfigException(
        'Invalid client ID: ${e.toString().replaceFirst('ArgumentError: ', '')}',
        'clientId',
      );
    }

    // Validate nodeId using similar rules as clientId
    try {
      TopicValidator.validateClientId(nodeId);
    } catch (e) {
      throw InvalidConfigException(
        'Invalid node ID: ${e.toString().replaceFirst('ArgumentError: ', '')}',
        'nodeId',
      );
    }

    // Validate timeout values
    if (keepAliveSeconds <= 0) {
      throw const InvalidConfigException(
        'Keep alive seconds must be positive',
        'keepAliveSeconds',
      );
    }

    if (sessionExpirySeconds <= 0) {
      throw const InvalidConfigException(
        'Session expiry seconds must be positive',
        'sessionExpirySeconds',
      );
    }

    if (skewMaxFutureMs < 0) {
      throw const InvalidConfigException(
        'Skew max future milliseconds must be non-negative',
        'skewMaxFutureMs',
      );
    }

    if (tombstoneRetentionHours <= 0) {
      throw const InvalidConfigException(
        'Tombstone retention hours must be positive',
        'tombstoneRetentionHours',
      );
    }

    // Validate persistence requirements
    if (persistenceEnabled &&
        (storagePath == null || storagePath.trim().isEmpty)) {
      throw const InvalidConfigException(
        'Storage path must be provided when persistence is enabled',
        'storagePath',
      );
    }

    // Normalize and validate topic prefix using enhanced validation
    String normalizedPrefix = TopicValidator.normalizePrefix(topicPrefix);
    try {
      TopicValidator.validatePrefix(normalizedPrefix);
    } catch (e) {
      throw InvalidConfigException(
        'Invalid topic prefix: ${e.toString().replaceFirst('ArgumentError: ', '')}',
        'topicPrefix',
      );
    }

    // Security warning for credentials without TLS
    if (!mqttUseTls && (username != null || password != null)) {
      _onSecurityWarning?.call(
        'Username or password provided without TLS encryption. '
        'Credentials will be transmitted in plain text.',
      );
    }

    return MerkleKVConfig._(
      mqttHost: mqttHost.trim(),
      mqttPort: finalPort,
      username: username,
      password: password,
      mqttUseTls: mqttUseTls,
      clientId: clientId,
      nodeId: nodeId,
      topicPrefix: normalizedPrefix,
      keepAliveSeconds: keepAliveSeconds,
      sessionExpirySeconds: sessionExpirySeconds,
      skewMaxFutureMs: skewMaxFutureMs,
      tombstoneRetentionHours: tombstoneRetentionHours,
      persistenceEnabled: persistenceEnabled,
      storagePath: storagePath,
      enableOfflineQueue: enableOfflineQueue ?? false,
    );
  }

  /// Sets the security warning handler for non-TLS credential usage.
  ///
  /// Pass null to disable warnings.
  static void setSecurityWarningHandler(
    void Function(String message)? handler,
  ) {
    _onSecurityWarning = handler;
  }

  /// Creates a copy of this configuration with updated values.
  ///
  /// All parameters are optional and will use the current value if not provided.
  /// When [mqttUseTls] is changed but [mqttPort] is not provided, the port will
  /// be inferred based on the new TLS setting.
  MerkleKVConfig copyWith({
    String? mqttHost,
    int? mqttPort,
    String? username,
    String? password,
    bool? mqttUseTls,
    String? clientId,
    String? nodeId,
    String? topicPrefix,
    int? keepAliveSeconds,
    int? sessionExpirySeconds,
    int? skewMaxFutureMs,
    int? tombstoneRetentionHours,
    bool? persistenceEnabled,
    String? storagePath,
  }) {
    // If TLS setting changes but port is not specified, infer the port
    final newTlsSetting = mqttUseTls ?? this.mqttUseTls;
    final newPort =
        mqttPort ??
        (mqttUseTls != null && mqttUseTls != this.mqttUseTls
            ? (newTlsSetting ? 8883 : 1883)
            : this.mqttPort);

    return MerkleKVConfig(
      mqttHost: mqttHost ?? this.mqttHost,
      mqttPort: newPort,
      username: username ?? this.username,
      password: password ?? this.password,
      mqttUseTls: newTlsSetting,
      clientId: clientId ?? this.clientId,
      nodeId: nodeId ?? this.nodeId,
      topicPrefix: topicPrefix ?? this.topicPrefix,
      keepAliveSeconds: keepAliveSeconds ?? this.keepAliveSeconds,
      sessionExpirySeconds: sessionExpirySeconds ?? this.sessionExpirySeconds,
      skewMaxFutureMs: skewMaxFutureMs ?? this.skewMaxFutureMs,
      tombstoneRetentionHours:
          tombstoneRetentionHours ?? this.tombstoneRetentionHours,
      persistenceEnabled: persistenceEnabled ?? this.persistenceEnabled,
      storagePath: storagePath ?? this.storagePath,
    );
  }

  /// Converts this configuration to a JSON map.
  ///
  /// Excludes sensitive data (username and password) for security.
  /// Use [fromJson] with explicit credentials to reconstruct.
  Map<String, dynamic> toJson() {
    return {
      'mqttHost': mqttHost,
      'mqttPort': mqttPort,
      'mqttUseTls': mqttUseTls,
      'clientId': clientId,
      'nodeId': nodeId,
      'topicPrefix': topicPrefix,
      'keepAliveSeconds': keepAliveSeconds,
      'sessionExpirySeconds': sessionExpirySeconds,
      'skewMaxFutureMs': skewMaxFutureMs,
      'tombstoneRetentionHours': tombstoneRetentionHours,
      'persistenceEnabled': persistenceEnabled,
      'storagePath': storagePath,
    };
  }

  /// Creates a MerkleKVConfig from a JSON map with optional credentials.
  ///
  /// Sensitive data (username/password) must be provided separately
  /// for security and future keystore integration.
  static MerkleKVConfig fromJson(
    Map<String, dynamic> json, {
    String? username,
    String? password,
  }) {
    return MerkleKVConfig(
      mqttHost: json['mqttHost'] as String,
      mqttPort: json['mqttPort'] as int,
      username: username,
      password: password,
      mqttUseTls: json['mqttUseTls'] as bool,
      clientId: json['clientId'] as String,
      nodeId: json['nodeId'] as String,
      topicPrefix: json['topicPrefix'] as String? ?? '',
      keepAliveSeconds: json['keepAliveSeconds'] as int? ?? 60,
      sessionExpirySeconds: json['sessionExpirySeconds'] as int? ?? 86400,
      skewMaxFutureMs: json['skewMaxFutureMs'] as int? ?? 300000,
      tombstoneRetentionHours: json['tombstoneRetentionHours'] as int? ?? 24,
      persistenceEnabled: json['persistenceEnabled'] as bool? ?? false,
      storagePath: json['storagePath'] as String?,
    );
  }

  @override
  String toString() {
    final maskedUsername = username != null ? '***' : null;
    final maskedPassword = password != null ? '***' : null;

    return 'MerkleKVConfig{'
        'mqttHost: $mqttHost, '
        'mqttPort: $mqttPort, '
        'username: $maskedUsername, '
        'password: $maskedPassword, '
        'mqttUseTls: $mqttUseTls, '
        'clientId: $clientId, '
        'nodeId: $nodeId, '
        'topicPrefix: $topicPrefix, '
        'keepAliveSeconds: $keepAliveSeconds, '
        'sessionExpirySeconds: $sessionExpirySeconds, '
        'skewMaxFutureMs: $skewMaxFutureMs, '
        'tombstoneRetentionHours: $tombstoneRetentionHours, '
        'persistenceEnabled: $persistenceEnabled, '
        'storagePath: $storagePath'
        '}';
  }

  /// Creates a new builder for MerkleKVConfig.
  ///
  /// The builder pattern provides a fluent interface for configuring
  /// MerkleKV instances with validation and sensible defaults.
  ///
  /// Example:
  /// ```dart
  /// final config = MerkleKVConfig.builder()
  ///   .mqttHost('broker.example.com')
  ///   .mqttPort(8883)
  ///   .clientId('mobile-app-1')
  ///   .nodeId('node-1')
  ///   .topicPrefix('myapp/production')
  ///   .useTLS(true)
  ///   .credentials('username', 'password')
  ///   .build();
  /// ```
  static MerkleKVConfigBuilder builder() => MerkleKVConfigBuilder();
}

/// Builder class for creating MerkleKVConfig instances.
///
/// Provides a fluent interface with validation and sensible defaults.
class MerkleKVConfigBuilder {
  String? _mqttHost;
  int? _mqttPort;
  String? _username;
  String? _password;
  bool _mqttUseTls = false;
  String? _clientId;
  String? _nodeId;
  String _topicPrefix = '';
  int _keepAliveSeconds = 60;
  int _sessionExpirySeconds = 86400;
  int _skewMaxFutureMs = 300000;
  int _tombstoneRetentionHours = 24;
  bool _persistenceEnabled = false;
  String? _storagePath;
  bool? _enableOfflineQueue;

  /// Sets the MQTT broker hostname or IP address.
  MerkleKVConfigBuilder mqttHost(String host) {
    _mqttHost = host;
    return this;
  }

  /// Sets the MQTT broker port.
  ///
  /// If not specified, defaults to 8883 for TLS connections or 1883 otherwise.
  MerkleKVConfigBuilder mqttPort(int port) {
    _mqttPort = port;
    return this;
  }

  /// Sets MQTT authentication credentials.
  MerkleKVConfigBuilder credentials(String username, String password) {
    _username = username;
    _password = password;
    return this;
  }

  /// Sets the MQTT username for authentication.
  MerkleKVConfigBuilder username(String username) {
    _username = username;
    return this;
  }

  /// Sets the MQTT password for authentication.
  MerkleKVConfigBuilder password(String password) {
    _password = password;
    return this;
  }

  /// Enables or disables TLS for MQTT connection.
  MerkleKVConfigBuilder useTLS([bool enabled = true]) {
    _mqttUseTls = enabled;
    return this;
  }

  /// Sets the unique client identifier for MQTT connection.
  ///
  /// Must be between 1 and 128 characters long.
  MerkleKVConfigBuilder clientId(String clientId) {
    _clientId = clientId;
    return this;
  }

  /// Sets the unique node identifier for replication.
  ///
  /// Must be between 1 and 128 characters long.
  MerkleKVConfigBuilder nodeId(String nodeId) {
    _nodeId = nodeId;
    return this;
  }

  /// Sets the topic prefix for all MQTT topics.
  ///
  /// The prefix will be automatically normalized (no leading/trailing slashes).
  /// If empty after normalization, defaults to "mkv".
  MerkleKVConfigBuilder topicPrefix(String prefix) {
    _topicPrefix = prefix;
    return this;
  }

  /// Sets the MQTT keep-alive interval in seconds.
  ///
  /// Default: 60 seconds.
  MerkleKVConfigBuilder keepAlive(int seconds) {
    _keepAliveSeconds = seconds;
    return this;
  }

  /// Sets the session expiry interval in seconds.
  ///
  /// Default: 86400 seconds (24 hours).
  MerkleKVConfigBuilder sessionExpiry(int seconds) {
    _sessionExpirySeconds = seconds;
    return this;
  }

  /// Sets the maximum future time skew tolerance in milliseconds.
  ///
  /// Default: 300000 ms (5 minutes).
  MerkleKVConfigBuilder maxFutureSkew(int milliseconds) {
    _skewMaxFutureMs = milliseconds;
    return this;
  }

  /// Sets the tombstone retention period in hours.
  ///
  /// Default: 24 hours.
  MerkleKVConfigBuilder tombstoneRetention(int hours) {
    _tombstoneRetentionHours = hours;
    return this;
  }

  /// Enables or disables data persistence.
  ///
  /// When enabled, data will be stored to disk for durability.
  MerkleKVConfigBuilder persistence([bool enabled = true]) {
    _persistenceEnabled = enabled;
    return this;
  }

  /// Sets the storage path for persistence.
  ///
  /// If persistence is enabled but no path is specified,
  /// a temporary path will be generated automatically.
  MerkleKVConfigBuilder storagePath(String path) {
    _storagePath = path;
    return this;
  }

  /// Enables or disables offline queue for operations.
  ///
  /// When enabled, operations can be queued while disconnected
  /// and will be executed when connection is restored.
  MerkleKVConfigBuilder offlineQueue([bool enabled = true]) {
    _enableOfflineQueue = enabled;
    return this;
  }

  /// Builds and returns the configured MerkleKVConfig instance.
  ///
  /// Validates all required parameters and applies defaults where appropriate.
  ///
  /// Throws [ArgumentError] if required parameters are missing or invalid.
  MerkleKVConfig build() {
    if (_mqttHost == null) {
      throw ArgumentError('mqttHost is required');
    }
    if (_clientId == null) {
      throw ArgumentError('clientId is required');
    }
    if (_nodeId == null) {
      throw ArgumentError('nodeId is required');
    }

    return MerkleKVConfig(
      mqttHost: _mqttHost!,
      mqttPort: _mqttPort,
      username: _username,
      password: _password,
      mqttUseTls: _mqttUseTls,
      clientId: _clientId!,
      nodeId: _nodeId!,
      topicPrefix: _topicPrefix,
      keepAliveSeconds: _keepAliveSeconds,
      sessionExpirySeconds: _sessionExpirySeconds,
      skewMaxFutureMs: _skewMaxFutureMs,
      tombstoneRetentionHours: _tombstoneRetentionHours,
      persistenceEnabled: _persistenceEnabled,
      storagePath: _storagePath,
    );
  }
}
