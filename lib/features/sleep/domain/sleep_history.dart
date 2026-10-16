import 'sleep_entry.dart';
import 'sleep_math.dart';
import 'sleep_score.dart';

/// 「全部睡眠数据」页的周期口径。
///
/// **v3.34 起标签从 `按周 / 按月 / 按年` 缩成 `周 / 月 / 年`**（照原型的分段控件）。
enum HistoryGrouping {
  week('周'),
  month('月'),
  year('年');

  const HistoryGrouping(this.label);

  final String label;
}

/// 一个周期窗口，以及这个窗口里的聚合。
///
/// 这一页 v3.31 时是「一次把全部记录分好组、一屏列出所有组」；v3.34 起改成
/// 「给一个锚点，算出一个周期」，一次只显示一个窗口，靠翻页看别的周期。
///
/// **纯数据**：没有数据库、没有插件、也没有自己的时钟。归组用的是每条记录的
/// **醒来本地日历日**（[SleepEntry.archiveDay]），与总规格 §5.2「统计以本地日历天
/// 分组，跨午夜记录按醒来日期计入一天」同一条口径。
class HistoryWindow {
  const HistoryWindow({
    required this.grouping,
    required this.anchor,
    required this.startDay,
    required this.endDay,
    required this.entries,
    required this.sufficientCount,
  });

  final HistoryGrouping grouping;

  /// 用户翻到的那个锚点（本地日历日）。它落在周期内哪一天都得到同一个窗口。
  final DateTime anchor;

  /// 周期的首日 / 末日，都是本地日历日：周一与周日、月首与月末、年初与年末。
  final DateTime startDay;
  final DateTime endDay;

  /// 窗口内的记录，**最新在前**。
  final List<SleepEntry> entries;

  /// 时长达到 7 小时（[DurationBand.healthy]）的条数。
  final int sufficientCount;

  int get count => entries.length;

  bool get isEmpty => entries.isEmpty;

  /// 窗口内平均时长。分母是**窗口内的记录条数**——漏记的日子不稀释平均，
  /// 与统计页同一条分母规则。空窗口为 `null`。
  double? get averageHours {
    if (entries.isEmpty) return null;
    final minutes =
        entries.fold<int>(0, (sum, entry) => sum + entry.durationMinutes);
    return minutes / entries.length / 60;
  }

  /// 窗口内平均评分。**只计有评分的记录**（分子分母都排除未评分的）；
  /// 一条都没评分时为 `null`，界面据此写「—」而不是一个 0。
  int? get averageScore {
    final scores = [
      for (final entry in entries)
        if (entry.score != null) entry.score!,
    ];
    if (scores.isEmpty) return null;
    return (scores.fold<int>(0, (sum, score) => sum + score) / scores.length)
        .round();
  }

  /// 达标率（%）。空窗口为 0——界面那一格此时写「0%」而不是「—」，
  /// 因为「这个周期一条记录都没有」已经由列表的空状态说清楚了。
  int get sufficientRate =>
      entries.isEmpty ? 0 : (sufficientCount / entries.length * 100).round();

  /// 周期抬头。
  ///
  /// 周写成日期区间而不是「第 N 周」：日期的含义不需要解释，也不会在跨年的那一周
  /// 变成「第 1 周属于哪一年」这种要另加说明的问题。
  ///
  /// **周这一档的年份不能省。** 行里只有「10月14日 周三」，年份全靠抬头给；而同一段
  /// 日历区间在相隔若干年的两个年份里可以逐字相同（1 月 5 日都是周一的那种年份），
  /// 省掉年份就有两个周期抬头长得一模一样。月和年两档本来就带年份。
  String get label => switch (grouping) {
        HistoryGrouping.year => '${startDay.year}年',
        HistoryGrouping.month => '${startDay.year}年${startDay.month}月',
        HistoryGrouping.week => startDay.year == endDay.year
            ? '${startDay.year}年${formatDate(startDay)} – ${formatDate(endDay)}'
            : '${startDay.year}年${formatDate(startDay)} – '
                '${endDay.year}年${formatDate(endDay)}',
      };
}

/// 一个记录归到哪一天的窗口：它醒来那天的周一 / 月首 / 年初。
///
/// 用 `DateTime(y, m, d - n)` 这种**构造**而不是 `subtract(Duration(days: n))`：
/// 后者加的是绝对时长，在有夏令时的时区里会把本地午夜推成前一天 23:00，
/// 于是那一天的记录被归进上一组。构造式按日历字段归一，不会。
DateTime startOfDay(DateTime day, HistoryGrouping grouping) =>
    switch (grouping) {
      HistoryGrouping.week =>
        DateTime(day.year, day.month, day.day - (day.weekday - 1)),
      HistoryGrouping.month => DateTime(day.year, day.month),
      HistoryGrouping.year => DateTime(day.year),
    };

/// 一个窗口的最后一天。用构造式，理由同 [startOfDay]。
DateTime endOfDay(DateTime start, HistoryGrouping grouping) =>
    switch (grouping) {
      HistoryGrouping.week => DateTime(start.year, start.month, start.day + 6),
      // 下个月的第 0 天 = 这个月的最后一天。
      HistoryGrouping.month => DateTime(start.year, start.month + 1, 0),
      HistoryGrouping.year => DateTime(start.year, 12, 31),
    };

/// 库里最新一条记录所在的周期锚点（醒来本地日）。空库为 `null`。
DateTime? latestAnchor(List<SleepEntry> allEntries) {
  if (allEntries.isEmpty) return null;
  var latest = _archiveDayOf(allEntries.first);
  for (final entry in allEntries) {
    final day = _archiveDayOf(entry);
    if (day.isAfter(latest)) latest = day;
  }
  return latest;
}

/// 算出 [anchor] 落在的那个周期窗口。
///
/// 排序在**这里**显式做一遍，不沿用调用方给的顺序：`sleepEntriesProvider` 给的是倒序，
/// 而将来仓库一改排序，这一页的行序不该跟着悄悄变。排序是**全序**
/// （同一入睡时刻按 id 兜底），理由与 `SleepExporter.exportableOf` 相同——
/// 只按时间排时，入睡时刻相同的两条先后**未定义**，两次输入顺序不同就可能给出两种结果。
HistoryWindow windowOf({
  required List<SleepEntry> allEntries,
  required HistoryGrouping grouping,
  required DateTime anchor,
}) {
  final start = startOfDay(anchor, grouping);
  final end = endOfDay(start, grouping);

  final entries = [
    for (final entry in allEntries)
      if (_within(_archiveDayOf(entry), start, end)) entry,
  ]..sort((a, b) {
      final byStart = b.startAtUtc.compareTo(a.startAtUtc);
      return byStart != 0 ? byStart : a.id.compareTo(b.id);
    });

  return HistoryWindow(
    grouping: grouping,
    anchor: _dayOf(anchor),
    startDay: start,
    endDay: end,
    entries: entries,
    sufficientCount: entries
        .where((entry) =>
            durationBand(entry.durationHours) == DurationBand.healthy)
        .length,
  );
}

/// [window] 是不是库里最新的那个周期。
///
/// 界面据此**禁用「下一个」**：往后翻永远是空周期，让一个必然通向空状态的按钮
/// 保持可点是白费一次点击（总规格 §8 偏差 #71）。空库时返回 `true`——
/// 没有记录就没有「更新」可言，而那一刻整页本来就是空状态。
bool isLatestWindow({
  required List<SleepEntry> allEntries,
  required HistoryWindow window,
}) {
  final latest = latestAnchor(allEntries);
  if (latest == null) return true;
  return !startOfDay(latest, window.grouping).isAfter(window.startDay);
}

/// 把一条记录归一到一个本地日历日（丢掉时刻）。
DateTime _dayOf(DateTime value) => DateTime(value.year, value.month, value.day);

DateTime _archiveDayOf(SleepEntry entry) => _dayOf(entry.archiveDay);

bool _within(DateTime day, DateTime start, DateTime end) =>
    !day.isBefore(start) && !day.isAfter(end);
