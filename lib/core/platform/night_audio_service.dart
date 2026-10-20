import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 起「夜间录音前台服务」的结果。
///
/// **五个值不是把一件事拆成五种说法，而是三个不同的处置**：
/// - [started] / [unsupported] / [failed] → **照旧去开流**。拿不到前台服务不等于录不了音：
///   iOS 根本没有这条通道（`unsupported`），而平台偶发失败时应用仍在前台，本来就录得下来。
/// - [notForeground] / [missingPermission] → **不进录音态**，也不去开一个注定收到静音的
///   麦克风，抛出带中文说明的错误。
///
/// 后两条必须分开：一个说「此刻不行，等你回到前台」，另一个说「这个包不行，去更新」。
enum NightAudioServiceResult {
  /// 前台服务已经起来了。
  started,

  /// 应用此刻不可见，系统不许起前台服务（API 31+ 直接抛），就算硬起也拿不到麦克风。
  notForeground,

  /// 应用缺少后台录音所需的权限（`RECORD_AUDIO` 不在手里，或安装包没声明
  /// `FOREGROUND_SERVICE_MICROPHONE`）。
  missingPermission,

  /// 这个平台没有这条通道（如 iOS），或通道还没接上（widget 测试里）。
  unsupported,

  /// 通道在、权限也在，但平台侧起服务失败。原因不猜。
  failed,
}

/// 夜间录音前台服务的入口。
///
/// **它只负责「让系统认为应用还在前台」这一件事，一个采样都不采。** 采集链路完全不动：
/// PCM 仍由 `record` 插件交给 Dart isolate。
///
/// 抽成接口是为了让单元 / widget 测试注入假实现——**这条链路一个测试都不该碰平台通道**。
abstract class NightAudioService {
  /// 起服务。**必须在应用可见时调**，见 [NightAudioServiceResult.notForeground]。
  Future<NightAudioServiceResult> start();

  /// 撤服务。已经在录的那一场由调用方先停流、后调它。
  Future<void> stop();
}

/// 没有 Android 前台服务的平台与测试用的空实现。
///
/// 返回 [NightAudioServiceResult.unsupported] 而不是抛：调用方**照旧开流**，
/// iOS 上的录音一个字都不该被它拦下来。
class NoopNightAudioService implements NightAudioService {
  const NoopNightAudioService();

  @override
  Future<NightAudioServiceResult> start() async =>
      NightAudioServiceResult.unsupported;

  @override
  Future<void> stop() async {}
}

/// 包 `night_sleep/recording_service` 这条 MethodChannel 的实现。
///
/// Kotlin 侧见 `android/app/src/main/kotlin/com/example/night_sleep/`
/// 的 `NightAudioServiceHandler.kt` 与 `NightRecordingService.kt`。
///
/// 两种失败分开处理，因为它们对调用方的意义不同：
/// - **`MissingPluginException` → [NightAudioServiceResult.unsupported]**。它有两个来源：
///   iOS 上通道根本不存在，以及 **widget 测试里没有人应答那条通道**。后者尤其要紧——
///   漏了这一条，测试里的夜间录音会被全数拦下，表现成「测试里录音永远起不来」。
/// - **`PlatformException` → [NightAudioServiceResult.failed]**。通道在，但它报错了。
class MethodChannelNightAudioService implements NightAudioService {
  const MethodChannelNightAudioService();

  /// 与 Kotlin 侧 `MainActivity.RECORDING_SERVICE_CHANNEL`、以及
  /// `NightAudioServiceHandler` 的码表逐字对应，改一处必须改两处。
  static const channelName = 'night_sleep/recording_service';

  static const _channel = MethodChannel(channelName);

  @override
  Future<NightAudioServiceResult> start() async {
    // 非 Android 直接返回 `unsupported`（**不去碰通道**）：iOS 上真要调一次才会拿到
    // `MissingPluginException`，而那一次多余往返的代价是每次起录都要等一个平台往返。
    if (defaultTargetPlatform != TargetPlatform.android) {
      return NightAudioServiceResult.unsupported;
    }

    final String? code;
    try {
      code = await _channel.invokeMethod<String>('start');
    } on MissingPluginException {
      return NightAudioServiceResult.unsupported;
    } on PlatformException {
      return NightAudioServiceResult.failed;
    }

    switch (code) {
      case 'started':
        return NightAudioServiceResult.started;
      case 'notForeground':
        return NightAudioServiceResult.notForeground;
      case 'missingPermission':
        return NightAudioServiceResult.missingPermission;
      case 'failed':
        return NightAudioServiceResult.failed;
      // **未知的码一律 failed，不猜。** 猜错的方向是「以为起来了、其实没有」——
      // 那会连着开一个收不到声音的麦克风，而界面写着「录音中」。
      default:
        return NightAudioServiceResult.failed;
    }
  }

  @override
  Future<void> stop() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    // 撤服务失败不该把调用方（收尾那一段）拖累掉——上层已经用
    // 「先停流、后撤服务」的顺序把录音本身保住了。
    try {
      await _channel.invokeMethod<void>('stop');
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }
}

/// 前台服务的注入口（与 `reminderSchedulerProvider` 同款）。
final nightAudioServiceProvider = Provider<NightAudioService>(
  (ref) => const MethodChannelNightAudioService(),
);
