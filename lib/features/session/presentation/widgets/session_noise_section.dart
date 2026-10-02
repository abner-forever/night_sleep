import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/noise_session.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/app_basics.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/widgets/ios_controls.dart';
import '../../../sleep/presentation/widgets/noise_controls.dart';

/// 会话页展开区里的白噪音设定：八宫格 + 音量 + 定时，外加后台播放的如实标注。
///
/// 白噪音**不归它播放**：播放器与倒计时挂在 [noiseSessionControllerProvider] 上，
/// 生命周期比这一页长——收起展开区不会静音（使用方裁定，见 [NoiseSessionController]）。
class SessionNoiseSection extends ConsumerWidget {
  const SessionNoiseSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTokens.of(context);
    final noise = ref.watch(noiseSessionControllerProvider);
    final remaining = noise.remainingLabel;
    final failure = noise.failure;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('助眠音效'),
        IosListGroup(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final option in kNoiseOptions)
                        NoiseTile(
                          option: option,
                          active: option.id == noise.activeId,
                          onTap: () => noise.select(option),
                          // 四列：(宽度 - 三个间隔) / 4。
                          width: (MediaQuery.sizeOf(context).width - 110) / 4,
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  VolumeSlider(
                    value: noise.volume,
                    color: noise.activeOption?.color ?? tokens.accent,
                    onChanged: noise.changeVolume,
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      AppIcons.timer(
                          size: 14, color: tokens.textMuted, strokeWidth: 1.8),
                      const SizedBox(width: 6),
                      Text(
                        '定时关闭',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.96,
                          color: tokens.textMuted,
                        ),
                      ),
                      if (remaining != null) ...[
                        const Spacer(),
                        Text(
                          '剩余 $remaining',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: tokens.accent,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final minutes in NoiseSessionController.timerChoices)
                        TimerChip(
                          label: '${minutes}m',
                          selected: noise.timerMinutes == minutes,
                          onTap: () => noise.selectTimer(minutes),
                        ),
                    ],
                  ),
                  if (failure != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      failure,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.45,
                        color: tokens.danger,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const SectionHeader('说明'),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: tokens.bgMuted,
            borderRadius: BorderRadius.circular(AppRadii.panel),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppIcons.volume(
                  size: 15, color: tokens.textMuted, strokeWidth: 1.6),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '退到后台或锁屏后声音会停（后台播放未接入）。',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: tokens.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
