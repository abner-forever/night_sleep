import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import 'app_basics.dart';

/// 页面 hero 卡角上的光团。
///
/// 原型里它是绝对定位的一个圆（首页 `190px` 放在 `top:-76 / right:-54`，
/// 回顾页那个 `::after` 是 `108px` 放在 `top:-34 / right:-28`），这里照着搬。
@immutable
class HeroGlow {
  const HeroGlow({
    required this.size,
    required this.colors,
    required this.stops,
    this.top,
    this.right,
    this.left,
    this.bottom,
    this.breathe = false,
  });

  final double size;
  final List<Color> colors;
  final List<double> stops;
  final double? top;
  final double? right;

  /// 贴左下角的那一团用 [left] / [bottom]，与 [top] / [right] 互不干扰
  /// （首页夜色卡右上月晕 + 左下青雾，两团各贴一角）。
  final double? left;
  final double? bottom;

  /// 是否呼吸。原型的 `homeMoonGlow`：5 秒一个来回，中点降到 `opacity .72` 并放大到 `1.08`。
  ///
  /// **这不是偏差 #9 说的那三团 `.liquid-orb`**（`.liquid-orb{opacity:0}`，仍然不做）——
  /// 那是早期层被覆盖掉的元素，这是末层里另一个开着动画的东西。
  final bool breathe;
}

/// 每页有且只有一张的 hero 卡。
///
/// 五张 hero（首页夜色、回顾晨光、统计冷净、统计评分、设置目标）共用这一份绘制路径，
/// 差别全部由调用方传进来：渐变、描边、阴影、角光晕、星点，以及**可选的局部令牌**。
///
/// **局部令牌**是首页夜色卡的关键：那张卡在局部把 `--text-primary` / `--accent` 整套换掉，
/// 于是浅色主题下它也是深的。做法与偏差 #32 对会话页的裁定同源——**收在这一页自己的常量里，
/// `AppTokens` 一个字节不动**。传进来的这套令牌只在这张卡的子树里生效。
class HeroSurface extends StatelessWidget {
  const HeroSurface({
    super.key,
    required this.child,
    required this.gradient,
    required this.shadow,
    this.borderColor,
    this.borderRadius,
    this.padding,
    this.glow,
    this.secondGlow,
    this.stars = false,
    this.scopedTokens,
    this.onTap,
    this.semanticLabel,
    this.expandWidth = true,
  });

  final Widget child;

  /// 底色渐变。首页那张是三层叠出来的，调用方直接给一个 [LinearGradient] 或
  /// 用 [Stack] 自铺——这里只负责把它画进圆角里。
  final Gradient gradient;
  final List<BoxShadow> shadow;
  final Color? borderColor;
  final BorderRadiusGeometry? borderRadius;
  final EdgeInsetsGeometry? padding;
  final HeroGlow? glow;

  /// 第二个角光。
  ///
  /// 首页夜色卡要两团（右上月晕 + 左下青雾），一个 [glow] 装不下。两团走的是
  /// 同一条绘制路径，谁贴哪个角由各自的 [HeroGlow] 说了算，画在内容之下、
  /// 卡自己的圆角之内。不用它的调用方传 `null`，行为与从前一致。
  final HeroGlow? secondGlow;

  /// 四点星点（`.sleep-hero-stars`）。
  final bool stars;

  /// 只在这张卡子树里生效的令牌覆盖。
  final AppTokens? scopedTokens;

  final VoidCallback? onTap;
  final String? semanticLabel;
  final bool expandWidth;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final radius = borderRadius ?? BorderRadius.circular(AppRadii.card);

    Widget surface = DecoratedBox(
      // 阴影在裁剪之外，与 `GlassSurface` / `QuietSurface` 同一条。
      decoration: BoxDecoration(borderRadius: radius, boxShadow: shadow),
      child: ClipRRect(
        borderRadius: radius,
        child: Container(
          decoration: BoxDecoration(gradient: gradient, borderRadius: radius),
          foregroundDecoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: borderColor ?? tokens.glassBorder),
          ),
          child: Stack(
            children: [
              if (stars)
                const Positioned.fill(
                  child: IgnorePointer(
                      child: CustomPaint(painter: _StarPainter())),
                ),
              if (glow != null) _glowLayer(glow!),
              if (secondGlow != null) _glowLayer(secondGlow!),
              Material(
                type: MaterialType.transparency,
                child: Padding(
                  padding: padding ?? EdgeInsets.zero,
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (onTap != null) {
      surface = Pressable(
        onTap: onTap,
        semanticLabel: semanticLabel,
        child: surface,
      );
    } else if (semanticLabel != null) {
      surface =
          Semantics(label: semanticLabel, container: true, child: surface);
    }

    if (expandWidth) {
      surface = SizedBox(width: double.infinity, child: surface);
    }

    final scoped = scopedTokens;
    if (scoped != null) {
      // `AppTokens.of` 读的就是 `Theme` 上挂的那个扩展，所以换掉扩展
      // 就等于在这棵子树里换掉整套令牌。
      surface = Theme(
        data: Theme.of(context).copyWith(extensions: [scoped]),
        child: surface,
      );
    }

    return surface;
  }

  /// 一团角光。`top` / `right` 与 `left` / `bottom` 各贴一角，四者不会同时给，
  /// 所以尺寸永远由 `width` / `height` 定，`Positioned` 的约束不会打架。
  Widget _glowLayer(HeroGlow glow) => Positioned(
        top: glow.top,
        right: glow.right,
        left: glow.left,
        bottom: glow.bottom,
        width: glow.size,
        height: glow.size,
        child: IgnorePointer(
          child:
              glow.breathe ? _BreathingGlow(glow: glow) : _GlowDisc(glow: glow),
        ),
      );
}

/// 静置的光团。
///
/// **`radius` 必须写 0.707，不能用 Flutter 的默认 0.5。** CSS 的
/// `radial-gradient(circle, …)` 按 **farthest-corner** 铺开——对一个正方形来说，
/// 那正好是 `√2 / 2 = 0.7071` 倍的边长；而 Flutter 的 `RadialGradient.radius` 是
/// 「**最短边**的几分之几」，默认 0.5。用默认值会把原型给的百分比止点整体压缩三成，
/// 光团看起来比原型小一圈（`stops: [0, .42, .70]` 那个 42% 会落在错的地方）。
class _GlowDisc extends StatelessWidget {
  const _GlowDisc({required this.glow});

  final HeroGlow glow;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: glow.colors,
            stops: glow.stops,
            radius: _farthestCornerRadius,
          ),
        ),
      );
}

/// 正方形画布上 farthest-corner 与「最短边」之比：`√2 / 2`。
const double _farthestCornerRadius = 0.7071067811865476;

/// 会呼吸的光团。
///
/// 5 秒一个来回、`Curves.easeInOut`，中点 `opacity .72` + `scale 1.08`——
/// 对应原型那条 `homeMoonGlow`。
class _BreathingGlow extends StatefulWidget {
  const _BreathingGlow({required this.glow});

  final HeroGlow glow;

  @override
  State<_BreathingGlow> createState() => _BreathingGlowState();
}

class _BreathingGlowState extends State<_BreathingGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 5),
  );

  // 启动只放在 `didChangeDependencies`：`_start` 要读 `MediaQuery`，而在
  // `initState` 里读 `InheritedWidget` 会撞上框架那条「initState 尚未完成」的断言
  // （`dependOnInheritedWidgetOfExactType` 不允许在 initState 里调用）。
  // 首帧紧跟着就会调一次 `didChangeDependencies`，早启动这一帧没有任何损失。

  void _start() {
    // 系统开了「减弱动态效果」时**不启动**，而不是启动一个零幅度的动画：
    // 后者仍然每帧回调一次，挂在首页上就是白烧一夜的电。
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
    _controller.repeat(reverse: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller.isAnimating) return;
    _start();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_controller.value);
        return Opacity(
          opacity: 1 - 0.28 * t,
          child: Transform.scale(scale: 1 + 0.08 * t, child: child),
        );
      },
      child: _GlowDisc(glow: widget.glow),
    );
  }
}

/// 四点星点（`.sleep-hero-stars`）。
///
/// 原型把它们写成四个 `radial-gradient` 圆点铺在整张卡上，整体 `opacity .48`。
/// 四个点位与各自的白色浓度逐条搬过来，透明度已经乘过那个 `.48`。
class _StarPainter extends CustomPainter {
  const _StarPainter();

  static const _dots = <(double, double, double)>[
    (0.12, 0.18, 0.80),
    (0.72, 0.16, 0.65),
    (0.90, 0.48, 0.70),
    (0.56, 0.78, 0.52),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    // 原型里星点是 1px 半径的实点，稍带一点柔边（渐变止于 1.5px）。
    final radius = size.width / 390 * 1.2;
    for (final (dx, dy, alpha) in _dots) {
      final center = Offset(size.width * dx, size.height * dy);
      canvas.drawCircle(
        center,
        radius * 1.5,
        Paint()
          ..shader = RadialGradient(
            colors: [
              Colors.white.withValues(alpha: alpha * 0.48),
              Colors.white.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: center, radius: radius * 1.5)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _StarPainter oldDelegate) => false;
}
