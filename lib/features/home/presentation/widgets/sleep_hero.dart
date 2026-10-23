import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/app_basics.dart';
import '../../../sleep/domain/sleep_entry.dart';
import '../../../sleep/presentation/sheets/detail_sheet.dart';
import '../../../sleep/presentation/widgets/score_ring.dart';
import '../../../sleep/presentation/widgets/sleep_summary.dart';

class SleepHeroCard extends StatelessWidget {
  const SleepHeroCard({
    super.key,
    required this.entry,
    required this.animateRing,
    this.wide = false,
  });

  final SleepEntry entry;
  final bool animateRing;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final outerTokens = AppTokens.of(context);
    final tokens = wide ? outerTokens : AppTokens.dark;
    return Theme(
      data: Theme.of(context).copyWith(extensions: [tokens]),
      child: Builder(builder: (context) {
        return Pressable(
          onTap: () => showSleepDetailSheet(context, entry),
          semanticLabel: '查看昨夜睡眠详情',
          child: Container(
            constraints: const BoxConstraints(minHeight: 157),
            padding: EdgeInsets.all(wide ? 25 : 17),
            decoration: BoxDecoration(
              color: wide ? tokens.bgCard : null,
              gradient: wide
                  ? null
                  : const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF173358), Color(0xFF0D1C3A)],
                    ),
              borderRadius: wide
                  ? const BorderRadius.vertical(top: Radius.circular(19))
                  : BorderRadius.circular(20),
              border: wide ? Border.all(color: tokens.border) : null,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('昨夜睡眠',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: tokens.textSecondary,
                          )),
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 9,
                        runSpacing: 7,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SleepDuration(
                              hours: entry.durationHours, size: wide ? 39 : 38),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: tokens.good.withValues(alpha: .15),
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: Text(
                                entry.durationHours >= 7 ? '睡眠良好' : '需要多休息',
                                style: TextStyle(
                                    fontSize: 10, color: tokens.good)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 13),
                      SleepTimes(entry: entry),
                      const SizedBox(height: 7),
                      Text(
                          entry.hasSoundEvents
                              ? '${entry.soundClips.length}条声音'
                              : '无声音片段',
                          style:
                              TextStyle(fontSize: 10, color: tokens.textMuted)),
                    ],
                  ),
                ),
                if (entry.score != null) ...[
                  const SizedBox(width: 14),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: animateRing ? 0 : 1, end: 1),
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 850),
                    builder: (context, value, child) => Opacity(
                      opacity: value,
                      child: ScoreRing(
                        score: entry.score!,
                        size: 97,
                        prominent: true,
                        estimated: entry.isEstimated,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      }),
    );
  }
}
