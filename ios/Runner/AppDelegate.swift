import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if #available(iOS 15.0, *) {
      ScreenTimeBridge.register(with: self.registrar(forPlugin: "ScreenTimeBridge")!)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
