import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/features/sleep/domain/sleep_session.dart';

void main() {
  SleepSession session({
    required DateTime start,
    int wakeMinutes = 7 * 60,
  }) =>
      SleepSession(
        startAtUtc: start.toUtc(),
        timeZoneId: 'UTC',
        wakeMinutes: wakeMinutes,
        alarmEnabled: false,
        createdAtUtc: start.toUtc(),
      );

  group('计划时长', () {
    test('起床时间在开始之后：当天', () {
      final s = session(start: DateTime(2026, 8, 30, 6, 0));
      expect(s.plannedDuration, const Duration(hours: 1));
    });

    test('起床时间早于开始：跨到次日', () {
      final s = session(start: DateTime(2026, 8, 30, 23, 14));
      expect(s.plannedDuration, const Duration(hours: 7, minutes: 46));
    });

    /// 起床时刻**正好等于**开始时刻时不能得到 0，否则进度会除零。
    test('起床时刻与开始时刻相同：算作次日，不会得到零时长', () {
      final s = session(start: DateTime(2026, 8, 30, 7, 0));
      expect(s.plannedDuration, const Duration(days: 1));
    });
  });

  group('进度', () {
    test('刚开始是 0，到点是一半圈以上', () {
      final start = DateTime(2026, 8, 30, 23, 0);
      final s = session(start: start);
      expect(s.progressAt(start), 0);
      expect(s.progressAt(start.add(const Duration(hours: 4))),
          closeTo(0.5, 0.01));
    });

    test('超过起床时间后封顶在 1，不溢出', () {
      final start = DateTime(2026, 8, 30, 23, 0);
      final s = session(start: start);
      expect(s.progressAt(start.add(const Duration(hours: 30))), 1.0);
    });

    test('超过起床时间才算 overdue', () {
      final start = DateTime(2026, 8, 30, 23, 0);
      final s = session(start: start);
      expect(s.overdueAt(start.add(const Duration(hours: 7))), isFalse);
      expect(s.overdueAt(start.add(const Duration(hours: 9))), isTrue);
    });
  });

  group('结束守门', () {
    test('零与负时长被拒', () {
      expect(validateSessionDuration(Duration.zero),
          SessionFinishRejection.tooShort);
      expect(
        validateSessionDuration(const Duration(minutes: -5)),
        SessionFinishRejection.tooShort,
      );
    });

    test('超过 24 小时被拒', () {
      expect(
        validateSessionDuration(const Duration(hours: 24, minutes: 1)),
        SessionFinishRejection.tooLong,
      );
    });

    test('边界值通过', () {
      expect(
        validateSessionDuration(const Duration(minutes: 1)),
        SessionFinishRejection.none,
      );
      expect(
        validateSessionDuration(const Duration(hours: 24)),
        SessionFinishRejection.none,
      );
    });
  });
}
