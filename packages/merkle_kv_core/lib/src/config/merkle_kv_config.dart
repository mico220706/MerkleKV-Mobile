import 'package:logging/logging.dart';

/// Configuration class for MerkleKV Mobile client
class MerkleKVConfig {
  /// MQTT broker hostname or IP address
  final String mqttBroker;
  
  /// MQTT broker port (default: 1883 for non-TLS, 8883 for TLS)
  final int mqttPort;
  
  /// MQTT username (optional)
  final String? mqttUsername;
  
  /// MQTT password (optional)
  final String? mqttPassword;
  
  /// Use TLS for MQTT connection
  final bool useTls;
  
  /// Validate TLS certificates
  final bool validateCertificates;
  
  /// Client ID for MQTT connection (must be unique per device)
  final String clientId;
  
  /// Node ID for replication (used in change events)
  final String nodeId;
  
  /// Topic prefix for all MQTT topics
  final String topicPrefix;
  
  /// Enable persistence to disk
  final bool persistenceEnabled;
  
  /// Path for persistent storage
  final String storagePath;
  
  /// Enable replication
  final bool replicationEnabled;
  
  /// Anti-entropy synchronization interval
  final Duration antientropyInterval;
  
  /// Request timeout duration
  final Duration requestTimeout;
  
  /// MQTT keep-alive interval
  final Duration keepAliveInterval;
  
  /// Connection timeout for MQTT
  final Duration connectionTimeout;
  
  /// Automatic reconnect on connection loss
  final bool autoReconnect;
  
  /// Maximum number of reconnection attempts
  final int maxReconnectAttempts;
  
  /// Reconnection delay
  final Duration reconnectDelay;
  
  /// Log level for the client
  final Level logLevel;
  
  /// Maximum message size for MQTT
  final int maxMessageSize;
  
  /// Quality of Service level for MQTT messages
  final int qosLevel;
  
  /// Retain messages on broker
  final bool retainMessages;
  
  /// Clean session on MQTT connect
  final bool cleanSession;
  
  /// Will topic for MQTT last will and testament
  final String? willTopic;
  
  /// Will message for MQTT last will and testament
  final String? willMessage;
  
  /// Will retain flag for MQTT last will and testament
  final bool willRetain;
  
  /// Will QoS for MQTT last will and testament
  final int willQos;
  
  const MerkleKVConfig({
    required this.mqttBroker,
    this.mqttPort = 1883,
    this.mqttUsername,
    this.mqttPassword,
    this.useTls = false,
    this.validateCertificates = true,
    required this.clientId,
    required this.nodeId,
    this.topicPrefix = 'merkle_kv_mobile',
    this.persistenceEnabled = false,
    this.storagePath = '/tmp/merkle_kv',
    this.replicationEnabled = true,
    this.antientropyInterval = const Duration(minutes: 5),
    this.requestTimeout = const Duration(seconds: 30),
    this.keepAliveInterval = const Duration(seconds: 60),
    this.connectionTimeout = const Duration(seconds: 10),
    this.autoReconnect = true,
    this.maxReconnectAttempts = 5,
    this.reconnectDelay = const Duration(seconds: 5),
    this.logLevel = Level.INFO,
    this.maxMessageSize = 1024 * 1024, // 1MB
    this.qosLevel = 1, // At least once delivery
    this.retainMessages = false,
    this.cleanSession = true,
    this.willTopic,
    this.willMessage,
    this.willRetain = false,
    this.willQos = 0,
  });
  
  /// Create a copy of this configuration with updated values
  MerkleKVConfig copyWith({
    String? mqttBroker,
    int? mqttPort,
    String? mqttUsername,
    String? mqttPassword,
    bool? useTls,
    bool? validateCertificates,
    String? clientId,
    String? nodeId,
    String? topicPrefix,
    bool? persistenceEnabled,
    String? storagePath,
    bool? replicationEnabled,
    Duration? antientropyInterval,
    Duration? requestTimeout,
    Duration? keepAliveInterval,
    Duration? connectionTimeout,
    bool? autoReconnect,
    int? maxReconnectAttempts,
    Duration? reconnectDelay,
    Level? logLevel,
    int? maxMessageSize,
    int? qosLevel,
    bool? retainMessages,
    bool? cleanSession,
    String? willTopic,
    String? willMessage,
    bool? willRetain,
    int? willQos,
  }) {
    return MerkleKVConfig(
      mqttBroker: mqttBroker ?? this.mqttBroker,
      mqttPort: mqttPort ?? this.mqttPort,
      mqttUsername: mqttUsername ?? this.mqttUsername,
      mqttPassword: mqttPassword ?? this.mqttPassword,
      useTls: useTls ?? this.useTls,
      validateCertificates: validateCertificates ?? this.validateCertificates,
      clientId: clientId ?? this.clientId,
      nodeId: nodeId ?? this.nodeId,
      topicPrefix: topicPrefix ?? this.topicPrefix,
      persistenceEnabled: persistenceEnabled ?? this.persistenceEnabled,
      storagePath: storagePath ?? this.storagePath,
      replicationEnabled: replicationEnabled ?? this.replicationEnabled,
      antientropyInterval: antientropyInterval ?? this.antientropyInterval,
      requestTimeout: requestTimeout ?? this.requestTimeout,
      keepAliveInterval: keepAliveInterval ?? this.keepAliveInterval,
      connectionTimeout: connectionTimeout ?? this.connectionTimeout,
      autoReconnect: autoReconnect ?? this.autoReconnect,
      maxReconnectAttempts: maxReconnectAttempts ?? this.maxReconnectAttempts,
      reconnectDelay: reconnectDelay ?? this.reconnectDelay,
      logLevel: logLevel ?? this.logLevel,
      maxMessageSize: maxMessageSize ?? this.maxMessageSize,
      qosLevel: qosLevel ?? this.qosLevel,
      retainMessages: retainMessages ?? this.retainMessages,
      cleanSession: cleanSession ?? this.cleanSession,
      willTopic: willTopic ?? this.willTopic,
      willMessage: willMessage ?? this.willMessage,
      willRetain: willRetain ?? this.willRetain,
      willQos: willQos ?? this.willQos,
    );
  }
  
  /// Get the command topic for this client
  String get commandTopic => '$topicPrefix/$clientId/cmd';
  
  /// Get the response topic for this client
  String get responseTopic => '$topicPrefix/$clientId/res';
  
  /// Get the replication topic
  String get replicationTopic => '$topicPrefix/replication/events';
  
  /// Get the anti-entropy topic
  String get antientropyTopic => '$topicPrefix/antientropy';
  
  /// Validate the configuration
  void validate() {
    if (mqttBroker.isEmpty) {
      throw ArgumentError('MQTT broker cannot be empty');
    }
    
    if (mqttPort <= 0 || mqttPort > 65535) {
      throw ArgumentError('MQTT port must be between 1 and 65535');
    }
    
    if (clientId.isEmpty) {
      throw ArgumentError('Client ID cannot be empty');
    }
    
    if (nodeId.isEmpty) {
      throw ArgumentError('Node ID cannot be empty');
    }
    
    if (topicPrefix.isEmpty) {
      throw ArgumentError('Topic prefix cannot be empty');
    }
    
    if (requestTimeout.inMilliseconds <= 0) {
      throw ArgumentError('Request timeout must be positive');
    }
    
    if (keepAliveInterval.inSeconds <= 0) {
      throw ArgumentError('Keep alive interval must be positive');
    }
    
    if (connectionTimeout.inMilliseconds <= 0) {
      throw ArgumentError('Connection timeout must be positive');
    }
    
    if (maxReconnectAttempts < 0) {
      throw ArgumentError('Max reconnect attempts must be non-negative');
    }
    
    if (qosLevel < 0 || qosLevel > 2) {
      throw ArgumentError('QoS level must be 0, 1, or 2');
    }
    
    if (willQos < 0 || willQos > 2) {
      throw ArgumentError('Will QoS level must be 0, 1, or 2');
    }
    
    if (maxMessageSize <= 0) {
      throw ArgumentError('Max message size must be positive');
    }
  }
  
  @override
  String toString() {
    return 'MerkleKVConfig{'
        'broker: $mqttBroker:$mqttPort, '
        'clientId: $clientId, '
        'nodeId: $nodeId, '
        'tls: $useTls, '
        'persistence: $persistenceEnabled, '
        'replication: $replicationEnabled'
        '}';
  }
  
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! MerkleKVConfig) return false;
    
    return mqttBroker == other.mqttBroker &&
        mqttPort == other.mqttPort &&
        mqttUsername == other.mqttUsername &&
        mqttPassword == other.mqttPassword &&
        useTls == other.useTls &&
        validateCertificates == other.validateCertificates &&
        clientId == other.clientId &&
        nodeId == other.nodeId &&
        topicPrefix == other.topicPrefix &&
        persistenceEnabled == other.persistenceEnabled &&
        storagePath == other.storagePath &&
        replicationEnabled == other.replicationEnabled &&
        antientropyInterval == other.antientropyInterval &&
        requestTimeout == other.requestTimeout &&
        keepAliveInterval == other.keepAliveInterval &&
        connectionTimeout == other.connectionTimeout &&
        autoReconnect == other.autoReconnect &&
        maxReconnectAttempts == other.maxReconnectAttempts &&
        reconnectDelay == other.reconnectDelay &&
        logLevel == other.logLevel &&
        maxMessageSize == other.maxMessageSize &&
        qosLevel == other.qosLevel &&
        retainMessages == other.retainMessages &&
        cleanSession == other.cleanSession &&
        willTopic == other.willTopic &&
        willMessage == other.willMessage &&
        willRetain == other.willRetain &&
        willQos == other.willQos;
  }
  
  @override
  int get hashCode {
    return Object.hashAll([
      mqttBroker,
      mqttPort,
      mqttUsername,
      mqttPassword,
      useTls,
      validateCertificates,
      clientId,
      nodeId,
      topicPrefix,
      persistenceEnabled,
      storagePath,
      replicationEnabled,
      antientropyInterval,
      requestTimeout,
      keepAliveInterval,
      connectionTimeout,
      autoReconnect,
      maxReconnectAttempts,
      reconnectDelay,
      logLevel,
      maxMessageSize,
      qosLevel,
      retainMessages,
      cleanSession,
      willTopic,
      willMessage,
      willRetain,
      willQos,
    ]);
  }
}
