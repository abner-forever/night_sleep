import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_basics.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../sleep/domain/sleep_entry.dart';
import '../../sleep/domain/sleep_math.dart';

/// 打开「换一晚回顾」的选择弹层，返回用户选中的那一晚；取消或下滑返回 `null`。
///
/// [entries] 只包含**真实**记录：演示行不在这里出现。演示记录一旦被改写就不再
/// 匹配「清除演示数据」，且它的阶段与窗口会互相矛盾，所以回顾页根本不提供入口。
Future<SleepEntry?> showReviewNightPicker(
  BuildContext context, {
  required List<SleepEntry> entries,
  required String currentId,
}) {
  return showAppSheet<SleepEntry>(
    context: context,
    builder: (context) => ReviewNightPicker(
      entries: entries,
      currentId: currentId,
    ),
  );
}

/// 选择要回顾的那一晚。
class ReviewNightPicker extends StatelessWidget {
  const ReviewNightPicker({
    super.key,
    required this.entries,
    required this.currentId,
  });

  final List<SleepEntry> entries;
  final String currentId;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    return AppSheet(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '换一晚回顾',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: tokens.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '只列出你自己的记录，演示数据不在其中。',
              style: TextStyle(fontSize: 13, color: tokens.textMuted),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: entries.length,
                separatorBuilder: (context, index) => const SizedBox(height: 4),
                itemBuilder: (context, index) => _NightRow(
                  entry: entries[index],
                  current: entries[index].id == currentId,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NightRow extends StatelessWidget {
  const _NightRow({required this.entry, required this.current});

  final SleepEntry entry;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final hours = entry.durationHours.floor();
    final minutes = ((entry.durationHours - hours) * 60).round();

    return Pressable(
      onTap: () => Navigator.of(context).pop(entry),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: current ? tokens.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadii.panel),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    formatDate(entry.wakeLocal),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: tokens.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${entry.bedtimeLabel} → ${entry.wakeLabel} · ${hours}h ${minutes}m',
                    style: TextStyle(fontSize: 12, color: tokens.textMuted),
                  ),
                ],
              ),
            ),
            if (current)
              AppIcons.check(size: 16, color: tokens.accent, strokeWidth: 2.5),
          ],
        ),
      ),
    );
  }
}
