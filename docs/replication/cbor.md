# CBOR Replication Event Schema (Spec §3.3)

> Deterministic CBOR encoding for replication change events with strict size limit ≤ 300 KiB (Spec §11).

## Schema

```json
{
  "key": "string",           // required (UTF-8)
  "node_id": "string",       // required
  "seq": 123,                // required (int64)
  "timestamp_ms": 1712345678901, // required (UTC ms, int64)
  "tombstone": false,        // required
  "value": "string"          // present ONLY if tombstone=false
}
```

## Deterministic Encoding

- Stable field order: key, node_id, seq, timestamp_ms, tombstone, value?
- Canonical representation for cross-device equality

## Size Limits (Spec §11)

- Total CBOR payload ≤ 300 KiB. At 300 KiB + 1 byte → error
- Enforced on both encode and decode

## Usage

```dart
// Encode
final bytes = CborSerializer.encode(
  ReplicationEvent.value(
    key: 'k',
    nodeId: 'n1',
    seq: 42,
    timestampMs: 1712345678901,
    value: 'hello',
  ),
);

// Decode
final evt = CborSerializer.decode(bytes);
```

## Tombstones

- tombstone=true → omit value in CBOR output
- Decoding enforces this rule

## Errors

- Oversized payload → size-limit error (Spec §11)
- Malformed/invalid CBOR → parse/validation error
- Missing/invalid fields → schema validation error

## Testing & Determinism

- Golden vectors confirm identical binary output across devices
- Boundary tests: exact 300 KiB passes; +1 byte fails
