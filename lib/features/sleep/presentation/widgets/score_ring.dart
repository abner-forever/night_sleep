import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_tokens.dart';
import 'stage_style.dart';

/// `AIRing` — a 50px circular gauge showing a 0–100 score.
class ScoreRing extends StatelessWidget {
  const ScoreRing(
      {super.key,
      required this.score,
      this.size = 50,
      this.prominent = false,
      this.estimated = false});

  final int score;
  final double size;
  final bool prominent;
  final bool estimated;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final color = scoreBandColor(tokens, score);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size.square(size),
            painter: _ScoreRingPainter(
              progress: (score / 100).clamp(0.0, 1.0),
              color: color,
              trackColor: prominent
                  ? tokens.textPrimary.withValues(alpha: .14)
                  : tokens.borderStrong,
              gradient: prominent
                  ? LinearGradient(colors: [
                      tokens.stageRem,
                      tokens.stageDeep,
                      tokens.stageLight
                    ])
                  : null,
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$score',
                style: AppTheme.num(
                  context,
                  size: prominent ? 29 : 12,
                  weight: prominent ? FontWeight.w500 : FontWeight.w700,
                  color: prominent ? tokens.textPrimary : color,
                ),
              ),
              if (prominent) ...[
                const SizedBox(height: 3),
                Text(estimated ? '估算评分' : '睡眠评分',
                    style: TextStyle(fontSize: 9, color: tokens.textSecondary)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ScoreRingPainter extends CustomPainter {
  const _ScoreRingPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
    this.gradient,
  });

  final double progress;
  final Color color;
  final Color trackColor;
  final Gradient? gradient;

  @override
  void paint(Canvas canvas, Size size) {
    // The prototype draws a 48-unit viewBox into a 50px box; radii are scaled
    // from the 24-unit centre with r = 20 and a 4-unit stroke.
    final scale = size.width / 48;
    final centre = Offset(size.width / 2, size.height / 2);
    final radius = 20 * scale;
    final strokeWidth = 4 * scale;

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = trackColor;
    canvas.drawCircle(centre, radius, track);

    if (progress <= 0) return;

    final progressPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = color;
    if (gradient != null) {
      progressPaint.shader = gradient!.createShader(Offset.zero & size);
    }

    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(_ScoreRingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.gradient != gradient;
}
