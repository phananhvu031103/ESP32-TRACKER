import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/tracker_data.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );

    const InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsIOS,
        );

    await flutterLocalNotificationsPlugin.initialize(initializationSettings);

    // Request permissions for Android 13+
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
  }

  Future<void> showNotification({
    required String title,
    required String body,
  }) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
          'esp32_tracker_channel',
          'ESP32 Tracker',
          channelDescription: 'Thông báo từ thiết bị tracker',
          importance: Importance.high,
          priority: Priority.high,
          showWhen: true,
        );

    const DarwinNotificationDetails iOSPlatformChannelSpecifics =
        DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        );

    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: iOSPlatformChannelSpecifics,
    );

    await flutterLocalNotificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      platformChannelSpecifics,
    );
  }

  Future<void> checkAndShowAlerts(
    TrackerData data,
    TrackerData? previousData,
  ) async {
    // Kiểm tra thay đổi alarm_stage
    if (previousData == null || data.alarmStage != previousData.alarmStage) {
      if (data.alarmStage == 'WARNING') {
        await showNotification(
          title: '⚠️ Cảnh báo',
          body: 'Thiết bị đang ở trạng thái cảnh báo',
        );
      } else if (data.alarmStage == 'ALERT') {
        await showNotification(
          title: '🚨 Báo động',
          body: 'Thiết bị đang ở trạng thái báo động!',
        );
      } else if (data.alarmStage == 'TRACKING') {
        await showNotification(
          title: '📍 Theo dõi',
          body: 'Thiết bị đang được theo dõi',
        );
      }
    }

    // Kiểm tra motion detected
    if (data.motionDetected &&
        (previousData == null || !previousData.motionDetected)) {
      await showNotification(
        title: '🏃 Phát hiện chuyển động',
        body: 'Thiết bị đã phát hiện chuyển động',
      );
    }

    // Kiểm tra low battery
    if (data.lowBattery && (previousData == null || !previousData.lowBattery)) {
      await showNotification(
        title: '🔋 Pin yếu',
        body: 'Pin thiết bị đang yếu, cần sạc',
      );
    }

    // Kiểm tra GPS invalid
    if (!data.gpsValid && (previousData == null || previousData.gpsValid)) {
      await showNotification(
        title: '📡 Mất tín hiệu GPS',
        body: 'Thiết bị đã mất tín hiệu GPS',
      );
    }
  }
}
