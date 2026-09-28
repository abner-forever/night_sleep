/// A single hypnogram segment.
///
/// Stage data only ever comes from a real source (an import or a recording), so
/// there is deliberately no "guess the stages from total duration" helper — the
/// spec forbids inventing stages the device never measured. A record with no
/// stages simply renders the stage blocks as absent.
library;

enum SleepStageType {
  awake('awake', '清醒'),
  light('light', '浅睡'),
  deep('deep', '深睡'),
  rem('rem', 'REM');

  const SleepStageType(this.id, this.label);

  /// Stable identifier used in persistence and imports.
  final String id;

  /// Chinese label shown in legends and charts.
  final String label;

  static SleepStageType? fromId(String id) {
    for (final stage in SleepStageType.values) {
      if (stage.id == id) return stage;
    }
    return null;
  }

  /// Relative bar height in the hypnogram, transcribed from the prototype's
  /// `hm` maps: `{ awake: 10, light: 35, deep: 80, rem: 58 }` on the detail
  /// sheet and `{ awake: 10, light: 40, deep: 100, rem: 70 }` on the hero card.
  double get barWeight => switch (this) {
        SleepStageType.awake => 10,
        SleepStageType.light => 40,
        SleepStageType.deep => 100,
        SleepStageType.rem => 70,
      };

  /// The three stages the design charts and legends care about. `awake` is
  /// plotted in the hypnogram but excluded from the summary legend.
  static const charted = [
    SleepStageType.deep,
    SleepStageType.light,
    SleepStageType.rem
  ];
}

class SleepStageSegment {
  const SleepStageSegment({
    required this.stage,
    required this.startAtUtc,
    required this.endAtUtc,
    this.source = 'import',
  });

  final SleepStageType stage;
  final DateTime startAtUtc;
  final DateTime endAtUtc;

  /// Provenance of the measurement, shown wherever stages are displayed.
  final String source;

  Duration get duration => endAtUtc.difference(startAtUtc);

  int get minutes => duration.inMinutes;

  /// Local wall-clock label used by the hypnogram tooltip, e.g. `23:35`.
  String timeLabel({DateTime? now}) {
    final local = startAtUtc.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}

/// Totals per stage, used by the detail sheet's percentage grid and the
/// legends under each hypnogram.
Map<SleepStageType, int> stageTotals(Iterable<SleepStageSegment> segments) {
  final totals = <SleepStageType, int>{};
  for (final segment in segments) {
    totals.update(
      segment.stage,
      (value) => value + segment.minutes,
      ifAbsent: () => segment.minutes,
    );
  }
  return totals;
}

/// Formats a minute count the way the prototype does: `2h35m`, `45m`, `3h`.
String formatStageMinutes(int minutes) {
  if (minutes < 60) return '${minutes}m';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '${hours}h' : '${hours}h${rest}m';
}
