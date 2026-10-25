import '../../../app/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/platform/haptics.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_basics.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/ios_controls.dart';
import '../../../core/widgets/quiet_surface.dart';
import '../../sleep/data/sleep_repository.dart';
import '../../sleep/domain/sleep_entry.dart';
import '../../sleep/domain/sleep_statistics.dart';
import '../../sleep/domain/sound_event.dart';
import '../../sleep/presentation/sheets/detail_sheet.dart';
import '../../sleep/presentation/widgets/sleep_summary.dart';
import '../../sleep/presentation/widgets/stage_style.dart';

/// 统计页柱状图的稳定标识，供无障碍与布局测试定位到具体一晚。
Key statsDurationBarKey(String entryId) =>
    ValueKey<String>('stats-duration-bar-$entryId');

/// 当前选中柱顶的数值徽标。
const Key statsSelectedDurationLabelKey = Key('stats-selected-duration-label');

/// 每日时长柱状图的绘图区。
const Key statsDurationChartKey = Key('stats-duration-chart');

/// 统计页——所选周期内的时长趋势、评分与声音汇总。
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
      bottom: pageBottomInset(context),
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
            // 右上角是「看全部」的入口（v3.31）：这一页只看最近 7 / 14 / 30 条，
            // 想翻更早的记录得有个去处。库里一条记录都没有时不显示它——
            // 那一刻它通向一个只能显示空状态的地方，而下面的空状态已经把话说完了。
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Expanded(
                  child: PageHeading(title: '统计'),
                ),
                if (records.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4, left: 12),
                    child: Pressable(
                      onTap: () => context.push('/stats/all'),
                      semanticLabel: '查看全部数据',
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '全部数据',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: tokens.accent,
                            ),
                          ),
                          const SizedBox(width: 2),
                          AppIcons.chevronRight(
                            size: 14,
                            color: tokens.accent,
                            strokeWidth: 2,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
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
                  expand: true,
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
              const SizedBox(height: 18),
              SleepSummary(
                records: stats.entries,
                periodLabel:
                    _period == StatsPeriod.week ? '本周' : '近 ${_period.days} 天',
              ),
              const SizedBox(height: 18),
              _SoundSummary(stats: stats),
              if (_transcripts(stats).isNotEmpty) ...[
                const SizedBox(height: 18),
                _TranscriptCard(items: _transcripts(stats)),
              ],
            ],
          ],
        );
      },
    );
  }

  static List<({SleepEntry entry, SoundClip clip})> _transcripts(
    SleepStatistics stats,
  ) {
    return [
      for (final entry in stats.entries.reversed)
        for (final clip in entry.soundClips)
          if (clip.kind == SoundEventKind.talk &&
              (clip.transcript?.trim().isNotEmpty ?? false))
            (entry: entry, clip: clip),
    ];
  }
}

/// 每日时长柱状图与 7 小时目标线——这一页的 hero 卡（规格 §2.3「冷净」）。
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

    return QuietSurface(
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
                // 柱位宽度决定柱子下面那行事件图标放不放得下。宽度只能在这里量——
                // 它取决于条数、柱间距与视口宽三者，任何一处写死都会在别的机型上错。
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // 一根柱子分到多宽。两只 10px 的图标加一点余量 = 24px；低于它就
                    // 整行不画（见下面那段注释）。
                    final slot = (constraints.maxWidth -
                            barGap * (stats.entries.length - 1)) /
                        stats.entries.length;
                    final showEventIcons = slot >= 24;
                    final selectedIndex = selected == null
                        ? -1
                        : stats.entries
                            .indexWhere((entry) => entry.id == selected!.id);
                    final selectedEntry =
                        selectedIndex < 0 ? null : stats.entries[selectedIndex];

                    return Column(
                      children: [
                        SizedBox(
                          height: _chartHeight,
                          child: Stack(
                            key: statsDurationChartKey,
                            clipBehavior: Clip.none,
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
                                    color: fraction ==
                                            stats.targetHeightPercent / 100
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
                                        showLabel: showDayLabels &&
                                            selected?.id != entry.id,
                                        onTap: () {
                                          AppHaptics.select();
                                          onSelect(entry);
                                        },
                                      )),
                                    ],
                                  ],
                                ),
                              ),
                              if (selectedEntry != null)
                                _SelectedDurationLabel(
                                  key: statsSelectedDurationLabelKey,
                                  entry: selectedEntry,
                                  percent: stats.barPercentFor(selectedEntry),
                                  index: selectedIndex,
                                  slotWidth: slot,
                                  gap: barGap,
                                  chartWidth: constraints.maxWidth,
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
                                    // **再挤下去这一行就是溢出**（实测：390 宽的屏上 14 天
                                    // 溢出 7.4px，30 天更长）。两只 10px 的图标要塞进
                                    // 12.6px 的柱位，`Row` 只能是「放不下」。
                                    //
                                    // 柱位放不下两只图标时整行不画，而不是缩小或裁一半：
                                    // 裁一半会让人以为那晚只打鼾没说梦话（那是**假读数**），
                                    // 缩到 3px 则谁也看不清。事件计数在下方的「打鼾夜数 /
                                    // 梦话夜数」里一直有，信息没有丢。
                                    if (showEventIcons)
                                      SizedBox(
                                        height: 12,
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
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
                    );
                  },
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
    final selectionOutline = Color.lerp(color, Colors.white, 0.2)!;

    return Semantics(
      key: statsDurationBarKey(entry.id),
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
              child: AnimatedScale(
                scale: selected ? 1.04 : 1,
                alignment: Alignment.bottomCenter,
                duration: AppDurations.control,
                curve: AppMotion.standardCurve,
                child: AnimatedContainer(
                  duration: AppDurations.control,
                  curve: AppMotion.standardCurve,
                  height: (percent / 100 * 160).clamp(6.0, 160.0),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.72),
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(5)),
                    border: selected
                        ? Border.all(
                            color: selectionOutline,
                            width: 1.25,
                          )
                        : null,
                    boxShadow: selected
                        ? [
                            BoxShadow(
                              color: color.withValues(alpha: 0.34),
                              blurRadius: 12,
                              spreadRadius: 1,
                            ),
                            BoxShadow(
                              color: color.withValues(alpha: 0.2),
                              blurRadius: 3,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 选中柱子的时长数值。
///
/// 数值不跟随柱子的窄槽位布局，而是在整张图表的坐标系里夹到左右边界内：
/// 30 天视图里最右一根柱子的槽位可能只有 7px，直接向两侧扩标签会被卡片圆角裁掉。
class _SelectedDurationLabel extends StatelessWidget {
  const _SelectedDurationLabel({
    super.key,
    required this.entry,
    required this.percent,
    required this.index,
    required this.slotWidth,
    required this.gap,
    required this.chartWidth,
  });

  static const _width = 48.0;
  static const _height = 22.0;

  final SleepEntry entry;
  final double percent;
  final int index;
  final double slotWidth;
  final double gap;
  final double chartWidth;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final center = index * (slotWidth + gap) + slotWidth / 2;
    final maxLeft = chartWidth > _width ? chartWidth - _width : 0.0;
    final left = (center - _width / 2).clamp(0.0, maxLeft).toDouble();
    final barHeight =
        (percent / 100 * _DurationChartCard._chartHeight).clamp(6.0, 160.0);
    const maxTop = _DurationChartCard._chartHeight - _height;
    final top = (barHeight - _height - 6).clamp(0.0, maxTop).toDouble();

    return AnimatedPositioned(
      duration: AppDurations.control,
      curve: AppMotion.standardCurve,
      left: left,
      top: top,
      width: _width,
      height: _height,
      child: Center(
        child: Text(
          '${entry.durationHours.toStringAsFixed(1)}h',
          maxLines: 1,
          style: AppTheme.num(
            context,
            size: 11,
            weight: FontWeight.w700,
            color: tokens.textPrimary,
          ).copyWith(
            shadows: [
              Shadow(
                color: tokens.bgCardSolid.withValues(alpha: 0.96),
                blurRadius: 3,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SoundSummary extends StatelessWidget {
  const _SoundSummary({required this.stats});

  final SleepStatistics stats;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return QuietSurface(
      borderRadius: BorderRadius.circular(AppRadii.panel),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      child: Row(
        children: [
          Expanded(
            child: _SoundSummaryItem(
              icon: AppIcons.snore(
                size: 19,
                color: tokens.accent,
                strokeWidth: 1.5,
              ),
              label: '打鼾夜数',
              value: '${stats.snoreNights}',
            ),
          ),
          Container(
            width: 1,
            height: 38,
            margin: const EdgeInsets.symmetric(horizontal: 20),
            color: tokens.border,
          ),
          Expanded(
            child: _SoundSummaryItem(
              icon: AppIcons.bubble(
                size: 19,
                color: tokens.accent,
                strokeWidth: 1.5,
              ),
              label: '梦话夜数',
              value: '${stats.talkNights}',
            ),
          ),
        ],
      ),
    );
  }
}

class _SoundSummaryItem extends StatelessWidget {
  const _SoundSummaryItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  final Widget icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Row(
      children: [
        icon,
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 10, color: tokens.textMuted),
              ),
              const SizedBox(height: 4),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: value,
                      style: AppTheme.num(
                        context,
                        size: 20,
                        weight: FontWeight.w600,
                        color: tokens.textPrimary,
                      ),
                    ),
                    TextSpan(
                      text: ' 晚',
                      style: TextStyle(
                        fontSize: 10,
                        color: tokens.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 已保存的梦话转录。只展示录音分析实际产出的文本。
class _TranscriptCard extends StatelessWidget {
  const _TranscriptCard({required this.items});

  final List<({SleepEntry entry, SoundClip clip})> items;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return QuietSurface(
      borderRadius: BorderRadius.circular(AppRadii.panel),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '梦话记录',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: tokens.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          for (var index = 0; index < items.length; index++) ...[
            if (index > 0) Divider(height: 1, color: tokens.border),
            _TranscriptRow(item: items[index]),
          ],
          const SizedBox(height: 8),
          Text(
            '转录内容来自夜间录音，仅供参考，不构成医疗建议。',
            style: TextStyle(
              fontSize: 10,
              height: 1.5,
              color: tokens.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _TranscriptRow extends StatelessWidget {
  const _TranscriptRow({required this.item});

  final ({SleepEntry entry, SoundClip clip}) item;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final local = item.clip.startedAtUtc.toLocal();
    final date = '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
    final raw = item.clip.transcript!.trim();
    final transcript = raw.startsWith('「') ? raw : '「$raw」';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$date · ${item.clip.timeLabel}',
            style: AppTheme.num(
              context,
              size: 10,
              weight: FontWeight.w400,
              color: tokens.textMuted,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            transcript,
            style: TextStyle(
              fontSize: 12,
              height: 1.65,
              color: tokens.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
