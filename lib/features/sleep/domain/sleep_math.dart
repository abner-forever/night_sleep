import 'package:intl/intl.dart';

Duration sleepDuration(DateTime startAtUtc, DateTime endAtUtc) {
  return endAtUtc.difference(startAtUtc);
}

String formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours == 0) return '$minutes分钟';
  if (minutes == 0) return '$hours小时';
  return '$hours小时$minutes分';
}

String formatDate(DateTime value) => DateFormat('M月d日').format(value.toLocal());

String formatDateTime(DateTime value) =>
    DateFormat('M月d日 HH:mm').format(value.toLocal());

String qualityLabel(int quality) => switch (quality) {
      1 => '很差',
      2 => '较差',
      3 => '一般',
      4 => '不错',
      5 => '很好',
      _ => '未评分',
    };

class SleepStats {
  const SleepStats({
    required this.records,
    required this.average,
    required this.goalDays,
    required this.qualityAverage,
  });

  final int records;
  final Duration? average;
  final int goalDays;
  final double? qualityAverage;
}

SleepStats calculateStats(
    Iterable<dynamic> records, DateTime now, int goalMinutes) {
  return calculateStatsForDays(records, now, goalMinutes, 30);
}

SleepStats calculateStatsForDays(
  Iterable<dynamic> records,
  DateTime now,
  int goalMinutes,
  int days,
) {
  final today = DateTime(now.year, now.month, now.day);
  final cutoff = today.subtract(Duration(days: days - 1));
  final inRange = records.where((record) {
    final end = (record.endAtUtc as DateTime).toLocal();
    final day = DateTime(end.year, end.month, end.day);
    return !day.isBefore(cutoff) && !day.isAfter(today);
  }).toList();
  if (inRange.isEmpty) {
    return const SleepStats(
        records: 0, average: null, goalDays: 0, qualityAverage: null);
  }
  final total = inRange.fold<int>(0, (sum, record) {
    final start = record.startAtUtc as DateTime;
    final end = record.endAtUtc as DateTime;
    return sum + end.difference(start).inMinutes;
  });
  final goalDays = inRange.where((record) {
    final start = record.startAtUtc as DateTime;
    final end = record.endAtUtc as DateTime;
    return end.difference(start).inMinutes >= goalMinutes;
  }).length;
  final qualityTotal =
      inRange.fold<int>(0, (sum, record) => sum + (record.quality as int));
  return SleepStats(
    records: inRange.length,
    average: Duration(minutes: total ~/ inRange.length),
    goalDays: goalDays,
    qualityAverage: qualityTotal / inRange.length,
  );
}
