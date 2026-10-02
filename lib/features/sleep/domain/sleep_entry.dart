import 'sleep_insight.dart';
import 'sleep_quality.dart';
import 'sleep_score.dart';
import 'sleep_stage.dart';
import 'sound_event.dart';

/// Where a displayed score came from. The UI must say which, because a
/// rule-based estimate and a model finding carry different weight.
enum ScoreSource {
  /// No score available.
  none,

  /// Computed on-device from duration, self-rated quality and flagged events.
  onDeviceEstimate,

  /// Returned by a configured model provider.
  modelInsight,
}

/// A night's sleep, assembled from persisted rows.
///
/// Times are stored as UTC instants plus the originating zone (see
/// `SleepRecords`), so every wall-clock value here is derived at read time
/// rather than stored as a string. That keeps a record's instant stable when
/// the device changes time zone, which the spec calls out explicitly.
class SleepEntry {
  const SleepEntry({
    required this.id,
    required this.startAtUtc,
    required this.endAtUtc,
    required this.timeZoneId,
    required this.quality,
    this.notes = '',
    this.tags = const [],
    this.source = 'manual',
    this.loggedEvents = LoggedEvents.none,
    this.stages = const [],
    this.soundClips = const [],
    this.insight,
    required this.createdAtUtc,
    required this.updatedAtUtc,
  });

  final String id;
  final DateTime startAtUtc;
  final DateTime endAtUtc;
  final String timeZoneId;

  /// 用户自评的主观质量。`null` 表示**还没评过**（会话结束跳过了评星，
  /// 或用户还没到回顾页去评）。为空时这条记录不产生评分。
  final SleepQuality? quality;

  final String notes;
  final List<String> tags;

  /// 取值：`manual`（手动补录）、`import`（设备导入）、`demo`（内置示例），
  /// 或由睡眠会话结束写入的 `session`。
  final String source;

  /// Disturbances the user flagged while logging. Persisted because they are
  /// user-entered data and the on-device estimate is derived from them.
  final LoggedEvents loggedEvents;

  final List<SleepStageSegment> stages;
  final List<SoundClip> soundClips;
  final Insight? insight;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;

  // ── Derived timing ────────────────────────────────────────────────────────

  Duration get duration => endAtUtc.difference(startAtUtc);

  int get durationMinutes => duration.inMinutes;

  /// Fractional hours, the unit the design displays (e.g. `8.1`).
  double get durationHours => durationMinutes / 60;

  DateTime get wakeLocal => endAtUtc.toLocal();
  DateTime get bedtimeLocal => startAtUtc.toLocal();

  static String _hhmm(DateTime local) =>
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';

  String get bedtimeLabel => _hhmm(bedtimeLocal);

  String get wakeLabel => _hhmm(wakeLocal);

  /// Records are archived under the local date the user **woke up**, so a night
  /// spanning midnight belongs to one day. `YYYY-MM-DD`.
  String get dateLabel => '${wakeLocal.year.toString().padLeft(4, '0')}-'
      '${wakeLocal.month.toString().padLeft(2, '0')}-'
      '${wakeLocal.day.toString().padLeft(2, '0')}';

  /// `MM/DD`, the form used on record cards.
  String get shortDateLabel => '${wakeLocal.month.toString().padLeft(2, '0')}/'
      '${wakeLocal.day.toString().padLeft(2, '0')}';

  /// Day-of-month, used as the axis label on the statistics chart.
  String get dayLabel => wakeLocal.day.toString().padLeft(2, '0');

  /// The local calendar day this record counts toward.
  DateTime get archiveDay =>
      DateTime(wakeLocal.year, wakeLocal.month, wakeLocal.day);

  // ── Stage helpers ─────────────────────────────────────────────────────────

  bool get hasStages => stages.isNotEmpty;

  Map<SleepStageType, int> get totalsByStage => stageTotals(stages);

  int minutesFor(SleepStageType stage) => totalsByStage[stage] ?? 0;

  int get totalStageMinutes =>
      stages.fold(0, (sum, segment) => sum + segment.minutes);

  /// Percentage of measured stage time, or 0 when nothing was measured.
  int stagePercent(SleepStageType stage) {
    final total = totalStageMinutes;
    if (total == 0) return 0;
    return ((minutesFor(stage) / total) * 100).round();
  }

  // ── Sound helpers ─────────────────────────────────────────────────────────

  bool get hasSoundEvents => soundClips.isNotEmpty;

  bool get hasSnore =>
      soundClips.any((clip) => clip.kind == SoundEventKind.snore);

  bool get hasTalk =>
      soundClips.any((clip) => clip.kind == SoundEventKind.talk);

  List<SoundClip> get talkClipsWithTranscript => soundClips
      .where(
          (clip) => clip.kind == SoundEventKind.talk && clip.transcript != null)
      .toList();

  // ── Scoring ───────────────────────────────────────────────────────────────

  /// True when nothing was measured — no hypnogram, no audio. Only then does
  /// the design fall back to a rule-based estimate.
  bool get isManualEntry => !hasStages && !hasSoundEvents;

  ScoreSource get scoreSource {
    if (insight?.isUsable ?? false) return ScoreSource.modelInsight;
    // **未评分就没有评分。**
    //
    // 这一条必须排在 `isManualEntry` 之前：`estimateScore` 的质量项占 35 分权重，
    // 喂一个假值进去等于替用户打了分。为空的记录直接不给分，界面与统计里那两条
    // 既有的 `score != null` 分支会照着走。
    if (quality == null) return ScoreSource.none;
    if (isManualEntry) return ScoreSource.onDeviceEstimate;
    return ScoreSource.none;
  }

  /// The score to display, or null when none applies. A model insight wins over
  /// the local estimate; a record with measured data but no insight shows no
  /// score at all rather than inventing one.
  int? get score => switch (scoreSource) {
        ScoreSource.modelInsight => insight!.score,
        // `scoreSource` 已经在 quality 为空时返回 none，走到这里必然有值。
        ScoreSource.onDeviceEstimate =>
          estimateScore(durationHours, quality!, loggedEvents),
        ScoreSource.none => null,
      };

  /// Model-written summary. Null unless a provider actually produced one.
  String? get insightText =>
      insight?.isUsable ?? false ? insight!.content : null;

  /// Locally generated summary for manually logged nights, phrased as habit
  /// guidance. Null when the record has measured data.
  String? get estimatedSummary {
    if (scoreSource != ScoreSource.onDeviceEstimate) return null;
    return estimateSummary(
      durationHours,
      // 同 `score`：走到这里 quality 必然非空。
      quality!,
      loggedEvents,
      estimateScore(durationHours, quality!, loggedEvents),
    );
  }

  bool get isEstimated => scoreSource == ScoreSource.onDeviceEstimate;

  String get providerLabel => insight?.provider ?? '';
}
