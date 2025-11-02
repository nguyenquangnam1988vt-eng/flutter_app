import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:vibration/vibration.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

const MethodChannel _nativeChannel = MethodChannel('driver_monitor/native');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Driver Phone Monitor',
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFF121212),
      ),
      home: const Dashboard(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});
  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  double x = 0, y = 0, z = 0;
  double speed = 0;
  bool alert = false;
  bool monitoringBackground = false;

  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<Position>? _posSub;

  final FlutterLocalNotificationsPlugin _localNotif = FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    _initNotifications();
    _setupNativeCallback();
    _requestPermissions();
    _listenSensors();
    _listenLocation();
  }

  @override
  void dispose() {
    _accelSub?.cancel();
    _posSub?.cancel();
    super.dispose();
  }

  // --- Notification setup ---
  Future<void> _initNotifications() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iOS = DarwinInitializationSettings();
    await _localNotif.initialize(const InitializationSettings(android: android, iOS: iOS));
  }

  void _setupNativeCallback() {
    _nativeChannel.setMethodCallHandler((call) async {
      if (call.method == 'backgroundSpeedAlert') {
        final args = call.arguments as Map<dynamic, dynamic>?;
        final bgSpeed = (args?['speed'] ?? 0).toDouble();
        await _showLocalAlertFromNative(bgSpeed);
      }
    });
  }

  Future<void> _showLocalAlertFromNative(double speed) async {
    const androidDetails = AndroidNotificationDetails(
      'bg_alerts',
      'Background Alerts',
      channelDescription: 'Cảnh báo khi vượt ngưỡng tốc độ trong nền',
      importance: Importance.max,
      priority: Priority.high,
    );
    await _localNotif.show(
      999,
      'Cảnh báo nền',
      'Tốc độ ${speed.toStringAsFixed(1)} km/h — mở app để kiểm tra',
      const NotificationDetails(android: androidDetails),
    );
    if (await Vibration.hasVibrator() ?? false) Vibration.vibrate(duration: 1000);
  }

  // --- Permissions ---
  Future<void> _requestPermissions() async {
    await Permission.locationWhenInUse.request();
    await Permission.sensors.request();
  }

  // --- Sensor ---
  void _listenSensors() {
    _accelSub = accelerometerEvents.listen((event) {
      setState(() {
        x = event.x;
        y = event.y;
        z = event.z;
      });
      _checkAlert();
    });
  }

  // --- GPS ---
  void _listenLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    if (p == LocationPermission.deniedForever) return;

    const settings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 1,
    );

    _posSub = Geolocator.getPositionStream(locationSettings: settings).listen((Position pos) {
      setState(() {
        speed = (pos.speed >= 0) ? pos.speed * 3.6 : 0.0;
      });
      _checkAlert();
    });
  }

  // --- Background Monitor ---
  Future<void> startBackgroundMonitoring() async {
    try {
      await _nativeChannel.invokeMethod('startBackground');
      setState(() => monitoringBackground = true);
    } on PlatformException catch (e) {
      debugPrint('startBackground error: $e');
    }
  }

  Future<void> stopBackgroundMonitoring() async {
    try {
      await _nativeChannel.invokeMethod('stopBackground');
      setState(() => monitoringBackground = false);
    } on PlatformException catch (e) {
      debugPrint('stopBackground error: $e');
    }
  }

  // --- Logic ---
  void _checkAlert() async {
    final bool isTilted = y.abs() > 4.0; // nghiêng quá 4 theo trục Y
    final bool overSpeed = speed > 30.0;

    if (isTilted && overSpeed) {
      if (!alert) {
        if (await Vibration.hasVibrator() ?? false) Vibration.vibrate(duration: 1000);
      }
      setState(() => alert = true);
    } else {
      setState(() => alert = false);
    }
  }

  // --- UI helper ---
  Color getAlertColor() => alert ? Colors.redAccent : Colors.greenAccent;

  Widget _buildCard(String title, List<Widget> children) {
    return Card(
      color: const Color(0xFF1E2933),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 10),
          ...children,
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Driver Phone Monitor")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Alert Banner
            AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              height: 60,
              width: double.infinity,
              decoration: BoxDecoration(color: getAlertColor(), borderRadius: BorderRadius.circular(12)),
              alignment: Alignment.center,
              child: Text(
                alert ? "⚠️ Cảnh báo: Không sử dụng điện thoại!" : "✅ An toàn",
                style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
            const SizedBox(height: 16),

            // Cảm biến
            _buildCard("Cảm biến gia tốc", [
              Text("x = ${x.toStringAsFixed(2)}", style: const TextStyle(color: Colors.white)),
              Text("y = ${y.toStringAsFixed(2)}", style: const TextStyle(color: Colors.white)),
              Text("z = ${z.toStringAsFixed(2)}", style: const TextStyle(color: Colors.white)),
            ]),
            const SizedBox(height: 16),

            // Tốc độ
            _buildCard("Tốc độ (km/h)", [
              Text("${speed.toStringAsFixed(1)} km/h",
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: (speed / 100).clamp(0, 1),
                color: alert ? Colors.redAccent : Colors.greenAccent,
                backgroundColor: Colors.grey[700],
                minHeight: 8,
              ),
            ]),
            const SizedBox(height: 16),

            // Buttons
            Row(children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: monitoringBackground ? null : startBackgroundMonitoring,
                  child: const Text("Bắt đầu giám sát nền"),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: monitoringBackground ? stopBackgroundMonitoring : null,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                  child: const Text("Dừng giám sát nền"),
                ),
              ),
            ]),
            const SizedBox(height: 16),

            const Text(
              "Ghi chú: iOS cần bật Background Modes → Location updates và cấp quyền “Allow Always”.",
              style: TextStyle(color: Colors.white54, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}