import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../../../core/config/app_config.dart';
import '../../../core/database/app_database.dart';
import '../domain/sleep_stage.dart';
import '../domain/sound_event.dart';

/// 需要时安装演示数据，任何失败都只记录、不外抛。
///
/// 由 `main()` 在 `runApp` **之前**调用，所以这里不能往外抛：一次写入失败
/// （残留行撞主键、库文件损坏、磁盘写满）会一路冒到 `runApp` 之前，
/// 屏幕上什么都留不下——用户既看不到首页，也没有任何可上报的现象。
/// 一个空首页是用户能上报的 bug；一次死在这里的启动不是。
///
/// 判据是「还没有演示行」而不是「表是空的」，这样后开开关才真的生效。
/// 已有的真实记录一律不碰：演示行带 `source = 'demo'`，界面会标注它们，
/// 而 `deleteDemoData` 只删这些行。
///
/// 抽成顶层函数是为了能被测到——`main()` 在测试里跑不起来，而这条路径的
/// 全部价值就在于「失败时仍然不抛」。
Future<void> installDemoSeedIfNeeded(
  AppDatabase database, {
  required bool enabled,
}) async {
  if (!enabled) return;

  try {
    final existing = await database.allRecords();
    final hasDemo = existing.any((row) => row.source == AppConfig.demoSource);
    if (hasDemo) return;
    await DemoSeed.install(database);
  } on Object catch (error, stack) {
    debugPrint('演示数据安装失败，应用继续启动：$error\n$stack');
  }
}

/// The prototype's bundled sample nights, used so the UI can be built and
/// reviewed against realistic data.
///
/// Two properties matter here:
///
/// * Everything is written with `source = 'demo'`, so [AppDatabase.deleteDemoData]
///   can remove it and the UI can badge it. Demo rows never masquerade as real
///   measurements.
/// * Stage segments are laid out cumulatively from bedtime. The prototype
///   lists a wall-clock time per segment, and adding the listed minutes in
///   sequence reproduces those times exactly (each night's segments sum to its
///   recorded duration), so the hypnogram stays contiguous instead of inheriting
///   any drift between the listed clock values.
class DemoSeed {
  const DemoSeed._();

  static Future<void> install(AppDatabase db, {DateTime? now}) async {
    final reference = now ?? DateTime.now();

    await db.transaction(() async {
      // 每一次写入都是 upsert。record 本来如此；stages、clips 和 insights 却不是，
      // 于是在有残留行时重装会撞主键，整个事务回滚——而且是静默的，因为调用方没有
      // 处理函数。真正的修复是让写入幂等；schema v3 补的外键只是除掉了产生残留的
      // 其中一条路径。
      for (var i = 0; i < _nights.length; i++) {
        final night = _nights[i];
        final id = 'demo-${i + 1}';
        final window = _resolveWindow(night, reference);

        await db.saveRecord(
          SleepRecordsCompanion(
            id: Value(id),
            startAtUtc: Value(window.start.toUtc()),
            endAtUtc: Value(window.end.toUtc()),
            timeZoneId: Value(window.zoneId),
            quality: Value(night.quality),
            notes: Value(night.notes),
            tagsJson: const Value('[]'),
            source: const Value(AppConfig.demoSource),
            createdAt: Value(reference.toUtc()),
            updatedAt: Value(reference.toUtc()),
          ),
        );

        // Walk the stage list forward from bedtime.
        var cursor = window.start;
        final stageRows = <SleepStageSegmentsCompanion>[];
        for (var s = 0; s < night.stages.length; s++) {
          final (stage, minutes) = night.stages[s];
          final end = cursor.add(Duration(minutes: minutes));
          stageRows.add(
            SleepStageSegmentsCompanion(
              id: Value('$id-stage-$s'),
              recordId: Value(id),
              stage: Value(stage.id),
              startAtUtc: Value(cursor.toUtc()),
              endAtUtc: Value(end.toUtc()),
              source: const Value(AppConfig.demoSource),
            ),
          );
          cursor = end;
        }
        await db.batch(
          (b) => b.insertAllOnConflictUpdate(db.sleepStageSegments, stageRows),
        );

        for (var c = 0; c < night.clips.length; c++) {
          final clip = night.clips[c];
          final startedAt = _clockWithin(window, clip.time);
          await db.into(db.soundClips).insertOnConflictUpdate(
                SoundClipsCompanion(
                  id: Value('$id-clip-$c'),
                  recordId: Value(id),
                  kind: Value(clip.kind.id),
                  startedAtUtc: Value(startedAt.toUtc()),
                  durationMs: Value(clip.seconds * 1000),
                  transcript: Value(clip.transcript),
                  analysis: Value(clip.analysis),
                  analysisStatus: Value(clip.analysis == null
                      ? SoundAnalysisStatus.pending.id
                      : SoundAnalysisStatus.analysed.id),
                  source: const Value(AppConfig.demoSource),
                ),
              );
        }

        await db.into(db.insights).insertOnConflictUpdate(
              InsightsCompanion(
                id: Value('$id-insight'),
                recordId: Value(id),
                kind: const Value('record_summary'),
                content: Value(night.summary),
                provider: const Value(AppConfig.demoSource),
                model: const Value('demo'),
                score: Value(night.score),
                generatedAtUtc: Value(reference.toUtc()),
                status: const Value('ok'),
              ),
            );
      }
    });
  }

  /// Resolves a night to a concrete local window.
  ///
  /// The wake date is the **archive** date, matching how records are grouped.
  /// Bedtime falls on the previous day when its clock time is later than the
  /// wake time, which keeps `00:30 → 07:00` on one day while `23:15 → 07:20`
  /// crosses midnight.
  static _Window _resolveWindow(_DemoNight night, DateTime reference) {
    final today = DateTime(reference.year, reference.month, reference.day);
    final wakeDay = today.subtract(Duration(days: night.wakeOffsetDays));
    final end = _atClock(wakeDay, night.wakeTime);
    var start = _atClock(wakeDay, night.bedtime);
    if (!start.isBefore(end)) {
      start = start.subtract(const Duration(days: 1));
    }
    return _Window(start: start, end: end, zoneId: reference.timeZoneName);
  }

  /// First occurrence of a `HH:mm` clock time inside the sleep window.
  static DateTime _clockWithin(_Window window, String clock) {
    var candidate = _atClock(
      DateTime(window.start.year, window.start.month, window.start.day),
      clock,
    );
    while (candidate.isBefore(window.start)) {
      candidate = candidate.add(const Duration(days: 1));
    }
    return candidate;
  }

  static DateTime _atClock(DateTime day, String clock) {
    final parts = clock.split(':');
    return DateTime(
      day.year,
      day.month,
      day.day,
      int.parse(parts[0]),
      int.parse(parts[1]),
    );
  }

  // The dates are fixed offsets from "today" at install time so the sample
  // always looks recent, preserving the prototype's spacing of consecutive
  // nights.
  static final List<_DemoNight> _nights = [
    _DemoNight(
      wakeOffsetDays: 1,
      bedtime: '23:15',
      wakeTime: '07:20',
      quality: 4,
      notes: '做了个奇怪的梦',
      stages: const [
        (SleepStageType.light, 20),
        (SleepStageType.deep, 75),
        (SleepStageType.rem, 25),
        (SleepStageType.light, 15),
        (SleepStageType.deep, 60),
        (SleepStageType.rem, 30),
        (SleepStageType.light, 20),
        (SleepStageType.deep, 55),
        (SleepStageType.rem, 35),
        (SleepStageType.light, 30),
        (SleepStageType.deep, 40),
        (SleepStageType.rem, 40),
        (SleepStageType.light, 40),
      ],
      clips: const [
        _DemoClip(
          kind: SoundEventKind.snore,
          time: '01:20',
          seconds: 45,
          analysis: '轻度打鼾，持续约45秒，呼吸节律正常，无呼吸暂停迹象。',
        ),
        _DemoClip(
          kind: SoundEventKind.talk,
          time: '03:05',
          seconds: 12,
          transcript: '「不对……那个……放在那里……」',
          analysis: '梦话发生在深睡向REM过渡阶段，内容片段化，情绪平静，与日间记忆整合有关。',
        ),
        _DemoClip(
          kind: SoundEventKind.snore,
          time: '05:40',
          seconds: 28,
          analysis: '轻微鼾声，建议侧卧改善。',
        ),
      ],
      score: 82,
      summary: '睡眠结构良好，深睡眠占比27%，高于健康均值。检测到2次轻度打鼾、1次梦话，整体质量优秀。建议保持当前作息规律。',
    ),
    _DemoNight(
      wakeOffsetDays: 2,
      bedtime: '00:30',
      wakeTime: '07:00',
      quality: 3,
      notes: '入睡困难',
      stages: const [
        (SleepStageType.light, 40),
        (SleepStageType.deep, 45),
        (SleepStageType.rem, 20),
        (SleepStageType.light, 30),
        (SleepStageType.deep, 40),
        (SleepStageType.rem, 25),
        (SleepStageType.light, 50),
        (SleepStageType.deep, 35),
        (SleepStageType.rem, 30),
        (SleepStageType.light, 75),
      ],
      clips: const [
        _DemoClip(
          kind: SoundEventKind.talk,
          time: '02:30',
          seconds: 8,
          transcript: '「等一下……不要走……」',
          analysis: '梦话出现在REM阶段，含情绪色彩词汇，可能反映白天情绪压力。',
        ),
      ],
      score: 64,
      summary: '入睡偏晚，深睡眠仅21%。建议提前30分钟就寝，减少蓝光暴露。',
    ),
    _DemoNight(
      wakeOffsetDays: 3,
      bedtime: '22:45',
      wakeTime: '06:45',
      quality: 5,
      notes: '非常满意',
      stages: const [
        (SleepStageType.light, 15),
        (SleepStageType.deep, 90),
        (SleepStageType.rem, 30),
        (SleepStageType.light, 20),
        (SleepStageType.deep, 70),
        (SleepStageType.rem, 40),
        (SleepStageType.deep, 60),
        (SleepStageType.rem, 45),
        (SleepStageType.light, 30),
        (SleepStageType.rem, 50),
        (SleepStageType.light, 30),
      ],
      clips: const [],
      score: 96,
      summary: '近期最佳睡眠！深睡充足，REM丰富，全程无异常声音。睡眠效率98%。',
    ),
    _DemoNight(
      wakeOffsetDays: 4,
      bedtime: '01:00',
      wakeTime: '08:30',
      quality: 3,
      notes: '',
      stages: const [
        (SleepStageType.light, 35),
        (SleepStageType.deep, 50),
        (SleepStageType.rem, 25),
        (SleepStageType.light, 40),
        (SleepStageType.deep, 45),
        (SleepStageType.rem, 30),
        (SleepStageType.light, 55),
        (SleepStageType.deep, 40),
        (SleepStageType.rem, 35),
        (SleepStageType.light, 95),
      ],
      clips: const [
        _DemoClip(
          kind: SoundEventKind.snore,
          time: '03:15',
          seconds: 62,
          analysis: '中度打鼾，持续1分钟，建议就医排查睡眠呼吸问题。',
        ),
      ],
      score: 71,
      summary: '睡眠时长达标，但入睡偏晚。检测到1次中度打鼾，建议关注。',
    ),
    _DemoNight(
      wakeOffsetDays: 5,
      bedtime: '23:00',
      wakeTime: '06:30',
      quality: 4,
      notes: '感觉不错',
      stages: const [
        (SleepStageType.light, 18),
        (SleepStageType.deep, 80),
        (SleepStageType.rem, 28),
        (SleepStageType.light, 15),
        (SleepStageType.deep, 65),
        (SleepStageType.rem, 35),
        (SleepStageType.deep, 55),
        (SleepStageType.rem, 40),
        (SleepStageType.light, 30),
        (SleepStageType.rem, 44),
        (SleepStageType.light, 40),
      ],
      clips: const [],
      score: 88,
      summary: '睡眠质量优秀，深睡与REM分布均衡，全程无异常声音。',
    ),
  ];
}

class _DemoNight {
  _DemoNight({
    required this.wakeOffsetDays,
    required this.bedtime,
    required this.wakeTime,
    required this.quality,
    required this.notes,
    required this.stages,
    required this.clips,
    required this.score,
    required this.summary,
  });

  /// Days before today that this night's wake-up fell on.
  final int wakeOffsetDays;
  final String bedtime;
  final String wakeTime;
  final int quality;
  final String notes;
  final List<(SleepStageType, int)> stages;
  final List<_DemoClip> clips;
  final int score;
  final String summary;
}

class _DemoClip {
  const _DemoClip({
    required this.kind,
    required this.time,
    required this.seconds,
    this.transcript,
    this.analysis,
  });

  final SoundEventKind kind;
  final String time;
  final int seconds;
  final String? transcript;
  final String? analysis;
}

class _Window {
  const _Window({required this.start, required this.end, required this.zoneId});

  final DateTime start;
  final DateTime end;
  final String zoneId;
}
