import 'merkle_kv_config.dart';

/// Default configuration presets for different environments
class DefaultConfig {
  /// Development configuration with local broker
  static MerkleKVConfig development({
    required String clientId,
    String? nodeId,
  }) {
    return MerkleKVConfig(
      mqttHost: 'localhost',
      mqttUseTls: false,
      clientId: clientId,
      nodeId: nodeId ?? clientId,
      topicPrefix: 'merkle_kv_mobile_dev',
      persistenceEnabled: false,
    );
  }

  /// Production configuration with TLS
  static MerkleKVConfig production({
    required String mqttHost,
    required String clientId,
    required String nodeId,
    String? username,
    String? password,
    int? mqttPort,
    String topicPrefix = 'merkle_kv_mobile',
  }) {
    return MerkleKVConfig(
      mqttHost: mqttHost,
      mqttPort: mqttPort,
      username: username,
      password: password,
      mqttUseTls: true,
      clientId: clientId,
      nodeId: nodeId,
      topicPrefix: topicPrefix,
      persistenceEnabled: true,
      storagePath: '/var/lib/merkle_kv',
    );
  }

  /// Testing configuration with in-memory storage
  static MerkleKVConfig testing({
    required String clientId,
    String? nodeId,
    String mqttHost = 'test.mosquitto.org',
  }) {
    return MerkleKVConfig(
      mqttHost: mqttHost,
      mqttUseTls: false,
      clientId: clientId,
      nodeId: nodeId ?? clientId,
      topicPrefix: 'merkle_kv_mobile_test',
      persistenceEnabled: false,
    );
  }

  /// Offline configuration for testing without MQTT
  static MerkleKVConfig offline({
    required String clientId,
    String? nodeId,
  }) {
    return MerkleKVConfig(
      mqttHost: 'offline',
      mqttUseTls: false,
      clientId: clientId,
      nodeId: nodeId ?? clientId,
      topicPrefix: 'merkle_kv_mobile_offline',
      persistenceEnabled: true,
      storagePath: '/tmp/merkle_kv_offline',
    );
  }

  /// Mobile-optimized configuration
  static MerkleKVConfig mobile({
    required String mqttHost,
    required String clientId,
    required String nodeId,
    String? username,
    String? password,
    bool useTls = true,
  }) {
    return MerkleKVConfig(
      mqttHost: mqttHost,
      username: username,
      password: password,
      mqttUseTls: useTls,
      clientId: clientId,
      nodeId: nodeId,
      topicPrefix: 'merkle_kv_mobile',
      persistenceEnabled: true,
      storagePath: '/var/lib/merkle_kv_mobile',
      keepAliveSeconds: 120, // 2 minutes for mobile
      sessionExpirySeconds: 3600, // 1 hour for mobile
    );
  }

  /// Edge device configuration with minimal resources
  static MerkleKVConfig edge({
    required String mqttHost,
    required String clientId,
    required String nodeId,
    String? username,
    String? password,
  }) {
    return MerkleKVConfig(
      mqttHost: mqttHost,
      username: username,
      password: password,
      mqttUseTls: false, // Minimal TLS overhead
      clientId: clientId,
      nodeId: nodeId,
      topicPrefix: 'merkle_kv_edge',
      persistenceEnabled: false, // Minimal storage usage
      keepAliveSeconds: 300, // 5 minutes for edge
      sessionExpirySeconds: 7200, // 2 hours for edge
    );
  }
}
