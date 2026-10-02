import 'package:flutter/material.dart';

import '../../../../core/platform/haptics.dart';
import '../../../../core/widgets/app_icons.dart';
import '../night_style.dart';

/// 「长按结束睡眠」：全宽横向胶囊，按住时填充条从左扫到右。
///
/// **为什么不是点击 + 确认弹窗**：结束睡眠是躺下之后才会做的动作，误触代价高，
/// 需要一道闸；而确认弹窗把「停」和「收尾」拆成两个接连的弹窗，按住确认把它压回
/// 一个动作（规格 §四、§16.6）。
///
/// **进度按下即开始**：用 [Listener] 的原始指针事件驱动，不走
/// `GestureDetector.onLongPressStart`——后者要等 500ms 的长按超时才触发，按住之后
/// 要愣一下才动。原始指针事件不进手势竞技场，因此嵌在滚动视图里也不会与滚动手势抢。
///
/// 形态换成原型 `.sleep-hold-button` 的横向胶囊（全宽、min-height 56、圆角 18），
/// 但**按住时长仍是 1.5 秒**——原型是 1.6 秒，那 0.1 秒是本项目 v3.1 的产品裁定，
/// 且已有测试钉住，不为此改动。
///
/// **前提：父级横向约束必须有界**。胶囊靠 `minWidth: double.infinity` 撑满可用宽度，
/// 当前唯一调用点在竖向滚动列表里（宽度有界）。若日后塞进 `Row` 或横向滚动视图，
/// 会遇到无界宽度断言——那种场景要自己套一层 `SizedBox(width:)` 或
/// `ConstrainedBox` 给个有限宽。
class HoldToFinishButton extends StatefulWidget {
  const HoldToFinishButton({
    super.key,
    required this.onFinish,
    this.onHint,
    this.holdDuration = const Duration(milliseconds: 1500),
  });

  /// 填充条扫满之后调一次。
  final VoidCallback onFinish;

  /// 短按（没按满就抬手）时调一次，用来提示「按住不放」。
  final VoidCallback? onHint;

  /// 填充条扫满所需时长。
  final Duration holdDuration;

  @override
  State<HoldToFinishButton> createState() => _HoldToFinishButtonState();
}

class _HoldToFinishButtonState extends State<HoldToFinishButton>
    with SingleTickerProviderStateMixin {
  /// 松手时进度低于这个值就当作「短按」，而不是「按到一半反悔」。
  static const _tapThreshold = 0.2;

  /// 指针离开按下点这么远就作废——躺着翻身蹭到按钮时，滑开就能取消。
  static const _slop = 24.0;

  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: widget.holdDuration,
    // **`preserve` 不能省**：这条时长是承载语义的功能性进度反馈（用户靠它判断
    // 「还要按多久」），不是装饰动效，不属于 Reduce Motion 想抑制的范畴。默认的
    // `AnimationBehavior.normal` 会在系统开启「减弱动态效果」时把时长乘 0.05
    // （`animation_controller.dart`），1.5 秒的误触守卫会塌成 75ms——轻蹭一下就结束，
    // 而且填充条瞬间满格，失效还不可见。`preserve` 正是为「时长本身有意义」的动画准备的。
    animationBehavior: AnimationBehavior.preserve,
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
    // 先复位：评星那一步可以跳过、弹层也可以直接关掉，按钮不该卡在满格。
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
    return Semantics(
      label: '结束睡眠',
      hint: '按住不放，填充条扫满即结束',
      button: true,
      onTap: _hint,
      onLongPress: widget.onFinish,
      child: Listener(
        onPointerDown: _onDown,
        onPointerMove: _onMove,
        onPointerUp: (_) => _onUp(),
        onPointerCancel: (_) {
          // 与 `_onUp` 同款收尾：指针被系统取消（来电、手势被夺走）同样可能发生在
          // 「已按满触发」之后。这里不复位 `_fired` 的话，下一次短按会被当成那次
          // 触发的收尾而吞掉——既不给「按住不放」的提示，填充条也可能停在非零。
          _fired = false;
          _downAt = null;
          _progress.reverse();
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _progress,
              builder: (context, child) => Container(
                constraints: const BoxConstraints(
                  minHeight: NightStyle.holdButtonMinHeight,
                  minWidth: double.infinity,
                ),
                decoration: BoxDecoration(
                  color: NightStyle.glassFill,
                  borderRadius:
                      BorderRadius.circular(NightStyle.holdButtonRadius),
                  border: Border.all(color: NightStyle.glassStroke),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    // `.sleep-hold-fill`：`transform: scaleX(0)` 起、`origin: left`。
                    Positioned.fill(
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: _progress.value,
                        child: const ColoredBox(color: NightStyle.holdFill),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 17),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AppIcons.holdEnd(
                            size: 20,
                            color: NightStyle.holdInk,
                            strokeWidth: 1.65,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            '长按结束睡眠',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: NightStyle.holdInk,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 9),
            const Text(
              '持续按住，避免误触',
              style: TextStyle(fontSize: 10, color: NightStyle.textFaint),
            ),
          ],
        ),
      ),
    );
  }
}
