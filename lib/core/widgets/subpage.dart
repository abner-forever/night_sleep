import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_tokens.dart';
import 'atmosphere.dart';
import 'app_basics.dart';

/// 返回箭头本身的尺寸（原型里 `polyline points="8,1 1,7.5 8,14"`）。
const double _chevronWidth = 9;
const double _chevronHeight = 15;

/// 二级页统一的返回按钮：44×44 点击区，箭头只有图标没有文字。
class SubpageBackButton extends StatelessWidget {
  const SubpageBackButton({
    super.key,
    required this.onTap,
    this.semanticLabel = '返回',
  });

  final VoidCallback onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Pressable(
      semanticLabel: semanticLabel,
      onTap: onTap,
      child: SizedBox(
        width: kSubpageNavigationHeight,
        height: kSubpageNavigationHeight,
        child: Center(
          child: SizedBox(
            key: const ValueKey('subpage-back-icon'),
            width: _chevronWidth,
            height: _chevronHeight,
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
    );
  }
}

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
    this.action,
  });

  final String title;
  final List<Widget> children;
  final double maxContentWidth;

  /// 右上角的动作（可空）。约定是一个 44×44 的点击区，图标 20 左右。
  final Widget? action;

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
            action: action,
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
    required this.action,
  });

  final AppTokens tokens;
  final String title;
  final Widget? action;

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
        // **整行铺满宽度**：返回键的触控区要比标题多探出半个按钮宽，
        // 探出的那截必须留在 Stack 的边界里才收得到点击。
        Positioned(
          left: 0,
          right: 0,
          top: statusBarInset,
          bottom: 0,
          child: _headerRow(context),
        ),
      ],
    );
  }

  Widget _headerRow(BuildContext context) {
    // **返回箭头与正文左边缘齐平**（和隐私协议页那个 AppBar 返回键同一个位置），
    // 所以触控区整体向左探出留白：44×44 的点击范围不变，只是不再从留白处起算。
    // 标题仍按两侧各让出一个按钮宽居中。
    final backLeft = sideInset - (kSubpageNavigationHeight - _chevronWidth) / 2;

    return Stack(
      children: [
        Center(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: sideInset + kSubpageNavigationHeight,
            ),
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
        ),
        Positioned(
          left: backLeft,
          top: 0,
          bottom: 0,
          // 大字号把行高顶高时，按钮跟着标题一起垂直居中。
          child: Align(
            alignment: Alignment.centerLeft,
            // **只有图标，没有文字标签。** 读屏靠 `semanticLabel` 说明它是返回；
            // 删掉文字之后不能让无障碍跟着一起消失。
            child: SubpageBackButton(
              key: const ValueKey('subpage-back'),
              onTap: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/');
                }
              },
            ),
          ),
        ),
        // 右上角动作与返回键对称：44 宽的点击区向留白里探出，图标仍与正文右边缘齐平。
        if (action != null)
          Positioned(
            right: sideInset - 12,
            top: 0,
            bottom: 0,
            child: Align(
              alignment: Alignment.centerRight,
              child: action,
            ),
          ),
      ],
    );
  }

  @override
  bool shouldRebuild(covariant _SubpageHeaderDelegate oldDelegate) =>
      oldDelegate.tokens != tokens ||
      oldDelegate.title != title ||
      oldDelegate.sideInset != sideInset ||
      oldDelegate.statusBarInset != statusBarInset ||
      oldDelegate.rowHeight != rowHeight ||
      oldDelegate.action != action;
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
