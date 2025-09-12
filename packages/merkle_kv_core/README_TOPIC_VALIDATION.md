# Topic Prefix Configuration & Multi-Tenant Isolation

This document describes the enhanced topic validation and multi-tenant isolation features implemented in MerkleKV Mobile.

## Overview

The Topic Prefix Configuration feature provides comprehensive validation and multi-tenant isolation for MQTT topic management. It implements UTF-8 byte length validation, character restrictions, canonical topic schemes, and strong multi-tenant boundaries.

## Features

### Enhanced Topic Validation
- **UTF-8 Byte Length Validation**: Prefixes ≤50 bytes, Client IDs ≤128 bytes, Topics ≤100 bytes
- **Character Restrictions**: Only `[A-Za-z0-9_/-]` allowed for prefixes and client IDs
- **MQTT Wildcard Prevention**: Blocks `+` and `#` characters to prevent subscription injection
- **Canonical Topic Schemes**: Enforces `{prefix}/{client_id}/cmd|res` and `{prefix}/replication/events`

### Multi-Tenant Isolation
- **Prefix-Based Isolation**: Each tenant gets isolated topic namespace
- **Validation Integration**: Automatic validation in `MerkleKVConfig` and `TopicScheme`
- **Backward Compatibility**: Existing APIs enhanced without breaking changes

## Usage Examples

### Basic Configuration

```dart
import 'package:merkle_kv_core/merkle_kv_core.dart';

// Configure tenant-specific MerkleKV instance
final config = MerkleKVConfig(
  mqttHost: 'mqtt.example.com',
  mqttPort: 1883,
  clientId: 'mobile-device-001',
  nodeId: 'node-001',
  topicPrefix: 'tenant-a/production', // Tenant isolation
);

// Topics will be generated as:
// Commands: tenant-a/production/mobile-device-001/cmd
// Responses: tenant-a/production/mobile-device-001/res
// Replication: tenant-a/production/replication/events
```

### Multi-Tenant Scenarios

#### Scenario 1: Application Environments
```dart
// Production environment
final prodConfig = MerkleKVConfig(
  mqttHost: 'mqtt.company.com',
  clientId: 'app-device-123',
  nodeId: 'prod-node-1',
  topicPrefix: 'myapp/production',
);

// Staging environment
final stagingConfig = MerkleKVConfig(
  mqttHost: 'mqtt.company.com', 
  clientId: 'app-device-123',
  nodeId: 'staging-node-1',
  topicPrefix: 'myapp/staging',
);

// Topics are completely isolated:
// Production: myapp/production/app-device-123/cmd
// Staging: myapp/staging/app-device-123/cmd
```

#### Scenario 2: Customer Separation
```dart
// Customer A configuration
final customerAConfig = MerkleKVConfig(
  mqttHost: 'shared-mqtt.saas.com',
  clientId: 'device-001',
  nodeId: 'node-a-001',
  topicPrefix: 'customer-a/production',
);

// Customer B configuration  
final customerBConfig = MerkleKVConfig(
  mqttHost: 'shared-mqtt.saas.com',
  clientId: 'device-001', // Same device ID, different tenant
  nodeId: 'node-b-001',
  topicPrefix: 'customer-b/production',
);

// Completely isolated despite same clientId:
// Customer A: customer-a/production/device-001/cmd
// Customer B: customer-b/production/device-001/cmd
```

#### Scenario 3: Hierarchical Tenancy
```dart
// Multi-level tenant hierarchy
final configs = [
  MerkleKVConfig(
    mqttHost: 'enterprise.mqtt.com',
    clientId: 'sensor-001',
    nodeId: 'enterprise-node-1',
    topicPrefix: 'acme-corp/division-a/department-1',
  ),
  MerkleKVConfig(
    mqttHost: 'enterprise.mqtt.com',
    clientId: 'sensor-001',
    nodeId: 'enterprise-node-2', 
    topicPrefix: 'acme-corp/division-a/department-2',
  ),
  MerkleKVConfig(
    mqttHost: 'enterprise.mqtt.com',
    clientId: 'sensor-001',
    nodeId: 'enterprise-node-3',
    topicPrefix: 'acme-corp/division-b/department-1',
  ),
];

// Results in isolated topic spaces:
// acme-corp/division-a/department-1/sensor-001/cmd
// acme-corp/division-a/department-2/sensor-001/cmd
// acme-corp/division-b/department-1/sensor-001/cmd
```

### TopicValidator Direct Usage

```dart
import 'package:merkle_kv_core/merkle_kv_core.dart';

// Validate topic components
try {
  TopicValidator.validatePrefix('tenant-1/prod');
  TopicValidator.validateClientId('device-123');
  print('Validation passed');
} catch (ArgumentError e) {
  print('Validation failed: ${e.message}');
}

// Build canonical topics
final commandTopic = TopicValidator.buildCommandTopic(
  'tenant-1/prod', 
  'device-123'
);
print(commandTopic); // tenant-1/prod/device-123/cmd

// Extract prefix from existing topics
final prefix = TopicValidator.extractPrefix(
  'tenant-1/prod/device-123/cmd'
);
print(prefix); // tenant-1/prod

// Check UTF-8 byte lengths
final byteLength = TopicValidator.getUtf8ByteLength('café');
print(byteLength); // 5 (é takes 2 bytes in UTF-8)
```

### TopicScheme Enhanced Usage

```dart
// Create topic scheme with validation
final scheme = TopicScheme.create('tenant-a/env', 'mobile-app');

// Access canonical topics
print(scheme.commandTopic);    // tenant-a/env/mobile-app/cmd
print(scheme.responseTopic);   // tenant-a/env/mobile-app/res
print(scheme.replicationTopic); // tenant-a/env/replication/events

// Validate client IDs
try {
  TopicScheme.validateClientId('valid-client');
  TopicScheme.validateClientId('invalid/client'); // Throws ArgumentError
} catch (ArgumentError e) {
  print('Client ID validation failed: ${e.message}');
}
```

## MQTT Broker ACL Configuration

### Mosquitto ACL Examples

Configure your MQTT broker to enforce tenant isolation using Access Control Lists (ACLs):

```bash
# /etc/mosquitto/acl.conf

# Tenant A - Production Environment
user tenant-a-prod
topic readwrite tenant-a/production/+/cmd
topic readwrite tenant-a/production/+/res
topic readwrite tenant-a/production/replication/events

# Tenant A - Staging Environment  
user tenant-a-staging
topic readwrite tenant-a/staging/+/cmd
topic readwrite tenant-a/staging/+/res
topic readwrite tenant-a/staging/replication/events

# Tenant B - All Environments
user tenant-b
topic readwrite tenant-b/+/+/cmd
topic readwrite tenant-b/+/+/res
topic readwrite tenant-b/+/replication/events

# Admin user - All access
user admin
topic readwrite #

# Default - No access
pattern readwrite $SYS/#
```

### HiveMQ ACL Example

```xml
<!-- hivemq-extension/acl.xml -->
<acl>
  <!-- Tenant A Production -->
  <client-group>
    <id>tenant-a-prod</id>
    <client-id-pattern>tenant-a-prod-.*</client-id-pattern>
  </client-group>
  
  <permission>
    <client-group>tenant-a-prod</client-group>
    <topic>tenant-a/production/+/cmd</topic>
    <activity>PUBLISH</activity>
    <activity>SUBSCRIBE</activity>
  </permission>
  
  <permission>
    <client-group>tenant-a-prod</client-group>
    <topic>tenant-a/production/+/res</topic>
    <activity>PUBLISH</activity>
    <activity>SUBSCRIBE</activity>
  </permission>
  
  <permission>
    <client-group>tenant-a-prod</client-group>
    <topic>tenant-a/production/replication/events</topic>
    <activity>PUBLISH</activity>
    <activity>SUBSCRIBE</activity>
  </permission>
</acl>
```

## Migration Guide

### From Existing MerkleKV Deployments

#### Step 1: Update Configuration
Replace existing configurations with tenant-aware prefixes:

```dart
// OLD: Single shared namespace
final oldConfig = MerkleKVConfig(
  mqttHost: 'mqtt.example.com',
  clientId: 'device-123',
  nodeId: 'node-123',
  topicPrefix: '', // Default/shared namespace
);

// NEW: Tenant-isolated namespace
final newConfig = MerkleKVConfig(
  mqttHost: 'mqtt.example.com',
  clientId: 'device-123', 
  nodeId: 'node-123',
  topicPrefix: 'tenant-a/production', // Isolated namespace
);
```

#### Step 2: Update MQTT ACLs
Migrate broker ACLs to enforce tenant boundaries:

```bash
# Before: Single shared topic space
# topic readwrite mkv/+/cmd
# topic readwrite mkv/+/res
# topic readwrite mkv/replication/events

# After: Tenant-specific topic spaces
topic readwrite tenant-a/production/+/cmd
topic readwrite tenant-a/production/+/res
topic readwrite tenant-a/production/replication/events
```

#### Step 3: Data Migration
If migrating existing data, consider topic namespace changes:

```dart
// Helper function to migrate existing topic structures
String migrateTopic(String oldTopic, String tenantPrefix) {
  // OLD: mkv/device-123/cmd
  // NEW: tenant-a/production/device-123/cmd
  
  if (oldTopic.startsWith('mkv/')) {
    return oldTopic.replaceFirst('mkv/', '$tenantPrefix/');
  }
  return oldTopic;
}
```

#### Step 4: Verify Isolation
Test tenant isolation in your deployment:

```dart
void verifyTenantIsolation() {
  final tenant1Topic = TopicValidator.buildCommandTopic(
    'tenant-1/prod', 
    'device-123'
  );
  final tenant2Topic = TopicValidator.buildCommandTopic(
    'tenant-2/prod', 
    'device-123'
  );
  
  assert(tenant1Topic != tenant2Topic);
  assert(TopicValidator.extractPrefix(tenant1Topic) == 'tenant-1/prod');
  assert(TopicValidator.extractPrefix(tenant2Topic) == 'tenant-2/prod');
  
  print('Tenant isolation verified ✓');
}
```

## Validation Rules Reference

### Topic Prefix Validation
- **Length**: ≤50 UTF-8 bytes
- **Characters**: `[A-Za-z0-9_/-]` only
- **Format**: No leading/trailing slashes, no MQTT wildcards (`+`, `#`)
- **Normalization**: Automatic trimming and slash cleanup

### Client ID Validation  
- **Length**: ≤128 UTF-8 bytes
- **Characters**: `[A-Za-z0-9_-]` only (no forward slash)
- **Format**: No MQTT wildcards (`+`, `#`)

### Topic Length Validation
- **Total Length**: ≤100 UTF-8 bytes for complete topics
- **UTF-8 Aware**: Properly handles Unicode characters

### Canonical Topic Formats
- **Command**: `{prefix}/{client_id}/cmd`
- **Response**: `{prefix}/{client_id}/res`  
- **Replication**: `{prefix}/replication/events`

## Error Handling

Common validation errors and solutions:

```dart
// Empty prefix
try {
  TopicValidator.validatePrefix('');
} catch (ArgumentError e) {
  print(e.message); // "Topic prefix cannot be empty"
}

// Invalid characters
try {
  TopicValidator.validatePrefix('tenant@invalid');
} catch (ArgumentError e) {
  print(e.message); // "Topic prefix contains invalid characters"
}

// MQTT wildcards
try {
  TopicValidator.validatePrefix('tenant+dangerous');
} catch (ArgumentError e) {
  print(e.message); // "Topic prefix cannot contain MQTT wildcard '+'"
}

// Too long
try {
  TopicValidator.validatePrefix('a' * 51);
} catch (ArgumentError e) {
  print(e.message); // "Topic prefix too long: 51 UTF-8 bytes. Maximum allowed: 50 bytes"
}

// Client ID with slash
try {
  TopicValidator.validateClientId('device/invalid');
} catch (ArgumentError e) {
  print(e.message); // "Client ID cannot contain forward slash (/)"
}
```

## Security Considerations

### Multi-Tenant Data Isolation
- Prefixes create strong boundaries between tenants
- MQTT ACLs enforce server-side access control
- Client-side validation prevents accidental cross-tenant access

### Wildcard Prevention
- Blocks `+` and `#` in prefixes and client IDs
- Prevents subscription escalation attacks
- Ensures predictable topic structures

### Length Limits
- UTF-8 byte length validation prevents buffer overflows
- Reasonable limits prevent resource exhaustion
- Compatible with MQTT broker limits

## Performance Considerations

### Validation Overhead
- Client-side validation is O(n) where n is string length
- UTF-8 byte length calculation has minimal overhead
- Validation is performed once at configuration time

### Topic Generation
- Topic building is O(1) string concatenation
- No regex or complex parsing required
- Optimized for mobile device constraints

### Memory Usage
- No persistent state in TopicValidator (stateless utility)
- Minimal memory overhead for validation
- Efficient UTF-8 encoding operations

## Testing

The implementation includes comprehensive tests:

### Unit Tests
- `test/mqtt/topic_validator_test.dart`: Core validation logic
- All validation rules, edge cases, UTF-8 handling
- Multi-tenant scenarios and security boundary testing

### Integration Tests  
- `test/mqtt/topic_validator_integration_test.dart`: End-to-end scenarios
- MerkleKVConfig integration testing
- TopicScheme backward compatibility verification
- Complete multi-tenant isolation validation

### Running Tests
```bash
cd packages/merkle_kv_core
dart test test/mqtt/topic_validator_test.dart
dart test test/mqtt/topic_validator_integration_test.dart
```

## API Reference

### TopicValidator Class

#### Static Methods
- `validatePrefix(String prefix)`: Validates topic prefix
- `validateClientId(String clientId)`: Validates client identifier
- `buildTopic(String prefix, String clientId, TopicType type)`: Builds canonical topic
- `buildCommandTopic(String prefix, String clientId)`: Convenience method for command topics
- `normalizePrefix(String prefix)`: Normalizes prefix format
- `isValidTopic(String topic)`: Checks if topic is valid and canonical
- `extractPrefix(String topic)`: Extracts prefix from canonical topic
- `getUtf8ByteLength(String text)`: Calculates UTF-8 byte length

#### Enums
- `TopicType`: `command`, `response`, `replication`

### Enhanced APIs

#### MerkleKVConfig
- Automatic prefix and client ID validation during construction
- Throws `ArgumentError` for invalid configurations

#### TopicScheme  
- Enhanced validation while maintaining API compatibility
- Delegates to TopicValidator for consistent validation

## Support

For questions about multi-tenant configuration or validation issues:

1. Check validation error messages for specific guidance
2. Review the migration guide for upgrade scenarios
3. Verify MQTT broker ACL configuration matches your tenant structure
4. Run the included tests to validate your setup

## Changelog

### Version 1.0.0
- Initial implementation of TopicValidator
- Multi-tenant isolation support
- UTF-8 byte length validation
- MerkleKVConfig and TopicScheme integration
- Comprehensive test coverage
- Documentation and migration guide