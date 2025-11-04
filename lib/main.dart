import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:vibration/vibration.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:background_fetch/background_fetch.dart';
import 'package:dio/dio.dart';

// -------------------- ⚙️ HÀM ĐO TỐC ĐỘ MẠNG --------------------
Future<Map<String, dynamic>> measureNetwork() async {
  final stopwatch = Stopwatch()..start();
  final dio = Dio();

  try {
    final response = await dio.get(
      'https://speed.hetzner.de/5MB.bin',
      options: Options(responseType: ResponseType.stream),
    );

    int total = 0;
    await for (var chunk in response.data.stream) {
      total += (chunk as List<int>).length;
    }

    stopwatch.stop();
    double seconds = stopwatch.elapsedMilliseconds / 1000;
    double speedMbps = (total * 8 / seconds) / 1e6;

    print('🚀 Download speed: ${speedMbps.toStringAsFixed(2)} Mbps');
    return {'speed': speedMbps};
  } catch (e) {
    print('⚠️ Lỗi đo mạng: $e');
    return {'speed': 0.0};
  }
}

// -------------------- 📍 HÀM LẤY VỊ TRÍ --------------------
Future<void> trackLocation() async {
  bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) return;

  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) return;
  }

  final pos = await Geolocator.getCurrentPosition();
  print('📍 Vị trí hiện tại: ${pos.latitude}, ${pos.longitude}');
}

// -------------------- 🔁 BACKGROUND TASK --------------------
void backgroundTask(HeadlessTask task) async {
  print('🕒 Background task triggered: ${task.taskId}');
  await trackLocation();
  final net = await measureNetwork();
  print('🌐 Background net speed: ${net['speed']} Mbps');
  BackgroundFetch.finish(task.taskId);
}

// -------------------- 🚀 MAIN --------------------
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initNotifications();

  BackgroundFetch.configure(
    BackgroundFetchConfig(
      minimumFetchInterval: 5,
      stopOnTerminate: false,
      enableHeadless: true,
      startOnBoot: true,
      requiredNetworkType: NetworkType.ANY,
      requiresCharging: false,
      requiresDeviceIdle: false,
      requiresBatteryNotLow: false,
      requiresStorageNotLow: false,
    ),
    (String taskId) async {
      print('🕒 Foreground background fetch triggered: $taskId');
      await trackLocation();
      final net = await measureNetwork();
      print('🌐 Foreground net speed: ${net['speed']} Mbps');
      BackgroundFetch.finish(taskId);
    },
    (String taskId) async {
      print('⚠️ Background fetch timeout: $taskId');
      BackgroundFetch.finish(taskId);
    },
  );

  BackgroundFetch.registerHeadlessTask(backgroundTask);

  runApp(const MyApp());
}

// -------------------- 🔔 THÔNG BÁO --------------------
Future<void> _initNotifications() async {
  const android = AndroidInitializationSettings('@mipmap/ic_launcher');
  const ios = DarwinInitializationSettings();
  const initSettings = InitializationSettings(android: android, iOS: ios);
  await FlutterLocalNotificationsPlugin().initialize(initSettings);
}

// -------------------- 🌟 GIAO DIỆN --------------------
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Driver Phone Monitor',
      theme: ThemeData(primarySwatch: Colors.blue, brightness: Brightness.dark),
      home: const Dashboard(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// -------------------- 🧠 DASHBOARD --------------------
class Dashboard extends StatefulWidget {
  const Dashboard({super.key});
  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  double x = 0, y = 0, z = 0;
  double speed = 0;
  double netSpeed = 0;
  bool alert = false;
  bool monitoring = false; // 👈 trạng thái giám sát nền
  bool screenOn = true;

  final List<double> _yBuffer = [];
<<<<<<< HEAD
  static const int _bufferSize = 30;
=======
  final List<double> _zBuffer = [];
  final int _bufferSize = 20; // dùng cho RMS trục Y và Z
>>>>>>> 42ab913abc0b39281a54ee76a8c771c8f63fa755
  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<Position>? _posSub;
  final FlutterLocalNotificationsPlugin _localNotif =
      FlutterLocalNotificationsPlugin();
  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _listenSensors();
    _listenLocation();
    _scheduleNetworkCheck();
  }

  Future<void> _requestPermissions() async {
    await Permission.locationAlways.request();
    await Permission.sensors.request();
    await Permission.notification.request();
  }

  void _scheduleNetworkCheck() {
    Timer.periodic(const Duration(minutes: 5), (_) async {
      final result = await measureNetwork();
      setState(() => netSpeed = result['speed'] ?? 0.0);
      _checkAlert();
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
      'Phát hiện sử dụng điện thoại và mạng khi di chuyển ở ${spd.toStringAsFixed(1)} km/h',
      const NotificationDetails(android: androidDetails, iOS: iosDetails),
    );

    await _audioPlayer.play(AssetSource('assets/alert.mp3'));
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
      _yBuffer.add(y);
      if (_yBuffer.length > _bufferSize) _yBuffer.removeAt(0);
<<<<<<< HEAD
=======

      _zBuffer.add(event.z);
      if (_zBuffer.length > _bufferSize) _zBuffer.removeAt(0);

>>>>>>> 42ab913abc0b39281a54ee76a8c771c8f63fa755
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
<<<<<<< HEAD
        accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 1);
=======
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 1,
    );

>>>>>>> 42ab913abc0b39281a54ee76a8c771c8f63fa755
    _posSub = Geolocator.getPositionStream(locationSettings: settings)
        .listen((Position pos) {
      setState(() {
        speed = (pos.speed >= 0) ? pos.speed * 3.6 : 0.0;
      });
      _checkAlert();
    });
  }

  double _calculateRMS(List<double> values) {
    if (values.isEmpty) return 0.0;
    double sumSq = values.fold(0, (sum, v) => sum + v * v);
    return sqrt(sumSq / values.length);
  }

  void _checkAlert() async {
<<<<<<< HEAD
    bool overSpeed = speed > 1.0;
    bool yTilted = y > 5.0;
    bool zValid = z < 6.0;
    double rmsY = _calculateRMS(_yBuffer);
    bool rmsYStable = rmsY >= 0.5 && rmsY <= 2.5;
    bool usingNetwork = netSpeed > 0.5;

    if (overSpeed && yTilted && zValid && rmsYStable && screenOn && usingNetwork) {
=======
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
>>>>>>> 42ab913abc0b39281a54ee76a8c771c8f63fa755
      if (!alert) {
        await _showLocalAlert(speed);
      }
      setState(() => alert = true);
    } else {
      setState(() => alert = false);
    }
  }

  Future<void> _toggleBackgroundMonitor() async {
    if (monitoring) {
      await BackgroundFetch.stop();
      setState(() => monitoring = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("⛔ Đã dừng giám sát nền")),
      );
    } else {
      await BackgroundFetch.start();
      setState(() => monitoring = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("✅ Đang giám sát nền")),
      );
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
    double rmsY = _calculateRMS(_yBuffer);
    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: AppBar(
        title: const Text("Driver Phone Monitor (iOS/Android)"),
        backgroundColor: Colors.blueGrey[900],
        actions: [
          IconButton(
            icon: Icon(monitoring ? Icons.stop_circle : Icons.play_circle_fill),
            onPressed: _toggleBackgroundMonitor,
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(children: [
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
              alert
                  ? "⚠️ Cảnh báo: Sử dụng điện thoại & mạng khi di chuyển!"
                  : "✅ An toàn",
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
          const SizedBox(height: 20),
          _buildAccelCard(rmsY),
          const SizedBox(height: 20),
          _buildSpeedCard(),
          const SizedBox(height: 20),
          _buildNetworkCard(),
          const SizedBox(height: 30),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: monitoring ? Colors.redAccent : Colors.green,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
<<<<<<< HEAD
            onPressed: _toggleBackgroundMonitor,
            icon: Icon(
              monitoring ? Icons.pause_circle_filled : Icons.play_circle_fill,
              size: 28,
=======
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
>>>>>>> 42ab913abc0b39281a54ee76a8c771c8f63fa755
            ),
            label: Text(
              monitoring ? "Dừng giám sát nền" : "Bắt đầu giám sát nền",
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ]),
      ),
    );
  }

  // -------------------- WIDGETS --------------------
  Widget _buildAccelCard(double rmsY) => Card(
        color: Colors.blueGrey[800],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(children: [
            const Text("Cảm biến gia tốc",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text("X = ${x.toStringAsFixed(2)}"),
            Text("Y = ${y.toStringAsFixed(2)}"),
            Text("Z = ${z.toStringAsFixed(2)}"),
            const SizedBox(height: 10),
            Text("RMS(Y) = ${rmsY.toStringAsFixed(2)}"),
          ]),
        ),
      );

  Widget _buildSpeedCard() => Card(
        color: Colors.blueGrey[800],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
<<<<<<< HEAD
          child: Column(children: [
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
          ]),
        ),
      );

  Widget _buildNetworkCard() => Card(
        color: Colors.blueGrey[800],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(children: [
            const Text("Tốc độ mạng (Mbps)",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text("${netSpeed.toStringAsFixed(2)} Mbps",
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: (netSpeed / 20).clamp(0, 1),
              color: netSpeed > 0.5 ? Colors.greenAccent : Colors.redAccent,
              backgroundColor: Colors.grey[700],
              minHeight: 10,
            ),
          ]),
=======
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
>>>>>>> 42ab913abc0b39281a54ee76a8c771c8f63fa755
        ),
      );
}
