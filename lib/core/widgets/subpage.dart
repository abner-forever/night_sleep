import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_tokens.dart';
import 'atmosphere.dart';
import 'liquid_glass.dart';

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
/// 顶部那行（返回胶囊 + 标题）**上滑吸顶**：它随内容一起往上走一小段，随后钉在
/// 顶部，内容从它下面滚过去；吸顶时补一层玻璃底板，字不会和滚上来的内容叠在一起。
class Subpage extends StatelessWidget {
  const Subpage({
    super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

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
        // 左右与底部照旧交给 SafeArea。
        body: SafeArea(
          top: false,
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
    final horizontal = isWide ? 52.0 : 16.0;
    final topPadding = isWide ? 48.0 : 24.0;

    // 内容仍是「最宽 720、居中」，只是把限宽从 `ConstrainedBox` 换成了左右留白，
    // 好让吸顶条的玻璃底板可以铺满整个宽度（含状态栏背后），不被 720 截断。
    final sideInset = (width - math.min(720.0, width)) / 2 + horizontal;

    // 吸顶头的边界是固定值，行高必须跟着系统字号走——写死 36 的话，用户把字号
    // 调大之后标题会把这一行顶出边界。返回键是定长图标，不参与换算。
    final textScaler = MediaQuery.textScalerOf(context);
    final rowHeight = math.max(36.0, textScaler.scale(22) * 1.3);

    return CustomScrollView(
      slivers: [
        SliverPersistentHeader(
          pinned: true,
          delegate: _SubpageHeaderDelegate(
            tokens: tokens,
            title: title,
            sideInset: sideInset,
            statusBarInset: MediaQuery.paddingOf(context).top,
            topPadding: topPadding,
            rowHeight: rowHeight,
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(sideInset, 0, sideInset, 40),
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
/// [maxExtent] 是「还没滚」的高度：状态栏 + 上留白 + 标题行 + 下留白，和第 0 屏
/// 的旧排法一个数；[minExtent] 是吸顶后的高度：状态栏 + 标题行 + 上下各 12px。
/// 滚动时这段差值被吃掉，标题行因此先随页面上移、再钉住。
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
    required this.topPadding,
    required this.rowHeight,
  });

  final AppTokens tokens;
  final String title;

  /// 标题行离屏幕左右边缘的距离（已含内容限宽的居中留白）。
  final double sideInset;

  /// 状态栏高度；系统未预留状态栏空间时为 0。
  final double statusBarInset;

  final double topPadding;

  /// 返回胶囊 / 标题行的高度（已按系统字号换算过）。
  final double rowHeight;

  /// 未滚动时标题行下方的间距，与改动前一致。
  static const double _bottomGap = 20;

  /// 吸顶后胶囊上下的呼吸空间。
  ///
  /// 吸顶条要像一条导航栏，而不是把胶囊挤在两条边上；加上状态栏那一截
  /// （安卓约 24–30px），整条在手机上约 84–90px 高。
  static const double _pinnedInset = 12;

  @override
  double get maxExtent => statusBarInset + topPadding + rowHeight + _bottomGap;

  @override
  double get minExtent => statusBarInset + _pinnedInset * 2 + rowHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    // 0 = 还没滚，1 = 已经钉住。底板与下留白都跟着它走。
    final collapse = (shrinkOffset / (maxExtent - minExtent)).clamp(0.0, 1.0);
    final bottomInset = _bottomGap + (_pinnedInset - _bottomGap) * collapse;

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
          bottom: bottomInset,
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
        LiquidGlass(
          key: const ValueKey('subpage-back'),
          borderRadius: BorderRadius.circular(AppRadii.pill),
          blur: 18,
          saturation: 1.4,
          tint: tokens.material,
          expandWidth: false,
          semanticLabel: '返回',
          shadow: [
            BoxShadow(
              color: const Color(0xFF1C2C52).withValues(alpha: 0.10),
              blurRadius: 7,
              offset: const Offset(0, 2),
            ),
          ],
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
            width: 36,
            height: 36,
            child: Center(
              child: SizedBox(
                width: 9,
                height: 15,
                child: CustomPaint(painter: _ChevronPainter(tokens.accent)),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.6,
              color: tokens.textPrimary,
            ),
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
      oldDelegate.topPadding != topPadding ||
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
