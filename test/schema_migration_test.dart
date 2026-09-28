import 'dart:io';

// `show` rather than the whole library: drift's query builder also exports
// `isNull` / `isNotNull`, which collide with the matchers of the same name.
import 'package:drift/drift.dart' show MigrationStrategy, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/core/database/app_database.dart';
import 'package:night_sleep/features/sleep/data/sleep_repository.dart';
import 'package:path/path.dart' as p;

/// Upgrading a **real** v1 database file to v2.
///
/// The other data tests all start from `NativeDatabase.memory()`, which drift
/// creates at the current schema version — so none of them ever execute the
/// `onUpgrade` branch. That branch shipped with the v2 work and, until now, had
/// never been run against a database that actually contains a user's night.
/// This file closes that gap by building a v1 file first and then opening the
/// real [AppDatabase] on top of it.
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

  AppDatabase openV2() => AppDatabase(NativeDatabase(file));

  Future<int> userVersion(AppDatabase db) async {
    final row = await db.customSelect('PRAGMA user_version').getSingle();
    return row.read<int>('user_version');
  }

  test('夹具确实是 v1，而升级后确实是 v2', () async {
    // Without this the whole file could pass vacuously: if the fixture failed to
    // stamp `user_version = 1`, drift would run `onCreate` instead of
    // `onUpgrade` and create every v2 table anyway, so the assertions below
    // would hold while the migration code never executed.
    final v1 = _V1Database(NativeDatabase(file));
    await v1.customStatement('SELECT 1');
    expect(await userVersion(v1), 1, reason: '夹具必须停在 v1');
    await v1.close();

    final v2 = openV2();
    addTearDown(v2.close);
    await v2.allRecords();
    expect(await userVersion(v2), 2, reason: '打开后必须由 onUpgrade 推到 v2');
  });

  test('v1 记录升级后仍然存在，字段原样保留', () async {
    await writeV1Database();
    final db = openV2();
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
    final db = openV2();
    addTearDown(db.close);

    // `source` decides whether 一键清除演示数据 touches a row, so a migration
    // that reset it would either delete real data or strand demo rows.
    expect((await db.allRecords()).single.source, 'import');
  });

  test('新增的事件标记列按默认值补齐为未勾选', () async {
    await writeV1Database();
    final db = openV2();
    addTearDown(db.close);

    final record = (await db.allRecords()).single;
    expect(record.flaggedSnore, isFalse);
    expect(record.flaggedTalk, isFalse);
    expect(record.flaggedRestless, isFalse);
    expect(record.flaggedNightmare, isFalse);
  });

  test('v2 新增的三张表在迁移后可用', () async {
    await writeV1Database();
    final db = openV2();
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
    final db = openV2();
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
    final db = openV2();
    addTearDown(db.close);

    // getSettings() inserts the row on demand; it must not trip over the
    // four columns the migration just added.
    final settings = await db.getSettings();
    expect(settings.id, 'default');
    expect(settings.themeMode, 'system');
  });

  test('迁移后的库记录为 v2，再次打开不会重跑迁移', () async {
    await writeV1Database();
    final first = openV2();
    await first.allRecords();
    await first.close();

    final second = openV2();
    addTearDown(second.close);

    // Re-running v1→v2 would throw "duplicate column name" on addColumn, which
    // is exactly how a botched upgrade leaves the app unable to open at all.
    expect(await second.getSettings(), isNotNull);
    expect((await second.allRecords()).single.id, 'v1-night');
  });

  test('升级后的记录能被仓库读成完整聚合', () async {
    await writeV1Database();
    final db = openV2();
    addTearDown(db.close);

    // The repository is what every page reads through, so a migration that
    // produced readable rows but rejected the aggregate would still be broken.
    final entries = await SleepRepository(db).loadAll();
    expect(entries, hasLength(1));
    expect(entries.single.durationHours, closeTo(7.5, 0.001));
    expect(entries.single.hasStages, isFalse);
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
/// the current table classes describe v2 — creating them would produce a v2 file
/// and the upgrade would never run. These statements are frozen: do not "fix"
/// them to match the current schema.
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
