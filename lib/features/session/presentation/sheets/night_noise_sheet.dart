import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/noise_session.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/app_sheet.dart'
    show kPanelDismissFraction, kPanelDismissVelocity;
import '../../../../core/widgets/app_icons.dart';
import '../../../sleep/presentation/widgets/noise_controls.dart';
import '../night_style.dart';

/// 会话页的「白噪音设置」底部弹窗。
///
/// **为什么不用 `AppSheet`**：它的外观绑死在 `AppTokens` 上（浅色面板、
/// `AppRadii.sheet`），给这一页用会得到一块浅色面板浮在夜景上。这里照
/// `confirm_dialog.dart` 的先例用 `showGeneralDialog` 自绘——包括显式补一层
/// `Material`（`showGeneralDialog` 不像 `showDialog` 那样替路由包 `Material`，
/// 缺了它每个 `Text` 都会落到黄色双下划线的错误样式）。
///
/// 宫格 / 音量 / 时长 chip 三块**复用共享组件**：它们从 `AppTokens` 取色，
/// 所以 `pageBuilder` 里显式再包一层 `Theme(AppTheme.dark(), …)`，不抄第二份色值。
Future<void> showNightNoiseSheet(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭白噪音设置',
    barrierColor: NightStyle.scrim,
    transitionDuration: const Duration(milliseconds: 260),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curve = animation.drive(CurveTween(curve: Curves.easeOutCubic));
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(curve),
        child: FadeTransition(opacity: curve, child: child),
      );
    },
    // `showGeneralDialog` 默认 `useRootNavigator: true`，弹窗路由挂在 **root
    // navigator** 下，**继承不到会话页那层 `Theme(AppTheme.dark())`**。浅色应用主题
    // 下，外框仍走 `NightStyle` 是深的，但宫格 / 音量 / 时长 chip 这些共享控件会从
    // 应用主题取到浅色令牌，深浅拼在一张面板上。所以这里显式再包一层深色 Theme。
    pageBuilder: (context, animation, secondaryAnimation) =>
        Theme(data: AppTheme.dark(), child: const _NightNoiseSheetHost()),
  );
}

/// 面板本体 + **下拉关闭**。
///
/// 判据与另外两处**同一份**（[kPanelDismissVelocity] / [kPanelDismissFraction]）：
/// 底部弹层（`app_sheet.dart`）与会话页那条整屏面板都用它，这一处没有自己的阈值。
///
/// 手势挂在门把手上、不挂整面板，也不挂标题行：面板主体是一个滚动视图，整面板级的
/// 竖直手势会和它抢（同 `app_sheet.dart` 里 `_SheetHandle` 那条注释）。
class _NightNoiseSheetHost extends StatefulWidget {
  const _NightNoiseSheetHost();

  @override
  State<_NightNoiseSheetHost> createState() => _NightNoiseSheetHostState();
}

class _NightNoiseSheetHostState extends State<_NightNoiseSheetHost>
    with SingleTickerProviderStateMixin {
  /// 跟手位移（逻辑像素，正数向下）。
  ///
  /// **`unbounded`**：它不驱动动画进度，只被当「当前位移」读写——下拉时直接赋值，
  /// 松手回弹时 `animateTo(0)`（与 `app_sheet.dart` 的宿主同款）。
  late final AnimationController _drag =
      AnimationController.unbounded(vsync: this, value: 0);

  /// 面板高度，拉过它的 [kPanelDismissFraction] 就关。
  ///
  /// 取的是这一层的**可用**高度（与 `app_sheet.dart` 同一手法）：面板自身封顶在屏幕的
  /// 88%，所以这条线比真实面板高度略高一点——宁可多拉一点再关，也不要一碰就走。
  double _availableHeight = 0;

  @override
  void dispose() {
    _drag.dispose();
    super.dispose();
  }

  void _onDragUpdate(double dy) {
    _drag.stop();
    _drag.value = (_drag.value + dy).clamp(0.0, double.infinity);
  }

  void _onDragEnd(double velocity) {
    final flung = velocity > kPanelDismissVelocity;
    final pulled = _availableHeight > 0 &&
        _drag.value > _availableHeight * kPanelDismissFraction;
    if (flung || pulled) {
      Navigator.of(context).pop();
      return;
    }
    _settle();
  }

  /// 手势被抢走时按「松手」处理：不处理的话面板会停在拉到的位置，而手指早已松开。
  void _onDragCancel() => _settle();

  /// 回弹**带动画**：4px 的横杠被拉下去两百像素再瞬间弹回原位，看起来像掉帧。
  void _settle() {
    if (!mounted) return;
    _drag.animateTo(
      0,
      duration: AppDurations.standard,
      curve: AppMotion.standardCurve,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: AnimatedBuilder(
            animation: _drag,
            // **必须带 `child:`**：不带的话每一帧都会重建整块面板（宫格、音量条、
            // 圆角与投影全在里面）。
            builder: (context, child) => Transform.translate(
              offset: Offset(0, _drag.value),
              child: child,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                _availableHeight = constraints.maxHeight;
                return ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 620,
                    maxHeight: constraints.maxHeight * .88,
                  ),
                  child: _NightNoiseSheet(
                    onHandleDragUpdate: _onDragUpdate,
                    onHandleDragEnd: _onDragEnd,
                    onHandleDragCancel: _onDragCancel,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _NightNoiseSheet extends ConsumerWidget {
  const _NightNoiseSheet({
    required this.onHandleDragUpdate,
    required this.onHandleDragEnd,
    required this.onHandleDragCancel,
  });

  final ValueChanged<double> onHandleDragUpdate;
  final ValueChanged<double> onHandleDragEnd;
  final VoidCallback onHandleDragCancel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTokens.of(context);
    final noise = ref.watch(noiseSessionControllerProvider);
    final remaining = noise.remainingLabel;
    final failure = noise.failure;

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment(-0.34, -1),
          end: Alignment(0.34, 1),
          colors: [NightStyle.sheetFillTop, NightStyle.sheetFillBottom],
        ),
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(NightStyle.sheetRadius),
        ),
        border: Border(
          top: BorderSide(color: NightStyle.sheetStroke),
          left: BorderSide(color: NightStyle.sheetStroke),
          right: BorderSide(color: NightStyle.sheetStroke),
        ),
        boxShadow: [
          BoxShadow(
            color: NightStyle.sheetShadow,
            blurRadius: 70,
            offset: Offset(0, -22),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // `.sleep-sheet-handle`：4px 的横杠，命中区有 28px 高，
            // **下拉关闭的手势就挂在这里**。
            //
            // **它在滚动视图之外**（与 `app_sheet.dart` 同一结构）：门把手若落在
            // `SingleChildScrollView` 里，竖直手势会被那个滚动视图赢走，面板根本
            // 不动——测出来的现象是「拖了没反应」。顺带它也就常驻在顶边不随内容滚。
            _NightSheetHandle(
              onDragUpdate: onHandleDragUpdate,
              onDragEnd: onHandleDragEnd,
              onDragCancel: onHandleDragCancel,
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                    20, 0, 20, MediaQuery.paddingOf(context).bottom + 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '睡前声音',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1,
                                  color: NightStyle.textFaint,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                '白噪音设置',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.8,
                                  color: NightStyle.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('完成'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // ── 三列网格：关闭 + 五种声音（正好两行） ────────────────
                    GridView(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        mainAxisExtent: 64,
                      ),
                      children: [
                        _NightNoiseTile(
                          label: '关闭',
                          icon: AppIcons.soundOff(
                              size: 21,
                              color: _tileInk(noise.activeId == null)),
                          selected: noise.activeId == null,
                          onTap: noise.stop,
                        ),
                        for (final option in kNoiseOptions)
                          _NightNoiseTile(
                            label: option.label,
                            icon: option.icon(
                                21, _tileInk(noise.activeId == option.id)),
                            selected: noise.activeId == option.id,
                            onTap: () => noise.select(option),
                          ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // ── 音量 ────────────────────────────────────────────────
                    _NightBlock(
                      title: '音量',
                      trailing: '${(noise.volume * 100).round()}%',
                      icon: AppIcons.volume(
                          size: 16,
                          color: NightStyle.textHeading,
                          strokeWidth: 1.5),
                      child: VolumeSlider(
                        value: noise.volume,
                        color: noise.activeOption?.color ?? tokens.accent,
                        onChanged: noise.changeVolume,
                      ),
                    ),

                    const SizedBox(height: 12),

                    // ── 播放时长 ────────────────────────────────────────────
                    _NightBlock(
                      title: '播放时长',
                      icon: AppIcons.timer(
                          size: 16,
                          color: NightStyle.textHeading,
                          strokeWidth: 1.5),
                      trailing: remaining == null ? null : '剩余 $remaining',
                      child: Row(
                        children: [
                          for (final minutes
                              in NoiseSessionController.timerChoices) ...[
                            Expanded(
                              // `Expanded` 给的是**紧**宽度约束，而 `TimerChip` 是个
                              // 按内容收窄的 `Container`：不套一层 `Center` 的话，
                              // chip 会被拉到整格宽、文字却仍靠左，看起来像个破了的按钮。
                              child: Center(
                                child: TimerChip(
                                  label: '${minutes}m',
                                  selected: noise.timerMinutes == minutes,
                                  onTap: () => noise.selectTimer(minutes),
                                ),
                              ),
                            ),
                            if (minutes !=
                                NoiseSessionController.timerChoices.last)
                              const SizedBox(width: 6),
                          ],
                        ],
                      ),
                    ),

                    if (failure != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        failure,
                        // 「出错了」是语义色，走 `AppTokens.danger`，不另立一个字面量。
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.45,
                          color: tokens.danger,
                        ),
                      ),
                    ],

                    const SizedBox(height: 10),
                    // 会话里的白噪音不归弹窗播放，生命周期比它长——两句话都要在。
                    const Text(
                      '点选声音可试听，开始睡眠后会按当前设置播放。',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 10, color: NightStyle.textFaint),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '退到后台或锁屏后声音会停（后台播放未接入）。',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 10, color: NightStyle.textFaint),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 音效格选中态（`.sleep-full-noise-grid button.is-selected`）的文字与图标色。
///
/// 提成顶层函数，是因为面板本体（图标）与格子小件（文字）都要用同一份映射——
/// 各自内联一遍，选中态一旦调色就会漏掉其中一处。
Color _tileInk(bool selected) =>
    selected ? NightStyle.selectedInk : NightStyle.textMuted;

/// `.sleep-sheet-handle` 那条 4px 横杠，**外加下拉关闭的手势**。
///
/// 命中区 28px 高（与 `app_sheet.dart` 的门把手同高）：4px 高的横杠自己接不住手指。
/// 点它＝关闭，与那个门把手同一套语义——这一页没有未保存的草稿（选中的声音立刻
/// 生效），所以误触的代价只是面板收起来。
class _NightSheetHandle extends StatelessWidget {
  const _NightSheetHandle({
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onDragCancel,
  });

  final ValueChanged<double> onDragUpdate;
  final ValueChanged<double> onDragEnd;
  final VoidCallback onDragCancel;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).pop(),
      onVerticalDragUpdate: (details) => onDragUpdate(details.delta.dy),
      onVerticalDragEnd: (details) => onDragEnd(details.primaryVelocity ?? 0),
      onVerticalDragCancel: onDragCancel,
      child: SizedBox(
        height: 28,
        child: Center(
          child: Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: NightStyle.handle,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
      ),
    );
  }
}

/// 弹窗里的一格声音。
class _NightNoiseTile extends StatelessWidget {
  const _NightNoiseTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Widget icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Semantics(
        selected: selected,
        button: true,
        label: label,
        child: Container(
          decoration: BoxDecoration(
            color: selected
                ? NightStyle.noiseTileFill
                : NightStyle.noiseTileIdleFill,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: selected
                  ? NightStyle.noiseTileStroke
                  : NightStyle.noiseTileIdleStroke,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              icon,
              const SizedBox(height: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: _tileInk(selected),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `.sleep-setting-block`：标题行 + 内容。
class _NightBlock extends StatelessWidget {
  const _NightBlock({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget icon;
  final Widget child;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NightStyle.fieldFill,
        borderRadius: BorderRadius.circular(18),
        // 与音效格的描边同值，但那是 `.sleep-full-noise-grid button` 的另一条规则。
        border: Border.all(color: NightStyle.sheetFieldStroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              icon,
              const SizedBox(width: 7),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: NightStyle.textHeading,
                ),
              ),
              if (trailing != null) ...[
                const Spacer(),
                Text(
                  trailing!,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: NightStyle.fieldValueInk,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}
