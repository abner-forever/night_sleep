import 'package:flutter/material.dart';

import '../../../../core/platform/haptics.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/app_basics.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../domain/sleep_quality.dart';

/// 五档睡眠质量：彩色圆形星标、未评分时不预选。
class QualityChoice extends StatelessWidget {
  const QualityChoice({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final SleepQuality? value;
  final ValueChanged<SleepQuality> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final quality in SleepQuality.values)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Semantics(
                container: true,
                excludeSemantics: true,
                button: true,
                selected: quality == value,
                label: '睡眠质量 ${quality.label}',
                child: Pressable(
                  haptic: false,
                  onTap: () {
                    AppHaptics.select();
                    onChanged(quality);
                  },
                  child: AnimatedContainer(
                    duration: AppDurations.control,
                    curve: AppMotion.standardCurve,
                    constraints: const BoxConstraints(minHeight: 76),
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      children: [
                        AnimatedContainer(
                          duration: AppDurations.control,
                          width: 38,
                          height: 38,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: quality == value
                                ? Colors.transparent
                                : _qualityColor(tokens, quality)
                                    .withValues(alpha: 0.10),
                            border: Border.all(
                              color: _qualityColor(tokens, quality).withValues(
                                alpha: quality == value ? 1 : 0.22,
                              ),
                            ),
                          ),
                          child: quality == value
                              ? AppIcons.filledStar(
                                  size: 20,
                                  color: _qualityColor(tokens, quality),
                                )
                              : AppIcons.star(
                                  size: 20,
                                  color: _qualityColor(tokens, quality),
                                  strokeWidth: value != null &&
                                          quality.value <= value!.value
                                      ? 2
                                      : 1.5,
                                ),
                        ),
                        const SizedBox(height: 8),
                        AnimatedDefaultTextStyle(
                          duration: AppDurations.control,
                          curve: AppMotion.standardCurve,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: quality == value
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: quality == value
                                ? _qualityColor(tokens, quality)
                                : colorMix(
                                    _qualityColor(tokens, quality),
                                    0.72,
                                    tokens.textSecondary,
                                  ),
                          ),
                          child: Text(
                            quality.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  static Color _qualityColor(AppTokens tokens, SleepQuality quality) {
    return switch (quality) {
      SleepQuality.veryPoor => tokens.danger,
      SleepQuality.poor => tokens.warn,
      SleepQuality.fair => tokens.caution,
      SleepQuality.good => tokens.good,
      SleepQuality.excellent => tokens.accentViolet,
    };
  }
}
