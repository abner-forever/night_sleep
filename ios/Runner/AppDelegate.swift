import Flutter
import CoreMotion
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var compassChannel: FlutterEventChannel?
  private var exportStorageChannel: FlutterMethodChannel?
  private let compassHandler = CompassStreamHandler()
  private let exportStorageHandler = ExportStorageHandler()
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
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NightSleepExportStorage") {
      let channel = FlutterMethodChannel(
        name: "night_sleep/export_storage",
        binaryMessenger: registrar.messenger()
      )
      channel.setMethodCallHandler(exportStorageHandler.handle)
      exportStorageChannel = channel
    }
  }
}

private final class ExportStorageHandler {
  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "location", "resetLocation":
      result(locationInfo())
    case "chooseLocation":
      // iOS 的默认目录位于“文件”App 的夜深文件夹。自选持久目录需要额外的
      // security-scoped bookmark，当前入口不提供一个看似可用但会失效的按钮。
      result(nil)
    case "save":
      guard let arguments = call.arguments as? [String: Any],
            let rawFiles = arguments["files"] as? [[String: Any]] else {
        result(FlutterError(
          code: "invalid_source",
          message: "没有要保存的文件。",
          details: nil
        ))
        return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        let response = self.saveAll(rawFiles)
        DispatchQueue.main.async { result(response) }
      }
    case "latestBackup":
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          let path = try self.latestBackupPath()
          DispatchQueue.main.async { result(path) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(
              code: "storage_error",
              message: "无法读取默认导出目录。",
              details: nil
            ))
          }
        }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func locationInfo() -> [String: Any] {
    [
      "label": "文件 App/夜深/导出",
      "custom": false,
      "canChoose": false
    ]
  }

  private func saveAll(_ rawFiles: [[String: Any]]) -> [String: Any] {
    var saved = 0
    var failed = false
    for raw in rawFiles {
      do {
        try saveOne(raw)
        saved += 1
      } catch {
        failed = true
        break
      }
    }
    return [
      "savedCount": saved,
      "fileCount": rawFiles.count,
      "failed": failed
    ]
  }

  private func saveOne(_ raw: [String: Any]) throws {
    guard let rawPath = raw["path"] as? String else {
      throw ExportStorageError.invalidSource
    }
    let source = URL(fileURLWithPath: rawPath).resolvingSymlinksInPath()
    let temporaryRoot = FileManager.default.temporaryDirectory
      .resolvingSymlinksInPath()
    let prefix = temporaryRoot.path.hasSuffix("/")
      ? temporaryRoot.path
      : temporaryRoot.path + "/"
    guard source.path.hasPrefix(prefix) else {
      throw ExportStorageError.invalidSource
    }
    guard FileManager.default.fileExists(atPath: source.path) else {
      throw ExportStorageError.invalidSource
    }

    let directory = try exportDirectory()
    let rawName = raw["fileName"] as? String ?? source.lastPathComponent
    let fileName = sanitizedFileName(rawName)
    let destination = directory.appendingPathComponent(fileName)
    if FileManager.default.fileExists(atPath: destination.path) {
      try FileManager.default.removeItem(at: destination)
    }
    try FileManager.default.copyItem(at: source, to: destination)
  }

  private func latestBackupPath() throws -> String? {
    let directory = try exportDirectory()
    let files = try FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.contentModificationDateKey],
      options: [.skipsHiddenFiles]
    )
    let latest = files
      .filter {
        let ext = $0.pathExtension.lowercased()
        return ext == "zip" || ext == "json"
      }
      .max { lhs, rhs in
        let left = (try? lhs.resourceValues(
          forKeys: [.contentModificationDateKey]
        ).contentModificationDate) ?? .distantPast
        let right = (try? rhs.resourceValues(
          forKeys: [.contentModificationDateKey]
        ).contentModificationDate) ?? .distantPast
        return left < right
      }
    return latest?.path
  }

  private func exportDirectory() throws -> URL {
    guard let documents = FileManager.default.urls(
      for: .documentDirectory,
      in: .userDomainMask
    ).first else {
      throw ExportStorageError.directoryUnavailable
    }
    let directory = documents.appendingPathComponent("导出", isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    return directory
  }

  private func sanitizedFileName(_ raw: String) -> String {
    var invalid = CharacterSet(charactersIn: "/\\:*?\"<>|")
    invalid.formUnion(.controlCharacters)
    let cleaned = raw.components(separatedBy: invalid).joined(separator: "_")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return String(cleaned.prefix(200)).isEmpty ? "夜深导出文件" : String(cleaned.prefix(200))
  }
}

private enum ExportStorageError: Error {
  case invalidSource
  case directoryUnavailable
}

private final class CompassStreamHandler: NSObject, FlutterStreamHandler {
  private let motionManager = CMMotionManager()

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    let frames = CMMotionManager.availableAttitudeReferenceFrames()
    guard motionManager.isDeviceMotionAvailable, frames.contains(.xMagneticNorthZVertical) else {
      events(FlutterError(code: "unavailable", message: "此设备没有可用的罗盘传感器", details: nil))
      return nil
    }
    // 60 Hz：30 Hz 在 60 Hz 屏幕上转动会一卡一卡。与 Android 侧对齐。
    motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
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
        // 水平仪气泡：设备 +X / +Y 轴抬起的角度，正 = 右 / 上抬。
        "tiltX": asin(min(1.0, max(-1.0, upX))) * 180.0 / .pi,
        "tiltY": asin(min(1.0, max(-1.0, upY))) * 180.0 / .pi,
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
