import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/features/sleep/domain/sleep_quality.dart';
import 'package:night_sleep/features/sleep/domain/sleep_score.dart';

void main() {
  group('estimateScore 时长阶梯', () {
    // Duration alone: no events deduct anything, quality contributes its share.
    int scoreForDuration(double hours) =>
        estimateScore(hours, SleepQuality.fair, LoggedEvents.none);

    test('7–9 小时是满分区间', () {
      // 45 (duration cap) + 17.5 (mid quality) + 20 (no events) = 82.5 → 83.
      expect(scoreForDuration(7), 83);
      expect(scoreForDuration(8), 83);
      expect(scoreForDuration(9), 83);
    });

    test('超过 9 小时递减，而不是继续加分', () {
      // This is the branch the prototype made unreachable; the documented
      // intent is that oversleeping decays.
      final tenHours = estimateScore(10, SleepQuality.fair, LoggedEvents.none);
      final nineHours = scoreForDuration(9);
      expect(
        tenHours,
        lessThan(nineHours),
        reason: '睡 10 小时不应比 9 小时得分更高',
      );
      // 45 - (10-9)*8 = 37 duration points, so 37 + 17.5 + 20 = 74.5 → 75.
      expect(tenHours, 75);
    });

    test('递减有下限，不会跌破 28 分时长分', () {
      // At 12h: 45 - 3*8 = 21, floored to 28.
      // 28 + 17.5 + 20 = 65.5 → 66.
      expect(estimateScore(12, SleepQuality.fair, LoggedEvents.none), 66);
    });

    test('6 小时起始段与 5 小时段连续', () {
      // 33 + (6-6)*12 = 33 → 33 + 17.5 + 20 = 70.5 → 71 (round half away from 0)
      expect(scoreForDuration(6), 71);
      // 20 + (5-5)*13 = 20 → 20 + 17.5 + 20 = 57.5 → 58
      expect(scoreForDuration(5), 58);
    });

    test('低于 5 小时按比例衰减', () {
      // (4/5)*20 = 16 → 16 + 17.5 + 20 = 53.5 → 54
      expect(scoreForDuration(4), 54);
    });
  });

  group('estimateScore 事件扣分', () {
    test('每类事件按原型权重扣分', () {
      const base = LoggedEvents.none;
      final baseline = estimateScore(8, SleepQuality.fair, base);
      expect(
        estimateScore(8, SleepQuality.fair, base.copyWith(snore: true)),
        baseline - 4,
      );
      expect(
        estimateScore(8, SleepQuality.fair, base.copyWith(talk: true)),
        baseline - 3,
      );
      expect(
        estimateScore(8, SleepQuality.fair, base.copyWith(restless: true)),
        baseline - 7,
      );
      expect(
        estimateScore(8, SleepQuality.fair, base.copyWith(nightmare: true)),
        baseline - 6,
      );
    });

    test('事件扣分不会把分数压到负数', () {
      final score = estimateScore(
        3,
        SleepQuality.veryPoor,
        const LoggedEvents(
          snore: true,
          talk: true,
          restless: true,
          nightmare: true,
        ),
      );
      expect(score, greaterThanOrEqualTo(0));
    });
  });

  group('estimateScore 质量权重', () {
    test('主观质量从 0 到 35 线性映射', () {
      final worst = estimateScore(8, SleepQuality.veryPoor, LoggedEvents.none);
      final best = estimateScore(8, SleepQuality.excellent, LoggedEvents.none);
      expect(best - worst, 35);
    });
  });

  group('estimateSummary', () {
    test('时长与事件都出现在结论里', () {
      final summary = estimateSummary(
        6.5,
        SleepQuality.fair,
        const LoggedEvents(snore: true, nightmare: true),
        68,
      );
      expect(summary, contains('6.5'));
      expect(summary, contains('打鼾'));
      expect(summary, contains('噩梦'));
      expect(summary, contains('略显不足'));
    });

    test('无事件时说明未记录到干扰', () {
      final summary =
          estimateSummary(8, SleepQuality.good, LoggedEvents.none, 90);
      expect(summary, contains('未记录到明显干扰事件'));
      expect(summary, contains('健康区间'));
    });
  });

  group('分档', () {
    test('durationBand 边界', () {
      expect(durationBand(7), DurationBand.healthy);
      expect(durationBand(6.9), DurationBand.slightlyShort);
      expect(durationBand(6), DurationBand.slightlyShort);
      expect(durationBand(5.9), DurationBand.short);
    });

    test('scoreBand 边界', () {
      expect(scoreBand(85), ScoreBand.excellent);
      expect(scoreBand(84), ScoreBand.good);
      expect(scoreBand(70), ScoreBand.good);
      expect(scoreBand(69), ScoreBand.fair);
      expect(scoreBand(55), ScoreBand.fair);
      expect(scoreBand(54), ScoreBand.poor);
    });
  });
}
