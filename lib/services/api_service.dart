import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/tracker_data.dart';

class ApiService {
  static const String baseUrl = 'https://esp32-mqtt-backend.onrender.com';

  Future<TrackerData?> getLastState() async {
    try {
      print('[API] 📡 Fetching last state from backend...');

      final response = await http
          .get(
            Uri.parse('$baseUrl/api/last-state'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        print('[API] ✅ Data received: ${response.body}');

        return TrackerData.fromJson(jsonData);
      } else if (response.statusCode == 404) {
        print('[API] ⚠️ No data available yet');
        return null;
      } else {
        print('[API] ❌ HTTP Error: ${response.statusCode}');
        throw Exception('Failed to load data: ${response.statusCode}');
      }
    } catch (e) {
      print('[API] ❌ Error: $e');
      throw Exception('Network error: $e');
    }
  }

  Future<bool> registerFCMToken(String token) async {
    try {
      print('[API] 📱 Registering FCM token...');

      final response = await http
          .post(
            Uri.parse('$baseUrl/api/register-token'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'token': token,
              'platform': 'flutter',
              'timestamp': DateTime.now().toIso8601String(),
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        print('[API] ✅ FCM token registered successfully');
        return true;
      } else {
        print('[API] ❌ Failed to register token: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('[API] ❌ Error registering token: $e');
      return false;
    }
  }
}
