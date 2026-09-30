import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_tokens.dart';

/// 会话页的日晷圆环。
///
/// 弧表示「已过时长 ÷ 计划时长」：从空画到满，满圈即到设定的起床时间。
/// 超过之后由调用方传入已画满的进度并换掉中间的读数——圆环本身不认识时间，
/// 它只认识一个 0–1 的数，所以它可以被单独测。
///
/// 与 `MoonArc` 一样按几何尺寸而不是 SVG 绘制；这里只有一条弧，因此单独一个
/// widget 比给 `MoonArc` 加参数更清楚。
class WakeDial extends StatelessWidget {
  const WakeDial({
    super.key,
    required this.progress,
    required this.label,
    this.sublabel,
    this.size = 196,
    this.color,
    this.semanticLabel,
  });

  /// 0–1。调用方负责 clamp——这里再 clamp 一次只是防御。
  final double progress;

  /// 中心的读数，例如 `3h 42m`。
  final String label;

  /// 读数下面那行小字，例如 `已入睡` 或 `已超过起床时间 42m`。
  final String? sublabel;

  final double size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final arcColor = color ?? tokens.accent;
    final stroke = size * 0.072; // 196 上是 14

    return Semantics(
      label: semanticLabel ?? label,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: Size.square(size),
              painter: _DialPainter(
                progress: progress.clamp(0.0, 1.0),
                color: arcColor,
                trackColor: tokens.bgMuted,
                stroke: stroke,
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 字体族与 tabular figures 的口径走项目里那一个 helper，不自己拼
                // `FontFeature`——设计令牌只有一份。
                Text(
                  label,
                  style: AppTheme.num(
                    context,
                    size: size * 0.21,
                    weight: FontWeight.w700,
                    letterSpacing: -size * 0.007,
                  ),
                ),
                if (sublabel != null) ...[
                  SizedBox(height: size * 0.03),
                  Text(
                    sublabel!,
                    style: TextStyle(
                      fontSize: size * 0.052,
                      color: tokens.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  const _DialPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
    required this.stroke,
  });

  final double progress;
  final Color color;
  final Color trackColor;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - stroke) / 2;
    final rect = Rect.fromCircle(center: centre, radius: radius);

    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = trackColor,
    );

    if (progress <= 0) return;

    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_DialPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.stroke != stroke;
}
