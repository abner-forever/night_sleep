import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_basics.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/ios_controls.dart';
import '../../../core/widgets/quiet_surface.dart';
import '../../../core/widgets/subpage.dart';
import '../../sleep/data/sleep_repository.dart';
import '../../sleep/domain/sleep_entry.dart';
import '../../sleep/domain/sleep_history.dart';
import '../../sleep/domain/sleep_math.dart';
import '../../sleep/presentation/sheets/detail_sheet.dart';
import '../../sleep/presentation/widgets/stage_style.dart';

/// 「上一个周期」按钮的 key。测试靠它按部位找按钮（判断启用 / 禁用）。
const Key periodPreviousButtonKey = Key('all-data-period-previous');

/// 「下一个周期」按钮的 key。理由同上。
const Key periodNextButtonKey = Key('all-data-period-next');

/// 所有睡眠数据：一次只看一个周期，靠翻页看别的周期。
///
/// 与统计页分工不同——统计页算最近 7 / 14 / 30 条的**趋势**，这一页按周 / 月 / 年
/// **翻阅全部**：一张按周期的汇总卡（平均时长、柱状图、平均评分 / 达标率 / 记录夜数）
/// 加一个扁平记录列表，点一行开详情。
///
/// 周期口径（周一为一周之始、按醒来本地日归组、平均时长分母是记录条数、平均评分只计
/// 已评分）全在 [HistoryWindow] 里，是纯函数。**这一页自己不做任何口径判断**：
/// 两处各算一套的话，迟早各自漂移。
///
/// 形态见[静谧夜色 + 柔和晨光](../../../../docs/superpowers/specs/2026-10-16-quiet-night-visual-language.md)
/// §4.5（它取代了 v3.31 那份「一次列出全部组」的设计），偏差记在总规格 §8 的 #69 / #71。
class AllSleepDataPage extends ConsumerStatefulWidget {
  const AllSleepDataPage({super.key});

  @override
  ConsumerState<AllSleepDataPage> createState() => _AllSleepDataPageState();
}

class _AllSleepDataPageState extends ConsumerState<AllSleepDataPage> {
  /// 默认按周：一周七根柱子是最容易一眼读完的粒度，也照原型的默认档。
  HistoryGrouping _grouping = HistoryGrouping.week;

  /// 当前周期的锚点。`null` 表示还没翻过页——那一刻取库里最新的一条。
  ///
  /// 初始值不写死在字段里：记录是异步读到的，构造 `State` 时还没有数据可看。
  DateTime? _anchor;

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
      data: _content,
    );
  }

  /// 加载 / 出错 / 有数据三态共用同一副外壳。标题照原型是「所有睡眠数据」。
  Widget _shell(List<Widget> children) => Subpage(
        title: '所有睡眠数据',
        children: children,
      );

  Widget _content(List<SleepEntry> records) {
    final tokens = AppTokens.of(context);

    // **空库是整页空状态**，不是「这个周期没有记录」：一条记录都没有时，
    // 后者会让人以为是翻错了周期（偏差 #69 的三条红线之一）。
    if (records.isEmpty) {
      return _shell([
        EmptyState(
          icon: AppIcons.moon(size: 30, color: tokens.accent, strokeWidth: 1.6),
          title: '还没有睡眠记录',
          body: '记录第一晚之后，这里会按周、按月、按年翻阅全部记录，'
              '每一段给出条数、平均时长与达标情况。',
        ),
      ]);
    }

    final anchor = _anchor ?? latestAnchor(records)!;
    final window = windowOf(
      allEntries: records,
      grouping: _grouping,
      anchor: anchor,
    );
    // 已经是最新周期时「下一个」禁用：往后翻永远是空周期（偏差 #71）。
    final atLatest = isLatestWindow(allEntries: records, window: window);

    // 演示记录照列（与统计页同口径），但要在卡里报数——这一卡的三个数字把合成的
    // 与真实的混在了一起。数的是**本周期内**的条数：卡里的数字都是本周期的，
    // 报一个全库的条数会描述一个不在这屏上的集合。只有调试构建里会有它。
    final demoCount = window.entries
        .where((entry) => entry.source == AppConfig.demoSource)
        .length;

    return _shell([
      SegmentedControl<HistoryGrouping>(
        segments: [
          for (final grouping in HistoryGrouping.values)
            SegmentOption(value: grouping, label: grouping.label),
        ],
        selected: _grouping,
        onChanged: (grouping) => setState(() => _grouping = grouping),
        // 撑满宽度：它与下面那张卡是同一列的块级元素。
        expand: true,
      ),
      const SizedBox(height: 18),
      _PeriodPager(
        label: window.label,
        count: window.count,
        onPrevious: () =>
            setState(() => _anchor = _shiftedAnchor(anchor, _grouping, -1)),
        // `null` 就是禁用：颜色随之降到 muted，点击也不再接住。
        onNext: atLatest
            ? null
            : () =>
                setState(() => _anchor = _shiftedAnchor(anchor, _grouping, 1)),
      ),
      const SizedBox(height: 16),
      _SummaryCard(window: window, demoCount: demoCount),
      const SizedBox(height: 18),
      if (window.isEmpty)
        EmptyState(
          icon: AppIcons.moon(size: 30, color: tokens.accent, strokeWidth: 1.6),
          title: '这个周期还没有睡眠记录',
          body: '可切换其他周期查看历史数据',
        )
      else ...[
        Row(
          children: [
            Expanded(
              child: Text(
                '睡眠记录',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: tokens.textPrimary,
                ),
              ),
            ),
            Text(
              '按日期倒序',
              style: TextStyle(fontSize: 12, color: tokens.textMuted),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _RecordList(entries: window.entries),
      ],
    ]);
  }

  /// 把锚点挪到相邻周期。
  ///
  /// **用 `DateTime` 构造而不是 `Duration`**：`Duration` 加的是绝对时长，在有夏令时的
  /// 时区里会把本地午夜推成前一天 23:00（`sleep_history.dart` 里同一个理由）。
  ///
  /// 月与年这两档把日归到 1 号：锚点落在周期内哪一天都得到同一个窗口（[windowOf] 会把
  /// 它归到周期首日），而 `DateTime(2026, 10, 31)` 加一个月会溢出成 12 月 1 日
  /// ——那样向后翻一次就跳过一个周期。
  DateTime _shiftedAnchor(
          DateTime anchor, HistoryGrouping grouping, int step) =>
      switch (grouping) {
        HistoryGrouping.week =>
          DateTime(anchor.year, anchor.month, anchor.day + 7 * step),
        HistoryGrouping.month => DateTime(anchor.year, anchor.month + step, 1),
        HistoryGrouping.year => DateTime(anchor.year + step, 1, 1),
      };
}

/// 周期翻页行：左右两个圆钮夹着周期抬头与条数。
class _PeriodPager extends StatelessWidget {
  const _PeriodPager({
    required this.label,
    required this.count,
    required this.onPrevious,
    required this.onNext,
  });

  final String label;
  final int count;
  final VoidCallback onPrevious;

  /// 为空表示「已是最新周期」，按钮禁用。
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    return Row(
      children: [
        _button(
          tokens,
          key: periodPreviousButtonKey,
          forward: false,
          onTap: onPrevious,
          semanticLabel: '上一个周期',
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            children: [
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                // 周抬头是「2026年10月12日 – 10月18日」这种长串：溢出时截断而不是折行，
                // 折行会把翻页行顶成两行高，翻一次页整页跟着上下跳。
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.36,
                  color: tokens.textPrimary,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '$count 条睡眠记录',
                style: TextStyle(
                  fontSize: 12,
                  color: tokens.textMuted,
                  fontFeatures: AppTheme.tabular,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        _button(
          tokens,
          key: periodNextButtonKey,
          forward: true,
          onTap: onNext,
          semanticLabel: '下一个周期',
        ),
      ],
    );
  }

  Widget _button(
    AppTokens tokens, {
    required Key key,
    required bool forward,
    required VoidCallback? onTap,
    required String semanticLabel,
  }) {
    final enabled = onTap != null;
    // 禁用态**只降颜色**（箭头降到 muted），底色与尺寸都不变：
    // 换一套底色会让这个按钮看起来像另一种控件，而不只是暂时不可用。
    return Pressable(
      key: key,
      onTap: onTap,
      semanticLabel: semanticLabel,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: tokens.bgRaised,
          shape: BoxShape.circle,
          border: Border.all(color: tokens.glassBorder),
        ),
        child: Transform.flip(
          flipX: !forward,
          child: AppIcons.chevronRight(
            size: 15,
            color: enabled ? tokens.accent : tokens.textMuted,
            strokeWidth: 2.2,
          ),
        ),
      ),
    );
  }
}

/// 一个周期的汇总卡：平均时长、每日时长柱状图、三格指标。
///
/// 材质是 `StatsDataHero`（规格 §2.3 的「冷净」）：描边是 accent 12% 混
/// `glassBorder`，底色是 accentSoft 30% 到 45% 处透明的线性渐变叠 `materialStrong`。
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.window, required this.demoCount});

  final HistoryWindow window;

  /// 本周期内的演示记录条数。大于 0 时在卡片末尾如实写一句。
  final int demoCount;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final average = window.averageHours;
    final score = window.averageScore;
    // 目标达成只看**平均时长**这一件真的测过的事；没有记录时谈不上达标。
    final reached = average != null && average >= 7;

    return QuietSurface(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '平均睡眠时长',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.96,
                        color: tokens.textMuted,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          // 空周期写「—」：没有记录就没有平均，不摆一个 0。
                          average == null ? '—' : average.toStringAsFixed(1),
                          style: AppTheme.num(
                            context,
                            size: 36,
                            weight: FontWeight.w700,
                            letterSpacing: -1.44,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '小时',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: tokens.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  reached ? '已达到睡眠目标' : '目标 7 小时',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    // 「达标」判断用 good 薄荷绿；没达标就是一句中性提示，不涂色。
                    color: reached ? tokens.good : tokens.textMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          PeriodBarChart(bars: _barsFor(window), maxBarWidth: _maxBarWidth),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: tokens.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _Metric(
                    label: '平均评分',
                    // 一条都没评分时写「—」：一个 0 会被读成「大家都打了 0 分」。
                    value: score == null ? '—' : '$score',
                    color: score == null ? null : scoreBandColor(tokens, score),
                  ),
                ),
                Expanded(
                  child: _Metric(
                    label: '达标率',
                    value: '${window.sufficientRate}%',
                    // 「达标」是本轮新加的那个语义色唯一的用途（规格 §3.2）。
                    // 空窗口的 0% 不上色——那不是「没达标」，是「没有可算的东西」。
                    color: window.isEmpty ? null : tokens.good,
                  ),
                ),
                Expanded(
                  child: _Metric(label: '记录夜数', value: '${window.count}'),
                ),
              ],
            ),
          ),
          if (demoCount > 0) ...[
            const SizedBox(height: 10),
            Text(
              '其中 $demoCount 条是演示数据，不是你的记录',
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: tokens.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }

  double get _maxBarWidth => switch (window.grouping) {
        HistoryGrouping.week => 28,
        HistoryGrouping.month => 14,
        HistoryGrouping.year => 14,
      };

  /// 本周期要画的柱子。三种粒度各有一套起止与取值口径。
  List<PeriodBar> _barsFor(HistoryWindow window) {
    final start = window.startDay;
    switch (window.grouping) {
      // 周：周一到周日各一根。
      case HistoryGrouping.week:
        return [
          for (var i = 0; i < 7; i++)
            PeriodBar(
              label: _weekdayLabels[i],
              value: _hoursOn(window, _plusDays(start, i)),
            ),
        ];
      // 月：当月每一天一根。标签只在一号与逢五的日子写——31 个日期挤在一行里
      // 谁也读不清，而柱子本身已经给出了每天的分布。
      case HistoryGrouping.month:
        return [
          for (var day = 1; day <= window.endDay.day; day++)
            PeriodBar(
              label: '$day',
              labelSize: 9,
              showLabel: day == 1 || day % 5 == 0,
              value: _hoursOn(window, DateTime(start.year, start.month, day)),
            ),
        ];
      // 年：12 个月各一根，值取**当月平均**——一个月里几晚长短不一，报某一晚没意义。
      case HistoryGrouping.year:
        return [
          for (var month = 1; month <= 12; month++)
            PeriodBar(label: '$month月', value: _hoursInMonth(window, month)),
        ];
    }
  }
}

/// 从 [start] 往后挪 [offset] 天。
///
/// 用 `DateTime` 构造而不是 `add(Duration(days: n))`：后者加的是绝对时长，
/// 在有夏令时的时区里会把本地午夜推成前一天 23:00（`sleep_history.dart` 里同一个理由）。
DateTime _plusDays(DateTime start, int offset) =>
    DateTime(start.year, start.month, start.day + offset);

const _weekdayLabels = ['一', '二', '三', '四', '五', '六', '日'];

/// 窗口内某一天的时长（小时）。一天有多条时取平均；没有记录时为 `null`。
double? _hoursOn(HistoryWindow window, DateTime day) {
  final hours = [
    for (final entry in window.entries)
      if (_sameDay(entry.archiveDay, day)) entry.durationHours,
  ];
  if (hours.isEmpty) return null;
  return hours.reduce((a, b) => a + b) / hours.length;
}

/// 窗口内某个月的时长平均值（小时）。那个月没有记录时为 `null`。
double? _hoursInMonth(HistoryWindow window, int month) {
  final hours = [
    for (final entry in window.entries)
      if (entry.archiveDay.month == month) entry.durationHours,
  ];
  if (hours.isEmpty) return null;
  return hours.reduce((a, b) => a + b) / hours.length;
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// 一根柱子。
@immutable
class PeriodBar {
  const PeriodBar({
    required this.label,
    this.value,
    this.showLabel = true,
    this.labelSize = 10,
  });

  /// 轴标签。周是 `一`…`日`，月是日号，年是 `N月`。
  final String label;

  /// 时长（小时）。**`null` 表示这一段没有记录**——那一根画 1% 的淡条，
  /// 不是画一根 0 高的柱子（0 高与「没记录」在图上分不出来）。
  final double? value;

  /// 标签画不画。月视图只在一号与逢五的日子写日期。
  final bool showLabel;

  final double labelSize;
}

/// 周期柱状图：高 176，柱高按 `时长 / 10 小时` 换算。
///
/// 柱色是既有的 [durationBandColor]（照「不给图表重新染色」那条），透明度 .86；
/// 没有记录的那一段画 1% 的 `bgMuted` 淡条。
///
/// **柱宽与间距必须保证 390 宽下不溢出**：一个月 31 根柱子，一格只有 10 个逻辑像素。
/// 所以槽位一律由 `Expanded` 均分，柱宽在槽位内再夹到上限——不写死任何一格的实际宽度。
class PeriodBarChart extends StatelessWidget {
  const PeriodBarChart({
    super.key,
    required this.bars,
    this.maxBarWidth = 14,
  });

  final List<PeriodBar> bars;

  /// 单根柱子的宽度上限。周视图放得下 28，月与年只有 14。
  final double maxBarWidth;

  /// 图表区高度。
  static const double height = 176;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    // 一周七根柱子放得下「7.0」这种三字数值；一个月 31 根放不下任何数值。
    final showValues = bars.length <= 7;
    final barArea = showValues ? height - _kValueLabelHeight : height;

    return Column(
      children: [
        SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final bar in bars)
                Expanded(
                  child: _Column(
                    bar: bar,
                    maxBarWidth: maxBarWidth,
                    barArea: barArea,
                    showValue: showValues,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 14,
          child: Row(
            children: [
              for (final bar in bars)
                Expanded(
                  child: Center(
                    child: bar.showLabel
                        ? FittedBox(
                            fit: BoxFit.scaleDown,
                            // 一个月的格子只有十来个像素宽，字号 9 的两位日期在窄屏上
                            // 依然可能宽过格子——缩放而不是截断，日期少一位就成了别的日子。
                            child: Text(
                              bar.label,
                              style: AppTheme.num(
                                context,
                                size: bar.labelSize,
                                weight: FontWeight.w500,
                                color: tokens.textMuted,
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 柱顶数值那一行占的高度（只有周视图用得上）。
///
/// 它从柱子的可用高度里扣掉：数值与柱子同处一根槽位，不扣的话整列会高出
/// 图表区一头，`Column` 就要报溢出。
const double _kValueLabelHeight = 15;

class _Column extends StatelessWidget {
  const _Column({
    required this.bar,
    required this.maxBarWidth,
    required this.barArea,
    required this.showValue,
  });

  final PeriodBar bar;
  final double maxBarWidth;
  final double barArea;
  final bool showValue;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final value = bar.value;
    // 有值最低 5%：一根 0.2 小时的柱子如果按比例画就只剩一条看不见的线。
    final percent =
        value == null ? 1.0 : (value / 10 * 100).clamp(5.0, 100.0).toDouble();

    return LayoutBuilder(
      builder: (context, constraints) {
        // 槽位均分已经由 `Expanded` 保证，这里只把柱子在槽位里夹窄一点，
        // 留出可辨认的间距；槽位本身可能只有几个像素。
        final slot = constraints.maxWidth;
        final barWidth = math.max(1.0, math.min(maxBarWidth, slot - 2));

        return Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (showValue && value != null)
              SizedBox(
                height: _kValueLabelHeight,
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      value.toStringAsFixed(1),
                      style: AppTheme.num(
                        context,
                        size: 10,
                        weight: FontWeight.w600,
                        color: tokens.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            SizedBox(
              width: barWidth,
              height: math.min(barArea, percent / 100 * barArea),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  // 没有记录的那一段用最淡的底：柱子缺席本身就是信息，
                  // 涂上时长色会被读成「这一晚很短」。
                  color: value == null
                      ? tokens.bgMuted.withValues(alpha: 0.45)
                      : durationBandColor(tokens, value)
                          .withValues(alpha: 0.86),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(4)),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 三格指标里的一格：数值在上、标签在下。
class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: AppTheme.num(
            context,
            size: 20,
            weight: FontWeight.w700,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 12, color: tokens.textMuted)),
      ],
    );
  }
}

/// 一个周期里的全部记录，装在一个安静实体面里，行间 1px 分隔线。
///
/// **一行一张玻璃卡是上一版的形态**：一屏几张卡时，每张都带自己的阴影与描边，
/// 读起来是一堆并列的卡片而不是一段列表（偏差 #68）。
class _RecordList extends StatelessWidget {
  const _RecordList({required this.entries});

  final List<SleepEntry> entries;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    return QuietSurface(
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: Column(
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: tokens.border),
            _RecordRow(entry: entries[i]),
          ],
        ],
      ),
    );
  }
}

/// 一条记录：日期徽章、时长与质量、起止时刻、右侧评分。
class _RecordRow extends StatelessWidget {
  const _RecordRow({required this.entry});

  final SleepEntry entry;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final quality = entry.quality;
    final score = entry.score;

    return Pressable(
      // 开详情弹层：编辑与删除走它既有的两条路径，这一页不新增写路径。
      onTap: () => showSleepDetailSheet(context, entry),
      semanticLabel:
          '${formatDate(entry.wakeLocal)} ${entry.durationHours.toStringAsFixed(1)} 小时',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            _DateBadge(day: entry.wakeLocal),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        '${entry.durationHours.toStringAsFixed(1)} 小时',
                        style: AppTheme.num(
                          context,
                          size: 18,
                          weight: FontWeight.w700,
                        ),
                      ),
                      if (quality != null) ...[
                        const SizedBox(width: 8),
                        // 质量标签在窄屏上先让位（截断），时长数字不缩：
                        // 两个都缩的代价是两样都读不清。
                        Flexible(
                          child: Text(
                            quality.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: qualityColor(tokens, quality),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${entry.bedtimeLabel} 入睡 · ${entry.wakeLabel} 起床',
                    style: TextStyle(
                      fontSize: 12,
                      color: tokens.textMuted,
                      fontFeatures: AppTheme.tabular,
                    ),
                  ),
                ],
              ),
            ),
            // 未评分的记录不写这一行，也不写占位符。
            //
            // **估算与模型给的分数不是一回事**，措辞跟着首页走
            // （`isEstimated ? '估算' : '评分'`）：本地规则按质量与时长算出来的分数
            // 不该顶着「评分」两个字出场——那是把本地规则说成了模型结论。
            if (score != null)
              Text(
                '${entry.isEstimated ? '估算' : '评分'} $score',
                style: AppTheme.num(
                  context,
                  size: 14,
                  weight: FontWeight.w700,
                  color: scoreBandColor(tokens, score),
                ),
              ),
            const SizedBox(width: 4),
            AppIcons.chevronRight(
              size: 14,
              color: tokens.textMuted,
              strokeWidth: 2,
            ),
          ],
        ),
      ),
    );
  }
}

/// 行首的日期徽章：日号在上、月份在下。
class _DateBadge extends StatelessWidget {
  const _DateBadge({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tokens.accentSoft,
        // 44px 的方徽章：14 是它在圆角基数（16 / 24）之外的第三档，
        // 16 会圆到看不出是方形，12 又太方。
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${day.day}',
            style: AppTheme.num(
              context,
              size: 14,
              weight: FontWeight.w700,
              color: tokens.accent,
            ),
          ),
          Text(
            '${day.month}月',
            style: TextStyle(
              fontSize: 9,
              height: 1.2,
              fontWeight: FontWeight.w600,
              color: tokens.accent,
            ),
          ),
        ],
      ),
    );
  }
}
