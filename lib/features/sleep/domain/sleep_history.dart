import 'sleep_entry.dart';
import 'sleep_math.dart';

/// 「全部睡眠数据」页的分组口径。
enum HistoryGrouping {
  week('按周'),
  month('按月'),
  year('按年');

  const HistoryGrouping(this.label);

  final String label;
}

/// 一组记录，以及这一组的聚合。
class SleepHistoryGroup {
  const SleepHistoryGroup({
    required this.grouping,
    required this.startDay,
    required this.endDay,
    required this.entries,
    required this.averageHours,
    required this.averageScore,
  });

  final HistoryGrouping grouping;

  /// 分组的第一天 / 最后一天，都是本地日历日：周一与周日、月首与月末、年初与年末。
  final DateTime startDay;
  final DateTime endDay;

  /// 组内记录，**最新在前**。
  final List<SleepEntry> entries;

  /// 组内平均时长。分母是组内的**记录条数**——漏记的日子不稀释平均，
  /// 与统计页同一条分母规则。
  final double averageHours;

  /// 组内平均评分。**只计有评分的记录**（分子分母都排除未评分的）；
  /// 一条都没评分时为 `null`，界面据此不显示这一项。
  final int? averageScore;

  int get count => entries.length;

  /// 组抬头。
  ///
  /// 周写成日期区间而不是「第 N 周」：日期的含义不需要解释，也不会在跨年的那一周
  /// 变成「第 1 周属于哪一年」这种要另加说明的问题。
  ///
  /// **周这一档的年份不能省。** 行里只有「10月14日 周三」，年份全靠抬头给；而同一段
  /// 日历区间在相隔若干年的两个年份里可以逐字相同（1 月 5 日都是周一的那种年份），
  /// 省掉年份就有两组抬头长得一模一样。月和年两档本来就带年份。
  String get label => switch (grouping) {
        HistoryGrouping.year => '${startDay.year}年',
        HistoryGrouping.month => '${startDay.year}年${startDay.month}月',
        HistoryGrouping.week => startDay.year == endDay.year
            ? '${startDay.year}年${formatDate(startDay)} – ${formatDate(endDay)}'
            : '${startDay.year}年${formatDate(startDay)} – '
                '${endDay.year}年${formatDate(endDay)}',
      };
}

/// 全部记录按周 / 按月 / 按年分好的结果。
///
/// **纯函数**：没有数据库、没有插件、也没有自己的时钟。归组用的是每条记录的
/// **醒来本地日历日**（[SleepEntry.archiveDay]），与总规格 §5.2「统计以本地日历天
/// 分组，跨午夜记录按醒来日期计入一天」同一条口径。
class SleepHistory {
  const SleepHistory({
    required this.grouping,
    required this.groups,
    required this.firstDay,
    required this.lastDay,
    required this.averageHours,
    required this.averageScore,
  });

  final HistoryGrouping grouping;

  /// 分组结果，**最新的一组在前**。
  final List<SleepHistoryGroup> groups;

  /// 全部记录里最早 / 最晚的那一晚（按醒来日）。没有记录时都是 `null`。
  final DateTime? firstDay;
  final DateTime? lastDay;

  /// 全部记录的平均时长 / 平均评分，口径与单组相同。
  final double? averageHours;
  final int? averageScore;

  int get count => groups.fold(0, (sum, group) => sum + group.count);

  bool get isEmpty => groups.isEmpty;

  /// 「覆盖 M月d日 – M月d日」，跨年时两端各带年份。没有记录时为 `null`。
  String? get coverageLabel {
    final first = firstDay;
    final last = lastDay;
    if (first == null || last == null) return null;
    if (first.year == last.year) {
      return '覆盖 ${formatDate(first)} – ${formatDate(last)}';
    }
    return '覆盖 ${first.year}年${formatDate(first)} – '
        '${last.year}年${formatDate(last)}';
  }

  /// 把 [allEntries] 按 [grouping] 分好。
  ///
  /// 排序在**这里**显式做一遍，不沿用调用方给的顺序：`sleepEntriesProvider` 给的是倒序，
  /// 而将来仓库一改排序，这一页的组序与组内序不该跟着悄悄变。排序是**全序**
  /// （同一入睡时刻按 id 兜底），理由与 `SleepExporter.exportableOf` 相同。
  factory SleepHistory.from({
    required List<SleepEntry> allEntries,
    required HistoryGrouping grouping,
  }) {
    if (allEntries.isEmpty) {
      return SleepHistory(
        grouping: grouping,
        groups: const [],
        firstDay: null,
        lastDay: null,
        averageHours: null,
        averageScore: null,
      );
    }

    final sorted = [...allEntries]..sort((a, b) {
        final byStart = b.startAtUtc.compareTo(a.startAtUtc);
        // 入睡时刻相同的两条（同一早上补录两次就会这样）用 id 兜底定序：
        // 只按时间排时它们的先后**未定义**，两次输入顺序不同的排序就可能给出
        // 两种结果，界面上那两行会莫名其妙地对调。理由与
        // `SleepExporter.exportableOf` 完全相同。
        return byStart != 0 ? byStart : a.id.compareTo(b.id);
      });

    final buckets = <DateTime, List<SleepEntry>>{};
    for (final entry in sorted) {
      buckets
          .putIfAbsent(_startOf(entry.archiveDay, grouping), () => [])
          .add(entry);
    }

    final starts = buckets.keys.toList()..sort((a, b) => b.compareTo(a));
    final groups = [
      for (final start in starts)
        _groupOf(
          grouping: grouping,
          start: start,
          entries: buckets[start]!,
        ),
    ];

    final days = sorted.map((entry) => entry.archiveDay).toList()..sort();
    final scored = sorted.where((entry) => entry.score != null);

    return SleepHistory(
      grouping: grouping,
      groups: groups,
      firstDay: days.first,
      lastDay: days.last,
      averageHours: _averageHours(sorted)!,
      averageScore: _averageScore(scored),
    );
  }

  static SleepHistoryGroup _groupOf({
    required HistoryGrouping grouping,
    required DateTime start,
    required List<SleepEntry> entries,
  }) =>
      SleepHistoryGroup(
        grouping: grouping,
        startDay: start,
        endDay: _endOf(start, grouping),
        entries: entries,
        averageHours: _averageHours(entries)!,
        averageScore: _averageScore(entries.where((e) => e.score != null)),
      );

  /// 一条记录归到哪一组：它醒来那天的周一 / 月首 / 年初。
  ///
  /// 用 `DateTime(y, m, d - n)` 这种**构造**而不是 `subtract(Duration(days: n))`：
  /// 后者加的是绝对时长，在有夏令时的时区里会把本地午夜推成前一天 23:00，
  /// 于是那一天的记录被归进上一组。构造式按日历字段归一，不会。
  static DateTime _startOf(DateTime day, HistoryGrouping grouping) =>
      switch (grouping) {
        HistoryGrouping.week =>
          DateTime(day.year, day.month, day.day - (day.weekday - 1)),
        HistoryGrouping.month => DateTime(day.year, day.month),
        HistoryGrouping.year => DateTime(day.year),
      };

  static DateTime _endOf(DateTime start, HistoryGrouping grouping) =>
      switch (grouping) {
        HistoryGrouping.week =>
          DateTime(start.year, start.month, start.day + 6),
        // 下个月的第 0 天 = 这个月的最后一天。
        HistoryGrouping.month => DateTime(start.year, start.month + 1, 0),
        HistoryGrouping.year => DateTime(start.year, 12, 31),
      };

  static double? _averageHours(List<SleepEntry> entries) {
    if (entries.isEmpty) return null;
    final minutes =
        entries.fold<int>(0, (sum, entry) => sum + entry.durationMinutes);
    return minutes / entries.length / 60;
  }

  static int? _averageScore(Iterable<SleepEntry> scored) {
    final scores = [for (final entry in scored) entry.score!];
    if (scores.isEmpty) return null;
    return (scores.fold<int>(0, (sum, score) => sum + score) / scores.length)
        .round();
  }
}
