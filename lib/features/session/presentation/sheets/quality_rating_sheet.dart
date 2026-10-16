import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/app_basics.dart';
import '../../../../core/widgets/app_sheet.dart';
import '../../../sleep/domain/sleep_quality.dart';
import '../../../sleep/presentation/widgets/quality_rating.dart';

/// 结束睡眠时就地问一次「昨晚睡得怎么样？」。
///
/// 返回用户选中的质量，**跳过或关掉蒙层都返回 `null`**——两者对调用方是同一件事：
/// 这次没有评分。绝不替用户填一个中间值。
///
/// 为什么问在结束这一步：刚醒那一刻主观感受最清楚，隔几小时再回来看就只剩一个
/// 模糊印象了。
Future<SleepQuality?> showQualityRatingSheet(BuildContext context) {
  return showAppSheet<SleepQuality>(
    context: context,
    builder: (context) => const _QualityRatingSheet(),
  );
}

class _QualityRatingSheet extends StatefulWidget {
  const _QualityRatingSheet();

  @override
  State<_QualityRatingSheet> createState() => _QualityRatingSheetState();
}

class _QualityRatingSheetState extends State<_QualityRatingSheet> {
  /// 初始无选中——用户没点过的档位不该是亮的。
  SleepQuality? _choice;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    return AppSheet(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Column(
              children: [
                Text(
                  '昨晚睡得怎么样？',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: tokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '现在评一下最准。不想评就跳过，之后在「回顾」里还能补。',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: tokens.textMuted),
                ),
                const SizedBox(height: 20),
                QualityChoice(
                  value: _choice,
                  onChanged: (quality) => setState(() => _choice = quality),
                ),
                const SizedBox(height: 22),
                PrimaryAction(
                  label: '保存',
                  onTap: () => Navigator.of(context).pop(_choice),
                ),
                const SizedBox(height: 10),
                Pressable(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      '跳过',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: tokens.textMuted,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }
}
