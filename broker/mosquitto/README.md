# MerkleKV Mobile MQTT Broker

This directory contains a production-ready MQTT broker configuration for MerkleKV Mobile using Eclipse Mosquitto.

## 🚀 Quick Start

```bash
# Generate TLS certificates
./scripts/generate_certs.sh

# Create default users
./scripts/create_users.sh

# Start the broker
docker-compose up -d

# View logs
docker-compose logs -f mosquitto
```

## 📁 Directory Structure

```
mosquitto/
├── config/
│   ├── mosquitto.conf      # Main broker configuration
│   ├── acl.conf           # Access Control List
│   ├── passwd             # User credentials (auto-generated)
│   └── tls/               # TLS certificates (auto-generated)
├── scripts/
│   ├── generate_certs.sh  # TLS certificate generation
│   └── create_users.sh    # User management
├── docker-compose.yml     # Docker orchestration
├── Dockerfile            # Custom Mosquitto image
└── README.md             # This file
```

## 🔒 Security Features

- **TLS Encryption**: All connections can use TLS
- **Access Control**: Topic-level permissions via ACL
- **Authentication**: Username/password authentication
- **Certificate Support**: Client certificate authentication

## 🌐 Connection Details

| Service | Port | Protocol | Security |
|---------|------|----------|----------|
| MQTT    | 1883 | TCP      | Plain    |
| MQTTS   | 8883 | TCP      | TLS      |
| WebSocket | 9001 | HTTP   | Plain    |

## 👥 Default Users

| Username | Password | Permissions |
|----------|----------|-------------|
| admin | (generated) | Full access |
| monitor | (generated) | Read-only monitoring |
| test_user | test_pass | Limited testing |
| developer | dev_pass | Development access |

## 🔧 Configuration

### Environment Variables

```bash
# Set in docker-compose.yml or .env file
TZ=UTC                    # Timezone
MOSQUITTO_LOG_LEVEL=info  # Log level
```

### Custom Configuration

Edit `config/mosquitto.conf` to modify broker settings:

- Connection limits
- Message size limits
- Persistence settings
- Logging configuration

## 📊 Monitoring

The broker includes health checks and monitoring endpoints:

```bash
# Check broker status
docker-compose ps

# View real-time logs
docker-compose logs -f mosquitto

# Test connectivity
mosquitto_pub -h localhost -p 1883 -u test_user -P test_pass -t test/topic -m "Hello"
mosquitto_sub -h localhost -p 1883 -u test_user -P test_pass -t test/topic
```

## 🔍 Troubleshooting

### Common Issues

1. **Permission Denied**
   ```bash
   # Fix file permissions
   chmod 600 config/passwd
   chmod 644 config/mosquitto.conf config/acl.conf
   ```

2. **Certificate Errors**
   ```bash
   # Regenerate certificates
   rm -rf config/tls/
   ./scripts/generate_certs.sh
   ```

3. **Connection Refused**
   ```bash
   # Check if broker is running
   docker-compose ps
   
   # Check logs for errors
   docker-compose logs mosquitto
   ```

### Debug Mode

Enable verbose logging:

```bash
# Edit config/mosquitto.conf
log_type debug
log_type error
log_type warning
log_type notice
log_type information

# Restart broker
docker-compose restart mosquitto
```

## 🔄 Production Deployment

For production use:

1. **Change Default Passwords**
   ```bash
   ./scripts/create_users.sh
   # Choose option 1 and set strong passwords
   ```

2. **Use Valid TLS Certificates**
   - Replace auto-generated certificates with CA-signed certificates
   - Update certificate paths in `mosquitto.conf`

3. **Configure Firewall**
   - Only expose necessary ports
   - Use VPN or private networks when possible

4. **Enable Monitoring**
   ```bash
   # Start with monitoring stack
   docker-compose --profile monitoring up -d
   ```

5. **Backup Configuration**
   - Backup `config/` directory
   - Include user passwords and certificates
   - Set up automated backups for persistent data

## 📚 Additional Resources

- [Eclipse Mosquitto Documentation](https://mosquitto.org/documentation/)
- [MQTT Protocol Specification](https://mqtt.org/mqtt-specification/)
- [MerkleKV Mobile Documentation](../../docs/)
