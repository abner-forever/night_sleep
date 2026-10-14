import 'package:flutter/material.dart';

import '../night_style.dart';
import 'collapse_pill.dart';

/// 会话页顶部那一行：左边「收起」，中间两态各填各的，右边一块等宽占位。
///
/// **两态共用同一行**，差的是中间那段——入睡前是「睡眠模式」，进行中是呼吸圆点 +
/// 「睡眠进行中」。合并成一个壳的理由不只是省代码：**下拉关闭的手势就挂在整行上**，
/// 两态各写一份的话，任何一边漏挂都会变成「有一态拉不动」。
///
/// **整行都是下拉区，`收起` 胶囊也在区内**（用户 2026-10-14 拍的板，为的是「整行」
/// 名副其实——只包中间那段会把右侧那 56 的占位漏在外面）。点它仍然是点击，靠的是
/// 手势竞技场的既有裁决：胶囊自己的 `onTap` 比外层这个竖直识别器**更深**、先入队，
/// 抬起时 `sweep` 把胜利给最先入队者，而竖直识别器没越过 touch slop 会先 reject 自己。
///
/// 手势**只挂这一行**，不挂整个面板：面板主体是两个滚动视图（入睡前的
/// `SingleChildScrollView`、进行中的 `ListView`），面板级的竖直手势会和它们抢
/// （同 `app_sheet.dart` 里 `_SheetHandle` 那条注释记的教训）。
class SessionHeader extends StatelessWidget {
  /// 入睡前态：中间是「睡眠模式」。
  const SessionHeader.setup({
    super.key,
    required this.onCollapse,
    required this.onDragUpdate,
    required this.onDragEnd,
  }) : middle = const _SetupKicker();

  /// 进行中态：中间是呼吸圆点 +「睡眠进行中」。
  const SessionHeader.live({
    super.key,
    required this.onCollapse,
    required this.onDragUpdate,
    required this.onDragEnd,
  }) : middle = const _LiveKicker();

  /// 中间那一段。两态的子树**逐字搬过来**，不做「title + style」那套参数化——
  /// 插槽能让节点树与合并前逐节点相同，「视觉零改动」才真的成立。
  final Widget middle;

  final VoidCallback onCollapse;

  /// 跟手下拉的位移（逻辑像素，正数向下）。
  final ValueChanged<double> onDragUpdate;

  /// 松手时的竖直速度（`primaryVelocity`，向下为正）。
  final ValueChanged<double> onDragEnd;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (details) => onDragUpdate(details.delta.dy),
        onVerticalDragEnd: (details) => onDragEnd(details.primaryVelocity ?? 0),
        child: Row(
          children: [
            CollapsePill(onTap: onCollapse),
            Expanded(child: middle),
            // 右侧留一块与「收起」等宽的空白，中间的标题才真的落在整行正中
            // （原型用 `.sleep-header-spacer` 达到同一效果）。
            const SizedBox(width: 56),
          ],
        ),
      ),
    );
  }
}

/// 入睡前态的中段：`.sleep-kicker` 那句「睡眠模式」。
class _SetupKicker extends StatelessWidget {
  const _SetupKicker();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        '睡眠模式',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.4,
          color: NightStyle.kickerInk,
        ),
      ),
    );
  }
}

/// 进行中态的中段：呼吸圆点 + `.sleep-live-status` 那句「睡眠进行中」。
class _LiveKicker extends StatelessWidget {
  const _LiveKicker();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _PulseDot(),
        SizedBox(width: 8),
        Text(
          '睡眠进行中',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.3,
            color: NightStyle.statusText,
          ),
        ),
      ],
    );
  }
}

/// `.sleep-live-status > span:first-child`：2.2 秒一轮的呼吸圆点。
class _PulseDot extends StatefulWidget {
  const _PulseDot();

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (NightStyle.reduceMotion(context)) {
      _pulse.stop();
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) => Opacity(
        // `sleepPulse { 50% { opacity: .45 } }`
        opacity: 1 - 0.55 * Curves.easeInOut.transform(_pulse.value),
        child: child,
      ),
      child: const DecoratedBox(
        decoration: BoxDecoration(
          color: NightStyle.statusDot,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: NightStyle.statusDot, blurRadius: 12)],
        ),
        child: SizedBox(width: 6, height: 6),
      ),
    );
  }
}
