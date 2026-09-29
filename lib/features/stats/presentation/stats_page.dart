import '../../../app/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/haptics.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_basics.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/glass_surface.dart';
import '../../../core/widgets/ios_controls.dart';
import '../../sleep/data/sleep_repository.dart';
import '../../sleep/domain/sleep_entry.dart';
import '../../sleep/domain/sleep_statistics.dart';
import '../../sleep/presentation/sheets/detail_sheet.dart';
import '../../sleep/presentation/widgets/stage_style.dart';

/// Statistics — duration trend, score and sound summary for a chosen window.
class StatsPage extends ConsumerStatefulWidget {
  const StatsPage({super.key});

  @override
  ConsumerState<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends ConsumerState<StatsPage> {
  StatsPeriod _period = StatsPeriod.week;
  SleepEntry? _selected;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final entries = ref.watch(sleepEntriesProvider);

    // 外壳不再兜底留白，状态栏留白由页面自己补（见 [pageTopInset]），
    // 所以加载与错误分支也要和数据分支的 ListView 用同一套顶部与横向留白。
    final inset = EdgeInsets.only(
      top: pageTopInset(context),
      left: pageGutter(context),
      right: pageGutter(context),
    );

    return entries.when(
      loading: () => Padding(
        padding: inset,
        child: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, stack) => Padding(
        padding: inset,
        child: EmptyState(
          icon: AppIcons.chart(size: 30, color: tokens.danger),
          title: '无法读取记录',
          body: '本地数据库打开失败：$error',
        ),
      ),
      data: (records) {
        final stats = SleepStatistics.from(
          allEntries: records,
          period: _period,
        );

        return ListView(
          padding: EdgeInsets.fromLTRB(
            pageGutter(context),
            pageTopInset(context),
            pageGutter(context),
            pageBottomInset(context),
          ),
          children: [
            const PageHeading(eyebrow: '睡眠统计', title: '趋势分析'),
            const SizedBox(height: 18),
            if (stats.isEmpty)
              EmptyState(
                icon: AppIcons.chart(
                    size: 30, color: tokens.accent, strokeWidth: 1.6),
                title: '暂无统计数据',
                body: '记录几晚睡眠后，这里会显示时长趋势、评分与声音分析。',
              )
            else ...[
              Align(
                alignment: Alignment.centerLeft,
                child: SegmentedControl<StatsPeriod>(
                  segments: [
                    for (final period in StatsPeriod.values)
                      SegmentOption(value: period, label: period.label),
                  ],
                  selected: _period,
                  onChanged: (period) => setState(() {
                    _period = period;
                    _selected = null;
                  }),
                ),
              ),
              const SizedBox(height: 18),
              _DurationChartCard(
                stats: stats,
                selected: _selected,
                onSelect: (entry) => setState(() => _selected = entry),
                onOpenDetail: (entry) => showSleepDetailSheet(context, entry),
              ),
              if (stats.averageScore != null) ...[
                const SizedBox(height: 18),
                _ScoreCard(stats: stats),
              ],
              const SizedBox(height: 18),
              _SummaryGrid(stats: stats),
              if (stats.transcripts.isNotEmpty) ...[
                const SizedBox(height: 18),
                _TranscriptCard(stats: stats),
              ],
            ],
          ],
        );
      },
    );
  }
}

/// The daily-duration bar chart with the 7-hour target line.
class _DurationChartCard extends StatelessWidget {
  const _DurationChartCard({
    required this.stats,
    required this.selected,
    required this.onSelect,
    required this.onOpenDetail,
  });

  final SleepStatistics stats;
  final SleepEntry? selected;
  final ValueChanged<SleepEntry> onSelect;
  final ValueChanged<SleepEntry> onOpenDetail;

  static const _chartHeight = 160.0;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final showDayLabels = stats.period.days <= 14;
    final barGap = stats.period.days > 14 ? 3.0 : 8.0;

    return GlassSurface(
      borderRadius: BorderRadius.circular(AppRadii.card),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '每日睡眠时长',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.96,
                        color: tokens.textMuted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '柱高代表时长 · 蓝线为 7 小时目标',
                      style: TextStyle(fontSize: 12, color: tokens.textMuted),
                    ),
                  ],
                ),
              ),
              Text(
                '平均 ${stats.averageHours!.toStringAsFixed(1)}h',
                style: AppTheme.num(
                  context,
                  size: 14,
                  weight: FontWeight.w600,
                  color: tokens.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Y axis: ceiling, the 7h target, and the floor.
              SizedBox(
                width: 30,
                height: _chartHeight,
                child: Stack(
                  children: [
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Text(
                        '${stats.chartCeiling.toStringAsFixed(0)}h',
                        style: AppTheme.num(context,
                            size: 10, color: tokens.textMuted),
                      ),
                    ),
                    Positioned(
                      bottom:
                          _chartHeight * stats.targetHeightPercent / 100 - 6,
                      right: 0,
                      child: Text(
                        '7h',
                        style: AppTheme.num(
                          context,
                          size: 10,
                          color: tokens.accent,
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Text(
                        '${stats.chartFloor.toStringAsFixed(0)}h',
                        style: AppTheme.num(context,
                            size: 10, color: tokens.textMuted),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  children: [
                    SizedBox(
                      height: _chartHeight,
                      child: Stack(
                        children: [
                          // Baseline, target and ceiling rules.
                          for (final fraction in [
                            0.0,
                            stats.targetHeightPercent / 100,
                            1.0,
                          ])
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: _chartHeight * fraction,
                              child: Container(
                                height: 1,
                                color:
                                    fraction == stats.targetHeightPercent / 100
                                        ? tokens.accent.withValues(alpha: 0.72)
                                        : tokens.border.withValues(alpha: 0.55),
                              ),
                            ),
                          Positioned.fill(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                for (final entry in stats.entries) ...[
                                  if (entry != stats.entries.first)
                                    SizedBox(width: barGap),
                                  Expanded(
                                      child: _Bar(
                                    entry: entry,
                                    percent: stats.barPercentFor(entry),
                                    selected: selected?.id == entry.id,
                                    showLabel: showDayLabels ||
                                        selected?.id == entry.id,
                                    onTap: () {
                                      AppHaptics.select();
                                      onSelect(entry);
                                    },
                                  )),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        for (final entry in stats.entries) ...[
                          if (entry != stats.entries.first)
                            SizedBox(width: barGap),
                          Expanded(
                            child: Column(
                              children: [
                                if (showDayLabels)
                                  Text(
                                    entry.dayLabel,
                                    style: AppTheme.num(
                                      context,
                                      size: 10,
                                      color: tokens.textMuted,
                                    ),
                                  ),
                                SizedBox(
                                  height: 12,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      if (entry.hasSnore)
                                        AppIcons.snore(
                                          size: 10,
                                          color: tokens.accentBlue,
                                          strokeWidth: 1.5,
                                        ),
                                      if (entry.hasTalk)
                                        AppIcons.bubble(
                                          size: 10,
                                          color: tokens.accentViolet,
                                          strokeWidth: 1.5,
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(height: 1, color: tokens.border),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  '点按柱状图查看当晚摘要',
                  style: TextStyle(fontSize: 12, color: tokens.textMuted),
                ),
              ),
              if (selected != null)
                Pressable(
                  onTap: () => onOpenDetail(selected!),
                  child: Text(
                    '查看 ${selected!.dateLabel.substring(5)} 详情',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: tokens.accent,
                    ),
                  ),
                )
              else
                Text(
                  '近 ${stats.period.days} 天',
                  style: AppTheme.num(
                    context,
                    size: 14,
                    weight: FontWeight.w600,
                    color: tokens.textSecondary,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.entry,
    required this.percent,
    required this.selected,
    required this.showLabel,
    required this.onTap,
  });

  final SleepEntry entry;
  final double percent;
  final bool selected;
  final bool showLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final color = durationBandColor(tokens, entry.durationHours);

    return Semantics(
      button: true,
      selected: selected,
      label:
          '选择 ${entry.dateLabel}，睡眠 ${entry.durationHours.toStringAsFixed(1)} 小时',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (showLabel)
              Positioned(
                left: -12,
                right: -12,
                bottom: percent / 100 * 160 + 6,
                child: Text(
                  '${entry.durationHours.toStringAsFixed(1)}h',
                  textAlign: TextAlign.center,
                  style: AppTheme.num(
                    context,
                    size: 10,
                    weight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: selected ? color : tokens.textSecondary,
                  ),
                ),
              ),
            Align(
              alignment: Alignment.bottomCenter,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: AppMotion.standardCurve,
                height: (percent / 100 * 160).clamp(6.0, 160.0),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: selected ? 1 : 0.82),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(8)),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: color.withValues(alpha: 0.24),
                            spreadRadius: 3,
                          ),
                        ]
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Average score for the window, with the prototype's disclaimer.
class _ScoreCard extends StatelessWidget {
  const _ScoreCard({required this.stats});

  final SleepStatistics stats;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final average = stats.averageScore!;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: tokens.accentSoft,
        borderRadius: BorderRadius.circular(AppRadii.panel),
        border: Border.all(color: tokens.accent.withValues(alpha: 0.19)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppIcons.ai(size: 15, color: tokens.accent, strokeWidth: 1.8),
              const SizedBox(width: 8),
              Text(
                '本周睡眠评分',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: tokens.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$average',
                style: AppTheme.num(
                  context,
                  size: 52,
                  weight: FontWeight.w700,
                  letterSpacing: -2.08,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '/ 100 · ${stats.period.days}天平均',
                style: TextStyle(fontSize: 14, color: tokens.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            average >= 85
                ? '整体睡眠质量优秀'
                : average >= 70
                    ? '整体睡眠质量良好'
                    : '睡眠质量有待改善',
            style: TextStyle(fontSize: 14, color: tokens.textSecondary),
          ),
          const SizedBox(height: 12),
          Text(
            '评分根据时长、规律性与记录事件生成，仅供睡眠习惯参考，不构成医疗建议。',
            style:
                TextStyle(fontSize: 12, height: 1.45, color: tokens.textMuted),
          ),
        ],
      ),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.stats});

  final SleepStatistics stats;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final cards = [
      (
        '平均时长',
        '${stats.averageHours!.toStringAsFixed(1)}h',
        AppIcons.moon(size: 20, color: tokens.textMuted, strokeWidth: 1.5)
      ),
      (
        '充足天数',
        '${stats.goodNights}/${stats.count}天',
        AppIcons.check(size: 20, color: tokens.textMuted, strokeWidth: 1.5)
      ),
      (
        '打鼾夜数',
        '${stats.snoreNights}次',
        AppIcons.snore(size: 20, color: tokens.textMuted, strokeWidth: 1.5)
      ),
      (
        '梦话夜数',
        '${stats.talkNights}次',
        AppIcons.bubble(size: 20, color: tokens.textMuted, strokeWidth: 1.5)
      ),
    ];

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _SummaryCard(data: cards[0])),
            const SizedBox(width: 12),
            Expanded(child: _SummaryCard(data: cards[1])),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _SummaryCard(data: cards[2])),
            const SizedBox(width: 12),
            Expanded(child: _SummaryCard(data: cards[3])),
          ],
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.data});

  final (String, String, Widget) data;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return GlassSurface(
      borderRadius: BorderRadius.circular(AppRadii.panel),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          data.$3,
          const SizedBox(height: 8),
          Text(
            data.$2,
            style: AppTheme.num(
              context,
              size: 24,
              weight: FontWeight.w700,
              letterSpacing: -0.48,
            ),
          ),
          const SizedBox(height: 2),
          Text(data.$1,
              style: TextStyle(fontSize: 12, color: tokens.textMuted)),
        ],
      ),
    );
  }
}

/// Sleep-talk transcripts collected across the window.
class _TranscriptCard extends StatelessWidget {
  const _TranscriptCard({required this.stats});

  final SleepStatistics stats;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final count = stats.transcripts.length;

    return GlassSurface(
      borderRadius: BorderRadius.circular(AppRadii.panel),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppIcons.bubble(
                  size: 15, color: tokens.accentViolet, strokeWidth: 1.8),
              const SizedBox(width: 8),
              Text(
                '梦话记录',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: tokens.accentViolet,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final transcript in stats.transcripts) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: tokens.bgMuted,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                transcript,
                style: TextStyle(
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                  color: tokens.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 4),
          // Deliberately factual: it counts what was transcribed and describes
          // it, rather than diagnosing anything.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: tokens.accentSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AppIcons.ai(
                        size: 12, color: tokens.accent, strokeWidth: 1.8),
                    const SizedBox(width: 6),
                    Text(
                      '综合分析',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: tokens.accent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${stats.period.days}天内共检测到$count段梦话。转录内容来自夜间录音，'
                  '仅供参考，不构成医疗建议。',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: tokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
