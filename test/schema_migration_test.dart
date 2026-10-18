import 'dart:io';

// 只挡掉这两个与 `flutter_test` 匹配器重名的名字（它们在这里仍当匹配器用），而不是
// 列一份 `show` 清单：本文件用到的 drift 符号只有 `GeneratedDatabase`、
// `MigrationStrategy`、`Value`、`Variable` 四个，但夹具要用 `customStatement` 写裸
// DDL、各自定义一段迁移，最后还要把真实的 [AppDatabase] 打开在同一份文件上——
// 清单迟早要补，不如让其余名字照常进来。
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/core/database/app_database.dart';
import 'package:night_sleep/features/sleep/data/sleep_repository.dart';
import 'package:path/path.dart' as p;

/// 把**真实的**库文件——一份 v1 写下的、一份 v2 写下的——升级到当前 schema。
///
/// 其余数据测试都从 `NativeDatabase.memory()` 起步，drift 会按当前 schema 版本
/// 直接建好，所以它们一条 `onUpgrade` 分支都跑不到。这里的夹具先把一份旧版本的
/// 文件写出来，再把真实的 [AppDatabase] 打开在它上面——这是让迁移跑得跟用户设备
/// 上一样的唯一办法。
///
/// 这里冒出来的迁移 bug 不是观感问题：`onUpgrade` 是在用户打开应用时跑的，一个
/// 写错的列名或一张漏掉的表，就能让应用起不来、让已有的记录取不回来。
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

  /// 在 `file` 现有的内容之上，打开**当前**的 schema。
  ///
  /// 名字里写 current 而不是 v2 是故意的：这个辅助函数早于 v2→v3 这一轮，
  /// 在这里写死版本号，等 `schemaVersion` 下次再动时它就会过期——并且变成
  /// 一句假话。
  AppDatabase openCurrent() => AppDatabase(NativeDatabase(file));

  Future<int> userVersion(GeneratedDatabase db) async {
    final row = await db.customSelect('PRAGMA user_version').getSingle();
    return row.read<int>('user_version');
  }

  /// 写出一份 v2 的库，形态就是线上应用在「清除演示数据」之后留下的样子：
  /// 一条幸存下来的夜晚记录和它的洞察，一条记录已经不在了的洞察
  /// （`demo-9`——演示行被删掉了，洞察没被删，因为 v2 的 `insights.record_id`
  /// 没有外键），外加一条 `record_id` 为空的洞察——它从未挂到任何记录上，
  /// 迁移的孤儿删除条件够不着它，所以必须原样活下来。
  ///
  /// 写完就把文件关掉，好让升级跑的正是用户设备会交给它的那串字节。
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
      await v2.customStatement(
        'INSERT INTO insights '
        '(id, record_id, kind, content, provider, model, score, '
        ' generated_at_utc, status) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          'unbound-insight',
          // `record_id` 为空：这条洞察从未挂到任何记录上。迁移只清「指向不存在的
          // 记录」的行，`IS NOT NULL` 的守卫让它必须活下来。
          null,
          'record_summary',
          '这条洞察没有关联记录，迁移必须留下它。',
          'demo',
          'demo',
          64,
          _epoch(_bedtime),
          'ok',
        ],
      );
    } finally {
      await v2.close();
    }
  }

  /// 只写出 v2 的 `insights`、**一条记录都不写**：这是「记录表为空」的极端形态，
  /// 迁移里 `record_id IS NOT NULL` 那道守卫正是为它而设——记录表为空时
  /// `record_id NOT IN (...)` 对空值也求值为真，少了守卫，没有关联记录的洞察会被
  /// 一并清掉。上面的夹具带有记录，跑不到这个分支，只能另起一份。
  Future<void> writeV2DatabaseWithoutRecords() async {
    final v2 = _V2Database(NativeDatabase(file));
    try {
      await v2.customStatement(
        'INSERT INTO insights '
        '(id, record_id, kind, content, provider, model, score, '
        ' generated_at_utc, status) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          'unbound-insight',
          null,
          'record_summary',
          '这条洞察没有关联记录，记录表为空时也必须留下。',
          'demo',
          'demo',
          64,
          _epoch(_bedtime),
          'ok',
        ],
      );
    } finally {
      await v2.close();
    }
  }

  /// 写出一份 v3 的库：一条有质量的记录，外加它的阶段、声音片段与洞察，一条设置。
  ///
  /// 形态就是线上应用在 v4 到来之前留下的样子：`sleep_records.quality` 仍是
  /// `NOT NULL`，且还没有 `active_sessions` 表。
  ///
  /// **四类子表行都要写**（阶段 / 片段 / 洞察 / 设置）：v4 的 `alterTable` 是
  /// 「建新表 → 拷数据 → 删旧表 → 改名」，重建的恰恰是这三张子表所引用的
  /// `sleep_records`，最容易丢的就是子表数据。少写任何一类，对应的存活断言就是空的。
  ///
  /// 时间戳写成 **unix 秒**，与 [_epoch] 同一个口径——drift 的 `dateTime()` 在原生
  /// 执行器上按秒存，写微秒会被 `DateTime.fromMillisecondsSinceEpoch` 判成越界。
  Future<void> writeV3Database() async {
    final v3 = _V3Database(NativeDatabase(file));
    try {
      await v3.customStatement(
        "INSERT INTO sleep_records (id, start_at_utc, end_at_utc, time_zone_id, "
        "quality, notes, source, created_at, updated_at) VALUES "
        "('v3-night', 1759000000000, 1759028800000, 'UTC', 4, "
        "'v3 时期写的备注', 'manual', 1759000000000, 1759000000000)",
      );
      await v3.customStatement(
        "INSERT INTO sleep_stage_segments (id, record_id, stage, start_at_utc, "
        "end_at_utc, source) VALUES ('v3-night-stage-0', 'v3-night', 'deep', "
        "1759000000000, 1759003600000, 'import')",
      );
      await v3.customStatement(
        "INSERT INTO sound_clips (id, record_id, kind, started_at_utc, "
        "duration_ms, analysis_status, source) VALUES "
        "('v3-night-clip-0', 'v3-night', 'noise', 1759000000000, 1200, "
        "'pending', 'recording')",
      );
      await v3.customStatement(
        "INSERT INTO insights (id, record_id, kind, content, provider, model, "
        "score, generated_at_utc, status) VALUES ('v3-night-insight', "
        "'v3-night', 'record_summary', 'v3 时期写的洞察', 'demo', 'demo', 80, "
        "1759000000000, 'ok')",
      );
      await v3.customStatement(
        "INSERT INTO app_settings (id, theme_mode, sleep_goal_minutes, "
        "wake_reminder_minutes) VALUES ('default', 'dark', 450, 420)",
      );
    } finally {
      await v3.close();
    }
  }

  test('夹具确实是 v1，而升级后停在当前版本', () async {
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
    // 与 `schemaVersion` 比，不写死数字：写死的那个数每升一版就会变成一句假话，
    // 而这条断言要守的是「onUpgrade 一路推到了代码声明的版本」。
    expect(await userVersion(v2), v2.schemaVersion,
        reason: '打开后必须由 onUpgrade 一路推到当前版本');
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

  test('迁移后的库再次打开不会重跑迁移', () async {
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
    test('夹具确实是 v2，而升级后停在当前版本', () async {
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
      // 同「夹具确实是 v1」那条：与 `schemaVersion` 比，不写死版本号。
      expect(await userVersion(v3), v3.schemaVersion,
          reason: '打开后必须由 onUpgrade 推到当前版本');
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

      // 而从未挂到记录上的那条（`record_id` 为空）也必须留下——迁移的删除条件是
      // 「record_id 非空且指向不存在的记录」，空值不在其中。
      //
      // 这份夹具有一条记录，`NULL NOT IN (非空集合)` 在 SQL 里求值为 NULL（不删），
      // 所以「删掉 `IS NOT NULL` 守卫」在这里不会变红；真正让那道守卫吃重的是记录表
      // 为空的情形，见下面那条用例。
      final unbound = await db
          .customSelect(
            'SELECT count(*) AS c FROM insights WHERE record_id IS NULL',
          )
          .getSingle();
      expect(unbound.read<int>('c'), 1, reason: '迁移误删了没有关联记录的洞察');
    });

    test('记录表为空时，没有关联记录的洞察也不被清掉', () async {
      await writeV2DatabaseWithoutRecords();
      final db = openCurrent();
      addTearDown(db.close);

      // 记录表为空时 `record_id NOT IN (SELECT id FROM sleep_records)` 对空值也
      // 求值为真，只有 `IS NOT NULL` 守卫挡得住；去掉守卫这条用例变红。
      final kept = await db
          .customSelect(
            'SELECT count(*) AS c FROM insights WHERE record_id IS NULL',
          )
          .getSingle();
      expect(kept.read<int>('c'), 1, reason: '空表下 IS NOT NULL 守卫没挡住，误删了无主洞察');
    });

    test('迁移后删除记录会级联带走它的洞察', () async {
      await writeV2DatabaseWithOrphans();
      final db = openCurrent();
      addTearDown(db.close);
      await db.allRecords(); // 触发迁移

      await (db.delete(db.sleepRecords)..where((t) => t.id.equals('v1-night')))
          .go();

      // 只数有归属的行：夹具里那条 `record_id` 为空的洞察没有外键可级联，
      // 应当原样留下，不能算进这次删除的结果里。
      final left = await db
          .customSelect(
            'SELECT count(*) AS c FROM insights WHERE record_id IS NOT NULL',
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

      // alterTable 是把行拷进一张全新的表，列映射写错就会留下行、却丢了内容。
      final insight = await (db.select(db.insights)
            ..where((t) => t.id.equals('v1-night-insight')))
          .getSingle();
      expect(insight.recordId, 'v1-night');
      expect(insight.content, contains('迁移必须留下它'));
      expect(insight.score, 82);
    });
  });

  group('v3 → v4', () {
    test('夹具确实是 v3，而升级后停在当前版本', () async {
      await writeV3Database();
      final v3 = _V3Database(NativeDatabase(file));
      expect(await userVersion(v3), 3);
      await v3.customStatement('SELECT 1');
      await v3.close();

      final db = openCurrent();
      addTearDown(db.close);
      await db.allRecords(); // 触发迁移
      // 同「夹具确实是 v1 / v2」两条：与 `schemaVersion` 比，不写死数字。写死 4
      // 时它只在 v4 那一版成立，schemaVersion 一升就变成一句假话（本轮 v5 就是）。
      expect(await userVersion(db), db.schemaVersion);
    });

    test('v3 的记录、阶段、片段、洞察、设置一行不动', () async {
      await writeV3Database();
      final db = openCurrent();
      addTearDown(db.close);

      final records = await db.allRecords();
      expect(records, hasLength(1));
      expect(records.single.id, 'v3-night');
      expect(records.single.quality, 4);
      expect(records.single.notes, 'v3 时期写的备注');
      expect(await db.stagesFor('v3-night'), hasLength(1));

      // 片段与洞察：`alterTable` 重建的是它们引用的 `sleep_records`，行映射写错
      // 就会留下记录、却丢掉这两类子表数据。规格 §十二与主规格 §9 都点名要验。
      final clips = await db.allClipsByRecord();
      expect(clips['v3-night'], hasLength(1),
          reason: '重建 sleep_records 时丢掉了声音片段');
      expect(clips['v3-night']!.single.id, 'v3-night-clip-0');
      final insights = await db.allInsightsByRecord();
      expect(insights['v3-night'], isNotNull,
          reason: '重建 sleep_records 时丢掉了洞察');
      expect(insights['v3-night']!.content, 'v3 时期写的洞察');

      final settings = await db.getSettings();
      expect(settings.themeMode, 'dark');
      expect(settings.sleepGoalMinutes, 450);
      expect(settings.wakeReminderMinutes, 420);
    });

    /// 迁移过的库**再打开一次**必须原样可用、且不重跑 v3→v4。
    ///
    /// 重跑会撞上 `createTable(activeSessions)` 的「表已存在」——那正是迁移写错时
    /// 用户第二次打开应用就起不来的形态。v1→v3 那条已有同款用例，这里补上 v4 的。
    test('v3 升级后的库再次打开不重跑迁移，子表原样', () async {
      await writeV3Database();
      final first = openCurrent();
      await first.allRecords(); // 触发迁移
      await first.close();

      final second = openCurrent();
      addTearDown(second.close);

      expect((await second.allRecords()).single.id, 'v3-night');
      expect(await second.stagesFor('v3-night'), hasLength(1));
      expect((await second.allClipsByRecord())['v3-night'], hasLength(1));
      expect((await second.allInsightsByRecord())['v3-night'], isNotNull);
      expect(await second.getSettings(), isNotNull);
    });

    /// 表重建的要害：`quality` 的可空性**真的**放开了。
    test('重建后 quality 可以写空', () async {
      await writeV3Database();
      final db = openCurrent();
      addTearDown(db.close);
      await db.allRecords(); // 触发迁移

      await db.saveRecord(
        SleepRecordsCompanion.insert(
          id: 'unrated',
          startAtUtc: DateTime.utc(2026, 8, 30, 23),
          endAtUtc: DateTime.utc(2026, 8, 31, 7),
          quality: const Value(null),
          createdAt: DateTime.utc(2026, 8, 31, 7),
          updatedAt: DateTime.utc(2026, 8, 31, 7),
        ),
      );

      final row = await db.findRecord('unrated');
      expect(row!.quality, isNull);
    });

    /// 重建一张有子表引用它的表之后，级联还得真的生效。
    test('重建后子表外键仍然级联', () async {
      await writeV3Database();
      final db = openCurrent();
      addTearDown(db.close);
      await db.allRecords();

      await db.deleteRecord('v3-night');

      expect(await db.stagesFor('v3-night'), isEmpty);
    });

    test('会话表在迁移后可用', () async {
      await writeV3Database();
      final db = openCurrent();
      addTearDown(db.close);
      await db.allRecords();

      expect(await db.activeSession(), isNull);
      await db.saveActiveSession(
        ActiveSessionsCompanion.insert(
          id: 'active',
          startAtUtc: DateTime.utc(2026, 8, 30, 23, 14),
          timeZoneId: const Value('Asia/Shanghai'),
          wakeMinutes: 420,
          createdAt: DateTime.utc(2026, 8, 30, 23, 14),
        ),
      );
      expect((await db.activeSession())!.wakeMinutes, 420);
    });
  });

  /// 写出一份 v4 的库：一条会话行 + 一条设置。会话行正是 `scene_id` 要加在的那张表。
  Future<void> writeV4Database() async {
    final v4 = _V4Database(NativeDatabase(file));
    try {
      await v4.customStatement(
        "INSERT INTO active_sessions (id, start_at_utc, time_zone_id, "
        "wake_minutes, alarm_enabled, noise_id, noise_volume, created_at) "
        "VALUES ('active', 1759000000000, 'Asia/Shanghai', 420, 1, "
        "'rain', 0.35, 1759000000000)",
      );
      await v4.customStatement(
        "INSERT INTO app_settings (id, theme_mode, sleep_goal_minutes) "
        "VALUES ('default', 'dark', 450)",
      );
    } finally {
      await v4.close();
    }
  }

  group('v4 → v5', () {
    test('夹具确实是 v4，而升级后停在当前版本', () async {
      await writeV4Database();
      final v4 = _V4Database(NativeDatabase(file));
      expect(await userVersion(v4), 4);
      await v4.customStatement('SELECT 1');
      await v4.close();

      final db = openCurrent();
      addTearDown(db.close);
      await db.activeSession(); // 触发迁移
      // 与其余几条同口径：和 `schemaVersion` 比，不写死数字。
      expect(await userVersion(db), db.schemaVersion);
    });

    test('既有会话行一个字段不差，scene_id 读出来是空的', () async {
      await writeV4Database();
      final db = openCurrent();
      addTearDown(db.close);

      final row = await db.activeSession();
      expect(row, isNotNull, reason: '加列把既有会话行弄丢了');
      expect(row!.wakeMinutes, 420);
      expect(row.alarmEnabled, isTrue);
      expect(row.noiseId, 'rain');
      expect(row.noiseVolume, 0.35);
      // 新增列必须是可空的，且既有行读出来为空——这正是「没选过就按默认渲染」
      // 这条语义能成立的前提。
      expect(row.sceneId, isNull);
    });

    test('迁移后可以写入并读回 scene_id', () async {
      await writeV4Database();
      final db = openCurrent();
      addTearDown(db.close);
      await db.activeSession(); // 触发迁移

      await db.updateActiveSession(
        const ActiveSessionsCompanion(sceneId: Value('galaxy')),
      );
      expect((await db.activeSession())!.sceneId, 'galaxy');
    });

    test('升级后的库再次打开不重跑迁移', () async {
      await writeV4Database();
      final first = openCurrent();
      await first.activeSession(); // 触发迁移
      await first.close();

      final second = openCurrent();
      addTearDown(second.close);
      // 重跑会撞上 `duplicate column name: scene_id`。
      expect((await second.activeSession())!.id, 'active');
    });
  });

  /// 写出一份 v5 的库：一条片段行 + 一条会话行。这两张表正是 v6 要加列的地方。
  Future<void> writeV5Database() async {
    final v5 = _V5Database(NativeDatabase(file));
    try {
      await v5.customStatement(
        "INSERT INTO sleep_records (id, start_at_utc, end_at_utc, time_zone_id, "
        "quality, notes, tags_json, source, flagged_snore, flagged_talk, "
        "flagged_restless, flagged_nightmare, created_at, updated_at) "
        "VALUES ('r1', 1759000000, 1759026000, 'Asia/Shanghai', 4, '', '[]', "
        "'session', 0, 0, 0, 0, 1759000000, 1759000000)",
      );
      await v5.customStatement(
        "INSERT INTO sound_clips (id, record_id, kind, started_at_utc, "
        "duration_ms, local_uri, transcript, analysis, analysis_status, source) "
        "VALUES ('c1', 'r1', 'noise', 1759000100, 4200, "
        "'/tmp/clips/c1.wav', NULL, NULL, 'pending', 'recording')",
      );
      await v5.customStatement(
        "INSERT INTO active_sessions (id, start_at_utc, time_zone_id, "
        "wake_minutes, alarm_enabled, noise_id, noise_volume, scene_id, "
        "created_at) "
        "VALUES ('active', 1759000000, 'Asia/Shanghai', 420, 1, 'rain', 0.35, "
        "'galaxy', 1759000000)",
      );
    } finally {
      await v5.close();
    }
  }

  group('v5 → v6', () {
    test('夹具确实是 v5，而升级后停在当前版本', () async {
      await writeV5Database();
      final v5 = _V5Database(NativeDatabase(file));
      expect(await userVersion(v5), 5);
      await v5.customStatement('SELECT 1');
      await v5.close();

      final db = openCurrent();
      addTearDown(db.close);
      await db.activeSession(); // 触发迁移
      expect(await userVersion(db), db.schemaVersion);
    });

    test('既有片段行一个字段不差，三列读出来都是空的', () async {
      await writeV5Database();
      final db = openCurrent();
      addTearDown(db.close);

      final clips = await db.allRecordingClips();
      expect(clips, hasLength(1), reason: '加列把既有片段行弄丢了');
      final clip = clips.single;
      expect(clip.id, 'c1');
      expect(clip.recordId, 'r1');
      expect(clip.kind, 'noise');
      expect(clip.durationMs, 4200);
      expect(clip.localUri, '/tmp/clips/c1.wav');
      expect(clip.source, 'recording');
      // 三列都必须是可空的，且既有行读出来为空——这正是「还没标过 / 还没画过
      // 包络 / 还没有待落库的片段」这三条语义能成立的前提。
      expect(clip.waveformEnvelope, isNull);
      expect(clip.labeledAtUtc, isNull);

      final session = await db.activeSession();
      expect(session, isNotNull, reason: '加列把既有会话行弄丢了');
      expect(session!.wakeMinutes, 420);
      expect(session.sceneId, 'galaxy');
      expect(session.clipJournal, isNull);
    });

    test('迁移后可以写入并读回三列', () async {
      await writeV5Database();
      final db = openCurrent();
      addTearDown(db.close);
      await db.activeSession(); // 触发迁移

      await db.updateClipLabel(
        'c1',
        kind: 'snore',
        labeledAtUtc: DateTime.utc(2026, 10, 3, 1, 2, 3),
      );
      await db.updateActiveSession(
        const ActiveSessionsCompanion(clipJournal: Value('[{"id":"c2"}]')),
      );

      final clip = (await db.allRecordingClips()).single;
      expect(clip.kind, 'snore');
      // drift 在原生执行器上按 unix 秒存 DateTime，读回来的是**标记为本地时区**
      // 的 `DateTime`——瞬时值不变，变的是 `DateTime.==` 会一并比较的那个标记。
      // 所以这里比的是 `toUtc()`，不是裸值（`session_repository.dart` 记过同一个坑）。
      expect(clip.labeledAtUtc!.toUtc(), DateTime.utc(2026, 10, 3, 1, 2, 3));
      expect(
        (await db.activeSession())!.clipJournal,
        '[{"id":"c2"}]',
      );
    });

    test('清理掉文件的片段把 local_uri 置空，行本身还在', () async {
      await writeV5Database();
      final db = openCurrent();
      addTearDown(db.close);
      await db.activeSession(); // 触发迁移

      await db.clearClipLocalUris(['c1']);

      final clip = (await db.allRecordingClips()).single;
      expect(clip.localUri, isNull, reason: '音频被裁掉后文件指针该清空');
      expect(clip.id, 'c1', reason: '事件记录必须留着，不能整个片段凭空消失');
    });

    test('升级后的库再次打开不重跑迁移', () async {
      await writeV5Database();
      final first = openCurrent();
      await first.activeSession(); // 触发迁移
      await first.close();

      final second = openCurrent();
      addTearDown(second.close);
      // 重跑会撞上 `duplicate column name: clip_journal`。
      expect((await second.activeSession())!.id, 'active');
    });
  });

  /// v6 那三列的补法**两条下界不一样**（`sound_clips` 从 v2 起再没重建过，
  /// `active_sessions` 是 v4 才有的表），所以每条升上来的路都得单独走一遍。
  ///
  /// 这一组就是为那个 bug 而写的：最初把两条都写成 `from >= 5 && from < 6`，
  /// v4 与 v3 的库升上来时会**整块跳过**，而 v4→v5 那段只加 `scene_id`，
  /// 没有任何一段会补上这三列——升上来的库里根本没有这些列，直到有人录了一晚
  /// 才在 `finish()` 里炸开。
  group('旧库直升 v6', () {
    /// 迁移之后这三列必须真的能用：写进去、读回来。只断言「能打开」是不够的——
    /// 缺列时 drift 的报错发生在第一次碰它的那一刻，不在打开时。
    Future<void> expectV6ColumnsUsable(AppDatabase db) async {
      await db.saveRecord(
        SleepRecordsCompanion.insert(
          id: 'r-new',
          startAtUtc: DateTime.utc(2026, 10, 3, 22),
          endAtUtc: DateTime.utc(2026, 10, 4, 6),
          createdAt: DateTime.utc(2026, 10, 3, 22),
          updatedAt: DateTime.utc(2026, 10, 3, 22),
        ),
      );
      await db.insertClips([
        SoundClipsCompanion.insert(
          id: 'c-new',
          recordId: 'r-new',
          kind: 'noise',
          startedAtUtc: DateTime.utc(2026, 10, 4, 1),
          durationMs: 3000,
          waveformEnvelope: const Value('[0.1,0.9]'),
        ),
      ]);
      await db.updateClipLabel(
        'c-new',
        kind: 'talk',
        labeledAtUtc: DateTime.utc(2026, 10, 4, 8),
      );
      // 夹具里的老库不一定有会话行（v1 就没有），先确保有一行再写清单——
      // `update` 打在空表上什么也不做，那样断言会以「读回来是 null」的形式
      // 误报成「列没补上」。
      await db.saveActiveSession(
        ActiveSessionsCompanion.insert(
          id: 'active',
          startAtUtc: DateTime.utc(2026, 10, 3, 22),
          wakeMinutes: 420,
          createdAt: DateTime.utc(2026, 10, 3, 22),
        ),
      );
      await db.updateActiveSession(
        const ActiveSessionsCompanion(clipJournal: Value('[{"id":"x"}]')),
      );

      // 按 id 找，不用 `single`：夹具里本来就有别的片段行。
      final clip =
          (await db.allRecordingClips()).firstWhere((row) => row.id == 'c-new');
      expect(clip.kind, 'talk');
      expect(clip.waveformEnvelope, '[0.1,0.9]');
      expect(clip.labeledAtUtc!.toUtc(), DateTime.utc(2026, 10, 4, 8));
      expect((await db.activeSession())?.clipJournal, '[{"id":"x"}]');
    }

    test('v3 升上来：两列都补上了', () async {
      await writeV3Database();
      final db = openCurrent();
      addTearDown(db.close);
      await db.allRecords(); // 触发迁移

      await expectV6ColumnsUsable(db);
    });

    test('v4 升上来：两列都补上了', () async {
      await writeV4Database();
      final db = openCurrent();
      addTearDown(db.close);
      await db.activeSession(); // 触发迁移

      await expectV6ColumnsUsable(db);
    });

    test('v1 升上来：sound_clips 是这一轮新建的，不重复加列', () async {
      await writeV1Database();
      final db = openCurrent();
      addTearDown(db.close);
      await db.allRecords(); // 触发迁移

      // `from < 2` 那一支的 `createTable(soundClips)` 用的是当前表定义，一建出来
      // 就带着新列——所以这里再多加一次就会是 `duplicate column name`。
      await expectV6ColumnsUsable(db);
    });
  });

  /// 写出一份 v6 的库：一条片段行（带 v6 那三列的值）+ 一条会话行。
  Future<void> writeV6Database() async {
    final v6 = _V6Database(NativeDatabase(file));
    try {
      await v6.customStatement(
        "INSERT INTO sleep_records (id, start_at_utc, end_at_utc, time_zone_id, "
        "quality, notes, tags_json, source, flagged_snore, flagged_talk, "
        "flagged_restless, flagged_nightmare, created_at, updated_at) "
        "VALUES ('r1', 1759000000, 1759026000, 'Asia/Shanghai', 4, '', '[]', "
        "'session', 0, 0, 0, 0, 1759000000, 1759000000)",
      );
      await v6.customStatement(
        "INSERT INTO sound_clips (id, record_id, kind, started_at_utc, "
        "duration_ms, local_uri, transcript, analysis, analysis_status, source, "
        "waveform_envelope, labeled_at_utc) "
        "VALUES ('c1', 'r1', 'snore', 1759000100, 4200, "
        "'/tmp/clips/c1.wav', NULL, NULL, 'pending', 'recording', "
        "'[0.1,0.9]', 1759000200)",
      );
    } finally {
      await v6.close();
    }
  }

  Future<void> writeV7Database() async {
    final v7 = _V7Database(NativeDatabase(file));
    try {
      await v7.customStatement(
        "INSERT INTO sleep_records (id, start_at_utc, end_at_utc, time_zone_id, "
        "quality, notes, tags_json, source, flagged_snore, flagged_talk, "
        "flagged_restless, flagged_nightmare, created_at, updated_at) "
        "VALUES ('r1', 1759000000, 1759026000, 'Asia/Shanghai', 4, '', '[]', "
        "'session', 0, 0, 0, 0, 1759000000, 1759000000)",
      );
      // 三条真实片段各代表一种 v8 要区别对待的状态：
      //  * `c-analysed` —— 手写阈值跑过、写了结论（**该被清回 pending**）
      //  * `c-abstain`  —— 手写阈值跑过、弃权（同样该被清：那也是旧引擎的结论）
      //  * `c-failed`   —— 音频读不出来（**不该被动**：「读不出来」与「引擎换了」无关）
      for (final row in [
        (
          'c-analysed',
          'snore',
          'analysed',
          '\'{"kind":"snore","margin":0.42,"basis":"低频能量 66%",'
              '"startMs":300,"durationMs":6300,"atUtc":"2026-10-14T08:00:00.000Z"}\''
        ),
        (
          'c-abstain',
          'noise',
          'analysed',
          '\'{"kind":null,"atUtc":"2026-10-14T08:00:00.000Z"}\''
        ),
        ('c-failed', 'noise', 'failed', 'NULL'),
      ]) {
        await v7.customStatement(
          "INSERT INTO sound_clips (id, record_id, kind, started_at_utc, "
          "duration_ms, local_uri, transcript, analysis, analysis_status, "
          "source, waveform_envelope, labeled_at_utc, auto_analysis) "
          "VALUES ('${row.$1}', 'r1', '${row.$2}', 1759000100, 4200, "
          "'/tmp/clips/${row.$1}.wav', NULL, NULL, '${row.$3}', 'recording', "
          "'[0.1,0.9]', 1759000200, ${row.$4})",
        );
      }
      // 演示数据：它的 `analysis_status` 是示例数据本身的一部分，补跑按定义不看它，
      // 所以**不许被清回 pending**（清了就永远没人管，会一直挂在「待标注」上）。
      await v7.customStatement(
        "INSERT INTO sound_clips (id, record_id, kind, started_at_utc, "
        "duration_ms, local_uri, transcript, analysis, analysis_status, "
        "source, waveform_envelope, labeled_at_utc, auto_analysis) "
        "VALUES ('c-demo', 'r1', 'snore', 1759000100, 4200, NULL, NULL, NULL, "
        "'analysed', 'demo', NULL, NULL, NULL)",
      );
    } finally {
      await v7.close();
    }
  }

  /// 写一个停在 v8 的库。夹具与 v7 逐列相同（v8 只改数据），区别只在版本号。
  ///
  /// 三条真实片段各代表一种 v9 要区别对待的状态：
  ///  * `c-analysed` —— YAMNet 跑过、写了结论（**该被清回 pending 重算**）
  ///  * `c-abstain`  —— YAMNet 跑过、弃权（同样该被清：那也是旧口径的结论）
  ///  * `c-failed`   —— 音频读不出来（**不该被动**）
  /// v8 / v9 的列集与数据形状相同（两版都只改数据），只有版本号不同。
  Future<void> writeV8OrLaterDatabase(int version) async {
    final db = version == 9
        ? _V9Database(NativeDatabase(file))
        : _V8Database(NativeDatabase(file));
    try {
      await db.customStatement(
        "INSERT INTO sleep_records (id, start_at_utc, end_at_utc, time_zone_id, "
        "quality, notes, tags_json, source, flagged_snore, flagged_talk, "
        "flagged_restless, flagged_nightmare, created_at, updated_at) "
        "VALUES ('r1', 1759000000, 1759026000, 'Asia/Shanghai', 4, '', '[]', "
        "'session', 0, 0, 0, 0, 1759000000, 1759000000)",
      );
      for (final row in [
        (
          'c-analysed',
          'snore',
          'analysed',
          '\'{"kind":"snore","margin":0.42,'
              '"basis":"YAMNet 鼾声分 0.85（整段 8 个窗口均分、最高 0.92，'
              '判定线 0.40）· 人声分 0.02",'
              '"startMs":0,"durationMs":0,"atUtc":"2026-10-16T08:00:00.000Z"}\''
        ),
        (
          'c-abstain',
          'noise',
          'analysed',
          '\'{"kind":null,"margin":null,"basis":null,"startMs":null,'
              '"durationMs":null,"atUtc":"2026-10-16T08:00:00.000Z"}\''
        ),
        ('c-failed', 'noise', 'failed', 'NULL'),
        ('c-pending', 'noise', 'pending', 'NULL'),
      ]) {
        await db.customStatement(
          "INSERT INTO sound_clips (id, record_id, kind, started_at_utc, "
          "duration_ms, local_uri, transcript, analysis, analysis_status, "
          "source, waveform_envelope, labeled_at_utc, auto_analysis) "
          "VALUES ('${row.$1}', 'r1', '${row.$2}', 1759000100, 4200, "
          "'/tmp/clips/${row.$1}.wav', NULL, NULL, '${row.$3}', 'recording', "
          "'[0.1,0.9]', 1759000200, ${row.$4})",
        );
      }
      // 演示数据：`analysis_status` 是示例数据本身的一部分，不许被清。
      await db.customStatement(
        "INSERT INTO sound_clips (id, record_id, kind, started_at_utc, "
        "duration_ms, local_uri, transcript, analysis, analysis_status, "
        "source, waveform_envelope, labeled_at_utc, auto_analysis) "
        "VALUES ('c-demo', 'r1', 'snore', 1759000100, 4200, NULL, NULL, NULL, "
        "'analysed', 'demo', NULL, NULL, NULL)",
      );
    } finally {
      await db.close();
    }
  }

  Future<void> writeV8Database() => writeV8OrLaterDatabase(8);

  Future<void> writeV9Database() => writeV8OrLaterDatabase(9);

  // v8 是**本仓第一条改数据的迁移**（其余都是加列）。它要作废的是 2026-10-16 之前
  // 那套手写声学阈值写下的结论——那套规则已被证伪（47 段上覆盖 2% / 准确 0%）。
  // 留着不清的后果很具体：`analysePending` 只捡 `pending`，于是**使用者那 3 段真鼾声
  // 会永远停在「待标注」**，而那正是这一版要修的事。
  //
  // **v9 加进来之后，这一组夹具升级到的终点是当前版本**（不再停在 8），但断言只关心
  // v8 那条分支的行为；v8 清成 pending 之后，v9 只碰 `analysed`，不会再动它们。
  group('v7 → v8', () {
    test('夹具确实是 v7，而升级后停在当前版本', () async {
      await writeV7Database();
      final v7 = _V7Database(NativeDatabase(file));
      expect(await userVersion(v7), 7);
      await v7.customStatement('SELECT 1');
      await v7.close();

      final db = openCurrent();
      addTearDown(db.close);
      await db.allRecords(); // 触发迁移
      expect(await userVersion(db), db.schemaVersion);
    });

    test('旧引擎的判断被清回 pending，`auto_analysis` 一起清空', () async {
      await writeV7Database();
      final db = openCurrent();
      addTearDown(db.close);

      final rows = await db.allRecordingClips();
      for (final id in ['c-analysed', 'c-abstain']) {
        final row = rows.firstWhere((r) => r.id == id);
        expect(row.analysisStatus, 'pending', reason: '$id 该等着用新引擎重算');
        expect(row.autoAnalysis, isNull, reason: '$id 的旧结论该被清掉');
      }
    });

    test('**用户自己的标注一个字节都不动**——清的是机器那一列', () async {
      // 这是这条迁移唯一可能造成实质损失的地方：`kind` 与 `labeled_at_utc` 是用户
      // 听过之后标的东西，不是机器猜的。迁移碰了它们就等于替用户改写历史。
      await writeV7Database();
      final db = openCurrent();
      addTearDown(db.close);

      final row = (await db.allRecordingClips())
          .firstWhere((r) => r.id == 'c-analysed');
      expect(row.kind, 'snore', reason: '人标的那个词');
      expect(row.labeledAtUtc, isNotNull, reason: '标过的时刻');
      expect(row.waveformEnvelope, '[0.1,0.9]', reason: '实测包络');
      expect(row.localUri, '/tmp/clips/c-analysed.wav', reason: '音频路径');
    });

    test('记过 failed 的不动——「音频读不出来」与「引擎换了」是两件事', () async {
      await writeV7Database();
      final db = openCurrent();
      addTearDown(db.close);

      final row =
          (await db.allRecordingClips()).firstWhere((r) => r.id == 'c-failed');
      expect(row.analysisStatus, 'failed',
          reason: '清成 pending 会让它每次冷启动都重试一遍，而文件还是读不出来');
    });

    test('演示数据不动——补跑按定义不看它，清了就永远没人管', () async {
      await writeV7Database();
      final db = openCurrent();
      addTearDown(db.close);

      final all = (await db.allClipsByRecord())['r1']!;
      final demo = all.firstWhere((r) => r.id == 'c-demo');
      expect(demo.analysisStatus, 'analysed');
    });

    test('清完之后补跑真的捡得起它们（迁移与补跑是配套的两半）', () async {
      // 只断言状态字符串等于 'pending' 是不够的：真正要成立的是**下一次冷启动会把
      // 它们捡起来**。这两半分开写就都不算数。
      await writeV7Database();
      final db = openCurrent();
      addTearDown(db.close);

      final waiting = await db.clipsAwaitingAnalysis();
      expect(
        waiting.map((r) => r.id).toSet(),
        {'c-analysed', 'c-abstain'},
        reason: 'failed 与 demo 都不该在里面',
      );
    });

    test('再来一次不重跑（版本已经停在当前版）', () async {
      await writeV7Database();
      var db = openCurrent();
      await db.allRecords();
      await db.updateClipAutoAnalysis(
        'c-analysed',
        payload: '{"kind":"snore","margin":0.9,"basis":"YAMNet 鼾声分 0.85",'
            '"atUtc":"2026-10-16T08:00:00.000Z"}',
        status: 'analysed',
      );
      await db.close();

      db = openCurrent();
      addTearDown(db.close);
      final row = (await db.allRecordingClips())
          .firstWhere((r) => r.id == 'c-analysed');
      expect(row.analysisStatus, 'analysed', reason: '重开一次库不该把新引擎的结论又清掉');
      expect(row.autoAnalysis, contains('YAMNet'));
    });
  });

  // v9 与 v8 同型：判定口径又变了一次（整段均分 → 整段均分 + 连续两窗短事件）。
  // 不清旧的「弃权」，2026-10-18 04:25 那段有真实事件、但被整段均分摊薄的录音
  // 会永远停在「待标注」——正是这一版要修的事。
  group('v8 → v9', () {
    test('夹具确实是 v8，而升级后停在当前版本', () async {
      await writeV8Database();
      final v8 = _V8Database(NativeDatabase(file));
      expect(await userVersion(v8), 8);
      await v8.customStatement('SELECT 1');
      await v8.close();

      final db = openCurrent();
      addTearDown(db.close);
      await db.allRecords(); // 触发迁移
      expect(await userVersion(db), db.schemaVersion);
    });

    test('旧口径的判断被清回 pending，`auto_analysis` 一起清空', () async {
      await writeV8Database();
      final db = openCurrent();
      addTearDown(db.close);

      final rows = await db.allRecordingClips();
      for (final id in ['c-analysed', 'c-abstain']) {
        final row = rows.firstWhere((r) => r.id == id);
        expect(row.analysisStatus, 'pending', reason: '$id 该等着用新口径重算');
        expect(row.autoAnalysis, isNull, reason: '$id 的旧结论该被清掉');
      }
    });

    test('**用户自己的标注一个字节都不动**——清的是机器那一列', () async {
      await writeV8Database();
      final db = openCurrent();
      addTearDown(db.close);

      final row = (await db.allRecordingClips())
          .firstWhere((r) => r.id == 'c-analysed');
      expect(row.kind, 'snore', reason: '人标的那个词');
      expect(row.labeledAtUtc, isNotNull, reason: '标过的时刻');
      expect(row.waveformEnvelope, '[0.1,0.9]', reason: '实测包络');
      expect(row.localUri, '/tmp/clips/c-analysed.wav', reason: '音频路径');
    });

    test('记过 failed 的不动——「音频读不出来」与「判定口径变了」是两件事', () async {
      await writeV8Database();
      final db = openCurrent();
      addTearDown(db.close);

      final row =
          (await db.allRecordingClips()).firstWhere((r) => r.id == 'c-failed');
      expect(row.analysisStatus, 'failed');
    });

    test('原本就 pending 的仍然是 pending——不丢、不重复处理', () async {
      await writeV8Database();
      final db = openCurrent();
      addTearDown(db.close);

      final row =
          (await db.allRecordingClips()).firstWhere((r) => r.id == 'c-pending');
      expect(row.analysisStatus, 'pending');
    });

    test('演示数据不动——补跑按定义不看它，清了就永远没人管', () async {
      await writeV8Database();
      final db = openCurrent();
      addTearDown(db.close);

      final demo = (await db.allClipsByRecord())['r1']!
          .firstWhere((r) => r.id == 'c-demo');
      expect(demo.analysisStatus, 'analysed');
    });

    test('清完之后补跑真的捡得起它们（迁移与补跑是配套的两半）', () async {
      await writeV8Database();
      final db = openCurrent();
      addTearDown(db.close);

      final waiting = await db.clipsAwaitingAnalysis();
      expect(
        waiting.map((r) => r.id).toSet(),
        {'c-analysed', 'c-abstain', 'c-pending'},
        reason: 'failed 与 demo 都不该在里面',
      );
    });

    test('再来一次不重跑（版本已经停在当前版）', () async {
      await writeV8Database();
      var db = openCurrent();
      await db.allRecords();
      await db.updateClipAutoAnalysis(
        'c-analysed',
        payload: '{"kind":"snore","margin":0.9,'
            '"basis":"YAMNet 鼾声分 0.54（最像的连续 2 个窗口均分）",'
            '"atUtc":"2026-10-18T08:00:00.000Z"}',
        status: 'analysed',
      );
      await db.close();

      db = openCurrent();
      addTearDown(db.close);
      final row = (await db.allRecordingClips())
          .firstWhere((r) => r.id == 'c-analysed');
      expect(row.analysisStatus, 'analysed', reason: '重开一次库不该把新口径的结论又清掉');
      expect(row.autoAnalysis, contains('最像的连续'));
    });
  });

  // v10 与 v8/v9 同型：判定口径又变了一次——**有声音、两条线都没过的片段由
  // 「待标注」改为「杂音」**（2026-10-18 使用方明确要求）。旧结论里那些弃权必须
  // 重算，否则界面上仍是一堆「待标注」，而这正是这一版要改的事。
  group('v9 → v10', () {
    test('夹具确实是 v9，而升级后停在当前版本', () async {
      await writeV9Database();
      final v9 = _V9Database(NativeDatabase(file));
      expect(await userVersion(v9), 9);
      await v9.customStatement('SELECT 1');
      await v9.close();

      final db = openCurrent();
      addTearDown(db.close);
      await db.allRecords(); // 触发迁移
      expect(await userVersion(db), db.schemaVersion);
    });

    test('旧口径的结论被清回 pending，`auto_analysis` 一起清空', () async {
      await writeV9Database();
      final db = openCurrent();
      addTearDown(db.close);

      final rows = await db.allRecordingClips();
      for (final id in ['c-analysed', 'c-abstain']) {
        final row = rows.firstWhere((r) => r.id == id);
        expect(row.analysisStatus, 'pending', reason: '$id 该等着按新口径重算');
        expect(row.autoAnalysis, isNull, reason: '$id 的旧结论该被清掉');
      }
    });

    test('**用户自己的标注一个字节都不动**——清的是机器那一列', () async {
      await writeV9Database();
      final db = openCurrent();
      addTearDown(db.close);

      final row = (await db.allRecordingClips())
          .firstWhere((r) => r.id == 'c-analysed');
      expect(row.kind, 'snore', reason: '人标的那个词');
      expect(row.labeledAtUtc, isNotNull, reason: '标过的时刻');
      expect(row.waveformEnvelope, '[0.1,0.9]', reason: '实测包络');
      expect(row.localUri, '/tmp/clips/c-analysed.wav', reason: '音频路径');
    });

    test('failed / pending / 演示数据都不动', () async {
      await writeV9Database();
      final db = openCurrent();
      addTearDown(db.close);

      final rows = await db.allRecordingClips();
      expect(
        rows.firstWhere((r) => r.id == 'c-failed').analysisStatus,
        'failed',
        reason: '音频读不出来与判定口径变了无关',
      );
      expect(
        rows.firstWhere((r) => r.id == 'c-pending').analysisStatus,
        'pending',
        reason: '原本就 pending 的不丢、不重复处理',
      );
      final demo = (await db.allClipsByRecord())['r1']!
          .firstWhere((r) => r.id == 'c-demo');
      expect(demo.analysisStatus, 'analysed', reason: '补跑按定义不看演示数据');
    });

    test('清完之后补跑真的捡得起它们（迁移与补跑是配套的两半）', () async {
      await writeV9Database();
      final db = openCurrent();
      addTearDown(db.close);

      final waiting = await db.clipsAwaitingAnalysis();
      expect(
        waiting.map((r) => r.id).toSet(),
        {'c-analysed', 'c-abstain', 'c-pending'},
        reason: 'failed 与 demo 都不该在里面',
      );
    });

    test('再来一次不重跑（版本已经停在当前版）', () async {
      await writeV9Database();
      var db = openCurrent();
      await db.allRecords();
      await db.updateClipAutoAnalysis(
        'c-abstain',
        payload: '{"kind":"noise","margin":0,'
            '"basis":"YAMNet 未测到鼾声或人声",'
            '"atUtc":"2026-10-18T09:00:00.000Z"}',
        status: 'analysed',
      );
      await db.close();

      db = openCurrent();
      addTearDown(db.close);
      final row =
          (await db.allRecordingClips()).firstWhere((r) => r.id == 'c-abstain');
      expect(row.analysisStatus, 'analysed', reason: '重开一次库不该把新口径的结论又清掉');
      expect(row.autoAnalysis, contains('未测到鼾声或人声'));
    });
  });

  group('v6 → v7', () {
    test('夹具确实是 v6，而升级后停在当前版本', () async {
      await writeV6Database();
      final v6 = _V6Database(NativeDatabase(file));
      expect(await userVersion(v6), 6);
      await v6.customStatement('SELECT 1');
      await v6.close();

      final db = openCurrent();
      addTearDown(db.close);
      await db.allRecords(); // 触发迁移
      expect(await userVersion(db), db.schemaVersion);
    });

    test('既有片段行一个字段不差，auto_analysis 读出来是空的', () async {
      await writeV6Database();
      final db = openCurrent();
      addTearDown(db.close);

      final clip = (await db.allRecordingClips()).single;
      expect(clip.id, 'c1');
      expect(clip.kind, 'snore', reason: '加列把既有片段行弄丢了');
      expect(clip.waveformEnvelope, '[0.1,0.9]', reason: 'v6 的列被迁移弄丢了');
      expect(clip.labeledAtUtc, isNotNull);
      // 新列必须可空，且既有行读出来为空——**「从没分析过」这条语义全靠它**，
      // 非空的话升级上来的应用会凭空多出一堆「机器判断」。
      expect(clip.autoAnalysis, isNull);
    });

    test('迁移后可以写入并读回 auto_analysis', () async {
      await writeV6Database();
      final db = openCurrent();
      addTearDown(db.close);
      await db.allRecords(); // 触发迁移

      await db.updateClipAutoAnalysis(
        'c1',
        payload: '{"kind":"snore","margin":0.5,"basis":"低频能量 66%",'
            '"atUtc":"2026-10-14T08:00:00.000Z"}',
        status: 'analysed',
      );

      final clip = (await db.allRecordingClips()).single;
      expect(clip.autoAnalysis, contains('"snore"'));
      expect(clip.analysisStatus, 'analysed');
      // **写机器判断不许动 `kind`**：它是人标的（这里是 'snore'，但那是人标的
      // 意思），机器判断另存一列正是为了让这两件事分得开。
      expect(clip.kind, 'snore');
    });

    test('弃权也落库，且与「从没分析过」分得开', () async {
      await writeV6Database();
      final db = openCurrent();
      addTearDown(db.close);
      await db.allRecords();

      await db.updateClipAutoAnalysis(
        'c1',
        payload: '{"kind":null,"margin":null,"basis":null,'
            '"atUtc":"2026-10-14T08:00:00.000Z"}',
        status: 'analysed',
      );

      final clip = (await db.allRecordingClips()).single;
      expect(clip.autoAnalysis, isNotNull, reason: '机器看过了，这件事本身要留下');
      expect(clip.autoAnalysis, contains('"kind":null'));
    });
  });

  group('旧库直升 v7', () {
    /// 迁移之后 `auto_analysis` 必须真的能用：写进去、读回来。
    /// 只断言「能打开」是不够的——缺列时 drift 的报错发生在第一次碰它的那一刻。
    Future<void> expectV7ColumnUsable(AppDatabase db) async {
      await db.saveRecord(
        SleepRecordsCompanion.insert(
          id: 'r-new',
          startAtUtc: DateTime.utc(2026, 10, 3, 22),
          endAtUtc: DateTime.utc(2026, 10, 4, 6),
          createdAt: DateTime.utc(2026, 10, 3, 22),
          updatedAt: DateTime.utc(2026, 10, 3, 22),
        ),
      );
      await db.insertClips([
        SoundClipsCompanion.insert(
          id: 'c-new',
          recordId: 'r-new',
          kind: 'noise',
          startedAtUtc: DateTime.utc(2026, 10, 4, 1),
          durationMs: 3000,
        ),
      ]);
      await db.updateClipAutoAnalysis(
        'c-new',
        payload: '{"kind":"voice","margin":0.4,"basis":"x",'
            '"atUtc":"2026-10-14T08:00:00.000Z"}',
        status: 'analysed',
      );

      final clip =
          (await db.allRecordingClips()).firstWhere((row) => row.id == 'c-new');
      expect(clip.autoAnalysis, contains('"voice"'));
      expect(clip.analysisStatus, 'analysed');
    }

    // **下界写成 `from >= 2` 的理由**：`sound_clips` 从 v2 建表之后再没被重建过，
    // 停在 v2–v6 的库都缺 `auto_analysis`。下面四条各覆盖一个下界，少一条就是
    // 一类用户升上来之后那一列不存在——v6 那次就是写成 `from >= 5` 而漏了 v4。
    test('v1 升上来：sound_clips 是新建的，列已经在里面，不重复加', () async {
      await writeV1Database();
      final db = openCurrent();
      addTearDown(db.close);
      await db.allRecords(); // 触发迁移

      await expectV7ColumnUsable(db);
    });

    test('v3 升上来：列补上了', () async {
      await writeV3Database();
      final db = openCurrent();
      addTearDown(db.close);
      await db.allRecords();

      await expectV7ColumnUsable(db);
    });

    test('v4 升上来：列补上了', () async {
      await writeV4Database();
      final db = openCurrent();
      addTearDown(db.close);
      await db.activeSession();

      await expectV7ColumnUsable(db);
    });

    test('v5 升上来：列补上了', () async {
      await writeV5Database();
      final db = openCurrent();
      addTearDown(db.close);
      await db.activeSession();

      await expectV7ColumnUsable(db);
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

/// v2 出厂时的 schema。
///
/// 用裸 DDL 而不是 Dart 表类，理由与上面的 [_V1Database] 一样，共两条。第一条是
/// 它不引入代码生成：整个文件保持为一份普通测试，没有自己的构建步骤。第二条更
/// 要紧——裸 DDL 把这个形态**冻住了**。用表类写的夹具会跟着 `app_database.dart`
/// 一起演进，日后有人改了那些类，夹具就会悄悄不再代表 v2，下面每条断言都会在
/// 迁移代码一行没跑的情况下通过。这些语句是冻住的：不要为了对齐当前 schema 去
/// 「修」它们。
///
/// `insights` 正是被测的那张表。它的 `record_id` 是一个普通的、可为空的文本列，
/// **没有** `REFERENCES`——正是这个形态让孤儿行活过了 `deleteDemoData`。这就是
/// 那个 bug，也正是 v3 要重建掉的东西。
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

/// v3 出厂时的 schema：`sleep_records.quality` 仍是 `NOT NULL`，
/// 且没有 `active_sessions` 表。
///
/// 理由与上面的 [_V1Database]、[_V2Database] 完全一样，最要紧的一条是裸 DDL 把
/// 这个形态**冻住了**：用表类写的夹具会跟着 `app_database.dart` 一起演进，v4 的
/// `quality.nullable()` 一落，它就悄悄不再代表 v3，v3→v4 那几条断言会在迁移代码
/// 一行没跑的情况下全绿。
class _V3Database extends AppDatabase {
  _V3Database(super.executor);

  @override
  int get schemaVersion => 3;

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
              record_id TEXT
                REFERENCES sleep_records (id) ON DELETE CASCADE,
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

/// v4 出厂时的 schema：`sleep_records.quality` 已可空，`active_sessions` 已存在，
/// 但还没有 `scene_id`。
///
/// 理由与 [_V1Database] / [_V2Database] / [_V3Database] 完全一样，最要紧的一条是
/// 裸 DDL 把这个形态**冻住了**：用表类写的夹具会跟着 `app_database.dart` 一起演进，
/// `sceneId` 一落，它就悄悄不再代表 v4，v4→v5 那条断言会在迁移代码一行没跑的情况
/// 下全绿。
class _V4Database extends AppDatabase {
  _V4Database(super.executor);

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await customStatement('''
            CREATE TABLE sleep_records (
              id TEXT NOT NULL,
              start_at_utc INTEGER NOT NULL,
              end_at_utc INTEGER NOT NULL,
              time_zone_id TEXT NOT NULL DEFAULT 'UTC',
              quality INTEGER,
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
              record_id TEXT
                REFERENCES sleep_records (id) ON DELETE CASCADE,
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
            CREATE TABLE active_sessions (
              id TEXT NOT NULL,
              start_at_utc INTEGER NOT NULL,
              time_zone_id TEXT NOT NULL DEFAULT 'UTC',
              wake_minutes INTEGER NOT NULL,
              alarm_enabled INTEGER NOT NULL DEFAULT 0,
              noise_id TEXT,
              noise_volume REAL NOT NULL DEFAULT 0.5,
              created_at INTEGER NOT NULL,
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

/// The schema as it shipped in v6: v5 plus `clip_journal` / `waveform_envelope` /
/// `labeled_at_utc`.
///
/// 与上面几份夹具同一条理由，**用裸 DDL 把形态冻住**：`auto_analysis` 一落进表类，
/// 用表类写的夹具就会悄悄开始代表 v7，v6→v7 那几条断言会在迁移代码一行没跑的情况下
/// 全绿——而真实用户升上来时那一列根本不存在。
class _V6Database extends AppDatabase {
  _V6Database(super.executor);

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await customStatement('''
            CREATE TABLE sleep_records (
              id TEXT NOT NULL,
              start_at_utc INTEGER NOT NULL,
              end_at_utc INTEGER NOT NULL,
              time_zone_id TEXT NOT NULL DEFAULT 'UTC',
              quality INTEGER,
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
              waveform_envelope TEXT,
              labeled_at_utc INTEGER,
              PRIMARY KEY (id)
            )
          ''');
          await customStatement('''
            CREATE TABLE insights (
              id TEXT NOT NULL,
              record_id TEXT
                REFERENCES sleep_records (id) ON DELETE CASCADE,
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
            CREATE TABLE active_sessions (
              id TEXT NOT NULL,
              start_at_utc INTEGER NOT NULL,
              time_zone_id TEXT NOT NULL DEFAULT 'UTC',
              wake_minutes INTEGER NOT NULL,
              alarm_enabled INTEGER NOT NULL DEFAULT 0,
              noise_id TEXT,
              noise_volume REAL NOT NULL DEFAULT 0.5,
              scene_id TEXT,
              created_at INTEGER NOT NULL,
              clip_journal TEXT,
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

/// The schema as it shipped in v7: v6 plus `sound_clips.auto_analysis`.
///
/// **这一版的形状与 v8 完全相同**——v8 那条迁移只改数据（把旧引擎的判断清回
/// `pending`），不加列。所以这个夹具存在的理由与别的夹具不同：它冻住的不是列集，
/// 而是**升级前那一刻的数据状态**（一条 `analysed` 的、带着手写阈值结论的片段）。
class _V7Database extends AppDatabase {
  _V7Database(super.executor);

  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await customStatement('''
            CREATE TABLE sleep_records (
              id TEXT NOT NULL,
              start_at_utc INTEGER NOT NULL,
              end_at_utc INTEGER NOT NULL,
              time_zone_id TEXT NOT NULL DEFAULT 'UTC',
              quality INTEGER,
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
              waveform_envelope TEXT,
              labeled_at_utc INTEGER,
              auto_analysis TEXT,
              PRIMARY KEY (id)
            )
          ''');
          await customStatement('''
            CREATE TABLE insights (
              id TEXT NOT NULL,
              record_id TEXT
                REFERENCES sleep_records (id) ON DELETE CASCADE,
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
            CREATE TABLE active_sessions (
              id TEXT NOT NULL,
              start_at_utc INTEGER NOT NULL,
              time_zone_id TEXT NOT NULL DEFAULT 'UTC',
              wake_minutes INTEGER NOT NULL,
              alarm_enabled INTEGER NOT NULL DEFAULT 0,
              noise_id TEXT,
              noise_volume REAL NOT NULL DEFAULT 0.5,
              scene_id TEXT,
              created_at INTEGER NOT NULL,
              clip_journal TEXT,
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

/// The schema as it shipped in v8: **与 v7 逐列相同**——v8 只改数据（把旧引擎的
/// 判断清回 `pending`），不加列。
///
/// 直接复用 v7 的 DDL、只改版本号：这个夹具要冻住的是「v9 升级前那一刻」的数据状态
/// （一份 YAMNet 写下的 `analysed` 结论），列集与 v7 没有差别。
class _V8Database extends _V7Database {
  _V8Database(super.executor);

  @override
  int get schemaVersion => 8;
}

/// The schema as it shipped in v9: **与 v8 逐列相同**——v9 也只改数据（把 YAMNet
/// 旧口径的判断清回 `pending`），不加列。
///
/// 这个夹具要冻住的是「v10 升级前那一刻」：库里躺着 v9 口径写下的 `analysed`
/// （其中一批是有声音、但两条线都没过的弃权）。
class _V9Database extends _V8Database {
  _V9Database(super.executor);

  @override
  int get schemaVersion => 9;
}

/// The schema as it shipped in v5: v4 plus `active_sessions.scene_id`.
///
/// 同样用裸 DDL 把形态冻住。`clip_journal` / `waveform_envelope` / `labeled_at_utc`
/// 这三列一落进表类，用表类写的夹具就会悄悄开始代表 v6，v5→v6 那几条断言会在
/// 迁移代码一行没跑的情况下全绿。
class _V5Database extends AppDatabase {
  _V5Database(super.executor);

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await customStatement('''
            CREATE TABLE sleep_records (
              id TEXT NOT NULL,
              start_at_utc INTEGER NOT NULL,
              end_at_utc INTEGER NOT NULL,
              time_zone_id TEXT NOT NULL DEFAULT 'UTC',
              quality INTEGER,
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
              record_id TEXT
                REFERENCES sleep_records (id) ON DELETE CASCADE,
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
            CREATE TABLE active_sessions (
              id TEXT NOT NULL,
              start_at_utc INTEGER NOT NULL,
              time_zone_id TEXT NOT NULL DEFAULT 'UTC',
              wake_minutes INTEGER NOT NULL,
              alarm_enabled INTEGER NOT NULL DEFAULT 0,
              noise_id TEXT,
              noise_volume REAL NOT NULL DEFAULT 0.5,
              scene_id TEXT,
              created_at INTEGER NOT NULL,
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
