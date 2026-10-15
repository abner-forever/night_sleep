import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

/// A night's sleep. Times are UTC instants plus the zone they were entered in,
/// so a record's instant survives a device time-zone change; every wall-clock
/// value shown in the UI is derived at read time.
class SleepRecords extends Table {
  TextColumn get id => text()();
  DateTimeColumn get startAtUtc => dateTime()();
  DateTimeColumn get endAtUtc => dateTime()();
  TextColumn get timeZoneId => text().withDefault(const Constant('UTC'))();

  /// 用户自评的主观质量，1–5。**可以为空**：睡眠会话结束时会就地评一次星，
  /// 用户跳过就是真的没有评分。为空时 `SleepEntry.scoreSource` 返回 `none`，
  /// 界面显示「未评分」，统计的平均分把它排除在外——绝不填一个占位值冒充。
  IntColumn get quality => integer().nullable()();

  TextColumn get notes => text().withDefault(const Constant(''))();
  TextColumn get tagsJson => text().withDefault(const Constant('[]'))();

  /// 取值：`manual`、`import`、`demo`，或由睡眠会话结束写入的 `session`。
  TextColumn get source => text().withDefault(const Constant('manual'))();

  // Self-reported disturbances. Stored because the on-device score is derived
  // from them; the score itself is never persisted, so it cannot go stale.
  BoolColumn get flaggedSnore => boolean().withDefault(const Constant(false))();
  BoolColumn get flaggedTalk => boolean().withDefault(const Constant(false))();
  BoolColumn get flaggedRestless =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get flaggedNightmare =>
      boolean().withDefault(const Constant(false))();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// A measured hypnogram segment. Rows exist only when a device actually
/// measured stages — the app never derives stages from total duration.
class SleepStageSegments extends Table {
  TextColumn get id => text()();
  TextColumn get recordId =>
      text().references(SleepRecords, #id, onDelete: KeyAction.cascade)();
  TextColumn get stage => text()();
  DateTimeColumn get startAtUtc => dateTime()();
  DateTimeColumn get endAtUtc => dateTime()();
  TextColumn get source => text().withDefault(const Constant('import'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// A recorded night-time sound. `transcript` and `analysis` stay null until a
/// real recogniser produced them, and [analysisStatus] records whether that
/// attempt succeeded.
class SoundClips extends Table {
  TextColumn get id => text()();
  TextColumn get recordId =>
      text().references(SleepRecords, #id, onDelete: KeyAction.cascade)();
  TextColumn get kind => text()();
  DateTimeColumn get startedAtUtc => dateTime()();
  IntColumn get durationMs => integer()();
  TextColumn get localUri => text().nullable()();
  TextColumn get transcript => text().nullable()();
  TextColumn get analysis => text().nullable()();
  TextColumn get analysisStatus =>
      text().withDefault(const Constant('pending'))();
  TextColumn get source => text().withDefault(const Constant('recording'))();

  /// 实测包络：归一化到 0–1、重采样到 `SoundClip.waveformBarCount` 条，存成 JSON 数组。
  ///
  /// 落库而不是读取时解码文件，因为片段被保留期限裁掉之后 `localUri` 就空了，
  /// 而**形状仍然是真的**——那张卡理应继续画得出波形，只是不再能回放。
  TextColumn get waveformEnvelope => text().nullable()();

  /// 用户听过并标注过这一段的时刻；`null` = 还没标过。
  ///
  /// 少这一列就没法把「用户标成了杂音」与「还没标过」分开：两者在 [kind] 里
  /// 都是 `'noise'`。界面据此把未标注的片段显示成「待标注」而不是「杂音」。
  DateTimeColumn get labeledAtUtc => dateTime().nullable()();

  /// 机器跑完声学分析后的判断，存 JSON：`{kind, margin, basis, atUtc}`。
  ///
  /// **它不写 [kind]。** `kind` 只由人写（见 `sound_event.dart` 文件头与规格 M3），
  /// 机器判断另存一列，界面以「自动」标明来源——两者混在一列里，就再也分不清
  /// 「用户听过说是打鼾」和「机器猜是打鼾」。
  ///
  /// `kind` 为 `null` 表示**机器看过但没把握**（弃权），这与整列为 `null`（从没分析过）
  /// 是两件事，必须分得开——同 [labeledAtUtc] 那条理由。
  ///
  /// 存 JSON 而不是拆成四列，是照 [waveformEnvelope] 与 `active_sessions.clip_journal`
  /// 的既有惯例：这几个字段永远一起读、一起写，且没有任何按它们检索的查询。
  TextColumn get autoAnalysis => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// A model-generated observation. Only written when a provider returned a
/// result; failures are kept with [status] = `failed` so they never read as
/// valid conclusions.
class Insights extends Table {
  TextColumn get id => text()();

  // 与 stages、clips 一样级联删除。少了它，`deleteDemoData` 会留下孤儿行，
  // 重装演示数据时再撞上 `demo-N-insight` 的主键冲突——异常从一个没有任何
  // handler 的事务里抛出去，用户看到的就是「点了这个按钮没反应」。
  //
  // 先 `.nullable()` 再 `.references(...)`：这是 drift 文档规定的顺序。
  TextColumn get recordId => text()
      .nullable()
      .references(SleepRecords, #id, onDelete: KeyAction.cascade)();
  TextColumn get kind => text().withDefault(const Constant('record_summary'))();
  TextColumn get content => text().nullable()();
  TextColumn get provider => text().nullable()();
  TextColumn get model => text().nullable()();
  IntColumn get score => integer().nullable()();
  DateTimeColumn get generatedAtUtc => dateTime()();
  TextColumn get status => text().withDefault(const Constant('unavailable'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// 当前正在进行的睡眠会话。
///
/// **单行表**：主键固定为 `'active'`，沿用 `AppSettings` 的 `id = 'default'` 约定。
/// 于是「同时存在两个会话」在结构上不可能发生，不需要任何判重逻辑。
///
/// 会话结束时会在一个事务里写一条 `SleepRecords` 并删掉这一行，因此这张表
/// 为空就等价于「当前没有会话在跑」。
class ActiveSessions extends Table {
  TextColumn get id => text()();

  /// 点「开始睡眠」的真实时刻。
  DateTimeColumn get startAtUtc => dateTime()();

  /// 录入时区，与 `SleepRecords` 同口径。
  TextColumn get timeZoneId => text().withDefault(const Constant('UTC'))();

  /// 设定的起床时间，距本地午夜的分钟数。**起床时间就是闹钟时间**，
  /// 一个值；[alarmEnabled] 只决定到点响不响。
  IntColumn get wakeMinutes => integer()();

  BoolColumn get alarmEnabled => boolean().withDefault(const Constant(false))();

  /// 选中并正在播放的助眠音效 id，`null` 表示没选。
  TextColumn get noiseId => text().nullable()();

  RealColumn get noiseVolume => real().withDefault(const Constant(0.5))();

  /// 选中的夜景氛围 id（见 `NightScene`）。`null` = 用默认的「流星夜」。
  ///
  /// 存 id 字符串而不是枚举序号，与 [noiseId] 同一条既有做法：读不到认识的 id 时
  /// 按默认处理，一行坏数据不至于让整个会话读不出来。
  TextColumn get sceneId => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();

  /// 进行中会话已经录到的片段清单，JSON 数组；没有则为 `null`。
  ///
  /// 片段必须在会话结束**之前**就有地方待着：`SoundClips.recordId` 是指向
  /// `SleepRecords` 的外键，而记录行要等「结束睡眠」才写。攒在内存里的话，
  /// App 被杀就等于整晚录音全丢，而这一行会话是活下来的——用户重启后照常能
  /// 结束这一晚。所以清单跟着会话行走：每录完一段更新一次，结束时在同一个
  /// 事务里落成真正的片段行，然后随这一行一起消失。
  TextColumn get clipJournal => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class AppSettings extends Table {
  TextColumn get id => text()();
  TextColumn get themeMode => text().withDefault(const Constant('system'))();
  IntColumn get sleepGoalMinutes =>
      integer().withDefault(const Constant(480))();

  BoolColumn get bedtimeReminderEnabled =>
      boolean().withDefault(const Constant(false))();
  IntColumn get bedtimeReminderMinutes => integer().nullable()();
  BoolColumn get wakeReminderEnabled =>
      boolean().withDefault(const Constant(false))();
  IntColumn get wakeReminderMinutes => integer().nullable()();

  BoolColumn get soundRecordingEnabled =>
      boolean().withDefault(const Constant(false))();

  BoolColumn get onboarded => boolean().withDefault(const Constant(false))();

  /// Selected insight provider and model. The API key is deliberately **not**
  /// stored here — the spec requires platform secure storage, which is a
  /// separate follow-up; keeping it out of SQLite prevents it leaking into
  /// exports and backups.
  TextColumn get insightProvider => text().nullable()();
  TextColumn get insightModel => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(
  tables: [
    SleepRecords,
    SleepStageSegments,
    SoundClips,
    Insights,
    ActiveSessions,
    AppSettings,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  static Future<AppDatabase> open() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File(path.join(directory.path, 'night_sleep.sqlite'));
    return AppDatabase(NativeDatabase.createInBackground(file));
  }

  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // v1 shipped records and settings only. Stages, clips and insights
            // are new tables; the flagged-event and onboarding columns are new
            // on existing tables.
            await m.createTable(sleepStageSegments);
            await m.createTable(soundClips);
            await m.createTable(insights);
            await m.addColumn(sleepRecords, sleepRecords.flaggedSnore);
            await m.addColumn(sleepRecords, sleepRecords.flaggedTalk);
            await m.addColumn(sleepRecords, sleepRecords.flaggedRestless);
            await m.addColumn(sleepRecords, sleepRecords.flaggedNightmare);
            await m.addColumn(appSettings, appSettings.soundRecordingEnabled);
            await m.addColumn(appSettings, appSettings.onboarded);
            await m.addColumn(appSettings, appSettings.insightProvider);
            await m.addColumn(appSettings, appSettings.insightModel);
          }
          if (from < 3) {
            // 重建 `insights`，补上它本来就该有的那条外键。
            //
            // 清孤儿必须排在重建之前：`alterTable` 会把现有行拷进新表，而迁移
            // 期间 `PRAGMA foreign_keys` 是关着的（`beforeOpen` 要等迁移跑完才
            // 把它打开，而 SQLite 从不会回头校验已经存在的行）。少了这一步，
            // 重建出来的表会宣称一条它自己的内容并不满足的约束。
            //
            // 它同时修好已经在现场损坏的库：清除过演示数据的应用里躺着
            // `demo-N-insight` 这些记录已经不在了的行，而重装它们就是一次主键
            // 冲突，会从 `main()` 里抛出来、抛在 `runApp` 之前。
            await customStatement(
              'DELETE FROM insights WHERE record_id IS NOT NULL '
              'AND record_id NOT IN (SELECT id FROM sleep_records)',
            );
            await m.alterTable(TableMigration(insights));
          }
          if (from < 4) {
            // 两件事一起做，因为它们同属 v4。
            //
            // `alterTable` 是**重建**：SQLite 不能原地改一列的可空性。这是本项目
            // 第一次重建一张有子表引用它的表（stages / clips / insights 都指向
            // `sleep_records`）。迁移期间 `PRAGMA foreign_keys` 是关着的
            // （`beforeOpen` 要等迁移跑完才打开），子表里存的 record_id 是文本
            // 值、重建前后不变，所以改名之后引用仍然成立——但这条必须有测试盯着，
            // v3 那次踩的就是同一类「顺序与开关状态」的坑。
            await m.createTable(activeSessions);
            await m.alterTable(TableMigration(sleepRecords));
          }
          // 下界不能省成 `from < 5`：`from < 4` 那条分支的 `createTable` 用的是
          // **当前**的表定义，从 v1/v2/v3 升上来的库里 `active_sessions` 一建出来
          // 就带着 `scene_id`，再加一次就是 `duplicate column name: scene_id`。
          // 只有真正停在 v4 的库才需要补这一列——它那张表是用 v4 的列集建的。
          if (from >= 4 && from < 5) {
            // 只加一列可空列，不重建表：SQLite 的 `ALTER TABLE ADD COLUMN` 支持
            // 可空列原地添加，与 v4 那次「改可空性必须重建」是两回事。
            await m.addColumn(activeSessions, activeSessions.sceneId);
          }
          // v6 的三列都是可空列，`ADD COLUMN` 原地加，不重建表。**两条下界必须
          // 分开写，它们是两个不同的理由：**
          //
          // `sound_clips` 从 v2 那次 `createTable` 之后**再没被重建过**，所以
          // 停在 v2 / v3 / v4 / v5 的库里这张表都是老样子，四者都要补列——
          // 只有 `from < 2` 排除在外：那一支的 `createTable(soundClips)` 用的是
          // **当前**表定义，一建出来就带着这两列，再加就是 `duplicate column name`。
          //
          // `active_sessions` 相反：它是 v4 才有的表，且 `from < 4` 那一支的
          // `createTable` 同样用当前定义。所以只有**真正停在 v4 或 v5** 的库需要补。
          //
          // 这里踩过一次：最初写成 `from >= 5 && from < 6`，那会让 v4 的库升级时
          // 整块跳过——而 v4→v5 那段只加 `scene_id`，没有任何一段会补上这三列，
          // 结果是升上来的库里根本没有这些列。`test/schema_migration_test.dart`
          // 的 `v4 → v6` 与 `v2 → v6` 两条就是钉这个的。
          if (from >= 2 && from < 6) {
            await m.addColumn(soundClips, soundClips.waveformEnvelope);
            await m.addColumn(soundClips, soundClips.labeledAtUtc);
          }
          if (from >= 4 && from < 6) {
            await m.addColumn(activeSessions, activeSessions.clipJournal);
          }
          // v7 同样只加一列可空列。下界照 v6 那条的理由：`sound_clips` 从 v2 建表之后
          // 再没被重建过，停在 v2–v6 的库都缺这一列；而 `from < 2` 那一支的
          // `createTable` 用的是当前定义，已经带着它了，再加就是 `duplicate column name`。
          if (from >= 2 && from < 7) {
            await m.addColumn(soundClips, soundClips.autoAnalysis);
          }
        },
        beforeOpen: (details) async {
          // Deleting a record must take its stages, clips and insights with it.
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  // ── Records ───────────────────────────────────────────────────────────────

  Stream<List<SleepRecord>> watchAllRecords() {
    return (select(sleepRecords)
          ..orderBy([(table) => OrderingTerm.desc(table.endAtUtc)]))
        .watch();
  }

  Future<List<SleepRecord>> allRecords() {
    return (select(sleepRecords)
          ..orderBy([(table) => OrderingTerm.desc(table.endAtUtc)]))
        .get();
  }

  Future<SleepRecord?> findRecord(String id) {
    return (select(sleepRecords)..where((table) => table.id.equals(id)))
        .getSingleOrNull();
  }

  Future<void> saveRecord(SleepRecordsCompanion record) async {
    await into(sleepRecords).insertOnConflictUpdate(record);
  }

  Future<void> deleteRecord(String id) async {
    await (delete(sleepRecords)..where((table) => table.id.equals(id))).go();
  }

  Future<void> deleteRecordsBySource(String source) async {
    await (delete(sleepRecords)..where((table) => table.source.equals(source)))
        .go();
  }

  // ── Stages ────────────────────────────────────────────────────────────────

  Future<List<SleepStageSegment>> stagesFor(String recordId) {
    return (select(sleepStageSegments)
          ..where((table) => table.recordId.equals(recordId))
          ..orderBy([(table) => OrderingTerm.asc(table.startAtUtc)]))
        .get();
  }

  /// Every stage row, grouped by record id — one query instead of N.
  Future<Map<String, List<SleepStageSegment>>> allStagesByRecord() async {
    final rows = await (select(sleepStageSegments)
          ..orderBy([(table) => OrderingTerm.asc(table.startAtUtc)]))
        .get();
    final grouped = <String, List<SleepStageSegment>>{};
    for (final row in rows) {
      grouped.putIfAbsent(row.recordId, () => []).add(row);
    }
    return grouped;
  }

  Future<void> replaceStages(
    String recordId,
    List<SleepStageSegmentsCompanion> stages,
  ) async {
    await transaction(() async {
      await (delete(sleepStageSegments)
            ..where((table) => table.recordId.equals(recordId)))
          .go();
      await batch((b) => b.insertAll(sleepStageSegments, stages));
    });
  }

  // ── Sound clips ───────────────────────────────────────────────────────────

  Future<Map<String, List<SoundClip>>> allClipsByRecord() async {
    final rows = await (select(soundClips)
          ..orderBy([(table) => OrderingTerm.asc(table.startedAtUtc)]))
        .get();
    final grouped = <String, List<SoundClip>>{};
    for (final row in rows) {
      grouped.putIfAbsent(row.recordId, () => []).add(row);
    }
    return grouped;
  }

  /// 片段表的变更流。`sleepEntriesProvider` 订阅它，否则新写入的片段不会让
  /// 详情页重读——那条 provider 原本只 watch 记录表。
  Stream<List<SoundClip>> watchAllClips() {
    return (select(soundClips)
          ..orderBy([(table) => OrderingTerm.asc(table.startedAtUtc)]))
        .watch();
  }

  /// 会话结束时把整晚的片段一次写进去。调用方负责包在事务里——记录行与片段行
  /// 必须同生共死。
  Future<void> insertClips(List<SoundClipsCompanion> rows) async {
    if (rows.isEmpty) return;
    await batch((b) => b.insertAll(soundClips, rows));
  }

  /// 用户听完之后标注一段。`kind` 与 `labeledAtUtc` 必须一起写：
  /// 只改 `kind` 会让「标成了杂音」与「还没标过」再也分不开。
  Future<void> updateClipLabel(
    String clipId, {
    required String kind,
    required DateTime labeledAtUtc,
  }) async {
    await (update(soundClips)..where((table) => table.id.equals(clipId))).write(
      SoundClipsCompanion(
        kind: Value(kind),
        labeledAtUtc: Value(labeledAtUtc),
      ),
    );
  }

  /// 机器分析完一段之后写回。`autoAnalysis` 与 `analysisStatus` 必须一起写：
  /// 只写其一，界面就没法把「机器看过、没把握」（payload 里 `kind` 为 null）
  /// 与「从没分析过」（整列为 null、状态还是 pending）分开。
  ///
  /// **它不碰 [SoundClips.kind]，也不碰 [SoundClips.labeledAtUtc]。** 用户标过的
  /// 那一段，机器照样可以写下自己的看法——那是一条「机器当初猜的是这个」的记录，
  /// 只是界面上永远让位于人标的那个词。
  Future<void> updateClipAutoAnalysis(
    String clipId, {
    required String? payload,
    required String status,
  }) async {
    await (update(soundClips)..where((table) => table.id.equals(clipId))).write(
      SoundClipsCompanion(
        autoAnalysis: Value(payload),
        analysisStatus: Value(status),
      ),
    );
  }

  /// 还没被机器看过的真实录音片段（含文件路径）。
  ///
  /// 冷启动补跑靠它：装上新版本之后，**用户手机上已经录好的那些片段**会被自动补上
  /// 分析，不需要他做任何事。演示数据不在此列（`source = 'demo'`），它们的
  /// `kind` / `labeledAtUtc` 本来就是示例数据的一部分。
  Future<List<SoundClip>> clipsAwaitingAnalysis() {
    return (select(soundClips)
          ..where((table) =>
              table.source.equals('recording') &
              table.analysisStatus.equals('pending') &
              table.localUri.isNotNull()))
        .get();
  }

  /// 全部真实录音的片段（不含演示数据），供保留期限清理与占用统计用。
  Future<List<SoundClip>> allRecordingClips() {
    return (select(soundClips)
          ..where((table) => table.source.equals('recording')))
        .get();
  }

  /// 某条记录名下的全部片段。
  ///
  /// **删记录之前必须先用它把文件路径读出来**：`record_id` 是带 `onDelete: cascade`
  /// 的外键，记录行一删，这些行就跟着没了，连带着 `localUri` 也再没人知道——磁盘上的
  /// 音频于是变成可能要等到下次冷启动才被扫掉的孤儿。
  Future<List<SoundClip>> clipsFor(String recordId) {
    return (select(soundClips)
          ..where((table) => table.recordId.equals(recordId)))
        .get();
  }

  /// 把指定片段的文件指针清空，**行本身保留**。
  ///
  /// 这正是 `SoundClips.localUri` 列注释早就写好的语义：音频被裁掉之后事件记录
  /// 还在，详情页如实显示「这段录音未保留在本地」，而不是那个片段凭空消失。
  Future<void> clearClipLocalUris(List<String> clipIds) async {
    if (clipIds.isEmpty) return;
    await (update(soundClips)..where((table) => table.id.isIn(clipIds)))
        .write(const SoundClipsCompanion(localUri: Value(null)));
  }

  /// 「删除全部录音」：删掉全部真实录音的片段行（演示片段随演示数据走）。
  Future<void> deleteAllRecordingClips() async {
    await (delete(soundClips)
          ..where((table) => table.source.equals('recording')))
        .go();
  }

  // ── Insights ──────────────────────────────────────────────────────────────

  /// One insight per record — drift derives the row class `Insight` from the
  /// `Insights` table, so this is the generated row type, not the domain model
  /// of the same name in `features/sleep/domain`.
  Future<Map<String, Insight>> allInsightsByRecord() async {
    final rows = await select(insights).get();
    final grouped = <String, Insight>{};
    for (final row in rows) {
      final recordId = row.recordId;
      if (recordId == null) continue;
      grouped[recordId] = row;
    }
    return grouped;
  }

  // ── Active session ────────────────────────────────────────────────────────

  /// 当前会话，没有则为 `null`。主键固定，所以最多一行。
  Future<ActiveSession?> activeSession() {
    return (select(activeSessions)..where((table) => table.id.equals('active')))
        .getSingleOrNull();
  }

  Stream<ActiveSession?> watchActiveSession() {
    return (select(activeSessions)..where((table) => table.id.equals('active')))
        .watchSingleOrNull();
  }

  Future<void> saveActiveSession(ActiveSessionsCompanion session) async {
    await into(activeSessions).insertOnConflictUpdate(session);
  }

  /// 只写传入的列。会话页每次调一个开关都走它，不必读-改-写整行。
  Future<void> updateActiveSession(ActiveSessionsCompanion values) async {
    await (update(activeSessions)..where((table) => table.id.equals('active')))
        .write(values);
  }

  Future<void> deleteActiveSession() async {
    await (delete(activeSessions)..where((table) => table.id.equals('active')))
        .go();
  }

  // ── Settings ──────────────────────────────────────────────────────────────

  Future<AppSetting> getSettings() async {
    final current = await (select(appSettings)
          ..where((table) => table.id.equals('default')))
        .getSingleOrNull();
    if (current != null) return current;
    // 首次读取就地补一行默认值。**必须是 `insertOrIgnore`**：这是「先读后插」，
    // 同一帧里两个读者（例如会话页读起床草稿与鼾声偏好那两处）都会看到「没有」，
    // 于是都去插——后一个撞 `UNIQUE constraint failed: app_settings.id` 直接抛。
    await into(appSettings).insert(
      const AppSettingsCompanion(id: Value('default')),
      mode: InsertMode.insertOrIgnore,
    );
    return (select(appSettings)..where((table) => table.id.equals('default')))
        .getSingle();
  }

  Stream<AppSetting> watchSettings() {
    return (select(appSettings)..where((table) => table.id.equals('default')))
        .watchSingleOrNull()
        .asyncMap((row) async => row ?? await getSettings());
  }

  Future<void> updateSettings(AppSettingsCompanion values) async {
    await getSettings();
    await (update(appSettings)..where((table) => table.id.equals('default')))
        .write(values);
  }

  /// 删掉全部属于用户的行：记录（级联带走 stages、clips，以及 schema v3 起的
  /// insights），外加任何从未挂到记录上的洞察。settings 行原样保留，好让偏好
  /// 设置熬过一次数据清空。供「删除全部本地数据」使用。
  Future<void> deleteAllUserData() async {
    await transaction(() async {
      await delete(sleepRecords).go();
      // 留作兜底，不与级联重复：外键只覆盖 `record_id` 指向一条真实存在的记录的
      // 洞察，`record_id` 为空的那类行任何级联都够不着。当前唯一的洞察写入方
      // `DemoSeed` 恒传 `record_id`，v3 之后外键又保证没有悬空引用，所以这一行
      // 并不必需——保留只为兜住将来可能出现的无主洞察。
      await delete(insights).go();
      // 残留的会话会在下次启动时凭空长出一条记录。
      await delete(activeSessions).go();
    });
  }

  /// Drops only bundled demo rows, leaving real entries untouched.
  Future<void> deleteDemoData() async {
    await (delete(sleepRecords)..where((table) => table.source.equals('demo')))
        .go();
  }
}

final databaseProvider = Provider<AppDatabase>((ref) {
  throw StateError('databaseProvider must be overridden in main');
});

final recordsProvider = StreamProvider<List<SleepRecord>>((ref) {
  return ref.watch(databaseProvider).watchAllRecords();
});

/// 片段表的变更流。
///
/// `sleepEntriesProvider` **确实订阅了它**（`sleep_repository.dart`）。记录表与片段表
/// 是两张表：只订阅记录表的话，标注一段录音、裁掉超期录音、或会话结束时写入片段，
/// 都不会让首页与统计重读，界面会挂着旧数据。调用方那几处 `ref.invalidate` 是第二道
/// 保险，不是唯一的一道。
final clipsProvider = StreamProvider<List<SoundClip>>((ref) {
  return ref.watch(databaseProvider).watchAllClips();
});

final recordProvider = FutureProvider.family<SleepRecord?, String>((ref, id) {
  return ref.watch(databaseProvider).findRecord(id);
});

final activeSessionWatchProvider = StreamProvider<ActiveSession?>((ref) {
  return ref.watch(databaseProvider).watchActiveSession();
});
