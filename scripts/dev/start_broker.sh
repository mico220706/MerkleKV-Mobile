#!/bin/bash

# Start the MerkleKV Mobile MQTT broker
# This script starts the broker with proper initialization

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BROKER_DIR="$PROJECT_ROOT/broker/mosquitto"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Starting MerkleKV Mobile MQTT Broker${NC}"
echo "========================================"

cd "$BROKER_DIR"

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}❌ Docker is not running. Please start Docker first.${NC}"
    exit 1
fi

# Check if docker-compose is available
if ! command -v docker-compose &> /dev/null; then
    echo -e "${RED}❌ docker-compose not found. Please install docker-compose.${NC}"
    exit 1
fi

# Generate certificates if they don't exist
if [ ! -f "config/tls/ca.crt" ]; then
    echo -e "${YELLOW}🔐 TLS certificates not found. Generating...${NC}"
    ./scripts/generate_certs.sh
fi

# Create users if passwd file doesn't exist
if [ ! -f "config/passwd" ]; then
    echo -e "${YELLOW}👥 User database not found. Creating default users...${NC}"
    # Create empty password file first
    touch config/passwd
    # Create default users non-interactively
    echo "4" | ./scripts/create_users.sh > /dev/null 2>&1 || true
fi

# Create necessary directories
mkdir -p data log

# Set proper permissions
chmod 755 data log
chmod 644 config/mosquitto.conf config/acl.conf
if [ -f "config/passwd" ]; then
    chmod 600 config/passwd
fi

# Start the broker
echo -e "${YELLOW}🐳 Starting MQTT broker containers...${NC}"
docker-compose up -d

# Wait for the broker to be ready
echo -e "${YELLOW}⏳ Waiting for MQTT broker to be ready...${NC}"
sleep 5

# Health check
for i in {1..30}; do
    if docker-compose ps mosquitto | grep -q "Up"; then
        echo -e "${GREEN}✅ MQTT broker is running${NC}"
        break
    fi
    
    if [ $i -eq 30 ]; then
        echo -e "${RED}❌ MQTT broker failed to start within 30 seconds${NC}"
        docker-compose logs mosquitto
        exit 1
    fi
    
    sleep 1
done

# Test connectivity
echo -e "${YELLOW}🔍 Testing MQTT connectivity...${NC}"
if command -v mosquitto_pub &> /dev/null; then
    if mosquitto_pub -h localhost -p 1883 -u test_user -P test_pass -t test/startup -m "broker_started" -q 1 > /dev/null 2>&1; then
        echo -e "${GREEN}✅ MQTT broker connectivity test passed${NC}"
    else
        echo -e "${YELLOW}⚠️  MQTT broker authentication test failed (this is normal if users haven't been created)${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  mosquitto_pub not available for connectivity test${NC}"
fi

# Show broker status
echo ""
echo -e "${BLUE}📊 Broker Status${NC}"
echo "================"
docker-compose ps

echo ""
echo -e "${GREEN}🎉 MerkleKV Mobile MQTT Broker is running!${NC}"
echo ""
echo -e "${YELLOW}📝 Connection Details:${NC}"
echo "  MQTT Port (non-TLS): 1883"
echo "  MQTT Port (TLS):     8883"
echo "  WebSocket Port:      9001"
echo ""
echo -e "${YELLOW}📝 Useful Commands:${NC}"
echo "  View logs:    docker-compose logs -f mosquitto"
echo "  Stop broker:  docker-compose down"
echo "  Restart:      docker-compose restart mosquitto"
echo ""
echo -e "${YELLOW}📝 Test Commands:${NC}"
echo "  Subscribe:    mosquitto_sub -h localhost -p 1883 -t test/topic"
echo "  Publish:      mosquitto_pub -h localhost -p 1883 -t test/topic -m 'Hello World'"
echo ""
