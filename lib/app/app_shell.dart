import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/platform/haptics.dart';
import '../core/theme/app_tokens.dart';
import '../core/widgets/app_icons.dart';
import '../core/widgets/app_logo.dart';
import '../core/widgets/app_sheet.dart' show openSheetCount;
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

double _tabBarHeight(BuildContext context) => math.max(
      50,
      32 + MediaQuery.textScalerOf(context).scale(10) * 1.2,
    );

double tabBarFloat(BuildContext context) {
  final safeBottom = MediaQuery.paddingOf(context).bottom;
  return math.max(safeBottom, 10);
}

double tabBarReserve(BuildContext context) =>
    4 + _tabBarHeight(context) + tabBarFloat(context) + 16;

List<double> _tabBarSaturationMatrix(double saturation) {
  const lumR = 0.2126;
  const lumG = 0.7152;
  const lumB = 0.0722;
  final ir = (1 - saturation) * lumR;
  final ig = (1 - saturation) * lumG;
  final ib = (1 - saturation) * lumB;
  return <double>[
    ir + saturation,
    ig,
    ib,
    0,
    0,
    ir,
    ig + saturation,
    ib,
    0,
    0,
    ir,
    ig,
    ib + saturation,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];
}

double pageBottomInset(BuildContext context) {
  if (MediaQuery.sizeOf(context).width >= kWideLayoutBreakpoint) {
    return MediaQuery.paddingOf(context).bottom + 40;
  }
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
    MediaQuery.sizeOf(context).width >= kWideLayoutBreakpoint ? 36 : 20;

/// Lays out the current page with the app's navigation.
///
/// 手机使用全宽底部导航；滚动后保留顶部内容渐隐。
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
                      child: ValueListenableBuilder<int>(
                        valueListenable: openSheetCount,
                        builder: (context, open, child) => Visibility(
                          visible: open == 0,
                          maintainState: true,
                          maintainAnimation: true,
                          child: child!,
                        ),
                        child: _TabBar(
                          current: widget.current,
                          onSelect: widget.onSelect,
                        ),
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

class _TabBar extends StatelessWidget {
  const _TabBar({required this.current, required this.onSelect});

  final AppTab current;
  final ValueChanged<AppTab> onSelect;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final padding = MediaQuery.paddingOf(context);
    return ClipRect(
      key: const ValueKey('app-bottom-navigation'),
      child: BackdropFilter(
        filter: ui.ImageFilter.compose(
          outer: ui.ColorFilter.matrix(_tabBarSaturationMatrix(1.8)),
          inner: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tokens.bgNavbar,
            border: Border(
              top: BorderSide(color: tokens.border, width: 0.5),
            ),
            boxShadow: [
              BoxShadow(
                color: colorMix(
                  tokens.border,
                  0.42,
                  Colors.transparent,
                ),
                offset: const Offset(0, -1),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              padding.left,
              4,
              padding.right,
              tabBarFloat(context),
            ),
            child: Row(
              children: [
                for (final tab in AppTab.values)
                  Expanded(
                    child: _TabItem(
                      tab: tab,
                      active: tab == current,
                      onTap: () => onSelect(tab),
                    ),
                  ),
              ],
            ),
          ),
        ),
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

    // 四个标签都按设计稿在选中时切换实心图标。
    final glyph = _tabGlyph(context, tab, color, active);

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
        child: AnimatedOpacity(
          opacity: _pressed ? 0.58 : 1,
          duration: const Duration(milliseconds: 150),
          curve: AppMotion.standardCurve,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: _tabBarHeight(context)),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 28,
                  height: 27,
                  child: Center(
                    // 实心 / 线框字形之间淡入淡出，而不是「啪」地换一个符号。
                    // 位移胶囊已经在滑，图标跟着换颜色与形状，整条标签才像一次动作。
                    child: AnimatedSwitcher(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 220),
                      switchInCurve: const Cubic(0.2, 0.8, 0.3, 1.15),
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
                    height: 1.2,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                    letterSpacing: -0.1,
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

Widget _tabGlyph(
  BuildContext context,
  AppTab tab,
  Color color,
  bool active,
) {
  return AppIcons.tabGlyph(
    tab.id,
    active: active,
    size: 24,
    color: color,
    cutoutColor: AppTokens.of(context).bgNavbar,
  );
}

Widget _strokedGlyph(AppTab tab, Color color, bool active) {
  final strokeWidth = active ? 2.1 : 1.65;
  return switch (tab) {
    AppTab.home =>
      AppIcons.home(size: 21, color: color, strokeWidth: strokeWidth),
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
      child: Container(
        width: 240,
        decoration: BoxDecoration(
          color: tokens.bgRaised,
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
                        style: TextStyle(fontSize: 12, color: tokens.textMuted),
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
                          size: 16, color: tokens.textMuted, strokeWidth: 1.6),
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
