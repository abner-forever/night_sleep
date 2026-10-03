import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';

/// 「每晚睡眠目标」的滑块。
///
/// **为什么自绘而不是 `Slider`**：原型的轨道是一段**与取值无关**的三段渐变
/// （`linear-gradient(90deg, var(--border-strong), var(--accent), var(--border-strong))`），
/// 滑块是「3px accent 描边 + `bg-card-solid` 填充 + 投影」的圆。
/// Material `Slider` 的轨道按 `activeTrackColor` / `inactiveTrackColor` 以当前值
/// 一分为二，`SliderTheme` 表达不了这个形状；硬套出来是另一件东西。
///
/// 无障碍不能省：只画 `CustomPaint` 的控件对读屏是不可用的，所以外面套
/// [Semantics]，把「增大 / 减小」暴露成真正的 slider 动作，步长就是 [step]。
class GoalSlider extends StatelessWidget {
  const GoalSlider({
    super.key,
    required this.value,
    required this.onChanged,
    required this.format,
    this.min = 5,
    this.max = 12,
    this.step = 0.5,
    this.semanticLabel = '每晚睡眠目标',
  });

  /// 当前值（小时）。
  final double value;

  /// 取值已经吸附到 [step]、并夹在 `[min, max]` 之内。
  final ValueChanged<double> onChanged;

  /// 把小时数写成读屏要念的文字（「8 小时」「8 小时 30 分钟」），
  /// 供 [Semantics.value] / `increasedValue` / `decreasedValue` 使用。
  final String Function(double hours) format;

  final double min;
  final double max;
  final double step;
  final String semanticLabel;

  /// 控件总高。26px 的滑块要放得下，轨道 6px 居中。
  static const double _height = 28;

  /// 滑块直径，取自原型 `width: 26px; height: 26px`。
  static const double _thumbSize = 26;

  /// 滑块描边宽度，取自原型 `border: 3px solid var(--accent)`。
  static const double _thumbBorder = 3;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    final canIncrease = value < max;
    final canDecrease = value > min;

    return Semantics(
      slider: true,
      label: semanticLabel,
      value: format(value),
      increasedValue: canIncrease ? format(_snap(value + step)) : null,
      decreasedValue: canDecrease ? format(_snap(value - step)) : null,
      onIncrease: canIncrease ? () => onChanged(_snap(value + step)) : null,
      onDecrease: canDecrease ? () => onChanged(_snap(value - step)) : null,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;

          // 轨道的可走区间两端各让出半个滑块，滑块因此永远不会被裁掉一半。
          final travel = width - _thumbSize;
          final fraction = max <= min ? 0.0 : (value - min) / (max - min);

          void emit(double dx) {
            if (travel <= 0) return;
            final t = ((dx - _thumbSize / 2) / travel).clamp(0.0, 1.0);
            onChanged(_snap(min + t * (max - min)));
          }

          return GestureDetector(
            // `opaque`：整条轨道（含滑块以外的空白）都接手势，否则只有细轨道能按。
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => emit(details.localPosition.dx),
            onHorizontalDragStart: (details) => emit(details.localPosition.dx),
            onHorizontalDragUpdate: (details) => emit(details.localPosition.dx),
            child: CustomPaint(
              size: Size(width, _height),
              painter: _GoalSliderPainter(
                fraction: fraction.clamp(0.0, 1.0),
                track: tokens.borderStrong,
                accent: tokens.accent,
                thumbFill: tokens.bgCardSolid,
                shadow: tokens == AppTokens.dark
                    ? const Color(0x66000000)
                    : const Color(0x22101830),
              ),
            ),
          );
        },
      ),
    );
  }

  /// 吸附到步长并夹住。**写库前唯一的一处取整**，快捷按钮也走它，
  /// 免得出现两套 clamp/round 口径。
  double _snap(double hours) {
    final steps = ((hours - min) / step).round();
    return (min + steps * step).clamp(min, max);
  }
}

class _GoalSliderPainter extends CustomPainter {
  const _GoalSliderPainter({
    required this.fraction,
    required this.track,
    required this.accent,
    required this.thumbFill,
    required this.shadow,
  });

  final double fraction;
  final Color track;
  final Color accent;
  final Color thumbFill;
  final Color shadow;

  @override
  void paint(Canvas canvas, Size size) {
    final centreY = size.height / 2;
    const thumbRadius = GoalSlider._thumbSize / 2;

    final rail = Rect.fromLTRB(
      thumbRadius,
      centreY - 3,
      size.width - thumbRadius,
      centreY + 3,
    );
    if (rail.width <= 0) return;

    // 轨道与取值无关：两端淡、中间 accent 的三段渐变，照原型的 90deg 渐变。
    canvas.drawRRect(
      RRect.fromRectAndRadius(rail, const Radius.circular(3)),
      Paint()
        ..shader = LinearGradient(
          colors: [track, accent, track],
        ).createShader(rail),
    );

    final centre = Offset(rail.left + fraction * rail.width, centreY);

    canvas.drawCircle(
      centre,
      thumbRadius,
      Paint()
        ..color = shadow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(centre, thumbRadius, Paint()..color = thumbFill);
    canvas.drawCircle(
      centre,
      thumbRadius - GoalSlider._thumbBorder / 2,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = GoalSlider._thumbBorder,
    );
  }

  @override
  bool shouldRepaint(_GoalSliderPainter oldDelegate) =>
      oldDelegate.fraction != fraction ||
      oldDelegate.track != track ||
      oldDelegate.accent != accent ||
      oldDelegate.thumbFill != thumbFill ||
      oldDelegate.shadow != shadow;
}
