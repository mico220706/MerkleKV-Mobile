#!/bin/bash

# Generate TLS certificates for Mosquitto MQTT broker
# This script creates a Certificate Authority and server certificates

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TLS_DIR="${SCRIPT_DIR}/../config/tls"
DAYS=3650  # 10 years validity
COUNTRY="US"
STATE="California"
CITY="San Francisco"
ORG="MerkleKV Mobile"
OU="Development"

# Create TLS directory if it doesn't exist
mkdir -p "$TLS_DIR"
cd "$TLS_DIR"

echo "🔐 Generating TLS certificates for MerkleKV Mobile MQTT Broker..."

# Generate CA private key
echo "📝 Generating Certificate Authority private key..."
openssl genrsa -out ca.key 4096

# Generate CA certificate
echo "📝 Generating Certificate Authority certificate..."
openssl req -new -x509 -days $DAYS -key ca.key -out ca.crt -subj "/C=$COUNTRY/ST=$STATE/L=$CITY/O=$ORG/OU=$OU/CN=MerkleKV-Mobile-CA"

# Generate server private key
echo "📝 Generating server private key..."
openssl genrsa -out server.key 4096

# Create server certificate signing request
echo "📝 Creating server certificate signing request..."
openssl req -new -key server.key -out server.csr -subj "/C=$COUNTRY/ST=$STATE/L=$CITY/O=$ORG/OU=$OU/CN=localhost"

# Create extensions file for server certificate
cat > server.ext << EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = localhost
DNS.2 = mosquitto
DNS.3 = broker.merkle-kv.local
DNS.4 = *.merkle-kv.local
IP.1 = 127.0.0.1
IP.2 = 0.0.0.0
EOF

# Generate server certificate signed by CA
echo "📝 Generating server certificate..."
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out server.crt -days $DAYS -extensions v3_req -extfile server.ext

# Generate client certificate for testing (optional)
echo "📝 Generating client certificate for testing..."
openssl genrsa -out client.key 4096
openssl req -new -key client.key -out client.csr -subj "/C=$COUNTRY/ST=$STATE/L=$CITY/O=$ORG/OU=$OU/CN=client"
openssl x509 -req -in client.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out client.crt -days $DAYS

# Set proper permissions
chmod 600 *.key
chmod 644 *.crt
chmod 644 *.ext

# Clean up temporary files
rm -f server.csr client.csr server.ext

# Display certificate information
echo ""
echo "✅ TLS certificates generated successfully!"
echo ""
echo "📋 Certificate Information:"
echo "=========================="
echo "CA Certificate: $(pwd)/ca.crt"
echo "Server Certificate: $(pwd)/server.crt"
echo "Server Private Key: $(pwd)/server.key"
echo "Client Certificate: $(pwd)/client.crt (for testing)"
echo "Client Private Key: $(pwd)/client.key (for testing)"
echo ""

# Verify certificates
echo "🔍 Verifying certificates..."
echo "CA Certificate:"
openssl x509 -in ca.crt -text -noout | grep -E "(Subject|Validity)"
echo ""
echo "Server Certificate:"
openssl x509 -in server.crt -text -noout | grep -E "(Subject|Validity|DNS|IP Address)"
echo ""

# Test certificate chain
echo "🔗 Testing certificate chain..."
if openssl verify -CAfile ca.crt server.crt; then
    echo "✅ Server certificate chain is valid"
else
    echo "❌ Server certificate chain validation failed"
    exit 1
fi

if openssl verify -CAfile ca.crt client.crt; then
    echo "✅ Client certificate chain is valid"
else
    echo "❌ Client certificate chain validation failed"
    exit 1
fi

echo ""
echo "🚀 Certificates are ready for use!"
echo ""
echo "📝 Next steps:"
echo "1. Copy ca.crt to your clients for server verification"
echo "2. Use client.crt and client.key for client certificate authentication (if needed)"
echo "3. Start the Mosquitto broker with TLS enabled"
echo ""
echo "💡 For testing with mosquitto_pub/sub:"
echo "mosquitto_pub -h localhost -p 8883 --cafile $TLS_DIR/ca.crt -t test/topic -m 'Hello TLS!'"
