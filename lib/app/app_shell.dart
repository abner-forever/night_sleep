import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/platform/haptics.dart';
import '../core/theme/app_tokens.dart';
import '../core/widgets/app_icons.dart';
import '../core/widgets/app_sheet.dart' show openSheetCount;
import '../core/widgets/top_fade.dart';

/// The four primary destinations. Order matches the prototype's `NAV`.
enum AppTab {
  home('home', '首页'),
  log('log', '记录'),
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

/// The bar's own height: `min-height: 56px` inside `padding: 4px 6px`, plus its
/// 0.5px top and 1px bottom border.
const double _tabBarHeight = 56 + 8 + 1.5;

/// How much vertical room the floating bar takes out of the page, measured from
/// the bottom of the viewport: the bar itself, its float offset
/// (`max(12px, safe-area-inset-bottom)`), and a little breathing room so a card
/// never ends flush against the glass.
double tabBarReserve(BuildContext context) {
  final safeBottom = MediaQuery.paddingOf(context).bottom;
  return _tabBarHeight + (safeBottom > 12 ? safeBottom : 12) + 16;
}

/// How much room the floating tab bar needs at the bottom of the page.
///
/// Applied by each page's scroll view, not by the shell. Reserved *outside* the
/// scroll view the bar's band becomes an opaque strip the content is cut off
/// above; reserved inside, the viewport still reaches the bottom of the screen —
/// content scrolls under the translucent bar the way the design intends — and
/// the last item can still be scrolled clear of it.
/// This is the whole reserve, not just the bar's own height: the bar floats
/// `max(12px, safe-area-inset-bottom)` above the bottom edge, and the inset has
/// to clear that too or the last card comes to rest behind the glass.
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
      // `bottom/left/right: max(12px, env(safe-area-inset-*))`.
      padding: EdgeInsets.only(
        left: padding.left > 12 ? padding.left : 12,
        right: padding.right > 12 ? padding.right : 12,
        bottom: padding.bottom > 12 ? padding.bottom : 12,
      ),
      // The shadow sits outside the clip: declared inside `ClipRRect` it is
      // simply discarded, which left the bar looking pasted on.
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadii.tabBar),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1F2D51).withValues(alpha: 0.06),
              blurRadius: 30,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.tabBar),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: tokens.bgNavbar,
                borderRadius: BorderRadius.circular(AppRadii.tabBar),
                border: Border.all(color: tokens.glassBorder, width: 0.5),
              ),
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
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: tokens.accent.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(28),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF1F3970)
                                    .withValues(alpha: 0.08),
                                blurRadius: 3,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
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
          ),
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem(
      {required this.tab, required this.active, required this.onTap});

  final AppTab tab;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
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
        onTap: () {
          AppHaptics.select();
          onTap();
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 25,
                height: 28,
                child: Center(child: glyph),
              ),
              const SizedBox(height: 2),
              Text(
                tab.label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  letterSpacing: -0.2,
                  color: color,
                ),
              ),
            ],
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
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: tokens.accentSoft,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      alignment: Alignment.center,
                      child: AppIcons.moon(
                          size: 20, color: tokens.accent, strokeWidth: 1.6),
                    ),
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
            Text(
              tab.label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
