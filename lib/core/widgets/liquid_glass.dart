import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../platform/haptics.dart';
import '../theme/app_tokens.dart';

/// 液态玻璃材质，用在**导航与控件层**（标签条、分段控件、返回胶囊、弹层、
/// toast、会话页的「收起」）。
///
/// 真正的液态玻璃（iOS 26 的 `glassEffect`、Android 13+ 的 AGSL
/// `RuntimeShader`）会实时折射背后的画面：边缘把背景压弯、色散在弧线上分开。
/// Flutter 的 [BackdropFilter] 拿不到逐像素的位移能力，所以在跨平台上用四层
/// **近似**，这也是市面上没有原生 AGSL 时的通行做法：
///
/// 1. 背景模糊 + 提高饱和度（vibrancy）——`ImageFilter.compose` 把
///    [ui.ColorFilter.matrix] 套在模糊外面，一次采样里完成；
/// 2. 外缘一条细线：浅色模式走深灰、深色模式走白，保证浅底上也能看见轮廓；
/// 3. 内缘一圈渐变高光 + 一条宽而模糊的柔光，模拟光在玻璃厚度里散开；
/// 4. 顶部镜面高光与斜向扫光；可点击时再补一层跟着触点亮起的高光与按压缩放。
///
/// **不要把它用在内容卡上。** 玻璃叠玻璃既读不清、又每帧多一次背景采样；
/// 内容面继续用 [GlassSurface] / [QuietSurface]。
class LiquidGlass extends StatefulWidget {
  const LiquidGlass({
    super.key,
    required this.child,
    this.borderRadius,
    this.padding,
    this.margin,
    this.blur = 24,
    this.saturation = 1.5,
    this.tint,
    this.shadow,
    this.clipBehavior = Clip.antiAlias,
    this.onTap,
    this.semanticLabel,
    this.expandWidth = true,
    this.rimOpacity = 1,
    this.bottomEdge = true,
  });

  final Widget child;
  final BorderRadiusGeometry? borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  /// 背景模糊半径。标签条 / 弹层给 28–38，小控件 16–20 就够。
  final double blur;

  /// 背景饱和度倍数。低于 1.2 基本看不出「玻璃下面是活的」。
  final double saturation;

  /// 覆盖材质底色；默认 [AppTokens.material]。
  final Color? tint;
  final List<BoxShadow>? shadow;
  final Clip clipBehavior;

  /// 非空时整块玻璃可点，并带按压缩放 / 触点高光。
  final VoidCallback? onTap;
  final String? semanticLabel;

  /// 撑满可用宽度。列表里的卡片是块级元素，默认撑满；胶囊、返回键这类
  /// 贴着内容的控件要显式关掉。
  final bool expandWidth;

  /// 镜面边缘的强度（0–1）。小尺寸控件调低，否则一圈白边会显得太粗。
  final double rimOpacity;

  /// 底边是否也画内缘高光。贴屏幕底的弹层关掉，免得最下面多一条亮线。
  final bool bottomEdge;

  @override
  State<LiquidGlass> createState() => _LiquidGlassState();
}

class _LiquidGlassState extends State<LiquidGlass> {
  /// 取玻璃自身的尺寸，把触点换算成高光中心；不依赖外层的 margin / 撑宽。
  final GlobalKey _surfaceKey = GlobalKey();

  bool _pressed = false;
  Alignment _pressAlign = Alignment.center;

  void _onTapDown(TapDownDetails details) {
    final box = _surfaceKey.currentContext?.findRenderObject() as RenderBox?;
    var align = Alignment.center;
    if (box != null && box.hasSize && !box.size.isEmpty) {
      final local = box.globalToLocal(details.globalPosition);
      align = Alignment(
        (local.dx / box.size.width * 2 - 1).clamp(-1.0, 1.0),
        (local.dy / box.size.height * 2 - 1).clamp(-1.0, 1.0),
      );
    }
    setState(() {
      _pressed = true;
      _pressAlign = align;
    });
  }

  void _release() {
    if (_pressed) setState(() => _pressed = false);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final radius = (widget.borderRadius ?? BorderRadius.circular(AppRadii.card))
        .resolve(Directionality.of(context));
    final interactive = widget.onTap != null;

    final ui.ImageFilter? backdrop;
    if (widget.blur <= 0) {
      backdrop = null;
    } else {
      final blurFilter = ui.ImageFilter.blur(
        sigmaX: widget.blur,
        sigmaY: widget.blur,
      );
      backdrop = widget.saturation == 1
          ? blurFilter
          // `compose(outer, inner)` = outer(inner(source))：先模糊，再提饱和度。
          : ui.ImageFilter.compose(
              outer: ui.ColorFilter.matrix(
                _saturationMatrix(widget.saturation),
              ),
              inner: blurFilter,
            );
    }

    Widget tinted = ColoredBox(
      color: widget.tint ?? tokens.material,
      child: Stack(
        key: _surfaceKey,
        // 让「最小尺寸」多出来的空间落到内容两侧：收起胶囊靠这条在 56×34 里居中。
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _LiquidGlassPainter(
                  tokens: tokens,
                  radius: radius,
                  rimOpacity: widget.rimOpacity,
                  bottomEdge: widget.bottomEdge,
                ),
              ),
            ),
          ),
          if (interactive)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _pressed ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: _pressAlign,
                        radius: 0.62,
                        colors: [
                          _fade(tokens.liquidSpecular, 0.35),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          // 透明 Material 让任何玻璃面都能直接托住输入框（备注、API Key）。
          Material(
            type: MaterialType.transparency,
            child: Padding(
              padding: widget.padding ?? EdgeInsets.zero,
              child: widget.child,
            ),
          ),
        ],
      ),
    );

    if (backdrop != null) {
      tinted = BackdropFilter(filter: backdrop, child: tinted);
    }

    // 阴影必须在裁剪之外：写在会被自己 `ClipRRect` 裁掉的盒子上会被静默丢弃。
    Widget surface = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: widget.shadow ?? tokens.surfaceShadow,
      ),
      child: ClipRRect(
        borderRadius: radius,
        clipBehavior: widget.clipBehavior,
        child: tinted,
      ),
    );

    if (interactive) {
      surface = Semantics(
        label: widget.semanticLabel,
        button: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: _onTapDown,
          onTapUp: (_) => _release(),
          onTapCancel: _release,
          onTap: () {
            AppHaptics.tap();
            widget.onTap!();
          },
          child: AnimatedScale(
            scale: _pressed ? 0.976 : 1,
            duration: const Duration(milliseconds: 180),
            curve: AppMotion.standardCurve,
            child: surface,
          ),
        ),
      );
    } else if (widget.semanticLabel != null) {
      surface = Semantics(
        label: widget.semanticLabel,
        container: true,
        child: surface,
      );
    }

    if (widget.expandWidth) {
      // 与 `GlassSurface` 同一个理由：一列里的玻璃面是个块级元素。
      surface = SizedBox(width: double.infinity, child: surface);
    }

    return widget.margin == null
        ? surface
        : Padding(padding: widget.margin!, child: surface);
  }
}

/// 饱和度矩阵，公式与 CSS `filter: saturate(s)` 同构。
List<double> _saturationMatrix(double saturation) {
  final s = saturation;
  const lumR = 0.2126;
  const lumG = 0.7152;
  const lumB = 0.0722;
  final ir = (1 - s) * lumR;
  final ig = (1 - s) * lumG;
  final ib = (1 - s) * lumB;
  return <double>[
    ir + s,
    ig,
    ib,
    0,
    0,
    ir,
    ig + s,
    ib,
    0,
    0,
    ir,
    ig,
    ib + s,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];
}

Color _fade(Color color, double factor) =>
    color.withValues(alpha: (color.a * factor).clamp(0.0, 1.0));

/// 一次画完液态玻璃的四层装饰：顶部镜面、斜向扫光、内缘柔光、内外描边。
class _LiquidGlassPainter extends CustomPainter {
  const _LiquidGlassPainter({
    required this.tokens,
    required this.radius,
    required this.rimOpacity,
    required this.bottomEdge,
  });

  final AppTokens tokens;
  final BorderRadius radius;
  final double rimOpacity;
  final bool bottomEdge;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final rect = Offset.zero & size;
    final rrect = radius.toRRect(rect);

    // Textured edges are clipped to the glass itself.
    canvas.save();
    canvas.clipRRect(rrect);

    // 顶部镜面：一道从上往下很快淡出的白光，占玻璃高度的 55%。
    final sheen = _fade(tokens.liquidSpecular, rimOpacity);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height * 0.55),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(0, size.height * 0.55),
          [_fade(sheen, 0.22), _fade(sheen, 0)],
        ),
    );

    // 115° 斜向扫光：左上亮、右下也留一点，模拟整块玻璃的弧面。
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(size.width, size.height),
          [
            _fade(tokens.liquidSpecular, 0.13 * rimOpacity),
            _fade(tokens.liquidFringeCool, 0.30 * rimOpacity),
            Colors.transparent,
            _fade(tokens.liquidFringeWarm, 0.26 * rimOpacity),
          ],
          const [0.0, 0.28, 0.70, 1.0],
        ),
    );
    canvas.restore();

    // 内缘柔光：宽描边 + 模糊，向外淡进玻璃、向内淡进底色。
    final glow = _fade(tokens.liquidGlow, rimOpacity);
    canvas.drawPath(
      Path()..addRRect(rrect.deflate(5)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5)
        ..shader = ui.Gradient.linear(
          const Offset(0, 0),
          Offset(0, size.height),
          [
            glow,
            _fade(glow, 0.18),
            glow,
            _fade(glow, 0.35),
          ],
          const [0.0, 0.40, 0.76, 1.0],
        ),
    );

    // 贴屏幕底的面板不需要底边亮线。
    canvas.save();
    if (!bottomEdge) {
      canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height - 1));
    }

    // 外缘细线：浅色底上给轮廓，深色底上给一层很淡的白。
    canvas.drawPath(
      Path()..addRRect(rrect.deflate(0.5)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = _fade(tokens.liquidEdge, rimOpacity),
    );

    // 内缘亮边：左上最亮，沿对角走到右下收暗，中段带一点色散。
    canvas.drawPath(
      Path()..addRRect(rrect.deflate(1.25)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(size.width, size.height),
          [
            _fade(tokens.liquidSpecular, rimOpacity),
            _fade(tokens.liquidFringeCool, 0.55 * rimOpacity),
            _fade(tokens.liquidRim, rimOpacity),
            _fade(tokens.liquidFringeWarm, 0.45 * rimOpacity),
            _fade(tokens.liquidRimSoft, rimOpacity),
          ],
          const [0.0, 0.30, 0.56, 0.80, 1.0],
        ),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LiquidGlassPainter oldDelegate) =>
      oldDelegate.tokens != tokens ||
      oldDelegate.radius != radius ||
      oldDelegate.rimOpacity != rimOpacity ||
      oldDelegate.bottomEdge != bottomEdge;
}
