# MerkleKV Mobile

A distributed key-value store optimized for mobile edge devices with MQTT-based communication and replication.

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
