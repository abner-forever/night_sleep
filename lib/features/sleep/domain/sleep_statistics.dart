import 'sleep_entry.dart';

/// The 7 / 14 / 30-day windows offered on the Statistics tab.
enum StatsPeriod {
  week(7, '7天'),
  fortnight(14, '14天'),
  month(30, '30天');

  const StatsPeriod(this.days, this.label);

  final int days;
  final String label;
}

/// Aggregates for the selected window.
///
/// Averages divide by the number of **recorded** nights in the window, not by
/// the number of calendar days, so a gap in tracking does not silently drag the
/// average down. This is the denominator rule the spec requires, and it matches
/// the prototype's `data.reduce(...) / data.length`.
class SleepStatistics {
  const SleepStatistics({
    required this.period,
    required this.entries,
    required this.averageHours,
    required this.averageScore,
    required this.goodNights,
    required this.snoreNights,
    required this.talkNights,
    required this.chartFloor,
    required this.chartCeiling,
    required this.targetHeightPercent,
    required this.transcripts,
  });

  final StatsPeriod period;

  /// Entries in the window, oldest first — the order the chart plots them in.
  final List<SleepEntry> entries;

  /// Null when the window has no records.
  final double? averageHours;

  /// Null when no night in the window has a score.
  final int? averageScore;

  /// Nights at or above the 7-hour target.
  final int goodNights;
  final int snoreNights;
  final int talkNights;

  /// Y-axis bounds of the duration chart.
  final double chartFloor;
  final double chartCeiling;

  /// Vertical position (0–100, from the bottom) of the 7-hour target line.
  final double targetHeightPercent;

  final List<String> transcripts;

  int get count => entries.length;

  bool get isEmpty => entries.isEmpty;

  /// Builds the window from all records.
  ///
  /// [allEntries] must be ordered newest first, matching the query order; the
  /// window takes the most recent [StatsPeriod.days] *records*, exactly like the
  /// prototype's `records.slice(0, period)`.
  factory SleepStatistics.from({
    required List<SleepEntry> allEntries,
    required StatsPeriod period,
  }) {
    final window = allEntries.take(period.days).toList();

    if (window.isEmpty) {
      return SleepStatistics(
        period: period,
        entries: const [],
        averageHours: null,
        averageScore: null,
        goodNights: 0,
        snoreNights: 0,
        talkNights: 0,
        chartFloor: 5,
        chartCeiling: 9,
        targetHeightPercent: 50,
        transcripts: const [],
      );
    }

    final totalHours =
        window.fold<double>(0, (sum, e) => sum + e.durationHours);
    final averageHours = totalHours / window.length;

    final scored = window.where((e) => e.score != null).toList();
    final averageScore = scored.isEmpty
        ? null
        : (scored.fold<int>(0, (sum, e) => sum + e.score!) / scored.length)
            .round();

    final durations = window.map((e) => e.durationHours);
    final minDuration = durations.reduce((a, b) => a < b ? a : b);
    final maxDuration = durations.reduce((a, b) => a > b ? a : b);

    // The axis always covers at least 5–9h so a single short or long night does
    // not zoom the chart into a meaningless range.
    final floor = minDuration < 5 ? minDuration.floorToDouble() : 5.0;
    final ceiling = maxDuration > 9 ? maxDuration.ceilToDouble() : 9.0;
    final range = ceiling - floor;

    return SleepStatistics(
      period: period,
      entries: window.reversed.toList(),
      averageHours: averageHours,
      averageScore: averageScore,
      goodNights: window.where((e) => e.durationHours >= 7).length,
      snoreNights: window.where((e) => e.hasSnore).length,
      talkNights: window.where((e) => e.hasTalk).length,
      chartFloor: floor,
      chartCeiling: ceiling,
      targetHeightPercent:
          range == 0 ? 50 : (((7 - floor) / range) * 100).clamp(0, 100),
      transcripts: [
        for (final entry in window)
          ...entry.talkClipsWithTranscript.map((clip) => clip.transcript!),
      ],
    );
  }

  /// Bar height (0–100) for an entry, clamped so tiny values stay visible.
  double barPercentFor(SleepEntry entry) {
    final range = chartCeiling - chartFloor;
    if (range <= 0) return 100;
    final raw = ((entry.durationHours - chartFloor) / range) * 100;
    return raw.clamp(6, 100);
  }
}
