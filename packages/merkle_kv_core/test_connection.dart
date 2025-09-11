#!/usr/bin/env dart

// Simple standalone test to verify MQTT broker connectivity
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'lib/src/mqtt/mqtt_client_impl.dart';
import 'lib/src/mqtt/connection_state.dart';
import 'lib/src/config/merkle_kv_config.dart';

Future<void> main() async {
  print('Testing MQTT broker connectivity...');
  
  final host = Platform.environment['MQTT_HOST'] ?? '127.0.0.1';
  final port = int.parse(Platform.environment['MQTT_PORT'] ?? '1883');
  
  print('Connecting to broker at $host:$port');
  
  try {
    final client = MqttClientImpl(
      MerkleKVConfig(
        mqttHost: host,
        mqttPort: port,
        username: null,
        password: null,
        mqttUseTls: false,
        nodeId: 'test-node-${DateTime.now().millisecondsSinceEpoch}',
        clientId: 'test-connection-${DateTime.now().millisecondsSinceEpoch}',
        topicPrefix: 'test',
        storagePath: '',
        persistenceEnabled: false,
      ),
    );
    
    // Listen for connection state
    final completer = Completer<void>();
    late StreamSubscription subscription;
    
    subscription = client.connectionState.listen((state) {
      print('Connection state: $state');
      if (state == ConnectionState.connected && !completer.isCompleted) {
        completer.complete();
      }
    });
    
    // Timeout
    Timer(const Duration(seconds: 10), () {
      if (!completer.isCompleted) {
        completer.completeError(TimeoutException('Connection timeout', const Duration(seconds: 10)));
      }
    });
    
    // Connect
    print('Calling connect...');
    await client.connect();
    
    // Wait for connected state
    await completer.future;
    
    print('✅ Successfully connected to broker!');
    
    await subscription.cancel();
    await client.disconnect();
    
    print('✅ Test completed successfully');
    
  } catch (e) {
    print('❌ Connection failed: $e');
    exit(1);
  }
}
