import 'package:flutter/material.dart';

class TrackerData {
  final double latitude;
  final double longitude;
  final String alarmStage;
  final bool motionDetected;
  final bool lowBattery;
  final bool gpsValid;
  final int batteryLevel;
  final double batteryVoltage;
  final bool ownerPresent;
  final bool mqttConnected;
  final bool strongMotion;
  final DateTime timestamp;
  final DateTime serverTime; // Thời gian backend nhận MQTT (GMT+7)

  TrackerData({
    required this.latitude,
    required this.longitude,
    required this.alarmStage,
    required this.motionDetected,
    required this.lowBattery,
    required this.gpsValid,
    required this.batteryLevel,
    required this.batteryVoltage,
    required this.ownerPresent,
    required this.mqttConnected,
    required this.strongMotion,
    required this.timestamp,
    required this.serverTime,
  });

  factory TrackerData.fromJson(Map<String, dynamic> json) {
    // Chuyển đổi alarm_stage từ int sang string
    String alarmStageText = 'NORMAL';
    int alarmStageInt = json['alarm_stage'] ?? 0;
    switch (alarmStageInt) {
      case 1:
        alarmStageText = 'WARNING';
        break;
      case 2:
        alarmStageText = 'ALERT';
        break;
      case 3:
        alarmStageText = 'TRACKING';
        break;
      default:
        alarmStageText = 'NORMAL';
    }

    // Timestamp từ ESP32 là uptime (không phải Unix timestamp thực)
    DateTime parsedTimestamp;
    if (json['timestamp'] is String) {
      // Chỉ parse string khi load từ SharedPreferences
      try {
        parsedTimestamp = DateTime.parse(json['timestamp']);
      } catch (e) {
        print('[TrackerData] Error parsing timestamp: $e');
        parsedTimestamp = DateTime.now();
      }
    } else {
      // Dữ liệu mới từ MQTT luôn dùng thời gian hiện tại
      parsedTimestamp = DateTime.now();
    }

    // Parse server_time (thời gian backend nhận MQTT) - chuyển từ UTC sang GMT+7
    DateTime parsedServerTime;
    if (json['server_time'] != null) {
      try {
        // Parse UTC time (backend gửi là UTC)
        final utcTime = DateTime.parse(json['server_time']).toUtc();

        // ✅ Ép buộc chuyển sang GMT+7 (không phụ thuộc timezone thiết bị)
        parsedServerTime = utcTime.add(const Duration(hours: 7));

        print('[TrackerData] UTC: $utcTime → GMT+7: $parsedServerTime');
      } catch (e) {
        print('[TrackerData] Error parsing server_time: $e');
        parsedServerTime = DateTime.now();
      }
    } else {
      parsedServerTime = DateTime.now();
    }

    return TrackerData(
      latitude: (json['latitude'] ?? 0.0).toDouble(),
      longitude: (json['longitude'] ?? 0.0).toDouble(),
      alarmStage: alarmStageText,
      motionDetected:
          json['motion_detected'] == 1 || json['motion_detected'] == true,
      lowBattery: json['low_battery'] == 1 || json['low_battery'] == true,
      gpsValid: json['gps_valid'] == 1 || json['gps_valid'] == true,
      batteryLevel: json['battery_percent'] ?? 100,
      batteryVoltage: (json['battery_voltage'] ?? 0.0).toDouble(),
      ownerPresent: json['owner_present'] == 1 || json['owner_present'] == true,
      mqttConnected:
          json['mqtt_connected'] == 1 || json['mqtt_connected'] == true,
      strongMotion: json['strong_motion'] == 1 || json['strong_motion'] == true,
      timestamp: parsedTimestamp,
      serverTime: parsedServerTime,
    );
  }

  // Thêm method toJson để lưu trạng thái
  Map<String, dynamic> toJson() {
    // Chuyển đổi alarm_stage từ string sang int
    int alarmStageInt = 0;
    switch (alarmStage) {
      case 'WARNING':
        alarmStageInt = 1;
        break;
      case 'ALERT':
        alarmStageInt = 2;
        break;
      case 'TRACKING':
        alarmStageInt = 3;
        break;
      default:
        alarmStageInt = 0;
    }

    return {
      'latitude': latitude,
      'longitude': longitude,
      'alarm_stage': alarmStageInt,
      'motion_detected': motionDetected ? 1 : 0,
      'low_battery': lowBattery ? 1 : 0,
      'gps_valid': gpsValid ? 1 : 0,
      'battery_percent': batteryLevel,
      'battery_voltage': batteryVoltage,
      'owner_present': ownerPresent ? 1 : 0,
      'mqtt_connected': mqttConnected ? 1 : 0,
      'strong_motion': strongMotion ? 1 : 0,
      'timestamp': timestamp.toIso8601String(),
      'server_time': serverTime.toIso8601String(),
    };
  }

  String getAlarmStageText() {
    switch (alarmStage) {
      case 'WARNING':
        return 'Cảnh báo';
      case 'ALERT':
        return 'Báo động';
      case 'TRACKING':
        return 'Đang theo dõi';
      default:
        return 'Bình thường';
    }
  }

  String getBatteryText() {
    return '$batteryLevel%';
  }

  String getBatteryVoltageText() {
    return '${batteryVoltage.toStringAsFixed(2)}V';
  }

  Color getBatteryColor() {
    if (batteryLevel <= 20) return const Color(0xFFD32F2F); // Đỏ
    if (batteryLevel <= 50) return const Color(0xFFFFA726); // Cam
    return const Color(0xFF66BB6A); // Xanh lá
  }

  Color getAlarmStageColor() {
    switch (alarmStage) {
      case 'ALERT':
        return Colors.red;
      case 'WARNING':
        return Colors.orange;
      case 'TRACKING':
        return Colors.blue;
      default:
        return Colors.green;
    }
  }
}
