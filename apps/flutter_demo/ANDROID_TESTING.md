# Hướng dẫn testing MerkleKV Mobile trên Android Device

## Bước 1: Chuẩn bị thiết lập ✅
- [x] ADB và Android SDK đã được cài đặt
- [x] Flutter SDK đã sẵn sàng
- [x] Integration tests đã được tạo

## Bước 2: Kết nối Android Device

### Bật Developer Options trên Android:
1. Vào **Settings** > **About phone**
2. Nhấn 7 lần vào **Build number** để kích hoạt Developer options
3. Quay lại **Settings** > **Developer options**
4. Bật **USB debugging**
5. Bật **Stay awake** (để màn hình không tắt khi test)

### Kết nối qua USB:
1. Cắm cable USB từ máy tính vào điện thoại Android
2. Trên điện thoại, chọn **File transfer** hoặc **MTP mode**
3. Nếu xuất hiện popup "Allow USB debugging", chọn **Allow**

### Kiểm tra kết nối:
```bash
adb devices
```

Kết quả mong đợi:
```
List of devices attached
XXXXXXXXXX	device
```

## Bước 3: Thiết lập dự án Flutter

### Di chuyển vào thư mục Flutter Demo:
```bash
cd /workspaces/MerkleKV-Mobile/apps/flutter_demo
```

### Cài đặt dependencies:
```bash
flutter pub get
```

### Kiểm tra devices có sẵn:
```bash
flutter devices
```

## Bước 4: Chạy Integration Tests

### Chạy tất cả integration tests:
```bash
flutter test integration_test/merkle_kv_integration_test.dart
```

### Chạy test với device cụ thể:
```bash
flutter test integration_test/merkle_kv_integration_test.dart -d <device_id>
```

### Debug mode để xem chi tiết:
```bash
flutter test integration_test/merkle_kv_integration_test.dart --verbose
```

## Bước 5: Chạy App trên device

### Build và install app:
```bash
flutter run -d <device_id>
```

### Hoặc build APK để cài đặt thủ công:
```bash
flutter build apk --debug
```

APK sẽ được tạo tại: `build/app/outputs/flutter-apk/app-debug.apk`

## Bước 6: Testing Scenarios

### Test Case 1: Basic Operations
- Set/Get các key-value pairs
- Kiểm tra performance trên thiết bị thật

### Test Case 2: Network Conditions
- Test với WiFi
- Test với mobile data
- Test khi mất kết nối tạm thời

### Test Case 3: Multi-node Replication
- Chạy app trên 2 devices khác nhau
- Test sync giữa các devices

### Test Case 4: Background Operation
- Test app khi chuyển background
- Test khi screen off/on

## Troubleshooting

### Device không được nhận diện:
1. Kiểm tra USB cable
2. Thử USB port khác
3. Restart ADB: `adb kill-server && adb start-server`
4. Kiểm tra driver (Windows) hoặc udev rules (Linux)

### Build errors:
1. Clean project: `flutter clean`
2. Get dependencies: `flutter pub get`
3. Check Android SDK path: `flutter doctor -v`

### Permission errors:
1. Grant all required permissions khi app khởi động
2. Check network permissions for MQTT

## Metrics và Monitoring

Khi chạy tests, theo dõi các metrics:
- Response time cho SET/GET operations
- Network latency
- Memory usage
- Battery consumption
- Replication success rate
- LWW conflict resolution effectiveness

## Next Steps
1. Connect Android device theo hướng dẫn trên
2. Chạy integration tests
3. Kiểm tra performance metrics
4. Test các edge cases (network issues, concurrent access)
5. Benchmark với real-world data
