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

  DateTimeColumn get createdAt => dateTime()();

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
  int get schemaVersion => 4;

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
    await into(appSettings)
        .insert(const AppSettingsCompanion(id: Value('default')));
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

final recordProvider = FutureProvider.family<SleepRecord?, String>((ref, id) {
  return ref.watch(databaseProvider).findRecord(id);
});

final activeSessionWatchProvider = StreamProvider<ActiveSession?>((ref) {
  return ref.watch(databaseProvider).watchActiveSession();
});
