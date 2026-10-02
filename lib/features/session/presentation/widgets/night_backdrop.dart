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

/// 八套夜景的几何：把原型 `index.css` / `App.tsx` 的数值**逐条转写**成 Dart 算式。
///
/// **为什么单独抽一层**：这一页出过的错（极光盒高的符号、流星位移的分母、极光 i2 的
/// 左右内缩、海浪的嵌套百分比、`animation-delay` 的正负号……）全部出在
/// 「看着 CSS 手写 Dart 公式」这一步，而画进 `Canvas` 的东西没法在单测里直接断言。
/// 把算式拎成纯函数，`test/night_backdrop_test.dart` 才能拿 CSS 的字面量去核。
///
/// **坐标口径**：这些元素的包含块是 `.sleep-scene-visual { position: fixed; inset: 0 }`，
/// 也就是整块画布，所以它的 `%` / `vw` / `vh` 一律相对 `size` 解析；
/// **只有嵌套元素的 `%` 相对父盒**（海浪那层要当心）。
///
/// **有意的近似**（不假装逐像素）：
/// - `filter: blur(N)` 一律换算成 `MaskFilter.blur(…, N/2)`（CSS 的半径对应高斯 σ = r/2）；
/// - `animation-direction: alternate` 用三角波 [pingPong]；
/// - 各处的 `ease` / `ease-in` / `ease-in-out` 只在少数几处用 `Curves` 近似，
///   其余按线性处理（暗色渐变里看不出差别）；
/// - `radial-gradient(circle, …)` 的半径口径：CSS 按 farthest-corner、Flutter 的
///   `RadialGradient.radius` 按短边，所以光晕的**外扩范围**是近似的（色带形状对得上）。
@visibleForTesting
abstract final class NightSceneGeometry {
  // ── 通用 ────────────────────────────────────────────────────────────────
  /// CSS 的 `animation-direction: alternate`——往返一趟。
  static double pingPong(double v) => 1 - (2 * v - 1).abs();

  /// CSS 的 `ease-in-out`。
  static double easeInOut(double t) =>
      Curves.easeInOut.transform(t.clamp(0.0, 1.0));

  /// 某个元素在它自己那一轮里的进度（0–1）。
  ///
  /// `delay` 就是 CSS 的 `animation-delay`，**原样传进来、不要翻符号**：
  /// CSS 的本地时间是 `t - delay`，所以 `-4s`（相位提前）自带负号、
  /// `3.8s`（晚开始）自带正号。
  ///
  /// 近似：这里对负的本地时间取模回绕，而 CSS 在 `animation-fill-mode: none`
  /// （默认）下是「延迟期间保持元素自身的基线样式」。差别只出现在每 60 秒循环的
  /// 最前面那一小段（最长 3.44 秒，星点里延迟最大的一颗），暗色背景上看不出来。
  static double loopProgress(
      {required double t, required double duration, double delay = 0}) {
    final v = ((t - delay) / duration) % 1.0;
    return v < 0 ? v + 1 : v;
  }

  // ── 网点 ────────────────────────────────────────────────────────────────
  /// `.sleep-mode::before { background-size: 67px 67px;
  ///   background-image: radial-gradient(circle, rgba(255,255,255,.7) 0 1px, transparent 1.5px);
  ///   opacity: .13 }`。折出来 alpha = .7 × .13 ≈ .091。
  ///
  /// 近似：CSS 的渐变圆心默认在每格的**中心**，这里画在格点左上角——周期图案整体平移
  /// 半格，看不出差别。
  static const double textureStep = 67;
  static const double textureAlpha = .7 * .13;

  // ── 光晕 ────────────────────────────────────────────────────────────────
  /// `.sleep-scene-glow { opacity: .55 }`——两层光晕共用的**整层**透明度。
  /// 原型的 `filter: blur(4px)` 不跟：对这种尺寸的软径向渐变不足 1% 的差别。
  static const double glowOpacity = .55;

  /// `.sleep-scene-glow-one { width: 70vw; height: 42vw; top: -12vw; right: -10vw }`
  /// ⇒ 左边 = 100vw - 10vw - 70vw = 40vw。
  static Rect glowOneRect(Size size) => Rect.fromLTWH(
      size.width * .40, -size.width * .12, size.width * .70, size.width * .42);

  /// `.sleep-scene-moon .sleep-scene-glow-one { width: 48vw; height: 48vw; top: 8%; right: 7% }`
  /// ⇒ 左边 = 100% - 7% - 48% = 45% **宽**；`top: 8%` 是相对容器**高**。
  static Rect moonGlowRect(Size size) => Rect.fromLTWH(
      size.width * .45, size.height * .08, size.width * .48, size.width * .48);

  /// `.sleep-scene-glow-two { width: 62vw; height: 48vw; bottom: -20vw; left: -18vw }`
  /// ⇒ 顶边 = H + 20vw - 48vw（`bottom` 是 vw 单位，跟高无关）。
  static Rect glowTwoRect(Size size) => Rect.fromLTWH(-size.width * .18,
      size.height - size.width * .28, size.width * .62, size.width * .48);

  // ── 星点 ────────────────────────────────────────────────────────────────
  /// `SLEEP_STARS`（原型 App.tsx）：34 颗。`left`/`top` 是**百分数**。
  static const int starCount = 34;
  static double starLeft(int i) => ((i * 37 + 11) % 97) / 100;
  static double starTop(int i) => ((i * 53 + 7) % 82) / 100;

  /// `size: index % 6 === 0 ? 2 : 1`——那是**直径**（px），半径减半。
  static double starRadius(int i) => i % 6 == 0 ? 1 : .5;

  /// `animationDelay: (index % 9) * 0.43`（秒）——**正数**，即「晚一点才开始」。
  static double starDelay(int i) => (i % 9) * .43;

  /// `sleepTwinkle { 50% { opacity: .25; transform: scale(.65) } }`，4.5 秒，
  /// **没有** `alternate`（0% 与 100% 都是原样，中点最暗最小）。
  /// 返回 0–1 的「闪烁程度」：0 = 原样，1 = 中点。
  static double starTwinkleAt(double v) => easeInOut(pingPong(v));

  // ── 流星 ────────────────────────────────────────────────────────────────
  /// `.sleep-meteors i` 三条：基线是 `top: 8%; left: 78%; width: 110px`，
  /// 第 2/3 条由 `:nth-child(2)` / `:nth-child(3)` 覆盖。
  static const meteorTop = [.08, .27, .15];
  static const meteorLeft = [.78, .92, .55];
  static const meteorWidth = [110.0, 76.0, 58.0];
  static const meteorDuration = [8.5, 10.5, 12.0];

  /// CSS 的 `animation-delay` 是**正数**（3.8s / 7.1s）——「晚 3.8 秒才开始」。
  static const meteorDelay = [0.0, 3.8, 7.1];

  /// `sleepMeteor`：`0%, 82% { opacity: 0 }` 与 `91%, 100% { opacity: 0 }`
  /// 给出可见窗口，`84%` 是唯一亮点。
  static bool meteorVisibleAt(double p) => p >= .82 && p <= .91;

  /// `transform` 只在 `82%` 与 `91%` 两处声明，所以 `0 → (-58vw, 38vw)` 是在
  /// 这 9% 的区间里走完的（不是走到 100%）。
  static double meteorTravelAt(double p) => ((p - .82) / .09).clamp(0.0, 1.0);

  /// 透明度：`82% → 0`、`84% → .9`、`91% → 0`（两段线性）。
  static double meteorOpacityAt(double p) {
    if (!meteorVisibleAt(p)) return 0;
    return p < .84 ? .9 * (p - .82) / .02 : .9 * (.91 - p) / .07;
  }

  /// `background: linear-gradient(90deg, transparent, rgba(230,237,255,.85))`
  /// ——拖尾末端的 alpha 上限。
  static const meteorTrailAlpha = .85;

  // ── 极光 ────────────────────────────────────────────────────────────────
  /// `.sleep-scene-aurora .sleep-aurora { inset: -8% -20% 42% }`（i1）与
  /// `.sleep-aurora i:nth-child(2) { inset: 18% -8% -22% }`（i2）。
  ///
  /// CSS 的 `inset: A B C D` 是 top / right / bottom / left，于是
  /// 宽 = `W(1 - left - right)`、高 = `H(1 - top - bottom)`。
  /// **两层的左右内缩不同**（i1 是 -20%，i2 是 -8%），所以宽与左偏移都不一样。
  static Rect auroraBandRect(Size size, int index) => index == 0
      ? Rect.fromLTWH(-size.width * .20, -size.height * .08, size.width * 1.40,
          size.height * .66)
      : Rect.fromLTWH(-size.width * .08, size.height * .18, size.width * 1.16,
          size.height * 1.04);

  /// i1 `9s` / i2 `12s`；i2 另有 `animation-delay: -4s`（负号 = 相位**提前**）。
  static const auroraDuration = [9.0, 12.0];
  static const auroraDelay = [0.0, -4.0];

  /// `.sleep-aurora` 是 `opacity: .5`，`:nth-child(2)` 覆盖成 `.65`。
  static const auroraLayerOpacity = [.5, .65];

  /// `sleepAurora { to { transform: translate(8%, 8%) skewX(-8deg) scale(1.08) } }`。
  /// `translate` 的百分比相对**色带自己**的尺寸（不是视口）；`skewX` 略过——
  /// 它与那点旋转叠加在暗色渐变上看不出单独一档。
  static const auroraTranslate = .08;
  static const auroraScale = .08;

  // ── 海浪 ────────────────────────────────────────────────────────────────
  /// `.sleep-scene-ocean .sleep-ocean-waves { position: absolute; inset: auto -12% -4%;
  ///   height: 42%; opacity: .42 }`。
  ///
  /// `inset: auto A B` ⇒ top 由 `bottom: -4%`（相对容器**高**）反推：
  /// 顶边 = H + 4%H - 42%H = 62%H；左右各外扩 12% ⇒ 宽 124%W。
  static Rect oceanWaveContainerRect(Size size) => Rect.fromLTWH(
      -size.width * .12,
      size.height * (1 + .04 - .42),
      size.width * 1.24,
      size.height * .42);

  /// `.sleep-ocean-waves i { left: -8%; width: 116%; height: 52%; top: 0 / 20% / 42% }`
  /// ——**这些百分比相对父盒**（`.sleep-ocean-waves`），不是视口，所以先乘容器的宽/高。
  static const oceanWaveTop = [0.0, .20, .42];
  static const oceanWaveDelay = [0.0, -4.0, -7.0];

  /// `border: 1px solid rgba(81,168,202,.15)` × 容器 `opacity: .42` × 子元素各自的
  /// `opacity`（`1` / `.7` / `.45`）——三者相乘才是描边真正的不透明度。
  static const oceanWaveStrokeAlpha = .15 * .42;
  static const oceanWaveChildOpacity = [1.0, .7, .45];

  /// `sleepWaveDrift { to { transform: translateX(4%) translateY(-10px) scaleX(1.06) } }`。
  ///
  /// `transform-origin` 默认在元素中心：缩放不动中心，平移直接加在中心上。
  /// `translateX(4%)` 的百分比同样是**元素自己**的宽。轴对齐椭圆被 `scaleX`
  /// 拉完仍是轴对齐椭圆，所以结果能用矩形精确表示（描边宽度按 1px 画，不跟着拉）。
  static Rect oceanWaveRect(Size size, int index, double t) {
    final box = oceanWaveContainerRect(size);
    final left = box.left + box.width * -.08;
    final top = box.top + box.height * oceanWaveTop[index];
    final width = box.width * 1.16;
    final height = box.height * .52;
    final centre = Offset(
      left + width / 2 + width * .04 * t,
      top + height / 2 - 10 * t,
    );
    return Rect.fromCenter(
      center: centre,
      width: width * (1 + .06 * t),
      height: height,
    );
  }

  // ── 云 ──────────────────────────────────────────────────────────────────
  /// `.sleep-clouds i { position: absolute; left: -55vw; width: 50vw; height: 15vw }`
  /// 加 `sleepCloud { from { translateX(0) } to { translateX(170vw) } }`
  /// ⇒ 横向从 **-55vw 走到 115vw**。
  static const cloudTop = [.18, .55, .76];
  static const cloudWidth = [.50, .68, .44];
  static const cloudHeight = .15;
  static const cloudDuration = [26.0, 34.0, 29.0];
  static const cloudDelay = [0.0, -12.0, -21.0];
  static double cloudLeftAt(Size size, double p) =>
      size.width * (-.55 + 1.70 * p);

  // ── 萤火 ────────────────────────────────────────────────────────────────
  /// `.sleep-fireflies i:nth-child(1..10)` 逐条列举；`:nth-child(n+11)` 共用
  /// `left: 52%; top: 54%; animation-delay: -3.5s`，所以第 11–14 只**严格重叠**
  /// （相位也相同），实际可见 11 只。**原型如此，不是笔误**，照抄。
  static const fireflyLeft = [
    8.0, 18.0, 28.0, 38.0, 48.0, 58.0, 68.0, 78.0, 88.0, 93.0, //
    52.0, 52.0, 52.0, 52.0,
  ];
  static const fireflyTop = [
    25.0, 72.0, 44.0, 82.0, 31.0, 66.0, 17.0, 78.0, 42.0, 88.0, //
    54.0, 54.0, 54.0, 54.0,
  ];
  static const fireflyDelay = [
    0.0, -2.0, -5.0, -1.0, -3.0, -6.0, -4.0, -2.5, -5.5, -1.5, //
    -3.5, -3.5, -3.5, -3.5,
  ];

  /// `.sleep-fireflies i { width: 3px; height: 3px }` ⇒ 半径 1.5。
  static const fireflyRadius = 1.5;

  /// `sleepFirefly { 0%, 100% { opacity: .15; translate(0,0) }
  ///   45% { opacity: 1; translate(14px, -24px) }
  ///   70% { opacity: .4; translate(-9px, -12px) } }`——三段线性插值。
  static double fireflyOpacityAt(double p) {
    if (p < .45) return .15 + .85 * easeInOut(p / .45);
    if (p < .70) return 1 - .6 * ((p - .45) / .25);
    return .4 - .25 * easeInOut((p - .70) / .30);
  }

  static Offset fireflyShiftAt(double p) {
    if (p < .45) {
      final k = easeInOut(p / .45);
      return Offset(14 * k, -24 * k);
    }
    if (p < .70) {
      final k = (p - .45) / .25;
      return Offset.lerp(const Offset(14, -24), const Offset(-9, -12), k)!;
    }
    final k = easeInOut((p - .70) / .30);
    return Offset.lerp(const Offset(-9, -12), Offset.zero, k)!;
  }

  // ── 银河 ────────────────────────────────────────────────────────────────
  /// `.sleep-scene-galaxy .sleep-galaxy-band { inset: -22% -45%; transform: rotate(-24deg) }`
  /// ⇒ 宽 = W(1 + 90%) = 190%W、高 = H(1 + 44%) = 144%H、左上角 (-45%W, -22%H)。
  static Rect galaxyBandRect(Size size) => Rect.fromLTWH(-size.width * .45,
      -size.height * .22, size.width * 1.90, size.height * 1.44);

  /// `sleepGalaxy { to { transform: rotate(-19deg) scale(1.08); opacity: .7 } }`
  /// 配 `alternate`：起点是基线的 `rotate(-24deg)`、`scale(1)`、`opacity: 1`。
  static double galaxyAngleAt(double t) => (-24 + 5 * t) * math.pi / 180;
  static double galaxyScaleAt(double t) => 1 + .08 * t;
  static double galaxyFadeAt(double t) => 1 - .30 * t;

  // ── 雨丝 ────────────────────────────────────────────────────────────────
  /// `.sleep-rain-lines i:nth-child(1..14)` 逐条列举 `left` 与 `animation-delay`；
  /// `:nth-child(n+15)` 共用 `left: 50%; animation-delay: -2s`。
  /// 共 18 条（原型 `Array.from({ length: 18 })`），后 4 条同样重叠。
  static const rainLeft = [
    .04, .11, .18, .25, .32, .39, .46, .53, .60, .67, .74, .81, .88, .95, //
    .50, .50, .50, .50,
  ];
  static const rainDelay = [
    0.0, -.8, -1.7, -.2, -2.1, -1.1, -.5, -2.3, -1.4, -.3, -1.9, -.9, -2.5,
    -1.3, //
    -2.0, -2.0, -2.0, -2.0,
  ];

  /// `.sleep-rain-lines i { top: -12%; width: 1px; height: 38px }` 加
  /// `sleepRain { to { translateY(115vh) } }` ⇒ 纵向从 -12vh 走到 103vh。
  static const rainHeight = 38.0;
  static double rainTopAt(Size size, double p) =>
      size.height * (-.12 + 1.15 * p);

  /// `.sleep-rain-lines { opacity: .18 }` × 线色 `rgba(188,214,237,.8)`。
  static const rainAlpha = .8 * .18;
}

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

  double _progress(double seconds, {double delay = 0}) {
    if (reduceMotion) return 0;
    return NightSceneGeometry.loopProgress(
        t: phase * _kLoopSeconds, duration: seconds, delay: delay);
  }

  double _pingPong(double seconds, {double delay = 0}) =>
      NightSceneGeometry.pingPong(_progress(seconds, delay: delay));

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

  void _paintTexture(Canvas canvas, Size size) {
    const step = NightSceneGeometry.textureStep;
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: NightSceneGeometry.textureAlpha);
    for (var y = 0.0; y < size.height + step; y += step) {
      for (var x = 0.0; x < size.width + step; x += step) {
        canvas.drawCircle(Offset(x, y), 1, paint);
      }
    }
  }

  /// `.sleep-scene-glow-one` / `-two`：两团大范围径向光晕。
  void _paintGlows(Canvas canvas, Size size) {
    final moon = scene == NightScene.moon;
    const layer = NightSceneGeometry.glowOpacity;

    // 月华：`.sleep-scene-moon .sleep-scene-glow-one` 换成 48vw 见方的一轮月华。
    // 它的渐变多一档 `rgba(226,232,255,.27) 0 5%`——0–5% 是一块**平**的亮盘，
    // 所以 stops 是 [0, .05, .14, .57]，前两档同色。
    final oneRect = moon
        ? NightSceneGeometry.moonGlowRect(size)
        : NightSceneGeometry.glowOneRect(size);
    canvas.drawRect(
      oneRect,
      Paint()
        ..shader = (moon
                ? RadialGradient(
                    colors: [
                      const Color(0xFFE2E8FF).withValues(alpha: .27 * layer),
                      const Color(0xFFE2E8FF).withValues(alpha: .27 * layer),
                      const Color(0xFF97A3DC).withValues(alpha: .16 * layer),
                      const Color(0xFF97A3DC).withValues(alpha: 0),
                    ],
                    stops: const [0, .05, .14, .57],
                  )
                : RadialGradient(
                    colors: [
                      const Color(0xFF6D7EE0).withValues(alpha: .26 * layer),
                      const Color(0xFF6D7EE0).withValues(alpha: 0),
                    ],
                    stops: const [0, .68],
                  ))
            .createShader(oneRect),
    );

    final twoRect = NightSceneGeometry.glowTwoRect(size);
    canvas.drawRect(
      twoRect,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFF1F7695).withValues(alpha: .16 * layer),
            const Color(0xFF1F7695).withValues(alpha: 0),
          ],
          stops: const [0, .70],
        ).createShader(twoRect),
    );
  }

  /// `.sleep-stars i` 34 颗 + `sleepTwinkle`（中点 opacity .25、scale .65，4.5 秒）。
  void _paintStars(Canvas canvas, Size size) {
    for (var i = 0; i < NightSceneGeometry.starCount; i++) {
      final radius = NightSceneGeometry.starRadius(i);
      final twinkle = reduceMotion
          ? 0.0
          : NightSceneGeometry.starTwinkleAt(
              _progress(4.5, delay: NightSceneGeometry.starDelay(i)));
      final opacity = 1 - 0.75 * twinkle;
      final scale = 1 - 0.35 * twinkle;

      final centre = Offset(NightSceneGeometry.starLeft(i) * size.width,
          NightSceneGeometry.starTop(i) * size.height);
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

  /// `.sleep-meteors i` 三条 + `sleepMeteor`。
  void _paintMeteors(Canvas canvas, Size size) {
    for (var i = 0; i < NightSceneGeometry.meteorTop.length; i++) {
      final p = _progress(NightSceneGeometry.meteorDuration[i],
          delay: NightSceneGeometry.meteorDelay[i]);
      if (!NightSceneGeometry.meteorVisibleAt(p)) continue;

      final opacity = NightSceneGeometry.meteorOpacityAt(p);
      final travel = NightSceneGeometry.meteorTravelAt(p);
      final origin = Offset(NightSceneGeometry.meteorLeft[i] * size.width,
          NightSceneGeometry.meteorTop[i] * size.height);
      // `translate(-58vw, 38vw)`——两个分量都是 **vw**，所以都乘宽。
      final offset =
          Offset(-.58 * size.width * travel, .38 * size.width * travel);

      canvas.save();
      canvas.translate(origin.dx + offset.dx, origin.dy + offset.dy);
      canvas.rotate(-32 * math.pi / 180);
      final rect = Rect.fromLTWH(0, -0.5, NightSceneGeometry.meteorWidth[i], 1);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            colors: [
              const Color(0xFFE6EDFF).withValues(alpha: 0),
              const Color(0xFFE6EDFF).withValues(
                  alpha: NightSceneGeometry.meteorTrailAlpha * opacity),
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
    for (var i = 0; i < NightSceneGeometry.auroraDuration.length; i++) {
      final t = NightSceneGeometry.easeInOut(_pingPong(
          NightSceneGeometry.auroraDuration[i],
          delay: NightSceneGeometry.auroraDelay[i]));
      final rect = NightSceneGeometry.auroraBandRect(size, i);
      final layer = NightSceneGeometry.auroraLayerOpacity[i];

      canvas.save();
      canvas.translate(rect.center.dx, rect.center.dy);
      // 基线 `rotate(-8deg)`。`sleepAurora` 的 `translate(8%,8%)` 相对**色带自己**，
      // 加在已经对好中心的画布上就是色带内的百分比。
      canvas.rotate((-8) * math.pi / 180);
      canvas.translate(rect.width * NightSceneGeometry.auroraTranslate * t,
          rect.height * NightSceneGeometry.auroraTranslate * t);
      canvas.scale(1 + NightSceneGeometry.auroraScale * t);

      final r = Rect.fromCenter(
          center: Offset.zero, width: rect.width, height: rect.height);
      canvas.drawOval(
        r,
        Paint()
          ..shader = LinearGradient(
            begin: const Alignment(-.42, -.96),
            end: const Alignment(.42, .42),
            colors: [
              const Color(0xFF47DCBD).withValues(alpha: 0),
              const Color(0xFF47DCBD).withValues(alpha: .30 * layer),
              const Color(0xFF6671ED).withValues(alpha: .24 * layer),
              const Color(0xFF6671ED).withValues(alpha: 0),
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
    for (var i = 0; i < NightSceneGeometry.oceanWaveTop.length; i++) {
      final t = NightSceneGeometry.easeInOut(
          _pingPong(10, delay: NightSceneGeometry.oceanWaveDelay[i]));
      // 描边色 `rgba(81,168,202,.15)` × 容器 `.42` × 子元素各档，三者相乘。
      final alpha = NightSceneGeometry.oceanWaveStrokeAlpha *
          NightSceneGeometry.oceanWaveChildOpacity[i];
      canvas.drawOval(
        NightSceneGeometry.oceanWaveRect(size, i, t),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0xFF51A8CA).withValues(alpha: alpha),
      );
    }
  }

  /// `.sleep-clouds i` 三朵，`sleepCloud` 从左穿到右（-55vw → 115vw）。
  void _paintClouds(Canvas canvas, Size size) {
    for (var i = 0; i < NightSceneGeometry.cloudTop.length; i++) {
      final p = _progress(NightSceneGeometry.cloudDuration[i],
          delay: NightSceneGeometry.cloudDelay[i]);
      final rect = Rect.fromLTWH(
        NightSceneGeometry.cloudLeftAt(size, p),
        size.height * NightSceneGeometry.cloudTop[i],
        size.width * NightSceneGeometry.cloudWidth[i],
        size.width * NightSceneGeometry.cloudHeight,
      );
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            colors: [
              const Color(0xFFC8D6EE).withValues(alpha: .10),
              const Color(0xFFC8D6EE).withValues(alpha: 0),
            ],
            stops: const [0, .68],
          ).createShader(rect)
          // `.sleep-clouds i { filter: blur(8px) }` → σ≈4。
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }
  }

  /// `.sleep-fireflies i` 14 只，`sleepFirefly` 7 秒。
  void _paintFireflies(Canvas canvas, Size size) {
    for (var i = 0; i < NightSceneGeometry.fireflyLeft.length; i++) {
      final p = _progress(7, delay: NightSceneGeometry.fireflyDelay[i]);
      final shift = NightSceneGeometry.fireflyShiftAt(p);
      final centre = Offset(
        NightSceneGeometry.fireflyLeft[i] / 100 * size.width + shift.dx,
        NightSceneGeometry.fireflyTop[i] / 100 * size.height + shift.dy,
      );
      canvas.drawCircle(
        centre,
        NightSceneGeometry.fireflyRadius,
        Paint()
          ..color = const Color(0xFFD7E982)
              .withValues(alpha: NightSceneGeometry.fireflyOpacityAt(p))
          // `box-shadow: 0 0 10px #b9d75b` → σ≈5。
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
    }
  }

  /// `.sleep-galaxy-band`：一条斜带，`sleepGalaxy` 往返。
  void _paintGalaxy(Canvas canvas, Size size) {
    final t = NightSceneGeometry.easeInOut(_pingPong(16));
    // `sleepGalaxy { to { opacity: .7 } }` 配 `alternate`：1 → .7 → 1。
    // 同样**折进渐变色**，设了 shader 之后 `Paint.color` 是被忽略的。
    final fade = NightSceneGeometry.galaxyFadeAt(t);
    final rect = NightSceneGeometry.galaxyBandRect(size);

    canvas.save();
    canvas.translate(rect.center.dx, rect.center.dy);
    canvas.rotate(NightSceneGeometry.galaxyAngleAt(t));
    canvas.scale(NightSceneGeometry.galaxyScaleAt(t));
    final r = Rect.fromCenter(
        center: Offset.zero, width: rect.width, height: rect.height);
    canvas.drawRect(
      r,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            const Color(0xFF9671E0).withValues(alpha: 0),
            const Color(0xFF9671E0).withValues(alpha: .05 * fade),
            const Color(0xFF6589DE).withValues(alpha: .18 * fade),
            const Color(0xFFCC9AE6).withValues(alpha: .06 * fade),
            const Color(0xFFCC9AE6).withValues(alpha: 0),
          ],
          stops: const [.32, .40, .50, .62, .68],
        ).createShader(r)
        // `filter: blur(12px)` → σ≈6。
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.restore();
  }

  /// `.sleep-rain-lines i` 18 条，`sleepRain` 2.8 秒，整层 `opacity: .18`。
  void _paintRain(Canvas canvas, Size size) {
    for (var i = 0; i < NightSceneGeometry.rainLeft.length; i++) {
      final p = _progress(2.8, delay: NightSceneGeometry.rainDelay[i]);
      final rect = Rect.fromLTWH(
        NightSceneGeometry.rainLeft[i] * size.width,
        NightSceneGeometry.rainTopAt(size, p),
        1,
        NightSceneGeometry.rainHeight,
      );
      canvas.drawRect(
        rect,
        Paint()
          // 整层 `.18` 的 opacity 与线色自带的 `.8` 一起折进这条渐变里。
          // 设了 shader 之后 `Paint.color` 会被忽略，那样写等于没写。
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFFBCD5ED).withValues(alpha: 0),
              const Color(0xFFBCD5ED)
                  .withValues(alpha: NightSceneGeometry.rainAlpha),
            ],
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
