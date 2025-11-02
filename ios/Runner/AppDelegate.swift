import UIKit
import Flutter
import CoreLocation
import UserNotifications

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate, CLLocationManagerDelegate {
  var window: UIWindow?
  var locationManager: CLLocationManager?
  let channelName = "driver_monitor/native"
  var methodChannel: FlutterMethodChannel?

  // Speed threshold km/h
  let speedThresholdKmh: Double = 30.0

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    methodChannel = FlutterMethodChannel(name: channelName, binaryMessenger: controller.binaryMessenger)

    // Set up method call handler to receive start/stop requests from Flutter
    methodChannel?.setMethodCallHandler({ [weak self] (call, result) in
      if call.method == "startBackground" {
        self?.startLocationUpdates()
        result("started")
      } else if call.method == "stopBackground" {
        self?.stopLocationUpdates()
        result("stopped")
      } else {
        result(FlutterMethodNotImplemented)
      }
    })

    // request notification permission
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
      // handle if needed
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // MARK: - Location setup
  func startLocationUpdates() {
    if locationManager == nil {
      locationManager = CLLocationManager()
      locationManager?.delegate = self
      locationManager?.desiredAccuracy = kCLLocationAccuracyBestForNavigation
      locationManager?.distanceFilter = 5
    }

    // Request Always permission
    locationManager?.requestAlwaysAuthorization()

    // Allow background updates
    locationManager?.allowsBackgroundLocationUpdates = true
    locationManager?.pausesLocationUpdatesAutomatically = false

    locationManager?.startUpdatingLocation()
    // Also consider startMonitoringSignificantLocationChanges if you want less battery drain
  }

  func stopLocationUpdates() {
    locationManager?.stopUpdatingLocation()
    locationManager = nil
  }

  // CLLocationManagerDelegate
  func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
    // handle cases if needed
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let loc = locations.last else { return }

    // speed is in m/s; convert to km/h
    let speedMs = max(loc.speed, 0) // negative if invalid
    let speedKmh = speedMs * 3.6

    // If app is foreground, send event through method channel to Flutter
    if let channel = methodChannel, UIApplication.shared.applicationState == .active {
      channel.invokeMethod("nativeLocationUpdate", arguments: ["speed": speedKmh])
    }

    // If in background and speed > threshold, send a local notification
    if UIApplication.shared.applicationState != .active {
      if speedKmh > speedThresholdKmh {
        sendBackgroundNotification(speed: speedKmh)
        // also notify Flutter (method channel will be received when app next comes to foreground)
        methodChannel?.invokeMethod("backgroundSpeedAlert", arguments: ["speed": speedKmh])
      }
    } else {
      // Optionally you can also alert on foreground here if needed
    }
  }

  // Send local notification from native when in background
  func sendBackgroundNotification(speed: Double) {
    let content = UNMutableNotificationContent()
    content.title = "Cảnh báo khi lái xe"
    content.body = "Phát hiện di chuyển \(String(format: \"%.1f\", speed)) km/h. Mở ứng dụng để kiểm tra."
    content.sound = UNNotificationSound.default

    // fire immediately
    let req = UNNotificationRequest(identifier: "driver_bg_alert_\(UUID().uuidString)", content: content, trigger: nil)
    UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
  }

  // Optional: handle errors
  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    print("Location manager error: \(error.localizedDescription)")
  }
}