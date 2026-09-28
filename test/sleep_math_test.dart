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
}

class _Record {
  _Record(this.startAtUtc, this.endAtUtc, this.quality);

  final DateTime startAtUtc;
  final DateTime endAtUtc;
  final int quality;
}
