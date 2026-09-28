import 'sleep_quality.dart';

/// Disturbances the user can flag when logging a night by hand.
///
/// These are self-reported, so they legitimately feed the local estimate — they
/// are not inferred from audio.
class LoggedEvents {
  const LoggedEvents({
    this.snore = false,
    this.talk = false,
    this.restless = false,
    this.nightmare = false,
  });

  final bool snore;
  final bool talk;
  final bool restless;
  final bool nightmare;

  static const none = LoggedEvents();

  bool get any => snore || talk || restless || nightmare;

  LoggedEvents copyWith({
    bool? snore,
    bool? talk,
    bool? restless,
    bool? nightmare,
  }) {
    return LoggedEvents(
      snore: snore ?? this.snore,
      talk: talk ?? this.talk,
      restless: restless ?? this.restless,
      nightmare: nightmare ?? this.nightmare,
    );
  }

  /// Labels of the flagged events, in the prototype's display order.
  List<String> get flaggedLabels => [
        if (snore) '打鼾',
        if (talk) '梦话',
        if (restless) '辗转难眠',
        if (nightmare) '噩梦',
      ];
}

/// Severity band for a night's duration. The colour mapping lives in the
/// presentation layer so this stays a pure function.
enum DurationBand { healthy, slightlyShort, short }

/// Band for a 0–100 sleep score.
enum ScoreBand { excellent, good, fair, poor }

/// Colour cue for a duration, per the prototype's `durationColor`:
/// `>= 7h` healthy, `>= 6h` caution, otherwise short.
DurationBand durationBand(double hours) {
  if (hours >= 7) return DurationBand.healthy;
  if (hours >= 6) return DurationBand.slightlyShort;
  return DurationBand.short;
}

/// Colour cue for a score, per the prototype's `scoreColor`.
ScoreBand scoreBand(num score) {
  if (score >= 85) return ScoreBand.excellent;
  if (score >= 70) return ScoreBand.good;
  if (score >= 55) return ScoreBand.fair;
  return ScoreBand.poor;
}

/// Rule-based 0–100 score for a **manually logged** night.
///
/// Manual entries have no hypnogram and no audio, so the prototype scores them
/// on-device from duration, self-rated quality and flagged events. This is a
/// deterministic rule, not a model inference, which is why the UI labels the
/// result 「本地估算」 rather than presenting it as an AI finding.
///
/// Weights transcribed from the prototype: duration up to 45 points, quality up
/// to 35, and events starting from 20 with deductions.
///
/// Note on fidelity: the prototype's duration ladder checks `>= 6` *before*
/// `> 9`, so its `> 9` decay branch is unreachable — a 10-hour night scores
/// 81/45 on that term, contradicting the adjacent comment ("peaking in the 7–9h
/// healthy band"). This implementation follows the documented intent, so nights
/// longer than 9 hours decay instead of outscoring the healthy band. This is a
/// deliberate deviation; revert by moving the `> 9` case above `>= 6`.
int estimateScore(
    double durationHours, SleepQuality quality, LoggedEvents events) {
  final double durationPoints;
  if (durationHours >= 7 && durationHours <= 9) {
    durationPoints = 45;
  } else if (durationHours > 9) {
    durationPoints = _max(28, 45 - (durationHours - 9) * 8);
  } else if (durationHours >= 6) {
    durationPoints = 33 + (durationHours - 6) * 12;
  } else if (durationHours >= 5) {
    durationPoints = 20 + (durationHours - 5) * 13;
  } else {
    durationPoints = _max(0, (durationHours / 5) * 20);
  }

  final qualityPoints = ((quality.value - 1) / 4) * 35;

  var eventPoints = 20.0;
  if (events.snore) eventPoints -= 4;
  if (events.talk) eventPoints -= 3;
  if (events.restless) eventPoints -= 7;
  if (events.nightmare) eventPoints -= 6;

  final total = durationPoints + qualityPoints + _max(0, eventPoints);
  return total.clamp(0, 100).round();
}

/// Human-readable companion to [estimateScore], following the prototype's
/// `estimateSummary` sentence order. Phrased as habit guidance, never as a
/// medical conclusion.
String estimateSummary(
  double durationHours,
  SleepQuality quality,
  LoggedEvents events,
  int score,
) {
  final hours = durationHours.toStringAsFixed(1);
  final parts = <String>[];

  if (durationHours >= 7) {
    parts.add('睡眠时长 $hours 小时，处于健康区间。');
  } else if (durationHours >= 6) {
    parts.add('睡眠时长 $hours 小时，略显不足，建议尽量达到 7 小时。');
  } else {
    parts.add('睡眠时长仅 $hours 小时，明显不足，注意补觉与规律作息。');
  }

  final flagged = events.flaggedLabels;
  if (flagged.isNotEmpty) {
    parts.add('记录到 ${flagged.join('、')}，可留意近期压力与睡前习惯。');
  } else {
    parts.add('未记录到明显干扰事件。');
  }

  if (score >= 85) {
    parts.add('主观感受良好，保持当前节律。');
  } else if (score >= 70) {
    parts.add('整体尚可，作息可进一步稳定。');
  } else {
    parts.add('建议提前就寝、减少睡前蓝光。');
  }

  return parts.join();
}

double _max(double a, double b) => a > b ? a : b;
