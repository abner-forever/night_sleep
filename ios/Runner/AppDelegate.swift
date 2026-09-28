import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 没有 delegate 时，应用在前台收到的本地通知会被系统压掉——
    // 表现为「提醒到点了却什么都没出现」。
    //
    // 用可选转换而不是 `= self`：iOS 上 `FlutterAppDelegate` 确实实现了
    // `UNUserNotificationCenterDelegate`，所以 `self` 转换后非 nil，不是「可能失败」。
    // 前台展示通知正是靠这一行，不要删。
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
