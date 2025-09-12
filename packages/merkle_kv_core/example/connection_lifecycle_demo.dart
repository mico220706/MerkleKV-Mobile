import 'dart:async';

import '../lib/src/config/merkle_kv_config.dart';
import '../lib/src/mqtt/connection_lifecycle.dart';
import '../lib/src/mqtt/connection_logger.dart';
import '../lib/src/mqtt/mqtt_client_impl.dart';
import '../lib/src/replication/metrics.dart';

/// Simple console logger for demo purposes
class DemoLogger {
  static void info(String message) {
    // ignore: avoid_print
    print(message);
  }
  
  static void error(String message) {
    // ignore: avoid_print  
    print(message);
  }
}

/// Example demonstrating the Connection Lifecycle Manager
/// 
/// This example shows how to use the ConnectionLifecycleManager for proper
/// MQTT connection management with graceful disconnection, state monitoring,
/// and platform lifecycle integration.
void main() async {
  DemoLogger.info('🔄 Connection Lifecycle Manager Demo');
  DemoLogger.info('====================================');

  // Create configuration
  final config = MerkleKVConfig(
    mqttHost: 'localhost',  // Change to your MQTT broker
    mqttPort: 1883,
    nodeId: 'demo-node',
    clientId: 'lifecycle-demo-client',
    keepAliveSeconds: 30,
  );

  // Create MQTT client
  final mqttClient = MqttClientImpl(config);
  
  // Create metrics for observability
  final metrics = InMemoryReplicationMetrics();
  
  // Create connection lifecycle manager with custom logger
  final manager = DefaultConnectionLifecycleManager(
    config: config,
    mqttClient: mqttClient,
    metrics: metrics,
    maintainConnectionInBackground: true,
    logger: const DefaultConnectionLogger(enableDebug: false), // Less verbose for demo
  );

  // Monitor connection state changes
  final subscription = manager.connectionState.listen((event) {
    DemoLogger.info('📡 Connection State: ${event.state} - ${event.reason}');
    if (event.error != null) {
      DemoLogger.error('   ❌ Error: ${event.error}');
    }
  });

  try {
    DemoLogger.info('\n🚀 Connecting to MQTT broker...');
    
    // Attempt connection
    try {
      await manager.connect();
      DemoLogger.info('✅ Connected successfully!');
      DemoLogger.info('   Connection status: ${manager.isConnected}');
    } catch (e) {
      DemoLogger.error('❌ Connection failed: $e');
      DemoLogger.info('   (This is expected if no MQTT broker is running)');
      return;
    }

    // Simulate app lifecycle changes
    // ignore: avoid_print
    print('\n📱 Simulating app lifecycle changes...');
    
    // Simulate app going to background
    // ignore: avoid_print
    print('   ⏸️  App pausing (backgrounding)...');
    await manager.handleAppStateChange(AppLifecycleState.paused);
    // ignore: avoid_print
    print('   Connection status after pause: ${manager.isConnected}');
    
    // Wait a moment
    await Future.delayed(const Duration(seconds: 1));
    
    // Simulate app resuming
    // ignore: avoid_print
    print('   ▶️  App resuming (foregrounding)...');
    await manager.handleAppStateChange(AppLifecycleState.resumed);
    // ignore: avoid_print
    print('   Connection status after resume: ${manager.isConnected}');

    // Wait a moment to see connection activity
    await Future.delayed(const Duration(seconds: 2));

    // Demonstrate graceful disconnection
    // ignore: avoid_print
    print('\n🔌 Performing graceful disconnection...');
    // ignore: avoid_print
    print('   Suppressing LWT message for clean shutdown...');
    
    await manager.disconnect(suppressLWT: true);
    // ignore: avoid_print
    print('✅ Disconnected successfully!');
    // ignore: avoid_print
    print('   Connection status: ${manager.isConnected}');

  } catch (e) {
    // ignore: avoid_print
    print('❌ Demo error: $e');
  } finally {
    // Clean up resources
    // ignore: avoid_print
    print('\n🧹 Cleaning up resources...');
    
    await subscription.cancel();
    await manager.dispose();
    
    // ignore: avoid_print
    print('✅ Cleanup completed');
  }

  // ignore: avoid_print
  print('\n📊 Demo completed successfully!');
  // ignore: avoid_print
  print('   Features demonstrated:');
  // ignore: avoid_print
  print('   ✓ Connection establishment with proper handshake');
  // ignore: avoid_print
  print('   ✓ Connection state monitoring and events');
  // ignore: avoid_print
  print('   ✓ Platform lifecycle integration (background/foreground)');
  // ignore: avoid_print
  print('   ✓ Graceful disconnection with LWT suppression');
  // ignore: avoid_print
  print('   ✓ Resource cleanup and disposal');
  // ignore: avoid_print
  print('   ✓ Error handling and recovery');
}

/// Example showing different configuration options
void demonstrateConfigurationOptions() {
  // ignore: avoid_print
  print('\n🔧 Connection Lifecycle Configuration Options');
  // ignore: avoid_print
  print('===========================================');

  // Basic configuration
  final basicConfig = MerkleKVConfig(
    mqttHost: 'localhost',
    nodeId: 'basic-node',
    clientId: 'basic-client',
  );

  // Secure configuration with TLS
  final secureConfig = MerkleKVConfig(
    mqttHost: 'secure-broker.example.com',
    mqttPort: 8883,
    mqttUseTls: true,
    username: 'secure-user',
    password: 'secure-password',
    nodeId: 'secure-node',
    clientId: 'secure-client',
    keepAliveSeconds: 60,
  );

  // Configuration for mobile environments
  final mobileConfig = MerkleKVConfig(
    mqttHost: 'mobile-broker.example.com',
    nodeId: 'mobile-node',
    clientId: 'mobile-client',
    keepAliveSeconds: 120,  // Longer keep-alive for mobile networks
  );

  // ignore: avoid_print
  print('✓ Basic configuration: ${basicConfig.mqttHost}:${basicConfig.mqttPort}');
  // ignore: avoid_print
  print('✓ Secure configuration: ${secureConfig.mqttHost}:${secureConfig.mqttPort} (TLS)');
  // ignore: avoid_print
  print('✓ Mobile configuration: ${mobileConfig.mqttHost}:${mobileConfig.mqttPort}');
  
  // ignore: avoid_print
  print('\n🔒 Security features:');
  // ignore: avoid_print
  print('   ✓ TLS encryption when credentials are provided');
  // ignore: avoid_print
  print('   ✓ Certificate validation (reject bad certificates)');
  // ignore: avoid_print
  print('   ✓ Credential cleanup on disconnection');
  
  // ignore: avoid_print
  print('\n📱 Mobile optimizations:');
  // ignore: avoid_print
  print('   ✓ Configurable background connection maintenance');
  // ignore: avoid_print
  print('   ✓ Platform lifecycle event integration');
  // ignore: avoid_print
  print('   ✓ Automatic reconnection on foreground resume');
  // ignore: avoid_print
  print('   ✓ Proper resource cleanup for memory efficiency');
}