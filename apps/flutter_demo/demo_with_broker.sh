#!/bin/bash

echo "🚀 Demo MerkleKV Mobile với MQTT Broker Local"
echo "============================================="

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    echo "❌ Docker không được tìm thấy. Cần Docker để chạy MQTT broker."
    exit 1
fi

echo "📡 Khởi động MQTT Broker (Mosquitto)..."
cd /workspaces/MerkleKV-Mobile/broker/mosquitto

# Start mosquitto broker in background
docker-compose up -d

if [ $? -eq 0 ]; then
    echo "✅ MQTT Broker đã khởi động thành công"
    
    # Wait for broker to be ready
    echo "⏳ Đợi MQTT broker sẵn sàng..."
    sleep 5
    
    # Show broker status
    docker-compose ps
    
    echo ""
    echo "🔧 Thông tin MQTT Broker:"
    echo "  - Host: localhost"
    echo "  - Port: 1883 (non-TLS)"
    echo "  - Port: 8883 (TLS)"
    echo "  - WebSocket: 9001"
    echo ""
    
    echo "🧪 Chạy integration tests với MQTT broker..."
    cd /workspaces/MerkleKV-Mobile/packages/merkle_kv_core
    
    # Run integration tests that require MQTT broker
    flutter test test/replication/integration_test.dart
    
    echo ""
    echo "📱 Để test trên Android device:"
    echo "1. Kết nối Android device qua USB"
    echo "2. Bật USB debugging"
    echo "3. Chạy: cd /workspaces/MerkleKV-Mobile/apps/flutter_demo"
    echo "4. Chạy: flutter run"
    echo ""
    echo "🛑 Để dừng MQTT broker:"
    echo "   cd /workspaces/MerkleKV-Mobile/broker/mosquitto && docker-compose down"
    
else
    echo "❌ Không thể khởi động MQTT broker"
    exit 1
fi
