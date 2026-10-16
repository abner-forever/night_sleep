import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/features/sleep/domain/sleep_math.dart';

void main() {
  test('跨午夜时长使用时间戳差值', () {
    final start = DateTime.utc(2026, 9, 24, 23);
    final end = DateTime.utc(2026, 9, 25, 7, 30);
    expect(sleepDuration(start, end), const Duration(hours: 8, minutes: 30));
  });

  test('统计平均值只计算有记录的日子并按醒来日筛选', () {
    final now = DateTime(2026, 9, 24, 12);
    final records = [
      _Record(DateTime.utc(2026, 9, 23, 22), DateTime.utc(2026, 9, 24, 6), 3),
      _Record(DateTime.utc(2026, 9, 1, 22), DateTime.utc(2026, 9, 2, 6), 5),
    ];
    final stats = calculateStatsForDays(records, now, 480, 7);
    expect(stats.records, 1);
    expect(stats.average, const Duration(hours: 8));
    expect(stats.goalDays, 1);
    expect(stats.qualityAverage, 3);
  });

  test('星期七项都写对，且按本地区算', () {
    // 2026-10-12 是周一，往后数七天正好一个循环。
    const expected = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    for (var i = 0; i < 7; i++) {
      final day = DateTime(2026, 10, 12 + i, 7);
      expect(formatWeekday(day), expected[i], reason: '本地时刻 ${day.day} 日');
      // 传进去的是同一个瞬时值的 UTC 形式时，结论必须一致——不然「周一」会在
      // 时区偏移跨过午夜的那些机器上错一天。
      expect(formatWeekday(day.toUtc()), expected[i]);
    }
  });
}

class _Record {
  _Record(this.startAtUtc, this.endAtUtc, this.quality);

  final DateTime startAtUtc;
  final DateTime endAtUtc;
  final int quality;
}
