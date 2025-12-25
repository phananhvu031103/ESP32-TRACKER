# Hướng dẫn cấu hình Firebase cho ESP32 Alarm Tracker

## 📋 Các bước cần thực hiện

### 1. Cài đặt công cụ

```bash
# Cài Firebase CLI
npm install -g firebase-tools

# Cài FlutterFire CLI
dart pub global activate flutterfire_cli
```

### 2. Tạo dự án Firebase

1. Truy cập [Firebase Console](https://console.firebase.google.com)
2. Tạo dự án mới với tên `esp32-tracker` (hoặc tên bạn muốn)
3. Bật Google Analytics (tùy chọn)

### 3. Thêm ứng dụng Android

1. Trong Firebase Console, chọn "Add app" → Android
2. **Package name**: `com.example.esp32_alarm_track`
3. **App nickname**: `ESP32 Tracker Android`
4. **Debug SHA-1**: Lấy bằng lệnh:
   ```bash
   cd android
   ./gradlew signingReport
   ```
5. Tải file `google-services.json` và đặt vào `android/app/`

### 4. Cấu hình Firebase Cloud Messaging

1. Trong Firebase Console → Project Settings → Cloud Messaging
2. Tạo server key cho backend (nếu chưa có)
3. Bật FCM API v1

### 5. Cập nhật firebase_options.dart

Chạy lệnh sau để tự động tạo cấu hình:

```bash
flutterfire configure
```

Hoặc thay thế thủ công các giá trị trong `lib/firebase_options.dart`:

- `YOUR_PROJECT_ID`: ID dự án Firebase
- `YOUR_ANDROID_API_KEY`: Web API Key từ Project Settings
- `YOUR_ANDROID_APP_ID`: App ID từ google-services.json
- `YOUR_SENDER_ID`: Project Number từ Project Settings

### 6. Kiểm tra cấu hình

1. Chạy ứng dụng: `flutter run`
2. Kiểm tra logs để xem FCM token được tạo
3. Gửi test notification từ Firebase Console

## 🔧 Cấu hình đã hoàn thành

✅ **Android Build Configuration**

- Firebase plugins đã được thêm
- Dependencies đã được cấu hình
- Min SDK 21 (yêu cầu Firebase)

✅ **Android Manifest**

- Permissions cho FCM và location
- FCM service declarations
- Notification channel mặc định

✅ **Flutter Dependencies**

- firebase_core: ^2.24.2
- firebase_messaging: ^14.7.10

✅ **Services đã được tạo**

- `FirebaseService`: Xử lý FCM tokens và notifications
- `NotificationService`: Hiển thị local notifications

## 🚨 Lưu ý quan trọng

1. **File google-services.json**: Phải được đặt chính xác tại `android/app/google-services.json`

2. **Package name**: Phải khớp với:

   - `android/app/build.gradle.kts`: `applicationId`
   - Firebase Console app registration
   - `android/app/src/main/AndroidManifest.xml`: package name

3. **Backend integration**:
   - FCM tokens được gửi tự động đến backend tại URL:
     `https://esp32-mqtt-backend.onrender.com/api/register-token`
   - Đảm bảo backend đã sẵn sàng nhận tokens

## 🧪 Test Firebase

### Test FCM từ Firebase Console:

1. Firebase Console → Cloud Messaging → Send your first message
2. Nhập title và body
3. Chọn app Android
4. Send test message

### Test từ code:

```dart
// In FirebaseService
print('FCM Token: ${FirebaseService().fcmToken}');
```

## 🔍 Troubleshooting

### Lỗi thường gặp:

1. **"google-services.json not found"**

   - Đảm bảo file ở đúng vị trí `android/app/google-services.json`

2. **"FCM token is null"**

   - Kiểm tra internet connection
   - Kiểm tra Google Play Services (Android)

3. **"Build failed with Firebase"**
   - Clean build: `flutter clean && flutter pub get`
   - Kiểm tra version compatibility

### Debug logs:

```bash
flutter run --verbose
adb logcat | grep -i firebase
```
