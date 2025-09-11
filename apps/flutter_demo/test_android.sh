#!/bin/bash

echo "🚀 MerkleKV Mobile Android Testing Script"
echo "========================================"

# Set environment variables
export PATH="$PATH:/opt/flutter/bin"
export ANDROID_HOME=/opt/android-sdk
export PATH="$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Bước 1: Kiểm tra thiết lập môi trường${NC}"
echo "-----------------------------------"

# Check Flutter
if command -v flutter &> /dev/null; then
    echo -e "✅ Flutter: $(flutter --version | head -n1)"
else
    echo -e "${RED}❌ Flutter không được tìm thấy${NC}"
    exit 1
fi

# Check ADB
if command -v adb &> /dev/null; then
    echo -e "✅ ADB: $(adb version | head -n1)"
else
    echo -e "${RED}❌ ADB không được tìm thấy${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}Bước 2: Kiểm tra kết nối Android devices${NC}"
echo "----------------------------------------"

# Check connected devices
DEVICES=$(adb devices | grep -v "List of devices attached" | grep -v "^$" | wc -l)

if [ $DEVICES -eq 0 ]; then
    echo -e "${YELLOW}⚠️  Không có Android device nào được kết nối${NC}"
    echo ""
    echo -e "${YELLOW}Hướng dẫn kết nối Android device:${NC}"
    echo "1. Bật Developer Options và USB Debugging trên điện thoại"
    echo "2. Cắm cable USB"
    echo "3. Chấp nhận USB debugging prompt trên điện thoại"
    echo "4. Chạy lại script này"
    echo ""
    echo -e "${BLUE}Để kiểm tra lại, chạy: adb devices${NC}"
    echo ""
    echo -e "${YELLOW}Tiếp tục với emulator hoặc desktop testing...${NC}"
else
    echo -e "✅ Tìm thấy $DEVICES Android device(s):"
    adb devices
fi

echo ""
echo -e "${BLUE}Bước 3: Kiểm tra Flutter devices${NC}"
echo "-------------------------------"
cd /workspaces/MerkleKV-Mobile/apps/flutter_demo
flutter devices

echo ""
echo -e "${BLUE}Bước 4: Cài đặt dependencies${NC}"
echo "----------------------------"
flutter pub get

echo ""
echo -e "${BLUE}Bước 5: Chạy tests có sẵn${NC}"
echo "-------------------------"

# Check if we have connected Android devices
ANDROID_DEVICES=$(flutter devices | grep "android" | wc -l)

if [ $ANDROID_DEVICES -gt 0 ]; then
    echo -e "${GREEN}🎯 Chạy integration tests trên Android device...${NC}"
    flutter test integration_test/merkle_kv_integration_test.dart
else
    echo -e "${YELLOW}⚠️  Không có Android device, chạy unit tests...${NC}"
    # Run unit tests from core package
    cd ../../packages/merkle_kv_core
    flutter test
    cd ../../apps/flutter_demo
fi

echo ""
echo -e "${BLUE}Bước 6: Tạo demo app${NC}"
echo "-------------------"

# Check if we can build for Android
if [ $ANDROID_DEVICES -gt 0 ]; then
    echo -e "${GREEN}🔨 Building APK for testing...${NC}"
    flutter build apk --debug
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ APK đã được tạo tại: build/app/outputs/flutter-apk/app-debug.apk${NC}"
        echo -e "${BLUE}💡 Để cài đặt: adb install build/app/outputs/flutter-apk/app-debug.apk${NC}"
    else
        echo -e "${RED}❌ Build APK thất bại${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  Không có Android device để build APK${NC}"
    echo -e "${BLUE}💡 Có thể chạy trên desktop: flutter run -d linux${NC}"
fi

echo ""
echo -e "${BLUE}Bước 7: Hướng dẫn testing thủ công${NC}"
echo "--------------------------------"

echo -e "${GREEN}Để test MerkleKV Mobile trên Android device:${NC}"
echo ""
echo "1. Đảm bảo device đã được kết nối (adb devices)"
echo "2. Chạy app: flutter run"
echo "3. Test các tính năng:"
echo "   - SET/GET operations"
echo "   - Multi-node replication"
echo "   - Network disconnect/reconnect"
echo "   - Background/foreground switching"
echo ""

echo -e "${GREEN}Để test performance:${NC}"
echo "- Monitor memory usage"
echo "- Check battery consumption"
echo "- Measure response times"
echo "- Test with large datasets"
echo ""

echo -e "${GREEN}Để test replication:${NC}"
echo "- Run app on 2 different devices"
echo "- Test data sync between devices"
echo "- Test conflict resolution (LWW)"
echo ""

echo -e "${BLUE}🎉 Script hoàn thành! Sẵn sàng testing trên Android device.${NC}"
echo ""
echo -e "${YELLOW}📖 Xem thêm hướng dẫn chi tiết trong: ANDROID_TESTING.md${NC}"
