# MerkleKV Mobile

A distributed key-value store optimized for mobile edge devices with MQTT-based communication and replication.

## 📋 Table of Contents

- [📱 Overview](#-overview)
- [🚀 Getting Started](#-getting-started)
- [🏗️ Architecture](#️-architecture)
- [📚 API Reference](#-api-reference)
- [🔄 Replication System](#-replication-system)
- [💻 Implementation Details](#-implementation-details)
- [🛠️ Configuration](#️-configuration)
- [📋 Usage Example](#-usage-example)
- [🏭 Implementation Steps](#-implementation-steps)
- [🧪 Testing Strategy](#-testing-strategy)
- [📊 Performance Considerations](#-performance-considerations)
- [📱 Platform Support](#-platform-support)
- [🔒 Security Considerations](#-security-considerations)
- [⚡ Next Steps](#-next-steps)

## 📱 Overview

MerkleKV Mobile is a lightweight, distributed key-value store designed specifically for mobile edge devices. Unlike the original MerkleKV that uses a TCP server for client-server communication, MerkleKV Mobile uses MQTT for all communications, making it ideal for mobile environments where opening TCP ports is not feasible.

The system provides:
- In-memory key-value storage
- Real-time data synchronization between devices
- MQTT-based request-response communication pattern
- Efficient Merkle tree-based anti-entropy synchronization
- Device-specific message routing using client IDs

## 🏗️ Architecture

### Communication Model

MerkleKV Mobile uses a pure MQTT communication model:

1. **Command Channel**: Each device subscribes to its own command topic based on its client ID:
   ```
   merkle_kv_mobile/{client_id}/cmd
   ```

2. **Response Channel**: Responses are published to a client-specific response topic:
   ```
   merkle_kv_mobile/{client_id}/res
   ```

3. **Replication Channel**: Data changes are published to a shared replication topic:
   ```
   merkle_kv_mobile/replication/events
   ```

### Data Flow

#### Command Execution Flow
```
Mobile App                  MerkleKV Mobile Library               MQTT Broker
    |                               |                                  |
    |-- Command (SET user:1 value) ->|                                  |
    |                               |-- Publish to {client_id}/cmd --->|
    |                               |                                  |
    |                               |<- Subscribe to {client_id}/res --|
    |                               |                                  |
    |                               |-- Process command locally ------>|
    |                               |                                  |
    |                               |-- Publish result to {client_id}/res ->|
    |<- Response (OK) --------------|                                  |
    |                               |                                  |
```

#### Replication Flow
```
Device 1                     MQTT Broker                    Device 2
   |                             |                             |
   |-- SET operation ----------->|                             |
   |                             |                             |
   |-- Publish change event ---->|                             |
   |                             |                             |
   |                             |-- Forward change event ---->|
   |                             |                             |
   |                             |<- Subscribe to replication -|
   |                             |                             |
   |                             |                             |-- Apply change locally
   |                             |                             |
```

## 📚 API Reference

### Command Format

Commands are sent as JSON objects to the command topic:

```json
{
  "id": "req-12345",        // Request ID for correlation
  "op": "SET",              // Operation: GET, SET, DEL, etc.
  "key": "user:123",        // Key to operate on
  "value": "john_doe",      // Value (for SET, APPEND, etc.)
  "amount": 5               // Amount (for INCR, DECR operations)
}
```

### Response Format

Responses are published as JSON objects to the response topic:

```json
{
  "id": "req-12345",        // Original request ID
  "status": "OK",           // Status: OK, NOT_FOUND, ERROR
  "value": "john_doe",      // Value (for GET operations)
  "error": "error message"  // Error description (if status is ERROR)
}
```

### Supported Operations

#### Basic Operations
- `GET`: Retrieve a value by key
- `SET`: Store a key-value pair
- `DEL`: Delete a key and its value

#### Numeric Operations
- `INCR`: Increment a numeric value (with optional amount)
- `DECR`: Decrement a numeric value (with optional amount)

#### String Operations
- `APPEND`: Append a value to an existing string
- `PREPEND`: Prepend a value to an existing string

#### Bulk Operations
- `MGET`: Get multiple keys in one request
- `MSET`: Set multiple key-value pairs in one request

## 🔄 Replication System

### Change Event Format

Change events are serialized using CBOR for efficiency and published to the replication topic:

```
{
  "op": "SET",              // Operation type
  "key": "user:123",        // Key modified
  "value": "john_doe",      // New value (if applicable)
  "timestamp": 1637142400,  // Operation timestamp (UTC)
  "node_id": "device-xyz",  // Source device ID
  "seq": 42                 // Sequence number for ordering
}
```

### Conflict Resolution

- **Last-Write-Wins (LWW)**: Conflicts are resolved using timestamp ordering
- **Source Tracking**: Events include source node ID to prevent loops
- **Idempotency**: Duplicate events with the same sequence number are ignored

## 💻 Implementation Details

### Core Components

1. **Storage Engine**: In-memory key-value store with optional persistence
2. **MQTT Client**: Manages subscriptions, publications, and reconnection logic
3. **Command Processor**: Handles incoming commands and generates responses
4. **Replication Manager**: Publishes and applies change events
5. **Merkle Tree**: Efficient data structure for anti-entropy synchronization

### Message Processing Pipeline

```
MQTT Message → JSON Parsing → Command Validation → Command Execution → 
Response Generation → Response Publishing → (Optional) Replication
```

## 🛠️ Configuration

```dart
final config = MerkleKVConfig(
  // MQTT Connection
  mqttBroker: 'broker.example.com',
  mqttPort: 1883,
  mqttUsername: 'user',  // Optional
  mqttPassword: 'pass',  // Optional
  
  // Device Identity
  clientId: 'mobile-device-123',
  nodeId: 'user-456-device',
  
  // Topics
  topicPrefix: 'merkle_kv_mobile',
  
  // Storage
  persistenceEnabled: true,
  storagePath: '/data/local/tmp/merkle_kv',
  
  // Replication
  replicationEnabled: true,
  antientropyIntervalSeconds: 300,
);

final store = MerkleKVMobile(config);
await store.connect();
```

## 📋 Usage Example

```dart
import 'package:merkle_kv_mobile/merkle_kv_mobile.dart';

void main() async {
  // Initialize the store
  final store = MerkleKVMobile(
    MerkleKVConfig(
      mqttBroker: 'test.mosquitto.org',
      mqttPort: 1883,
      clientId: 'mobile-${DateTime.now().millisecondsSinceEpoch}',
      nodeId: 'demo-device',
    ),
  );
  
  // Connect to MQTT broker
  await store.connect();
  
  // Set a value
  final setResult = await store.set('user:123', 'john_doe');
  print('SET result: ${setResult.status}');
  
  // Get a value
  final getResult = await store.get('user:123');
  print('GET result: ${getResult.value}');
  
  // Increment a counter
  await store.set('counter', '10');
  final incrResult = await store.incr('counter', 5);
  print('INCR result: ${incrResult.value}'); // Should be 15
  
  // Delete a value
  final delResult = await store.delete('user:123');
  print('DEL result: ${delResult.status}');
  
  // Close the connection
  await store.disconnect();
}
```

## 🏭 Implementation Steps

### Phase 1: Core Functionality

1. Implement basic MQTT client with reconnection handling
2. Create in-memory storage engine
3. Implement command processing pipeline
4. Add request-response pattern over MQTT
5. Basic GET/SET/DEL operations

### Phase 2: Advanced Operations

1. Add numeric operations (INCR/DECR)
2. Add string operations (APPEND/PREPEND)
3. Add bulk operations (MGET/MSET)
4. Implement operation timeout handling
5. Add persistent storage option

### Phase 3: Replication System

1. Implement change event serialization (CBOR)
2. Add replication event publishing
3. Implement replication event handling
4. Add Last-Write-Wins conflict resolution
5. Implement loop prevention mechanism

### Phase 4: Anti-Entropy & Optimization

1. Implement Merkle tree for efficient synchronization
2. Add anti-entropy protocol
3. Optimize message sizes
4. Add compression for large values
5. Implement efficient binary protocol

## 🧪 Testing Strategy

1. **Unit Tests**: Test individual components in isolation
2. Unit tests for core components
3. Mock-based tests for MQTT communication
4. Integration tests with real MQTT brokers
5. Flutter-specific integration tests
6. End-to-end tests in a real mobile environment

## 📊 Performance Considerations

- **Message Size**: Use CBOR encoding for compact messages
- **Battery Impact**: Implement intelligent reconnection strategy
- **Bandwidth Usage**: Batch operations when possible
- **Storage Efficiency**: Use incremental updates for large values
- **CPU Usage**: Optimize Merkle tree calculations for mobile CPUs

## 📱 Platform Support

- Android (API level 21+)
- iOS (iOS 10+)
- Flutter compatibility
- React Native compatibility (through native bridge)

## 🔒 Security Considerations

- **Authentication**: Support for MQTT username/password and client certificates
- **Authorization**: Topic-level access control using client ID
- **Encryption**: TLS for transport security
- **Data Privacy**: Optional value encryption at rest

## 🚀 Getting Started

### Quick Setup

The MerkleKV Mobile project structure has been created and includes:

✅ **Complete Monorepo Structure**
- Core Dart package with essential interfaces
- Flutter demo application template
- MQTT broker with security configuration
- Comprehensive documentation and CI/CD pipelines

✅ **Production-Ready MQTT Broker**
- TLS encryption support
- User authentication and ACL
- Docker containerization
- Health monitoring

### Prerequisites

- **Flutter SDK** 3.10.0 or higher
- **Dart SDK** 3.0.0 or higher
- **Docker** (for MQTT broker)
- **Git** for version control

### Development Setup

1. **Clone and Bootstrap the Project**:
   ```bash
   git clone https://github.com/mico220706/MerkleKV-Mobile.git
   cd MerkleKV-Mobile
   
   # Install Melos for monorepo management
   dart pub global activate melos
   
   # Bootstrap all packages
   melos bootstrap
   ```

2. **Start the MQTT Broker**:
   ```bash
   # Navigate to broker directory
   cd broker/mosquitto
   
   # Start the broker with Docker Compose
   docker-compose up -d
   
   # Verify broker is running
   docker-compose ps
   ```

3. **Run the Flutter Demo**:
   ```bash
   cd apps/flutter_demo
   flutter run
   ```

### Quick Usage Example

1. **Add the package to your pubspec.yaml**:
   ```yaml
   dependencies:
     merkle_kv_core:
       path: ../../packages/merkle_kv_core
   ```

2. **Import and use the package**:
   ```dart
   import 'package:merkle_kv_core/merkle_kv_core.dart';
   
   void main() async {
     // Initialize with your MQTT broker
     final store = MerkleKVMobile(
       MerkleKVConfig(
         mqttBroker: 'localhost',  // Use your broker address
         mqttPort: 1883,
         clientId: 'device-${DateTime.now().millisecondsSinceEpoch}',
         nodeId: 'demo-device',
       ),
     );
     
     // Connect to the broker
     await store.connect();
     
     // Use the store
     await store.set('profile:name', 'John Doe');
     final result = await store.get('profile:name');
     print('Retrieved: ${result.value}');
     
     // Clean up
     await store.disconnect();
   }
   ```

### Project Structure

```
MerkleKV-Mobile/
├── packages/
│   └── merkle_kv_core/          # Core Dart implementation
├── apps/
│   └── flutter_demo/            # Flutter demonstration app
├── broker/
│   └── mosquitto/               # MQTT broker configuration
├── scripts/
│   └── dev/                     # Development automation
├── docs/                        # Technical documentation
└── .github/workflows/           # CI/CD automation
```

### Development Commands

```bash
# Analyze code across all packages
melos run analyze

# Format code across all packages
melos run format

# Run tests across all packages
melos run test

# Start development broker
./scripts/dev/start_broker.sh

# Setup development environment
./scripts/dev/setup.sh
```

## ⚡ Next Steps

- Implement offline queue for operation persistence
- Add client-side caching strategy
- Create administration dashboard for monitoring
- Add support for complex data types
- Implement cross-platform plugins

## Code Style and CI Policy

This repository enforces strict Dart formatting in CI. All `.dart` files must pass `dart format --set-exit-if-changed`.

Developers must run the formatter locally before committing:

```bash
dart format .
```

CI will fail if formatting is not compliant.

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guidelines](CONTRIBUTING.md) for details on:

- Code of conduct
- Development workflow
- Pull request process
- Issue reporting guidelines

### Development Status

| Component | Status | Description |
|-----------|---------|-------------|
| **Core Package** | 🟡 In Progress | Basic interfaces and configuration |
| **Flutter Demo** | 🟡 In Progress | Template application structure |
| **MQTT Broker** | ✅ Complete | Production-ready with TLS/ACL |
| **CI/CD Pipeline** | ✅ Complete | Enterprise-grade automation |
| **Documentation** | 🟡 In Progress | Architecture and API docs |
| **Testing** | 🔴 Planned | Unit and integration tests |

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙋‍♂️ Support

- 📖 **Documentation**: [docs/](docs/)
- 🐛 **Bug Reports**: [GitHub Issues](https://github.com/mico220706/MerkleKV-Mobile/issues)
- 💡 **Feature Requests**: [GitHub Discussions](https://github.com/mico220706/MerkleKV-Mobile/discussions)
- 🔒 **Security Issues**: See [SECURITY.md](SECURITY.md)

---

**Made with ❤️ for mobile distributed systems**
