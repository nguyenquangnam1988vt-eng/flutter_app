import UIKit
import Flutter
import CoreLocation
import UserNotifications

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate, CLLocationManagerDelegate {
    var locationManager: CLLocationManager?
    var methodChannel: FlutterMethodChannel?
    let channelName = "driver_monitor/native"
    let speedThresholdKmh: Double = 30.0

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        
        // Đăng ký toàn bộ plugin Flutter (bắt buộc)
        GeneratedPluginRegistrant.register(with: self)
        
        // Thiết lập kênh giao tiếp native <-> Flutter
        if let controller = window?.rootViewController as? FlutterViewController {
            methodChannel = FlutterMethodChannel(name: channelName, binaryMessenger: controller.binaryMessenger)
            
            methodChannel?.setMethodCallHandler({ [weak self] (call, result) in
                switch call.method {
                case "startBackground":
                    self?.startLocationUpdates()
                    result("started")
                case "stopBackground":
                    self?.stopLocationUpdates()
                    result("stopped")
                default:
                    result(FlutterMethodNotImplemented)
                }
            })
        }
        
        // Xin quyền gửi thông báo
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        UNUserNotificationCenter.current().delegate = self
        
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // MARK: - Location Background
    func startLocationUpdates() {
        if locationManager == nil {
            locationManager = CLLocationManager()
            locationManager?.delegate = self
            locationManager?.desiredAccuracy = kCLLocationAccuracyBestForNavigation
            locationManager?.distanceFilter = 1.0
            locationManager?.pausesLocationUpdatesAutomatically = false
        }

        locationManager?.requestAlwaysAuthorization()
        locationManager?.allowsBackgroundLocationUpdates = true
        locationManager?.startUpdatingLocation()
        print("🚗 Bắt đầu theo dõi vị trí nền")
    }

    func stopLocationUpdates() {
        locationManager?.stopUpdatingLocation()
        locationManager = nil
        print("🛑 Dừng theo dõi vị trí nền")
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        let speedMs = max(loc.speed, 0.0)
        let speedKmh = speedMs * 3.6

        if UIApplication.shared.applicationState != .active {
            if speedKmh > speedThresholdKmh {
                sendBackgroundNotification(speed: speedKmh)
                methodChannel?.invokeMethod("backgroundSpeedAlert", arguments: ["speed": speedKmh])
            }
        }
    }

    func sendBackgroundNotification(speed: Double) {
        let content = UNMutableNotificationContent()
        content.title = "⚠️ Cảnh báo lái xe"
        content.body = "Phát hiện di chuyển \(String(format: "%.1f", speed)) km/h. Vui lòng không sử dụng điện thoại."
        content.sound = UNNotificationSound.default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}