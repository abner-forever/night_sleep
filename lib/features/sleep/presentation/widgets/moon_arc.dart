import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../domain/sleep_stage.dart';

/// `MoonArc` — the hero dial on Home and the live preview on the Log tab.
///
/// Four concentric arcs drawn from the top of the circle, outermost first:
/// overall duration against an 8-hour reference, then deep, light and REM time
/// against the measured total. A moon glyph sits in the middle.
///
/// The prototype scales a 128-unit viewBox to the requested pixel size, so all
/// geometry here is expressed in that 128-unit space and scaled once.
class MoonArc extends StatefulWidget {
  const MoonArc({
    super.key,
    required this.durationHours,
    this.stages = const [],
    this.size = 128,
    this.animate = false,
  });

  final double durationHours;
  final List<SleepStageSegment> stages;
  final double size;

  /// Draws the arcs from empty on first build (`ring-animate`).
  final bool animate;

  static const double _viewBox = 128;

  @override
  State<MoonArc> createState() => _MoonArcState();
}

class _MoonArcState extends State<MoonArc> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
      value: widget.animate ? 0 : 1,
    );
    if (widget.animate) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(covariant MoonArc oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The log preview updates live as the user spins the pickers; only the
    // first arrival animates, so later value changes must not replay the draw.
    if (!widget.animate && oldWidget.animate) {
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int _minutesFor(SleepStageType stage) {
    var total = 0;
    for (final segment in widget.stages) {
      if (segment.stage == stage) total += segment.minutes;
    }
    return total;
  }

  int get _totalMinutes {
    var total = 0;
    for (final segment in widget.stages) {
      total += segment.minutes;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final hasStages = widget.stages.isNotEmpty;
    final total = _totalMinutes;

    // A screen-reader summary, mirroring the prototype's aria-label.
    final semantics = hasStages
        ? '睡眠 ${widget.durationHours.toStringAsFixed(1)} 小时，'
            '深睡 ${_minutesFor(SleepStageType.deep)} 分钟，'
            '浅睡 ${_minutesFor(SleepStageType.light)} 分钟，'
            '快速眼动 ${_minutesFor(SleepStageType.rem)} 分钟'
        : '睡眠 ${widget.durationHours.toStringAsFixed(1)} 小时';

    final scale = widget.size / MoonArc._viewBox;

    return Semantics(
      label: semantics,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = Curves.easeOutCubic.transform(_controller.value);
          return SizedBox(
            width: widget.size,
            height: widget.size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: Size.square(widget.size),
                  painter: _MoonArcPainter(
                    scale: scale,
                    progress: t,
                    trackColor: tokens.borderStrong,
                    rings: [
                      // Outermost: total duration against an 8h reference.
                      _RingSpec(
                        radius: 53,
                        value: widget.durationHours,
                        max: 8,
                        color: tokens.accent,
                        strokeWidth: 8,
                      ),
                      if (hasStages && total > 0) ...[
                        _RingSpec(
                          radius: 40,
                          value: _minutesFor(SleepStageType.deep).toDouble(),
                          max: total.toDouble(),
                          color: tokens.stageDeep,
                          strokeWidth: 8,
                        ),
                        _RingSpec(
                          radius: 27,
                          value: _minutesFor(SleepStageType.light).toDouble(),
                          max: total.toDouble(),
                          color: tokens.stageLight,
                          strokeWidth: 8,
                        ),
                        _RingSpec(
                          radius: 14,
                          value: _minutesFor(SleepStageType.rem).toDouble(),
                          max: total.toDouble(),
                          color: tokens.stageRem,
                          strokeWidth: 7,
                        ),
                      ],
                    ],
                  ),
                ),
                AppIcons.moon(
                  size: (hasStages ? 18 : 24) * scale,
                  color: tokens.accent,
                  strokeWidth: 1.55,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _RingSpec {
  const _RingSpec({
    required this.radius,
    required this.value,
    required this.max,
    required this.color,
    required this.strokeWidth,
  });

  final double radius;
  final double value;
  final double max;
  final Color color;
  final double strokeWidth;
}

class _MoonArcPainter extends CustomPainter {
  const _MoonArcPainter({
    required this.rings,
    required this.scale,
    required this.progress,
    required this.trackColor,
  });

  final List<_RingSpec> rings;
  final double scale;
  final double progress;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);

    for (final ring in rings) {
      final radius = ring.radius * scale;
      final stroke = ring.strokeWidth * scale;
      final rect = Rect.fromCircle(center: centre, radius: radius);

      // Track: the full circle at 38% opacity, drawn under every arc.
      canvas.drawCircle(
        centre,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = trackColor.withValues(alpha: 0.38),
      );

      if (ring.max <= 0) continue;
      final fraction = (ring.value / ring.max).clamp(0.0, 1.0) * progress;
      if (fraction <= 0) continue;

      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * fraction,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..color = ring.color,
      );
    }
  }

  @override
  bool shouldRepaint(_MoonArcPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.rings != rings ||
      oldDelegate.scale != scale;
}
