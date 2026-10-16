import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/features/sleep/domain/sleep_entry.dart';
import 'package:night_sleep/features/sleep/domain/sleep_history.dart';
import 'package:night_sleep/features/sleep/domain/sleep_insight.dart';
import 'package:night_sleep/features/sleep/domain/sleep_quality.dart';

/// 「全部睡眠数据」周期窗口口径的单元测试。
///
/// 夹具用**本地**时刻造记录再存成 UTC（`toUtc()`），醒来日的换算因此与跑测试的
/// 机器时区无关——这一组测的是归窗口与聚合，时区换算由 `sleep_window_test.dart` 覆盖。
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

  HistoryWindow window(
    List<SleepEntry> entries,
    HistoryGrouping grouping,
    DateTime anchor,
  ) =>
      windowOf(allEntries: entries, grouping: grouping, anchor: anchor);

  List<String> idsOf(HistoryWindow w) => [for (final e in w.entries) e.id];

  group('周窗口', () {
    test('周一到周日是同一个窗口', () {
      final entries = [
        night(DateTime(2026, 10, 12), id: 'mon'),
        night(DateTime(2026, 10, 15), id: 'thu'),
        night(DateTime(2026, 10, 18), id: 'sun'),
      ];
      final w = window(entries, HistoryGrouping.week, DateTime(2026, 10, 14));

      expect(w.startDay, DateTime(2026, 10, 12));
      expect(w.endDay, DateTime(2026, 10, 18));
      expect(w.entries.length, 3);
    });

    test('周日那晚不属于下一周', () {
      final entries = [
        night(DateTime(2026, 10, 18), id: 'sun'),
        night(DateTime(2026, 10, 19), id: 'next-mon'),
      ];
      final w = window(entries, HistoryGrouping.week, DateTime(2026, 10, 19));

      expect(w.startDay, DateTime(2026, 10, 19));
      expect(idsOf(w), ['next-mon']);
    });

    test('锚点落在窗口内任何一天都得到同一个窗口', () {
      final monday =
          window(const [], HistoryGrouping.week, DateTime(2026, 10, 12));
      final wednesday =
          window(const [], HistoryGrouping.week, DateTime(2026, 10, 14));
      final sunday =
          window(const [], HistoryGrouping.week, DateTime(2026, 10, 18));

      expect(wednesday.startDay, monday.startDay);
      expect(sunday.startDay, monday.startDay);
      expect(sunday.endDay, monday.endDay);
    });

    test('周标签带年份', () {
      final w = window(const [], HistoryGrouping.week, DateTime(2026, 10, 14));
      expect(w.label, '2026年10月12日 – 10月18日');
    });

    test('跨年那一周两端各带年份', () {
      // 2026-12-28 是周一，那一周跨到 2027-01-03（周日）。
      final w = window(const [], HistoryGrouping.week, DateTime(2026, 12, 28));
      expect(w.startDay, DateTime(2026, 12, 28));
      expect(w.endDay, DateTime(2027, 1, 3));
      expect(w.label, '2026年12月28日 – 2027年1月3日');
    });
  });

  group('月窗口与年窗口', () {
    test('月窗口是月首到月末', () {
      final w = window(const [], HistoryGrouping.month, DateTime(2026, 2, 15));
      expect(w.startDay, DateTime(2026, 2, 1));
      expect(w.endDay, DateTime(2026, 2, 28));
      expect(w.label, '2026年2月');
    });

    test('年窗口是年初到年末', () {
      final w = window(const [], HistoryGrouping.year, DateTime(2026, 7, 1));
      expect(w.startDay, DateTime(2026, 1, 1));
      expect(w.endDay, DateTime(2026, 12, 31));
      expect(w.label, '2026年');
    });

    test('月窗口只收当月那些晚', () {
      final entries = [
        night(DateTime(2026, 9, 30), id: 'sep'),
        night(DateTime(2026, 10, 1), id: 'oct-1'),
        night(DateTime(2026, 10, 31), id: 'oct-31'),
        night(DateTime(2026, 11, 1), id: 'nov'),
      ];
      final w = window(entries, HistoryGrouping.month, DateTime(2026, 10, 15));
      expect(idsOf(w), ['oct-31', 'oct-1']);
    });

    test('周期标签从 按周 / 按月 / 按年 缩成 周 / 月 / 年', () {
      expect(HistoryGrouping.week.label, '周');
      expect(HistoryGrouping.month.label, '月');
      expect(HistoryGrouping.year.label, '年');
    });
  });

  group('窗口内的行序', () {
    test('最新在前', () {
      final entries = [
        night(DateTime(2026, 10, 12), id: 'a'),
        night(DateTime(2026, 10, 15), id: 'c'),
        night(DateTime(2026, 10, 13), id: 'b'),
      ];
      final w = window(entries, HistoryGrouping.week, DateTime(2026, 10, 14));
      expect(idsOf(w), ['c', 'b', 'a']);
    });

    test('输入顺序打乱后行序不变', () {
      final ordered = [
        night(DateTime(2026, 10, 12), id: 'a'),
        night(DateTime(2026, 10, 13), id: 'b'),
        night(DateTime(2026, 10, 14), id: 'c'),
      ];
      final shuffled = [ordered[2], ordered[0], ordered[1]];
      final anchor = DateTime(2026, 10, 14);

      expect(
        idsOf(window(shuffled, HistoryGrouping.week, anchor)),
        idsOf(window(ordered, HistoryGrouping.week, anchor)),
      );
    });

    test('同一入睡时刻的两条按 id 定序', () {
      final same = DateTime(2026, 10, 14);
      final entries = [
        night(same, id: 'b'),
        night(same, id: 'a'),
      ];
      final w = window(entries, HistoryGrouping.week, same);
      expect(idsOf(w), ['a', 'b']);
    });
  });

  group('聚合', () {
    test('平均时长的分母是窗口内的记录条数，漏记的日子不稀释', () {
      final entries = [
        night(DateTime(2026, 10, 12), id: 'a', hours: 6),
        night(DateTime(2026, 10, 14), id: 'b', hours: 8),
      ];
      final w = window(entries, HistoryGrouping.week, DateTime(2026, 10, 14));
      // 一周七天里只记了两晚，平均是 (6+8)/2 而不是 /7。
      expect(w.averageHours, closeTo(7.0, 1e-9));
    });

    test('平均分只计已评分的记录', () {
      final entries = [
        night(DateTime(2026, 10, 12), id: 'a', insightScore: 80),
        night(DateTime(2026, 10, 13), id: 'b', insightScore: 90),
        // 未评分：质量为空时 `SleepEntry.score` 才是 null。填了质量却没洞察的
        // 记录会走本地估算（偏差 #26 / #47），那是「有分数」，不是「未评分」。
        night(DateTime(2026, 10, 14), id: 'c', quality: null),
      ];
      final w = window(entries, HistoryGrouping.week, DateTime(2026, 10, 14));
      expect(w.averageScore, 85);
    });

    test('一条都没评分时平均分为 null', () {
      final entries = [
        night(DateTime(2026, 10, 12), id: 'a', quality: null),
        night(DateTime(2026, 10, 13), id: 'b', quality: null),
      ];
      final w = window(entries, HistoryGrouping.week, DateTime(2026, 10, 14));
      expect(w.averageScore, isNull);
    });

    test('达标数按 7 小时线算，达标率是它除以记录条数', () {
      final entries = [
        night(DateTime(2026, 10, 12), id: 'a', hours: 7),
        night(DateTime(2026, 10, 13), id: 'b', hours: 6.9),
        night(DateTime(2026, 10, 14), id: 'c', hours: 8),
        night(DateTime(2026, 10, 15), id: 'd', hours: 5),
      ];
      final w = window(entries, HistoryGrouping.week, DateTime(2026, 10, 14));
      expect(w.sufficientCount, 2);
      expect(w.sufficientRate, 50);
    });

    test('空窗口：平均为 null、达标率为 0、不是「有数据」', () {
      final w = window(const [], HistoryGrouping.week, DateTime(2026, 10, 14));
      expect(w.isEmpty, isTrue);
      expect(w.count, 0);
      expect(w.averageHours, isNull);
      expect(w.averageScore, isNull);
      expect(w.sufficientRate, 0);
    });

    test('窗口外的记录一条都不进来', () {
      final entries = [night(DateTime(2026, 10, 11), id: 'last-sun')];
      final w = window(entries, HistoryGrouping.week, DateTime(2026, 10, 14));
      expect(w.isEmpty, isTrue);
    });
  });

  group('最新周期', () {
    test('latestAnchor 取库里最晚的醒来日；空库为 null', () {
      final entries = [
        night(DateTime(2026, 10, 12)),
        night(DateTime(2026, 11, 3)),
        night(DateTime(2026, 9, 30)),
      ];
      expect(latestAnchor(entries), DateTime(2026, 11, 3));
      expect(latestAnchor(const []), isNull);
    });

    test('最新记录所在的那个周期才算最新', () {
      final entries = [
        night(DateTime(2026, 10, 14)),
        night(DateTime(2026, 10, 7)),
      ];
      final latest =
          window(entries, HistoryGrouping.week, DateTime(2026, 10, 14));
      final older =
          window(entries, HistoryGrouping.week, DateTime(2026, 10, 7));

      expect(isLatestWindow(allEntries: entries, window: latest), isTrue);
      // 「下一个」在这里必须禁用：往后翻永远是空周期（总规格偏差 #71）。
      expect(isLatestWindow(allEntries: entries, window: older), isFalse);
    });

    test('空库时任何窗口都算最新——那一刻整页是空状态', () {
      final empty =
          window(const [], HistoryGrouping.week, DateTime(2026, 10, 14));
      expect(isLatestWindow(allEntries: const [], window: empty), isTrue);
    });
  });
}
