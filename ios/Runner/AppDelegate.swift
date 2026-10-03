import Flutter
import CoreMotion
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var compassChannel: FlutterEventChannel?
  private let compassHandler = CompassStreamHandler()
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 没有 delegate 时，应用在前台收到的本地通知会被系统压掉——
    // 表现为「提醒到点了却什么都没出现」。
    //
    // 直接赋 `self`：iOS 上 `FlutterAppDelegate` 确实实现了
    // `UNUserNotificationCenterDelegate`，转换恒成立——写成 `as?` 会招来
    // “conditional cast always succeeds” 警告。
    // 前台展示通知正是靠这一行，不要删。
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NightSleepCompass") {
      let channel = FlutterEventChannel(name: "night_sleep/compass", binaryMessenger: registrar.messenger())
      channel.setStreamHandler(compassHandler)
      compassChannel = channel
    }
  }
}

private final class CompassStreamHandler: NSObject, FlutterStreamHandler {
  private let motionManager = CMMotionManager()

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    let frames = CMMotionManager.availableAttitudeReferenceFrames()
    guard motionManager.isDeviceMotionAvailable, frames.contains(.xMagneticNorthZVertical) else {
      events(FlutterError(code: "unavailable", message: "此设备没有可用的罗盘传感器", details: nil))
      return nil
    }
    motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
    motionManager.showsDeviceMovementDisplay = true
    motionManager.startDeviceMotionUpdates(using: .xMagneticNorthZVertical, to: .main) { motion, error in
      if let error = error {
        events(FlutterError(code: "sensor_error", message: error.localizedDescription, details: nil))
        return
      }
      guard let motion = motion else { return }
      let gravity = motion.gravity
      let length = sqrt(gravity.x * gravity.x + gravity.y * gravity.y + gravity.z * gravity.z)
      guard length > 0 else { return }
      let upX = -gravity.x / length
      let upY = -gravity.y / length
      let upZ = -gravity.z / length
      let magnetic = motion.magneticField.field
      let projection = magnetic.x * upX + magnetic.y * upY + magnetic.z * upZ
      let northX = magnetic.x - projection * upX
      let northY = magnetic.y - projection * upY
      let northZ = magnetic.z - projection * upZ
      let horizontal = sqrt(northX * northX + northY * northY + northZ * northZ)
      let tilt = acos(min(1.0, max(-1.0, upZ))) * 180.0 / .pi
      let strength = sqrt(magnetic.x * magnetic.x + magnetic.y * magnetic.y + magnetic.z * magnetic.z)
      var reading: [String: Any] = [
        "timestamp": motion.timestamp,
        "tilt": tilt,
        "fieldStrength": strength,
        "accuracy": motion.magneticField.accuracy.rawValue,
        "rotationRate": -(motion.rotationRate.x * upX + motion.rotationRate.y * upY + motion.rotationRate.z * upZ)
      ]
      if horizontal > 1.0, tilt < 60.0, motion.magneticField.accuracy != .uncalibrated {
        let eastX = (northY * upZ - northZ * upY) / horizontal
        let eastY = (northZ * upX - northX * upZ) / horizontal
        let normalizedNorthX = northX / horizontal
        let normalizedNorthY = northY / horizontal
        let orientation = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.interfaceOrientation ?? .portrait
        let forward: (Double, Double)
        switch orientation {
        case .landscapeLeft: forward = (-1, 0)
        case .landscapeRight: forward = (1, 0)
        case .portraitUpsideDown: forward = (0, -1)
        default: forward = (0, 1)
        }
        let angle = atan2(eastX * forward.0 + eastY * forward.1, normalizedNorthX * forward.0 + normalizedNorthY * forward.1) * 180.0 / .pi
        reading["heading"] = (angle + 360.0).truncatingRemainder(dividingBy: 360.0)
      }
      events(reading)
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    motionManager.stopDeviceMotionUpdates()
    return nil
  }
}
