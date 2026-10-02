import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../night_scene.dart';
import '../night_style.dart';

/// 一个循环的秒数。取 60 是因为八套场景的周期（2.8–34 秒）都能在里面安放，
/// 「循环接缝」只体现在某一颗星的位置上，整屏暗色渐变里看不出来。
///
/// 用 `int` 是因为它同时要喂给 `Duration(seconds:)` 这个 const 构造；乘法里
/// `double * int` 会自动提升成 `double`，数值语义不变。
const int _kLoopSeconds = 60;

/// 会话页的全屏夜景背景。
///
/// **一个 60 秒循环的 `AnimationController` 驱动全部八套场景**，元素全画在
/// `CustomPaint` 里。不给 34 颗星、18 条雨丝、14 只萤火各建一个 widget，也不给每套
/// 场景各建一个 controller——这是整屏背景，用 widget 树做会同时压住布局与光栅化。
///
/// 系统开了「减弱动态效果」就停表，只留静态层（底色 + 网点 + 星点），对应原型的
/// `@media (prefers-reduced-motion: reduce)`。这是无障碍要求，不是优化。
class NightBackdrop extends StatefulWidget {
  const NightBackdrop({super.key, required this.scene});

  final NightScene scene;

  @override
  State<NightBackdrop> createState() => _NightBackdropState();
}

class _NightBackdropState extends State<NightBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: _kLoopSeconds),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 起点只在 `didChangeDependencies` 里定：`initState` 里 `dependOnInheritedWidget`
    // 是不允许的，而 `MediaQuery` 得靠它。
    if (NightStyle.reduceMotion(context)) {
      _clock.stop();
      _clock.value = 0;
    } else if (!_clock.isAnimating) {
      _clock.repeat();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 场景切换的 900ms 底色过渡，对应原型
          // `.sleep-mode { transition: background 900ms ease }`。
          AnimatedContainer(
            duration: const Duration(milliseconds: 900),
            curve: Curves.ease,
            decoration: BoxDecoration(gradient: widget.scene.background),
          ),
          AnimatedBuilder(
            animation: _clock,
            builder: (context, child) => CustomPaint(
              painter: _NightScenePainter(
                scene: widget.scene,
                phase: _clock.value,
                reduceMotion: NightStyle.reduceMotion(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NightScenePainter extends CustomPainter {
  _NightScenePainter({
    required this.scene,
    required this.phase,
    required this.reduceMotion,
  });

  final NightScene scene;

  /// 0–1 的循环相位；乘上 [_kLoopSeconds] 就是「本圈已过的秒数」。
  final double phase;
  final bool reduceMotion;

  /// 某个元素在它自己那一轮里的进度（0–1）。
  ///
  /// `delay` 就是 CSS 的 `animation-delay`，**负数表示相位提前**（原型的
  /// `animation-delay: -4s`），所以是减。
  double _progress(double seconds, {double delay = 0}) {
    if (reduceMotion) return 0;
    final elapsed = phase * _kLoopSeconds - delay;
    final v = (elapsed / seconds) % 1.0;
    return v < 0 ? v + 1 : v;
  }

  /// CSS 的 `animation-direction: alternate`：往返一趟。
  double _pingPong(double seconds, {double delay = 0}) {
    final v = _progress(seconds, delay: delay);
    return 1 - (2 * v - 1).abs();
  }

  /// CSS 的 `ease-in-out` 在三角波上的近似。
  double _easeInOut(double t) => Curves.easeInOut.transform(t.clamp(0.0, 1.0));

  @override
  void paint(Canvas canvas, Size size) {
    _paintTexture(canvas, size);
    _paintGlows(canvas, size);
    _paintStars(canvas, size);
    switch (scene) {
      case NightScene.meteor:
        _paintMeteors(canvas, size);
      case NightScene.aurora:
        _paintAurora(canvas, size);
      case NightScene.ocean:
        _paintOceanWaves(canvas, size);
      case NightScene.cloud:
        _paintClouds(canvas, size);
      case NightScene.firefly:
        _paintFireflies(canvas, size);
      case NightScene.galaxy:
        _paintGalaxy(canvas, size);
      case NightScene.rain:
        _paintRain(canvas, size);
      case NightScene.moon:
        // 月海只有一圈更大的光晕，已经在 `_paintGlows` 里按场景处理过了。
        break;
    }
  }

  /// `.sleep-mode::before`：67px 一格的网点，`radial-gradient(… rgba(255,255,255,.7))
  /// 0 1px` 叠 `opacity: .13`。乘出来是 alpha ≈ .091。
  void _paintTexture(Canvas canvas, Size size) {
    const step = 67.0;
    final paint = Paint()..color = const Color(0x17FFFFFF);
    for (var y = 0.0; y < size.height + step; y += step) {
      for (var x = 0.0; x < size.width + step; x += step) {
        canvas.drawCircle(Offset(x, y), 1, paint);
      }
    }
  }

  /// `.sleep-scene-glow-one` / `-two`：两团大范围径向光晕。
  ///
  /// 原型给它们挂了 `filter: blur(4px)`——对这种尺寸的软径向渐变来说不足 1% 的
  /// 视觉差别，这里不额外套一层模糊去凑那个数字。
  ///
  /// **一处如实的近似**：这几团的衰减范围不是与原型逐像素对齐的。CSS 的
  /// `radial-gradient(circle, …)` 默认按 **farthest-corner** 算半径，而 Flutter 的
  /// `RadialGradient.radius` 是相对**短边**的比例。盒子越扁，两者差得越多；这里沿用
  /// `stops` 的百分比落在色带内的相对位置，所以色带形状对得上、外扩范围是近似的。
  void _paintGlows(Canvas canvas, Size size) {
    final w = size.width;
    final moon = scene == NightScene.moon;

    // glow-one：默认 70vw × 42vw / top -12vw right -10vw；
    // `.sleep-scene-moon .sleep-scene-glow-one`：48vw 见方，top 8%（相对容器高）、
    // right 7%（相对容器宽）——即盒的左上角在 45% 宽、8% 高处，也就是一轮月华。
    final oneRect = moon
        ? Rect.fromLTWH(w * .45, size.height * .08, w * .48, w * .48)
        : Rect.fromLTWH(w + w * .10 - w * .70, -w * .12, w * .70, w * .42);
    canvas.drawRect(
      oneRect,
      Paint()
        ..shader = RadialGradient(
          colors: moon
              ? const [
                  Color(0x45E2E8FF),
                  Color(0x2997A3DC),
                  Color(0x00000000),
                ]
              : const [Color(0x426D7EE0), Color(0x00000000)],
          stops: moon ? const [0, .14, .57] : const [0, .68],
        ).createShader(oneRect),
    );

    // glow-two：62vw × 48vw / bottom -20vw left -18vw。
    final twoRect = Rect.fromLTWH(
        -w * .18, size.height + w * .20 - w * .48, w * .62, w * .48);
    canvas.drawRect(
      twoRect,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x291F7695), Color(0x00000000)],
          stops: [0, .70],
        ).createShader(twoRect),
    );
  }

  /// `.sleep-stars i` 34 颗 + `sleepTwinkle`（中点 opacity .25、scale .65，4.5 秒）。
  ///
  /// 位置用的是原型 `SLEEP_STARS` 那两条取模公式，逐颗对得上。
  void _paintStars(Canvas canvas, Size size) {
    for (var i = 0; i < 34; i++) {
      final left = ((i * 37 + 11) % 97) / 100;
      final top = ((i * 53 + 7) % 82) / 100;
      final radius = i % 6 == 0 ? 1.0 : 0.5;
      final delay = -((i % 9) * 0.43);

      final twinkle = reduceMotion
          ? 0.0
          : _easeInOut(1 - (2 * _progress(4.5, delay: delay) - 1).abs());
      final opacity = 1 - 0.75 * twinkle;
      final scale = 1 - 0.35 * twinkle;

      final centre = Offset(left * size.width, top * size.height);
      // `box-shadow: 0 0 5px rgba(196,209,255,.6)`——用一层模糊圆代替。
      canvas.drawCircle(
        centre,
        radius * scale * 2.2,
        Paint()
          ..color = const Color(0x99C4D1FF).withValues(alpha: 0.6 * opacity)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
      );
      canvas.drawCircle(
        centre,
        radius * scale,
        Paint()
          ..color = const Color(0xD1EFF3FF).withValues(alpha: 0.82 * opacity),
      );
    }
  }

  /// `.sleep-meteors i` 三条 + `sleepMeteor`：0–82% 不可见，84% 亮点，91% 起淡出，
  /// 整段沿 `translate(-58vw, 38vw) rotate(-32deg)` 划过去。
  void _paintMeteors(Canvas canvas, Size size) {
    const specs = [
      (top: .08, left: .78, width: 110.0, duration: 8.5, delay: 0.0),
      (top: .27, left: .92, width: 76.0, duration: 10.5, delay: 3.8),
      (top: .15, left: .55, width: 58.0, duration: 12.0, delay: 7.1),
    ];

    for (final spec in specs) {
      final p = _progress(spec.duration, delay: -spec.delay);
      if (p < .82 || p > .91) continue;

      // 82%→84% 亮起，84%→91% 淡出。
      final opacity = p < .84 ? (p - .82) / .02 : (.91 - p) / .07;
      final travel = ((p - .82) / .18).clamp(0.0, 1.0);
      final origin = Offset(spec.left * size.width, spec.top * size.height);
      final offset =
          Offset(-.58 * size.width * travel, .38 * size.width * travel);

      canvas.save();
      canvas.translate(origin.dx + offset.dx, origin.dy + offset.dy);
      canvas.rotate(-32 * math.pi / 180);
      final rect = Rect.fromLTWH(0, -0.5, spec.width, 1);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            colors: [
              const Color(0x00000000),
              const Color(0xD9E6EDFF).withValues(alpha: .85 * opacity),
            ],
          ).createShader(rect),
      );
      canvas.restore();
    }
  }

  /// `.sleep-aurora`：两层斜放的色带，`filter: blur(22px)` → σ≈11。
  ///
  /// **透明度要折进渐变色里**，不能靠 `Paint.color`：设了 `shader` 之后 `Paint.color`
  /// 整个被忽略（不是叠加），写上去是一句看不见效果的空话。原型那两层的 `.5` / `.65`
  /// 是 CSS 的 `opacity:`，等价于把整层的 alpha 乘一遍。
  void _paintAurora(Canvas canvas, Size size) {
    // i1：inset -8% -20% 42%，opacity .5；i2：inset 18% -8% -22%，opacity .65、
    // delay -4、12 秒。
    final bands = [
      (top: -.08, bottom: .42, delay: 0.0, duration: 9.0, layer: .5),
      (top: .18, bottom: -.22, delay: -4.0, duration: 12.0, layer: .65),
    ];

    for (final band in bands) {
      final t = _easeInOut(_pingPong(band.duration, delay: band.delay));
      final rect = Rect.fromLTWH(
        -size.width * .20,
        size.height * band.top,
        size.width * 1.40,
        size.height * (1 - band.top + band.bottom),
      );

      canvas.save();
      canvas.translate(rect.center.dx, rect.center.dy);
      // `rotate(-8deg)` 起步，`sleepAurora` 再叠 `translate(8%,8%) skewX(-8deg)
      // scale(1.08)`；这里把位移与缩放折进画布变换（`skewX` 在暗色渐变的观感里
      // 与旋转叠加后看不出单独一档，略过）。
      canvas.rotate((-8) * math.pi / 180);
      canvas.translate(size.width * .08 * t, size.height * .08 * t);
      canvas.scale(1 + .08 * t);

      final r = Rect.fromCenter(
          center: Offset.zero, width: rect.width, height: rect.height);
      canvas.drawOval(
        r,
        Paint()
          ..shader = LinearGradient(
            begin: const Alignment(-.42, -.96),
            end: const Alignment(.42, .42),
            colors: [
              const Color(0x0047DCBD),
              const Color(0xFF47DCBD).withValues(alpha: .30 * band.layer),
              const Color(0xFF6671ED).withValues(alpha: .24 * band.layer),
              const Color(0x006671ED),
            ],
            stops: const [.22, .38, .58, .72],
          ).createShader(r)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 11),
      );
      canvas.restore();
    }
  }

  /// `.sleep-ocean-waves`：三条描边椭圆，`sleepWaveDrift` 往返。
  void _paintOceanWaves(Canvas canvas, Size size) {
    const specs = [
      (top: 0.0, opacity: .42, delay: 0.0),
      (top: .20, opacity: .42 * .7, delay: -4.0),
      (top: .42, opacity: .42 * .45, delay: -7.0),
    ];

    for (final spec in specs) {
      final t = _easeInOut(_pingPong(10, delay: spec.delay));
      final rect = Rect.fromLTWH(
        -size.width * .08 + size.width * 1.16 * .04 * t,
        size.height * .58 + size.height * .42 * spec.top - 10 * t,
        size.width * 1.16 * (1 + .06 * t),
        size.height * .42 * .52,
      );
      canvas.drawOval(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0x2651A8CA).withValues(alpha: spec.opacity),
      );
    }
  }

  /// `.sleep-clouds i` 三朵，`sleepCloud` 从左穿到右（0 → 170vw）。
  void _paintClouds(Canvas canvas, Size size) {
    const specs = [
      (top: .18, width: .50, duration: 26.0, delay: -0.0),
      (top: .55, width: .68, duration: 34.0, delay: -12.0),
      (top: .76, width: .44, duration: 29.0, delay: -21.0),
    ];

    for (final spec in specs) {
      final p = _progress(spec.duration, delay: spec.delay);
      final left = -size.width * .55 + size.width * 1.70 * p;
      final rect = Rect.fromLTWH(left, size.height * spec.top,
          size.width * spec.width, size.width * .15);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = const RadialGradient(
            colors: [Color(0x1AC8D6EE), Color(0x00000000)],
            stops: [0, .68],
          ).createShader(rect)
          // `.sleep-clouds i { filter: blur(8px) }` → σ≈4。
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }
  }

  /// `.sleep-fireflies i` 14 只，`sleepFirefly` 7 秒。
  ///
  /// 原型把前 10 只的位置与延迟逐个列了出来，其余四只共用 `left: 52%; top: 54%`；
  /// 这里照抄那份列表，第 11–14 只沿用 CSS 的共用值。
  void _paintFireflies(Canvas canvas, Size size) {
    const spots = [
      (left: 8.0, top: 25.0, delay: -0.0),
      (left: 18.0, top: 72.0, delay: -2.0),
      (left: 28.0, top: 44.0, delay: -5.0),
      (left: 38.0, top: 82.0, delay: -1.0),
      (left: 48.0, top: 31.0, delay: -3.0),
      (left: 58.0, top: 66.0, delay: -6.0),
      (left: 68.0, top: 17.0, delay: -4.0),
      (left: 78.0, top: 78.0, delay: -2.5),
      (left: 88.0, top: 42.0, delay: -5.5),
      (left: 93.0, top: 88.0, delay: -1.5),
      (left: 52.0, top: 54.0, delay: -3.5),
      (left: 52.0, top: 54.0, delay: -3.5),
      (left: 52.0, top: 54.0, delay: -3.5),
      (left: 52.0, top: 54.0, delay: -3.5),
    ];

    for (final spot in spots) {
      final p = _progress(7, delay: spot.delay);
      // `sleepFirefly`：0/100% opacity .15 + 原点；45% opacity 1 + (14,-24)；
      // 70% opacity .4 + (-9,-12)。三段线性插值。
      final double opacity;
      final Offset shift;
      if (p < .45) {
        final k = _easeInOut(p / .45);
        opacity = .15 + .85 * k;
        shift = Offset(14 * k, -24 * k);
      } else if (p < .70) {
        final k = (p - .45) / .25;
        opacity = 1 - .6 * k;
        shift = Offset.lerp(const Offset(14, -24), const Offset(-9, -12), k)!;
      } else {
        final k = _easeInOut((p - .70) / .30);
        opacity = .4 - .25 * k;
        shift = Offset.lerp(const Offset(-9, -12), Offset.zero, k)!;
      }

      // 最后四只共用同一格：`left: 52%; top: 54%; animation-delay: -3.5s` 逐字相同，
      // 是原型 CSS `nth-child(n+11)` 的原样。`_progress` 是纯函数，相位也一样，
      // 所以这四只严格叠在一起、透明度也相同——**实际可见 11 只，不是 14 只**。
      // 这是原型如此，不是笔误：照抄，不替它挪位置、也不「修好」它。
      final centre = Offset(
        spot.left / 100 * size.width + shift.dx,
        spot.top / 100 * size.height + shift.dy,
      );
      canvas.drawCircle(
        centre,
        1.5,
        Paint()
          ..color = const Color(0xFFD7E982).withValues(alpha: opacity)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
    }
  }

  /// `.sleep-galaxy-band`：一条斜带，`sleepGalaxy` 往返。
  void _paintGalaxy(Canvas canvas, Size size) {
    final t = _easeInOut(_pingPong(16));
    // `sleepGalaxy { to { opacity: .7 } }` 配 `alternate`：1 → .7 → 1。
    // 同样**折进渐变色**，设了 shader 之后 `Paint.color` 是被忽略的。
    final fade = 1 - .30 * t;
    final rect = Rect.fromLTWH(-size.width * .45, -size.height * .22,
        size.width * 1.90, size.height * 1.44);

    canvas.save();
    canvas.translate(rect.center.dx, rect.center.dy);
    // `rotate(-24deg)` → `rotate(-19deg) scale(1.08)`。
    canvas.rotate(((-24) + 5 * t) * math.pi / 180);
    canvas.scale(1 + .08 * t);
    final r = Rect.fromCenter(
        center: Offset.zero, width: rect.width, height: rect.height);
    canvas.drawRect(
      r,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            const Color(0x009671E0),
            const Color(0xFF9671E0).withValues(alpha: .05 * fade),
            const Color(0xFF6589DE).withValues(alpha: .18 * fade),
            const Color(0xFFCC9AE6).withValues(alpha: .06 * fade),
            const Color(0x00CC9AE6),
          ],
          stops: const [.32, .40, .50, .62, .68],
        ).createShader(r)
        // `filter: blur(12px)` → σ≈6。
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.restore();
  }

  /// `.sleep-rain-lines i` 18 条，`sleepRain` 2.8 秒，整层 `opacity: .18`。
  ///
  /// 原型逐个列了前 14 条的 `left`（4%/7% 递增到 95%）与各自的延迟；这里沿用同一个
  /// 递增规律给出 `left`，延迟用等距公式代替逐条列举——2.8 秒一轮的雨丝看不出
  /// 那条延迟差几十毫秒。
  void _paintRain(Canvas canvas, Size size) {
    for (var i = 0; i < 18; i++) {
      final left = (i < 14 ? 4 + i * 7 : 50) / 100;
      final delay = -((i * 0.7) % 2.8);
      final p = _progress(2.8, delay: delay);
      final top = -0.12 + p * 1.15;
      final rect = Rect.fromLTWH(left * size.width, top * size.height, 1, 38);
      canvas.drawRect(
        rect,
        Paint()
          // 整层 `.18` 的 opacity 折进这一条渐变里：`rgba(188,214,237,.8) × .18`。
          // 设了 shader 之后 `Paint.color` 会被忽略，那样写等于没写。
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x00BCD5ED), Color(0x25BCD5ED)],
          ).createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(_NightScenePainter oldDelegate) =>
      oldDelegate.scene != scene ||
      oldDelegate.phase != phase ||
      oldDelegate.reduceMotion != reduceMotion;
}
