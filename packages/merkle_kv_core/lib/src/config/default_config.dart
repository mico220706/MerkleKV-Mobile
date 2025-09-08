import 'package:logging/logging.dart';
import 'merkle_kv_config.dart';

/// Default configuration presets for different environments
class DefaultConfig {
  /// Development configuration with local broker
  static MerkleKVConfig development({
    required String clientId,
    String? nodeId,
  }) {
    return MerkleKVConfig(
      mqttBroker: 'localhost',
      mqttPort: 1883,
      clientId: clientId,
      nodeId: nodeId ?? clientId,
      topicPrefix: 'merkle_kv_mobile_dev',
      persistenceEnabled: false,
      replicationEnabled: true,
      logLevel: Level.ALL,
      autoReconnect: true,
      cleanSession: true,
    );
  }
  
  /// Production configuration with TLS
  static MerkleKVConfig production({
    required String mqttBroker,
    required String clientId,
    required String nodeId,
    String? mqttUsername,
    String? mqttPassword,
    int mqttPort = 8883,
    String topicPrefix = 'merkle_kv_mobile',
  }) {
    return MerkleKVConfig(
      mqttBroker: mqttBroker,
      mqttPort: mqttPort,
      mqttUsername: mqttUsername,
      mqttPassword: mqttPassword,
      useTls: true,
      validateCertificates: true,
      clientId: clientId,
      nodeId: nodeId,
      topicPrefix: topicPrefix,
      persistenceEnabled: true,
      replicationEnabled: true,
      logLevel: Level.WARNING,
      autoReconnect: true,
      maxReconnectAttempts: 10,
      reconnectDelay: const Duration(seconds: 30),
      cleanSession: false,
    );
  }
  
  /// Testing configuration with in-memory storage
  static MerkleKVConfig testing({
    required String clientId,
    String? nodeId,
    String mqttBroker = 'test.mosquitto.org',
  }) {
    return MerkleKVConfig(
      mqttBroker: mqttBroker,
      mqttPort: 1883,
      clientId: clientId,
      nodeId: nodeId ?? clientId,
      topicPrefix: 'merkle_kv_mobile_test',
      persistenceEnabled: false,
      replicationEnabled: false,
      logLevel: Level.SEVERE,
      autoReconnect: false,
      requestTimeout: const Duration(seconds: 5),
      connectionTimeout: const Duration(seconds: 5),
      cleanSession: true,
    );
  }
  
  /// Offline configuration for testing without MQTT
  static MerkleKVConfig offline({
    required String clientId,
    String? nodeId,
  }) {
    return MerkleKVConfig(
      mqttBroker: 'offline',
      mqttPort: 1883,
      clientId: clientId,
      nodeId: nodeId ?? clientId,
      topicPrefix: 'merkle_kv_mobile_offline',
      persistenceEnabled: true,
      replicationEnabled: false,
      logLevel: Level.INFO,
      autoReconnect: false,
      requestTimeout: const Duration(seconds: 1),
      connectionTimeout: const Duration(seconds: 1),
    );
  }
  
  /// Mobile-optimized configuration
  static MerkleKVConfig mobile({
    required String mqttBroker,
    required String clientId,
    required String nodeId,
    String? mqttUsername,
    String? mqttPassword,
    bool useTls = true,
  }) {
    return MerkleKVConfig(
      mqttBroker: mqttBroker,
      mqttPort: useTls ? 8883 : 1883,
      mqttUsername: mqttUsername,
      mqttPassword: mqttPassword,
      useTls: useTls,
      validateCertificates: true,
      clientId: clientId,
      nodeId: nodeId,
      topicPrefix: 'merkle_kv_mobile',
      persistenceEnabled: true,
      replicationEnabled: true,
      logLevel: Level.INFO,
      autoReconnect: true,
      maxReconnectAttempts: 20,
      reconnectDelay: const Duration(seconds: 10),
      keepAliveInterval: const Duration(minutes: 2),
      requestTimeout: const Duration(seconds: 15),
      connectionTimeout: const Duration(seconds: 15),
      cleanSession: false,
      qosLevel: 1, // At least once delivery for mobile reliability
      antientropyInterval: const Duration(minutes: 10),
    );
  }
  
  /// Edge device configuration with minimal resources
  static MerkleKVConfig edge({
    required String mqttBroker,
    required String clientId,
    required String nodeId,
    String? mqttUsername,
    String? mqttPassword,
  }) {
    return MerkleKVConfig(
      mqttBroker: mqttBroker,
      mqttPort: 1883,
      mqttUsername: mqttUsername,
      mqttPassword: mqttPassword,
      useTls: false, // Minimal TLS overhead
      clientId: clientId,
      nodeId: nodeId,
      topicPrefix: 'merkle_kv_edge',
      persistenceEnabled: false, // Minimal storage usage
      replicationEnabled: true,
      logLevel: Level.WARNING, // Minimal logging
      autoReconnect: true,
      maxReconnectAttempts: 5,
      reconnectDelay: const Duration(seconds: 5),
      keepAliveInterval: const Duration(minutes: 5),
      requestTimeout: const Duration(seconds: 10),
      connectionTimeout: const Duration(seconds: 5),
      cleanSession: true,
      qosLevel: 0, // Fire and forget for performance
      maxMessageSize: 64 * 1024, // 64KB limit
      antientropyInterval: const Duration(hours: 1),
    );
  }
}
