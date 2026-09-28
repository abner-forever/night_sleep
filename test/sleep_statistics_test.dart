import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/features/sleep/domain/sleep_entry.dart';
import 'package:night_sleep/features/sleep/domain/sleep_insight.dart';
import 'package:night_sleep/features/sleep/domain/sleep_quality.dart';
import 'package:night_sleep/features/sleep/domain/sleep_statistics.dart';
import 'package:night_sleep/features/sleep/domain/sleep_stage.dart';
import 'package:night_sleep/features/sleep/domain/sound_event.dart';

/// Builds a night that woke on [day] with the given duration.
SleepEntry night({
  required int id,
  required int day,
  required double hours,
  bool snore = false,
  bool talkTalk = false,
  int? score,
}) {
  final end = DateTime(2026, 9, day, 7);
  final start = end.subtract(Duration(minutes: (hours * 60).round()));
  return SleepEntry(
    id: 'r$id',
    startAtUtc: start.toUtc(),
    endAtUtc: end.toUtc(),
    timeZoneId: 'UTC',
    quality: SleepQuality.good,
    stages: [
      SleepStageSegment(
        stage: SleepStageType.deep,
        startAtUtc: start.toUtc(),
        endAtUtc: end.toUtc(),
      ),
    ],
    soundClips: [
      if (snore)
        SoundClip(
          id: 'c$id-s',
          kind: SoundEventKind.snore,
          startedAtUtc: start.toUtc(),
          durationMs: 30000,
        ),
      if (talkTalk)
        SoundClip(
          id: 'c$id-t',
          kind: SoundEventKind.talk,
          startedAtUtc: start.toUtc(),
          durationMs: 8000,
          transcript: '「第$id条梦话」',
        ),
    ],
    createdAtUtc: start.toUtc(),
    updatedAtUtc: start.toUtc(),
  );
}

void main() {
  group('平均值分母', () {
    test('只按有记录的天数平均，漏记不稀释', () {
      // Two recorded nights inside a 7-day window; the five unrecorded days
      // must not pull the mean toward zero.
      final stats = SleepStatistics.from(
        allEntries: [
          night(id: 1, day: 27, hours: 8),
          night(id: 2, day: 26, hours: 6),
        ],
        period: StatsPeriod.week,
      );

      expect(stats.count, 2);
      expect(stats.averageHours, closeTo(7.0, 0.001));
    });

    test('窗口按记录条数截取，不是日历天数', () {
      final entries = [
        for (var i = 0; i < 10; i++) night(id: i, day: 27 - i, hours: 7),
      ];

      expect(
        SleepStatistics.from(allEntries: entries, period: StatsPeriod.week)
            .count,
        7,
      );
      expect(
        SleepStatistics.from(allEntries: entries, period: StatsPeriod.fortnight)
            .count,
        10,
        reason: '只有 10 条记录时，14 天窗口返回全部 10 条',
      );
    });

    test('空窗口不产生虚假平均', () {
      final stats = SleepStatistics.from(
        allEntries: const [],
        period: StatsPeriod.week,
      );
      expect(stats.isEmpty, isTrue);
      expect(stats.averageHours, isNull);
      expect(stats.averageScore, isNull);
      expect(stats.transcripts, isEmpty);
    });
  });

  group('图表坐标轴', () {
    test('时长落在 5–9 小时区间时使用默认边界', () {
      final stats = SleepStatistics.from(
        allEntries: [
          night(id: 1, day: 27, hours: 8),
          night(id: 2, day: 26, hours: 6),
        ],
        period: StatsPeriod.week,
      );
      expect(stats.chartFloor, 5);
      expect(stats.chartCeiling, 9);
      // 7h on a 5–9 axis sits at (7-5)/4 = 50%.
      expect(stats.targetHeightPercent, closeTo(50, 0.001));
    });

    test('超出区间时向外扩张', () {
      final stats = SleepStatistics.from(
        allEntries: [
          night(id: 1, day: 27, hours: 10.5),
          night(id: 2, day: 26, hours: 4.2),
        ],
        period: StatsPeriod.week,
      );
      expect(stats.chartFloor, 4);
      expect(stats.chartCeiling, 11);
    });

    test('柱高有下限，极短记录仍然可见', () {
      final stats = SleepStatistics.from(
        allEntries: [
          night(id: 1, day: 27, hours: 5),
          night(id: 2, day: 26, hours: 5),
        ],
        period: StatsPeriod.week,
      );
      for (final entry in stats.entries) {
        expect(stats.barPercentFor(entry), greaterThanOrEqualTo(6));
      }
    });

    test('柱高不超过 100%', () {
      final stats = SleepStatistics.from(
        allEntries: [
          night(id: 1, day: 27, hours: 20),
          night(id: 2, day: 26, hours: 5),
        ],
        period: StatsPeriod.week,
      );
      for (final entry in stats.entries) {
        expect(stats.barPercentFor(entry), lessThanOrEqualTo(100));
      }
    });
  });

  group('计数口径', () {
    test('充足天数、打鼾夜数、梦话夜数分别统计', () {
      final stats = SleepStatistics.from(
        allEntries: [
          night(id: 1, day: 27, hours: 8, snore: true),
          night(id: 2, day: 26, hours: 6.5, talkTalk: true),
          night(id: 3, day: 25, hours: 7),
        ],
        period: StatsPeriod.week,
      );

      expect(stats.goodNights, 2, reason: '8h 与 7h 达标，6.5h 不达标');
      expect(stats.snoreNights, 1);
      expect(stats.talkNights, 1);
    });

    test('图表按时间正序排列，最近的记录在右端', () {
      final stats = SleepStatistics.from(
        allEntries: [
          night(id: 1, day: 27, hours: 8),
          night(id: 2, day: 26, hours: 7),
          night(id: 3, day: 25, hours: 6),
        ],
        period: StatsPeriod.week,
      );
      expect(
          stats.entries.map((entry) => entry.id).toList(), ['r3', 'r2', 'r1']);
    });

    test('梦话转录只收集有转录的片段', () {
      final stats = SleepStatistics.from(
        allEntries: [
          night(id: 1, day: 27, hours: 8, talkTalk: true),
          night(id: 2, day: 26, hours: 8),
        ],
        period: StatsPeriod.week,
      );
      expect(stats.transcripts, hasLength(1));
      expect(stats.transcripts.single, contains('第1条梦话'));
    });
  });

  group('评分平均', () {
    test('只对有评分的夜晚求平均', () {
      final stats = SleepStatistics.from(
        allEntries: [
          _withScore(night(id: 1, day: 27, hours: 8), 90),
          _withScore(night(id: 2, day: 26, hours: 8), 70),
          night(id: 3, day: 25, hours: 8),
        ],
        period: StatsPeriod.week,
      );
      expect(stats.averageScore, 80);
    });
  });
}

/// Attaches a usable model insight so [SleepEntry.scoreSource] resolves to the
/// insight rather than the on-device estimate.
SleepEntry _withScore(SleepEntry entry, int score) => SleepEntry(
      id: entry.id,
      startAtUtc: entry.startAtUtc,
      endAtUtc: entry.endAtUtc,
      timeZoneId: entry.timeZoneId,
      quality: entry.quality,
      stages: entry.stages,
      soundClips: entry.soundClips,
      insight: Insight(
        id: 'insight-${entry.id}',
        recordId: entry.id,
        content: '测试洞察',
        provider: 'test',
        model: 'test',
        score: score,
        generatedAtUtc: entry.createdAtUtc,
        status: InsightStatus.ok,
      ),
      createdAtUtc: entry.createdAtUtc,
      updatedAtUtc: entry.updatedAtUtc,
    );
