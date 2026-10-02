# 睡眠会话与回顾 实现计划（plan A）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在「夜深」里加上「开始睡眠 → 睡眠会话页 → 结束落库 → 回顾补充感受」这条完整链路，把起床闹钟接上真实本地通知，并把应用显示名改成中文。

**Architecture:** 会话状态存进 SQLite 的一张单行表（主键固定 `'active'`），所以跨重启存活、不需要内存态兜底。会话页是一个推入式全屏路由，圆环画「已睡时长 ÷ 计划时长」。结束时在一个事务里写 `SleepRecord` 并删掉会话行，然后切到「回顾」Tab 补主观感受。起床闹钟复用既有的通知调度器，但走一个新的一次性 API。

**Tech Stack:** Flutter 3.47 / Dart 3.13、Riverpod、go_router、Drift(SQLite)、flutter_local_notifications。**本计划不新增任何依赖。**

## Global Constraints

- 界面文案、注释、文档一律中文；代码标识符英文。
- 颜色、圆角、动效曲线只从 `AppTokens.of(context)` / `AppRadii` / `AppDurations` / `AppMotion` 取，**不在 widget 里写死色值**。
- Widget 不直接读写数据库；页面只读 provider，写路径走仓库。
- 每个推入的页面都要自己提供 `Atmosphere` + `Scaffold` + `Material` 祖先（走 `Subpage`，或像会话页那样显式自带），否则 `Text` 会落到 Flutter 的黄色双下划线错误样式。
- `lib/**/*.g.dart` 由 Drift 生成，**不手工修改**；改表结构后必须跑 `dart run build_runner build`。
- `SleepRepository.save()` 的 `stages` 传 `null` 表示「保持已有阶段不变」；传 `[]` 才是替换为空。
- 项目规范命令：`dart format .`、`flutter analyze`（必须 **No issues found**）、`flutter test`。
- 提交信息用中文，conventional commits 前缀（`feat:` / `fix:` / `test:` / `docs:` / `refactor:`），**不加任何署名尾注**。

---

## 文件结构

**新建**

| 文件 | 职责 |
| --- | --- |
| `lib/features/sleep/domain/sleep_session.dart` | `SleepSession` 领域模型 + 计划时长/进度/守门判定的纯函数 |
| `lib/features/sleep/data/session_repository.dart` | 会话的读、开始、改、结束（事务）、丢弃；provider |
| `lib/features/sleep/presentation/widgets/quality_rating.dart` | 共享的星级评分行（表单、回顾页、结束评星弹层三处共用） |
| `lib/features/session/presentation/sleep_session_page.dart` | 会话页（路由 `/sleep/session`） |
| `lib/features/session/presentation/widgets/wake_dial.dart` | 日晷圆环（进度弧 + 中心读数） |
| `lib/features/session/presentation/widgets/session_drawer.dart` | 会话页的设定抽屉（起床闹钟 / 鼾声开关 / 白噪音 / 说明） |
| `lib/features/session/presentation/sheets/quality_rating_sheet.dart` | 结束睡眠时的就地评星（可跳过） |
| `lib/features/log/presentation/review_page.dart` | 回顾 Tab（含换一晚） |
| `lib/features/log/presentation/review_night_picker.dart` | 换一晚的选择弹层 |
| `lib/features/log/presentation/log_new_page.dart` | 手动补录路由 `/log/new` |

**修改**

| 文件 | 改动 |
| --- | --- |
| `lib/core/database/app_database.dart` | 新增 `ActiveSessions` 表、`quality` 可空、schemaVersion 4、迁移、会话查询 |
| `lib/features/sleep/domain/sleep_entry.dart` | `quality` 改为 `SleepQuality?`；`scoreSource` 在质量为空时返回 `none` |
| `lib/features/sleep/data/sleep_repository.dart` | `save()` 的 `quality` 可空；`_toEntry` 读可空质量 |
| `lib/features/settings/domain/sleep_export.dart` | CSV 质量列写空串、JSON 写 `null` |
| `lib/features/home/presentation/home_page.dart` | 质量标签空值处理；「开始睡眠」主按钮；「正在睡眠」卡 |
| `lib/features/log/presentation/log_page.dart` | 改为纯推入页；质量默认无选中 |
| `lib/app/app_shell.dart` | `AppTab.log` 的 label 改「回顾」（**id 保持 `'log'`**） |
| `lib/app/app.dart` | 新路由 `/sleep/session`、`/log/new`；Tab 分派 |
| `lib/app/reminder_sync.dart` | 启动时同时按活跃会话重排闹钟、并让 `9002` 让位 |
| `lib/core/platform/reminders.dart` | `wakeAlarmId`、`scheduleOnce`、`syncAlarm` |
| `lib/features/sleep/presentation/widgets/stage_style.dart` | 新增 `qualityColor(tokens, quality?)` |
| iOS / macOS `Info.plist`、`web/index.html`、`web/manifest.json` | 显示名 |

---

## Task 1: 应用显示名改为「夜深」

**Files:**
- Modify: `ios/Runner/Info.plist`, `macos/Runner/Info.plist`, `web/index.html`, `web/manifest.json`
- Test: `test/app_display_name_test.dart`（新建）

**Interfaces:**
- Consumes: 无
- Produces: 无（纯配置改动）

- [ ] **Step 1: 写失败的测试**

新建 `test/app_display_name_test.dart`：

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 显示名是纯配置，没有 widget 能断言它。
///
/// 用纯 `test()` 直接读文件：这几份文件就是构建产物里那几个键的**唯一**来源，
/// 读它们与读 `flutter build` 出来的包等价，但不需要构建。
void main() {
  group('应用显示名', () {
    test('iOS 桌面显示「夜深」', () {
      final plist = File('ios/Runner/Info.plist').readAsStringSync();
      expect(
        plist,
        contains('<key>CFBundleDisplayName</key>\n\t<string>夜深</string>'),
      );
    });

    test('macOS 补上 CFBundleDisplayName', () {
      final plist = File('macos/Runner/Info.plist').readAsStringSync();
      expect(
        plist,
        contains('<key>CFBundleDisplayName</key>\n\t<string>夜深</string>'),
      );
    });

    test('web 的 title 与 apple 标题都是「夜深」', () {
      final html = File('web/index.html').readAsStringSync();
      expect(html, contains('<title>夜深</title>'));
      expect(
        html,
        contains('<meta name="apple-mobile-web-app-title" content="夜深">'),
      );
    });

    test('web manifest 的 name 与 short_name 都是「夜深」', () {
      final manifest = jsonDecode(File('web/manifest.json').readAsStringSync())
          as Map<String, dynamic>;
      expect(manifest['name'], '夜深');
      expect(manifest['short_name'], '夜深');
    });

    /// 反向护栏：这三处**必须**保持英文。
    ///
    /// `PRODUCT_NAME` 决定 macOS 的 `.app` 包名与可执行文件名，改成中文会让构建
    /// 产物路径变成中文，并顺着 `EXECUTABLE_NAME` 影响一串构建设置；`CFBundleName`
    /// 是对内的短名（15 字节上限）。改错了不会有任何功能报错，只会在构建时炸，
    /// 所以在这里钉住。
    test('构建路径相关的名字仍是 night_sleep', () {
      expect(
        File('macos/Runner/Configs/AppInfo.xcconfig').readAsStringSync(),
        contains('PRODUCT_NAME = night_sleep'),
      );
      expect(
        File('ios/Runner/Info.plist').readAsStringSync(),
        contains('<key>CFBundleName</key>\n\t<string>night_sleep</string>'),
      );
    });
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/app_display_name_test.dart`
Expected: 前 4 条 FAIL（现在分别是 `Night Sleep` / 缺键 / `night_sleep`），最后一条 PASS。

- [ ] **Step 3: 改四处配置**

`ios/Runner/Info.plist`：把

```xml
	<key>CFBundleDisplayName</key>
	<string>Night Sleep</string>
```

改成

```xml
	<key>CFBundleDisplayName</key>
	<string>夜深</string>
```

`macos/Runner/Info.plist`：在 `<dict>` 之后、`CFBundleExecutable` 之前插入（macOS 原来没有这个键）：

```xml
	<key>CFBundleDisplayName</key>
	<string>夜深</string>
```

`web/index.html`：两处替换

```html
  <meta name="apple-mobile-web-app-title" content="夜深">
```

```html
  <title>夜深</title>
```

`web/manifest.json`：两处替换

```json
    "name": "夜深",
    "short_name": "夜深",
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/app_display_name_test.dart`
Expected: 5 条全 PASS。

- [ ] **Step 5: 格式化、分析、提交**

```bash
dart format .
flutter analyze
git add ios/Runner/Info.plist macos/Runner/Info.plist web/index.html web/manifest.json test/app_display_name_test.dart
git commit -m "feat: 应用显示名改为「夜深」

iOS 的 CFBundleDisplayName 由 Night Sleep 改为夜深；macOS 原本没有这个键，
补上一个。web 的 title 与 manifest 同步。

PRODUCT_NAME 与 CFBundleName 刻意保持 night_sleep 不动：前者决定 macOS 的
.app 包名与可执行文件名，改中文会让构建产物路径变成中文；后者是对内的短名。
测试里有一条反向护栏钉住这两处。"
```

---

## Task 2: schema v4 —— 会话表 + 质量可空

这一条包含两处结构改动，**必须同一个 commit**：它们是同一个 schema 版本，
且 `quality` 放开 `NOT NULL` 之后 `SleepRepository` 会立刻编译不过，拆开会让中间那个 commit 的树是坏的。

**Files:**
- Modify: `lib/core/database/app_database.dart`
- Modify: `lib/features/sleep/domain/sleep_entry.dart`
- Modify: `lib/features/sleep/data/sleep_repository.dart`
- Modify: `lib/features/settings/domain/sleep_export.dart`
- Modify: `lib/features/home/presentation/home_page.dart:662`
- Modify: `lib/features/log/presentation/log_page.dart`
- Modify: `lib/features/sleep/presentation/widgets/stage_style.dart`
- Test: `test/schema_migration_test.dart`, `test/sleep_data_test.dart`, `test/sleep_export_test.dart`, `test/pages_widget_test.dart`

**Interfaces:**
- Consumes: 无
- Produces:
  - `class ActiveSessions extends Table`，drift 行类 `ActiveSession`
  - `AppDatabase.activeSession()` → `Future<ActiveSession?>`
  - `AppDatabase.watchActiveSession()` → `Stream<ActiveSession?>`
  - `AppDatabase.saveActiveSession(ActiveSessionsCompanion)` → `Future<void>`
  - `AppDatabase.deleteActiveSession()` → `Future<void>`
  - `SleepEntry.quality` 类型变为 `SleepQuality?`
  - `SleepRepository.save({..., required SleepQuality? quality, ...})`
  - `qualityColor(AppTokens, SleepQuality?)` → `Color`（`stage_style.dart`）

- [ ] **Step 1: 写失败的迁移测试**

在 `test/schema_migration_test.dart` 末尾（`_V1Database` 之前）追加 v3 夹具与用例。
夹具用**裸 DDL 冻住 v3 的形态**，理由与既有的 `_V1Database` / `_V2Database` 相同：

```dart
/// v3 出厂时的 schema：`sleep_records.quality` 仍是 `NOT NULL`，
/// 且没有 `active_sessions` 表。
///
/// 这些语句是冻住的：不要为了对齐当前 schema 去「修」它们。
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

/// 写出一份 v3 的库：一条有质量的记录、一条阶段、一条设置。
Future<void> _writeV3(String path) async {
  final v3 = _V3Database(NativeDatabase(File(path)));
  await v3.customStatement(
    "INSERT INTO sleep_records (id, start_at_utc, end_at_utc, time_zone_id, "
    "quality, notes, source, created_at, updated_at) VALUES "
    "('v3-night', 1759000000000000, 1759028800000000, 'UTC', 4, "
    "'v3 时期写的备注', 'manual', 1759000000000000, 1759000000000000)",
  );
  await v3.customStatement(
    "INSERT INTO sleep_stage_segments (id, record_id, stage, start_at_utc, "
    "end_at_utc, source) VALUES ('v3-night-stage-0', 'v3-night', 'deep', "
    "1759000000000000, 1759003600000000, 'import')",
  );
  await v3.customStatement(
    "INSERT INTO app_settings (id, theme_mode, sleep_goal_minutes, "
    "wake_reminder_minutes) VALUES ('default', 'dark', 450, 420)",
  );
  await v3.close();
}
```

再加一组用例：

```dart
  group('v3 → v4', () {
    test('夹具确实是 v3，而升级后确实是 v4', () async {
      await _writeV3(path);
      final v3 = _V3Database(NativeDatabase(File(path)));
      expect(await _userVersion(v3), 3);
      await v3.customStatement('SELECT 1');
      await v3.close();

      final db = AppDatabase(NativeDatabase(File(path)));
      addTearDown(db.close);
      await db.allRecords(); // 触发迁移
      expect(await _userVersion(db), 4);
    });

    test('v3 的记录、阶段、设置一行不动', () async {
      await _writeV3(path);
      final db = AppDatabase(NativeDatabase(File(path)));
      addTearDown(db.close);

      final records = await db.allRecords();
      expect(records, hasLength(1));
      expect(records.single.id, 'v3-night');
      expect(records.single.quality, 4);
      expect(records.single.notes, 'v3 时期写的备注');
      expect(await db.stagesFor('v3-night'), hasLength(1));

      final settings = await db.getSettings();
      expect(settings.themeMode, 'dark');
      expect(settings.sleepGoalMinutes, 450);
      expect(settings.wakeReminderMinutes, 420);
    });

    /// 表重建的要害：`quality` 的可空性**真的**放开了。
    test('重建后 quality 可以写空', () async {
      await _writeV3(path);
      final db = AppDatabase(NativeDatabase(File(path)));
      addTearDown(db.close);
      await db.allRecords(); // 触发迁移

      await db.saveRecord(
        SleepRecordsCompanion.insert(
          id: const Value('unrated'),
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
      await _writeV3(path);
      final db = AppDatabase(NativeDatabase(File(path)));
      addTearDown(db.close);
      await db.allRecords();

      await db.deleteRecord('v3-night');

      expect(await db.stagesFor('v3-night'), isEmpty);
    });

    test('会话表在迁移后可用', () async {
      await _writeV3(path);
      final db = AppDatabase(NativeDatabase(File(path)));
      addTearDown(db.close);
      await db.allRecords();

      expect(await db.activeSession(), isNull);
      await db.saveActiveSession(
        ActiveSessionsCompanion.insert(
          id: const Value('active'),
          startAtUtc: DateTime.utc(2026, 8, 30, 23, 14),
          timeZoneId: const Value('Asia/Shanghai'),
          wakeMinutes: const Value(420),
          createdAt: DateTime.utc(2026, 8, 30, 23, 14),
        ),
      );
      expect((await db.activeSession())!.wakeMinutes, 420);
    });
  });
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/schema_migration_test.dart`
Expected: 编译失败（`_V3Database` 的 DDL 引用不到 `ActiveSessionsCompanion`、`db.activeSession` 不存在）。
先只加夹具与「夹具确实是 v3」两条，跑一次确认 v3 夹具能建起来；再补其余用例。

- [ ] **Step 3: 改表定义并重新生成**

`lib/core/database/app_database.dart`：

1. `SleepRecords` 的 quality 改为可空：

```dart
  /// 用户自评的主观质量，1–5。**可以为空**：睡眠会话结束时会就地评一次星，
  /// 用户跳过就是真的没有评分。为空时 `SleepEntry.scoreSource` 返回 `none`，
  /// 界面显示「未评分」，统计的平均分把它排除在外——绝不填一个占位值冒充。
  IntColumn get quality => integer().nullable()();
```

2. 在 `AppSettings` 之前插入新表：

```dart
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
```

3. 把 `ActiveSessions` 加进 `@DriftDatabase(tables: [...])` 列表。
4. `schemaVersion` 改为 `4`。
5. `onUpgrade` 追加：

```dart
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
```

6. 在 `// ── Settings ──` 之前加会话查询：

```dart
  // ── Active session ────────────────────────────────────────────────────────

  /// 当前会话，没有则为 `null`。主键固定，所以最多一行。
  Future<ActiveSession?> activeSession() {
    return (select(activeSessions)
          ..where((table) => table.id.equals('active')))
        .getSingleOrNull();
  }

  Stream<ActiveSession?> watchActiveSession() {
    return (select(activeSessions)
          ..where((table) => table.id.equals('active')))
        .watchSingleOrNull();
  }

  Future<void> saveActiveSession(ActiveSessionsCompanion session) async {
    await into(activeSessions).insertOnConflictUpdate(session);
  }

  Future<void> deleteActiveSession() async {
    await (delete(activeSessions)..where((table) => table.id.equals('active')))
        .go();
  }
```

7. `deleteAllUserData` 里加一句，理由与它已有的兜底注释一致：

```dart
      // 残留的会话会在下次启动时凭空长出一条记录。
      await delete(activeSessions).go();
```

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: 生成成功，`app_database.g.dart` 里出现 `ActiveSession` 行类，且 `SleepRecord.quality` 是 `int?`。

- [ ] **Step 4: 贯通领域层的空质量**

`lib/features/sleep/domain/sleep_entry.dart`：

```dart
  /// 用户自评的主观质量。`null` 表示**还没评过**（会话结束跳过了评星，
  /// 或用户还没到回顾页去评）。为空时这条记录不产生评分。
  final SleepQuality? quality;
```

构造函数参数改为 `required this.quality,`（类型变了，位置不变）。

`scoreSource` 的第一道判断：

```dart
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
```

`estimateScore` / `estimateSummary` 的调用处：把 `quality` 换成 `quality!`。
**这是安全的，且必须写注释说明为什么**：

```dart
  int? get score => switch (scoreSource) {
        ScoreSource.modelInsight => insight!.score,
        // `scoreSource` 已经在 quality 为空时返回 none，走到这里必然有值。
        ScoreSource.onDeviceEstimate =>
          estimateScore(durationHours, quality!, loggedEvents),
        ScoreSource.none => null,
      };
```

`estimatedSummary` 里同样用 `quality!`。

`lib/features/sleep/data/sleep_repository.dart` 的 `_toEntry`：

```dart
      quality: row.quality == null ? null : SleepQuality.fromValue(row.quality!),
```

`save()` 的签名改 `required SleepQuality? quality,`，companion 改为：

```dart
          quality: Value(quality),
```

（`Value(quality)` 里 `quality` 是 `SleepQuality?`，需要 `Value(quality?.value)`。）

`lib/features/sleep/presentation/widgets/stage_style.dart` 追加：

```dart
/// `Q_LBL` 每一档的语义色。未评分（`null`）取中性色——那不是一个档位，
/// 不该借用任何一档的颜色。
Color qualityColor(AppTokens tokens, SleepQuality? quality) => switch (quality) {
      null => tokens.textMuted,
      SleepQuality.veryPoor => tokens.danger,
      SleepQuality.poor => tokens.warn,
      SleepQuality.fair => tokens.caution,
      SleepQuality.good => tokens.accent,
      SleepQuality.excellent => tokens.accentViolet,
    };
```

需要在 `stage_style.dart` 顶部加 `import '../../domain/sleep_quality.dart';`。

- [ ] **Step 5: 改界面与导出对空质量的处理**

`lib/features/home/presentation/home_page.dart:662`：

```dart
                        if (entry.quality != null)
                          Tag(label: entry.quality!.label),
```

`lib/features/settings/domain/sleep_export.dart:127` 与 `:190`：

```dart
        'quality': entry.quality?.value,          // JSON：未评分写 null，不写占位值
```

```dart
        entry.quality?.value?.toString() ?? '',   // CSV：空单元格
```

`lib/features/log/presentation/log_page.dart`：`_quality` 改为可空、**初始无选中**。
这一步与 Task 10 的「改为纯推入页」是两件事，这里只改质量：

```dart
  /// 未评分为 `null`，且**表单初始就是无选中**。
  ///
  /// 原来是 `SleepQuality.good`，那等于应用替用户说了一句他没说过的话，
  /// 并让评分凭空带上 17.5 分的质量分。现在不选就不写。
  SleepQuality? _quality;
```

`initState` 里 `_quality = editing.quality;`（类型自洽）。
星级行与按钮的 `_quality` 用法全部改为可空安全（`_quality == quality` 的 `selected` 判断不变，因为 `SleepQuality?` 与 `SleepQuality` 可以 `==` 比较）。
`_quality.label` 的显示改为：

```dart
                _quality?.label ?? '未评分',
```

`_qualityColor(tokens, _quality)` 调用改为 `qualityColor(tokens, _quality)`，
并删掉 `log_page.dart` 里的私有 `_qualityColor`（已搬到 `stage_style.dart`）。

- [ ] **Step 6: 更新受影响的既有测试**

`test/pages_widget_test.dart:269`：

```dart
      // 表单初始无选中：没碰星级就保存，记录**没有**评分。
      expect(saved.single.quality, isNull, reason: '未选星级就不该写质量');
```

再补一条：点第 4 颗星再保存 → `saved.single.quality == SleepQuality.good`。

`test/record_edit_delete_test.dart:288` 的 `SleepQuality.fair.value` 保持不变（那条测的是编辑既有记录）。

`test/sleep_export_test.dart`：补两条——未评分记录的 JSON 里 `quality` 是 `null`、CSV 的质量列是空串。

- [ ] **Step 7: 跑全套**

Run: `dart format . && flutter analyze && flutter test`
Expected: `No issues found`；全部测试通过。

- [ ] **Step 8: 变异验证迁移测试**

把 `onUpgrade` 里的 `if (from < 4)` 整段注释掉，跑 `flutter test test/schema_migration_test.dart`。
Expected: v3→v4 那几条**必须变红**。确认后恢复。

- [ ] **Step 9: 提交**

```bash
git add lib/core/database/app_database.dart lib/core/database/app_database.g.dart \
        lib/features/sleep/domain/sleep_entry.dart \
        lib/features/sleep/data/sleep_repository.dart \
        lib/features/settings/domain/sleep_export.dart \
        lib/features/home/presentation/home_page.dart \
        lib/features/log/presentation/log_page.dart \
        lib/features/sleep/presentation/widgets/stage_style.dart \
        test/schema_migration_test.dart test/sleep_data_test.dart \
        test/sleep_export_test.dart test/pages_widget_test.dart
git commit -m "feat(db): schema v4 —— 会话表 + 质量可空

两处结构改动同属 v4，必须一起落：quality 放开 NOT NULL 之后仓库层立刻编译
不过，拆开会留下一个坏掉的树。

- 新增单行表 active_sessions（主键固定 'active'），供睡眠会话使用。
- sleep_records.quality 改为可空。SQLite 不能原地改可空性，走 alterTable 重建。
  这是本项目第一次重建一张有子表引用它的表（stages/clips/insights 都指向它），
  迁移期间外键是关的、子表存的是文本 id，重建后引用仍成立——测试钉住了级联。
- quality 为空时 scoreSource 返回 none：不产生评分，而不是喂一个占位值给
  estimateScore（那会让 35 分权重的质量项凭空拿 17.5 分）。
- 记录表单初始无选中，不选就不写质量；导出里 JSON 写 null、CSV 写空单元格。

迁移测试用裸 DDL 冻住 v3 形态，含「夹具确实停在 v3」的自检与级联护栏。"
```

---

## Task 3: 会话领域模型与会话仓库

**Files:**
- Create: `lib/features/sleep/domain/sleep_session.dart`
- Create: `lib/features/sleep/data/session_repository.dart`
- Test: `test/sleep_session_test.dart`（新建）、`test/session_repository_test.dart`（新建）

**Interfaces:**
- Consumes: `ActiveSession`（Task 2）、`SleepQuality?`（Task 2）
- Produces:
  - `class SleepSession`：`startAtUtc`、`timeZoneId`、`wakeMinutes`、`alarmEnabled`、`noiseId`、`noiseVolume`、`createdAtUtc`
  - `SleepSession.plannedDuration` → `Duration`
  - `SleepSession.elapsedAt(DateTime)` → `Duration`
  - `SleepSession.progressAt(DateTime)` → `double`（0–1）
  - `SleepSession.overdueAt(DateTime)` → `bool`
  - `SessionFinishRejection validateSessionDuration(Duration)` → `none | tooShort | tooLong`
  - `class SessionRepository`：`load()`、`start({now, wakeMinutes})`、`update({...})`、`finish({now, quality})`、`discard()`
  - `sessionRepositoryProvider`、`activeSessionProvider`

- [ ] **Step 1: 写失败的领域测试**

新建 `test/sleep_session_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/features/sleep/domain/sleep_session.dart';

void main() {
  SleepSession session({
    required DateTime start,
    int wakeMinutes = 7 * 60,
  }) =>
      SleepSession(
        startAtUtc: start.toUtc(),
        timeZoneId: 'UTC',
        wakeMinutes: wakeMinutes,
        alarmEnabled: false,
        createdAtUtc: start.toUtc(),
      );

  group('计划时长', () {
    test('起床时间在开始之后：当天', () {
      final s = session(start: DateTime(2026, 8, 30, 6, 0));
      expect(s.plannedDuration, const Duration(hours: 1));
    });

    test('起床时间早于开始：跨到次日', () {
      final s = session(start: DateTime(2026, 8, 30, 23, 14));
      expect(s.plannedDuration, const Duration(hours: 7, minutes: 46));
    });

    /// 起床时刻**正好等于**开始时刻时不能得到 0，否则进度会除零。
    test('起床时刻与开始时刻相同：算作次日，不会得到零时长', () {
      final s = session(start: DateTime(2026, 8, 30, 7, 0));
      expect(s.plannedDuration, const Duration(days: 1));
    });
  });

  group('进度', () {
    test('刚开始是 0，到点是一半圈以上', () {
      final start = DateTime(2026, 8, 30, 23, 0);
      final s = session(start: start);
      expect(s.progressAt(start), 0);
      expect(s.progressAt(start.add(const Duration(hours: 4))), closeTo(0.5, 0.01));
    });

    test('超过起床时间后封顶在 1，不溢出', () {
      final start = DateTime(2026, 8, 30, 23, 0);
      final s = session(start: start);
      expect(s.progressAt(start.add(const Duration(hours: 30))), 1.0);
    });

    test('超过起床时间才算 overdue', () {
      final start = DateTime(2026, 8, 30, 23, 0);
      final s = session(start: start);
      expect(s.overdueAt(start.add(const Duration(hours: 7))), isFalse);
      expect(s.overdueAt(start.add(const Duration(hours: 9))), isTrue);
    });
  });

  group('结束守门', () {
    test('零与负时长被拒', () {
      expect(validateSessionDuration(Duration.zero), SessionFinishRejection.tooShort);
      expect(
        validateSessionDuration(const Duration(minutes: -5)),
        SessionFinishRejection.tooShort,
      );
    });

    test('超过 24 小时被拒', () {
      expect(
        validateSessionDuration(const Duration(hours: 24, minutes: 1)),
        SessionFinishRejection.tooLong,
      );
    });

    test('边界值通过', () {
      expect(
        validateSessionDuration(const Duration(minutes: 1)),
        SessionFinishRejection.none,
      );
      expect(
        validateSessionDuration(const Duration(hours: 24)),
        SessionFinishRejection.none,
      );
    });
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/sleep_session_test.dart`
Expected: 编译失败——`sleep_session.dart` 还不存在。

- [ ] **Step 3: 实现领域模型**

新建 `lib/features/sleep/domain/sleep_session.dart`：

```dart
/// 一次正在进行（或刚刚结束）的睡眠会话。
///
/// **它不测量任何东西。** 两个时刻都来自用户自己按下的按钮，起床时间来自用户
/// 自己的设定。圆环画的是「已过时长 ÷ 计划时长」，两个数都是推导出来的，
/// 不是推断出来的。
library;

class SleepSession {
  const SleepSession({
    required this.startAtUtc,
    required this.timeZoneId,
    required this.wakeMinutes,
    required this.alarmEnabled,
    this.noiseId,
    this.noiseVolume = 0.5,
    required this.createdAtUtc,
  });

  /// 点「开始睡眠」的真实时刻。
  final DateTime startAtUtc;

  final String timeZoneId;

  /// 设定的起床时间，距本地午夜的分钟数。**起床时间就是闹钟时间**。
  final int wakeMinutes;

  /// 到点响不响。只影响通知，不影响圆环的目标。
  final bool alarmEnabled;

  /// 正在播放的助眠音效 id，`null` 表示没选。
  final String? noiseId;
  final double noiseVolume;

  final DateTime createdAtUtc;

  /// 起床时刻：从会话开始起，下一个落在 [wakeMinutes] 的**本地墙上时刻**。
  ///
  /// 用 `DateTime(y, m, d, h, min)` 构造而不是加时长，因此跨夏令时切换日时
  /// 仍落在同一个钟点上——与 `ReminderScheduler.nextOccurrence` 是同一条规则。
  /// 严格比较：正好等于开始时刻的那一秒已经过去，归到次日（否则计划时长会是
  /// 零，进度除零）。
  DateTime get _wakeAt {
    final start = startAtUtc.toLocal();
    final hour = wakeMinutes ~/ 60;
    final minute = wakeMinutes % 60;
    final sameDay = DateTime(start.year, start.month, start.day, hour, minute);
    if (sameDay.isAfter(start)) return sameDay;
    return DateTime(start.year, start.month, start.day + 1, hour, minute);
  }

  /// 计划睡多久：起床时刻 − 开始时刻。恒为正。
  Duration get plannedDuration => _wakeAt.difference(startAtUtc.toLocal());

  Duration elapsedAt(DateTime now) => now.toUtc().difference(startAtUtc);

  /// 圆环画的那条弧。超过起床时间后封顶在 1，不溢出也不回绕。
  double progressAt(DateTime now) {
    final planned = plannedDuration.inSeconds;
    if (planned <= 0) return 1;
    return (elapsedAt(now).inSeconds / planned).clamp(0.0, 1.0);
  }

  /// 是否已经过了设定的起床时间。
  bool overdueAt(DateTime now) => elapsedAt(now) > plannedDuration;

  /// 已睡时长的整分读法，供界面显示。
  String elapsedLabelAt(DateTime now) {
    final total = elapsedAt(now).inMinutes;
    if (total < 0) return '0h 0m';
    return '${total ~/ 60}h ${total % 60}m';
  }

  /// 超出起床时间多久，用于「已超过起床时间 42m」。
  String overdueLabelAt(DateTime now) {
    final over = elapsedAt(now) - plannedDuration;
    final minutes = over.inMinutes < 0 ? 0 : over.inMinutes;
    if (minutes < 60) return '${minutes}m';
    return '${minutes ~/ 60}h${minutes % 60}m';
  }

  SleepSession copyWith({
    int? wakeMinutes,
    bool? alarmEnabled,
    Object? noiseId = _unset,
    double? noiseVolume,
  }) {
    return SleepSession(
      startAtUtc: startAtUtc,
      timeZoneId: timeZoneId,
      wakeMinutes: wakeMinutes ?? this.wakeMinutes,
      alarmEnabled: alarmEnabled ?? this.alarmEnabled,
      // `noiseId` 可以**被显式设回 null**（用户取消选择），所以不能用
      // `?? this.noiseId` —— 那样就再也清不掉了。
      noiseId: identical(noiseId, _unset) ? this.noiseId : noiseId as String?,
      noiseVolume: noiseVolume ?? this.noiseVolume,
      createdAtUtc: createdAtUtc,
    );
  }

  static const _unset = Object();
}

/// 结束会话时时长的合法性判定。
enum SessionFinishRejection {
  none,

  /// 时长为零或负——点了开始就立刻点结束。
  tooShort,

  /// 超过 24 小时——点了开始忘了结束。
  tooLong,
}

/// 与 `SleepWindow.isPlausible` 同一口径：`0 < 时长 ≤ 24h`。
///
/// 越界时**不落库**：两种情形都不该静默变成一条睡眠记录。
SessionFinishRejection validateSessionDuration(Duration duration) {
  if (duration <= Duration.zero) return SessionFinishRejection.tooShort;
  if (duration > const Duration(hours: 24)) return SessionFinishRejection.tooLong;
  return SessionFinishRejection.none;
}
```

- [ ] **Step 4: 跑领域测试**

Run: `flutter test test/sleep_session_test.dart`
Expected: 全 PASS。

- [ ] **Step 5: 写失败的仓库测试**

新建 `test/session_repository_test.dart`：

```dart
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/core/database/app_database.dart';
import 'package:night_sleep/features/sleep/data/session_repository.dart';
import 'package:night_sleep/features/sleep/domain/sleep_quality.dart';

void main() {
  late AppDatabase database;
  late SessionRepository repo;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repo = SessionRepository(database);
  });
  tearDown(() => database.close());

  final start = DateTime.utc(2026, 8, 30, 15, 14); // 本地 23:14（CST）
  final end = DateTime.utc(2026, 8, 30, 23, 2); // 本地 07:02

  test('没有会话时 load 返回 null', () async {
    expect(await repo.load(), isNull);
  });

  test('start 写入一行，且默认值正确', () async {
    final session = await repo.start(now: start.toLocal());

    expect(session.startAtUtc, start);
    expect(session.alarmEnabled, isFalse, reason: '闹钟默认关，不继承任何偏好');
    expect(session.noiseId, isNull, reason: '不替用户选一个音');
    expect(session.noiseVolume, 0.5);
    expect(await repo.load(), isNotNull);
  });

  test('start 采用传入的起床时间，未传时用 07:00', () async {
    expect((await repo.start(now: start.toLocal())).wakeMinutes, 7 * 60);
    await repo.discard();
    expect(
      (await repo.start(now: start.toLocal(), wakeMinutes: 6 * 60 + 30))
          .wakeMinutes,
      390,
    );
  });

  test('update 只改传入的字段', () async {
    await repo.start(now: start.toLocal());
    await repo.update(alarmEnabled: true, wakeMinutes: 8 * 60);

    final session = (await repo.load())!;
    expect(session.alarmEnabled, isTrue);
    expect(session.wakeMinutes, 480);
    expect(session.startAtUtc, start, reason: '开始时刻不该被改');
  });

  test('update 可以把 noiseId 显式清回 null', () async {
    await repo.start(now: start.toLocal());
    await repo.update(noiseId: 'rain');
    expect((await repo.load())!.noiseId, 'rain');

    await repo.update(noiseId: null);
    expect((await repo.load())!.noiseId, isNull, reason: '取消选择必须能存下去');
  });

  test('finish 写一条 source=session 的记录并清掉会话行', () async {
    await repo.start(now: start.toLocal(), wakeMinutes: 7 * 60);
    await repo.finish(now: end.toLocal(), quality: SleepQuality.good);

    expect(await repo.load(), isNull, reason: '会话行必须被删掉');

    final rows = await database.allRecords();
    expect(rows, hasLength(1));
    expect(rows.single.source, 'session');
    expect(rows.single.startAtUtc, start);
    expect(rows.single.endAtUtc, end);
    expect(rows.single.quality, SleepQuality.good.value);
  });

  test('finish 允许质量为空（跳过评星）', () async {
    await repo.start(now: start.toLocal());
    await repo.finish(now: end.toLocal(), quality: null);

    expect((await database.allRecords()).single.quality, isNull);
  });

  test('finish 不写任何阶段', () async {
    await repo.start(now: start.toLocal());
    await repo.finish(now: end.toLocal(), quality: null);

    final id = (await database.allRecords()).single.id;
    expect(await database.stagesFor(id), isEmpty);
  });

  test('finish 按醒来日归档', () async {
    await repo.start(now: start.toLocal());
    await repo.finish(now: end.toLocal(), quality: null);

    final row = (await database.allRecords()).single;
    expect(row.endAtUtc.toLocal().day, 31);
  });

  test('没有会话时 finish 抛错，不写记录', () async {
    await expectLater(
      repo.finish(now: end.toLocal(), quality: null),
      throwsA(isA<StateError>()),
    );
    expect(await database.allRecords(), isEmpty);
  });

  test('discard 只删会话行，不写记录', () async {
    await repo.start(now: start.toLocal());
    await repo.discard();

    expect(await repo.load(), isNull);
    expect(await database.allRecords(), isEmpty);
  });

  test('删除全部本地数据会清掉残留的会话', () async {
    await repo.start(now: start.toLocal());
    await database.deleteAllUserData();

    expect(await repo.load(), isNull);
  });

  test('重启后会话仍在（数据在库里，不靠内存）', () async {
    await repo.start(now: start.toLocal(), wakeMinutes: 6 * 60);

    final reopened = SessionRepository(database);
    expect((await reopened.load())!.wakeMinutes, 360);
  });
}
```

- [ ] **Step 6: 跑测试确认失败**

Run: `flutter test test/session_repository_test.dart`
Expected: 编译失败——`session_repository.dart` 还不存在。

- [ ] **Step 7: 实现会话仓库**

新建 `lib/features/sleep/data/session_repository.dart`：

```dart
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart' as db;
import '../domain/sleep_quality.dart';
import '../domain/sleep_session.dart';

/// 活跃睡眠会话的读写。
///
/// 会话只活一行（主键固定 `'active'`，见 `ActiveSessions` 的注释），所以这里的
/// 每一个动作都是「最多一行」的语义，不需要任何判重。
class SessionRepository {
  SessionRepository(this._db);

  final db.AppDatabase _db;

  /// 默认起床时间 07:00。**与设置页显示的那个默认值同一个来源**，不另写一个
  /// 字面量——两处各写一份时，改了其中一处就会让「界面显示 07:00、库里是 06:00」
  /// 这种只在特定操作后才显形的问题活下来。
  static const defaultWakeMinutes = 7 * 60;

  static const sessionId = 'active';

  Future<SleepSession?> load() async {
    final row = await _db.activeSession();
    return row == null ? null : _toSession(row);
  }

  /// 开始一个会话。已有一个在跑时**直接覆盖**它——那意味着用户又按了一次
  /// 「开始睡眠」，按新的开始时刻重新计时才是他的意思。
  Future<SleepSession> start({DateTime? now, int? wakeMinutes}) async {
    final at = (now ?? DateTime.now()).toUtc();
    final resolvedWake = wakeMinutes ?? await _defaultWakeMinutes();

    await _db.saveActiveSession(
      db.ActiveSessionsCompanion.insert(
        id: const Value(sessionId),
        startAtUtc: at,
        timeZoneId: Value((now ?? DateTime.now()).timeZoneName),
        wakeMinutes: Value(resolvedWake),
        createdAt: at,
      ),
    );

    return (await load())!;
  }

  Future<int> _defaultWakeMinutes() async {
    final stored = await _db.getSettings();
    return stored.wakeReminderMinutes ?? defaultWakeMinutes;
  }

  /// 只改传入的字段。`noiseId` 显式传 `null` 表示取消选择。
  Future<void> update({
    int? wakeMinutes,
    bool? alarmEnabled,
    Object? noiseId = _unset,
    double? noiseVolume,
  }) async {
    await _db.updateActiveSession(
      db.ActiveSessionsCompanion(
        wakeMinutes: wakeMinutes == null ? const Value.absent() : Value(wakeMinutes),
        alarmEnabled:
            alarmEnabled == null ? const Value.absent() : Value(alarmEnabled),
        noiseId: identical(noiseId, _unset)
            ? const Value.absent()
            : Value(noiseId as String?),
        noiseVolume:
            noiseVolume == null ? const Value.absent() : Value(noiseVolume),
      ),
    );
  }

  /// 结束会话：**一个事务**里写记录 + 删会话行。
  ///
  /// 调用方必须先过 [validateSessionDuration]。这里再挡一道，因为「静默写出
  /// 一条 71 小时的睡眠记录」是这个功能最坏的失败形态。
  Future<void> finish({required DateTime now, required SleepQuality? quality}) async {
    final session = await load();
    if (session == null) {
      throw StateError('没有正在进行的会话，无法结束');
    }

    final endAt = now.toUtc();
    final rejection = validateSessionDuration(endAt.difference(session.startAtUtc));
    if (rejection != SessionFinishRejection.none) {
      throw StateError('会话时长不合法：$rejection');
    }

    final id = endAt.microsecondsSinceEpoch.toString();
    final stamp = DateTime.now().toUtc();

    await _db.transaction(() async {
      await _db.saveRecord(
        db.SleepRecordsCompanion.insert(
          id: Value(id),
          startAtUtc: session.startAtUtc,
          endAtUtc: endAt,
          timeZoneId: Value(session.timeZoneId),
          quality: Value(quality?.value),
          source: const Value('session'),
          createdAt: stamp,
          updatedAt: stamp,
        ),
      );
      await _db.deleteActiveSession();
    });
  }

  /// 丢弃这次会话。不写任何记录——「忘了结束、放了三天」的会话走这里。
  Future<void> discard() => _db.deleteActiveSession();

  SleepSession _toSession(db.ActiveSession row) => SleepSession(
        startAtUtc: row.startAtUtc,
        timeZoneId: row.timeZoneId,
        wakeMinutes: row.wakeMinutes,
        alarmEnabled: row.alarmEnabled,
        noiseId: row.noiseId,
        noiseVolume: row.noiseVolume,
        createdAtUtc: row.createdAt,
      );

  static const _unset = Object();
}

final sessionRepositoryProvider = Provider<SessionRepository>((ref) {
  return SessionRepository(ref.watch(db.databaseProvider));
});

/// 当前会话，没有则为 `null`。UI 读它来决定首页显示「开始睡眠」还是「正在睡眠」。
final activeSessionProvider = FutureProvider<SleepSession?>((ref) async {
  // 会话表一变就重读，与 `sleepEntriesProvider` 同一手法。
  ref.watch(db.activeSessionWatchProvider);
  return ref.watch(sessionRepositoryProvider).load();
});
```

这一步还需要在 `app_database.dart` 里补两个查询（`updateActiveSession`）与一个 provider：

```dart
  /// 只写传入的列。会话页每次调一个开关都走它，不必读-改-写整行。
  Future<void> updateActiveSession(ActiveSessionsCompanion values) async {
    await (update(activeSessions)..where((table) => table.id.equals('active')))
        .write(values);
  }
```

```dart
final activeSessionWatchProvider = StreamProvider<ActiveSession?>((ref) {
  return ref.watch(databaseProvider).watchActiveSession();
});
```

- [ ] **Step 8: 跑测试确认通过**

Run: `flutter test test/session_repository_test.dart test/sleep_session_test.dart`
Expected: 全 PASS。

> 若 `2026-08-30 15:14 UTC` 在测试机时区下不是本地 `23:14`，把测试里那两行 `start` /
> `end` 换成用 `DateTime(2026, 8, 30, 23, 14)` 构造的本地时刻再 `.toUtc()`，
> 并相应调整「按醒来日归档」那条。**断言的是本地日历日，不是硬编的 UTC 偏移。**

- [ ] **Step 9: 提交**

```bash
dart format . && flutter analyze
git add lib/features/sleep/domain/sleep_session.dart \
        lib/features/sleep/data/session_repository.dart \
        lib/core/database/app_database.dart lib/core/database/app_database.g.dart \
        test/sleep_session_test.dart test/session_repository_test.dart
git commit -m "feat(session): 睡眠会话的领域模型与仓库

SleepSession 的计划时长/进度是纯推导：两个时刻都来自用户按下的按钮，
圆环画的是「已过时长 ÷ 计划时长」，不测量任何东西。起床时刻用
DateTime(y,m,d,h,min) 构造而非加时长，跨夏令时仍在同一钟点上。

仓库把「结束」做成一个事务：写记录 + 删会话行，任一失败都不会留下
半写状态。时长守门 0 < d ≤ 24h，越界抛错而不是静默造一条 71 小时的记录。

会话只活一行（主键固定 'active'），所以不需要判重逻辑。"
```

---

## Task 4: 起床闹钟

**Files:**
- Modify: `lib/core/platform/reminders.dart`
- Modify: `lib/app/reminder_sync.dart`
- Modify: `lib/main.dart`（若 `reconcileReminders` 的调用签名变化；本任务保持不变，不改）
- Test: `test/reminder_scheduler_test.dart`, `test/reminder_sync_test.dart`

**Interfaces:**
- Consumes: `ActiveSession`、`SessionRepository.sessionId`（Task 3）
- Produces:
  - `ReminderScheduler.wakeAlarmId = 9003`
  - `ReminderScheduler.wakeAlarmTitle` / `wakeAlarmBody`
  - `ReminderScheduler.syncAlarm(ReminderRequest?)` → `Future<void>`
  - `@protected Future<void> scheduleOnce(ReminderRequest)`（子类实现）
  - `reconcileReminders(AppDatabase, ReminderScheduler)`（签名不变，行为扩展）

- [ ] **Step 1: 写失败的调度器测试**

该文件里既有的假调度器是 `_RecordingScheduler`，它把每次调用记成一个字符串进
`calls` 列表（形如 `'cancel:9001'` / `'schedule:9002@420'`）。先给它补上
`scheduleOnce` 的记录：

```dart
  @override
  Future<void> scheduleOnce(ReminderRequest request) async =>
      calls.add('scheduleOnce:${request.id}@${request.minutesOfDay}');
```

再追加用例组：

```dart
  group('起床闹钟', () {
    test('syncAlarm 传 null 时只取消，不排', () async {
      final scheduler = _RecordingScheduler();
      await scheduler.syncAlarm(null);

      expect(scheduler.calls, ['cancel:9003']);
    });

    test('syncAlarm 排出 9003，且走的是一次性通道', () async {
      final scheduler = _RecordingScheduler();
      await scheduler.syncAlarm(
        const ReminderRequest(
          id: ReminderScheduler.wakeAlarmId,
          minutesOfDay: 7 * 60,
          title: ReminderScheduler.wakeAlarmTitle,
          body: ReminderScheduler.wakeAlarmBody,
        ),
      );

      // **必须是 `scheduleOnce` 而不是 `schedule`**：后者写死了
      // `matchDateTimeComponents.time`，那是每天重复。
      expect(scheduler.calls, ['cancel:9003', 'scheduleOnce:9003@420']);
    });

    /// 这一条是整个闹钟设计里最关键的反向护栏。
    test('日常提醒的 sync 不会碰 9003', () async {
      final scheduler = _RecordingScheduler();
      await scheduler.sync(const ReminderPlan(bedtimeMinutes: 22 * 60 + 30));

      expect(
        scheduler.calls.where((call) => call.contains('9003')),
        isEmpty,
        reason: 'sync 若取消 9003，每次启动的全量重排都会把会话闹钟抹掉',
      );
    });
  });
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/reminder_scheduler_test.dart`
Expected: 编译失败——`syncAlarm` / `wakeAlarmId` / `scheduleOnce` 还不存在。

- [ ] **Step 3: 实现调度器**

`lib/core/platform/reminders.dart`，在 `ReminderScheduler` 里加常量：

```dart
  static const bedtimeId = 9001;
  static const wakeId = 9002;

  /// 睡眠会话的起床闹钟。**与上面两个分开**，因为它是一次性的，不是每天重复。
  static const wakeAlarmId = 9003;

  static const wakeAlarmTitle = '该起床了';
  static const wakeAlarmBody = '结束睡眠，记录一下昨晚睡得怎么样。';
```

加抽象方法（与既有的 `cancel` / `schedule` 一样是 `@protected`）：

```dart
  /// 在**下一个** [request] 的墙上时刻响一次，**不重复**。
  ///
  /// 与 [schedule] 的区别只在这一点上，但这一点是本质的：`schedule` 写死了
  /// `matchDateTimeComponents: DateTimeComponents.time`，那是每天都响。
  @protected
  Future<void> scheduleOnce(ReminderRequest request);
```

加公开方法：

```dart
  /// 让闹钟与「今晚有没有会话、闹钟开着没」保持一致。幂等。
  ///
  /// 与 [sync] 一样是「先取消再排」：调度与偏好不能各自拥有独立生命周期。
  /// 但**两者互不干涉**——[sync] 只动 9001/9002，本方法只动 9003。
  Future<void> syncAlarm(ReminderRequest? request) async {
    await cancel(wakeAlarmId);
    if (request != null) {
      await scheduleOnce(request);
    }
  }
```

`NoopReminderScheduler` 里补：

```dart
  @override
  Future<void> scheduleOnce(ReminderRequest request) async {}
```

`LocalReminderScheduler` 里补：

```dart
  @override
  Future<void> scheduleOnce(ReminderRequest request) async {
    if (!_ready) return;

    await _plugin.zonedSchedule(
      id: request.id,
      title: request.title,
      body: request.body,
      // **不传 `matchDateTimeComponents`。** 传了就是每天重复，而这个闹钟
      // 只该响一次。排定时刻复用 `nextOccurrence`——那个纯函数已经带着
      // 跨午夜的严格比较与跨夏令时的墙上时刻规则，且有自己的测试。
      scheduledDate: nextOccurrence(request, now: tz.TZDateTime.now(tz.local)),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          // 起床闹钟要能穿透专注模式。`interrupt` 级别是**刻意的上限**：
          // `critical` 需要 Apple 单独批准一项 entitlement，本项目没有。
          // 界面上如实写着「强度不如系统闹钟」。
          interruptionLevel: InterruptionLevel.timeSensitive,
          presentAlert: true,
          presentBanner: true,
          presentList: true,
          presentSound: true,
        ),
        macOS: DarwinNotificationDetails(
          interruptionLevel: InterruptionLevel.timeSensitive,
          presentAlert: true,
          presentBanner: true,
          presentList: true,
          presentSound: true,
        ),
      ),
      // 与日常提醒同一取舍：不申请精确闹钟权限。
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/reminder_scheduler_test.dart`
Expected: 全 PASS。

- [ ] **Step 5: 写失败的 reconcile 测试**

该文件里既有的假调度器是 `_FakeScheduler`，它**覆写了 `sync(plan)`**、只把计划记进
`lastSynced`。给它补上闹钟侧的可观测点：

```dart
  /// 会话闹钟最近一次被设成什么（`null` = 被排掉了）。
  ReminderRequest? lastAlarm;

  /// 日常起床提醒被显式让位过几次。
  final yieldedWake = <int>[];

  @override
  Future<void> scheduleOnce(ReminderRequest request) async => lastAlarm = request;

  @override
  Future<void> syncAlarm(ReminderRequest? request) async => lastAlarm = request;

  @override
  Future<void> yieldWakeReminder() async =>
      yieldedWake.add(ReminderScheduler.wakeId);
```

再追加用例组：

```dart
  group('会话闹钟', () {
    Future<void> seedActiveSession({bool alarmEnabled = false}) {
      return database.saveActiveSession(
        ActiveSessionsCompanion.insert(
          id: const Value('active'),
          startAtUtc: DateTime.utc(2026, 8, 30, 15, 14),
          wakeMinutes: const Value(420),
          alarmEnabled: Value(alarmEnabled),
          createdAt: DateTime.utc(2026, 8, 30, 15, 14),
        ),
      );
    }

    test('有会话且闹钟开着：排出 9003，并让日常起床提醒让位', () async {
      await seedActiveSession(alarmEnabled: true);
      await seedBothOn();

      final scheduler = _FakeScheduler(ReminderPermission.granted);
      await reconcileReminders(database, scheduler);

      expect(scheduler.lastAlarm, isNotNull);
      expect(scheduler.lastAlarm!.id, ReminderScheduler.wakeAlarmId);
      expect(scheduler.lastAlarm!.minutesOfDay, 420);
      expect(
        scheduler.yieldedWake,
        contains(ReminderScheduler.wakeId),
        reason: '两者很容易被设成同一个钟点，会响两条',
      );
    });

    test('没有会话：闹钟被排掉，日常提醒照常', () async {
      await seedBothOn();

      final scheduler = _FakeScheduler(ReminderPermission.granted);
      await reconcileReminders(database, scheduler);

      expect(scheduler.lastAlarm, isNull);
      expect(scheduler.yieldedWake, isEmpty);
      expect(scheduler.lastSynced!.wakeMinutes, 7 * 60);
    });

    test('有会话但闹钟关着：闹钟排掉，9002 不让位', () async {
      await seedActiveSession();
      await seedBothOn();

      final scheduler = _FakeScheduler(ReminderPermission.granted);
      await reconcileReminders(database, scheduler);

      expect(scheduler.lastAlarm, isNull);
      expect(scheduler.yieldedWake, isEmpty);
      expect(scheduler.lastSynced!.wakeMinutes, 7 * 60);
    });
  });
```

> 注意 `_FakeScheduler.sync` 只记录、不真的取消，所以「9002 让位」是通过
> `yieldedWake` 这个**显式调用**来断言的，而不是去数 `cancel` 的调用。
> 这也正是把让位做成具名方法 `yieldWakeReminder()` 的收益：它是可断言的行为，
> 而不是一条从 `cancel(wakeId)` 里猜出来的副作用。

- [ ] **Step 6: 跑测试确认失败**

Run: `flutter test test/reminder_sync_test.dart`
Expected: 「有会话且闹钟开着」那条 FAIL——9003 还没被排。

- [ ] **Step 7: 扩展 reconcile**

先在 `lib/core/platform/reminders.dart` 的 `ReminderScheduler` 上加一个公开方法，
把「起床提醒让位」做成语义明确的一步：

```dart
  /// 会话闹钟要占用起床这个钟点时，把**日常起床提醒**让出去。
  ///
  /// 做成独立方法而不是让调用方直接 `cancel(wakeId)`：`cancel` 是 `@protected`
  /// 的调度原语，让外部按 id 去取消，等于把「哪些 id 属于谁」的知识漏到调度器
  /// 之外；而且那样一行 `cancel` 是个**猜不出意图的副作用**，测试只能去数调用。
  Future<void> yieldWakeReminder() => cancel(wakeId);
```

然后在 `lib/app/reminder_sync.dart` 里加一个公开函数——**启动路径与设置路径共用它**，
两处各写一遍就会只在其中一条路径上出问题：

```dart
/// 让**会话闹钟**与「今晚有没有会话、闹钟开着没」保持一致。
///
/// 与 [reconcileReminders] 里那套日常提醒**分开推导**，因为两者的生命周期不同：
/// 日常提醒由偏好驱动，会话闹钟由「今晚有没有会话」驱动。
/// 但推导只有这一处。
Future<void> syncSessionAlarm(
  AppDatabase database,
  ReminderScheduler scheduler,
) async {
  final session = await database.activeSession();

  if (session != null && session.alarmEnabled) {
    // **今晚的闹钟胜过日常起床提醒。** 两者很容易被设成同一个钟点，排在一起
    // 用户会在同一分钟收到两条通知。起床提醒说的是「记录一下昨晚」，而这件事
    // 会话已经替你做了。就寝提醒不受影响——「该睡了」与闹钟无关。
    await scheduler.yieldWakeReminder();
    await scheduler.syncAlarm(
      ReminderRequest(
        id: ReminderScheduler.wakeAlarmId,
        // **起床时间就是闹钟时间**，会话页上没有第二个钟点。
        minutesOfDay: session.wakeMinutes,
        title: ReminderScheduler.wakeAlarmTitle,
        body: ReminderScheduler.wakeAlarmBody,
      ),
    );
    return;
  }

  // 没有会话（或闹钟关着）时把闹钟排掉，日常提醒照常。
  await scheduler.syncAlarm(null);
}
```

`reconcileReminders` 的尾部改成：

```dart
    await scheduler.sync(reminderPlanFrom(stored));

    // 会话闹钟**总要**推导一次：没有会话时这一步负责把可能残留的 9003 排掉。
    await syncSessionAlarm(database, scheduler);
```

`reconcileReminders` 原有的注释里写着「`unsupported` 时不动偏好」那个分支会提前
`return`——那个 `return` 之前也要排掉会话闹钟，否则权限被撤销后 9003 会留在系统里：

```dart
    if (permission == ReminderPermission.denied &&
        (wantsBedtime || wantsWake)) {
      await database.updateSettings(
        const AppSettingsCompanion(
          bedtimeReminderEnabled: Value(false),
          wakeReminderEnabled: Value(false),
        ),
      );
      await scheduler.sync(const ReminderPlan());
      // 闹钟与日常提醒的生命周期无关，不跟着上面那条一起跳过。
      await syncSessionAlarm(database, scheduler);
      return;
    }
```

- [ ] **Step 8: 跑测试确认通过**

Run: `flutter test test/reminder_sync_test.dart test/reminder_scheduler_test.dart`
Expected: 全 PASS。

- [ ] **Step 9: 变异验证**

把 `syncSessionAlarm` 尾部那行 `await scheduler.syncAlarm(null);` 删掉，跑测试。
「没有会话」与「闹钟关着」两条必须变红——它们断言闹钟被排掉了。恢复。

再删掉 `reconcileReminders` 尾部对 `syncSessionAlarm` 的调用，跑测试。
「有会话且闹钟开着」那条必须变红。恢复。

最后把 `ReminderScheduler.sync` 的第一行改成 `await cancel(wakeAlarmId);`，
`test/reminder_scheduler_test.dart` 的「sync 不会碰 9003」必须变红。恢复。

- [ ] **Step 10: 提交**

```bash
dart format . && flutter analyze
git add lib/core/platform/reminders.dart lib/app/reminder_sync.dart \
        test/reminder_scheduler_test.dart test/reminder_sync_test.dart
git commit -m "feat(reminder): 会话起床闹钟（一次性，id 9003）

不能复用 schedule()：它写死了 matchDateTimeComponents.time，那是每天重复。
新增 scheduleOnce + syncAlarm，排定时刻复用 nextOccurrence——跨午夜与跨
夏令时的墙上时刻规则因此免费拿到，且那条纯函数本来就有测试。

sync() 只动 9001/9002，**不碰 9003**：否则每次启动的全量重排都会把闹钟抹掉。
反向护栏已加。

会话活跃且闹钟开着时，日常起床提醒 9002 让位（同一个钟点会响两条）；就寝提醒
9001 不受影响。iOS 用 timeSensitive 穿专注模式，刻意不用需要 Apple 特批的
critical；Android 沿用 inexactAllowWhileIdle。界面上如实注明强度不如系统闹钟。"
```

---

## Task 5: 会话页骨架 —— 路由、日晷圆环、收起

**Files:**
- Create: `lib/features/session/presentation/widgets/wake_dial.dart`
- Create: `lib/features/session/presentation/sleep_session_page.dart`
- Modify: `lib/app/app.dart`
- Test: `test/sleep_session_page_test.dart`（新建）

**Interfaces:**
- Consumes: `SleepSession`（Task 3）、`activeSessionProvider`（Task 3）
- Produces:
  - `class WakeDial({required double progress, required String label, String? sublabel, double size})`
  - `class SleepSessionPage extends ConsumerStatefulWidget`，`const SleepSessionPage({super.key, this.now, this.tick})`

- [ ] **Step 1: 写失败的 widget 测试**

新建 `test/sleep_session_page_test.dart`。**注意**：页面在 `now == null` 时会起一个每秒
的 `Timer`，所以测试一律传固定的 `now`（冻住时钟就不起定时器），结尾不需要额外清理。

```dart
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/core/database/app_database.dart';
import 'package:night_sleep/core/theme/app_theme.dart';
import 'package:night_sleep/features/session/presentation/sleep_session_page.dart';
import 'package:night_sleep/features/sleep/data/session_repository.dart';
import 'package:night_sleep/features/sleep/domain/sleep_session.dart';

void main() {
  late AppDatabase database;

  setUp(() => database = AppDatabase(NativeDatabase.memory()));
  tearDown(() => database.close());

  /// 冻住时钟渲染会话页。
  ///
  /// `now` 非空时页面**不起定时器**，所以这里不会留下 pending timer——
  /// 这是这个测试接缝存在的全部理由，不要图省事改成「起定时器再 pump 掉」。
  Future<void> pumpSession(
    WidgetTester tester, {
    required SleepSession session,
    required DateTime now,
    bool wide = false,
  }) async {
    tester.view.physicalSize = wide ? const Size(1200, 2000) : const Size(430, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          activeSessionProvider.overrideWith((ref) => session),
          // 真的调度器在测试里没有平台通道，`initialize` 也从没跑过；换成空实现，
          // 免得测试依赖「它恰好会静默降级」这个实现细节。
          reminderSchedulerProvider.overrideWithValue(NoopReminderScheduler()),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: SleepSessionPage(now: now),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  SleepSession sessionAt(DateTime start, {int wakeMinutes = 7 * 60}) =>
      SleepSession(
        startAtUtc: start.toUtc(),
        timeZoneId: 'UTC',
        wakeMinutes: wakeMinutes,
        alarmEnabled: false,
        createdAtUtc: start.toUtc(),
      );

  testWidgets('显示已睡时长与设定的起床时间', (tester) async {
    final start = DateTime(2026, 8, 30, 23, 14);
    await pumpSession(
      tester,
      session: sessionAt(start),
      now: start.add(const Duration(hours: 3, minutes: 42)),
    );

    expect(find.text('正在睡眠'), findsOneWidget);
    expect(find.textContaining('3'), findsWidgets); // 3h 42m
    // 「定了几点起」必须在收合态就看得见。
    expect(find.text('23:14'), findsOneWidget);
    expect(find.text('07:00'), findsOneWidget);
  });

  testWidgets('超过起床时间后给出「已超过」而不是让弧溢出', (tester) async {
    final start = DateTime(2026, 8, 30, 23, 14);
    await pumpSession(
      tester,
      session: sessionAt(start),
      now: start.add(const Duration(hours: 9)),
    );

    expect(find.textContaining('已超过起床时间'), findsOneWidget);
  });

  testWidgets('闹钟关着时胶囊说自然醒后手动结束', (tester) async {
    final start = DateTime(2026, 8, 30, 23, 14);
    await pumpSession(
      tester,
      session: sessionAt(start),
      now: start.add(const Duration(hours: 1)),
    );

    expect(find.textContaining('自然醒后手动结束'), findsOneWidget);
  });

  testWidgets('推入页自己提供 Material 祖先与背景', (tester) async {
    final start = DateTime(2026, 8, 30, 23, 14);
    await pumpSession(
      tester,
      session: sessionAt(start),
      now: start.add(const Duration(hours: 1)),
    );

    final heading = find.text('正在睡眠');
    expect(
      DefaultTextStyle.of(tester.element(heading)).style.decoration,
      isNot(TextDecoration.underline),
      reason: '落到 Flutter 的无 Material 错误样式了（黄色双下划线）',
    );
    expect(find.byType(Material), findsWidgets);
  });

  testWidgets('没有会话时不崩，显示空状态并可返回', (tester) async {
    tester.view.physicalSize = const Size(430, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          activeSessionProvider.overrideWith((ref) => null),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: SleepSessionPage(now: DateTime(2026, 8, 30, 23, 14)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('没有正在进行的睡眠'), findsOneWidget);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/sleep_session_page_test.dart`
Expected: 编译失败——页面与 `WakeDial` 还不存在。

- [ ] **Step 3: 实现日晷圆环**

新建 `lib/features/session/presentation/widgets/wake_dial.dart`：

```dart
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';

/// 会话页的日晷圆环。
///
/// 弧表示「已过时长 ÷ 计划时长」：从空画到满，满圈即到设定的起床时间。
/// 超过之后由调用方传入已画满的进度并换掉中间的读数——圆环本身不认识时间，
/// 它只认识一个 0–1 的数，所以它可以被单独测。
///
/// 与 `MoonArc` 一样按几何尺寸而不是 SVG 绘制；这里只有一条弧，因此单独一个
/// widget 比给 `MoonArc` 加参数更清楚。
class WakeDial extends StatelessWidget {
  const WakeDial({
    super.key,
    required this.progress,
    required this.label,
    this.sublabel,
    this.size = 196,
    this.color,
    this.semanticLabel,
  });

  /// 0–1。调用方负责 clamp——这里再 clamp 一次只是防御。
  final double progress;

  /// 中心的读数，例如 `3h 42m`。
  final String label;

  /// 读数下面那行小字，例如 `已入睡` 或 `已超过起床时间 42m`。
  final String? sublabel;

  final double size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final arcColor = color ?? tokens.accent;
    final stroke = size * 0.072; // 196 上是 14

    return Semantics(
      label: semanticLabel ?? label,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: Size.square(size),
              painter: _DialPainter(
                progress: progress.clamp(0.0, 1.0),
                color: arcColor,
                trackColor: tokens.bgMuted,
                stroke: stroke,
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: size * 0.21,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -size * 0.007,
                    color: tokens.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (sublabel != null) ...[
                  SizedBox(height: size * 0.03),
                  Text(
                    sublabel!,
                    style: TextStyle(
                      fontSize: size * 0.052,
                      color: tokens.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  const _DialPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
    required this.stroke,
  });

  final double progress;
  final Color color;
  final Color trackColor;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - stroke) / 2;
    final rect = Rect.fromCircle(center: centre, radius: radius);

    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = trackColor,
    );

    if (progress <= 0) return;

    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_DialPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.stroke != stroke;
}
```

`FontFeature` 需要 `import 'dart:ui' show FontFeature;` 或直接用
`AppTheme.num` 的风格。**用 `AppTheme.num` 更符合项目约定**：把上面那个 `Text` 的
style 换成

```dart
                  style: AppTheme.num(
                    context,
                    size: size * 0.21,
                    weight: FontWeight.w700,
                    letterSpacing: -size * 0.007,
                  ),
```

并 `import '../../../../core/theme/app_theme.dart';`。

- [ ] **Step 4: 实现会话页骨架**

新建 `lib/features/session/presentation/sleep_session_page.dart`：

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/platform/haptics.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_basics.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/atmosphere.dart';
import '../../../core/widgets/glass_surface.dart';
import '../../sleep/data/session_repository.dart';
import '../../sleep/domain/sleep_session.dart';
import 'widgets/wake_dial.dart';

/// 睡眠会话页。
///
/// **它不测量任何东西**：两个时刻来自用户按下的按钮，起床时间来自用户的设定。
/// 没有阶段、没有鼾声判定、没有「睡眠质量」的推断——那些要么由用户自己补，
/// 要么在夜间录音那一轮才谈得上。
class SleepSessionPage extends ConsumerStatefulWidget {
  const SleepSessionPage({
    super.key,
    this.now,
    this.tick = const Duration(seconds: 1),
  });

  /// 固定「现在」的**测试接缝**。
  ///
  /// 非空时页面不起定时器，只按这一个时刻渲染。widget 测试因此不会留下
  /// pending timer——那正是这条接缝存在的全部理由。
  final DateTime? now;

  /// 实时模式下重绘的间隔。
  final Duration tick;

  @override
  ConsumerState<SleepSessionPage> createState() => _SleepSessionPageState();
}

class _SleepSessionPageState extends ConsumerState<SleepSessionPage> {
  Timer? _timer;
  late DateTime _now = widget.now ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    // 冻住时钟时**不要**起定时器：`Timer.periodic` 在 widget 测试的 FakeAsync
    // 里会一直挂着，拆解时留下 pending timer 让用例失败。
    if (widget.now == null) {
      _timer = Timer.periodic(widget.tick, (_) {
        if (mounted) setState(() => _now = DateTime.now());
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(activeSessionProvider).valueOrNull;

    return Atmosphere(
      child: Scaffold(
        // 透明，让 atmosphere 透出来；这个 Scaffold 只为 Material 祖先与键盘
        // 内边距而存在，不是为了它的颜色。推入的路由继承不到外壳的任何东西。
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: session == null
              ? const _NoSession()
              : _SessionBody(session: session, now: _now),
        ),
      ),
    );
  }
}

class _NoSession extends StatelessWidget {
  const _NoSession();

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: EmptyState(
          icon: AppIcons.moon(size: 30, color: tokens.accent, strokeWidth: 1.6),
          title: '没有正在进行的睡眠',
          body: '回到首页按「开始睡眠」就能开始记录今晚。',
          actionLabel: '回首页',
          onAction: () => context.go('/'),
        ),
      ),
    );
  }
}

class _SessionBody extends StatelessWidget {
  const _SessionBody({required this.session, required this.now});

  final SleepSession session;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final overdue = session.overdueAt(now);

    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.paddingOf(context).top + 8,
        16,
        24,
      ),
      children: [
        Row(
          children: [
            _CollapsePill(onTap: () => _collapse(context)),
            const Spacer(),
            Text(
              '夜深 · 睡眠中',
              style: TextStyle(fontSize: 12, color: tokens.textMuted),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Center(
          child: WakeDial(
            progress: session.progressAt(now),
            label: session.elapsedLabelAt(now),
            sublabel: overdue
                ? '已超过起床时间 ${session.overdueLabelAt(now)}'
                : '已入睡',
            semanticLabel: overdue
                ? '已睡 ${session.elapsedLabelAt(now)}，'
                    '已超过起床时间 ${session.overdueLabelAt(now)}'
                : '已睡 ${session.elapsedLabelAt(now)}',
          ),
        ),
        const SizedBox(height: 22),
        _BedWakeRow(session: session),
        const SizedBox(height: 12),
        _AlarmChip(session: session, now: now),
      ],
    );
  }
}

/// 左上角的「收起」：离开页面但**不结束会话**。
class _CollapsePill extends StatelessWidget {
  const _CollapsePill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        AppHaptics.tap();
        onTap();
      },
      child: Container(
        constraints: const BoxConstraints(minHeight: 36),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: tokens.material,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          border: Border.all(color: tokens.glassBorder),
        ),
        alignment: Alignment.center,
        child: Text(
          '收起',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: tokens.accent,
          ),
        ),
      ),
    );
  }
}

void _collapse(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go('/');
  }
}

/// `入睡 23:14 ─────── 闹钟 07:00`。
///
/// **收合态就必须看得见**：睡前设完的起床时间若藏在抽屉里，等于设完就再也
/// 看不到自己设了什么。
class _BedWakeRow extends StatelessWidget {
  const _BedWakeRow({required this.session});

  final SleepSession session;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final start = session.startAtUtc.toLocal();
    final hour = session.wakeMinutes ~/ 60;
    final minute = session.wakeMinutes % 60;

    return GlassSurface(
      borderRadius: BorderRadius.circular(AppRadii.panel),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          _TimeColumn(label: '入睡', value: _hhmm(start), color: tokens.accent),
          Expanded(
            child: Container(
              height: 1,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              color: tokens.border,
            ),
          ),
          _TimeColumn(
            label: '闹钟',
            value: '${hour.toString().padLeft(2, '0')}:'
                '${minute.toString().padLeft(2, '0')}',
            color: tokens.accentViolet,
            alignEnd: true,
          ),
        ],
      ),
    );
  }

  static String _hhmm(DateTime local) =>
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

class _TimeColumn extends StatelessWidget {
  const _TimeColumn({
    required this.label,
    required this.value,
    required this.color,
    this.alignEnd = false,
  });

  final String label;
  final String value;
  final Color color;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: tokens.textMuted)),
        const SizedBox(height: 2),
        Text(value, style: AppTheme.num(context, size: 15, weight: FontWeight.w700, color: color)),
      ],
    );
  }
}

/// 闹钟状态胶囊。开着报剩余时间，关着说明自然醒后手动结束。
class _AlarmChip extends StatelessWidget {
  const _AlarmChip({required this.session, required this.now});

  final SleepSession session;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final on = session.alarmEnabled;

    final remaining = session.plannedDuration - session.elapsedAt(now);
    final minutes = remaining.inMinutes < 0 ? 0 : remaining.inMinutes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: on ? tokens.accentSoft : tokens.bgMuted,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              AppIcons.timer(
                size: 15,
                color: on ? tokens.accent : tokens.textMuted,
                strokeWidth: 1.8,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  on
                      ? '起床闹钟已开 · 还有 ${minutes ~/ 60}h ${minutes % 60}m'
                      : '闹钟已关 · 自然醒后手动结束',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: on ? tokens.accent : tokens.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (on) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppIcons.volume(size: 13, color: tokens.textMuted, strokeWidth: 1.6),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '由系统通知投递；休眠模式下可能晚几分钟，强度不如系统闹钟。',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.45,
                    color: tokens.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
```

- [ ] **Step 5: 注册路由**

`lib/app/app.dart` 的 `_router` 里加：

```dart
        GoRoute(
          path: 'sleep/session',
          builder: (context, state) => const SleepSessionPage(),
        ),
```

并 `import '../features/session/presentation/sleep_session_page.dart';`。

- [ ] **Step 6: 跑测试**

Run: `flutter test test/sleep_session_page_test.dart`
Expected: 全 PASS。

- [ ] **Step 7: 格式化、分析、提交**

```bash
dart format . && flutter analyze
git add lib/features/session/presentation/widgets/wake_dial.dart \
        lib/features/session/presentation/sleep_session_page.dart \
        lib/app/app.dart test/sleep_session_page_test.dart
git commit -m "feat(session): 会话页骨架 —— 日晷圆环、入睡/闹钟行、收起

圆环画「已过时长 ÷ 计划时长」，超过起床时间后封顶并换掉中心读数，
不溢出也不回绕。WakeDial 不认识时间，只认识一个 0–1 的数，所以能单独测。

「入睡 23:14 ── 闹钟 07:00」放在收合态而不是抽屉里：起床时间是睡前设的，
设完就看不到等于白设。

页面在 now 非空时不起定时器——那是测试接缝，widget 测试因此不会留下
pending timer。页面自带 Atmosphere + Scaffold + Material，推入路由继承不到。"
```

---

## Task 6: 设定抽屉（点击摘要打开）

**Files:**
- Create: `lib/features/session/presentation/widgets/session_drawer.dart`
- Modify: `lib/features/session/presentation/sleep_session_page.dart`
- Test: `test/sleep_session_page_test.dart`

**Interfaces:**
- Consumes: `WakeDial`、`SleepSession`、`sessionRepositoryProvider`、`SettingsPage.defaultWakeMinutes`
- Produces: `class SessionDrawer extends ConsumerStatefulWidget`，`const SessionDrawer({required SleepSession session})`

- [ ] **Step 1: 写失败的 widget 测试**

在 `test/sleep_session_page_test.dart` 追加：

```dart
  testWidgets('点摘要条展开抽屉，四组设定都在', (tester) async {
    final start = DateTime(2026, 8, 30, 23, 14);
    await pumpSession(
      tester,
      session: sessionAt(start),
      now: start.add(const Duration(hours: 1)),
    );

    expect(find.text('今晚的设定'), findsNothing, reason: '收合态不该看到抽屉内容');

    await tester.tap(find.textContaining('白噪音'));
    await tester.pumpAndSettle();

    expect(find.text('今晚的设定'), findsOneWidget);
    expect(find.text('起床闹钟'), findsOneWidget);
    expect(find.text('鼾声/梦话记录'), findsOneWidget);
    expect(find.text('白噪音'), findsOneWidget);
  });

  testWidgets('抽屉里的白噪音定时最长 60 分钟，没有「不限」与 90m', (tester) async {
    final start = DateTime(2026, 8, 30, 23, 14);
    await pumpSession(
      tester,
      session: sessionAt(start),
      now: start.add(const Duration(hours: 1)),
    );
    await tester.tap(find.textContaining('白噪音'));
    await tester.pumpAndSettle();

    expect(find.text('15m'), findsOneWidget);
    expect(find.text('30m'), findsOneWidget);
    expect(find.text('45m'), findsOneWidget);
    expect(find.text('60m'), findsOneWidget);
    expect(find.text('不限'), findsNothing, reason: '会话里的白噪音必须有上限');
    expect(find.text('90m'), findsNothing);
  });

  testWidgets('鼾声/梦话开关带上「尚未接入录音」的说明（plan A）', (tester) async {
    final start = DateTime(2026, 8, 30, 23, 14);
    await pumpSession(
      tester,
      session: sessionAt(start),
      now: start.add(const Duration(hours: 1)),
    );
    await tester.tap(find.textContaining('白噪音'));
    await tester.pumpAndSettle();

    expect(find.textContaining('尚未接入录音'), findsOneWidget);
  });

  /// 这一条与上一条**互斥**：plan B 落地录音时必须把上一条删掉、这一条补上。
  /// 两轮之间不存在一个两边都写的中间状态。
  testWidgets('白噪音区注明后台播放未接入', (tester) async {
    final start = DateTime(2026, 8, 30, 23, 14);
    await pumpSession(
      tester,
      session: sessionAt(start),
      now: start.add(const Duration(hours: 1)),
    );
    await tester.tap(find.textContaining('白噪音'));
    await tester.pumpAndSettle();

    expect(find.textContaining('退到后台或锁屏后声音会停'), findsOneWidget);
  });

  testWidgets('拨动鼾声开关会写回设置', (tester) async {
    final start = DateTime(2026, 8, 30, 23, 14);
    await pumpSession(
      tester,
      session: sessionAt(start),
      now: start.add(const Duration(hours: 1)),
    );
    await tester.tap(find.textContaining('白噪音'));
    await tester.pumpAndSettle();

    // 抽屉里有两个开关，**鼾声/梦话是后一个**（前一个是起床闹钟，它要申请通知
    // 权限，走的是另一条路径）。
    await tester.tap(find.byType(IosToggle).last);
    await tester.pumpAndSettle();

    final stored = await database.getSettings();
    expect(stored.soundRecordingEnabled, isTrue,
        reason: '会话页与设置页必须共用 AppSettings 里同一个字段');
  });
```

（`IosToggle` 的 import 是 `package:night_sleep/core/widgets/ios_controls.dart`。）

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/sleep_session_page_test.dart`
Expected: 「点摘要条展开抽屉」等 FAIL——抽屉还不存在。

- [ ] **Step 3: 实现抽屉**

新建 `lib/features/session/presentation/widgets/session_drawer.dart`。它需要：

1. 一行「起床闹钟」：时刻 + `IosToggle`。点时刻走 `showPickerSheet` +
   `AppTimePicker`，**只有「完成」才提交**（与设置页 `_pickReminderTime` 同一写法，
   理由也一样：滚了轮再点取消不该落库）。
2. 一行「鼾声/梦话记录」+ `IosToggle`，副标题写明「尚未接入录音，开关只保存偏好。」
3. 白噪音：复用 `kNoiseOptions`（`noise_sheet.dart:42` 的公开列表）做八宫格，
   音量条复用 `NoiseSheet` 里的私有 `_VolumeSlider`——**把 `_VolumeSlider` 与
   `_NoiseTile` 从 `noise_sheet.dart` 提出来**成公开的 `NoiseTile` / `VolumeSlider`
   放进新文件 `lib/features/sleep/presentation/widgets/noise_controls.dart`，
   `noise_sheet.dart` 改为引用它们（避免复制一份）。

   要搬的两段在 `lib/features/sleep/presentation/sheets/noise_sheet.dart`：
   `_NoiseTile` 起于 **443 行**、`_VolumeSlider` 起于 **499 行**（连同它上面的
   `const double _thumbSize = 24;`）。搬运时把类名去掉下划线、加 `super.key`，
   其余实现**一字不改**——音量条的拖拽与钳制逻辑是调过的，重写容易丢掉
   「拇指在 0% 与 100% 处不被裁掉」那一条。
4. 定时 chips：`const [15, 30, 45, 60]`，默认 30，**没有 `null`**。
5. 说明行：「退到后台或锁屏后声音会停（后台播放未接入）。」

关键实现（节选，其余照 `noise_sheet.dart` 的现有写法搬）：

```dart
class SessionDrawer extends ConsumerStatefulWidget {
  const SessionDrawer({super.key, required this.session});

  final SleepSession session;

  @override
  ConsumerState<SessionDrawer> createState() => _SessionDrawerState();
}

class _SessionDrawerState extends ConsumerState<SessionDrawer> {
  /// 会话里的白噪音**必须有上限**，所以这里没有 `null`。
  ///
  /// 独立的助眠音效弹层保留「不限」与 90m——它是一个「醒着听」的入口，
  /// 与夜间录音没有交互。同一个功能两个上限，两处界面都要写清。
  static const _timerChoices = <int>[15, 30, 45, 60];

  int _timerMinutes = 30;

  Future<void> _pickWakeTime() async {
    final minutes = widget.session.wakeMinutes;
    var draft = '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
        '${(minutes % 60).toString().padLeft(2, '0')}';

    final confirmed = await showPickerSheet(
      context: context,
      title: '起床闹钟',
      child: AppTimePicker(
        value: draft,
        onChanged: (value) => draft = value,
      ),
    );
    if (confirmed != true) return;

    final parts = draft.split(':');
    final next = int.parse(parts[0]) * 60 + int.parse(parts[1]);
    await ref.read(sessionRepositoryProvider).update(wakeMinutes: next);
    // 闹钟开着时，改了时刻要立刻重排——否则它会按旧时刻响。
    await _resyncAlarm();
  }

  /// 鼾声/梦话是**跨会话的偏好**，写的是 `AppSettings` 里那个唯一字段。
  ///
  /// 会话表里刻意没有同名字段：存两份就会分叉（会话页关掉、设置页还写着开），
  /// 而这个项目明令禁止第二个真相来源。
  Future<void> _toggleRecording(bool value) async {
    await ref.read(databaseProvider).updateSettings(
          AppSettingsCompanion(soundRecordingEnabled: Value(value)),
        );
  }

  Future<void> _toggleAlarm(bool value) async {
    final scheduler = ref.read(reminderSchedulerProvider);

    if (value) {
      final permission = await scheduler.requestPermission();
      if (permission != ReminderPermission.granted) {
        if (!mounted) return;
        ref.read(toastProvider.notifier).show(
              permission == ReminderPermission.unsupported
                  ? '当前设备无法安排本地通知，闹钟未开启。'
                  : '没有获得通知权限，闹钟未开启。可在系统设置中允许「夜深」发送通知。',
            );
        ref.invalidate(reminderPermissionProvider);
        return;
      }
    }

    await ref.read(sessionRepositoryProvider).update(alarmEnabled: value);
    await _resyncAlarm();
  }

  Future<void> _resyncAlarm() async {
    final session = await ref.read(sessionRepositoryProvider).load();
    final scheduler = ref.read(reminderSchedulerProvider);
    await scheduler.syncAlarm(
      session != null && session.alarmEnabled
          ? ReminderRequest(
              id: ReminderScheduler.wakeAlarmId,
              minutesOfDay: session.wakeMinutes,
              title: ReminderScheduler.wakeAlarmTitle,
              body: ReminderScheduler.wakeAlarmBody,
            )
          : null,
    );
  }
}
```

**注意**：让位规则（会话闹钟开着时 `9002` 让位）在两条路径上都要成立——启动时的
`reconcileReminders`，以及本处改设定后的重排。**Task 4 已经把它抽成了公开函数
`syncSessionAlarm(database, scheduler)`**，所以这里不要自己拼一遍逻辑，直接调它：

```dart
  /// 让闹钟与「今晚有没有会话、闹钟开着没、几点响」保持一致。
  ///
  /// 直接复用启动路径的那个函数：各写一遍的话，「闹钟开着却不响」或「同一分钟
  /// 响两条」这类问题只会在其中一条路径上出现。
  Future<void> _resyncAlarm() => syncSessionAlarm(
        ref.read(databaseProvider),
        ref.read(reminderSchedulerProvider),
      );
```

（`import '../../../app/reminder_sync.dart';` 与
`import '../../../core/database/app_database.dart';`。）

把 `session_drawer.dart` 接进会话页：收合态底部那条摘要改成可点，点了
`setState(() => _drawerOpen = true)`，展开态用 `AnimatedSize` 或直接条件渲染
（保持简单：条件渲染 + `AnimatedSwitcher` 的淡入即可，不必做手势）。

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/sleep_session_page_test.dart`
Expected: 全 PASS。

- [ ] **Step 5: 跑全套确认没碰坏既有测试**

Run: `flutter test`
Expected: 全 PASS。`test/noise_sheet_test.dart` 会因为 `_VolumeSlider` / `_NoiseTile`
被提出来而需要改 import 或 finder——按实际编译错误逐个修，**不要**为了省事复制一份
私有副本。

- [ ] **Step 6: 变异验证两条诚实标注**

删掉「尚未接入录音，开关只保存偏好。」这一行，跑测试 → 对应用例必须变红。恢复。
删掉「退到后台或锁屏后声音会停（后台播放未接入）。」→ 对应用例必须变红。恢复。

- [ ] **Step 7: 提交**

```bash
dart format . && flutter analyze && flutter test
git add lib/features/session/presentation/widgets/session_drawer.dart \
        lib/features/session/presentation/sleep_session_page.dart \
        lib/features/sleep/presentation/widgets/noise_controls.dart \
        lib/features/sleep/presentation/sheets/noise_sheet.dart \
        lib/app/reminder_sync.dart test/sleep_session_page_test.dart
git commit -m "feat(session): 设定抽屉（起床闹钟 / 鼾声开关 / 白噪音）

点摘要条打开，不做纯上拉手势——躺着拖拽不好使。

起床时间与闹钟开关合成一行：起床时间就是闹钟时间，一个值；开关只决定到点
响不响。圆环的目标因此恒有值，不需要「没有目标」的降级分支。

会话里的白噪音定时最长 60 分钟（15/30/45/60，默认 30，列表里没有「不限」），
独立的助眠音效弹层不受此限。

鼾声/梦话开关直接读写 AppSettings.soundRecordingEnabled——会话表里刻意没有
同名字段，存两份就会分叉。plan A 阶段它仍只保存偏好，界面如实标注。

noise_sheet 的音量条与音效格子提成公开组件供两处共用，没有复制副本。
会话闹钟的重排与启动路径共用 syncSessionAlarm，避免两条路径各写一遍。"
```

---

## Task 7: 结束流程 —— 评星、守门、落库、跳转

**Files:**
- Create: `lib/features/sleep/presentation/widgets/quality_rating.dart`
- Create: `lib/features/session/presentation/sheets/quality_rating_sheet.dart`
- Modify: `lib/features/session/presentation/sleep_session_page.dart`
- Modify: `lib/features/log/presentation/log_page.dart`（改用共享的星级组件）
- Test: `test/sleep_session_page_test.dart`, `test/pages_widget_test.dart`

**Interfaces:**
- Consumes: `SessionRepository.finish` / `discard`、`validateSessionDuration`、`qualityColor`
- Produces:
  - `class QualityStars({required SleepQuality? value, required ValueChanged<SleepQuality> onChanged, double size})`
  - `Future<SleepQuality?> showQualityRatingSheet(BuildContext)` —— 返回选中的质量，跳过或关闭返回 `null`

- [ ] **Step 1: 写失败的测试**

在 `test/sleep_session_page_test.dart` 追加：

```dart
  testWidgets('结束睡眠先问一次星级', (tester) async {
    final start = DateTime(2026, 8, 30, 23, 14);
    await pumpSession(
      tester,
      session: sessionAt(start),
      now: start.add(const Duration(hours: 7, minutes: 48)),
    );

    await tester.tap(find.text('结束睡眠'));
    await tester.pumpAndSettle();

    expect(find.text('昨晚睡得怎么样？'), findsOneWidget);
    expect(find.text('跳过'), findsOneWidget);
  });

  testWidgets('跳过评星：记录落库但质量为 null 且没有评分', (tester) async {
    final start = DateTime(2026, 8, 30, 23, 14);
    await pumpSession(
      tester,
      session: sessionAt(start),
      now: start.add(const Duration(hours: 7, minutes: 48)),
    );

    await tester.tap(find.text('结束睡眠'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('跳过'));
    await tester.pumpAndSettle();

    final row = (await database.allRecords()).single;
    expect(row.quality, isNull);
    expect(row.source, 'session');
    expect(await database.activeSession(), isNull);
  });

  testWidgets('评了分：质量写进记录', (tester) async {
    final start = DateTime(2026, 8, 30, 23, 14);
    await pumpSession(
      tester,
      session: sessionAt(start),
      now: start.add(const Duration(hours: 7, minutes: 48)),
    );

    await tester.tap(find.text('结束睡眠'));
    await tester.pumpAndSettle();
    // 点第 5 颗星。
    await tester.tap(find.byType(QualityStars).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect((await database.allRecords()).single.quality, isNotNull);
  });

  /// 时长守门：点了开始就立刻结束，**不许**静默写出一条零时长记录。
  testWidgets('时长过短不落库，给出说明与两个出口', (tester) async {
    final start = DateTime(2026, 8, 30, 23, 14);
    await pumpSession(
      tester,
      session: sessionAt(start),
      now: start,
    );

    await tester.tap(find.text('结束睡眠'));
    await tester.pumpAndSettle();

    expect(find.textContaining('太短'), findsOneWidget);
    expect(find.text('手动补录某一晚'), findsOneWidget);
    expect(find.text('丢弃这次会话'), findsOneWidget);
    expect(await database.allRecords(), isEmpty);
    expect(await database.activeSession(), isNotNull, reason: '会话仍在，等用户决定');
  });

  testWidgets('时长超过 24 小时同样不落库', (tester) async {
    final start = DateTime(2026, 8, 30, 23, 14);
    await pumpSession(
      tester,
      session: sessionAt(start),
      now: start.add(const Duration(hours: 30)),
    );

    await tester.tap(find.text('结束睡眠'));
    await tester.pumpAndSettle();

    expect(find.textContaining('超过 24 小时'), findsOneWidget);
    expect(await database.allRecords(), isEmpty);
  });

  testWidgets('丢弃这次会话：不写记录，会话消失', (tester) async {
    final start = DateTime(2026, 8, 30, 23, 14);
    await pumpSession(
      tester,
      session: sessionAt(start),
      now: start,
    );

    await tester.tap(find.text('结束睡眠'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('丢弃这次会话'));
    await tester.pumpAndSettle();

    expect(await database.allRecords(), isEmpty);
    expect(await database.activeSession(), isNull);
  });
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/sleep_session_page_test.dart`
Expected: 全部编译失败或 FAIL——结束流程还不存在。

- [ ] **Step 3: 抽出共享的星级组件**

新建 `lib/features/sleep/presentation/widgets/quality_rating.dart`，把
`log_page.dart` 里的私有 `_QualityStar` 搬过来改名 `QualityStars`：

```dart
import 'package:flutter/material.dart';

import '../../../../core/platform/haptics.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../domain/sleep_quality.dart';
import 'stage_style.dart';

/// 1–5 星的主观质量评分行。
///
/// 表单、回顾页与结束评星弹层三处共用。`value` 为空表示**还没评过**——
/// 此时一颗星都不选中，这是这个组件唯一需要小心的状态：默认选中某一档等于
/// 应用替用户打了分。
class QualityStars extends StatelessWidget {
  const QualityStars({
    super.key,
    required this.value,
    required this.onChanged,
    this.size = 44,
  });

  final SleepQuality? value;
  final ValueChanged<SleepQuality> onChanged;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final quality in SleepQuality.values) ...[
          _Star(
            quality: quality,
            selected: value == quality,
            filledTo: value?.value ?? 0,
            size: size,
            onTap: () {
              AppHaptics.select();
              onChanged(quality);
            },
          ),
          if (quality != SleepQuality.values.last) const SizedBox(width: 10),
        ],
      ],
    );
  }
}
```

`_Star` 的内部实现照搬 `log_page.dart` 的 `_QualityStar`，把
`_qualityColor(tokens, quality)` 换成 `qualityColor(tokens, quality)`，
并把 `Semantics(label: '睡眠质量 ${quality.label}')` 保留。

`log_page.dart` 里删掉 `_QualityStar` 与 `_qualityColor`，改用 `QualityStars`：

```dart
            QualityStars(
              value: _quality,
              onChanged: (quality) => setState(() => _quality = quality),
            ),
```

- [ ] **Step 4: 实现评星弹层**

新建 `lib/features/session/presentation/sheets/quality_rating_sheet.dart`：

```dart
import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/app_sheet.dart';
import '../../../sleep/domain/sleep_quality.dart';
import '../../../sleep/presentation/widgets/quality_rating.dart';

/// 结束睡眠时就地问一次「昨晚睡得怎么样？」。
///
/// 返回用户选中的质量，**跳过或关掉蒙层都返回 `null`**——两者对调用方是同一件事：
/// 这次没有评分。绝不替用户填一个中间值。
///
/// 为什么问在结束这一步：刚醒那一刻主观感受最清楚，隔几小时再回来看就只剩一个
/// 模糊印象了。
Future<SleepQuality?> showQualityRatingSheet(BuildContext context) {
  return showAppSheet<SleepQuality>(
    context: context,
    builder: (context) => const _QualityRatingSheet(),
  );
}

class _QualityRatingSheet extends StatefulWidget {
  const _QualityRatingSheet();

  @override
  State<_QualityRatingSheet> createState() => _QualityRatingSheetState();
}

class _QualityRatingSheetState extends State<_QualityRatingSheet> {
  /// 初始无选中——用户没点过的档位不该是亮的。
  SleepQuality? _choice;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    return AppSheet(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Column(
              children: [
                Text(
                  '昨晚睡得怎么样？',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: tokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '现在评一下最准。不想评就跳过，之后在「回顾」里还能补。',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: tokens.textMuted),
                ),
                const SizedBox(height: 20),
                QualityStars(
                  value: _choice,
                  onChanged: (quality) => setState(() => _choice = quality),
                ),
                const SizedBox(height: 22),
                PrimaryAction(
                  label: '保存',
                  onTap: () => Navigator.of(context).pop(_choice),
                ),
                const SizedBox(height: 10),
                Pressable(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      '跳过',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: tokens.textMuted,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }
}
```

`PrimaryAction` / `Pressable` 需要 `import '../../../../core/widgets/app_basics.dart';`。

- [ ] **Step 5: 实现结束流程**

在 `sleep_session_page.dart` 里给 `_SessionBody` 加 `onFinish` 回调，并在
`_SleepSessionPageState` 实现。

**先补这些 import**（Task 5 那份 import 列表里还没有）：
`import '../../../app/app_shell.dart';`（`AppTab` / `activeTabProvider`）、
`import '../../../app/app_toast.dart';`（`toastProvider`）、
`import '../../../app/reminder_sync.dart';`（`syncSessionAlarm`）、
`import '../../../core/database/app_database.dart';`（`databaseProvider`）、
`import '../../../core/platform/reminders.dart';`、
`import '../../../core/widgets/app_sheet.dart';`、
`import '../sheets/quality_rating_sheet.dart';`

（`_RejectedSheet` 与 `_EndButton` 都写在本文件里，不需要新 import。）

```dart
  Future<void> _finish(SleepSession session) async {
    final now = widget.now ?? DateTime.now();
    final rejection = validateSessionDuration(now.toUtc().difference(session.startAtUtc));

    if (rejection != SessionFinishRejection.none) {
      if (!mounted) return;
      await showAppSheet<void>(
        context: context,
        builder: (context) => _RejectedSheet(
          rejection: rejection,
          onDiscard: () async {
            await ref.read(sessionRepositoryProvider).discard();
            if (!mounted) return;
            Navigator.of(context).pop();
            context.go('/');
          },
        ),
      );
      return;
    }

    final quality = await showQualityRatingSheet(context);
    if (!mounted) return;

    try {
      await ref.read(sessionRepositoryProvider).finish(now: now, quality: quality);
    } catch (error) {
      if (!mounted) return;
      ref.read(toastProvider.notifier).show('保存失败：$error');
      return;
    }

    // 会话行没了，闹钟也该跟着取消。
    await syncSessionAlarm(
      ref.read(databaseProvider),
      ref.read(reminderSchedulerProvider),
    );

    if (!mounted) return;
    unawaited(AppHaptics.success());
    ref.read(toastProvider.notifier).show('睡眠记录已保存，补充一下今晚的感受吧。');
    ref.read(activeTabProvider.notifier).state = AppTab.log;
    context.go('/');
  }
```

`_RejectedSheet` 是本文件里的私有组件，如实说明两种越界并给两个出口：

```dart
/// 时长越界时的说明层。
///
/// 只有两种操作会产生它：点了开始就立刻点结束，或者点了开始忘了结束、放了好几天。
/// 两种都不该静默变成一条睡眠记录，所以这里**不落库**，让用户自己选。
class _RejectedSheet extends StatelessWidget {
  const _RejectedSheet({required this.rejection, required this.onDiscard});

  final SessionFinishRejection rejection;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final tooShort = rejection == SessionFinishRejection.tooShort;

    return AppSheet(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tooShort ? '这次会话太短' : '这次会话超过 24 小时',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: tokens.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              tooShort
                  ? '还没有睡够一分钟，先不记录。如果你是刚点错了，丢弃它就好。'
                  : '看起来是忘了结束睡眠。这么长的记录多半不是真的，'
                      '与其写一条不可信的时长，不如你自己补上准确的那一晚。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, height: 1.5, color: tokens.textMuted),
            ),
            const SizedBox(height: 20),
            PrimaryAction(
              label: '手动补录某一晚',
              onTap: () {
                Navigator.of(context).pop();
                context.push('/log/new');
              },
            ),
            const SizedBox(height: 10),
            Pressable(
              onTap: onDiscard,
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  '丢弃这次会话',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: tokens.danger,
                  ),
                ),
              ),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
          ],
        ),
      ),
    );
  }
}
```

会话页底部加「结束睡眠」按钮（`GlassSurface` + `danger` 描边，与详情页的
「删除记录」同一观感）：

```dart
        const SizedBox(height: 22),
        _EndButton(onTap: () => onFinish(session)),
```

- [ ] **Step 6: 跑测试确认通过**

Run: `flutter test test/sleep_session_page_test.dart test/pages_widget_test.dart`
Expected: 全 PASS。

- [ ] **Step 7: 变异验证**

把 `_finish` 里的守门判断删掉（直接走评星），「时长过短不落库」必须变红。恢复。
把跳过分支改成 `quality: SleepQuality.fair`，「跳过评星」那条必须变红。恢复。

- [ ] **Step 8: 提交**

```bash
dart format . && flutter analyze && flutter test
git add lib/features/sleep/presentation/widgets/quality_rating.dart \
        lib/features/session/presentation/sheets/quality_rating_sheet.dart \
        lib/features/session/presentation/sleep_session_page.dart \
        lib/features/log/presentation/log_page.dart \
        test/sleep_session_page_test.dart test/pages_widget_test.dart
git commit -m "feat(session): 结束流程 —— 就地评星、时长守门、事务落库

点结束先问一次星级：刚醒那一刻最准。跳过就是**留空**，绝不填中间值——
填了会凭空带进评分里 17.5 分的质量分。

时长不在 (0, 24h] 内不落库，转成说明 + 「手动补录」/「丢弃这次会话」。
只有两种操作会产生它：点了开始就点结束，或忘了结束放了好几天。两种都不该
静默变成一条睡眠记录。

星级行提成共享组件，表单/回顾页/评星弹层三处共用；value 为空时一颗星都不
选中，这是它唯一需要小心的状态。"
```

---

## Task 8: 首页入口 —— 开始睡眠 / 正在睡眠

**Files:**
- Modify: `lib/features/home/presentation/home_page.dart`
- Modify: `lib/app/app.dart`
- Test: `test/pages_widget_test.dart`

**Interfaces:**
- Consumes: `activeSessionProvider`、`sessionRepositoryProvider`、`SleepSession`
- Produces: 无新公开 API

- [ ] **Step 1: 写失败的测试**

在 `test/pages_widget_test.dart` 的「首页」组里追加（`pumpPage` 需要支持覆盖
`activeSessionProvider`——给它的 `pumpWithOverrides` 加一个
`SleepSession? activeSession` 具名参数，默认 `null`）：

```dart
    testWidgets('没有会话时主按钮是「开始睡眠」', (tester) async {
      await pumpPage(tester, home(), activeSession: null);

      expect(find.text('开始睡眠'), findsOneWidget);
      expect(find.text('记录昨夜睡眠'), findsNothing);
    });

    testWidgets('空状态的行动按钮也是「开始睡眠」', (tester) async {
      await pumpPage(tester, home(), activeSession: null);

      expect(find.text('记录第一晚'), findsNothing);
      expect(find.text('开始睡眠'), findsWidgets);
    });

    testWidgets('有会话时显示「正在睡眠」卡并可回到会话页', (tester) async {
      final start = DateTime(2026, 8, 30, 23, 14);
      await pumpPage(
        tester,
        home(),
        activeSession: SleepSession(
          startAtUtc: start.toUtc(),
          timeZoneId: 'UTC',
          wakeMinutes: 7 * 60,
          alarmEnabled: false,
          createdAtUtc: start.toUtc(),
        ),
        clock: start.add(const Duration(hours: 3, minutes: 42)),
      );

      expect(find.textContaining('正在睡眠'), findsOneWidget);
      expect(find.textContaining('已睡'), findsOneWidget);
      expect(find.text('开始睡眠'), findsNothing, reason: '会话在跑时不该再给开始按钮');
    });

    testWidgets('点「开始睡眠」会写入会话行', (tester) async {
      await pumpPage(tester, home(), activeSession: null);

      await tester.tap(find.text('开始睡眠'));
      await tester.pumpAndSettle();

      expect(await database.activeSession(), isNotNull);
    });
```

`pumpWithOverrides` 里加：

```dart
          activeSessionProvider.overrideWith((ref) => activeSession),
```

并按需覆盖 `sessionRepositoryProvider`（它有默认实现，指向被 override 的
`databaseProvider`，所以**不需要**额外覆盖）。

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/pages_widget_test.dart`
Expected: 「主按钮是开始睡眠」等 FAIL——首页还是「记录昨夜睡眠」。

- [ ] **Step 3: 改首页**

`home_page.dart` 的 `HomePage` 多一个 `onStartSleep` 回调（与既有的
`onRecordNow` 并存或替换），由 `_TabContent` 传入。改动要点：

1. `build` 里 `ref.watch(activeSessionProvider)`。
2. 有会话时，主按钮位置换成「正在睡眠」卡：

```dart
        if (session != null)
          _ActiveSessionCard(session: session, now: DateTime.now())
        else
          PrimaryAction(
            label: '开始睡眠',
            subtitle: '定好闹钟与白噪音，记录今晚',
            trailing: AppIcons.moon(size: 20, color: Colors.white, strokeWidth: 2),
            onTap: onStartSleep,
          ),
```

3. 空状态的 `actionLabel` 与 `onAction` 改成「开始睡眠」/ `onStartSleep`。
4. 删掉原来的「记录昨夜睡眠」`PrimaryAction`——那条路径由回顾 Tab 承担。
5. `_ActiveSessionCard` 显示圆环进度与「已睡 3h 42m」，`onTap` 走
   `context.push('/sleep/session')`。

「开始睡眠」的动作在 `_TabContent`（`app.dart`）里：

```dart
  Future<void> _startSleep(BuildContext context, WidgetRef ref) async {
    await ref.read(sessionRepositoryProvider).start();
    if (!context.mounted) return;
    context.push('/sleep/session');
  }
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/pages_widget_test.dart`
Expected: 全 PASS。

- [ ] **Step 5: 提交**

```bash
dart format . && flutter analyze && flutter test
git add lib/features/home/presentation/home_page.dart lib/app/app.dart \
        test/pages_widget_test.dart
git commit -m "feat(home): 「开始睡眠」入口与「正在睡眠」卡

空状态的行动按钮一并改掉。首页不再有「记录昨夜睡眠」——那条路径由回顾 Tab
承担。会话在跑时不再显示开始按钮，改为显示已睡时长并可点回会话页。"
```

---

## Task 9: 回顾 Tab

**Files:**
- Create: `lib/features/log/presentation/review_page.dart`
- Create: `lib/features/log/presentation/review_night_picker.dart`
- Modify: `lib/app/app_shell.dart`（`AppTab.log` 的 label）
- Modify: `lib/app/app.dart`（Tab 分派）
- Test: `test/review_page_test.dart`（新建）

**Interfaces:**
- Consumes: `sleepEntriesProvider`、`sleepRepositoryProvider`、`QualityStars`、`LoggedEvents`
- Produces: `class ReviewPage extends ConsumerStatefulWidget`

- [ ] **Step 1: 写失败的测试**

新建 `test/review_page_test.dart`：

```dart
// 沿用 pages_widget_test.dart 的 pumpPage 写法（Scaffold(body:) + provider 覆盖，
// **不订阅 drift 流**）。

  testWidgets('默认补充最近一条真实记录', (tester) async {
    await pumpReview(tester, entries: [realEntry(date: '2026-08-30')]);

    expect(find.textContaining('8月30日'), findsOneWidget);
    expect(find.text('来自：睡眠会话'), findsOneWidget);
  });

  testWidgets('只有演示数据时说明不可补充', (tester) async {
    await pumpReview(tester, entries: [demoEntry()]);

    expect(find.textContaining('演示'), findsWidgets);
    expect(find.text('手动补录某一晚'), findsOneWidget);
  });

  testWidgets('没有任何记录时走空状态', (tester) async {
    await pumpReview(tester, entries: const []);

    expect(find.text('还没有可回顾的记录'), findsOneWidget);
  });

  testWidgets('可以换到别的晚上', (tester) async {
    await pumpReview(tester, entries: [
      realEntry(date: '2026-08-30', id: 'a'),
      realEntry(date: '2026-08-29', id: 'b'),
    ]);

    expect(find.textContaining('8月30日'), findsOneWidget);

    await tester.tap(find.textContaining('8月30日'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('8月29日'));
    await tester.pumpAndSettle();

    expect(find.textContaining('8月29日'), findsWidgets);
  });

  testWidgets('未评分的记录，星级一颗都不选中', (tester) async {
    await pumpReview(tester, entries: [realEntry(date: '2026-08-30', quality: null)]);

    final stars = tester.widget<QualityStars>(find.byType(QualityStars));
    expect(stars.value, isNull);
  });

  testWidgets('保存写回同一条 id，不新增副本', (tester) async {
    await pumpReview(tester, entries: [realEntry(date: '2026-08-30', id: 'night-a')]);

    await tester.tap(find.text('保存补充'));
    await tester.pumpAndSettle();

    final rows = await database.allRecords();
    expect(rows, hasLength(1));
    expect(rows.single.id, 'night-a');
  });

  testWidgets('保存补充时不改动起止时刻', (tester) async {
    final before = realEntry(date: '2026-08-30', id: 'night-a');
    await pumpReview(tester, entries: [before]);

    await tester.tap(find.text('保存补充'));
    await tester.pumpAndSettle();

    final row = (await database.allRecords()).single;
    expect(row.startAtUtc, before.startAtUtc);
    expect(row.endAtUtc, before.endAtUtc);
  });
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/review_page_test.dart`
Expected: 编译失败——`review_page.dart` 还不存在。

- [ ] **Step 3: 实现回顾页**

`review_page.dart` 结构：

1. `PageHeading(eyebrow: '回顾', title: '睡得怎么样？')`
2. 记录头（可点，打开选择器）：日期、`入睡 → 起床`、时长、`来自：<来源>`。
   来源文案：`session` → 「睡眠会话」，`import` → 「导入」，其余 → 「手动记录」。
3. `SectionHeader('睡眠质量')` + `QualityStars(value: _quality, ...)`
4. `SectionHeader('睡眠事件')` + 四个 `_EventTile`。`_EventTile` 现在是
   `log_page.dart` 里的私有类（起于 **564 行**），连同四类事件的图标与语义色
   （`log_page.dart` 的 **318–374 行**：打鼾/`AppIcons.snore`/`accentBlue`、
   说梦话/`AppIcons.bubble`/`accentViolet`、辗转难眠/`AppIcons.sparkle`/`caution`、
   噩梦/`AppIcons.moon`/`danger`）一起提成公开的
   `lib/features/sleep/presentation/widgets/event_tiles.dart`，`log_page.dart`
   与回顾页都改用共享版。

   搬运时**必须保留 `_EventTile` 里那段关于「图标要在构造 `SvgPicture.string`
   的那一刻就烤进颜色」的注释**——深色模式下每个 tile 变成黑色，就是当初忽略
   它造成的。
5. `SectionHeader('备注')` + `TextField`
6. `PrimaryAction(label: '保存补充')`
7. 底部次要入口：`Pressable` → `context.push('/log/new')`，文案「手动补录某一晚 ›」

保存：

```dart
  Future<void> _save(SleepEntry entry) async {
    await ref.read(sleepRepositoryProvider).save(
          id: entry.id,
          startAtUtc: entry.startAtUtc,
          endAtUtc: entry.endAtUtc,
          timeZoneId: entry.timeZoneId,
          quality: _quality,
          notes: _notesController.text.trim(),
          events: _events,
          source: entry.source,
          // `stages` 留空 = **保持已有阶段不变**。补充感受绝不能抹掉设备测到的
          // 睡眠阶段——这是 `save()` 那个 nullable 参数存在的全部理由。
        );
    ref.read(toastProvider.notifier).show('已更新这一晚的感受。');
  }
```

记录头的 `current` 状态：`SleepEntry? _selected`，初始为
`entries.firstWhereOrNull((e) => e.source != 'demo')`。列表变化时若 `_selected`
已不在列表里，回落到默认。

- [ ] **Step 4: 换成回顾 Tab**

`app_shell.dart`：

```dart
  log('log', '回顾'),
```

**id 保持 `'log'` 不动**：它是标签条取实心图标的键（`filledTabGlyph(tab.id, …)`），
改了会让标签图标静默掉回描边态。笔的图标继续用——「写感受」正好是它的意思。

`app.dart` 的 `_TabContent` 里 `AppTab.log => const ReviewPage(),`。

- [ ] **Step 5: 跑测试确认通过**

Run: `flutter test test/review_page_test.dart test/pages_widget_test.dart`
Expected: 全 PASS（`pages_widget_test` 里断言「记录」标签文案的用例需要跟着改成「回顾」）。

- [ ] **Step 6: 提交**

```bash
dart format . && flutter analyze && flutter test
git add lib/features/log/presentation/review_page.dart \
        lib/features/log/presentation/review_night_picker.dart \
        lib/features/sleep/presentation/widgets/event_tiles.dart \
        lib/features/log/presentation/log_page.dart \
        lib/app/app_shell.dart lib/app/app.dart test/review_page_test.dart \
        test/pages_widget_test.dart
git commit -m "feat(log): 「记录」Tab 改为「回顾」Tab

默认补充最近一条真实记录，记录头可点开选择器换到任意一晚（演示记录不出现
在选择器里）。空状态与「只有演示数据」都给出如实说明并保留手动补录入口。

Tab 的 id 保持 'log'：它是标签条取实心图标的键，改掉会让图标静默掉回描边态。

回顾页**不改起止时刻**——它补的是感受，不是记录。要改时刻走详情页的编辑记录。
stages 传 null（保持已有阶段不变），补充感受绝不能抹掉设备测到的阶段。

四类事件格子提成共享组件供表单与回顾页共用。"
```

---

## Task 10: `LogPage` 改为纯推入页 + `/log/new`

**Files:**
- Create: `lib/features/log/presentation/log_new_page.dart`
- Modify: `lib/features/log/presentation/log_page.dart`
- Modify: `lib/app/app.dart`
- Test: `test/pages_widget_test.dart`, `test/record_edit_delete_test.dart`

**Interfaces:**
- Consumes: `LogPage`、`Subpage`
- Produces: `class LogNewPage extends StatelessWidget`（路由 `/log/new`）

- [ ] **Step 1: 改测试（先红）**

`test/pages_widget_test.dart` 里断言「保存后切到首页 Tab」的用例改为断言
「保存后 pop 掉、不再切换 Tab」。`test/record_edit_delete_test.dart` 同理。
先改测试跑一次，确认变红。

- [ ] **Step 2: 把 `LogPage` 的 Tab 分支删掉**

`log_page.dart`：

```dart
  @override
  Widget build(BuildContext context) {
    ...
    // 手动补录与编辑现在**只会**以推入路由的形式出现（回顾 Tab 取代了原来的
    // 「记录」Tab），所以永远自带外框。Tab 分支随之删除，附带的两个跨页副作用
    // 也一起消失：不再需要「保存后切回首页」，也不再需要「2 秒后重置已保存态」
    // —— 推入页 pop 掉就没了，不存在需要重置的下一次。
    return Subpage(
      title: _isEditing ? '编辑记录' : '手动补录',
      children: items,
    );
  }
```

并删掉 `_isEditing == false` 时那段 `PageHeading(eyebrow: '记录睡眠', title: '今天睡得怎么样？')`
（`Subpage` 自带标题），以及顶部对 `pageGutter` / `pageTopInset` / `pageBottomInset`
与 `ListView` 的使用。

保存分支统一为：

```dart
      ref.read(toastProvider.notifier).show(
            editing != null ? '记录已更新。' : '睡眠记录已保存。',
          );
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      } else {
        context.go('/');
      }
```

删掉 `_saved` 状态与那个 `Future.delayed` 重置（推入页 pop 掉就没有「下一次」了），
按钮文案固定为 `_saving ? '保存中…' : (_isEditing ? '保存修改' : '保存记录')`。

- [ ] **Step 3: 加 `/log/new` 路由**

新建 `lib/features/log/presentation/log_new_page.dart`：

```dart
import 'package:flutter/material.dart';

import 'log_page.dart';

/// 手动补录某一晚。
///
/// 能力原先是「记录」Tab 的正文，现在降级成二级页——它没有消失，只是不再占一个
/// 标签位。入口在回顾页底部，以及会话时长越界时的说明层里。
class LogNewPage extends StatelessWidget {
  const LogNewPage({super.key});

  @override
  Widget build(BuildContext context) => const LogPage();
}
```

`app.dart` 加路由：

```dart
        GoRoute(
          path: 'log/new',
          builder: (context, state) => const LogNewPage(),
        ),
```

- [ ] **Step 4: 跑全套**

Run: `dart format . && flutter analyze && flutter test`
Expected: 全 PASS。

- [ ] **Step 5: 变异验证**

把 `LogPage` 的 `Subpage` 换回 `Scaffold(body: ListView(...))`，跑
`test/pages_widget_test.dart`：断言「推入页无 Material 祖先会露出下划线」的那类
用例（`pumpRoute` + `expectProperlyRendered`）必须变红。恢复。

- [ ] **Step 6: 提交**

```bash
git add lib/features/log/presentation/log_page.dart \
        lib/features/log/presentation/log_new_page.dart lib/app/app.dart \
        test/pages_widget_test.dart test/record_edit_delete_test.dart
git commit -m "refactor(log): LogPage 改为纯推入页，手动补录入 /log/new

回顾 Tab 取代「记录」Tab 之后，这个表单只会被推入，Tab 分支随之删除，
顺带消掉两个跨页副作用：不再需要「保存后切回首页」，也不再需要「2 秒后重置
已保存态」——推入页 pop 掉就没了。

手动补录能力没有消失，只是换了入口层级。"
```

---

## Task 11: 文档同步

**Files:**
- Modify: `docs/superpowers/specs/2026-09-28-night-sleep-design.md`
- Modify: `docs/superpowers/specs/2026-09-30-sleep-session-design.md`（状态改「已完成（plan A）」）
- Modify: `README.md`
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: 前面所有任务的实现
- Produces: 无

- [ ] **Step 1: 同步主规格**

按 `2026-09-30-sleep-session-design.md` 的 §十四「文档同步清单」逐条改：

- §2.4 页面表：新增会话页与回顾页两行，「记录」一行改写。
- §3 映射表：补会话页、回顾页、`ActiveSessions`、`scheduleOnce` 的代码位置。
- §4 里程碑：M1 补「手动录入降级为二级页」；**M3 由「未开始」改为「进行中：
  会话页已落地，夜间录音见 plan B」**。
- §5.1 表结构：加 `ActiveSessions`；`quality` 的约束改为「1–5 或空（未评分）」；
  补 v3 → v4 的两步迁移。
- §5.2 计算口径：补「质量为空时不产生评分」。
- §7 隐私：补麦克风与录音的本地存储、保留期限、一键删除（plan B 用，先写着）。
- §8 偏差表：补 #23–#27，并把 #7 标注为「plan B 落地后作废」。
- §9 测试矩阵：补本计划各任务的用例。
- §10：麦克风用途文案从「待提供」改为「已起草，待确认」。

- [ ] **Step 2: 同步 README**

- 「当前实现范围」加会话、回顾与显示名。
- 「未实现」表保留「夜间录音/鼾声梦话检测」一行（plan B 才做），
  把 Android 那一行补上 `RECORD_AUDIO` 与前台服务。
- 「验证记录」补本轮的 `flutter test` 条数与未验证项。

- [ ] **Step 3: 写 CHANGELOG**

新增 **3.0（2026-09-30）** 一节，记清：显示名、会话、回顾、闹钟、
以及**两处诚实的边界**（会话不测量任何东西；录音仍未接入，开关只存偏好）。

- [ ] **Step 4: 跑最后一遍全套**

Run: `dart format --set-exit-if-changed . && flutter analyze && flutter test`
Expected: 无改动；`No issues found`；全 PASS。

- [ ] **Step 5: 提交**

```bash
git add docs/ README.md CHANGELOG.md
git commit -m "docs: 同步 v3.0 —— 会话与回顾的主规格、README 与变更记录

偏差表补 #23-#27；M3 由「未开始」改为「进行中」；README 的未实现表保留
夜间录音一行（plan B 才做）并补 Android 的录音权限。"
```

---

## 完成标准

- `dart format --set-exit-if-changed .` 无改动
- `flutter analyze` → No issues found
- `flutter test` → 全绿，且**每条新断言都做过变异验证**
- 显示名在 iOS / macOS / Web 三处都是「夜深」
- 会话能开始、收起、改设定、结束落库、丢弃
- 起床闹钟在真机上真的响过（**这条必须在真机确认后才算完成**）
- README 的「未实现」表如实反映：夜间录音仍未接入

## 已知的未验证项（不要写成已完成）

- 通知是否真的到点投递——Dart 侧契约有测试，投递本身需真机确认
- `timeSensitive` 是否真的穿透了专注模式——需真机开专注模式实测
- 宽屏（macOS 侧边栏）下的会话页与回顾页需要逐屏核对
- Dock / 桌面显示名的实际观感——plist 改了不等于系统重读了缓存
