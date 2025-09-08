# Use official Eclipse Mosquitto image as base
FROM eclipse-mosquitto:2.0

# Install additional tools for certificate management
USER root

# Install necessary packages
RUN apk add --no-cache \
    openssl \
    bash \
    curl \
    gettext

# Create necessary directories
RUN mkdir -p /mosquitto/config/tls \
    && mkdir -p /mosquitto/data \
    && mkdir -p /mosquitto/log \
    && chown -R mosquitto:mosquitto /mosquitto

# Copy configuration files
COPY config/mosquitto.conf /mosquitto/config/
COPY config/acl.conf /mosquitto/config/
COPY config/passwd /mosquitto/config/

# Copy scripts
COPY scripts/ /mosquitto/scripts/
RUN chmod +x /mosquitto/scripts/*.sh

# Copy TLS certificates (if they exist)
COPY config/tls/ /mosquitto/config/tls/

# Set proper permissions
RUN chown -R mosquitto:mosquitto /mosquitto/config \
    && chown -R mosquitto:mosquitto /mosquitto/data \
    && chown -R mosquitto:mosquitto /mosquitto/log \
    && chmod 644 /mosquitto/config/mosquitto.conf \
    && chmod 644 /mosquitto/config/acl.conf \
    && chmod 600 /mosquitto/config/passwd

# Switch back to mosquitto user
USER mosquitto

# Expose MQTT ports
EXPOSE 1883 8883 9001

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
  CMD mosquitto_sub -h localhost -t '$SYS/broker/uptime' -C 1 | grep -q '[0-9]' || exit 1

# Use custom entrypoint if needed
# COPY docker-entrypoint.sh /usr/local/bin/
# ENTRYPOINT ["docker-entrypoint.sh"]

# Default command
CMD ["/usr/sbin/mosquitto", "-c", "/mosquitto/config/mosquitto.conf"]
