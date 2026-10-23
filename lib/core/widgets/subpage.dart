import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_tokens.dart';
import 'atmosphere.dart';
import 'app_basics.dart';

/// Shared chrome for a page pushed **over** the tab shell: a back pill, the page
/// title, and a scrolling content column.
///
/// A pushed route inherits nothing. It has no [Scaffold], so it has no
/// background and no [Material] ancestor; it has no shell padding; and it has no
/// atmosphere gradient. All four have to come from here:
///
///  * no background → the page paints on bare black;
///  * no `Material` ancestor → every [Text] falls back to Flutter's error style,
///    which renders as a **yellow double underline**;
///  * no padding → content jams against the screen edges and the status bar.
///
/// Every page reached by a push goes through here so that stays in one place.
///
/// 顶部导航固定在系统安全区下方，滚动时补一层玻璃底板。
class Subpage extends StatelessWidget {
  const Subpage({
    super.key,
    required this.title,
    required this.children,
    this.maxContentWidth = 720,
  });

  final String title;
  final List<Widget> children;
  final double maxContentWidth;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    return Atmosphere(
      child: Scaffold(
        // Transparent so the atmosphere shows through; the Scaffold is here for
        // the Material ancestor and the keyboard inset handling, not its colour.
        backgroundColor: Colors.transparent,
        // **顶部不躲开状态栏**：吸顶条要铺到状态栏背后，滚起来之后和状态栏
        // 连成一块；状态栏的高度改由吸顶头自己算进去（见 `statusBarInset`）。
        body: SafeArea(
          top: false,
          bottom: false,
          child: LayoutBuilder(
            builder: (context, constraints) => _content(
              context,
              tokens,
              constraints.maxWidth,
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, AppTokens tokens, double width) {
    final isWide = width >= kWideLayoutBreakpoint;
    final horizontal = isWide ? 36.0 : 20.0;

    // 内容仍是「最宽 720、居中」，只是把限宽从 `ConstrainedBox` 换成了左右留白，
    // 好让吸顶条的玻璃底板可以铺满整个宽度（含状态栏背后），不被 720 截断。
    final sideInset =
        (width - math.min(maxContentWidth, width)) / 2 + horizontal;

    final textScaler = MediaQuery.textScalerOf(context);
    final rowHeight =
        math.max(kSubpageNavigationHeight, textScaler.scale(17) * 1.4);

    return CustomScrollView(
      slivers: [
        SliverPersistentHeader(
          pinned: true,
          delegate: _SubpageHeaderDelegate(
            tokens: tokens,
            title: title,
            sideInset: sideInset,
            statusBarInset: MediaQuery.paddingOf(context).top,
            rowHeight: rowHeight,
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(sideInset, 20, sideInset,
              MediaQuery.paddingOf(context).bottom + 24),
          sliver: SliverList(
            delegate: SliverChildListDelegate(children),
          ),
        ),
      ],
    );
  }
}

/// 吸顶的顶部导航。
///
/// 高度为顶部系统安全区加导航行，默认导航行高 44，大字号时随文字增高。
///
/// **状态栏那一截算在头部里**：页面铺到屏幕物理边缘（Android 也是 edge-to-edge），
/// 底板因此能画到状态栏背后。少了这一截，吸顶条和状态栏之间会留一条底色不同的
/// 横带——深色模式下一眼就能看见。
class _SubpageHeaderDelegate extends SliverPersistentHeaderDelegate {
  _SubpageHeaderDelegate({
    required this.tokens,
    required this.title,
    required this.sideInset,
    required this.statusBarInset,
    required this.rowHeight,
  });

  final AppTokens tokens;
  final String title;

  /// 标题行离屏幕左右边缘的距离（已含内容限宽的居中留白）。
  final double sideInset;

  /// 状态栏高度；系统未预留状态栏空间时为 0。
  final double statusBarInset;

  /// 返回胶囊 / 标题行的高度（已按系统字号换算过）。
  final double rowHeight;

  @override
  double get maxExtent => statusBarInset + rowHeight;

  @override
  double get minExtent => maxExtent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final collapse = (shrinkOffset / rowHeight).clamp(0.0, 1.0);

    return Stack(
      fit: StackFit.expand,
      children: [
        // **底板只在被推上去之后出现**：停在第 0 屏时页面保持原来的透明观感，
        // 一滚起来再淡入，玻璃下面压的是刚滚过去的内容。
        //
        // 透明度为 0 时 `Opacity` 根本不会画这棵子树，没滚动就没有模糊的开销。
        Opacity(
          key: const ValueKey('subpage-header-band'),
          opacity: collapse,
          child: ClipRect(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      tokens.bgBase.withValues(alpha: 0.94),
                      tokens.bgBase.withValues(alpha: 0.86),
                      tokens.bgBase.withValues(alpha: 0),
                    ],
                    stops: const [0.0, 0.68, 1.0],
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: sideInset,
          right: sideInset,
          top: statusBarInset,
          bottom: 0,
          child: _headerRow(context),
        ),
      ],
    );
  }

  Widget _headerRow(BuildContext context) {
    return Row(
      children: [
        // **只有图标，没有文字标签。** 读屏靠 `semanticLabel` 说明它是返回；
        // 删掉文字之后不能让无障碍跟着一起消失。
        Pressable(
          key: const ValueKey('subpage-back'),
          semanticLabel: '返回',
          onTap: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          },
          // The chevron is drawn inline as the prototype does, so it
          // keeps its 2.2 stroke and tight 9×15 proportion.
          child: SizedBox(
            width: kSubpageNavigationHeight,
            height: kSubpageNavigationHeight,
            child: Center(
              child: SizedBox(
                width: 9,
                height: 15,
                child: CustomPaint(
                  painter: _ChevronPainter(
                    Theme.of(context).brightness == Brightness.dark
                        ? tokens.textPrimary
                        : Colors.black,
                  ),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              height: 1.4,
              letterSpacing: -0.3,
              color: tokens.textPrimary,
            ),
          ),
        ),
        const SizedBox(width: kSubpageNavigationHeight),
      ],
    );
  }

  @override
  bool shouldRebuild(covariant _SubpageHeaderDelegate oldDelegate) =>
      oldDelegate.tokens != tokens ||
      oldDelegate.title != title ||
      oldDelegate.sideInset != sideInset ||
      oldDelegate.statusBarInset != statusBarInset ||
      oldDelegate.rowHeight != rowHeight;
}

class _ChevronPainter extends CustomPainter {
  const _ChevronPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // `polyline points="8,1 1,7.5 8,14"` in a 9×15 box.
    final path = Path()
      ..moveTo(8, 1)
      ..lineTo(1, 7.5)
      ..lineTo(8, 14);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_ChevronPainter oldDelegate) => oldDelegate.color != color;
}
