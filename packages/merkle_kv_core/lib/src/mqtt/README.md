# Connection Lifecycle Management

## Overview

The Connection Lifecycle Management component provides comprehensive MQTT connection management for the MerkleKV Mobile system. It handles connection establishment, graceful disconnection with Last Will and Testament (LWT) suppression, connection state monitoring, resource cleanup, and platform lifecycle integration.

## Features

### ✅ Connection Establishment
- Proper MQTT handshake with configured parameters
- Support for clientId, cleanStart, keepAlive, LWT, and TLS
- Connection timeout handling with configurable timeouts
- State transitions: Disconnected → Connecting → Connected

### ✅ Graceful Disconnection
- LWT suppression option for clean shutdowns
- Clean MQTT DISCONNECT protocol
- Resource cleanup before disconnection
- State transitions: Connected → Disconnecting → Disconnected

### ✅ Connection State Monitoring
- Detailed connection state events with timestamps
- Error categorization (timeout, authentication, network, broker)
- Real-time state change notifications
- Connection duration tracking

### ✅ Resource Cleanup
- Automatic subscription cleanup on disconnect
- Active timer cancellation
- Authentication material clearance
- Memory leak prevention

### ✅ Platform Lifecycle Integration
- Background/foreground state handling
- Configurable connection maintenance policies
- Automatic reconnection on app resume
- iOS/Android lifecycle event support

### ✅ Observability and Metrics
- Connection lifecycle event tracking
- Connection duration metrics
- Disconnection reason categorization
- Resource cleanup operation counting

## Architecture

```dart
abstract class ConnectionLifecycleManager {
  Future<void> connect();
  Future<void> disconnect({bool suppressLWT = true});
  Future<void> handleAppStateChange(AppLifecycleState state);
  Stream<ConnectionStateEvent> get connectionState;
  bool get isConnected;
  Future<void> dispose();
}
```

### Key Components

1. **ConnectionStateEvent**: Detailed state events with timestamps, reasons, and error information
2. **DisconnectionReason**: Categorized reasons for connection failures
3. **AppLifecycleState**: Platform lifecycle states for mobile integration
4. **DefaultConnectionLifecycleManager**: Full implementation with all features

## Usage

### Basic Connection Management

```dart
import 'package:merkle_kv_core/merkle_kv_core.dart';

// Create configuration
final config = MerkleKVConfig(
  mqttHost: 'your-broker.example.com',
  nodeId: 'mobile-node-1',
  clientId: 'mobile-client-1',
);

// Create MQTT client and lifecycle manager
final mqttClient = MqttClientImpl(config);
final manager = DefaultConnectionLifecycleManager(
  config: config,
  mqttClient: mqttClient,
  metrics: InMemoryReplicationMetrics(),
);

// Monitor connection state
manager.connectionState.listen((event) {
  print('Connection state: ${event.state} - ${event.reason}');
  if (event.error != null) {
    print('Error: ${event.error}');
  }
});

// Connect
try {
  await manager.connect();
  print('Connected: ${manager.isConnected}');
} catch (e) {
  print('Connection failed: $e');
}

// Graceful disconnect
await manager.disconnect(suppressLWT: true);
print('Disconnected: ${manager.isConnected}');
```

### Platform Lifecycle Integration

```dart
// Configure background behavior
final manager = DefaultConnectionLifecycleManager(
  config: config,
  mqttClient: mqttClient,
  maintainConnectionInBackground: false, // Disconnect when backgrounded
);

// Handle app lifecycle changes
class AppLifecycleHandler with WidgetsBindingObserver {
  final ConnectionLifecycleManager manager;
  
  AppLifecycleHandler(this.manager) {
    WidgetsBinding.instance.addObserver(this);
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    manager.handleAppStateChange(state);
  }
  
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }
}
```

### Secure Configuration

```dart
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
```

## Configuration Options

### Connection Parameters
- `mqttHost`: MQTT broker hostname/IP
- `mqttPort`: MQTT broker port (1883 for plain, 8883 for TLS)
- `mqttUseTls`: Enable TLS encryption
- `username`/`password`: Authentication credentials
- `keepAliveSeconds`: MQTT keep-alive interval

### Lifecycle Options
- `maintainConnectionInBackground`: Keep connection when app is backgrounded
- Connection timeouts are based on `keepAliveSeconds * 2`
- Disconnection timeout is fixed at 10 seconds

## State Management

### Connection States
- `disconnected`: Not connected to broker
- `connecting`: Attempting to establish connection
- `connected`: Successfully connected and ready
- `disconnecting`: Gracefully disconnecting

### State Events
```dart
class ConnectionStateEvent {
  final ConnectionState state;
  final DateTime timestamp;
  final String? reason;
  final Exception? error;
}
```

### App Lifecycle States
- `resumed`: App has input focus
- `inactive`: App inactive but visible
- `paused`: App backgrounded
- `detached`: App detached from host
- `hidden`: App hidden from user

## Error Handling

### Error Categories
- **Timeout**: Connection establishment timeout
- **Authentication**: Invalid credentials
- **Network**: Network connectivity issues
- **Broker**: MQTT broker errors

### Recovery Strategies
- Connection timeouts trigger automatic cleanup
- Authentication failures require credential update
- Network errors support retry mechanisms
- Broker errors are logged for debugging

## Resource Management

### Automatic Cleanup
- Subscription removal on disconnect
- Timer cancellation
- Authentication material clearing
- Memory leak prevention

### Disposal Pattern
```dart
try {
  // Use connection lifecycle manager
  await manager.connect();
  // ... work with connection
} finally {
  // Always dispose resources
  await manager.dispose();
}
```

## Metrics and Observability

### Connection Metrics
- Connection establishment events
- Connection duration tracking
- Disconnection reason categorization
- Resource cleanup operation counts

### Logging
- Timestamped connection events
- Error details and stack traces
- State transition information
- Resource cleanup status

## Testing

### Unit Tests
- Connection establishment scenarios
- Graceful disconnection with/without LWT
- State transition validation
- Resource cleanup verification
- App lifecycle handling
- Error recovery scenarios

### Integration Tests
- Real MQTT broker connectivity
- Network interruption handling
- Performance benchmarking
- Reliability under stress
- Platform lifecycle simulation

## Best Practices

### Connection Management
1. Always use graceful disconnection with LWT suppression
2. Monitor connection state events for errors
3. Implement proper error handling and recovery
4. Clean up resources with dispose()

### Mobile Optimization
1. Configure appropriate keep-alive intervals
2. Handle app lifecycle states properly
3. Consider background connection policies
4. Optimize for battery and data usage

### Security
1. Always use TLS for production deployments
2. Implement proper credential management
3. Validate server certificates
4. Clear sensitive data on disconnection

### Performance
1. Monitor connection establishment times
2. Track resource usage and cleanup
3. Handle rapid connect/disconnect cycles
4. Optimize for mobile network conditions

## Troubleshooting

### Common Issues

**Connection Timeouts**
- Check network connectivity
- Verify broker accessibility
- Adjust keep-alive settings
- Review firewall configurations

**Authentication Failures**
- Verify username/password
- Check broker user permissions
- Ensure TLS configuration matches
- Validate certificate chain

**Resource Leaks**
- Always call dispose()
- Monitor subscription cleanup
- Check timer cancellation
- Verify state cleanup

**App Lifecycle Issues**
- Implement WidgetsBindingObserver
- Handle all lifecycle states
- Configure background policies
- Test foreground/background transitions

## Integration Examples

See `/example/connection_lifecycle_demo.dart` for a complete working example demonstrating all features of the Connection Lifecycle Manager.

## Dependencies

- `dart:async`: Core async support
- `MerkleKVConfig`: System configuration
- `MqttClientInterface`: MQTT client abstraction
- `ReplicationMetrics`: Observability metrics
- Platform lifecycle APIs (Flutter/native)

## Future Enhancements

- Custom authentication mechanisms
- Advanced connection pooling
- Detailed network diagnostics
- Enhanced mobile optimizations
- Custom retry strategies