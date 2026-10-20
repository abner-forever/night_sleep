import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Android 的系统栏（状态栏 / 导航栏）落地方式。
///
/// iOS 上应用本来就铺满整屏：两条系统栏浮在内容**之上**、自身透明，所以安全区
/// 的含义是「内容该躲开多少」。Android 默认**不是**这样——`android/` 下没有任何
/// 一条系统栏配置时，引擎只申请到 `LAYOUT_FULLSCREEN`（状态栏盖在内容上），
/// 导航栏那一块仍然被排除在内容区之外，于是：
///
///  * 顶部压着系统在透明状态栏背后自动加的对比度蒙层，浅色主题下就是一整条灰带；
///  * 底部是系统自己画的一条不透明黑条，把页面**截断**在导航栏上沿。
///
/// 这两条都是「不像 iOS」的直接来源。这里把 Android 拉齐到 iOS 的语义：内容铺到
/// 屏幕物理边缘，两条栏都设成透明、并关掉那层自动蒙层。
///
/// 调用点只有三处：启动时调一次 [enableEdgeToEdge]；[appSystemUiOverlayRegion]
/// 挂在 `MaterialApp.builder` 上跟随应用主题；常暗的会话页再用
/// [appSystemUiOverlayStyle] 自己覆写一层。

/// 让内容铺满整屏（含两条系统栏背后）。
///
/// **只在 Android 上调。** iOS 本来就是边到边，调它等于空操作。
///
/// Android 10（API 29）以下这一调用是空操作：引擎的
/// `PlatformPlugin.setSystemChromeEnabledSystemUIMode` 里有 `SDK_INT >= 29` 的门槛，
/// 低于它的设备维持旧行为（状态栏盖在内容上、导航栏把内容顶起来）。
/// **这不是遗漏，是引擎自己就不支持**，不要试图在这里补。
Future<void> enableEdgeToEdge() async {
  if (defaultTargetPlatform != TargetPlatform.android) return;
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
}

/// 跟随应用主题明暗的系统栏样式。
///
/// **不能直接用 `SystemUiOverlayStyle.light` / `.dark` 这两个预设**：它们把
/// `systemNavigationBarColor` 写死成不透明黑（`0xFF000000`），导航栏会重新变回一条
/// 黑带——正是这次要消掉的东西。所以字段自己写全，四条要点：
///
///  * 两条栏都透明，页面自己的背景（`Atmosphere` / `NightBackdrop`）铺到物理边缘；
///  * `*ContrastEnforced: false` 关掉 Android 10+ 在**透明**栏背后自动加的半透明
///    蒙层。顶部那条灰带就是它：底下明明是页面自己的背景 `(240,242,248)`，
///    蒙上 25% 黑之后恰好是实测到的 `(181,181,186)`；
///  * 图标明暗跟着**应用主题**走，不是跟系统设置——应用内可以单独切浅色 / 深色，
///    系统却可能停在另一边（会话页另外覆写，见下）；
///  * `statusBarBrightness` 一并给出：它和 [statusBarIconBrightness] 语义相反，
///    且只在 iOS 上生效，两个平台各自读各自的那个。
SystemUiOverlayStyle appSystemUiOverlayStyle(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
    statusBarBrightness: dark ? Brightness.dark : Brightness.light,
    systemStatusBarContrastEnforced: false,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness:
        dark ? Brightness.light : Brightness.dark,
    systemNavigationBarContrastEnforced: false,
  );
}

/// `MaterialApp.builder` 上挂的那一层：把系统栏样式钉到**应用当前生效的主题**上。
///
/// 挂在这里而不是各页各自声明，是因为它得覆盖全部路由（推入页、弹层都在
/// `MaterialApp` 的 Navigator 里）；挂在这里而不是 `main()` 里调一次
/// `SystemChrome.setSystemUIOverlayStyle`，是因为应用内可以单独切浅色 / 深色
/// ——一次性调用只在启动那一刻正确，之后系统栏再也不跟着变。
///
/// 各页自己的 `AnnotatedRegion`（如常暗的会话页）压在它上面，仍然说话算数：
/// `AnnotatedRegion` 取的是覆盖该区域的最上面一层。
Widget appSystemUiOverlayRegion(BuildContext context, Widget? child) =>
    AnnotatedRegion<SystemUiOverlayStyle>(
      value: appSystemUiOverlayStyle(Theme.of(context).brightness),
      child: child ?? const SizedBox.shrink(),
    );
