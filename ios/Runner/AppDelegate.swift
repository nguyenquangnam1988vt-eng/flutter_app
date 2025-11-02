import UIKit
import Flutter

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Đăng ký tất cả plugin Flutter
    GeneratedPluginRegistrant.register(with: self)

    // Có thể thêm custom code iOS ở đây nếu muốn
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

}