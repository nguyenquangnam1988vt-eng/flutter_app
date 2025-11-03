import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:vibration/vibration.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:math';

const MethodChannel _nativeChannel = MethodChannel('driver_monitor/native');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initNotifications();
  runApp(const MyApp());
}

Future<void> _initNotifications() async {
  const android = AndroidInitializationSettings('@mipmap/ic_launcher');
  const ios = DarwinInitializationSettings();
  const initSettings = InitializationSettings(android: android, iOS: ios);
  await FlutterLocalNotificationsPlugin().initialize(initSettings);
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Driver Phone Monitor',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.dark,
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
  bool screenOn = true;

  final List<double> _yBuffer = [];
  final List<double> _zBuffer = [];
  final int _bufferSize = 20; // dùng cho RMS trục Y và Z
  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<Position>? _posSub;
  final FlutterLocalNotificationsPlugin _localNotif =
      FlutterLocalNotificationsPlugin();
  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    if (Platform.isIOS) {
      _setupNativeCallback();
    }
    _listenSensors();
    _listenLocation();
  }

  Future<void> _requestPermissions() async {
    await Permission.locationAlways.request();
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
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'alert.mp3',
    );

    await _localNotif.show(
      999,
      '⚠️ Cảnh báo',
      'Phát hiện sử dụng điện thoại khi di chuyển ở ${spd.toStringAsFixed(1)} km/h',
      const NotificationDetails(android: androidDetails, iOS: iosDetails),
    );

    // Phát âm thanh trực tiếp (iOS và Android)
    await _audioPlayer.play(AssetSource('alert.mp3'));

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

      _yBuffer.add(event.y);
      if (_yBuffer.length > _bufferSize) _yBuffer.removeAt(0);

      _zBuffer.add(event.z);
      if (_zBuffer.length > _bufferSize) _zBuffer.removeAt(0);

      _checkAlert();
    });
  }

  void _listenLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) return;

    LocationPermission p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied)
      p = await Geolocator.requestPermission();
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever)
      return;

    const settings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 1,
    );

    _posSub = Geolocator.getPositionStream(locationSettings: settings)
        .listen((Position pos) {
      setState(() {
        speed = (pos.speed >= 0) ? pos.speed * 3.6 : 0.0;
      });
      _checkAlert();
    });
  }

  void _checkAlert() async {
    // RMS trục Y
    final rmsY = _yBuffer.isEmpty
        ? 0.0
        : sqrt(_yBuffer.fold<double>(0, (sum, val) => sum + val * val) /
            _yBuffer.length);

    // RMS trục Z
    final rmsZ = _zBuffer.isEmpty
        ? 0.0
        : sqrt(_zBuffer.fold<double>(0, (sum, val) => sum + val * val) /
            _zBuffer.length);

    bool overSpeed = speed > 5;
    bool yTilted = y > 5.0; // CHỈ cảnh báo khi y > 5.0 (bỏ abs)
    bool rmsYValid = rmsY >= 0.5 && rmsY <= 3.0;
    bool rmsZValid = rmsZ <= 1.5; // RMS trục Z trong khoảng 0 - 1.5

    if (overSpeed && yTilted && rmsYValid && rmsZValid && screenOn) {
      if (!alert) {
        await _showLocalAlert(speed);
      }
      setState(() => alert = true);
    } else {
      setState(() => alert = false);
    }
  }

  Future<void> startBackgroundMonitoring() async {
    if (!Platform.isIOS) return;
    try {
      await _nativeChannel.invokeMethod('startBackground');
      setState(() => monitoringBackground = true);
    } on PlatformException catch (e) {
      debugPrint('startBackground failed: $e');
    }
  }

  Future<void> stopBackgroundMonitoring() async {
    if (!Platform.isIOS) return;
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
        title: const Text("Driver Phone Monitor (iOS)"),
        backgroundColor: Colors.blueGrey[900],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
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
            _buildAccelCard(),
            const SizedBox(height: 20),
            _buildSpeedCard(),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed:
                        monitoringBackground ? null : startBackgroundMonitoring,
                    child: const Text('Bắt đầu giám sát nền'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed:
                        monitoringBackground ? stopBackgroundMonitoring : null,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent),
                    child: const Text('Dừng'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccelCard() => Card(
        color: Colors.blueGrey[800],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              const Text("Cảm biến gia tốc (iOS)",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Text("X = ${x.toStringAsFixed(2)}"),
              Text("Y = ${y.toStringAsFixed(2)}"),
              Text("Z = ${z.toStringAsFixed(2)}"),
            ],
          ),
        ),
      );

  Widget _buildSpeedCard() => Card(
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
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold)),
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
      );
}
