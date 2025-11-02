import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vibration/vibration.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

const MethodChannel _nativeChannel = MethodChannel('driver_monitor/native');

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
  // sensors
  double x = 0, y = 0, z = 0;
  // gps
  double speed = 0;
  // ui
  bool alert = false;
  bool monitoringBackground = false;

  // audio
  final AudioPlayer _audioPlayer = AudioPlayer();

  // local notifications (for foreground convenience)
  final FlutterLocalNotificationsPlugin _localNotif = FlutterLocalNotificationsPlugin();

  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<Position>? _posSub;

  @override
  void initState() {
    super.initState();
    _initNotifications();
    _setupNativeCallback();
    _requestPermissions();
    _startSensors();
    _startLocationForeground();
  }

  @override
  void dispose() {
    _accelSub?.cancel();
    _posSub?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _initNotifications() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iOS = DarwinInitializationSettings();
    await _localNotif.initialize(const InitializationSettings(android: android, iOS: iOS));
  }

  void _setupNativeCallback() {
    _nativeChannel.setMethodCallHandler((call) async {
      if (call.method == 'backgroundSpeedAlert') {
        final args = call.arguments as Map<dynamic, dynamic>?;
        final speed = (args?['speed'] ?? 0).toDouble();
        // Show a local notification and in-app banner if foreground
        _showLocalAlertFromNative(speed);
      }
    });
  }

  Future<void> _showLocalAlertFromNative(double speed) async {
    const androidDetails = AndroidNotificationDetails(
      'bg_alerts', 'Background Alerts',
      channelDescription: 'Alerts from native when speed threshold exceeded',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
    );
    const iOSDetails = DarwinNotificationDetails();
    const details = NotificationDetails(android: androidDetails, iOS: iOSDetails);
    await _localNotif.show(999, 'Cảnh báo (nền)', 'Tốc độ ${speed.toStringAsFixed(1)} km/h — mở app để kiểm tra', details);
    if (await Vibration.hasVibrator() ?? false) Vibration.vibrate(duration: 800);
  }

  // Request permissions (foreground); for iOS background Always permission: we will call native startBackground that triggers requestAlwaysAuthorization
  Future<void> _requestPermissions() async {
    // location when in use
    var status = await Permission.locationWhenInUse.request();
    if (!status.isGranted) {
      // user denied; we continue but gps won't work
    }
    // sensors permission (Android)
    await Permission.sensors.request();
  }

  void _startSensors() {
    _accelSub = accelerometerEvents.listen((event) {
      setState(() {
        x = event.x;
        y = event.y;
        z = event.z;
      });
      _evaluateAlert();
    });
  }

  void _startLocationForeground() async {
    // check service & permission
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // optionally open settings
      return;
    }

    LocationPermission p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    if (p == LocationPermission.deniedForever || p == LocationPermission.denied) {
      // cannot get location
      return;
    }

    const settings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 1,
    );

    _posSub = Geolocator.getPositionStream(locationSettings: settings).listen((pos) {
      setState(() {
        speed = (pos.speed >= 0) ? pos.speed * 3.6 : 0.0;
      });
      _evaluateAlert();
    });
  }

  // call native to start background location (iOS). Native will request Always permission and start updates.
  Future<void> startBackgroundMonitoring() async {
    try {
      final res = await _nativeChannel.invokeMethod('startBackground');
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

  // Evaluation: based on trục Y (user asked), speed > 30, and screenOn (we treat as true because iOS won't expose)
  void _evaluateAlert() {
    final bool isTiltedY = y.abs() > 4.0; // threshold you wanted
    final bool overSpeed = speed > 30.0;

    if (isTiltedY && overSpeed) {
      if (!alert) {
        _triggerForegroundAlert();
      }
      setState(() => alert = true);
    } else {
      if (alert) {
        _stopAlertActions();
      }
      setState(() => alert = false);
    }
  }

  Future<void> _triggerForegroundAlert() async {
    // vibration
    if (await Vibration.hasVibrator() ?? false) Vibration.vibrate(duration: 1500);

    // play loud alert sound (assets/alert.mp3) at max volume
    try {
      await _audioPlayer.setVolume(1.0);
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
      await _audioPlayer.play(AssetSource('alert.mp3'));
    } catch (_) {}

    // show in-app dialog (if app is foreground)
    if (mounted) {
      showDialog(context: context, builder: (c) {
        return AlertDialog(
          title: const Text('Cảnh báo'),
          content: const Text('Phát hiện sử dụng điện thoại khi phương tiện đang di chuyển. Vui lòng dừng xe để sử dụng.'),
          actions: [
            TextButton(onPressed: () {
              Navigator.of(c).pop();
            }, child: const Text('OK'))
          ],
        );
      });
    }
  }

  Future<void> _stopAlertActions() async {
    try {
      await _audioPlayer.stop();
    } catch (_) {}
    if (await Vibration.hasVibrator() ?? false) Vibration.cancel();
  }

  Widget _buildInfoCard(String title, Widget content) {
    return Card(
      color: const Color(0xFF1E2933),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(color: Colors.white70, fontSize: 13)),
        const SizedBox(height: 8),
        content
      ])),
    );
  }

  @override
  Widget build(BuildContext context) {
    final alertColor = alert ? Colors.redAccent : Colors.greenAccent;
    return Scaffold(
      appBar: AppBar(title: const Text('Driver Phone Monitor')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            height: 64,
            width: double.infinity,
            decoration: BoxDecoration(color: alertColor, borderRadius: BorderRadius.circular(12)),
            alignment: Alignment.center,
            child: Text(alert ? '⚠️ CẢNH BÁO: Không dùng điện thoại khi lái xe!' : '✅ An toàn', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 12),
          _buildInfoCard('Trục Y (nghiêng)', Text('${y.toStringAsFixed(2)}', style: const TextStyle(fontSize: 20, color: Colors.white))),
          const SizedBox(height: 10),
          _buildInfoCard('Tốc độ (km/h)', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${speed.toStringAsFixed(1)}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: (speed/100).clamp(0,1), color: alert ? Colors.redAccent : Colors.greenAccent, backgroundColor: Colors.grey[700], minHeight: 8)
          ])),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: ElevatedButton(
                onPressed: monitoringBackground ? null : () { startBackgroundMonitoring(); },
                child: const Text('Bắt đầu giám sát nền (iOS)'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: monitoringBackground ? () { stopBackgroundMonitoring(); } : null,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                child: const Text('Dừng giám sát nền'),
              )
            )
          ]),
          const SizedBox(height: 12),
          const Text('Ghi chú: iOS chỉ cho chạy nền GPS nếu đã bật Background Modes → Location updates và cấp quyền "Allow Always".', style: TextStyle(color: Colors.white54))
        ]),
      ),
    );
  }
}