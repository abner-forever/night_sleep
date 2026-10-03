import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// 打开「本应用」在系统设置里的那一页。
///
/// **与 `reminders.dart` 的 `openSystemSettings()` 是两回事。** 那个走
/// `flutter_local_notifications` 的通知设置页，只能落在「通知」那一项；麦克风权限
/// 被拒之后要跳的是应用自己的设置页，用户才能在那里打开麦克风——所以另做一个通用
/// 入口，不复用通知那个（复用了就等于跳到一个到不了麦克风的地方，却宣称能去授权）。
///
/// 抽成接口是为了让 widget 测试注入假实现，**不碰平台通道**。
abstract class AppSettingsLauncher {
  Future<void> open();
}

/// 用系统 URL scheme 跳转的实现。
///
/// 两个 scheme 都由 `url_launcher` 交给系统打开，不必自己写平台通道，也就不会在
/// 测试里漏出一条没被假实现挡住的通道。
class UrlAppSettingsLauncher implements AppSettingsLauncher {
  const UrlAppSettingsLauncher();

  /// 当前平台该跳的地址。做成静态纯函数，好让「跳的是不是对的那一页」可单测。
  static Uri uriFor(TargetPlatform platform) {
    switch (platform) {
      case TargetPlatform.iOS:
        // `UIApplication.openSettingsURLString` 的值：直接落在**本应用**那一页，
        // 麦克风开关就在上面。
        return Uri.parse('app-settings:');
      case TargetPlatform.macOS:
        // **不能只写 `x-apple.systempreferences:`**——那只会把用户丢到「系统设置」
        // 首页，他还得自己翻到隐私与安全性、再翻到麦克风。这里直接落到那个面板。
        return Uri.parse(
          'x-apple.systempreferences:com.apple.preference.security'
          '?Privacy_Microphone',
        );
      default:
        // Android 平台目录尚未生成（README「未实现」），这里给不出一个验证过的地址；
        // 退回 iOS 的写法只是不崩，不代表在别处能用。
        return Uri.parse('app-settings:');
    }
  }

  @override
  Future<void> open() async {
    try {
      await launchUrl(uriFor(defaultTargetPlatform));
    } catch (_) {
      // 跳转失败不该打断调用方：界面上那一行说明已经把该去哪里讲清楚了。
    }
  }
}

final appSettingsLauncherProvider = Provider<AppSettingsLauncher>(
  (ref) => const UrlAppSettingsLauncher(),
);
