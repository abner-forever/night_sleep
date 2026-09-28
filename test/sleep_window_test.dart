import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/features/sleep/domain/sleep_window.dart';

/// Fixed instant for constructing [SleepWindow] values directly; only the
/// derived `durationHours` matters in those cases.
final _epoch = DateTime.utc(2026, 1, 1);

void main() {
  group('buildSleepWindow', () {
    test('晚间入睡跨午夜，归档在醒来日', () {
      final window = buildSleepWindow(
        wakeDate: DateTime(2026, 9, 27),
        bedtime: '23:15',
        wakeTime: '07:20',
      );
      // Started the previous evening.
      expect(window.startAtUtc.toLocal().day, 26);
      expect(window.startAtUtc.toLocal().hour, 23);
      expect(window.startAtUtc.toLocal().minute, 15);
      expect(window.endAtUtc.toLocal().day, 27);
      expect(window.endAtUtc.toLocal().hour, 7);
      expect(window.durationHours, closeTo(8.083, 0.001));
    });

    test('凌晨入睡落在同一天', () {
      final window = buildSleepWindow(
        wakeDate: DateTime(2026, 9, 27),
        bedtime: '00:30',
        wakeTime: '07:00',
      );
      expect(window.startAtUtc.toLocal().day, 27);
      expect(window.startAtUtc.toLocal().hour, 0);
      expect(window.durationHours, closeTo(6.5, 0.001));
    });

    test('跨午夜时长用瞬时差值，不是时钟差', () {
      final window = buildSleepWindow(
        wakeDate: DateTime(2026, 9, 27),
        bedtime: '22:00',
        wakeTime: '06:00',
      );
      // A naive `wake - bed` would be negative; the window must be 8h.
      expect(window.durationHours, closeTo(8, 0.001));
      expect(window.isPlausible, isTrue);
    });

    test('记录保存的是 UTC 瞬时值并带上录入时区', () {
      final window = buildSleepWindow(
        wakeDate: DateTime(2026, 9, 27),
        bedtime: '23:00',
        wakeTime: '07:00',
      );
      expect(window.startAtUtc.isUtc, isTrue);
      expect(window.endAtUtc.isUtc, isTrue);
      expect(window.timeZoneId, isNotEmpty);
    });

    test('同一起止时间得到 24 小时，恰好落在允许的上界', () {
      final window = buildSleepWindow(
        wakeDate: DateTime(2026, 9, 27),
        bedtime: '07:00',
        wakeTime: '07:00',
      );
      // bed == wake rolls back a day, giving exactly 24h. The spec's bound is
      // `0 < 时长 <= 24h`, so this is the inclusive upper limit and passes; the
      // form rejects anything that computes to zero or negative instead.
      expect(window.durationHours, closeTo(24, 0.001));
      expect(window.isPlausible, isTrue);
    });

    test('isPlausible 拒绝零时长与非正时长', () {
      // Defensive check of the guard the Log form relies on, independent of how
      // the window was produced.
      final zero = SleepWindow(
        startAtUtc: _epoch,
        endAtUtc: _epoch,
        timeZoneId: 'UTC',
        durationHours: 0,
      );
      expect(zero.isPlausible, isFalse);

      final over = SleepWindow(
        startAtUtc: _epoch,
        endAtUtc: _epoch,
        timeZoneId: 'UTC',
        durationHours: 25,
      );
      expect(over.isPlausible, isFalse);
    });
  });

  group('日期与时钟格式化', () {
    test('formatClock 补零到 HH:mm', () {
      expect(formatClock(DateTime(2026, 9, 27, 7, 5)), '07:05');
      expect(formatClock(DateTime(2026, 9, 27, 23, 59)), '23:59');
    });

    test('formatIsoDate / parseIsoDate 往返一致', () {
      final date = DateTime(2026, 9, 27);
      final encoded = formatIsoDate(date);
      expect(encoded, '2026-09-27');
      expect(parseIsoDate(encoded, DateTime(2000)), date);
    });

    test('parseIsoDate 对非法输入回退到默认值', () {
      final fallback = DateTime(2026, 1, 1);
      expect(parseIsoDate('not-a-date', fallback), fallback);
      expect(parseIsoDate('2026-09', fallback), fallback);
    });
  });
}
