import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:vibration/vibration.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(MyApp());
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

class _DashboardState extends State<Dashboard> with SingleTickerProviderStateMixin {
  double x = 0, y = 0, z = 0;
  double speed = 0;
  bool screenOn = true; // Giả lập
  bool alert = false;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _listenSensors();
    _listenLocation();
  }

  Future<void> _requestPermissions() async {
    await Permission.location.request();
    await Permission.sensors.request();
  }

  void _listenSensors() {
    accelerometerEvents.listen((event) {
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

    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 1,
      ),
    ).listen((Position position) {
      setState(() {
        speed = position.speed * 3.6; // m/s -> km/h
      });
      _checkAlert();
    });
  }

  void _checkAlert() {
    bool isTilted = (x.abs() > 3 || y.abs() > 3); // điều chỉnh theo cảm biến
    bool overSpeed = speed > 30; // >30 km/h

    if (isTilted && screenOn && overSpeed) {
      if (!alert) Vibration.vibrate(duration: 1000);
      setState(() {
        alert = true;
      });
      print("⚠️ Cảnh báo: Không sử dụng điện thoại khi lái xe!");
    } else {
      setState(() {
        alert = false;
      });
    }
  }

  Color getAlertColor() => alert ? Colors.redAccent : Colors.greenAccent;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: AppBar(
        title: Text("Driver Phone Monitor"),
        backgroundColor: Colors.blueGrey[900],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Alert Banner
            AnimatedContainer(
              duration: Duration(milliseconds: 500),
              height: 60,
              width: double.infinity,
              decoration: BoxDecoration(
                color: getAlertColor(),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text(
                alert ? "⚠️ Cảnh báo: Không sử dụng điện thoại!" : "✅ An toàn",
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
            SizedBox(height: 20),

            // Accelerometer Card
            Card(
              color: Colors.blueGrey[800],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Text(
                      "Cảm biến gia tốc",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    SizedBox(height: 10),
                    Text("x = ${x.toStringAsFixed(2)}"),
                    Text("y = ${y.toStringAsFixed(2)}"),
                    Text("z = ${z.toStringAsFixed(2)}"),
                  ],
                ),
              ),
            ),
            SizedBox(height: 20),

            // Speed Card
            Card(
              color: Colors.blueGrey[800],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Text(
                      "Tốc độ (km/h)",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    SizedBox(height: 10),
                    Text(
                      "${speed.toStringAsFixed(1)} km/h",
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 10),
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
            SizedBox(height: 20),

            // Screen status
            Card(
              color: Colors.blueGrey[800],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                leading: Icon(screenOn ? Icons.phone_android : Icons.phone_disabled, color: Colors.white),
                title: Text("Màn hình bật", style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}