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
/// **「铺满整屏」那一半在原生侧**：`MainActivity.onCreate` 里的
/// `WindowCompat.setDecorFitsSystemWindows(window, false)`。它曾经是 Dart 侧的
/// `SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge)`，但实测在
/// 小米 9 + Android 11 上要 **~800ms** 才返回，而且会把同一根平台线程上的其它
/// 平台通道一起堵住——那正好是冷启动最贵的窗口。原生化之后第一帧天然就是边到边。
///
/// 本文件负责另一半：[appSystemUiOverlayRegion] 挂在 `MaterialApp.builder` 上，
/// 把两条栏的颜色与图标明暗钉到**应用当前生效的主题**；常暗的会话页再用
/// [appSystemUiOverlayStyle] 自己覆写一层。

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
