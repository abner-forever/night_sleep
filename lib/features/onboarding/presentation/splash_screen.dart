import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// 开屏页（原型 `SplashScreen`）。
///
/// 深蓝渐变 + 月亮 logo + 「夜深 / 听见夜晚，看见睡眠」+ 底部进度条。
/// 播完由调用方移除（[onFinished]），首次安装随后才轮到引导页。
///
/// **时长是 1.6 秒，不是原型的 3.2 秒**（使用方裁定）：原型那 3.2 秒是网页首屏
/// 加载的遮盖，而原生应用在它之前已经有系统启动图，照抄等于每次冷启动白等 3 秒。
/// 压缩办法是把总时长对半砍，**各元素的出场时刻仍然照原型的百分比**——比如 logo
/// 的 `.16s / 3.2s = 5%` 原样用，所以整条时间轴的节奏与原型一致，只是快一倍。
///
/// **这一页的配色不走 `AppTokens`**，理由与会话页的 `night_style.dart` 相同
/// （规格偏差 #32）：它是一屏自成一体、且与主题无关的品牌面，把它塞进 `AppTokens`
/// 会让人以为这些深蓝是应用级令牌。
///
/// **只有一个有限时长的 `AnimationController`，没有 `Timer`、没有 `repeat()`**。
/// 循环动画会让 `pumpAndSettle()` 永不收敛（`sleep_moon_mark.dart` 的 `_sync()`
/// 注释记的就是这个坑），而挂真外壳的测试会在结束时报 pending timer。
/// Version 19 去掉星点、轨道环和图标光晕，保留品牌描线与文案的有限时间轴。
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.onFinished});

  /// 时间轴播完时回调一次。
  final VoidCallback onFinished;

  /// 整条时间轴的长度。
  static const duration = Duration(milliseconds: 1600);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

/// 开屏专用的几个颜色。见类注释：不进 `AppTokens`。
abstract final class _SplashPalette {
  static const night0 = Color(0xFF07102D);
  static const night1 = Color(0xFF101B50);
  static const night2 = Color(0xFF151145);
  static const glowBlue = Color(0x404C81FF); // rgba(76,129,255,.25)
  static const glowCyan = Color(0x1F68DAFF); // rgba(104,218,255,.12)
  static const copySub = Color(0xB8DDEBFF); // rgba(221,235,255,.72)
  static const progressTrack = Color(0x1FFFFFFF); // rgba(255,255,255,.12)
  static const progressFrom = Color(0xFF75D8FF);
  static const progressTo = Color(0xFFA89CFF);
}

/// 原型 `SplashScreen` 里那份 SVG 的逐字转写。
///
/// 与 `assets/branding/app-icon.svg` 的差别只有一处：这里**保留**了圆角矩形的
/// `rx="236"`。那份资产是刻意去角的（iOS 会给应用图标套遮罩，见
/// `tool/generate_app_icons.dart`），而开屏是在界面里画一枚圆角图标，不需要外部遮罩。
///
/// 两条声波**不在这里**：它们要做出「描线」的出场，得由 [_WavePainter] 用
/// `PathMetric` 逐段画出来，静态 SVG 做不到。
const String splashLogoSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="splash-night" x1="148" y1="98" x2="876" y2="926"
      gradientUnits="userSpaceOnUse">
      <stop stop-color="#75D8FF"/>
      <stop offset=".42" stop-color="#397BEA"/>
      <stop offset="1" stop-color="#3F3CC6"/>
    </linearGradient>
    <linearGradient id="splash-moon" x1="351" y1="245" x2="673" y2="776"
      gradientUnits="userSpaceOnUse">
      <stop stop-color="#FFFFFF"/>
      <stop offset="1" stop-color="#D9E7FF"/>
    </linearGradient>
  </defs>
  <rect width="1024" height="1024" rx="236" fill="url(#splash-night)"/>
  <path d="M839 695c-58 63-141 102-233 102-175 0-317-142-317-317 0-103 49-194 125-252-28 52-44 112-44 175 0 204 165 369 369 369 35 0 69-5 100-15Z"
    fill="#171D71" fill-opacity=".2"/>
  <path d="M604 212c-137 0-248 111-248 248 0 137 111 248 248 248 48 0 93-14 132-37-49 72-132 119-226 119-151 0-274-123-274-274s123-274 274-274c34 0 66 6 94 18Z"
    fill="url(#splash-moon)"/>
</svg>
''';

/// 原型 `@keyframes` 的时长（秒）与延迟（秒），原样抄自 `index.css`。
/// 用的时候除以原型总时长 3.2 秒换算成这条 1.6 秒时间轴上的比例。
const double _protoTotal = 3.2;

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: SplashScreen.duration,
  );

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) widget.onFinished();
    });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 原型某个动画在**本时间轴**上的区间（比例，0–1）。延迟与时长都除以原型总时长。
  static Interval _interval(double delay, double duration,
          [Curve curve = Curves.linear]) =>
      Interval((delay / _protoTotal).clamp(0.0, 1.0),
          ((delay + duration) / _protoTotal).clamp(0.0, 1.0),
          curve: curve);

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.of(context).padding;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final v = _controller.value;

        // 与 `OnboardingOverlay` 同一做法：外层是 `Stack`，这一页铺满整屏。
        return Positioned.fill(
          child: Opacity(
            // 原型 `splashScreen` 的 `0% opacity 0; 8%,88% opacity 1; 100% opacity 0`。
            //
            // **只有后半段照抄**：原型开头那 8% 是从透明淡入的，因为它是往一个已经
            // 渲染好的网页上叠一层。原生冷启动时应用外壳还没出来，开头再淡入就变成
            // 「先闪一下浅色界面再变深」，所以这里从第一帧就是不透明的。
            opacity: _screenOpacity(v),
            child: ColoredBox(
              color: _SplashPalette.night0,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const _Backdrop(),
                  Center(
                    child: Transform.translate(
                      // 原型 `.splash-brand { transform: translateY(-2vh) }`。
                      offset:
                          Offset(0, -MediaQuery.sizeOf(context).height * 0.02),
                      child: _Brand(
                        controller: _controller,
                        reduceMotion: reduceMotion,
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      // `bottom: max(42px, env(safe-area-inset-bottom) + 24px)`。
                      padding: EdgeInsets.only(
                        bottom: math.max(42, padding.bottom + 24),
                      ),
                      child: Opacity(
                        opacity: _interval(1.7, 0.4).transform(v),
                        child: _Progress(
                          progress: reduceMotion
                              ? 1
                              : _interval(1.75, 1.2, Curves.easeInOut)
                                  .transform(v),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// 整屏透明度：1 一直保持到 88%，最后 12% 淡出（原型 `splashScreen` 的收尾）。
  static double _screenOpacity(double v) {
    const fadeFrom = 0.88;
    if (v <= fadeFrom) return 1;
    return (1 - (v - fadeFrom) / (1 - fadeFrom)).clamp(0.0, 1.0);
  }
}

/// 渐变底 + 两处径向光晕。
class _Backdrop extends StatelessWidget {
  const _Backdrop();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        // `linear-gradient(155deg, …)`：155° 是「从正上顺时针转 155°」，
        // 换算成 Flutter 的对齐坐标就是下面这一对方向。
        gradient: LinearGradient(
          begin: Alignment(-0.211, -0.453),
          end: Alignment(0.211, 0.453),
          colors: [
            _SplashPalette.night0,
            _SplashPalette.night1,
            _SplashPalette.night2,
          ],
          stops: [0, 0.48, 1],
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.16), // `circle at 50% 42%`
            radius: 0.40,
            colors: [_SplashPalette.glowBlue, Color(0x004C81FF)],
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(-0.7, -0.84), // `circle at 15% 8%`
              radius: 0.34,
              colors: [_SplashPalette.glowCyan, Color(0x0068DAFF)],
            ),
          ),
        ),
      ),
    );
  }
}

/// logo + 文案。
class _Brand extends StatelessWidget {
  const _Brand({required this.controller, required this.reduceMotion});

  final AnimationController controller;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final v = reduceMotion ? 1.0 : controller.value;
    final size = math.min(148.0, MediaQuery.sizeOf(context).width * 0.31);

    // `splashLogoIn`：1s / cubic-bezier(.18,.9,.26,1.16) / 延迟 .16s
    final logoIn = _SplashScreenState._interval(
      0.16,
      1.0,
      const Cubic(0.18, 0.9, 0.26, 1.16),
    ).transform(v);
    // `splashCopyIn`：正文 .7s，延迟 1.38s / 1.55s
    final titleIn =
        _SplashScreenState._interval(1.38, 0.7, Curves.easeOut).transform(v);
    final bodyIn =
        _SplashScreenState._interval(1.55, 0.7, Curves.easeOut).transform(v);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Opacity(
          opacity: logoIn.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, 18 * (1 - logoIn)),
            child: Transform.scale(
              scale: 0.82 + 0.18 * logoIn,
              child: SizedBox(
                width: size,
                height: size,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    SvgPicture.string(
                      splashLogoSvg,
                      excludeFromSemantics: true,
                    ),
                    CustomPaint(
                      painter: _WavePainter(
                        progress: _SplashScreenState._interval(
                          1.05,
                          0.72,
                          const Cubic(0.45, 0, 0.3, 1),
                        ).transform(v),
                        second: _SplashScreenState._interval(
                          1.28,
                          0.72,
                          const Cubic(0.45, 0, 0.3, 1),
                        ).transform(v),
                        scale: size / 1024,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Opacity(
          opacity: titleIn.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, 10 * (1 - titleIn)),
            child: const _SplashTitle(),
          ),
        ),
        const SizedBox(height: 9),
        Opacity(
          opacity: bodyIn.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, 10 * (1 - bodyIn)),
            child: const Text(
              '听见夜晚，看见睡眠',
              style: TextStyle(
                color: _SplashPalette.copySub,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                letterSpacing: 2.16,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 「夜深」两个字：38px、字距 `.2em`、`text-indent` 用左侧内边距补回来，
/// 否则字距会加在最后一个字后面，整块看上去偏左。
class _SplashTitle extends StatelessWidget {
  const _SplashTitle();

  @override
  Widget build(BuildContext context) {
    const letterSpacing = 7.6; // 38px × .2em
    return const Padding(
      padding: EdgeInsets.only(left: letterSpacing),
      child: Text(
        '夜深',
        style: TextStyle(
          color: Colors.white,
          fontSize: 38,
          fontWeight: FontWeight.w700,
          letterSpacing: letterSpacing,
          shadows: [
            Shadow(
                color: Color(0x2E000000), blurRadius: 24, offset: Offset(0, 8)),
          ],
        ),
      ),
    );
  }
}

/// 底部那条 56×2 的进度条。
class _Progress extends StatelessWidget {
  const _Progress({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    const width = 56.0;
    const height = 2.0;

    return SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height / 2),
        child: ColoredBox(
          color: _SplashPalette.progressTrack,
          child: Transform.translate(
            // `splashProgress`：填充块从左侧外滑进来（`translateX(-100%) → 0`）。
            offset: Offset(-width * (1 - progress), 0),
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _SplashPalette.progressFrom,
                    _SplashPalette.progressTo,
                  ],
                ),
              ),
              child: SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
  }
}

/// 两条声波的「描线」出场。
///
/// 路径就是原型那条 `d`，逐段抄成三次贝塞尔；`PathMetric.extractPath` 按进度
/// 截取，得到与 CSS `stroke-dashoffset` 同形的效果。
class _WavePainter extends CustomPainter {
  const _WavePainter({
    required this.progress,
    required this.second,
    required this.scale,
  });

  /// 第一条弧（`splash-wave-one`）的进度，0–1。
  final double progress;

  /// 第二条弧（`splash-wave-two`）的进度，0–1。
  final double second;

  /// 1024 的 viewBox 缩放到实际尺寸的倍率。
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(scale);
    _drawWave(
      canvas,
      // M698 381c66 42 110 116 110 201 0 85-44 159-110 201
      Path()
        ..moveTo(698, 381)
        ..cubicTo(764, 423, 808, 497, 808, 582)
        ..cubicTo(808, 667, 764, 741, 698, 783),
      progress,
      const Color(0xFFDDEBFF),
      42,
      1,
    );
    _drawWave(
      canvas,
      // M757 322c103 64 171 178 171 317 0 139-68 253-171 317
      Path()
        ..moveTo(757, 322)
        ..cubicTo(860, 386, 928, 500, 928, 639)
        ..cubicTo(928, 778, 860, 892, 757, 956),
      second,
      const Color(0xFFB9D6FF),
      30,
      0.78,
    );
    canvas.restore();
  }

  void _drawWave(
    Canvas canvas,
    Path path,
    double amount,
    Color color,
    double strokeWidth,
    double opacity,
  ) {
    if (amount <= 0) return;
    final partial = amount >= 1
        ? path
        : (() {
            final metric = path.computeMetrics().first;
            return metric.extractPath(0, metric.length * amount);
          })();
    canvas.drawPath(
      partial,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: opacity),
    );
  }

  @override
  bool shouldRepaint(_WavePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.second != second ||
      oldDelegate.scale != scale;
}
