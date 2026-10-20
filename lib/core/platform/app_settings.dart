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
/// 地址由 `url_launcher` 交给系统打开，不必自己写平台通道，也就不会在
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
      default:
        // **Android 上这一行是死按钮，且换个 URI 也修不好**（规格偏差 §5.4）。
        //
        // v3.11 起 Android 平台目录已生成（见 README「平台配置」），但这里仍然给不出
        // 一个能用的地址，原因有两条，缺一条都不够：
        //   1. `app-settings:` 是 iOS 的私有 scheme，Android 没有对应的 intent filter，
        //      `launchUrl` 会拿到 ActivityNotFoundException（本方法吞掉，界面无反馈）；
        //   2. API 30 起强制**包可见性**，就算换成 Android 真正认的
        //      `package:`，没有在清单里用 `<queries>` 声明过，系统同样不会把它交给任何人。
        //
        // 所以要真的能用，得走真正的 Intent（`ACTION_APPLICATION_DETAILS_SETTINGS`，
        // 通常是一个平台通道），或者补上 `<queries>` 声明——不是把下面这行改个字符串的事。
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
