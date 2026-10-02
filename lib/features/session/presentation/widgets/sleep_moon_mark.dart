import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../night_style.dart';

/// 原型 `SleepMoonMark` 的月亮，逐字转写它的 SVG。
///
/// **`<filter>` 那一段被去掉了**，这是实测的结果而不是偷懒：`flutter_svg` 2.3 会
/// 静默丢弃 `<filter>`（控制台打一行 `unhandled element <filter/>`），渐变与裁剪
/// 都正常、外发光却不在，而且不抛异常。发光改由 [SleepMoonOrbit] 那圈径向光晕
/// 近似——原型自己的 `.sleep-moon-orbit::before/::after` 也各画了一圈光晕，
/// 所以这里近似的是同一层东西，不是凭空补一个形状。
///
/// 月亮的**上下浮动**动画与轨道光晕都在 [SleepMoonOrbit] 里，本组件只管月亮本身
/// （没有缩放或透明度那一层）。
const String sleepMoonSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="14 0 120 120">
  <defs>
    <linearGradient id="sleep-moon-body" x1="24" y1="18" x2="96" y2="104"
      gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#f5f7ff"/>
      <stop offset=".42" stop-color="#c8d4ff"/>
      <stop offset="1" stop-color="#8299eb"/>
    </linearGradient>
    <linearGradient id="sleep-moon-edge" x1="42" y1="24" x2="83" y2="93"
      gradientUnits="userSpaceOnUse">
      <stop stop-color="#ffffff" stop-opacity=".78"/>
      <stop offset="1" stop-color="#9cafef" stop-opacity=".08"/>
    </linearGradient>
    <radialGradient id="sleep-moon-crater">
      <stop stop-color="#6f82c8" stop-opacity=".5"/>
      <stop offset=".72" stop-color="#aebcf2" stop-opacity=".18"/>
      <stop offset="1" stop-color="#eef2ff" stop-opacity=".45"/>
    </radialGradient>
    <clipPath id="sleep-moon-clip">
      <path d="M78 17C53 20 34 39 34 63c0 25 20 44 45 42 14-1 26-8 34-19-8 4-17 6-26 4-22-4-36-24-33-46 2-13 11-23 24-27Z"/>
    </clipPath>
  </defs>
  <path d="M78 17C53 20 34 39 34 63c0 25 20 44 45 42 14-1 26-8 34-19-8 4-17 6-26 4-22-4-36-24-33-46 2-13 11-23 24-27Z"
    fill="url(#sleep-moon-body)"/>
  <g clip-path="url(#sleep-moon-clip)">
    <ellipse cx="45" cy="62" rx="9" ry="7" fill="url(#sleep-moon-crater)"
      transform="rotate(-18 45 62)"/>
    <ellipse cx="61" cy="87" rx="6.5" ry="5" fill="url(#sleep-moon-crater)"
      transform="rotate(22 61 87)"/>
    <ellipse cx="49" cy="39" rx="4" ry="3" fill="url(#sleep-moon-crater)"/>
    <path d="M27 77c18-8 35-24 47-48" fill="none" stroke="url(#sleep-moon-edge)"
      stroke-width="5" stroke-linecap="round"/>
  </g>
  <path d="M78 17C53 20 34 39 34 63c0 25 20 44 45 42" fill="none"
    stroke="rgba(255,255,255,.58)" stroke-width="1.2" stroke-linecap="round"/>
</svg>
''';

class SleepMoonMark extends StatelessWidget {
  const SleepMoonMark({super.key, this.size = 84});

  final double size;

  @override
  Widget build(BuildContext context) {
    // 原型 `.sleep-moon-mark { overflow: visible }`：月牙的两端会稍稍越出盒子，
    // 裁掉就会削掉两个尖。
    return SizedBox(
      width: size,
      height: size,
      child: SvgPicture.string(
        sleepMoonSvg,
        width: size,
        height: size,
        fit: BoxFit.contain,
        excludeFromSemantics: true,
      ),
    );
  }
}

/// 月亮 + 外面那圈轨道光晕。
///
/// `.sleep-moon-orbit`：116 见方的圆框，`1px rgba(150,167,255,.18)` 描边 + 径向
/// 渐变底 + 内外两层光晕。会话页中央那个大月亮（132 见方）额外套一层上下浮动。
class SleepMoonOrbit extends StatefulWidget {
  const SleepMoonOrbit({super.key, this.size = 116, this.live = false});

  /// 外圈直径。原型 setup 态是 116，激活态是 132。
  final double size;

  /// 激活态：整圈上下浮动（原型 `sleepFloat`，5 秒）。
  final bool live;

  @override
  State<SleepMoonOrbit> createState() => _SleepMoonOrbitState();
}

class _SleepMoonOrbitState extends State<SleepMoonOrbit>
    with SingleTickerProviderStateMixin {
  late final AnimationController _float = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 5),
  );

  /// `live` 为真且没开减弱动态效果 → 起表；否则 → 停表。
  ///
  /// 减弱动态效果时停表既是无障碍要求（对应原型 CSS 的
  /// `@media (prefers-reduced-motion: reduce)`），也是测试能收敛的前提：
  /// 循环动画会让 `pumpAndSettle()` 永不收敛（见计划头部的 Global Constraints）。
  void _sync() {
    if (widget.live && !NightStyle.reduceMotion(context)) {
      if (!_float.isAnimating) _float.repeat();
    } else {
      _float.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 覆盖 MediaQuery（减弱动态效果）变化这一路。
    _sync();
  }

  @override
  void didUpdateWidget(SleepMoonOrbit oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 父组件在同一个元素位置重建、只把 `live` 从 false 翻成 true 时，
    // `didChangeDependencies` 不会再跑（State 被复用、依赖没变），只有这里能接住，
    // 否则月亮会静默地不浮动。
    _sync();
  }

  @override
  void dispose() {
    _float.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.size;
    return AnimatedBuilder(
      animation: _float,
      builder: (context, child) => Transform.translate(
        // 原型 `@keyframes sleepFloat { 50% { transform: translateY(-7px) } }`
        // 配 `5s infinite`，**没有 alternate**：5 秒是「升到顶再落下」的一整轮，
        // 不是往返两轮。把 0→1 折成三角波（0→1→0）再套缓动，正好对上。
        offset: Offset(
          0,
          -7 *
              Curves.easeInOut.transform(
                1 - (2 * _float.value - 1).abs(),
              ),
        ),
        child: child,
      ),
      child: Container(
        width: d,
        height: d,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0x2E96A7FF)),
          gradient: const RadialGradient(
            colors: [Color(0x33758DED), Color(0x0F4A59A9), Color(0x00000000)],
            stops: [0, .60, .62],
          ),
          boxShadow: const [
            // 原型用 `box-shadow: 0 0 50px rgba(89,105,205,.15)` 加一层外发光。
            // 这也是月亮那一圈被 flutter_svg 丢掉的外发光的近似（见文件头注释）。
            BoxShadow(color: Color(0x265969CD), blurRadius: 50),
          ],
        ),
        child: Center(child: SleepMoonMark(size: d * 0.79)),
      ),
    );
  }
}
