import 'dart:async';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:vibration/vibration.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';

const MethodChannel _nativeChannel = MethodChannel('driver_monitor/native');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initNotifications();
  runApp(MyApp());
}

Future<void> _initNotifications() async {
  const android = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: android);
  await FlutterLocalNotificationsPlugin().initialize(initSettings);
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Driver Phone Monitor',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.dark,
      ),
      home: Dashboard(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class Dashboard extends StatefulWidget {
  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  double x = 0, y = 0, z = 0;
  double speed = 0;
  bool alert = false;
  bool monitoringBackground = false;
  bool screenOn = true; // giả lập

  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<Position>? _posSub;
  final FlutterLocalNotificationsPlugin _localNotif = FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _setupNativeCallback();
    _listenSensors();
    _listenLocation();
  }

  Future<void> _requestPermissions() async {
    await Permission.locationWhenInUse.request();
    await Permission.sensors.request();
    await Permission.notification.request();
  }

  void _setupNativeCallback() {
    _nativeChannel.setMethodCallHandler((call) async {
      if (call.method == 'backgroundSpeedAlert') {
        final args = call.arguments as Map<dynamic, dynamic>?;
        final speed = (args?['speed'] ?? 0).toDouble();
        _showLocalAlert(speed);
      }
    });
  }

  Future<void> _showLocalAlert(double spd) async {
    const androidDetails = AndroidNotificationDetails(
      'driver_alerts',
      'Driver Alerts',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
    );
    await _localNotif.show(
      999,
      '⚠️ Cảnh báo',
      'Phát hiện sử dụng điện thoại khi di chuyển ở ${spd.toStringAsFixed(1)} km/h',
      NotificationDetails(android: androidDetails),
    );
    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(duration: 1000);
    }
  }

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

  void _listenLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();

    if (p == LocationPermission.denied || p == LocationPermission.deniedForever) return;

    const settings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 1,
    );

    _posSub = Geolocator.getPositionStream(locationSettings: settings).listen((Position pos) {
      setState(() {
        speed = (pos.speed >= 0) ? pos.speed * 3.6 : 0.0; // m/s -> km/h
      });
      _checkAlert();
    });
  }

  void _checkAlert() async {
    bool isTilted = y.abs() > 4; // cảm biến nghiêng theo trục Y
    bool overSpeed = speed > 30;

    if (isTilted && screenOn && overSpeed) {
      if (!alert) {
        await _showLocalAlert(speed);
      }
      setState(() => alert = true);
    } else {
      setState(() => alert = false);
    }
  }

  Future<void> startBackgroundMonitoring() async {
    try {
      await _nativeChannel.invokeMethod('startBackground');
      setState(() => monitoringBackground = true);
    } on PlatformException catch (e) {
      debugPrint('startBackground failed: $e');
    }
  }

  Future<void> stopBackgroundMonitoring() async {
    try {
      await _nativeChannel.invokeMethod('stopBackground');
      setState(() => monitoringBackground = false);
    } on PlatformException catch (e) {
      debugPrint('stopBackground failed: $e');
    }
  }

  @override
  void dispose() {
    _accelSub?.cancel();
    _posSub?.cancel();
    super.dispose();
  }

  Color getAlertColor() => alert ? Colors.redAccent : Colors.greenAccent;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: AppBar(
        title: const Text("Driver Phone Monitor"),
        backgroundColor: Colors.blueGrey[900],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Cảnh báo
            AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              height: 60,
              width: double.infinity,
              decoration: BoxDecoration(
                color: getAlertColor(),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text(
                alert ? "⚠️ Cảnh báo: Không sử dụng điện thoại!" : "✅ An toàn",
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Cảm biến gia tốc
            Card(
              color: Colors.blueGrey[800],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const Text("Cảm biến gia tốc",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Text("X = ${x.toStringAsFixed(2)}"),
                    Text("Y = ${y.toStringAsFixed(2)}"),
                    Text("Z = ${z.toStringAsFixed(2)}"),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Tốc độ
            Card(
              color: Colors.blueGrey[800],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const Text("Tốc độ (km/h)",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Text("${speed.toStringAsFixed(1)} km/h",
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      value: (speed / 100).clamp(0, 1),
                      color: alert ? Colors.redAccent : Colors.greenAccent,
                      backgroundColor: Colors.grey[700],
                      minHeight: 10,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Nút điều khiển nền
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: monitoringBackground ? null : startBackgroundMonitoring,
                    child: const Text('Bắt đầu giám sát nền (iOS/Android)'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: monitoringBackground ? stopBackgroundMonitoring : null,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                    child: const Text('Dừng giám sát nền'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}