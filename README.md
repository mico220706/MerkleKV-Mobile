# MerkleKV Mobile

A distributed key-value store optimized for mobile edge devices with MQTT-based communication and real-time synchronization.

## � Quick Start

```dart
import 'package:merkle_kv_core/merkle_kv_core.dart';

// 1. Configure
final config = MerkleKVConfig(
  mqttHost: 'broker.example.com',
  clientId: 'mobile-device-1',
  nodeId: 'unique-device-id',
  topicPrefix: 'myapp/production', // Multi-tenant support
);

// 2. Initialize
final client = MerkleKVMobile(config);
await client.start();

// 3. Use
await client.set('user:123', 'Alice');
final value = await client.get('user:123');
await client.delete('user:123');

// 4. Real-time sync between devices happens automatically
```

## 📋 What's New

### Latest Features (2025)
- ✅ **Multi-Tenant Isolation**: Prefix-based topic isolation with UTF-8 validation
- ✅ **Connection Lifecycle Management**: Auto-reconnection with exponential backoff
- ✅ **Anti-Entropy Protocol**: Merkle tree-based synchronization
- ✅ **Event Publishing**: Reliable replication with CBOR serialization
- ✅ **Production Ready**: Comprehensive testing and CI/CD

### Core Capabilities
- 📱 **Mobile-First**: Designed for mobile edge devices
- 🔄 **Real-Time Sync**: Automatic data synchronization between devices
- 📡 **MQTT-Based**: Uses MQTT instead of TCP for mobile-friendly communication
- 🔒 **Multi-Tenant**: Secure tenant isolation with topic prefixes
- ⚡ **High Performance**: In-memory storage with efficient sync protocols

## 📖 Documentation

| Topic | Description | Link |
|-------|-------------|------|
| **Getting Started** | Installation, basic usage, examples | [→ Tutorial](docs/TUTORIAL.md) |
| **Multi-Tenant Setup** | Topic validation, ACL configuration | [→ Multi-Tenant Guide](packages/merkle_kv_core/README_TOPIC_VALIDATION.md) |
| **Architecture** | System design, protocols, components | [→ Architecture](docs/architecture.md) |
| **API Reference** | Complete API documentation | [→ API Docs](packages/merkle_kv_core/README.md) |
| **Deployment** | Production setup, MQTT broker config | [→ Deployment Guide](docs/DEPLOYMENT.md) |
| **Contributing** | Development workflow, testing | [→ Contributing](CONTRIBUTING.md) |

## 🏗️ Architecture Overview

```
┌─────────────────┐    MQTT     ┌─────────────────┐
│   Mobile App A  │◄──────────►│   Mobile App B  │
│                 │             │                 │
│ ┌─────────────┐ │             │ ┌─────────────┐ │
│ │ MerkleKV    │ │             │ │ MerkleKV    │ │
│ │ Mobile      │ │             │ │ Mobile      │ │
│ │             │ │             │ │             │ │
│ │ • Storage   │ │             │ │ • Storage   │ │
│ │ • Sync      │ │             │ │ • Sync      │ │
│ │ • Commands  │ │             │ │ • Commands  │ │
│ └─────────────┘ │             │ └─────────────┘ │
└─────────────────┘             └─────────────────┘
        │                               │
        └─────────────┐     ┌───────────┘
                      ▼     ▼
                ┌─────────────────┐
                │   MQTT Broker   │
                │                 │
                │ • Message Routing
                │ • Topic Management
                │ • Multi-Tenant ACL
                └─────────────────┘
```

## 💻 Installation

### Flutter/Dart Projects

Add to your `pubspec.yaml`:

```yaml
dependencies:
  merkle_kv_core: ^1.0.0
```

```bash
flutter pub get
```

### MQTT Broker Setup

**Option 1: Local Development (Mosquitto)**
```bash
# Install
brew install mosquitto  # macOS
apt install mosquitto   # Ubuntu

# Start
mosquitto -p 1883 -v
```

**Option 2: Cloud (HiveMQ)**
```dart
final config = MerkleKVConfig(
  mqttHost: 'your-cluster.hivemq.cloud',
  mqttPort: 8883,
  mqttUseTls: true,
  username: 'your-username',
  password: 'your-password',
  // ... other config
);
```
## 🔧 Configuration Examples

### Single Tenant (Simple)
```dart
final config = MerkleKVConfig(
  mqttHost: 'broker.example.com',
  clientId: 'mobile-app-1',
  nodeId: 'device-uuid-123',
);
```

### Multi-Tenant (Production)
```dart
// Customer A - Production
final customerA = MerkleKVConfig(
  mqttHost: 'broker.example.com',
  clientId: 'device-001',
  nodeId: 'customer-a-device-001',
  topicPrefix: 'customer-a/production',
);

// Customer B - Production  
final customerB = MerkleKVConfig(
  mqttHost: 'broker.example.com',
  clientId: 'device-001',  // Same ID, different tenant
  nodeId: 'customer-b-device-001',
  topicPrefix: 'customer-b/production',
);

// Topics are completely isolated:
// Customer A: customer-a/production/device-001/cmd
// Customer B: customer-b/production/device-001/cmd
```

### With Persistence
```dart
final config = MerkleKVConfig(
  mqttHost: 'broker.example.com',
  clientId: 'mobile-device-1',
  nodeId: 'device-uuid-123',
  persistenceEnabled: true,
  storagePath: '/path/to/storage',
);
```

## 🚀 Advanced Usage

### Real-Time Synchronization
```dart
// Data changes sync automatically between devices
// Device A
await clientA.set('shared-counter', '1');

// Device B (receives update automatically)
final value = await clientB.get('shared-counter'); // Returns '1'

// Device B updates
await clientB.set('shared-counter', '2');

// Device A (receives update automatically)  
final updated = await clientA.get('shared-counter'); // Returns '2'
```

### Event Streaming
```dart
// Listen for replication events
client.replicationEvents.listen((event) {
  print('Key ${event.key} changed to ${event.value}');
});

// Enable event publishing
final config = MerkleKVConfig(
  // ... basic config
  enableReplication: true,
);
```

### Anti-Entropy Sync
## 🔐 Security & Production Setup

### MQTT TLS Configuration
```dart
final secureConfig = MerkleKVConfig(
  mqttHost: 'secure-broker.example.com',
  mqttPort: 8883,  // TLS port
  clientId: 'production-client-1',
  nodeId: 'prod-device-uuid-123',
  username: 'mqtt-user',
  password: 'secure-password',
  // TLS automatically enabled when credentials present
);
```

### Multi-Tenant Production
```dart
// Tenant isolation prevents data leakage
final tenant1Config = MerkleKVConfig(
  mqttHost: 'broker.example.com',
  clientId: 'device-001',
  nodeId: 'tenant1-device-001',
  topicPrefix: 'tenant1/production',  // Complete isolation
);

final tenant2Config = MerkleKVConfig(
  mqttHost: 'broker.example.com', 
  clientId: 'device-001',  // Same client ID, different tenant
  nodeId: 'tenant2-device-001',
  topicPrefix: 'tenant2/production',  // Complete isolation
);
```

### Certificate Validation
- Enable certificate pinning in production
- Use ACL files for MQTT broker user permissions
- Implement device registration and key rotation
- Monitor connection health and authentication failures

## 📊 Performance & Monitoring

### Built-in Metrics
```dart
// Check replication performance
final metrics = await client.getReplicationMetrics();
print('Published: ${metrics.eventsPublished}');
print('Queue size: ${metrics.outboxSize}');
print('Failed: ${metrics.publishFailures}');

// Monitor storage usage
final storageMetrics = await client.getStorageMetrics();
print('Total entries: ${storageMetrics.totalEntries}');
print('Storage size: ${storageMetrics.totalSizeBytes}');
```

### Optimizing Performance
- Use appropriate `topicPrefix` for tenant isolation
- Enable persistence only when needed
- Monitor outbox queue for delivery issues
- Implement proper error handling and retry logic
- Use connection pooling for multiple clients

## 🏗️ Architecture Overview

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Flutter App   │    │   MerkleKV Core  │    │  MQTT Broker    │
│                 │    │                  │    │                 │
│ ┌─────────────┐ │    │ ┌──────────────┐ │    │ ┌─────────────┐ │
│ │    UI       │ │◄──►│ │   Commands   │ │◄──►│ │   Topics    │ │
│ └─────────────┘ │    │ └──────────────┘ │    │ └─────────────┘ │
│                 │    │ ┌──────────────┐ │    │ ┌─────────────┐ │
│ │   Models    │ │◄──►│ │   Storage    │ │    │ │     TLS     │ │
│ └─────────────┘ │    │ │    Engine    │ │    │ │  Security   │ │
│                 │    │ └──────────────┘ │    │ └─────────────┘ │
│ ┌─────────────┐ │    │ ┌──────────────┐ │    │ ┌─────────────┐ │
│ │  Services   │ │◄──►│ │ Replication  │ │◄──►│ │    ACL      │ │
│ └─────────────┘ │    │ │    Events    │ │    │ │ Permissions │ │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

### Key Components
- **Commands**: GET/SET/DEL operations with response correlation
- **Storage**: In-memory with optional persistence and conflict resolution  
- **Replication**: Real-time sync via MQTT with anti-entropy recovery
- **Security**: TLS encryption with multi-tenant topic isolation

### Topic Scheme
```
{prefix}/{client_id}/cmd         # Command channel
{prefix}/{client_id}/res         # Response channel  
{prefix}/replication/events      # Shared replication
```

## 📚 Documentation & Tutorials

| Resource | Description | Level |
|----------|-------------|-------|
| [Quick Start](#-quick-start) | 5-minute setup guide | Beginner |
| [Configuration Examples](#-configuration-examples) | Production configs | Intermediate |
| [Architecture Guide](docs/architecture.md) | Deep technical dive | Advanced |
| [API Reference](packages/merkle_kv_core/README.md) | Complete API docs | Reference |
| [Security Guide](SECURITY.md) | Production security | Advanced |
| [CBOR Replication](docs/replication/cbor.md) | Serialization details | Advanced |
| [Contributing Guide](CONTRIBUTING.md) | Development setup | Contributor |

## 🛠️ Development

### Local Setup
```bash
# Clone repository
git clone https://github.com/your-org/MerkleKV-Mobile.git
cd MerkleKV-Mobile

# Setup development environment
./scripts/dev/setup.sh

# Start local MQTT broker
./scripts/dev/start_broker.sh

# Run tests
melos test
```

### Project Structure
```
packages/merkle_kv_core/     # Core library
apps/flutter_demo/           # Demo application
broker/mosquitto/            # Local MQTT broker
docs/                        # Documentation
```

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details on:
- Setting up development environment
- Running tests and linting
- Submitting pull requests
- Code style guidelines

## 📄 License

This project is licensed under the [MIT License](LICENSE) - see the LICENSE file for details.

## 🔗 Links

- **Issues**: [GitHub Issues](https://github.com/your-org/MerkleKV-Mobile/issues)
- **Discussions**: [GitHub Discussions](https://github.com/your-org/MerkleKV-Mobile/discussions)  
- **Security**: [Security Policy](SECURITY.md)
- **Changelog**: [CHANGELOG.md](CHANGELOG.md)

