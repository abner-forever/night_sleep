import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_basics.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/glass_surface.dart';
import '../../../core/widgets/ios_controls.dart';
import '../../../core/widgets/subpage.dart';
import '../../sleep/data/sleep_repository.dart';
import '../../sleep/domain/sleep_entry.dart';
import '../../sleep/domain/sleep_history.dart';
import '../../sleep/domain/sleep_math.dart';
import '../../sleep/presentation/sheets/detail_sheet.dart';

/// 全部睡眠数据：把库里每一条记录按时段翻阅一遍。
///
/// 与统计页分工不同——统计页算趋势（最近 7 / 14 / 30 条的平均、评分与汇总），
/// 这一页只**列全部**：按周 / 按月 / 按年分组，每组给出条数与平均，点一行开详情。
///
/// 分组口径在 [SleepHistory] 里（纯函数）：按每条记录**醒来所在的本地日历日**归组，
/// 与统计页同一条口径。这一页自己不做任何口径判断，也不再画一套图表——两处图表
/// 迟早会各自漂移。
class AllSleepDataPage extends ConsumerStatefulWidget {
  const AllSleepDataPage({super.key});

  @override
  ConsumerState<AllSleepDataPage> createState() => _AllSleepDataPageState();
}

class _AllSleepDataPageState extends ConsumerState<AllSleepDataPage> {
  /// 默认按月：一天一条的睡眠记录，一月一组是最好读的密度。
  HistoryGrouping _grouping = HistoryGrouping.month;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final entries = ref.watch(sleepEntriesProvider);

    // 数据还没读到时不要下结论：空状态那句「还没有睡眠记录」是**结论**。
    return entries.when(
      loading: () => _shell(const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(child: CircularProgressIndicator()),
        ),
      ]),
      error: (error, stack) => _shell([
        EmptyState(
          icon: AppIcons.chart(size: 30, color: tokens.danger),
          title: '无法读取记录',
          body: '本地数据库打开失败：$error',
        ),
      ]),
      data: (records) => _content(context, records),
    );
  }

  /// 加载 / 出错 / 有数据三态共用同一副外壳与标题。
  Widget _shell(List<Widget> children) => Subpage(
        backLabel: '统计',
        title: '全部睡眠数据',
        children: children,
      );

  Widget _content(BuildContext context, List<SleepEntry> records) {
    final tokens = AppTokens.of(context);
    final history = SleepHistory.from(allEntries: records, grouping: _grouping);

    if (history.isEmpty) {
      return _shell([
        EmptyState(
          icon: AppIcons.moon(size: 30, color: tokens.accent, strokeWidth: 1.6),
          title: '还没有睡眠记录',
          body: '记录第一晚之后，这里会按周、按月、按年列出全部记录，'
              '每一段给出条数与平均时长。',
        ),
      ]);
    }

    return _shell(
      [
        _SummaryCard(
          history: history,
          demoCount:
              records.where((e) => e.source == AppConfig.demoSource).length,
        ),
        const SizedBox(height: 18),
        Align(
          alignment: Alignment.centerLeft,
          child: SegmentedControl<HistoryGrouping>(
            segments: [
              for (final grouping in HistoryGrouping.values)
                SegmentOption(value: grouping, label: grouping.label),
            ],
            selected: _grouping,
            onChanged: (grouping) => setState(() => _grouping = grouping),
          ),
        ),
        const SizedBox(height: 20),
        for (final group in history.groups) ...[
          _GroupHeader(group: group),
          const SizedBox(height: 8),
          IosListGroup(
            children: [
              for (final entry in group.entries)
                IosListItem(
                  // 开详情弹层：编辑与删除走它既有的两条路径，这一页不新增写路径。
                  onTap: () => showSleepDetailSheet(context, entry),
                  child: _RecordRow(entry: entry),
                ),
            ],
          ),
          const SizedBox(height: 20),
        ],
        Text(
          '分组按每晚醒来所在的那一天算，跨午夜的记录因此只属于一天。'
          '平均时长只按有记录的夜晚计算，漏记的日子不会把平均拉低。'
          '评分可能来自模型，也可能是本地规则估算——点开某一晚能看到这一晚是哪一种。',
          style: TextStyle(fontSize: 12, height: 1.5, color: tokens.textMuted),
        ),
      ],
    );
  }
}

/// 全库汇总：条数、平均时长、平均评分与覆盖范围。
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.history, required this.demoCount});

  final SleepHistory history;

  /// 库里有多少条演示记录。大于 0 时在卡片里如实写一句。
  final int demoCount;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final averageScore = history.averageScore;

    return GlassSurface(
      borderRadius: BorderRadius.circular(AppRadii.card),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '全部记录',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.96,
              color: tokens.textMuted,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _Stat(label: '记录', value: '${history.count}'),
              _Stat(
                label: '平均时长',
                value: '${history.averageHours!.toStringAsFixed(1)}h',
              ),
              // 一条都没评分时如实写「未评分」，不摆一个 0 或空位。
              _Stat(
                label: '平均评分',
                value: averageScore?.toString() ?? '未评分',
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            history.coverageLabel!,
            style:
                TextStyle(fontSize: 12, height: 1.5, color: tokens.textMuted),
          ),
          // 演示记录照列（与统计页同口径），但**要说出来**：上面那三个数字把合成的
          // 与真实的混在一起，而首页对同一个库也挂着横幅。只有调试构建里才有它。
          if (demoCount > 0) ...[
            const SizedBox(height: 6),
            Text(
              '其中 $demoCount 条是演示数据，不是你的记录',
              style:
                  TextStyle(fontSize: 12, height: 1.5, color: tokens.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: tokens.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 12, color: tokens.textMuted)),
        ],
      ),
    );
  }
}

/// 一段时间的抬头：组标签 + 这一段的条数与平均。
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.group});

  final SleepHistoryGroup group;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final score = group.averageScore;

    return Row(
      children: [
        Expanded(
          child: Text(
            group.label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: tokens.textPrimary,
            ),
          ),
        ),
        Text(
          // 组内一条评分都没有时，整段不写评分——不显示一个并不存在的平均。
          '${group.count} 晚 · 平均 ${group.averageHours.toStringAsFixed(1)}h'
          '${score == null ? '' : ' · 评分 $score'}',
          style: TextStyle(
            fontSize: 12,
            color: tokens.textMuted,
            fontFeatures: AppTheme.tabular,
          ),
        ),
      ],
    );
  }
}

/// 一条记录：日期与周几、起止时刻，右侧时长与评分。
class _RecordRow extends StatelessWidget {
  const _RecordRow({required this.entry});

  final SleepEntry entry;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final hours = entry.durationHours.floor();
    final minutes = ((entry.durationHours - hours) * 60).round();
    final score = entry.score;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${formatDate(entry.wakeLocal)} ${formatWeekday(entry.wakeLocal)}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: tokens.textPrimary,
                  fontFeatures: AppTheme.tabular,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${entry.bedtimeLabel} → ${entry.wakeLabel}',
                style: TextStyle(
                  fontSize: 12,
                  color: tokens.textMuted,
                  fontFeatures: AppTheme.tabular,
                ),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${hours}h ${minutes}m',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: tokens.accent,
                fontFeatures: AppTheme.tabular,
              ),
            ),
            // 未评分的记录不写这一行，也不写占位符。
            //
            // **估算与模型给的分数不是一回事**，措辞跟着首页走（`HomePage` 同一句
            // `isEstimated ? '估算' : '评分'`）：本地规则按质量与时长算出来的分数
            // 不该顶着「评分」两个字出场，详情弹层里也是分开标的。
            if (score != null) ...[
              const SizedBox(height: 2),
              Text(
                '${entry.isEstimated ? '估算' : '评分'} $score',
                style: TextStyle(
                  fontSize: 12,
                  color: tokens.textMuted,
                  fontFeatures: AppTheme.tabular,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(width: 8),
        AppIcons.chevronRight(
          size: 14,
          color: tokens.textMuted,
          strokeWidth: 2,
        ),
      ],
    );
  }
}
