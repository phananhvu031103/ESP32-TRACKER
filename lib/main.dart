import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart'; // Import firebase_options
import 'services/firebase_service.dart';
import 'services/api_service.dart';
import 'services/notification_service.dart';
import 'models/tracker_data.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase với options
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Initialize services
  await NotificationService().initialize();
  await FirebaseService().initialize();

  runApp(
    ChangeNotifierProvider(
      create: (_) => TrackerProvider(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ESP32 Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const TrackerHomePage(),
    );
  }
}

class TrackerProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();
  TrackerData? _currentData;
  TrackerData? _previousData;
  String _connectionStatus = 'Đang tải...';
  final List<TrackerData> _dataHistory = [];
  SharedPreferences? _prefs;
  Timer? _pollingTimer;

  TrackerData? get currentData => _currentData;
  String get connectionStatus => _connectionStatus;
  List<TrackerData> get dataHistory => _dataHistory;

  TrackerProvider() {
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadLastState();
    await _startPolling();
  }

  // ✅ Lưu trạng thái cuối cùng
  Future<void> _saveLastState() async {
    if (_currentData != null && _prefs != null) {
      final jsonString = json.encode(_currentData!.toJson());
      await _prefs!.setString('last_tracker_data', jsonString);
      print('💾 [STATE] Saved last state');
    }
  }

  // ✅ Khôi phục trạng thái khi mở app
  Future<void> _loadLastState() async {
    if (_prefs != null) {
      final jsonString = _prefs!.getString('last_tracker_data');
      if (jsonString != null) {
        try {
          final jsonData = json.decode(jsonString);
          _currentData = TrackerData.fromJson(jsonData);

          // ✅ Kiểm tra nếu dữ liệu quá cũ (> 1 giờ) thì không hiển thị
          final timeDiff = DateTime.now().difference(_currentData!.timestamp);
          if (timeDiff.inHours > 1) {
            print(
              '⚠️ [STATE] Cached data is too old (${timeDiff.inHours}h), clearing...',
            );
            _currentData = null;
            await _prefs!.remove('last_tracker_data');
          } else {
            print(
              '✅ [STATE] Restored last state from ${_currentData!.timestamp}',
            );
            notifyListeners();
          }
        } catch (e) {
          print('❌ [STATE] Error loading last state: $e');
          await _prefs!.remove('last_tracker_data');
        }
      }
    }
  }

  // 🔄 Polling data từ backend API thay vì MQTT
  Future<void> _startPolling() async {
    // Gọi ngay lập tức
    await _fetchDataFromAPI();

    // Sau đó poll mỗi 10 giây
    _pollingTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _fetchDataFromAPI();
    });
  }

  Future<void> _fetchDataFromAPI() async {
    try {
      _connectionStatus = 'Đang tải...';
      notifyListeners();

      final data = await _apiService.getLastState();

      if (data != null) {
        _previousData = _currentData;
        _currentData = data;
        _dataHistory.insert(0, data);
        if (_dataHistory.length > 50) {
          _dataHistory.removeLast();
        }

        // Lưu trạng thái mới
        _saveLastState();

        // Kiểm tra và hiển thị thông báo (chỉ khi app đang mở)
        if (_previousData != null) {
          NotificationService().checkAndShowAlerts(data, _previousData);
        }

        _connectionStatus = 'Đã kết nối';
      } else {
        _connectionStatus = 'Chưa có dữ liệu';
      }
    } catch (e) {
      print('❌ [API] Error fetching data: $e');
      _connectionStatus = 'Lỗi kết nối';
    }

    notifyListeners();
  }

  Future<void> refreshData() async {
    await _fetchDataFromAPI();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }
}

class TrackerHomePage extends StatefulWidget {
  const TrackerHomePage({super.key});

  @override
  State<TrackerHomePage> createState() => _TrackerHomePageState();
}

class _TrackerHomePageState extends State<TrackerHomePage> {
  MapController? _mapController;
  List<Marker> _markers = [];
  double _panelHeightRatio = 1.0; // 1.0 = full screen, 0.5 = nửa màn hình
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
  }

  void _updateMap(TrackerData? data) {
    if (data == null || !data.gpsValid) return;

    final position = LatLng(data.latitude, data.longitude);

    setState(() {
      _markers = [
        Marker(
          point: position,
          width: 80,
          height: 80,
          child: Column(
            children: [
              Icon(
                Icons.location_on,
                size: 40,
                color: data.alarmStage == 'ALERT'
                    ? Colors.red
                    : data.alarmStage == 'WARNING'
                    ? Colors.orange
                    : Colors.green,
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: Text(
                  data.getAlarmStageText(),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ];
    });

    _mapController?.move(position, 15);
  }

  Future<bool> _ensureLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  Future<void> _navigateToDestination(LatLng destination) async {
    // Kiểm tra quyền GPS
    if (!await _ensureLocationPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ứng dụng chưa được cấp quyền GPS')),
        );
      }
      return;
    }

    // Lấy vị trí hiện tại
    Position position;
    try {
      position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không lấy được vị trí hiện tại: $e')),
        );
      }
      return;
    }

    final start = LatLng(position.latitude, position.longitude);

    // Hiện dialog như cũ
    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Chỉ đường'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Vị trí hiện tại:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _buildGPSInfoRow('Vĩ độ', start.latitude.toStringAsFixed(6)),
              const SizedBox(height: 8),
              _buildGPSInfoRow('Kinh độ', start.longitude.toStringAsFixed(6)),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              const Text(
                'Vị trí xe:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _buildGPSInfoRow(
                'Vĩ độ',
                destination.latitude.toStringAsFixed(6),
              ),
              const SizedBox(height: 8),
              _buildGPSInfoRow(
                'Kinh độ',
                destination.longitude.toStringAsFixed(6),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Hủy'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _openGoogleMaps(start, destination);
              },
              icon: const Icon(Icons.directions),
              label: const Text('Mở Google Maps'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _openGoogleMaps(LatLng start, LatLng destination) async {
    final intentUrl = Uri.parse(
      "google.navigation:q=${destination.latitude},${destination.longitude}&mode=d",
    );

    if (await canLaunchUrl(intentUrl)) {
      await launchUrl(intentUrl, mode: LaunchMode.externalApplication);
      return;
    }

    final fallbackUrl = Uri.parse(
      "https://www.google.com/maps/dir/?api=1"
      "&origin=${start.latitude},${start.longitude}"
      "&destination=${destination.latitude},${destination.longitude}"
      "&travelmode=driving",
    );

    if (await canLaunchUrl(fallbackUrl)) {
      await launchUrl(fallbackUrl, mode: LaunchMode.externalApplication);
      return;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Không mở được Google Maps")),
      );
    }
  }

  Widget _buildGPSInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.copy, size: 18),
          onPressed: () {
            // Copy to clipboard
            final text = '$label: $value';
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Đã copy: $text')));
          },
          tooltip: 'Copy',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight =
        MediaQuery.of(context).size.height -
        MediaQuery.of(context).padding.top -
        kToolbarHeight;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ESP32 Tracker'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          Consumer<TrackerProvider>(
            builder: (context, provider, child) {
              return IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () => provider.refreshData(),
                tooltip: 'Làm mới dữ liệu',
              );
            },
          ),
        ],
      ),
      body: Consumer<TrackerProvider>(
        builder: (context, provider, child) {
          final data = provider.currentData;
          final hasGPS = data != null && data.gpsValid;

          WidgetsBinding.instance.addPostFrameCallback((_) {
            _updateMap(data);
          });

          return Stack(
            children: [
              // 🗺️ MAP NỀN (chỉ hiện khi có GPS)
              if (hasGPS)
                Positioned.fill(
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: LatLng(data.latitude, data.longitude),
                      initialZoom: 15,
                      minZoom: 5,
                      maxZoom: 18,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.example.esp32_alarm_track',
                      ),
                      MarkerLayer(markers: _markers),
                    ],
                  ),
                ),

              // 📊 PANEL THÔNG SỐ (có thể kéo xuống khi có GPS)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                bottom: hasGPS ? screenHeight * (1 - _panelHeightRatio) : 0,
                child: GestureDetector(
                  onVerticalDragUpdate: hasGPS
                      ? (details) {
                          setState(() {
                            _isDragging = true;
                            // Kéo xuống = giảm panel height ratio
                            final delta = details.delta.dy / screenHeight;
                            _panelHeightRatio -= delta;

                            // Giới hạn: tối thiểu 40% màn hình, tối đa 100%
                            if (_panelHeightRatio < 0.4) {
                              _panelHeightRatio = 0.4;
                            }
                            if (_panelHeightRatio > 1.0) {
                              _panelHeightRatio = 1.0;
                            }
                          });
                        }
                      : null,
                  onVerticalDragEnd: hasGPS
                      ? (details) {
                          setState(() {
                            _isDragging = false;
                            // Snap to 40%, 70%, or 100%
                            if (_panelHeightRatio > 0.85) {
                              _panelHeightRatio = 1.0;
                            } else if (_panelHeightRatio > 0.55) {
                              _panelHeightRatio = 0.7;
                            } else {
                              _panelHeightRatio = 0.4;
                            }
                          });
                        }
                      : null,
                  child: AnimatedContainer(
                    duration: _isDragging
                        ? Duration.zero
                        : const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: hasGPS
                          ? const BorderRadius.only(
                              bottomLeft: Radius.circular(20),
                              bottomRight: Radius.circular(20),
                            )
                          : BorderRadius.zero,
                      boxShadow: hasGPS
                          ? [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 10,
                                offset: const Offset(0, 5),
                              ),
                            ]
                          : null,
                    ),
                    child: Column(
                      children: [
                        // Status Bar
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: provider.connectionStatus == 'Đã kết nối'
                                ? Colors.green
                                : Colors.orange,
                            borderRadius: hasGPS
                                ? const BorderRadius.only(
                                    bottomLeft: Radius.circular(20),
                                    bottomRight: Radius.circular(20),
                                  )
                                : BorderRadius.zero,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                provider.connectionStatus == 'Đã kết nối'
                                    ? Icons.check_circle
                                    : Icons.warning,
                                color: Colors.white,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                provider.connectionStatus,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Drag Handle (chỉ hiện khi có GPS)
                        if (hasGPS)
                          Container(
                            margin: const EdgeInsets.symmetric(vertical: 8),
                            width: 60,
                            height: 5,
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),

                        // Info Panel (scrollable)
                        Expanded(
                          child: data != null
                              ? _buildInfoPanel(data)
                              : const Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      CircularProgressIndicator(),
                                      SizedBox(height: 16),
                                      Text(
                                        'Đang chờ dữ liệu từ thiết bị...',
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                        ),

                        // Navigation Button
                        if (hasGPS)
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: ElevatedButton.icon(
                              onPressed: () => _navigateToDestination(
                                LatLng(data.latitude, data.longitude),
                              ),
                              icon: const Icon(Icons.directions),
                              label: const Text('Chỉ đường'),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),

              // 🗺️ Indicator khi không có GPS
              if (!hasGPS && data != null)
                Positioned(
                  bottom: 20,
                  left: 20,
                  right: 20,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.location_off, color: Colors.white),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'GPS chưa sẵn sàng. Bản đồ sẽ hiển thị khi có tín hiệu GPS.',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildInfoPanel(TrackerData data) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Alarm Stage
          _buildStatusCard(
            title: 'Trạng thái',
            value: data.getAlarmStageText(),
            icon: Icons.emergency,
            color: data.getAlarmStageColor(),
          ),

          const SizedBox(height: 12),

          // Row 1: Motion + Battery
          Row(
            children: [
              Expanded(
                child: _buildStatusItem(
                  'Chuyển động',
                  data.motionDetected
                      ? (data.strongMotion ? 'Mạnh' : 'Có')
                      : 'Không',
                  data.strongMotion
                      ? Icons.warning
                      : data.motionDetected
                      ? Icons.directions_run
                      : Icons.accessibility_new,
                  data.strongMotion
                      ? Colors.red
                      : data.motionDetected
                      ? Colors.orange
                      : Colors.grey,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: _buildBatteryStatusItem(data)),
            ],
          ),

          const SizedBox(height: 12),

          // Row 2: GPS + Owner Present
          Row(
            children: [
              Expanded(
                child: _buildStatusItem(
                  'GPS',
                  data.gpsValid ? 'Tốt' : 'Mất',
                  Icons.gps_fixed,
                  data.gpsValid ? Colors.green : Colors.red,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatusItem(
                  'Chủ xe',
                  data.ownerPresent ? 'Có mặt' : 'Vắng',
                  data.ownerPresent ? Icons.person : Icons.person_off,
                  data.ownerPresent ? Colors.green : Colors.orange,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Row 3: Battery Voltage + Update Time
          Row(
            children: [
              Expanded(
                child: _buildStatusItem(
                  'Điện áp',
                  data.getBatteryVoltageText(),
                  Icons.electrical_services,
                  Colors.purple,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatusItem(
                  'Cập nhật',
                  _formatTime(data.timestamp),
                  Icons.update,
                  Colors.blue,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // GPS Coordinates
          if (data.gpsValid) ...[
            const Divider(),
            const SizedBox(height: 8),
            Text(
              'Tọa độ GPS',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildCoordinateItem(
                    'Vĩ độ',
                    data.latitude.toStringAsFixed(6),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildCoordinateItem(
                    'Kinh độ',
                    data.longitude.toStringAsFixed(6),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBatteryStatusItem(TrackerData data) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: data.getBatteryColor().withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(
            data.batteryLevel <= 20
                ? Icons.battery_alert
                : data.batteryLevel <= 50
                ? Icons.battery_3_bar
                : Icons.battery_full,
            color: data.getBatteryColor(),
            size: 24,
          ),
          const SizedBox(height: 8),
          Text('Pin', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          const SizedBox(height: 4),
          Text(
            data.getBatteryText(),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: data.getBatteryColor(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 2),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusItem(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoordinateItem(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inSeconds < 60) {
      return '${diff.inSeconds}s trước';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}p trước';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h trước';
    } else {
      return '${diff.inDays} ngày trước';
    }
  }
}
