import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/features/sleep/domain/sleep_entry.dart';
import 'package:night_sleep/features/sleep/domain/sleep_history.dart';
import 'package:night_sleep/features/sleep/domain/sleep_insight.dart';
import 'package:night_sleep/features/sleep/domain/sleep_quality.dart';

/// 「全部睡眠数据」分组口径的单元测试。
///
/// 夹具用**本地**时刻造记录再存成 UTC（`toUtc()`），醒来日的换算因此与跑测试的
/// 机器时区无关——这一组测的是归组与聚合，时区换算由 `sleep_window_test.dart` 覆盖。
void main() {
  SleepEntry night(
    DateTime wakeDay, {
    String id = 'r',
    double hours = 8,
    int? insightScore,

    /// 默认评过质量；显式传 `null` 造一条**未评分**的记录。
    SleepQuality? quality = SleepQuality.good,
  }) {
    final end = DateTime(wakeDay.year, wakeDay.month, wakeDay.day, 7);
    final start = end.subtract(Duration(minutes: (hours * 60).round()));
    return SleepEntry(
      id: id,
      startAtUtc: start.toUtc(),
      endAtUtc: end.toUtc(),
      timeZoneId: 'UTC',
      quality: quality,
      // 分数走**模型洞察**这条路：本地估算的分数由时长与质量算出来，
      // 钉不住期望值，而这一组要断的是「平均分怎么算」。
      insight: insightScore == null
          ? null
          : Insight(
              id: '$id-insight',
              recordId: id,
              content: '总结',
              provider: 'deepseek',
              model: 'deepseek-chat',
              score: insightScore,
              generatedAtUtc: end.toUtc(),
              status: InsightStatus.ok,
            ),
      createdAtUtc: end.toUtc(),
      updatedAtUtc: end.toUtc(),
    );
  }

  List<String> idsOf(SleepHistoryGroup group) =>
      [for (final entry in group.entries) entry.id];

  group('按周', () {
    test('周一到周日是一组，周日的记录属于上一组', () {
      final history = SleepHistory.from(
        allEntries: [
          night(DateTime(2026, 10, 12), id: 'mon'),
          night(DateTime(2026, 10, 18), id: 'sun'),
          night(DateTime(2026, 10, 11), id: 'prevSun'),
        ],
        grouping: HistoryGrouping.week,
      );

      expect(history.groups, hasLength(2));
      expect(history.groups.first.label, '2026年10月12日 – 10月18日');
      expect(idsOf(history.groups.first), ['sun', 'mon'], reason: '组内最新在前');
      expect(history.groups.last.label, '2026年10月5日 – 10月11日');
      expect(idsOf(history.groups.last), ['prevSun']);
    });

    test('同一段日历区间在不同年份里不会撞成同一个抬头', () {
      // 2026-01-05 与 2027-01-04 都是周一，两组的「月日」区间长度还一样；
      // 抬头不带年份时它们只差那一个数字，翻起来就分不清是哪一年。
      final history = SleepHistory.from(
        allEntries: [
          night(DateTime(2026, 1, 5), id: 'a'),
          night(DateTime(2027, 1, 4), id: 'b'),
        ],
        grouping: HistoryGrouping.week,
      );

      final labels = history.groups.map((group) => group.label).toList();
      expect(labels.toSet(), hasLength(2), reason: '两个抬头必须不同');
      expect(labels.first, '2027年1月4日 – 1月10日');
      expect(labels.last, '2026年1月5日 – 1月11日');
    });

    test('跨年那一周两端各带年份', () {
      final history = SleepHistory.from(
        allEntries: [
          night(DateTime(2026, 12, 28), id: 'a'),
          night(DateTime(2027, 1, 3), id: 'b'),
        ],
        grouping: HistoryGrouping.week,
      );

      expect(history.groups, hasLength(1));
      expect(history.groups.single.label, '2026年12月28日 – 2027年1月3日');
    });

    test('起止是周一与周日', () {
      final history = SleepHistory.from(
        allEntries: [night(DateTime(2026, 10, 14))],
        grouping: HistoryGrouping.week,
      );

      expect(history.groups.single.startDay, DateTime(2026, 10, 12));
      expect(history.groups.single.endDay, DateTime(2026, 10, 18));
    });
  });

  group('按月与按年', () {
    test('标签带年份，跨月不并组', () {
      final entries = [
        night(DateTime(2026, 9, 30), id: 'sep'),
        night(DateTime(2026, 10, 1), id: 'oct'),
        night(DateTime(2025, 12, 31), id: 'lastYear'),
      ];

      final byMonth = SleepHistory.from(
        allEntries: entries,
        grouping: HistoryGrouping.month,
      );

      expect(byMonth.groups.map((group) => group.label),
          ['2026年10月', '2026年9月', '2025年12月']);
      expect(idsOf(byMonth.groups.first), ['oct']);
    });

    test('按年把同一年并成一组', () {
      final history = SleepHistory.from(
        allEntries: [
          night(DateTime(2026, 9, 30), id: 'sep'),
          night(DateTime(2026, 10, 1), id: 'oct'),
          night(DateTime(2025, 12, 31), id: 'lastYear'),
        ],
        grouping: HistoryGrouping.year,
      );

      expect(history.groups.map((group) => group.label), ['2026年', '2025年']);
      expect(history.groups.first.count, 2);
      expect(idsOf(history.groups.first), ['oct', 'sep']);
    });

    test('起止是月首与月末、年初与年末', () {
      final month = SleepHistory.from(
        allEntries: [night(DateTime(2026, 2, 3))],
        grouping: HistoryGrouping.month,
      );
      expect(month.groups.single.startDay, DateTime(2026, 2, 1));
      expect(month.groups.single.endDay, DateTime(2026, 2, 28),
          reason: '2026 年 2 月只有 28 天');

      final year = SleepHistory.from(
        allEntries: [night(DateTime(2026, 2, 3))],
        grouping: HistoryGrouping.year,
      );
      expect(year.groups.single.startDay, DateTime(2026));
      expect(year.groups.single.endDay, DateTime(2026, 12, 31));
    });
  });

  test('入睡时刻相同的两条按 id 定序，与调用方给的顺序无关', () {
    // 同一早上补录两次就会造出这种数据。只按时间排时它们的先后未定义，
    // 两次输入顺序不同的排序就可能给出两种结果，界面上那两行会对调。
    final a = night(DateTime(2026, 10, 14), id: 'aaa');
    final b = night(DateTime(2026, 10, 14), id: 'bbb');

    List<String> idsFor(List<SleepEntry> input) => idsOf(
          SleepHistory.from(
            allEntries: input,
            grouping: HistoryGrouping.month,
          ).groups.single,
        );

    expect(idsFor([b, a]), ['aaa', 'bbb']);
    expect(idsFor([a, b]), ['aaa', 'bbb']);
  });

  test('输入顺序被打乱，组序与组内序都不变', () {
    DateTime day(int d) => DateTime(2026, 10, d);
    final entries = [
      night(day(2), id: 'a'),
      night(day(14), id: 'b'),
      night(day(13), id: 'c'),
    ];

    final forward = SleepHistory.from(
      allEntries: entries,
      grouping: HistoryGrouping.month,
    );
    final backward = SleepHistory.from(
      allEntries: entries.reversed.toList(),
      grouping: HistoryGrouping.month,
    );

    expect(idsOf(forward.groups.single), ['b', 'c', 'a']);
    expect(idsOf(backward.groups.single), idsOf(forward.groups.single));
  });

  group('聚合', () {
    test('平均时长的分母是组内记录数，漏记的日子不稀释', () {
      final history = SleepHistory.from(
        allEntries: [
          night(DateTime(2026, 10, 14), id: 'a', hours: 8),
          night(DateTime(2026, 10, 2), id: 'b', hours: 6),
        ],
        grouping: HistoryGrouping.month,
      );

      expect(history.groups.single.averageHours, closeTo(7.0, 0.001));
      expect(history.averageHours, closeTo(7.0, 0.001));
    });

    test('平均评分只计已评分的记录', () {
      final history = SleepHistory.from(
        allEntries: [
          night(DateTime(2026, 10, 14), id: 'a', insightScore: 90),
          night(DateTime(2026, 10, 13), id: 'b', insightScore: 70),
          night(DateTime(2026, 10, 12), id: 'c', quality: null),
        ],
        grouping: HistoryGrouping.month,
      );

      // 60 分那条未评分，既不进分子也不进分母。
      expect(history.groups.single.averageScore, 80);
      expect(history.averageScore, 80);
    });

    test('一条都没评分时不显示平均分', () {
      final history = SleepHistory.from(
        allEntries: [
          night(DateTime(2026, 10, 14), id: 'a', quality: null),
          night(DateTime(2026, 10, 13), id: 'b', quality: null),
        ],
        grouping: HistoryGrouping.month,
      );

      expect(history.groups.single.averageScore, isNull);
      expect(history.averageScore, isNull);
      expect(history.groups.single.averageHours, isNotNull,
          reason: '时长照旧算——没有评分不等于没有记录');
    });
  });

  test('空库：没有组，也没有覆盖范围', () {
    final history = SleepHistory.from(
      allEntries: const [],
      grouping: HistoryGrouping.month,
    );

    expect(history.groups, isEmpty);
    expect(history.isEmpty, isTrue);
    expect(history.count, 0);
    expect(history.averageHours, isNull);
    expect(history.averageScore, isNull);
    expect(history.coverageLabel, isNull);
  });

  test('覆盖范围是同一年时只写一次年份，跨年时两端都写', () {
    final sameYear = SleepHistory.from(
      allEntries: [
        night(DateTime(2026, 1, 3)),
        night(DateTime(2026, 10, 15)),
      ],
      grouping: HistoryGrouping.year,
    );

    expect(sameYear.coverageLabel, '覆盖 1月3日 – 10月15日');
    expect(sameYear.firstDay, DateTime(2026, 1, 3));
    expect(sameYear.lastDay, DateTime(2026, 10, 15));

    final across = SleepHistory.from(
      allEntries: [
        night(DateTime(2025, 12, 20)),
        night(DateTime(2026, 1, 3)),
      ],
      grouping: HistoryGrouping.year,
    );

    expect(across.coverageLabel, '覆盖 2025年12月20日 – 2026年1月3日');
  });
}
