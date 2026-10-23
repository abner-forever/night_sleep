import 'package:flutter/material.dart';

import '../../../../core/platform/haptics.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/app_basics.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../domain/sleep_quality.dart';

/// 五档感受选择：保留原有档位、文案和即时反馈；未评分时不预选。
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
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
                      onTap: () {
                        AppHaptics.select();
                        onChanged(quality);
                      },
                      child: AnimatedContainer(
                        duration: AppDurations.control,
                        curve: AppMotion.standardCurve,
                        constraints: const BoxConstraints(minHeight: 76),
                        padding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 2),
                        decoration: BoxDecoration(
                          color: quality == value
                              ? tokens.accentSoft
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            AppIcons.star(
                              size: 23,
                              color:
                                  value != null && quality.value <= value!.value
                                      ? tokens.accent
                                      : tokens.textMuted,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              quality.label,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: quality == value
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: quality == value
                                    ? tokens.accent
                                    : tokens.textMuted,
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
        ),
        if (value != null)
          Padding(
            padding: const EdgeInsets.only(top: 8, right: 4),
            child: Text(value!.feedback,
                style: TextStyle(fontSize: 12, color: tokens.accent)),
          ),
      ],
    );
  }
}
