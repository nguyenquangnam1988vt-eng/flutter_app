import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vibration/vibration.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

const MethodChannel _nativeChannel = MethodChannel('driver_monitor/native');

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

enum PhonePosition { Flat, Upright, Tilted }

class _MyAppState extends State<MyApp> {
  final FlutterLocalNotificationsPlugin _localNotif = FlutterLocalNotificationsPlugin();

  double _ax = 0, _ay = 0, _az = 0;
  double _speedKmh = 0;
  bool _alerted = false;
  bool _isMonitoring = false;

  PhonePosition _position = PhonePosition.Flat;

  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<Position>? _posSub;

  @override
  void initState() {
    super.initState();
    _initNotifications();
    _setupNativeCallback();
    _startAccelerometer();
    _listenPositionForeground();
  }

  @override
  void dispose() {
    _accelSub?.cancel();
    _posSub?.cancel();
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
        _showBackgroundAlert(speed);
      }
    });
  }

  Future<void> _showBackgroundAlert(double speed) async {
    const androidDetails = AndroidNotificationDetails(
        'bg_alerts', 'Background Alerts',
        channelDescription: 'Alerts sent from iOS native when speed threshold exceeded',
        importance: Importance.max, priority: Priority.high);
    const iOSDetails = DarwinNotificationDetails();
    const details = NotificationDetails(android: androidDetails, iOS: iOSDetails);

    await _localNotif.show(999, 'Cảnh báo nền',
        'Phát hiện di chuyển ${speed.toStringAsFixed(1)} km/h — mở app để kiểm tra', details);

    if (await Vibration.hasVibrator() ?? false) Vibration.vibrate(duration: 800);
  }

  void _startAccelerometer() {
    _accelSub = accelerometerEvents.listen((e) {
      setState(() {
        _ax = e.x;
        _ay = e.y;
        _az = e.z;
        _position = _detectPhonePosition(_ax, _ay, _az);
      });
    });
  }

  PhonePosition _detectPhonePosition(double ax, double ay, double az) {
    if (az.abs() > 7 && ax.abs() < 3 && ay.abs() < 3) return PhonePosition.Flat;
    if (az.abs() < 5 && (ax.abs() > 5 || ay.abs() > 5)) return PhonePosition.Upright;
    return PhonePosition.Tilted;
  }

  void _listenPositionForeground() async {
    final status = await Permission.locationWhenInUse.request();
    if (!status.isGranted) return;

    const settings = LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 5);

    _posSub = Geolocator.getPositionStream(locationSettings: settings)
        .listen((pos) {
      final speed = (pos.speed >= 0) ? pos.speed * 3.6 : 0.0;
      setState(() => _speedKmh = speed);
    });
  }

  void _onUserInteraction() {
    const speedThreshold = 30.0;
    if (_position != PhonePosition.Flat && _speedKmh > speedThreshold && !_alerted) {
      _triggerForegroundAlert();
    }
  }

  Future<void> _triggerForegroundAlert() async {
    _alerted = true;

    if (await Vibration.hasVibrator() ?? false) Vibration.vibrate(duration: 1000);

    const androidDetails = AndroidNotificationDetails('fg_alerts', 'Foreground Alerts',
        channelDescription: 'FG alerts', importance: Importance.max, priority: Priority.high);
    const iOSDetails = DarwinNotificationDetails();
    await _localNotif.show(1, 'Cảnh báo lái xe',
        'Phát hiện thao tác khi đang di chuyển >30 km/h', const NotificationDetails(android: androidDetails, iOS: iOSDetails));

    if (mounted) {
      showDialog(
        context: context,
        builder: (c) {
          return AlertDialog(
            title: const Text('Cảnh báo'),
            content: const Text(
                'Phát hiện sử dụng điện thoại khi phương tiện đang di chuyển. Vui lòng dừng xe để sử dụng.'),
            actions: [
              TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text('OK'))
            ],
          );
        },
      );
    }

    Future.delayed(const Duration(seconds: 20), () {
      _alerted = false;
    });
  }

  Future<void> _startBackgroundMonitoring() async {
    try {
      await _nativeChannel.invokeMethod('startBackground');
      setState(() => _isMonitoring = true);
    } on PlatformException catch (e) {
      debugPrint('startBackground failed: $e');
    }
  }

  Future<void> _stopBackgroundMonitoring() async {
    try {
      await _nativeChannel.invokeMethod('stopBackground');
      setState(() => _isMonitoring = false);
    } on PlatformException catch (e) {
      debugPrint('stopBackground failed: $e');
    }
  }

  Widget _buildStatusCard(String title, String value, {Color? color, IconData? icon}) {
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.all(16),
        width: double.infinity,
        child: Row(
          children: [
            if (icon != null) Icon(icon, size: 36, color: color ?? Colors.black54),
            if (icon != null) const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 14, color: Colors.grey)),
                const SizedBox(height: 4),
                Text(value,
                    style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold, color: color ?? Colors.black)),
              ],
            )
          ],
        ),
      ),
    );
  }

  Color _getPositionColor() {
    switch (_position) {
      case PhonePosition.Flat:
        return Colors.green;
      case PhonePosition.Upright:
        return Colors.red;
      case PhonePosition.Tilted:
        return Colors.orange;
    }
  }

  IconData _getPositionIcon() {
    switch (_position) {
      case PhonePosition.Flat:
        return Icons.phone_android;
      case PhonePosition.Upright:
        return Icons.phone_iphone;
      case PhonePosition.Tilted:
        return Icons.screen_rotation;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _onUserInteraction(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          appBar: AppBar(
            title: const Text('Cảnh báo khi lái xe'),
            centerTitle: true,
            flexibleSpace: Container(
              decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [Color(0xFF0F9D58), Color(0xFF34A853)])),
            ),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: const LinearGradient(
                        colors: [Color(0xFF2196F3), Color(0xFF4FC3F7)]),
                    boxShadow: const [
                      BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 4))
                    ],
                  ),
                  child: Column(
                    children: [
                      Text('${_speedKmh.toStringAsFixed(1)}',
                          style: const TextStyle(
                              fontSize: 56, fontWeight: FontWeight.bold, color: Colors.white)),
                      const SizedBox(height: 6),
                      const Text('km/h', style: TextStyle(color: Colors.white70)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _buildStatusCard('Trạng thái thiết bị',
                    _position == PhonePosition.Flat
                        ? 'Đặt phẳng'
                        : _position == PhonePosition.Upright
                            ? 'Dựng thẳng'
                            : 'Nghiêng',
                    color: _getPositionColor(),
                    icon: _getPositionIcon()),
                const SizedBox(height: 12),
                _buildStatusCard(
                    'Accelerometer',
                    'ax=${_ax.toStringAsFixed(2)} ay=${_ay.toStringAsFixed(2)} az=${_az.toStringAsFixed(2)}',
                    icon: Icons.sensors),
                const SizedBox(height: 12),
                _buildStatusCard('Monitoring (background)', _isMonitoring ? 'Bật' : 'Tắt',
                    icon: Icons.monitor),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isMonitoring ? null : _startBackgroundMonitoring,
                        style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14)),
                        child: const Text('Bắt đầu giám sát nền'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isMonitoring ? _stopBackgroundMonitoring : null,
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            padding: const EdgeInsets.symmetric(vertical: 14)),
                        child: const Text('Dừng giám sát'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Text(
                  'Ghi chú: iOS chỉ cho phép theo dõi vị trí khi app chạy nền nếu bạn cấp "Always" location permission và bật Background Modes -> Location updates trong Xcode.',
                  style: TextStyle(color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}