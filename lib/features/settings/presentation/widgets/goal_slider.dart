import 'package:flutter/material.dart';

import '../../../../core/platform/haptics.dart';
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
class GoalSlider extends StatefulWidget {
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
  State<GoalSlider> createState() => _GoalSliderState();
}

class _GoalSliderState extends State<GoalSlider> {
  /// 手指是否按在轨道上。按住时滑块长大一点，松手缩回。
  bool _active = false;

  /// 上一次跨过的步进下标。每跨一格补一次轻触感（iOS 滑块的刻度感），
  /// 同一次按下不重复响同一格。
  int? _lastStep;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    final canIncrease = widget.value < widget.max;
    final canDecrease = widget.value > widget.min;

    return Semantics(
      slider: true,
      label: widget.semanticLabel,
      value: widget.format(widget.value),
      increasedValue:
          canIncrease ? widget.format(_snap(widget.value + widget.step)) : null,
      decreasedValue:
          canDecrease ? widget.format(_snap(widget.value - widget.step)) : null,
      onIncrease: canIncrease
          ? () => widget.onChanged(_snap(widget.value + widget.step))
          : null,
      onDecrease: canDecrease
          ? () => widget.onChanged(_snap(widget.value - widget.step))
          : null,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;

          // 轨道的可走区间两端各让出半个滑块，滑块因此永远不会被裁掉一半。
          final travel = width - GoalSlider._thumbSize;
          final fraction = widget.max <= widget.min
              ? 0.0
              : (widget.value - widget.min) / (widget.max - widget.min);

          void emit(double dx) {
            if (travel <= 0) return;
            final t =
                ((dx - GoalSlider._thumbSize / 2) / travel).clamp(0.0, 1.0);
            final next = _snap(widget.min + t * (widget.max - widget.min));
            final stepIndex = ((next - widget.min) / widget.step).round();
            final currentStep =
                ((widget.value - widget.min) / widget.step).round();
            if (stepIndex != _lastStep && stepIndex != currentStep) {
              AppHaptics.select();
            }
            _lastStep = stepIndex;
            widget.onChanged(next);
          }

          void stop() {
            _lastStep = null;
            if (_active) setState(() => _active = false);
          }

          return GestureDetector(
            // `opaque`：整条轨道（含滑块以外的空白）都接手势，否则只有细轨道能按。
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) {
              if (!_active) setState(() => _active = true);
              emit(details.localPosition.dx);
            },
            onTapUp: (_) => stop(),
            onTapCancel: stop,
            onHorizontalDragStart: (details) {
              if (!_active) setState(() => _active = true);
              emit(details.localPosition.dx);
            },
            onHorizontalDragUpdate: (details) => emit(details.localPosition.dx),
            onHorizontalDragEnd: (_) => stop(),
            onHorizontalDragCancel: stop,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(end: _active ? 1.12 : 1),
              duration: const Duration(milliseconds: 160),
              curve: AppMotion.springyCurve,
              builder: (context, thumbScale, _) => CustomPaint(
                size: Size(width, GoalSlider._height),
                painter: _GoalSliderPainter(
                  fraction: fraction.clamp(0.0, 1.0),
                  thumbScale: thumbScale,
                  track: tokens.borderStrong,
                  accent: tokens.accent,
                  thumbFill: tokens.bgCardSolid,
                  shadow: tokens == AppTokens.dark
                      ? const Color(0x66000000)
                      : const Color(0x22101830),
                ),
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
    final steps = ((hours - widget.min) / widget.step).round();
    return (widget.min + steps * widget.step).clamp(widget.min, widget.max);
  }
}

class _GoalSliderPainter extends CustomPainter {
  const _GoalSliderPainter({
    required this.fraction,
    required this.thumbScale,
    required this.track,
    required this.accent,
    required this.thumbFill,
    required this.shadow,
  });

  final double fraction;

  /// 按住时的视觉放大。只放大画出来的半径，行程与命中区不变。
  final double thumbScale;

  final Color track;
  final Color accent;
  final Color thumbFill;
  final Color shadow;

  @override
  void paint(Canvas canvas, Size size) {
    final centreY = size.height / 2;
    // 轨道与行程用**基准半径**，只有画出来的滑块跟着 `thumbScale` 变大。
    // 拿放大后的半径去算轨道，按下的那一瞬整条轨道会向内缩一下。
    const baseRadius = GoalSlider._thumbSize / 2;
    final thumbRadius = baseRadius * thumbScale;

    final rail = Rect.fromLTRB(
      baseRadius,
      centreY - 3,
      size.width - baseRadius,
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
      oldDelegate.thumbScale != thumbScale ||
      oldDelegate.track != track ||
      oldDelegate.accent != accent ||
      oldDelegate.thumbFill != thumbFill ||
      oldDelegate.shadow != shadow;
}
