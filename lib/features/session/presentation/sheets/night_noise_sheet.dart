import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/noise_session.dart';
import '../../../../core/theme/app_tokens.dart';
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
/// 宫格 / 音量 / 时长 chip 三块**复用共享组件**：调用方把整页包在
/// `Theme(AppTheme.dark())` 里，它们照常从 `AppTokens` 取深色值，不抄第二份。
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
    pageBuilder: (context, animation, secondaryAnimation) =>
        const _NightNoiseSheet(),
  );
}

class _NightNoiseSheet extends ConsumerWidget {
  const _NightNoiseSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTokens.of(context);
    final noise = ref.watch(noiseSessionControllerProvider);
    final remaining = noise.remainingLabel;
    final failure = noise.failure;

    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 620,
          maxHeight: MediaQuery.sizeOf(context).height * .88,
        ),
        child: DecoratedBox(
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
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                  20, 10, 20, MediaQuery.paddingOf(context).bottom + 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // `.sleep-sheet-handle`
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: NightStyle.handle,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
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

                  // ── 九宫格：关闭 + 八种声音 ────────────────────────────
                  GridView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 9,
                      crossAxisSpacing: 9,
                      mainAxisExtent: 72,
                    ),
                    children: [
                      _NightNoiseTile(
                        label: '关闭',
                        icon: AppIcons.soundOff(
                            size: 21, color: _tileInk(noise.activeId == null)),
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

                  const SizedBox(height: 14),

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

                  const SizedBox(height: 14),

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

                  const SizedBox(height: 13),
                  // 会话里的白噪音不归弹窗播放，生命周期比它长——两句话都要在。
                  const Text(
                    '点选声音可试听，开始睡眠后会按当前设置播放。',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 10, color: NightStyle.textFaint),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '退到后台或锁屏后声音会停（后台播放未接入）。',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 10, color: NightStyle.textFaint),
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

/// 音效格选中态（`.sleep-full-noise-grid button.is-selected`）的文字与图标色。
///
/// 提成顶层函数，是因为面板本体（图标）与格子小件（文字）都要用同一份映射——
/// 各自内联一遍，选中态一旦调色就会漏掉其中一处。
Color _tileInk(bool selected) =>
    selected ? NightStyle.selectedInk : NightStyle.textMuted;

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
              const SizedBox(height: 7),
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
      padding: const EdgeInsets.all(15),
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
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
