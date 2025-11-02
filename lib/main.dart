import 'dart:async';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:vibration/vibration.dart';
import 'package:audioplayers/audioplayers.dart';

void main() {
  runApp(const DriverMonitorApp());
}

class DriverMonitorApp extends StatefulWidget {
  const DriverMonitorApp({Key? key}) : super(key: key);

  @override
  State<DriverMonitorApp> createState() => _DriverMonitorAppState();
}

class _DriverMonitorAppState extends State<DriverMonitorApp> {
  double accelY = 0.0;
  double speedKmh = 0.0;
  bool isAlerting = false;

  StreamSubscription? accelSubscription;
  StreamSubscription<Position>? positionStream;
  final player = AudioPlayer();
  final FlutterLocalNotificationsPlugin notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    _initPermissions();
    _initNotifications();
    _startAccelerometer();
    _startGpsMonitoring();
  }

  Future<void> _initPermissions() async {
    await Permission.location.request();
    await Permission.notification.request();
    await Permission.sensors.request();
  }

  Future<void> _initNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await notificationsPlugin.initialize(initSettings);
  }

  void _startAccelerometer() {
    accelSubscription = accelerometerEvents.listen((AccelerometerEvent event) {
      setState(() {
        accelY = event.y;
      });
      _checkAlertCondition();
    });
  }

  void _startGpsMonitoring() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await Geolocator.openLocationSettings();
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.deniedForever) return;
    }

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
    );

    positionStream =
        Geolocator.getPositionStream(locationSettings: locationSettings)
            .listen((Position position) {
      double newSpeed = (position.speed >= 0)
          ? position.speed * 3.6
          : 0; // m/s → km/h
      setState(() {
        speedKmh = newSpeed;
      });
      _checkAlertCondition();
    });
  }

  void _checkAlertCondition() async {
    bool overSpeed = speedKmh > 30.0;
    bool phoneUpright = accelY.abs() > 4.0; // bạn yêu cầu ngưỡng này

    if (overSpeed && phoneUpright) {
      if (!isAlerting) {
        _triggerWarning();
        setState(() => isAlerting = true);
      }
    } else {
      if (isAlerting) {
        _stopWarning();
        setState(() => isAlerting = false);
      }
    }
  }

  Future<void> _triggerWarning() async {
    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(duration: 800);
    }
    await player.play(AssetSource('alert.mp3'));

    const androidDetails = AndroidNotificationDetails(
      'driver_alerts',
      'Driver Alerts',
      importance: Importance.high,
      priority: Priority.high,
    );
    const notifDetails = NotificationDetails(android: androidDetails);

    await notificationsPlugin.show(
      0,
      '⚠️ Cảnh báo',
      'Phát hiện điện thoại dựng thẳng khi xe đang di chuyển nhanh!',
      notifDetails,
    );
  }

  Future<void> _stopWarning() async {
    try {
      await player.stop();
    } catch (_) {}
    if (await Vibration.hasVibrator() ?? false) Vibration.cancel();
  }

  @override
  void dispose() {
    accelSubscription?.cancel();
    positionStream?.cancel();
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Giám sát lái xe',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: Scaffold(
        appBar: AppBar(title: const Text('Giám sát sử dụng điện thoại khi lái xe')),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: 60,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: isAlerting ? Colors.redAccent : Colors.green,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(
                  isAlerting
                      ? '⚠️ CẢNH BÁO: Dừng xe để sử dụng điện thoại!'
                      : '✅ An toàn',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 20),
              Text('Tốc độ: ${speedKmh.toStringAsFixed(1)} km/h',
                  style: const TextStyle(fontSize: 22)),
              const SizedBox(height: 10),
              Text('Trục Y (điện thoại nghiêng): ${accelY.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 22)),
              const SizedBox(height: 20),
              const Text(
                'Ứng dụng sẽ cảnh báo khi tốc độ >30 km/h và điện thoại dựng thẳng (|Y| > 4)',
                style: TextStyle(fontSize: 16, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}