# MerkleKV Core

A distributed key-value store optimized for mobile edge devices with MQTT-based communication and replication.

## Features

### Enhanced Replication System
- **Event Publisher**: Reliable replication event publishing with persistent outbox queue
- **CBOR Serialization**: Efficient binary encoding for replication events
- **Monotonic Sequencing**: Ordered event delivery with automatic recovery
- **Observability**: Comprehensive metrics for monitoring replication health
- **Offline Resilience**: Buffered delivery with at-least-once guarantee

### Core Platform
- **MQTT Communication**: Request-response pattern over MQTT with correlation
- **In-Memory Storage**: Fast key-value store with Last-Write-Wins conflict resolution  
- **Command Processing**: GET/SET/DEL operations with validation and error handling
- **Configuration Management**: Type-safe, immutable configuration with validation

## Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  merkle_kv_core: ^0.0.1
```

Then run:

```bash
flutter pub get
```

## Quick Start

### Basic Usage

```dart
import 'package:merkle_kv_core/merkle_kv_core.dart';

// Configure the client
final config = MerkleKVConfig(
  mqttHost: 'broker.example.com',
  nodeId: 'mobile-device-1',
  clientId: 'app-instance-1',
);

// Initialize and start
final client = MerkleKVMobile(config);
await client.start();

// Basic operations
await client.set('user:123', 'Alice');
final value = await client.get('user:123');
await client.delete('user:123');
```

### Event Publishing

```dart
// Enable replication event publishing
final config = MerkleKVConfig(
  mqttHost: 'broker.example.com', 
  nodeId: 'mobile-device-1',
  clientId: 'app-instance-1',
  enableReplication: true,
);

final client = MerkleKVMobile(config);
await client.start();

// Operations automatically publish replication events
await client.set('key', 'value'); // Publishes SET event
await client.delete('key');       // Publishes DEL event
```

## Replication: CBOR Encoding/Decoding

```dart
// Encoding
final bytes = CborSerializer.encode(
  ReplicationEvent.value(
    key: 'k',
    nodeId: 'n1',
    seq: 42,
    timestampMs: 1712345678901,
    value: 'hello',
  ),
);

// Decoding
final evt = CborSerializer.decode(bytes);

// Constructors
// - value event (tombstone=false): includes `value`
// - tombstone event (tombstone=true): omits `value`
final del = ReplicationEvent.tombstone(
  key: 'k',
  nodeId: 'n1',
  seq: 43,
  timestampMs: 1712345679901,
);
```

### Notes

- Deterministic field order; binary output is stable across devices.
- Size limit: total CBOR payload ≤ 300 KiB (Spec §11). Oversize → error.
- Schema fields use snake_case (e.g., timestamp_ms, node_id).
