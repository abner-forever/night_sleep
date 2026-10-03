import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Imported with a prefix because drift derives row classes with the same names
// as the domain models (`Insights` → `Insight`, `SoundClips` → `SoundClip`,
// `SleepStageSegments` → `SleepStageSegment`). The prefix keeps the two layers
// unambiguous at the boundary where they meet.
import '../../../core/database/app_database.dart' as db;
import '../domain/sleep_entry.dart';
import '../domain/sleep_insight.dart';
import '../domain/sleep_quality.dart';
import '../domain/sleep_score.dart';
import '../domain/sleep_stage.dart';
import '../domain/sound_event.dart';
import 'demo_seed.dart';

/// Reads persisted rows and assembles [SleepEntry] aggregates.
///
/// Widgets never touch the database directly; they observe [sleepEntriesProvider]
/// and get fully-formed domain objects, so the derived values (wall-clock
/// labels, wake-date archiving, stage totals) are computed in exactly one place.
class SleepRepository {
  SleepRepository(this._db);

  final db.AppDatabase _db;

  /// All records, newest first, with stages, clips and insights attached.
  Future<List<SleepEntry>> loadAll() async {
    final records = await _db.allRecords();
    if (records.isEmpty) return const [];

    // Three bulk queries rather than per-record lookups.
    final stages = await _db.allStagesByRecord();
    final clips = await _db.allClipsByRecord();
    final insights = await _db.allInsightsByRecord();

    return records
        .map(
          (row) => _toEntry(
            row,
            stages[row.id] ?? const [],
            clips[row.id] ?? const [],
            insights[row.id],
          ),
        )
        .toList();
  }

  SleepEntry _toEntry(
    db.SleepRecord row,
    List<db.SleepStageSegment> stageRows,
    List<db.SoundClip> clipRows,
    db.Insight? insightRow,
  ) {
    return SleepEntry(
      id: row.id,
      startAtUtc: row.startAtUtc,
      endAtUtc: row.endAtUtc,
      timeZoneId: row.timeZoneId,
      quality:
          row.quality == null ? null : SleepQuality.fromValue(row.quality!),
      notes: row.notes,
      tags: _decodeTags(row.tagsJson),
      source: row.source,
      loggedEvents: LoggedEvents(
        snore: row.flaggedSnore,
        talk: row.flaggedTalk,
        restless: row.flaggedRestless,
        nightmare: row.flaggedNightmare,
      ),
      stages: [
        for (final stage in stageRows)
          if (SleepStageType.fromId(stage.stage) case final type?)
            SleepStageSegment(
              stage: type,
              startAtUtc: stage.startAtUtc,
              endAtUtc: stage.endAtUtc,
              source: stage.source,
            ),
      ],
      soundClips: [
        for (final clip in clipRows)
          if (SoundEventKind.fromId(clip.kind) case final kind?)
            SoundClip(
              id: clip.id,
              kind: kind,
              startedAtUtc: clip.startedAtUtc,
              durationMs: clip.durationMs,
              localUri: clip.localUri,
              transcript: clip.transcript,
              analysis: clip.analysis,
              analysisStatus: SoundAnalysisStatus.fromId(clip.analysisStatus),
              source: clip.source,
              // 演示行整个是合成的（转写与睡眠阶段同样是示例），包络照旧现算。
              // 真实行的包络是采集时实测的，存在列里；读不到或读坏了就是 null，
              // 界面画等高轨道，绝不给它编一个形状。
              waveformEnvelope: clip.source == 'demo'
                  ? SoundClip.demoWaveformEnvelope(clip.id, kind)
                  : _decodeEnvelope(clip.waveformEnvelope),
              labeledAtUtc: clip.labeledAtUtc?.toUtc(),
            ),
      ],
      insight: insightRow == null
          ? null
          : Insight(
              id: insightRow.id,
              recordId: insightRow.recordId,
              kind: insightRow.kind,
              content: insightRow.content,
              provider: insightRow.provider,
              model: insightRow.model,
              score: insightRow.score,
              generatedAtUtc: insightRow.generatedAtUtc,
              status: InsightStatus.fromId(insightRow.status),
            ),
      createdAtUtc: row.createdAt,
      updatedAtUtc: row.updatedAt,
    );
  }

  static List<String> _decodeTags(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.whereType<String>().toList();
      }
    } on FormatException {
      // Corrupt tags should not make a record unreadable.
    }
    return const [];
  }

  /// Inserts or updates a record, inside one transaction so a failure cannot
  /// leave a half-written night behind.
  ///
  /// [stages] is nullable **on purpose**. `null` means "leave the hypnogram as
  /// it is", which is what correcting a hand-logged night needs: the form has no
  /// stage fields, so re-saving must not wipe stages that a real measurement
  /// put there. Pass a list — including an empty one — to replace them
  /// outright.
  ///
  /// `createdAt` is read back from the stored row rather than passed in, so an
  /// edit cannot silently rewrite when the night was first recorded.
  Future<void> save({
    required String id,
    required DateTime startAtUtc,
    required DateTime endAtUtc,
    required String timeZoneId,
    required SleepQuality? quality,
    required String notes,
    required LoggedEvents events,
    List<SleepStageSegment>? stages,
    String source = 'manual',
  }) async {
    final now = DateTime.now().toUtc();

    await _db.transaction(() async {
      final existing = await _db.findRecord(id);

      await _db.saveRecord(
        db.SleepRecordsCompanion(
          id: Value(id),
          startAtUtc: Value(startAtUtc),
          endAtUtc: Value(endAtUtc),
          timeZoneId: Value(timeZoneId),
          quality: Value(quality?.value),
          notes: Value(notes),
          tagsJson: const Value('[]'),
          source: Value(source),
          flaggedSnore: Value(events.snore),
          flaggedTalk: Value(events.talk),
          flaggedRestless: Value(events.restless),
          flaggedNightmare: Value(events.nightmare),
          createdAt: Value(existing?.createdAt ?? now),
          updatedAt: Value(now),
        ),
      );

      if (stages == null) return;

      await _db.replaceStages(id, [
        for (var i = 0; i < stages.length; i++)
          db.SleepStageSegmentsCompanion(
            id: Value('$id-stage-$i'),
            recordId: Value(id),
            stage: Value(stages[i].stage.id),
            startAtUtc: Value(stages[i].startAtUtc),
            endAtUtc: Value(stages[i].endAtUtc),
            source: Value(stages[i].source),
          ),
      ]);
    });
  }

  /// Stores a model-written summary, replacing whatever the record had.
  ///
  /// The row id is derived from the record id — the same convention
  /// `demo_seed.dart` uses — so one record can only ever hold one insight and
  /// a regenerate is an upsert rather than a second row that
  /// `allInsightsByRecord` would then pick between arbitrarily.
  ///
  /// Failures are deliberately **not** written: a bad request must not erase a
  /// good insight the user already had. See 偏差 #47.
  Future<void> saveInsight({
    required String recordId,
    required String content,
    required String provider,
    required String model,
    int? score,
    required DateTime generatedAtUtc,
  }) {
    return _db.into(_db.insights).insertOnConflictUpdate(
          db.InsightsCompanion(
            id: Value('$recordId-insight'),
            recordId: Value(recordId),
            kind: const Value('record_summary'),
            content: Value(content),
            provider: Value(provider),
            model: Value(model),
            score: Value(score),
            generatedAtUtc: Value(generatedAtUtc.toUtc()),
            status: Value(InsightStatus.ok.id),
          ),
        );
  }

  Future<void> delete(String id) => _db.deleteRecord(id);

  Future<void> deleteDemoData() => _db.deleteDemoData();

  /// Re-seeds the bundled sample nights.
  ///
  /// Without this the only way back to the demo data is 「删除全部本地数据」 and a
  /// restart, which also throws away the user's own records — a steep price for
  /// wanting the samples back.
  Future<void> installDemoData() => DemoSeed.install(_db);

  Future<void> deleteAllUserData() => _db.deleteAllUserData();
}

/// 把 `sound_clips.waveform_envelope` 里的 JSON 数组读成包络。
///
/// **读不出来就是 `null`，不是抛异常、也不是补一个形状。** 这一列有可能是旧版本
/// 留下的、写了一半的、或者被手工改坏的；一行坏数据不该让整晚的睡眠详情打不开，
/// 而补一个编出来的包络等于把「没测量」说成「测量过了」。
List<double>? _decodeEnvelope(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return null;
  }
  if (decoded is! List) return null;
  final bars = <double>[];
  for (final bar in decoded) {
    if (bar is! num) return null;
    bars.add(bar.toDouble());
  }
  return bars.isEmpty ? null : bars;
}

final sleepRepositoryProvider = Provider<SleepRepository>((ref) {
  return SleepRepository(ref.watch(db.databaseProvider));
});

/// Every entry, newest first. The single source the UI reads from.
final sleepEntriesProvider = FutureProvider<List<SleepEntry>>((ref) async {
  // 记录表变了要重读。
  ref.watch(db.recordsProvider);
  // **片段表变了也要重读。** 它是另一张表：标注一段录音（`updateClipLabel`）、
  // 保留期限裁掉超期录音（`clearClipLocalUris`）、「删除全部录音」
  // （`deleteAllRecordingClips`）都不碰 `sleep_records`，只 watch 记录表的话，
  // 这几件事做完首页与详情页还挂着旧数据。调用方那几处 `ref.invalidate` 是第二道
  // 保险，不该是唯一的一道。
  ref.watch(db.clipsProvider);
  return ref.watch(sleepRepositoryProvider).loadAll();
});
