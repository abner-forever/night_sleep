import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/platform/haptics.dart';
import '../core/theme/app_tokens.dart';
import '../core/widgets/app_icons.dart';
import '../core/widgets/app_logo.dart';
import '../core/widgets/app_sheet.dart' show openSheetCount;
import '../core/widgets/bottom_fade.dart';
import '../core/widgets/liquid_glass.dart';
import '../core/widgets/top_fade.dart';

/// The four primary destinations. Order matches the prototype's `NAV`.
enum AppTab {
  home('home', '首页'),
  log('log', '回顾'),
  stats('stats', '统计'),
  settings('settings', '设置');

  const AppTab(this.id, this.label);

  final String id;
  final String label;
}

/// The selected destination.
///
/// Held in a provider rather than widget state so a page can move the user
/// somewhere else — saving a record returns to Home, which is what the
/// prototype does.
final activeTabProvider = StateProvider<AppTab>((ref) => AppTab.home);

/// The bar's own height: `min-height: 56px` inside `padding: 4px 6px`, plus the
/// `Border.all(width: 0.5)` that wraps it — 1px in total, not 1.5.
/// `test/tab_bar_inset_test.dart` 量的是渲染出来的胶囊，改这里之前先跑它。
const double _tabBarHeight = 56 + 8 + 1;

/// iOS 上标签条能从安全区底部往回收多少。
///
/// 原型写的是 `bottom: max(12px, env(safe-area-inset-bottom))`，本实现特意
/// **更贴底** 14px（见规格书第 8 章偏差 #21）：安全区底部那 34px 是留给系统
/// 手势的**整块**空间，而 home indicator 本身只画在底部 8–13px，照搬安全区
/// 会让玻璃胶囊平白悬空一大截。
const double _iosTabBarFloatRelief = 14;

/// 标签条玻璃胶囊下边缘到屏幕底边的浮起量。
///
/// [tabBarReserve] 与 `_TabBar` 必须共用它：两处各算一遍时，任何一侧单独
/// 调整都会让页面底部留白与胶囊的位置脱节——留白算小了最后一行压进玻璃，
/// 算大了玻璃上方空出一条。
///
/// **「能借多少」取决于手势指示条画在安全区的哪一段，这一点两个平台不一样，
/// 也是这个文件里唯一按平台分叉的地方**：
///
///  * iOS 的 home indicator 5pt 高、贴底 8pt，34pt 的安全区里空着 21pt，
///    所以借得起那 14pt——胶囊底边落到离底 20pt，指示条上沿之上还留 7pt；
///  * Android 的手势条贴在安全区**下沿**（真机 MI 9 / API 30 实测：16dp 的安全区
///    里只有约 5dp 是空的），借不了。照搬 iOS 那个 14 的后果很具体——胶囊底边落到
///    `y≈2307`、手势条上沿在 `y≈2312`，**只差 5px，看着就是压在一起**。
///    所以 Android 整个让开安全区，不去借（改完胶囊底边在 `y=2296`，中间留出 14px）。
///
/// 安全区为零或较小时，仍保留下限 12px。
double tabBarFloat(BuildContext context) {
  final safeBottom = MediaQuery.paddingOf(context).bottom;
  final relief = defaultTargetPlatform == TargetPlatform.android
      ? 0.0
      : _iosTabBarFloatRelief;
  final float = safeBottom - relief;
  return float > 12 ? float : 12;
}

/// How much vertical room the floating bar takes out of the page, measured from
/// the bottom of the viewport: the bar itself, its float offset
/// ([tabBarFloat]), and a little breathing room so a card never ends flush
/// against the glass.
double tabBarReserve(BuildContext context) =>
    _tabBarHeight + tabBarFloat(context) + 16;

/// How much room the floating tab bar needs at the bottom of the page.
///
/// Applied by each page's scroll view, not by the shell. Reserved *outside* the
/// scroll view the bar's band becomes an opaque strip the content is cut off
/// above; reserved inside, the viewport still reaches the bottom of the screen —
/// content scrolls under the translucent bar the way the design intends — and
/// the last item can still be scrolled clear of it.
/// This is the whole reserve, not just the bar's own height: the bar floats
/// [tabBarFloat] above the bottom edge, and the inset has to clear that too or
/// the last card comes to rest behind the glass.
double pageBottomInset(BuildContext context) {
  // Wide layouts have no floating bar, so they only need breathing room —
  // reserving the bar's band there would leave a gap nothing sits in.
  if (MediaQuery.sizeOf(context).width >= kWideLayoutBreakpoint) return 40;
  return tabBarReserve(context);
}

/// 页面在状态栏下方需要的留白。
///
/// 与 [pageBottomInset]、[pageGutter] 一样，由各页自己的滚动视图施加，
/// **不是**外壳上的 `SafeArea`。外壳级的 `SafeArea` 会把整个外壳按该内边距
/// 一起下移，于是渐变带的原点落到了状态栏下沿：状态栏那段完全没有渐变填充，
/// 而带内第一个停点正好是满值，两者形成一条横贯页面的硬分界。
/// 把留白放在这里，视口才能顶到物理顶端，内容滚进状态栏下面，
/// 渐变带整整 144px 也才有东西可模糊。
double pageTopInset(BuildContext context) =>
    MediaQuery.paddingOf(context).top +
    (MediaQuery.sizeOf(context).width >= kWideLayoutBreakpoint ? 48 : 24);

/// The page's horizontal gutter.
///
/// Applied by each page's own scroll view rather than by the shell, so the
/// scroll viewport itself spans the full width. That matters for shadows: a
/// scroll view clips at its own edge, so padding applied *outside* it leaves a
/// full-width card with nowhere for its shadow to fall, and the shadow reads as
/// cut off down both sides. Inside the scroll view, the gutter becomes room the
/// shadow can use — which is what a content inset does on iOS.
double pageGutter(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kWideLayoutBreakpoint ? 52 : 16;

/// Lays out the current page with the app's navigation.
///
/// Phone: content fills the viewport, a floating tab bar pill sits above the
/// bottom edge, and a translucent fade washes the top once the page scrolls.
/// Wide: a sidebar replaces the tab bar, the content column is capped at 720px,
/// and the fade is off — matching the design, which hides it at ≥768px.
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.current,
    required this.onSelect,
    required this.child,
    this.onOpenNoise,
  });

  final AppTab current;
  final ValueChanged<AppTab> onSelect;
  final Widget child;
  final VoidCallback? onOpenNoise;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  bool _scrolled = false;

  bool _onScroll(ScrollNotification notification) {
    // Only vertical scrolling of the page itself should raise the fade; a
    // horizontal drag inside a chart must not.
    if (notification.metrics.axis != Axis.vertical) return false;
    final next = notification.metrics.pixels > TopFade.revealAfter;
    if (next != _scrolled) setState(() => _scrolled = next);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= kWideLayoutBreakpoint;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isWide)
              _Sidebar(
                  current: widget.current,
                  onSelect: widget.onSelect,
                  onOpenNoise: widget.onOpenNoise),
            Expanded(
              child: Stack(
                children: [
                  NotificationListener<ScrollNotification>(
                    onNotification: _onScroll,
                    // No bottom padding here: the pages inset their own scroll
                    // views. See [pageBottomInset].
                    child: widget.child,
                  ),
                  if (!isWide)
                    // Retired while a sheet is open, as the design does.
                    ValueListenableBuilder<int>(
                      valueListenable: openSheetCount,
                      builder: (context, open, _) => TopFade(
                        visible: _scrolled && open == 0,
                      ),
                    ),
                  if (!isWide)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      // 与 `TopFade` 不同：弹层打开时**有意**不收起。蒙层本来就盖住
                      // 整屏，带子只是跟着一起变暗；专门收起反而会在开弹层那一瞬
                      // 闪一下（设计规格「边界情况」表）。
                      // 高度由标签条的实际预留量推导：预留多少，带子就盖住多少，
                      // 再多 20px 供内容化开。写死 120 会在别的机型上脱节。
                      // 排在 `_TabBar` **之前**——`BackdropFilter` 模糊的是它之前
                      // 画好的画面，排在后面会把玻璃胶囊本身糊掉。
                      child: BottomFade(height: tabBarReserve(context) + 20),
                    ),
                  if (!isWide)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _TabBar(
                        current: widget.current,
                        onSelect: widget.onSelect,
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// `ios-tab-bar` — a floating, blurred pill with a sliding accent capsule.
class _TabBar extends StatelessWidget {
  const _TabBar({required this.current, required this.onSelect});

  final AppTab current;
  final ValueChanged<AppTab> onSelect;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final padding = MediaQuery.of(context).padding;
    const tabs = AppTab.values;
    final index = tabs.indexOf(current);

    return Padding(
      // 左右仍是 `max(12px, env(safe-area-inset-*))`（横屏刘海要避开）；
      // 底部改走 [tabBarFloat]，与页面底部留白同源。
      padding: EdgeInsets.only(
        left: padding.left > 12 ? padding.left : 12,
        right: padding.right > 12 ? padding.right : 12,
        bottom: tabBarFloat(context),
      ),
      // 液态玻璃整块托底：阴影在裁剪之外，否则会被自己的 `ClipRRect` 丢掉。
      child: LiquidGlass(
        borderRadius: BorderRadius.circular(AppRadii.tabBar),
        blur: 28,
        saturation: 1.6,
        tint: tokens.bgNavbar,
        // 比旧 Container 的 4 / 6 各多半像素：旧描边占掉的 0.5px 现在由
        // painter 画在内侧，不再参与布局；补回来胶囊总高才仍是 65。
        padding: const EdgeInsets.symmetric(horizontal: 6.5, vertical: 4.5),
        shadow: [
          BoxShadow(
            color: const Color(0xFF1F2D51).withValues(alpha: 0.08),
            blurRadius: 34,
            offset: const Offset(0, -8),
          ),
        ],
        child: LayoutBuilder(
          builder: (context, constraints) {
            final slot = constraints.maxWidth / tabs.length;
            return Stack(
              children: [
                // Sliding accent capsule behind the active tab.
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 420),
                  curve: AppMotion.standardCurve,
                  left: index * slot,
                  top: 3,
                  bottom: 3,
                  width: slot,
                  child: _ActiveTabCapsule(color: tokens.accent),
                ),
                Row(
                  children: [
                    for (final tab in tabs)
                      Expanded(
                        child: _TabItem(
                          tab: tab,
                          active: tab == current,
                          onTap: () => onSelect(tab),
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 选中标签背后的玻璃胶囊。
///
/// 与外层标签条共用一套「上亮下暗」的语言：底色是从 accent 淡到更淡的两段
/// 渐变，加一条 0.5px 的内缘描边——它不再是一块实色块，而是被点亮的一小片玻璃。
///
/// **不要在胶囊顶部再画一条 1px 镜面线。** 浅色模式下白线压在蓝色胶囊上是一根
/// 实打实的硬边，看着像贴纸；渐变底色本身已经让上半部分更亮，足够了。
class _ActiveTabCapsule extends StatelessWidget {
  const _ActiveTabCapsule({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.20),
            color.withValues(alpha: 0.10),
          ],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: color.withValues(alpha: 0.12), width: 0.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1F3970).withValues(alpha: 0.08),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
    );
  }
}

class _TabItem extends StatefulWidget {
  const _TabItem(
      {required this.tab, required this.active, required this.onTap});

  final AppTab tab;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_TabItem> createState() => _TabItemState();
}

class _TabItemState extends State<_TabItem> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final tab = widget.tab;
    final active = widget.active;
    final color = active ? tokens.accent : tokens.textMuted;

    // Home, Log and Statistics swap in a filled glyph when active; Settings has
    // no filled counterpart in the design and thickens its stroke instead.
    final glyph = active
        ? AppIcons.filledTabGlyph(tab.id, size: 21, color: color) ??
            _strokedGlyph(tab, color, active)
        : _strokedGlyph(tab, color, active);

    return Semantics(
      selected: active,
      button: true,
      label: tab.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: () {
          AppHaptics.select();
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _pressed ? 0.94 : 1,
          duration: const Duration(milliseconds: 160),
          curve: AppMotion.standardCurve,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 25,
                  height: 28,
                  child: Center(
                    // 实心 / 线框字形之间淡入淡出，而不是「啪」地换一个符号。
                    // 位移胶囊已经在滑，图标跟着换颜色与形状，整条标签才像一次动作。
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(
                          scale: Tween<double>(begin: 0.88, end: 1)
                              .animate(animation),
                          child: child,
                        ),
                      ),
                      child: KeyedSubtree(
                        key: ValueKey('${tab.id}-$active'),
                        child: glyph,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                AnimatedDefaultTextStyle(
                  duration: AppDurations.control,
                  curve: AppMotion.standardCurve,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    letterSpacing: -0.2,
                    color: color,
                  ),
                  child: Text(tab.label),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Widget _strokedGlyph(AppTab tab, Color color, bool active) {
  final strokeWidth = active ? 2.1 : 1.65;
  return switch (tab) {
    AppTab.home =>
      AppIcons.moon(size: 21, color: color, strokeWidth: strokeWidth),
    AppTab.log =>
      AppIcons.pen(size: 21, color: color, strokeWidth: strokeWidth),
    AppTab.stats =>
      AppIcons.chart(size: 21, color: color, strokeWidth: strokeWidth),
    AppTab.settings =>
      AppIcons.gear(size: 21, color: color, strokeWidth: strokeWidth),
  };
}

/// `ios-sidebar` — the wide-layout navigation rail.
class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.current,
    required this.onSelect,
    this.onOpenNoise,
  });

  final AppTab current;
  final ValueChanged<AppTab> onSelect;
  final VoidCallback? onOpenNoise;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final padding = MediaQuery.of(context).padding;

    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          width: 240,
          decoration: BoxDecoration(
            color: tokens.bgRaised.withValues(alpha: 0.76),
            border: Border(right: BorderSide(color: tokens.glassBorder)),
          ),
          padding: EdgeInsets.only(
            top: padding.top + 40,
            bottom: padding.bottom + 16,
            left: padding.left + 12,
            right: 12,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 8, right: 8, bottom: 32),
                child: Row(
                  children: [
                    const AppLogo(size: 40, cornerRadius: 12),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '夜深',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.4,
                            color: tokens.textPrimary,
                          ),
                        ),
                        Text(
                          '睡眠记录',
                          style:
                              TextStyle(fontSize: 12, color: tokens.textMuted),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                // **中段可以滚**：头部那块 logo 与底部那张助眠音效卡都是定高的，
                // 矮窗口（手机横屏，实测 800×360 那一档）里三层加起来会撑破侧边栏
                // ——用户看到的就是左下角那条黑黄警告。让成滚动而不是把导航项压扁：
                // 压扁的导航比要滚还难用，而滚动在鼠标滚轮与触摸上都成立。
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final tab in AppTab.values)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: _SidebarItem(
                            tab: tab,
                            active: tab == current,
                            onTap: () => onSelect(tab),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (onOpenNoise != null)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    AppHaptics.tap();
                    onOpenNoise!();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: tokens.accentSoft,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        AppIcons.music(
                            size: 16,
                            color: tokens.textMuted,
                            strokeWidth: 1.6),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '助眠音效',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: tokens.textPrimary,
                              ),
                            ),
                            Text(
                              '白噪音',
                              style: TextStyle(
                                  fontSize: 11, color: tokens.textMuted),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem(
      {required this.tab, required this.active, required this.onTap});

  final AppTab tab;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final color = active ? tokens.accent : tokens.textSecondary;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        AppHaptics.select();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: active ? tokens.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            _strokedGlyph(
                tab, active ? tokens.accent : tokens.textMuted, active),
            const SizedBox(width: 12),
            AnimatedDefaultTextStyle(
              duration: AppDurations.control,
              curve: AppMotion.standardCurve,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: color,
              ),
              child: Text(tab.label),
            ),
          ],
        ),
      ),
    );
  }
}
