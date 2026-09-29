import 'dart:io';

// The whole library with two names held back, rather than a `show` list: the
// fixtures below drive `customStatement`, `TableMigration`-free migrations and
// the real [AppDatabase] at once, so naming every symbol they reach would be a
// running battle. `isNull` / `isNotNull` are the only collisions with
// `flutter_test`'s matchers, and both are still used as matchers below.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/core/database/app_database.dart';
import 'package:night_sleep/features/sleep/data/sleep_repository.dart';
import 'package:path/path.dart' as p;

/// Upgrading a **real** database file — one written by v1, one written by v2 —
/// to the current schema.
///
/// The other data tests all start from `NativeDatabase.memory()`, which drift
/// creates at the current schema version — so none of them ever execute the
/// `onUpgrade` branch. These fixtures build an older file first and then open
/// the real [AppDatabase] on top of it, which is the only way the migration
/// runs the way it does on a user's device.
///
/// A migration bug here is not a cosmetic one: `onUpgrade` runs while the user
/// is opening the app, so a wrong column name or a missing table makes the app
/// fail to start and the existing records unreachable.
void main() {
  late Directory tempDir;
  late File file;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('night_sleep_migration');
    file = File(p.join(tempDir.path, 'night_sleep.sqlite'));
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  /// Writes a v1 database containing one night and one settings row, and closes
  /// it so the file is left exactly as the shipped app would have left it.
  Future<void> writeV1Database({
    String source = 'manual',
    bool includeSettings = true,
  }) async {
    final v1 = _V1Database(NativeDatabase(file));
    try {
      await v1.customStatement(
        'INSERT INTO sleep_records '
        '(id, start_at_utc, end_at_utc, time_zone_id, quality, notes, '
        ' tags_json, source, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          'v1-night',
          _epoch(_bedtime),
          _epoch(_wakeTime),
          'Asia/Shanghai',
          4,
          'v1 时期写的备注',
          '["旧标签"]',
          source,
          _epoch(_bedtime),
          _epoch(_bedtime),
        ],
      );
      if (includeSettings) {
        await v1.customStatement(
          'INSERT INTO app_settings '
          '(id, theme_mode, sleep_goal_minutes, bedtime_reminder_enabled, '
          ' bedtime_reminder_minutes, wake_reminder_enabled, '
          ' wake_reminder_minutes) '
          'VALUES (?, ?, ?, ?, ?, ?, ?)',
          ['default', 'dark', 450, 1, 1350, 1, 420],
        );
      }
    } finally {
      await v1.close();
    }
  }

  /// Opens the **current** schema on top of whatever `file` already holds.
  ///
  /// The name says current rather than v2 on purpose: this helper predates the
  /// v2→v3 work, and hard-coding a version here would go stale — and read as a
  /// lie — the moment `schemaVersion` moves again.
  AppDatabase openCurrent() => AppDatabase(NativeDatabase(file));

  Future<int> userVersion(GeneratedDatabase db) async {
    final row = await db.customSelect('PRAGMA user_version').getSingle();
    return row.read<int>('user_version');
  }

  /// Writes a v2 database in the shape the shipped app left behind after
  /// 「清除演示数据」: one surviving night with its insight, plus an insight whose
  /// record is already gone (`demo-9` — the demo rows were deleted, the insight
  /// was not, because v2's `insights.record_id` had no foreign key).
  ///
  /// It closes the file afterwards so the upgrade runs against exactly the bytes
  /// a user's device would hand it.
  Future<void> writeV2DatabaseWithOrphans() async {
    final v2 = _V2Database(NativeDatabase(file));
    try {
      await v2.customStatement(
        'INSERT INTO sleep_records '
        '(id, start_at_utc, end_at_utc, time_zone_id, quality, notes, '
        ' tags_json, source, flagged_snore, flagged_talk, flagged_restless, '
        ' flagged_nightmare, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          'v1-night',
          _epoch(_bedtime),
          _epoch(_wakeTime),
          'Asia/Shanghai',
          4,
          'v2 时期写的备注',
          '[]',
          'manual',
          0,
          0,
          0,
          0,
          _epoch(_bedtime),
          _epoch(_bedtime),
        ],
      );
      await v2.customStatement(
        'INSERT INTO insights '
        '(id, record_id, kind, content, provider, model, score, '
        ' generated_at_utc, status) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          'v1-night-insight',
          'v1-night',
          'record_summary',
          '这条洞察的记录还在，迁移必须留下它。',
          'demo',
          'demo',
          82,
          _epoch(_bedtime),
          'ok',
        ],
      );
      await v2.customStatement(
        'INSERT INTO insights '
        '(id, record_id, kind, content, provider, model, score, '
        ' generated_at_utc, status) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          'demo-9-insight',
          'demo-9',
          'record_summary',
          '这条洞察的记录已经被清掉了。',
          'demo',
          'demo',
          71,
          _epoch(_bedtime),
          'ok',
        ],
      );
    } finally {
      await v2.close();
    }
  }

  test('夹具确实是 v1，而升级后确实是 v3', () async {
    // Without this the whole file could pass vacuously: if the fixture failed to
    // stamp `user_version = 1`, drift would run `onCreate` instead of
    // `onUpgrade` and create every current table anyway, so the assertions below
    // would hold while the migration code never executed.
    final v1 = _V1Database(NativeDatabase(file));
    await v1.customStatement('SELECT 1');
    expect(await userVersion(v1), 1, reason: '夹具必须停在 v1');
    await v1.close();

    final v2 = openCurrent();
    addTearDown(v2.close);
    await v2.allRecords();
    expect(await userVersion(v2), 3, reason: '打开后必须由 onUpgrade 一路推到 v3');
  });

  test('v1 记录升级后仍然存在，字段原样保留', () async {
    await writeV1Database();
    final db = openCurrent();
    addTearDown(db.close);

    final records = await db.allRecords();

    expect(records, hasLength(1), reason: '迁移不得丢弃已有记录');
    final record = records.single;
    expect(record.id, 'v1-night');
    // `isAtSameMomentAs`, not `==`: drift hands back a DateTime flagged local,
    // and `==` also compares that flag. What must survive the migration is the
    // instant — the wall-clock labels are derived with `.toLocal()` on top.
    expect(record.startAtUtc.isAtSameMomentAs(_bedtime), isTrue,
        reason: '入睡时刻的瞬时值被迁移改动了');
    expect(record.endAtUtc.isAtSameMomentAs(_wakeTime), isTrue,
        reason: '起床时刻的瞬时值被迁移改动了');
    expect(record.timeZoneId, 'Asia/Shanghai');
    expect(record.quality, 4);
    expect(record.notes, 'v1 时期写的备注');
    expect(record.tagsJson, '["旧标签"]', reason: '标签是自由文本，不该被迁移重写');
  });

  test('v1 的 source 不会被重置成 manual', () async {
    await writeV1Database(source: 'import');
    final db = openCurrent();
    addTearDown(db.close);

    // `source` decides whether 一键清除演示数据 touches a row, so a migration
    // that reset it would either delete real data or strand demo rows.
    expect((await db.allRecords()).single.source, 'import');
  });

  test('新增的事件标记列按默认值补齐为未勾选', () async {
    await writeV1Database();
    final db = openCurrent();
    addTearDown(db.close);

    final record = (await db.allRecords()).single;
    expect(record.flaggedSnore, isFalse);
    expect(record.flaggedTalk, isFalse);
    expect(record.flaggedRestless, isFalse);
    expect(record.flaggedNightmare, isFalse);
  });

  test('v2 新增的三张表在迁移后可用', () async {
    await writeV1Database();
    final db = openCurrent();
    addTearDown(db.close);

    // Reading each table is the assertion: a migration that skipped
    // createTable would throw "no such table" here rather than at first use
    // deep inside the UI.
    expect(await db.allStagesByRecord(), isEmpty);
    expect(await db.allClipsByRecord(), isEmpty);
    expect(await db.allInsightsByRecord(), isEmpty);

    // And they accept a write, with the foreign key resolving to the v1 row.
    await db.into(db.sleepStageSegments).insert(
          SleepStageSegmentsCompanion(
            id: const Value('post-migration-stage'),
            recordId: const Value('v1-night'),
            stage: const Value('deep'),
            startAtUtc: Value(_bedtime),
            endAtUtc: Value(_bedtime.add(const Duration(minutes: 40))),
          ),
        );
    final stages = await db.stagesFor('v1-night');
    expect(stages, hasLength(1));
  });

  test('v1 的设置行保留原值，并补齐新增列', () async {
    await writeV1Database();
    final db = openCurrent();
    addTearDown(db.close);

    final settings = await db.getSettings();
    expect(settings.themeMode, 'dark', reason: '用户选过的外观不能被迁移重置');
    expect(settings.sleepGoalMinutes, 450);
    expect(settings.bedtimeReminderEnabled, isTrue);
    expect(settings.bedtimeReminderMinutes, 1350);
    expect(settings.wakeReminderEnabled, isTrue);
    expect(settings.wakeReminderMinutes, 420);

    // Added in v2.
    expect(settings.soundRecordingEnabled, isFalse);
    expect(settings.onboarded, isFalse, reason: '老用户没看过新引导，应重新展示一次');
    expect(settings.insightProvider, isNull);
    expect(settings.insightModel, isNull);
  });

  test('没有设置行时迁移后仍能读出一行默认设置', () async {
    await writeV1Database(includeSettings: false);
    final db = openCurrent();
    addTearDown(db.close);

    // getSettings() inserts the row on demand; it must not trip over the
    // four columns the migration just added.
    final settings = await db.getSettings();
    expect(settings.id, 'default');
    expect(settings.themeMode, 'system');
  });

  test('迁移后的库记录为 v3，再次打开不会重跑迁移', () async {
    await writeV1Database();
    final first = openCurrent();
    await first.allRecords();
    await first.close();

    final second = openCurrent();
    addTearDown(second.close);

    // Re-running v1→v3 would throw "duplicate column name" on addColumn, which
    // is exactly how a botched upgrade leaves the app unable to open at all.
    expect(await second.getSettings(), isNotNull);
    expect((await second.allRecords()).single.id, 'v1-night');
  });

  test('升级后的记录能被仓库读成完整聚合', () async {
    await writeV1Database();
    final db = openCurrent();
    addTearDown(db.close);

    // The repository is what every page reads through, so a migration that
    // produced readable rows but rejected the aggregate would still be broken.
    final entries = await SleepRepository(db).loadAll();
    expect(entries, hasLength(1));
    expect(entries.single.durationHours, closeTo(7.5, 0.001));
    expect(entries.single.hasStages, isFalse);
  });

  group('v2 → v3', () {
    test('夹具确实是 v2，而升级后确实是 v3', () async {
      // 防止空跑：夹具若没把 user_version 戳成 2，drift 会走 onCreate 建全部新表，
      // 下面的断言会全绿而迁移代码一行没跑。
      final v2 = _V2Database(NativeDatabase(file));
      await v2.customStatement('SELECT 1');
      expect(await userVersion(v2), 2, reason: '夹具必须停在 v2');

      // 同一个「防止空跑」的理由，换个维度：夹具要是自己带上了外键，
      // 「外键在迁移后的表上确实存在」就成了一句废话——它测的正是这条约束
      // 从无到有。夹具的 insights 必须真的没有它。
      final fixtureDdl = await v2
          .customSelect("SELECT sql FROM sqlite_master WHERE name = 'insights'")
          .getSingle();
      expect(fixtureDdl.read<String>('sql'), isNot(contains('REFERENCES')),
          reason: '夹具必须重现「insights 没有外键」这个旧形态');
      await v2.close();

      final v3 = openCurrent();
      addTearDown(v3.close);
      await v3.allRecords();
      expect(await userVersion(v3), 3, reason: '打开后必须由 onUpgrade 推到 v3');
    });

    test('迁移清掉指向已删记录的孤儿洞察行', () async {
      await writeV2DatabaseWithOrphans();
      final db = openCurrent();
      addTearDown(db.close);

      // 这就是用户模拟器库的形状：记录被 deleteDemoData 删了，洞察留了下来。
      final orphans = await db
          .customSelect(
            'SELECT count(*) AS c FROM insights WHERE record_id IS NOT NULL '
            'AND record_id NOT IN (SELECT id FROM sleep_records)',
          )
          .getSingle();
      expect(orphans.read<int>('c'), 0, reason: '迁移必须清掉孤儿行，否则重装必然主键冲突');

      // 而属于存活记录的那条必须留下——迁移不是「清空 insights」。
      final kept = await db.customSelect(
        'SELECT count(*) AS c FROM insights WHERE record_id = ?',
        variables: const [Variable<String>('v1-night')],
      ).getSingle();
      expect(kept.read<int>('c'), 1, reason: '迁移误删了仍有关联的洞察');
    });

    test('迁移后删除记录会级联带走它的洞察', () async {
      await writeV2DatabaseWithOrphans();
      final db = openCurrent();
      addTearDown(db.close);
      await db.allRecords(); // 触发迁移

      await (db.delete(db.sleepRecords)..where((t) => t.id.equals('v1-night')))
          .go();

      final left = await db
          .customSelect(
            'SELECT count(*) AS c FROM insights',
          )
          .getSingle();
      expect(left.read<int>('c'), 0, reason: '外键级联没生效——这正是本 bug 的根因');
    });

    test('外键在迁移后的表上确实存在', () async {
      await writeV2DatabaseWithOrphans();
      final db = openCurrent();
      addTearDown(db.close);
      await db.allRecords();

      final sql = await db
          .customSelect(
            "SELECT sql FROM sqlite_master WHERE name = 'insights'",
          )
          .getSingle();
      expect(sql.read<String>('sql'), contains('REFERENCES'),
          reason: '重建后的 insights 表必须带上外键');
    });

    test('迁移保留没有被删除的洞察内容', () async {
      await writeV2DatabaseWithOrphans();
      final db = openCurrent();
      addTearDown(db.close);

      // alterTable copies rows into a brand-new table, so a mapping slip would
      // lose the payload while still leaving a row behind.
      final insight = await (db.select(db.insights)
            ..where((t) => t.id.equals('v1-night-insight')))
          .getSingle();
      expect(insight.recordId, 'v1-night');
      expect(insight.content, contains('迁移必须留下它'));
      expect(insight.score, 82);
    });
  });
}

/// 2026-09-26 23:30 → 2026-09-27 07:00 in UTC, so the fixture does not depend on
/// the machine's zone.
final _bedtime = DateTime.utc(2026, 9, 26, 15, 30);
final _wakeTime = DateTime.utc(2026, 9, 26, 23, 0);

/// drift stores `DateTimeColumn` as unix seconds on the native executor, which
/// is how the v1 app wrote them.
int _epoch(DateTime value) => value.millisecondsSinceEpoch ~/ 1000;

/// The schema as it shipped in v1: records and settings only, and without the
/// event flags, the onboarding/recording switches or the insight provider.
///
/// It is written as raw DDL rather than reused from `app_database.dart` because
/// the current table classes describe v3 — creating them would produce a
/// current-version file and the upgrade would never run. These statements are
/// frozen: do not "fix" them to match the current schema.
class _V1Database extends AppDatabase {
  _V1Database(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await customStatement('''
            CREATE TABLE sleep_records (
              id TEXT NOT NULL,
              start_at_utc INTEGER NOT NULL,
              end_at_utc INTEGER NOT NULL,
              time_zone_id TEXT NOT NULL DEFAULT 'UTC',
              quality INTEGER NOT NULL,
              notes TEXT NOT NULL DEFAULT '',
              tags_json TEXT NOT NULL DEFAULT '[]',
              source TEXT NOT NULL DEFAULT 'manual',
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              PRIMARY KEY (id)
            )
          ''');
          await customStatement('''
            CREATE TABLE app_settings (
              id TEXT NOT NULL,
              theme_mode TEXT NOT NULL DEFAULT 'system',
              sleep_goal_minutes INTEGER NOT NULL DEFAULT 480,
              bedtime_reminder_enabled INTEGER NOT NULL DEFAULT 0,
              bedtime_reminder_minutes INTEGER,
              wake_reminder_enabled INTEGER NOT NULL DEFAULT 0,
              wake_reminder_minutes INTEGER,
              PRIMARY KEY (id)
            )
          ''');
        },
      );
}

/// The schema as it shipped in v2.
///
/// Raw DDL rather than Dart table classes, for the same two reasons as
/// [_V1Database] above. The first is that it costs no code generation: the whole
/// file stays a plain test with no build step of its own. The second matters
/// more — raw DDL **freezes the shape**. A fixture built from table classes
/// keeps tracking `app_database.dart` as it evolves, so a later edit to those
/// classes would silently stop describing v2 and every assertion below would
/// pass with no migration code running. These statements are frozen: do not
/// "fix" them to match the current schema.
///
/// `insights` is the table under test. Its `record_id` is a plain nullable text
/// column with **no** `REFERENCES` — the shape that let orphan rows survive
/// `deleteDemoData`. That is the bug, and it is exactly what v3 rebuilds.
class _V2Database extends AppDatabase {
  _V2Database(super.executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await customStatement('''
            CREATE TABLE sleep_records (
              id TEXT NOT NULL,
              start_at_utc INTEGER NOT NULL,
              end_at_utc INTEGER NOT NULL,
              time_zone_id TEXT NOT NULL DEFAULT 'UTC',
              quality INTEGER NOT NULL,
              notes TEXT NOT NULL DEFAULT '',
              tags_json TEXT NOT NULL DEFAULT '[]',
              source TEXT NOT NULL DEFAULT 'manual',
              flagged_snore INTEGER NOT NULL DEFAULT 0,
              flagged_talk INTEGER NOT NULL DEFAULT 0,
              flagged_restless INTEGER NOT NULL DEFAULT 0,
              flagged_nightmare INTEGER NOT NULL DEFAULT 0,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              PRIMARY KEY (id)
            )
          ''');
          await customStatement('''
            CREATE TABLE sleep_stage_segments (
              id TEXT NOT NULL,
              record_id TEXT NOT NULL
                REFERENCES sleep_records (id) ON DELETE CASCADE,
              stage TEXT NOT NULL,
              start_at_utc INTEGER NOT NULL,
              end_at_utc INTEGER NOT NULL,
              source TEXT NOT NULL DEFAULT 'import',
              PRIMARY KEY (id)
            )
          ''');
          await customStatement('''
            CREATE TABLE sound_clips (
              id TEXT NOT NULL,
              record_id TEXT NOT NULL
                REFERENCES sleep_records (id) ON DELETE CASCADE,
              kind TEXT NOT NULL,
              started_at_utc INTEGER NOT NULL,
              duration_ms INTEGER NOT NULL,
              local_uri TEXT,
              transcript TEXT,
              analysis TEXT,
              analysis_status TEXT NOT NULL DEFAULT 'pending',
              source TEXT NOT NULL DEFAULT 'recording',
              PRIMARY KEY (id)
            )
          ''');
          await customStatement('''
            CREATE TABLE insights (
              id TEXT NOT NULL,
              record_id TEXT,
              kind TEXT NOT NULL DEFAULT 'record_summary',
              content TEXT,
              provider TEXT,
              model TEXT,
              score INTEGER,
              generated_at_utc INTEGER NOT NULL,
              status TEXT NOT NULL DEFAULT 'unavailable',
              PRIMARY KEY (id)
            )
          ''');
          await customStatement('''
            CREATE TABLE app_settings (
              id TEXT NOT NULL,
              theme_mode TEXT NOT NULL DEFAULT 'system',
              sleep_goal_minutes INTEGER NOT NULL DEFAULT 480,
              bedtime_reminder_enabled INTEGER NOT NULL DEFAULT 0,
              bedtime_reminder_minutes INTEGER,
              wake_reminder_enabled INTEGER NOT NULL DEFAULT 0,
              wake_reminder_minutes INTEGER,
              sound_recording_enabled INTEGER NOT NULL DEFAULT 0,
              onboarded INTEGER NOT NULL DEFAULT 0,
              insight_provider TEXT,
              insight_model TEXT,
              PRIMARY KEY (id)
            )
          ''');
        },
      );
}
