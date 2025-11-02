import UIKit
import Flutter

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
    
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        
        // GeneratedPluginRegistrant đảm bảo Flutter plugin được khởi tạo
        GeneratedPluginRegistrant.register(with: self)
        
        // Cho phép background fetch
        application.setMinimumBackgroundFetchInterval(UIApplication.backgroundFetchIntervalMinimum)
        
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    
    // Optional: handle background fetch nếu cần
    override func application(
        _ application: UIApplication,
        performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // Gọi Flutter hoặc plugin để lấy dữ liệu GPS/cảm biến
        completionHandler(.newData)
    }
}