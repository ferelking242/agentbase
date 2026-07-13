import UIKit
import Flutter

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  let flutterEngine = FlutterEngine(name: "main_engine")

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    flutterEngine.run()
    GeneratedPluginRegistrant.register(with: flutterEngine)

    let flutterVC = FlutterViewController(engine: flutterEngine, nibName: nil, bundle: nil)
    flutterVC.view.backgroundColor = UIColor(red: 0.055, green: 0.055, blue: 0.086, alpha: 1)

    let window = UIWindow(frame: UIScreen.main.bounds)
    window.rootViewController = flutterVC
    window.backgroundColor = UIColor(red: 0.055, green: 0.055, blue: 0.086, alpha: 1)
    window.makeKeyAndVisible()
    self.window = window

    return true
  }
}
