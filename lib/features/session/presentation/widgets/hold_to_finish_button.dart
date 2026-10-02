import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/platform/haptics.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/widgets/glass_surface.dart';

/// 「结束睡眠」：按住不放，外圈进度环扫满才生效。
///
/// **为什么不是点击 + 确认弹窗**：结束睡眠是躺下之后才会做的动作，误触代价高，
/// 需要一道闸；但确认弹窗把「停」和「收尾」拆成两个接连的弹窗，而按住确认把它
/// 压回一个动作（规格 §四「结束：按住 1.5 秒」）。
///
/// **进度按下即开始**：用 [Listener] 的原始指针事件驱动，不走
/// `GestureDetector.onLongPressStart`——后者要等 500ms 的长按超时才触发，按住
/// 之后要愣一下才动。原始指针事件不进手势竞技场，因此嵌在滚动视图里也不会与
/// 滚动手势抢。
class HoldToFinishButton extends StatefulWidget {
  const HoldToFinishButton({
    super.key,
    required this.onFinish,
    this.onHint,
    this.holdDuration = const Duration(milliseconds: 1500),
    this.size = 104,
  });

  /// 环扫满之后调一次。
  final VoidCallback onFinish;

  /// 短按（没按满就抬手）时调一次，用来提示「按住不放」。
  final VoidCallback? onHint;

  /// 环扫满所需时长。
  final Duration holdDuration;

  /// 含外圈的直径。
  final double size;

  @override
  State<HoldToFinishButton> createState() => _HoldToFinishButtonState();
}

class _HoldToFinishButtonState extends State<HoldToFinishButton>
    with SingleTickerProviderStateMixin {
  static const _stroke = 3.5;
  static const _gap = 6.0;

  /// 松手时进度低于这个值就当作「短按」，而不是「按到一半反悔」。
  static const _tapThreshold = 0.2;

  /// 指针离开按下点这么远就作废——躺着翻身蹭到按钮时，滑开就能取消。
  static const _slop = 24.0;

  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: widget.holdDuration,
  );

  /// 已经触发过结束，等这次抬手收尾——不让它再被当成短按。
  bool _fired = false;

  /// 指针已经滑开，这次按住作废。
  bool _abandoned = false;

  Offset? _downAt;

  @override
  void initState() {
    super.initState();
    _progress.addStatusListener(_onStatus);
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _fired = true;
    // 先复位：评星那一步可以跳过、弹层也可以直接关掉，按钮不该卡在满圈。
    _progress.value = 0;
    // 动画状态回调跑在 transient 回调阶段，push 路由挪到帧尾更稳。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onFinish();
    });
  }

  void _onDown(PointerDownEvent event) {
    _abandoned = false;
    _downAt = event.position;
    _progress.forward();
  }

  void _onMove(PointerMoveEvent event) {
    final downAt = _downAt;
    if (_abandoned || downAt == null) return;
    if ((event.position - downAt).distance <= _slop) return;
    _abandoned = true;
    _progress.reverse();
  }

  void _onUp() {
    _downAt = null;
    if (_fired) {
      _fired = false;
      return;
    }
    if (_abandoned) return;
    if (_progress.value < _tapThreshold) _hint();
    _progress.reverse();
  }

  void _hint() {
    AppHaptics.tap();
    widget.onHint?.call();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final inner = widget.size - 2 * (_stroke + _gap);

    return Semantics(
      label: '结束睡眠',
      hint: '按住不放，圆环填满即结束',
      button: true,
      onTap: _hint,
      onLongPress: widget.onFinish,
      child: Listener(
        onPointerDown: _onDown,
        onPointerMove: _onMove,
        onPointerUp: (_) => _onUp(),
        onPointerCancel: (_) {
          _downAt = null;
          _progress.reverse();
        },
        child: AnimatedBuilder(
          animation: _progress,
          builder: (context, child) => SizedBox(
            width: widget.size,
            height: widget.size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: Size.square(widget.size),
                  painter: _HoldRingPainter(
                    progress: _progress.value,
                    color: tokens.danger,
                    trackColor: tokens.bgMuted,
                    stroke: _stroke,
                  ),
                ),
                // 按下时轻微收缩，与全 App 的按压缩放同一口径。
                Transform.scale(
                  scale: 1 - 0.03 * _progress.value,
                  child: child,
                ),
              ],
            ),
          ),
          child: GlassSurface(
            borderRadius: BorderRadius.circular(inner / 2),
            expandWidth: false,
            padding: EdgeInsets.zero,
            borderColor: tokens.danger.withValues(alpha: 0.38),
            child: SizedBox(
              width: inner,
              height: inner,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AppIcons.sun(
                      size: 18, color: tokens.danger, strokeWidth: 1.9),
                  const SizedBox(height: 6),
                  Text(
                    '结束',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: tokens.danger,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 外圈那条进度弧。画法与 `wake_dial.dart` 的 `_DialPainter` 同款：
/// 从 12 点起顺时针，`StrokeCap.round`。
class _HoldRingPainter extends CustomPainter {
  const _HoldRingPainter({
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
      2 * math.pi * progress.clamp(0.0, 1.0),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_HoldRingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.stroke != stroke;
}
