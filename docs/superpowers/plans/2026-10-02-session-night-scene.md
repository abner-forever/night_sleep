# 会话页夜景改版实现计划（plan C）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `/sleep/session`（「正在睡眠」）按新原型 `SleepView` 的「睡眠进行中」态重建——月亮 + `HH:MM:SS` 实时计时、八套夜景氛围动画背景、当前睡眠事件卡、横向长按结束按钮。

**Architecture:** 不改数据语义，只动 `features/session/presentation/` 与 `ActiveSessions` 的一个新可空列。页面自己带一套深色材质（`night_style.dart`），整页包在 `Theme(AppTheme.dark())` 里，让复用的共享组件（白噪音宫格 / 音量条 / 时长 chip / `IosToggle`）照常从 `AppTokens` 取深色值，不抄第二份。八套场景的动画由**一个** 60 秒循环的 `AnimationController` 驱动，全部画在一个 `CustomPaint` 里。

**Tech Stack:** Flutter 3.47.5 / Dart 3 / Riverpod / Drift（schema v5）/ go_router / `flutter_svg` 2.3。

**设计出处:** `docs/superpowers/specs/2026-09-30-sleep-session-design.md` §十六（本轮新增），偏差 #28–#32。

## Global Constraints

- 界面文案、注释、文档**一律中文**；代码标识符英文。
- **本轮范围只到会话页**（使用方裁定）。`AppTokens` / `AppRadii` / `AppTheme` / `AppShell` 与其余四页**一个字节都不动**；需要新色值时进 `night_style.dart`。
- 不碰 `lib/**/*.g.dart`（Drift 生成，已 gitignore）。改表结构后必须跑 `dart run build_runner build`。
- 产品红线，**一个字都不许改**：
  - 鼾声那一行的 `'尚未接入录音，开关只保存偏好。'`（偏差 #7）。
  - 投递强度标注必须用 `ReminderScheduler.wakeAlarmDeliveryNote` 这份字面量，不另抄一遍。
  - 白噪音定时只有 15/30/45/60，**没有「整晚」**；默认 30。
  - 空状态、时长守门 `(0, 24h]` 不落库、就地评星、丢弃、白噪音生命周期（关弹窗 / 收起页面都继续响）全部原样保留。
- **循环动画与 `pumpAndSettle` 不能共存。** 已实测：`AnimationController.repeat()` 挂上之后 `pumpAndSettle()` 会 `timed out`（`test/_scratch_anim_test.dart` 临时验过，已删）。因此：
  - 所有 widget 测试夹具必须设 `tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);` 并 `addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);`（已实测可让 `MediaQuery.disableAnimationsOf` 为真且 `pumpAndSettle` 收敛）。
  - 只有 `test/night_backdrop_test.dart` 开动画，且那一份**只用显式 `pump()`**，绝不用 `pumpAndSettle()`。
- 每条任务结束时跑一次 `flutter test test/sleep_session_page_test.dart`；Task 10 跑全量。

---

### Task 1: schema v5 —— `active_sessions.scene_id`

**Files:**
- Modify: `lib/core/database/app_database.dart:116-140`（表定义）、`:191`（版本号）、`:196-242`（迁移）
- Modify: `lib/features/sleep/domain/sleep_session.dart:8-34`
- Modify: `lib/features/sleep/data/session_repository.dart:33-48`、`:56-75`、`:128-136`
- Test: `test/schema_migration_test.dart`、`test/session_repository_test.dart`

**Interfaces:**
- Produces: `SleepSession.sceneId`（`String?`，未设过为 `null`）；`SessionRepository.update(sceneId: ...)`（`Object?` 参数，与既有的 `noiseId` 同款哨兵语义：不传 = 不动，显式传 `null` = 清成默认）。

- [ ] **Step 1: 改表定义与版本**

`lib/core/database/app_database.dart` 的 `ActiveSessions` 里，`noiseVolume` 之后加一列：

```dart
  /// 选中的夜景氛围 id（见 `NightScene`）。`null` = 用默认的「流星夜」。
  ///
  /// 存 id 字符串而不是枚举序号，与 [noiseId] 同一条既有做法：读不到认识的 id 时
  /// 按默认处理，一行坏数据不至于让整个会话读不出来。
  TextColumn get sceneId => text().nullable()();
```

`int get schemaVersion => 4;` 改成 `=> 5;`。

`onUpgrade` 的末尾（`if (from < 4) {...}` 之后）追加：

```dart
          if (from < 5) {
            // 只加一列可空列，不重建表：SQLite 的 `ALTER TABLE ADD COLUMN` 支持
            // 可空列原地添加，与 v4 那次「改可空性必须重建」是两回事。
            await m.addColumn(activeSessions, activeSessions.sceneId);
          }
```

- [ ] **Step 2: 跑 build_runner 并确认生成物跟上**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: 成功，`lib/core/database/app_database.g.dart` 里出现 `sceneId`。

- [ ] **Step 3: 领域模型与仓库**

`lib/features/sleep/domain/sleep_session.dart`：构造函数加参数 `this.sceneId,`（放在 `noiseId` 之前），并加字段：

```dart
  /// 选中的夜景氛围 id。`null` 表示没选过，界面按默认的「流星夜」渲染。
  final String? sceneId;
```

`lib/features/sleep/data/session_repository.dart`：

1. `update` 的参数表在 `double? noiseVolume,` 之后加 `Object? sceneId = _unset,`，并在 `updateActiveSession` 的 companion 里加：

```dart
        sceneId: identical(sceneId, _unset)
            ? const Value.absent()
            : Value(sceneId as String?),
```

2. `_toSession` 里加 `sceneId: row.sceneId,`。

3. 在 `update` 的文档注释上补一句：

```dart
  /// 只改传入的字段。`noiseId` 与 `sceneId` 显式传 `null` 表示清成默认/取消选择。
```

- [ ] **Step 4: 写失败测试（迁移）**

`test/schema_migration_test.dart` 末尾的 `_V3Database` 之后，加一份 v4 夹具（**裸 DDL，冻住，不要为了对齐当前 schema 去改它**）：

```dart
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
```

再在 `main()` 里（`group('v3 → v4', ...)` 之后）加：

```dart
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
```

- [ ] **Step 5: 跑测试，确认失败**

Run: `flutter test test/schema_migration_test.dart --plain-name "v4 → v5"`
Expected: FAIL —— `sceneId` 未定义 / `_V4Database` 不存在。

- [ ] **Step 6: 写仓库测试**

`test/session_repository_test.dart` 末尾追加（沿用该文件既有的 `repository` / `db` 夹具名，若不同则就地对齐）：

```dart
  test('场景 id 写进会话行，重开还在', () async {
    await repository.start(now: DateTime(2026, 8, 30, 23, 14));
    await repository.update(sceneId: 'galaxy');

    expect((await repository.load())!.sceneId, 'galaxy');
  });

  test('不传 sceneId 时不动它；显式传 null 才清回默认', () async {
    await repository.start(now: DateTime(2026, 8, 30, 23, 14));
    await repository.update(sceneId: 'ocean');

    // 改别的字段不该顺手把场景抹掉——`_unset` 哨兵存在的全部理由。
    await repository.update(alarmEnabled: true);
    expect((await repository.load())!.sceneId, 'ocean');

    await repository.update(sceneId: null);
    expect((await repository.load())!.sceneId, isNull);
  });
```

- [ ] **Step 7: 跑测试**

Run: `flutter test test/schema_migration_test.dart test/session_repository_test.dart`
Expected: PASS。

- [ ] **Step 8: 格式化、静态检查、提交**

Run: `dart format . && flutter analyze`
Expected: 无告警。

```bash
git add lib/core/database/app_database.dart lib/core/database/app_database.g.dart lib/features/sleep/domain/sleep_session.dart lib/features/sleep/data/session_repository.dart test/schema_migration_test.dart test/session_repository_test.dart
git commit -m "feat(session): schema v5 —— 会话行记住选中的夜景氛围"
```

---

### Task 2: 页面局部令牌 `NightStyle` 与场景表 `NightScene`

**Files:**
- Create: `lib/features/session/presentation/night_style.dart`
- Create: `lib/features/session/presentation/night_scene.dart`
- Test: `test/night_scene_test.dart`

**Interfaces:**
- Produces:
  - `abstract final class NightStyle` —— 常量 + `static bool reduceMotion(BuildContext)`。
  - `enum NightScene` —— `id` / `label` / `background`（`Gradient`）/ `previewGradient` / `previewDots`；`static const fallback`；`static NightScene fromId(String?)`。

- [ ] **Step 1: 写 `night_style.dart`**

```dart
import 'package:flutter/material.dart';

/// 会话页（「正在睡眠」）自己的材质与调色板。
///
/// **为什么不吃 `AppTokens`**：新原型的最终生效层把全站换成了扁平原生风
/// （`.glass` 不再模糊/描边/投影、底色改 `#f4f5f8`、主按钮改纯色），而这一轮的范围
/// **只到会话页**——把那些值塞进 `AppTokens` 会连带改掉首页/回顾/统计/设置四页
/// （见规格 §16.7 与偏差 #32）。约定不破：一个概念仍只有一处，只是这一处落在这一页。
///
/// 值逐条取自原型 `index.css` 的 `.sleep-mode` / `.sleep-events` /
/// `.sleep-option-card` / `.sleep-event-*` / `.sleep-hold-button` /
/// `.sleep-navigation-back` / `.sleep-settings-sheet` 等规则，注释里标出原始字面量。
abstract final class NightStyle {
  // ── 卡片 ────────────────────────────────────────────────────────────────
  /// `.sleep-events`（激活态）：`linear-gradient(145deg, .075, .035)`。
  static const eventsFillTop = Color(0x13FFFFFF); // rgba(255,255,255,.075)
  static const eventsFillBottom = Color(0x09FFFFFF); // rgba(255,255,255,.035)
  /// `.sleep-option-card`：`1px rgba(255,255,255,.09)` 描边。
  static const cardStroke = Color(0x17FFFFFF); // rgba(255,255,255,.09)
  /// `.sleep-event-row` 的分隔线。
  static const rowDivider = Color(0x11FFFFFF); // rgba(255,255,255,.065)

  // ── 文字 ────────────────────────────────────────────────────────────────
  /// `.sleep-mode` 的前景色。
  static const textPrimary = Color(0xF5F4F7FF); // rgba(244,247,255,.96)
  /// `.sleep-control-copy strong` 一档。
  static const textStrong = Color(0xE6F4F7FF); // rgba(244,247,255,.90)
  /// `.sleep-events-title > span:first-child`。
  static const textHeading = Color(0xC2E1E5F4); // rgba(225,229,244,.76)
  /// `.sleep-event-row small`。
  static const textMuted = Color(0x7AE1E5F4); // rgba(225,229,244,.48)
  /// `.sleep-hold-wrap > p` / `.sleep-elapsed-label`。
  static const textFaint = Color(0x57E1E5F4); // rgba(225,229,244,.34)

  /// `.sleep-live-status`。
  static const statusText = Color(0x9ED6DEFF); // rgba(214,222,255,.62)
  static const statusDot = Color(0xFF8299FF);

  /// `.sleep-time-now`。
  static const clockText = Color(0x94E1E5F4); // rgba(225,229,244,.58)

  // ── 强调 ────────────────────────────────────────────────────────────────
  /// `.sleep-event-icon` 的图标色与底色。
  static const iconInk = Color(0xFFAEBDFF);
  static const iconFill = Color(0x1F7E91E9); // rgba(126,145,233,.12)
  /// `.sleep-event-state`（「记录中」「已设置」）。
  static const stateInk = Color(0xFF9FAFEF);
  /// `.sleep-scene-choice.is-selected` 的文字色。
  static const selectedInk = Color(0xFFC4D0FF);
  /// `.sleep-scene-choice.is-selected .sleep-scene-preview` 的描边与外圈。
  static const selectedStroke = Color(0xB8AEBEFF); // rgba(174,190,255,.72)
  static const selectedGlow = Color(0x2E7A8FEB); // rgba(122,143,235,.18)

  // ── 顶部胶囊与结束按钮 ───────────────────────────────────────────────────
  static const glassStroke = Color(0x1CFFFFFF); // rgba(255,255,255,.11)
  static const glassFill = Color(0x11FFFFFF); // rgba(255,255,255,.065)
  static const glassInk = Color(0xD1E1E8FF); // rgba(225,232,255,.82)
  static const holdInk = Color(0xD1F2F4FC); // rgba(242,244,252,.82)
  /// `.sleep-hold-fill`。
  static const holdFill = Color(0x57707ECA); // rgba(112,126,202,.34)

  // ── 白噪音弹窗 ──────────────────────────────────────────────────────────
  static const sheetFillTop = Color(0xF7232A44); // rgba(35,42,68,.97)
  static const sheetFillBottom = Color(0xFA0D111F); // rgba(13,17,31,.98)
  static const sheetStroke = Color(0x1FFFFFFF); // rgba(255,255,255,.12)
  static const scrim = Color(0x9402050C); // rgba(2,5,12,.58)
  static const handle = Color(0x33E1E5F4); // rgba(225,229,244,.20)
  /// 弹窗里「音量」「播放时长」两块的内底色：`rgba(255,255,255,.035)`。
  static const fieldFill = Color(0x09FFFFFF);

  // ── 尺寸 ────────────────────────────────────────────────────────────────
  static const cardRadius = 22.0; // .sleep-option-card / .sleep-events
  static const sheetRadius = 30.0; // .sleep-settings-sheet
  static const pickerRadius = 20.0; // 激活态的场景选择器
  static const previewRadius = 13.0; // .sleep-scene-preview
  static const eventIconSize = 34.0; // .sleep-event-icon
  static const eventIconRadius = 12.0;
  static const eventRowMinHeight = 61.0; // .sleep-event-row
  static const holdButtonMinHeight = 56.0;
  static const holdButtonRadius = 18.0;
  static const scenePreviewWidth = 64.0;
  static const scenePreviewHeight = 42.0;

  /// 系统开了「减弱动态效果」没有。对应原型 CSS 里的
  /// `@media (prefers-reduced-motion: reduce)`。
  static bool reduceMotion(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context);
}
```

- [ ] **Step 2: 写 `night_scene.dart`**

```dart
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 会话页的夜景氛围。id 与中文标签逐字取自原型的 `SLEEP_SCENES`。
enum NightScene {
  meteor('meteor', '流星夜'),
  aurora('aurora', '极光'),
  ocean('ocean', '深海'),
  moon('moon', '月海'),
  cloud('cloud', '云上'),
  firefly('firefly', '萤火'),
  galaxy('galaxy', '银河'),
  rain('rain', '雨夜');

  const NightScene(this.id, this.label);

  final String id;
  final String label;

  /// 原型 `useState<SleepScene>('meteor')` 的初值。
  static const fallback = NightScene.meteor;

  /// 按 id 解析。**读不到认识的 id 时回落默认**——与 `noiseId` 同一条既有做法：
  /// 一行坏数据不该让整个会话读不出来。
  static NightScene fromId(String? id) {
    for (final scene in values) {
      if (scene.id == id) return scene;
    }
    return fallback;
  }

  /// 整页底色，逐字取自 `.sleep-scene-*`。
  Gradient get background => switch (this) {
        NightScene.meteor =>
          _css(165, [const Color(0xFF11162A), const Color(0xFF080B16)], [0, .72]),
        NightScene.aurora => _css(
            165,
            [const Color(0xFF071D29), const Color(0xFF0A1224), const Color(0xFF090C18)],
            [0, .58, 1]),
        NightScene.ocean => _css(
            180,
            [const Color(0xFF071827), const Color(0xFF06111C), const Color(0xFF030810)],
            [0, .55, 1]),
        NightScene.moon => _css(
            160,
            [const Color(0xFF17182D), const Color(0xFF0D1020), const Color(0xFF080A13)],
            [0, .60, 1]),
        NightScene.cloud => _css(
            165,
            [const Color(0xFF20283C), const Color(0xFF111827), const Color(0xFF0B101C)],
            [0, .60, 1]),
        NightScene.firefly => _css(
            165,
            [const Color(0xFF0E211D), const Color(0xFF071510), const Color(0xFF050B09)],
            [0, .60, 1]),
        NightScene.galaxy => _css(
            155,
            [const Color(0xFF1C1236), const Color(0xFF0D1028), const Color(0xFF070916)],
            [0, .55, 1]),
        NightScene.rain => _css(
            165,
            [const Color(0xFF17212C), const Color(0xFF0B121C), const Color(0xFF070B11)],
            [0, .58, 1]),
      };

  /// 预览小卡的底色，逐字取自 `.sleep-scene-preview-*`。
  ///
  /// 雨夜那条原型用的是 `repeating-linear-gradient` 画斜纹，Flutter 的渐变不能重复，
  /// 这里用一串交替的 `stops` 近似出同样的斜纹观感（64×42 的缩略图上看不出差别）。
  Gradient get previewGradient => switch (this) {
        NightScene.meteor => const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1B2340), Color(0xFF11162A)]),
        NightScene.aurora => _css(
            145,
            [const Color(0xFF0B3A3A), const Color(0xFF172850), const Color(0xFF09111F)],
            [0, .56, 1]),
        NightScene.ocean => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0B3047), Color(0xFF06101B)]),
        NightScene.moon => _css(
            145, [const Color(0xFF262844), const Color(0xFF0C1020)]),
        NightScene.cloud => _css(
            145, [const Color(0xFF465269), const Color(0xFF151E2D)]),
        NightScene.firefly => const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0C2A20), Color(0xFF092018)]),
        NightScene.galaxy => _css(
            145,
            [const Color(0xFF3A205D), const Color(0xFF101839), const Color(0xFF090D1B)],
            [0, .55, 1]),
        NightScene.rain => _css(105, const [
          Color(0x00000000), Color(0x00000000), Color(0x24BED5EB),
          Color(0x24BED5EB), Color(0x00000000), Color(0x00000000),
          Color(0x24BED5EB), Color(0x24BED5EB), Color(0x00000000),
          Color(0x00000000), Color(0x24BED5EB), Color(0x24BED5EB),
          Color(0x00000000), Color(0x00000000),
        ], const [
          0, .14, .15, .28, .29, .43, .44, .57, .58, .72, .73, .86, .87, 1,
        ]),
      };

  /// 预览卡上那几个光点。`.sleep-scene-preview i` 的三颗星在每一张上都在；
  /// 月海与萤火另有各自的原生径向点。
  List<Alignment> get previewDots => switch (this) {
        NightScene.rain => const [],
        NightScene.moon => const [Alignment(0.44, -0.4)],
        NightScene.firefly => const [
            Alignment(-0.5, 0.2),
            Alignment(0.44, -0.3),
          ],
        _ => const [
            Alignment(-0.72, -0.52),
            Alignment(-0.28, 0.38),
            Alignment(0.56, -0.14),
          ],
      };

  /// CSS 的 `linear-gradient(<deg>, …)` 用「0° 朝上、顺时针」；这里换算成 Flutter
  /// 的两个 `Alignment`。非正方形容器上角度会有轻微偏差（Flutter 按盒子比例归一化
  /// 控点），对这八条差不到 10° 的暗色渐变来说看不出来。
  static LinearGradient _css(
    double deg,
    List<Color> colors, [
    List<double>? stops,
  ]) {
    final rad = deg * math.pi / 180;
    final dx = math.sin(rad);
    final dy = -math.cos(rad);
    return LinearGradient(
      begin: Alignment(-dx, -dy),
      end: Alignment(dx, dy),
      colors: colors,
      stops: stops,
    );
  }
}
```

- [ ] **Step 3: 写测试**

`test/night_scene_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/features/session/presentation/night_scene.dart';

void main() {
  test('八种场景的 id 与标签与原型一致', () {
    expect(NightScene.values.map((s) => s.id).toList(), [
      'meteor', 'aurora', 'ocean', 'moon', 'cloud', 'firefly', 'galaxy', 'rain',
    ]);
    expect(NightScene.meteor.label, '流星夜');
    expect(NightScene.rain.label, '雨夜');
  });

  test('每个场景都有底色与预览底色', () {
    for (final scene in NightScene.values) {
      expect(scene.background.colors.length, greaterThanOrEqualTo(2),
          reason: '${scene.id} 的整页底色缺失');
      expect(scene.previewGradient.colors.length, greaterThanOrEqualTo(2),
          reason: '${scene.id} 的预览底色缺失');
    }
  });

  test('认不出的 id 回落默认场景，不抛', () {
    expect(NightScene.fromId('galaxy'), NightScene.galaxy);
    // 库里可能存着上一个版本写下的 id，或干脆是坏数据。
    expect(NightScene.fromId('nebula-2077'), NightScene.fallback);
    expect(NightScene.fromId(null), NightScene.fallback);
    expect(NightScene.fromId(''), NightScene.fallback);
  });
}
```

- [ ] **Step 4: 跑测试**

Run: `flutter test test/night_scene_test.dart`
Expected: PASS。

- [ ] **Step 5: 格式化、静态检查、提交**

Run: `dart format . && flutter analyze`

```bash
git add lib/features/session/presentation/night_style.dart lib/features/session/presentation/night_scene.dart test/night_scene_test.dart
git commit -m "feat(session): 会话页的夜景调色板与八种场景表"
```

---

### Task 3: `SleepSession.elapsedClockAt`

**Files:**
- Modify: `lib/features/sleep/domain/sleep_session.dart:63-91`
- Test: `test/sleep_session_test.dart`

**Interfaces:**
- Produces: `String SleepSession.elapsedClockAt(DateTime now)` —— `HH:MM:SS`，小时不封顶、不回绕。

- [ ] **Step 1: 写失败测试**

`test/sleep_session_test.dart` 末尾追加：

```dart
  group('elapsedClockAt', () {
    test('从 00:00:00 起算，时分秒都补零', () {
      final start = DateTime(2026, 8, 30, 23, 14);
      final session = SleepSession(
        startAtUtc: start.toUtc(),
        timeZoneId: 'UTC',
        wakeMinutes: 7 * 60,
        alarmEnabled: false,
        createdAtUtc: start.toUtc(),
      );

      expect(session.elapsedClockAt(start), '00:00:00');
      expect(
        session.elapsedClockAt(start.add(const Duration(hours: 3, minutes: 42))),
        '03:42:00',
      );
      expect(
        session.elapsedClockAt(
            start.add(const Duration(hours: 3, minutes: 42, seconds: 7))),
        '03:42:07',
      );
    });

    test('超过 24 小时不回绕——小时一直往上加', () {
      final start = DateTime(2026, 8, 30, 23, 14);
      final session = SleepSession(
        startAtUtc: start.toUtc(),
        timeZoneId: 'UTC',
        wakeMinutes: 7 * 60,
        alarmEnabled: false,
        createdAtUtc: start.toUtc(),
      );

      // 「忘了结束、放了两天」是会真的发生的；读数该如实说 48 小时，
      // 而不是像钟表一样回绕成 00:00——回绕会把一个明显的异常藏起来。
      expect(
        session.elapsedClockAt(start.add(const Duration(hours: 48))),
        '48:00:00',
      );
    });

    test('负时长夹到零，不出现负号', () {
      final start = DateTime(2026, 8, 30, 23, 14);
      final session = SleepSession(
        startAtUtc: start.toUtc(),
        timeZoneId: 'UTC',
        wakeMinutes: 7 * 60,
        alarmEnabled: false,
        createdAtUtc: start.toUtc(),
      );

      expect(
        session.elapsedClockAt(start.subtract(const Duration(minutes: 5))),
        '00:00:00',
      );
    });
  });
```

- [ ] **Step 2: 跑测试，确认失败**

Run: `flutter test test/sleep_session_test.dart --plain-name "elapsedClockAt"`
Expected: FAIL —— `elapsedClockAt` isn't defined。

- [ ] **Step 3: 实现**

`lib/features/sleep/domain/sleep_session.dart`，在 `elapsedLabelAt` 之后加：

```dart
  /// 已睡时长的**钟表读法** `HH:MM:SS`，供会话页中央那个大数字用。
  ///
  /// 与 [elapsedLabelAt]（`3h 42m`）并存而不是合并：首页「正在睡眠 · 已睡 3h42m」
  /// 卡要的是粗读，会话页那一屏要的是每秒都在动的秒表——两处本来就该有不同的读法。
  ///
  /// **小时不封顶、不回绕**：原型 `formatElapsed` 就是这么算的，而且回绕会把
  /// 「忘了结束、放了两天」这件明显的异常藏成一个正常的 00:00。
  String elapsedClockAt(DateTime now) {
    final total = elapsedAt(now).inSeconds;
    if (total <= 0) return '00:00:00';
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    final seconds = total % 60;
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
```

- [ ] **Step 4: 跑测试**

Run: `flutter test test/sleep_session_test.dart`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add lib/features/sleep/domain/sleep_session.dart test/sleep_session_test.dart
git commit -m "feat(session): 会话页计时口径补一个 HH:MM:SS 的钟表读法"
```

---

### Task 4: `AppIcons.holdEnd` 与 `SleepMoonMark`

**Files:**
- Modify: `lib/core/widgets/app_icons.dart:67-76`（加 path 常量）、`:249-251`（加访问器）
- Create: `lib/features/session/presentation/widgets/sleep_moon_mark.dart`
- Test: `test/sleep_moon_mark_test.dart`

**Interfaces:**
- Produces: `AppIcons.holdEnd({size, color, strokeWidth})`；`class SleepMoonMark extends StatelessWidget` —— `SleepMoonMark({Key? key, double size = 92, bool live = false})`。

**背景（已实测，实现者必须知道）：** `flutter_svg` 2.3 **会静默丢弃 `<filter>`**。把原型那份 `SleepMoonMark`（含 `feGaussianBlur` / `feFlood` / `feComposite` / `feMerge`）交给 `SvgPicture.string`，渐变与 `clipPath` 都正常，但控制台打印 `unhandled element <filter/>`——**外发光没画出来，且不抛异常**。所以这里**把 `<filter>` 元素整段去掉**（免得每帧打一行警告），外发光改用外面那圈径向光晕近似；这不是手画一个假形状，原型 `.sleep-moon-orbit::before/::after` 本来也各画了一圈光晕。

- [ ] **Step 1: 写失败的测试**

`test/sleep_moon_mark_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/core/widgets/app_icons.dart';
import 'package:night_sleep/features/session/presentation/widgets/sleep_moon_mark.dart';

void main() {
  testWidgets('月亮标记能渲染且不抛异常', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Center(child: SleepMoonMark())),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(SvgPicture), findsOneWidget);
  });

  test('交给 flutter_svg 的文档里没有 <filter>', () {
    // 实测：flutter_svg 2.3 会静默丢弃 <filter> 并在控制台打一行
    // `unhandled element <filter/>`。发光改用轨道光晕近似，所以源串里不该再有它，
    // 否则每帧一行警告，而且会让人误以为发光是滤镜画出来的。
    expect(sleepMoonSvg.contains('<filter'), isFalse);
    // 渐变与裁剪必须留着——月亮本体的质感全靠它们。
    expect(sleepMoonSvg.contains('linearGradient'), isTrue);
    expect(sleepMoonSvg.contains('radialGradient'), isTrue);
    expect(sleepMoonSvg.contains('clipPath'), isTrue);
  });

  test('「结束睡眠」的长按图标是一个独立的具名访问器', () {
    final widget = AppIcons.holdEnd(size: 20, color: const Color(0xFFFFFFFF));
    expect(widget, isNotNull);
  });
}
```

- [ ] **Step 2: 跑测试，确认失败**

Run: `flutter test test/sleep_moon_mark_test.dart`
Expected: FAIL —— `SleepMoonMark` / `sleepMoonSvg` / `AppIcons.holdEnd` 未定义。

- [ ] **Step 3: 加图标**

`lib/core/widgets/app_icons.dart` 的 `_trash` 之后加：

```dart
  // 长按结束：一只按在圆弧上的手，逐字取自原型 `icons.tsx` 的 `IconHoldEnd`。
  static const _holdEnd =
      '<path d="M8.5 11V7.5a1.5 1.5 0 0 1 3 0V11"/>'
      '<path d="M11.5 10V6.5a1.5 1.5 0 0 1 3 0V11"/>'
      '<path d="M14.5 10V8a1.5 1.5 0 0 1 3 0v5"/>'
      '<path d="M8.5 10.5 7 9.2a1.5 1.5 0 0 0-2.1 2.1l4.2 6.2A4 4 0 0 0 12.4 19H14a3.5 3.5 0 0 0 3.5-3.5V13"/>'
      '<path d="M5 4.5A9 9 0 0 1 19 4"/>';
```

再加一个「静音」图标——白噪音弹窗那格「关闭」用的：

```dart
  // 静音喇叭，逐字取自原型 `icons.tsx` 的 `IconSoundOff`。
  //
  // **不借 `_stop`（播放控制里的停止方块）凑数**：语义对不上，正是偏差 #12 当初
  // 骂过的那种「借一个形状差不多的图标」。
  static const _soundOff =
      '<path d="M11 5 6.5 9H3v6h3.5l2.1 1.9"/>'
      '<path d="M11 12V5"/>'
      '<path d="m15 10 6 6"/>'
      '<path d="m21 10-6 6"/>'
      '<path d="m3 3 18 18"/>';
```

两个访问器都加在 `trash` 之后：

```dart
  static Widget holdEnd(
          {double size = 24, Color? color, double strokeWidth = 1.6}) =>
      glyph(_holdEnd, size: size, color: color, strokeWidth: strokeWidth);

  static Widget soundOff(
          {double size = 24, Color? color, double strokeWidth = 1.6}) =>
      glyph(_soundOff, size: size, color: color, strokeWidth: strokeWidth);
```

- [ ] **Step 4: 写月亮标记**

`lib/features/session/presentation/widgets/sleep_moon_mark.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../night_style.dart';

/// 原型 `SleepMoonMark` 的月亮，逐字转写它的 SVG。
///
/// **`<filter>` 那一段被去掉了**，这是实测的结果而不是偷懒：`flutter_svg` 2.3 会
/// 静默丢弃 `<filter>`（控制台打一行 `unhandled element <filter/>`），渐变与裁剪
/// 都正常、外发光却不在，而且不抛异常。发光改由 [SleepMoonOrbit] 那圈径向光晕
/// 近似——原型自己的 `.sleep-moon-orbit::before/::after` 也各画了一圈光晕，
/// 所以这里近似的是同一层东西，不是凭空补一个形状。
///
/// 轨道光晕与月亮的**呼吸**动画都在 [SleepMoonOrbit] 里，本组件只管月亮本身。
const String sleepMoonSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="14 0 120 120">
  <defs>
    <linearGradient id="sleep-moon-body" x1="24" y1="18" x2="96" y2="104"
      gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#f5f7ff"/>
      <stop offset=".42" stop-color="#c8d4ff"/>
      <stop offset="1" stop-color="#8299eb"/>
    </linearGradient>
    <linearGradient id="sleep-moon-edge" x1="42" y1="24" x2="83" y2="93"
      gradientUnits="userSpaceOnUse">
      <stop stop-color="#ffffff" stop-opacity=".78"/>
      <stop offset="1" stop-color="#9cafef" stop-opacity=".08"/>
    </linearGradient>
    <radialGradient id="sleep-moon-crater">
      <stop stop-color="#6f82c8" stop-opacity=".5"/>
      <stop offset=".72" stop-color="#aebcf2" stop-opacity=".18"/>
      <stop offset="1" stop-color="#eef2ff" stop-opacity=".45"/>
    </radialGradient>
    <clipPath id="sleep-moon-clip">
      <path d="M78 17C53 20 34 39 34 63c0 25 20 44 45 42 14-1 26-8 34-19-8 4-17 6-26 4-22-4-36-24-33-46 2-13 11-23 24-27Z"/>
    </clipPath>
  </defs>
  <path d="M78 17C53 20 34 39 34 63c0 25 20 44 45 42 14-1 26-8 34-19-8 4-17 6-26 4-22-4-36-24-33-46 2-13 11-23 24-27Z"
    fill="url(#sleep-moon-body)"/>
  <g clip-path="url(#sleep-moon-clip)">
    <ellipse cx="45" cy="62" rx="9" ry="7" fill="url(#sleep-moon-crater)"
      transform="rotate(-18 45 62)"/>
    <ellipse cx="61" cy="87" rx="6.5" ry="5" fill="url(#sleep-moon-crater)"
      transform="rotate(22 61 87)"/>
    <ellipse cx="49" cy="39" rx="4" ry="3" fill="url(#sleep-moon-crater)"/>
    <path d="M27 77c18-8 35-24 47-48" fill="none" stroke="url(#sleep-moon-edge)"
      stroke-width="5" stroke-linecap="round"/>
  </g>
  <path d="M78 17C53 20 34 39 34 63c0 25 20 44 45 42" fill="none"
    stroke="rgba(255,255,255,.58)" stroke-width="1.2" stroke-linecap="round"/>
</svg>
''';

class SleepMoonMark extends StatelessWidget {
  const SleepMoonMark({super.key, this.size = 84});

  final double size;

  @override
  Widget build(BuildContext context) {
    // 原型 `.sleep-moon-mark { overflow: visible }`：月牙的两端会稍稍越出盒子，
    // 裁掉就会削掉两个尖。
    return SizedBox(
      width: size,
      height: size,
      child: SvgPicture.string(
        sleepMoonSvg,
        width: size,
        height: size,
        fit: BoxFit.contain,
        excludeFromSemantics: true,
      ),
    );
  }
}

/// 月亮 + 外面那圈轨道光晕。
///
/// `.sleep-moon-orbit`：116 见方的圆框，`1px rgba(150,167,255,.18)` 描边 + 径向
/// 渐变底 + 内外两层光晕。会话页中央那个大月亮（132 见方）额外套一层上下浮动。
class SleepMoonOrbit extends StatefulWidget {
  const SleepMoonOrbit({super.key, this.size = 116, this.live = false});

  /// 外圈直径。原型 setup 态是 116，激活态是 132。
  final double size;

  /// 激活态：整圈上下浮动（原型 `sleepFloat`，5 秒）。
  final bool live;

  @override
  State<SleepMoonOrbit> createState() => _SleepMoonOrbitState();
}

class _SleepMoonOrbitState extends State<SleepMoonOrbit>
    with SingleTickerProviderStateMixin {
  late final AnimationController _float = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 5),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 减弱动态效果时停表。循环动画会让 `pumpAndSettle()` 永不收敛，测试夹具因此
    // 一律把 `disableAnimations` 打开（见计划头部的 Global Constraints）。
    if (widget.live && !NightStyle.reduceMotion(context)) {
      if (!_float.isAnimating) _float.repeat(reverse: true);
    } else {
      _float.stop();
    }
  }

  @override
  void dispose() {
    _float.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.size;
    return AnimatedBuilder(
      animation: _float,
      builder: (context, child) => Transform.translate(
        // `sleepFloat { 50% { transform: translateY(-7px) } }`，往返。
        offset: Offset(0, -7 * Curves.easeInOut.transform(_float.value)),
        child: child,
      ),
      child: Container(
        width: d,
        height: d,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0x2E96A7FF)),
          gradient: const RadialGradient(
            colors: [Color(0x33758DED), Color(0x0F4A59A9), Color(0x00000000)],
            stops: [0, .60, .62],
          ),
          boxShadow: const [
            // 原型用 `box-shadow: 0 0 50px rgba(89,105,205,.15)` 加一层外发光。
            // 这也是月亮那一圈被 flutter_svg 丢掉的外发光的近似（见文件头注释）。
            BoxShadow(color: Color(0x265969CD), blurRadius: 50),
          ],
        ),
        child: Center(child: SleepMoonMark(size: d * 0.79)),
      ),
    );
  }
}
```

- [ ] **Step 5: 跑测试**

Run: `flutter test test/sleep_moon_mark_test.dart`
Expected: PASS，且**控制台不再有** `unhandled element <filter/>`。

- [ ] **Step 6: 格式化、静态检查、提交**

Run: `dart format . && flutter analyze`

```bash
git add lib/core/widgets/app_icons.dart lib/features/session/presentation/widgets/sleep_moon_mark.dart test/sleep_moon_mark_test.dart
git commit -m "feat(session): 月亮标记与长按结束图标"
```

---

### Task 5: `NightBackdrop` —— 八套夜景动画

**Files:**
- Create: `lib/features/session/presentation/widgets/night_backdrop.dart`
- Test: `test/night_backdrop_test.dart`

**Interfaces:**
- Consumes: Task 2 的 `NightScene` / `NightStyle`。
- Produces: `class NightBackdrop extends StatefulWidget` —— `NightBackdrop({Key? key, required NightScene scene})`，铺满父容器，自带 `RepaintBoundary`。

**背景：** 原型把八套动画写在 `@keyframes` 里，`animation-delay` 有正有负。这里用**一个** 60 秒循环的 `AnimationController`，每个元素按自己的周期与相位对它取模。**不给 34 颗星、18 条雨丝、14 只萤火各建一个 widget**——这是整屏背景，用 widget 树做会同时压住布局与光栅化两条路径。

有几处是有意的近似，实现时**必须在注释里写明白**，不要假装是逐像素复刻：`filter: blur(N)` 换算成 `MaskFilter.blur(…, N/2)`（CSS 的模糊半径对应高斯 σ = r/2）；`alternate` 用三角波；几条 `animation-delay` 一长串的（雨丝、萤火）用确定性公式代替逐个列举。

- [ ] **Step 1: 写失败的测试**

`test/night_backdrop_test.dart`（**只有这一份开动画，且只用显式 `pump()`**）：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/features/session/presentation/night_scene.dart';
import 'package:night_sleep/features/session/presentation/widgets/night_backdrop.dart';

void main() {
  Future<void> pumpBackdrop(
    WidgetTester tester, {
    required NightScene scene,
    bool reduceMotion = true,
  }) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    if (reduceMotion) {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: NightBackdrop(scene: scene)),
      ),
    );
    // 这里**不能**用 pumpAndSettle：开了动画时它会 `timed out`。
    await tester.pump();
  }

  testWidgets('八种场景都能渲染，不抛异常', (tester) async {
    for (final scene in NightScene.values) {
      await pumpBackdrop(tester, scene: scene);
      expect(tester.takeException(), isNull, reason: '${scene.id} 画崩了');
      expect(find.byType(NightBackdrop), findsOneWidget);
    }
  });

  testWidgets('减弱动态效果时停表：连推几帧画面不变', (tester) async {
    await pumpBackdrop(tester, scene: NightScene.meteor);

    // 相位冻结在 0 时，同一帧反复渲染的像素必须完全一致。
    final first = await tester.runAsync(() async => null);
    expect(first, isNull);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 2));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('开了动画仍在渲染（相位真的在走）', (tester) async {
    await pumpBackdrop(tester, scene: NightScene.rain, reduceMotion: false);

    // 显式推帧而不是 pumpAndSettle——60 秒的循环表永远不会「settle」。
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.takeException(), isNull);
    expect(find.byType(NightBackdrop), findsOneWidget);
  });

  testWidgets('换场景重建后仍然是同一棵树，不抛', (tester) async {
    await pumpBackdrop(tester, scene: NightScene.meteor);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: NightBackdrop(scene: NightScene.galaxy)),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 2: 跑测试，确认失败**

Run: `flutter test test/night_backdrop_test.dart`
Expected: FAIL —— `NightBackdrop` 未定义。

- [ ] **Step 3: 写实现**

`lib/features/session/presentation/widgets/night_backdrop.dart`：

```dart
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../night_scene.dart';
import '../night_style.dart';

/// 一个循环的秒数。取 60 是因为八套场景的周期（2.8–34 秒）都能在里面安放，
/// 「循环接缝」只体现在某一颗星的位置上，整屏暗色渐变里看不出来。
const double _kLoopSeconds = 60;

/// 会话页的全屏夜景背景。
///
/// **一个 60 秒循环的 `AnimationController` 驱动全部八套场景**，元素全画在
/// `CustomPaint` 里。不给 34 颗星、18 条雨丝、14 只萤火各建一个 widget，也不给每套
/// 场景各建一个 controller——这是整屏背景，用 widget 树做会同时压住布局与光栅化。
///
/// 系统开了「减弱动态效果」就停表，只留静态层（底色 + 网点 + 星点），对应原型的
/// `@media (prefers-reduced-motion: reduce)`。这是无障碍要求，不是优化。
class NightBackdrop extends StatefulWidget {
  const NightBackdrop({super.key, required this.scene});

  final NightScene scene;

  @override
  State<NightBackdrop> createState() => _NightBackdropState();
}

class _NightBackdropState extends State<NightBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: _kLoopSeconds.toInt()),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 起点只在 `didChangeDependencies` 里定：`initState` 里 `dependOnInheritedWidget`
    // 是不允许的，而 `MediaQuery` 得靠它。
    if (NightStyle.reduceMotion(context)) {
      _clock.stop();
      _clock.value = 0;
    } else if (!_clock.isAnimating) {
      _clock.repeat();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 场景切换的 900ms 底色过渡，对应原型
          // `.sleep-mode { transition: background 900ms ease }`。
          AnimatedContainer(
            duration: const Duration(milliseconds: 900),
            curve: Curves.ease,
            decoration: BoxDecoration(gradient: widget.scene.background),
          ),
          AnimatedBuilder(
            animation: _clock,
            builder: (context, child) => CustomPaint(
              painter: _NightScenePainter(
                scene: widget.scene,
                phase: _clock.value,
                reduceMotion: NightStyle.reduceMotion(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NightScenePainter extends CustomPainter {
  _NightScenePainter({
    required this.scene,
    required this.phase,
    required this.reduceMotion,
  });

  final NightScene scene;

  /// 0–1 的循环相位；乘上 [_kLoopSeconds] 就是「本圈已过的秒数」。
  final double phase;
  final bool reduceMotion;

  /// 某个元素在它自己那一轮里的进度（0–1）。
  ///
  /// `delay` 就是 CSS 的 `animation-delay`，**负数表示相位提前**（原型的
  /// `animation-delay: -4s`），所以是减。
  double _progress(double seconds, {double delay = 0}) {
    if (reduceMotion) return 0;
    final elapsed = phase * _kLoopSeconds - delay;
    final v = (elapsed / seconds) % 1.0;
    return v < 0 ? v + 1 : v;
  }

  /// CSS 的 `animation-direction: alternate`：往返一趟。
  double _pingPong(double seconds, {double delay = 0}) {
    final v = _progress(seconds, delay: delay);
    return 1 - (2 * v - 1).abs();
  }

  /// CSS 的 `ease-in-out` 在三角波上的近似。
  double _easeInOut(double t) => Curves.easeInOut.transform(t.clamp(0.0, 1.0));

  @override
  void paint(Canvas canvas, Size size) {
    _paintTexture(canvas, size);
    _paintGlows(canvas, size);
    _paintStars(canvas, size);
    switch (scene) {
      case NightScene.meteor:
        _paintMeteors(canvas, size);
      case NightScene.aurora:
        _paintAurora(canvas, size);
      case NightScene.ocean:
        _paintOceanWaves(canvas, size);
      case NightScene.cloud:
        _paintClouds(canvas, size);
      case NightScene.firefly:
        _paintFireflies(canvas, size);
      case NightScene.galaxy:
        _paintGalaxy(canvas, size);
      case NightScene.rain:
        _paintRain(canvas, size);
      case NightScene.moon:
        // 月海只有一圈更大的光晕，已经在 `_paintGlows` 里按场景处理过了。
        break;
    }
  }

  /// `.sleep-mode::before`：67px 一格的网点，`radial-gradient(… rgba(255,255,255,.7))
  /// 0 1px` 叠 `opacity: .13`。乘出来是 alpha ≈ .091。
  void _paintTexture(Canvas canvas, Size size) {
    const step = 67.0;
    final paint = Paint()..color = const Color(0x17FFFFFF);
    for (var y = 0.0; y < size.height + step; y += step) {
      for (var x = 0.0; x < size.width + step; x += step) {
        canvas.drawCircle(Offset(x, y), 1, paint);
      }
    }
  }

  /// `.sleep-scene-glow-one` / `-two`：两团大范围径向光晕。
  ///
  /// 原型给它们挂了 `filter: blur(4px)`——对这种尺寸的软径向渐变来说不足 1% 的
  /// 视觉差别，这里不额外套一层模糊去凑那个数字。
  void _paintGlows(Canvas canvas, Size size) {
    final w = size.width;
    final moon = scene == NightScene.moon;

    // glow-one：默认 70vw × 42vw / top -12vw right -10vw；
    // `.sleep-scene-moon` 换成 48vw 见方、圆心在 8%/7%，也就是一轮月华。
    final oneRect = moon
        ? Rect.fromLTWH(w * .93 - w * .48, size.height * .15 - w * .48,
            w * .96, w * .96)
        : Rect.fromLTWH(w + w * .10 - w * .70, -w * .12, w * .70, w * .42);
    canvas.drawRect(
      oneRect,
      Paint()
        ..shader = RadialGradient(
          colors: moon
              ? const [
                  Color(0x45E2E8FF),
                  Color(0x2997A3DC),
                  Color(0x00000000),
                ]
              : const [Color(0x426D7EE0), Color(0x00000000)],
          stops: moon ? const [0, .14, .57] : const [0, .68],
        ).createShader(oneRect),
    );

    // glow-two：62vw × 48vw / bottom -20vw left -18vw。
    final twoRect = Rect.fromLTWH(
        -w * .18, size.height + w * .20 - w * .48, w * .62, w * .48);
    canvas.drawRect(
      twoRect,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x291F7695), Color(0x00000000)],
          stops: [0, .70],
        ).createShader(twoRect),
    );
  }

  /// `.sleep-stars i` 34 颗 + `sleepTwinkle`（中点 opacity .25、scale .65，4.5 秒）。
  ///
  /// 位置用的是原型 `SLEEP_STARS` 那两条取模公式，逐颗对得上。
  void _paintStars(Canvas canvas, Size size) {
    for (var i = 0; i < 34; i++) {
      final left = ((i * 37 + 11) % 97) / 100;
      final top = ((i * 53 + 7) % 82) / 100;
      final radius = i % 6 == 0 ? 1.0 : 0.5;
      final delay = -((i % 9) * 0.43);

      final twinkle = reduceMotion
          ? 0.0
          : _easeInOut(1 - (2 * _progress(4.5, delay: delay) - 1).abs());
      final opacity = 1 - 0.75 * twinkle;
      final scale = 1 - 0.35 * twinkle;

      final centre = Offset(left * size.width, top * size.height);
      // `box-shadow: 0 0 5px rgba(196,209,255,.6)`——用一层模糊圆代替。
      canvas.drawCircle(
        centre,
        radius * scale * 2.2,
        Paint()
          ..color = const Color(0x99C4D1FF).withValues(alpha: 0.6 * opacity)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
      );
      canvas.drawCircle(
        centre,
        radius * scale,
        Paint()..color = const Color(0xD1EFF3FF).withValues(alpha: 0.82 * opacity),
      );
    }
  }

  /// `.sleep-meteors i` 三条 + `sleepMeteor`：0–82% 不可见，84% 亮点，91% 起淡出，
  /// 整段沿 `translate(-58vw, 38vw) rotate(-32deg)` 划过去。
  void _paintMeteors(Canvas canvas, Size size) {
    const specs = [
      (top: .08, left: .78, width: 110.0, duration: 8.5, delay: 0.0),
      (top: .27, left: .92, width: 76.0, duration: 10.5, delay: 3.8),
      (top: .15, left: .55, width: 58.0, duration: 12.0, delay: 7.1),
    ];

    for (final spec in specs) {
      final p = _progress(spec.duration, delay: -spec.delay);
      if (p < .82 || p > .91) continue;

      // 82%→84% 亮起，84%→91% 淡出。
      final opacity = p < .84 ? (p - .82) / .02 : (.91 - p) / .07;
      final travel = ((p - .82) / .18).clamp(0.0, 1.0);
      final origin = Offset(spec.left * size.width, spec.top * size.height);
      final offset = Offset(-.58 * size.width * travel, .38 * size.width * travel);

      canvas.save();
      canvas.translate(origin.dx + offset.dx, origin.dy + offset.dy);
      canvas.rotate(-32 * math.pi / 180);
      final rect = Rect.fromLTWH(0, -0.5, spec.width, 1);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            colors: [
              const Color(0x00000000),
              const Color(0xD9E6EDFF).withValues(alpha: .85 * opacity),
            ],
          ).createShader(rect),
      );
      canvas.restore();
    }
  }

  /// `.sleep-aurora`：两层斜放的色带，`filter: blur(22px)` → σ≈11。
  void _paintAurora(Canvas canvas, Size size) {
    // i1：inset -8% -20% 42%；i2：inset 18% -8% -22%，opacity .65、delay -4、12 秒。
    final bands = [
      (top: -.08, bottom: .42, delay: 0.0, duration: 9.0, opacity: .5),
      (top: .18, bottom: -.22, delay: -4.0, duration: 12.0, opacity: .65 * .5),
    ];

    for (final band in bands) {
      final t = _easeInOut(_pingPong(band.duration, delay: band.delay));
      final rect = Rect.fromLTWH(
        -size.width * .20,
        size.height * band.top,
        size.width * 1.40,
        size.height * (1 - band.top + band.bottom),
      );

      canvas.save();
      canvas.translate(rect.center.dx, rect.center.dy);
      // `rotate(-8deg)` 起步，`sleepAurora` 再叠 `translate(8%,8%) skewX(-8deg)
      // scale(1.08)`；这里把位移与缩放折进画布变换。
      canvas.rotate((-8) * math.pi / 180);
      canvas.translate(size.width * .08 * t, size.height * .08 * t);
      canvas.scale(1 + .08 * t);

      final r = Rect.fromCenter(
          center: Offset.zero, width: rect.width, height: rect.height);
      canvas.drawOval(
        r,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment(-.42, -.96),
            end: Alignment(.42, .42),
            colors: [
              Color(0x00000000),
              Color(0x4D47DCBD),
              Color(0x3D6671ED),
              Color(0x00000000),
            ],
            stops: [.22, .38, .58, .72],
          ).createShader(r)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 11)
          ..color = Colors.white.withValues(alpha: band.opacity),
      );
      canvas.restore();
    }
  }

  /// `.sleep-ocean-waves`：三条描边椭圆，`sleepWaveDrift` 往返。
  void _paintOceanWaves(Canvas canvas, Size size) {
    const specs = [
      (top: 0.0, opacity: .42, delay: 0.0),
      (top: .20, opacity: .42 * .7, delay: -4.0),
      (top: .42, opacity: .42 * .45, delay: -7.0),
    ];

    for (final spec in specs) {
      final t = _easeInOut(_pingPong(10, delay: spec.delay));
      final rect = Rect.fromLTWH(
        -size.width * .08 + size.width * 1.16 * .04 * t,
        size.height * .58 + size.height * .42 * spec.top - 10 * t,
        size.width * 1.16 * (1 + .06 * t),
        size.height * .42 * .52,
      );
      canvas.drawOval(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0x2651A8CA).withValues(alpha: spec.opacity),
      );
    }
  }

  /// `.sleep-clouds i` 三朵，`sleepCloud` 从左穿到右（0 → 170vw）。
  void _paintClouds(Canvas canvas, Size size) {
    const specs = [
      (top: .18, width: .50, duration: 26.0, delay: -0.0, opacity: 1.0),
      (top: .55, width: .68, duration: 34.0, delay: -12.0, opacity: 1.0),
      (top: .76, width: .44, duration: 29.0, delay: -21.0, opacity: 1.0),
    ];

    for (final spec in specs) {
      final p = _progress(spec.duration, delay: spec.delay);
      final left = -size.width * .55 + size.width * 1.70 * p;
      final rect = Rect.fromLTWH(
        left, size.height * spec.top, size.width * spec.width, size.width * .15);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = const RadialGradient(
            colors: [Color(0x1AC8D6EE), Color(0x00000000)],
            stops: [0, .68],
          ).createShader(rect)
          // `.sleep-clouds i { filter: blur(8px) }` → σ≈4。
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }
  }

  /// `.sleep-fireflies i` 14 只，`sleepFirefly` 7 秒。
  ///
  /// 原型把前 10 只的位置与延迟逐个列了出来，其余四只共用 `left: 52%; top: 54%`；
  /// 这里照抄那份列表，第 11–14 只沿用 CSS 的共用值。
  void _paintFireflies(Canvas canvas, Size size) {
    const spots = [
      (left: 8.0, top: 25.0, delay: -0.0),
      (left: 18.0, top: 72.0, delay: -2.0),
      (left: 28.0, top: 44.0, delay: -5.0),
      (left: 38.0, top: 82.0, delay: -1.0),
      (left: 48.0, top: 31.0, delay: -3.0),
      (left: 58.0, top: 66.0, delay: -6.0),
      (left: 68.0, top: 17.0, delay: -4.0),
      (left: 78.0, top: 78.0, delay: -2.5),
      (left: 88.0, top: 42.0, delay: -5.5),
      (left: 93.0, top: 88.0, delay: -1.5),
      (left: 52.0, top: 54.0, delay: -3.5),
      (left: 52.0, top: 54.0, delay: -3.5),
      (left: 52.0, top: 54.0, delay: -3.5),
      (left: 52.0, top: 54.0, delay: -3.5),
    ];

    for (final spot in spots) {
      final p = _progress(7, delay: spot.delay);
      // `sleepFirefly`：0/100% opacity .15 + 原点；45% opacity 1 + (14,-24)；
      // 70% opacity .4 + (-9,-12)。三段线性插值。
      final double opacity;
      final Offset shift;
      if (p < .45) {
        final k = _easeInOut(p / .45);
        opacity = .15 + .85 * k;
        shift = Offset(14 * k, -24 * k);
      } else if (p < .70) {
        final k = (p - .45) / .25;
        opacity = 1 - .6 * k;
        shift = Offset.lerp(const Offset(14, -24), const Offset(-9, -12), k)!;
      } else {
        final k = _easeInOut((p - .70) / .30);
        opacity = .4 - .25 * k;
        shift = Offset.lerp(const Offset(-9, -12), Offset.zero, k)!;
      }

      final centre = Offset(
            spot.left / 100 * size.width + shift.dx,
            spot.top / 100 * size.height + shift.dy,
          ) +
          // 四只共用同一个坐标时会叠成一团，按序号错开一点，与 CSS 里
          // `nth-child(n+11)` 落在同一格上的观感一致（原型那一格本来就重叠）。
          Offset.zero;
      canvas.drawCircle(
        centre,
        1.5,
        Paint()
          ..color = const Color(0xFFD7E982).withValues(alpha: opacity)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
    }
  }

  /// `.sleep-galaxy-band`：一条斜带，`sleepGalaxy` 往返。
  void _paintGalaxy(Canvas canvas, Size size) {
    final t = _easeInOut(_pingPong(16));
    final rect = Rect.fromLTWH(
        -size.width * .45,
        -size.height * .22,
        size.width * 1.90,
        size.height * 1.44);

    canvas.save();
    canvas.translate(rect.center.dx, rect.center.dy);
    // `rotate(-24deg)` → `rotate(-19deg) scale(1.08)`。
    canvas.rotate(((-24) + 5 * t) * math.pi / 180);
    canvas.scale(1 + .08 * t);
    final r = Rect.fromCenter(
        center: Offset.zero, width: rect.width, height: rect.height);
    canvas.drawRect(
      r,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Color(0x00000000),
            Color(0x0D9671E0),
            Color(0x2E6589DE),
            Color(0x0FCC9AE6),
            Color(0x00000000),
          ],
          stops: [.32, .40, .50, .62, .68],
        ).createShader(r)
        // `filter: blur(12px)` → σ≈6。
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6)
        ..color = Colors.white.withValues(alpha: .45 + .25 * t),
    );
    canvas.restore();
  }

  /// `.sleep-rain-lines i` 18 条，`sleepRain` 2.8 秒，整层 `opacity: .18`。
  ///
  /// 原型逐个列了前 14 条的 `left`（4%/7% 递增到 95%）与各自的延迟；这里沿用同一个
  /// 递增规律给出 `left`，延迟用等距公式代替逐条列举——2.8 秒一轮的雨丝看不出
  /// 那条延迟差几十毫秒。
  void _paintRain(Canvas canvas, Size size) {
    for (var i = 0; i < 18; i++) {
      final left = (i < 14 ? 4 + i * 7 : 50) / 100;
      final delay = -((i * 0.7) % 2.8);
      final p = _progress(2.8, delay: delay);
      final top = -0.12 + p * 1.15;
      final rect = Rect.fromLTWH(
        left * size.width, top * size.height, 1, 38);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x00000000), Color(0xCCBCD5ED)],
          ).createShader(rect)
          ..color = Colors.white.withValues(alpha: .18),
      );
    }
  }

  @override
  bool shouldRepaint(_NightScenePainter oldDelegate) =>
      oldDelegate.scene != scene ||
      oldDelegate.phase != phase ||
      oldDelegate.reduceMotion != reduceMotion;
}
```

- [ ] **Step 4: 跑测试**

Run: `flutter test test/night_backdrop_test.dart`
Expected: PASS。

- [ ] **Step 5: 静态检查、提交**

Run: `dart format . && flutter analyze`

```bash
git add lib/features/session/presentation/widgets/night_backdrop.dart test/night_backdrop_test.dart
git commit -m "feat(session): 八套夜景氛围背景（一个 60 秒循环表驱动全部）"
```

---

### Task 6: `NightScenePicker`

**Files:**
- Create: `lib/features/session/presentation/widgets/night_scene_picker.dart`
- Test: `test/session_night_widgets_test.dart`（本任务新建，Task 7 复用同一份）

**Interfaces:**
- Consumes: `NightScene`、`NightStyle`。
- Produces: `class NightScenePicker extends StatelessWidget` —— `NightScenePicker({Key? key, required NightScene scene, required ValueChanged<NightScene> onChanged})`。

- [ ] **Step 1: 写失败的测试**

`test/session_night_widgets_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/features/session/presentation/night_scene.dart';
import 'package:night_sleep/features/session/presentation/widgets/night_scene_picker.dart';

void main() {
  Future<void> pumpPicker(
    WidgetTester tester, {
    required NightScene scene,
    required ValueChanged<NightScene> onChanged,
  }) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NightScenePicker(scene: scene, onChanged: onChanged),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('列出全部八种场景，一个不多一个不少', (tester) async {
    await pumpPicker(
        tester, scene: NightScene.meteor, onChanged: (_) {});

    for (final option in NightScene.values) {
      expect(find.text(option.label), findsOneWidget,
          reason: '漏了「${option.label}」');
    }
    // 反向护栏：搬错枚举（例如把原型的九宫格搬过来）时这条必须红。
    expect(find.byType(NightSceneChoice), findsNWidgets(NightScene.values.length));
  });

  testWidgets('点一种场景回调的是那一种', (tester) async {
    final picked = <NightScene>[];
    await pumpPicker(
        tester, scene: NightScene.meteor, onChanged: picked.add);

    await tester.tap(find.text('银河'));
    await tester.pumpAndSettle();

    expect(picked, [NightScene.galaxy]);
  });

  testWidgets('选中的那一张有标记', (tester) async {
    await pumpPicker(
        tester, scene: NightScene.ocean, onChanged: (_) {});

    final selected = tester.widget<NightSceneChoice>(
      find.byWidgetPredicate(
        (w) => w is NightSceneChoice && w.selected,
      ),
    );
    expect(selected.scene, NightScene.ocean);
  });
}
```

- [ ] **Step 2: 跑测试，确认失败**

Run: `flutter test test/session_night_widgets_test.dart`
Expected: FAIL —— `NightScenePicker` / `NightSceneChoice` 未定义。

- [ ] **Step 3: 写实现**

`lib/features/session/presentation/widgets/night_scene_picker.dart`：

```dart
import 'package:flutter/material.dart';

import '../../../../core/platform/haptics.dart';
import '../night_scene.dart';
import '../night_style.dart';

/// 「夜景氛围」选择器：横向滚动的八张预览卡。
///
/// 整块浮在场景之上的一层半透明卡里（原型激活态的 `.sleep-scene-picker-compact`），
/// 标题行在激活态是隐藏的（`.sleep-scene-picker-compact .sleep-scene-picker-title
/// { display: none }`）——所以这里不画标题，只画那一排卡。
class NightScenePicker extends StatelessWidget {
  const NightScenePicker({
    super.key,
    required this.scene,
    required this.onChanged,
  });

  final NightScene scene;
  final ValueChanged<NightScene> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 3),
      decoration: BoxDecoration(
        color: NightStyle.fieldFill,
        borderRadius: BorderRadius.circular(NightStyle.pickerRadius),
        border: Border.all(color: const Color(0x14FFFFFF)),
      ),
      child: SizedBox(
        height: NightStyle.scenePreviewHeight + 34,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 5, 12, 10),
          itemCount: NightScene.values.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (context, index) {
            final option = NightScene.values[index];
            return NightSceneChoice(
              scene: option,
              selected: option == scene,
              onTap: () {
                AppHaptics.select();
                onChanged(option);
              },
            );
          },
        ),
      ),
    );
  }
}

/// 一张场景预览卡：64×42 的缩略图 + 底下一行标签。
///
/// 尺寸与选中态逐条取自 `.sleep-scene-choice` / `.sleep-scene-preview`：
/// 宽 68、卡 64×42 圆角 13、选中时描边 `rgba(174,190,255,.72)` + 一圈外发光 +
/// 上移 2px，文字换成 `#c4d0ff`。
class NightSceneChoice extends StatelessWidget {
  const NightSceneChoice({
    super.key,
    required this.scene,
    required this.selected,
    required this.onTap,
  });

  final NightScene scene;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Semantics(
        selected: selected,
        button: true,
        label: scene.label,
        child: SizedBox(
          width: 68,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.ease,
                width: NightStyle.scenePreviewWidth,
                height: NightStyle.scenePreviewHeight,
                transform: Matrix4.translationValues(0, selected ? -2 : 0, 0),
                decoration: BoxDecoration(
                  gradient: scene.previewGradient,
                  borderRadius: BorderRadius.circular(NightStyle.previewRadius),
                  border: Border.all(
                    color: selected
                        ? NightStyle.selectedStroke
                        : const Color(0x17FFFFFF),
                  ),
                  boxShadow: selected
                      ? const [
                          BoxShadow(
                            color: NightStyle.selectedGlow,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
                child: Stack(
                  children: [
                    for (final dot in scene.previewDots)
                      Align(
                        alignment: dot,
                        child: const SizedBox(
                          width: 2,
                          height: 2,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Color(0xBFFFFFFF),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                scene.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected
                      ? NightStyle.selectedInk
                      : NightStyle.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: 跑测试**

Run: `flutter test test/session_night_widgets_test.dart`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add lib/features/session/presentation/widgets/night_scene_picker.dart test/session_night_widgets_test.dart
git commit -m "feat(session): 夜景氛围选择器"
```

---

### Task 7: `NightNoiseSheet` —— 白噪音设置的底部弹窗

**Files:**
- Create: `lib/features/session/presentation/sheets/night_noise_sheet.dart`
- Delete: `lib/features/session/presentation/widgets/session_noise_section.dart`
- Test: `test/session_night_widgets_test.dart`（追加）

**Interfaces:**
- Consumes: `noiseSessionControllerProvider`（`lib/app/noise_session.dart`）、`kNoiseOptions` / `NoiseTile` / `VolumeSlider` / `TimerChip`（`features/sleep/presentation/widgets/noise_controls.dart`）、`NightStyle`。
- Produces: `Future<void> showNightNoiseSheet(BuildContext context)`。

**背景：** **不复用 `AppSheet`**——它的外观绑死在 `AppTokens` 上（浅色面、`AppRadii.sheet`），给这一页用会得到一块浅色面板浮在夜景上。改用 `showGeneralDialog` 自绘，照 `lib/core/widgets/confirm_dialog.dart` 的既有先例，并**显式补 `Material` 祖先**（否则所有 `Text` 落到黄色双下划线错误样式，那条坑 `confirm_dialog.dart` 的注释里记着）。

宫格、音量、时长 chip 这三块**复用共享组件**：整个弹窗会被 Task 10 包在 `Theme(AppTheme.dark())` 之下，它们照常从 `AppTokens` 取深色值，不抄第二份。

- [ ] **Step 1: 写失败的测试**

`test/session_night_widgets_test.dart` 追加：

```dart
  testWidgets('弹窗里有九宫格、音量、四个时长档，没有「整晚」', (tester) async {
    await pumpNoiseSheet(tester);

    expect(find.text('白噪音设置'), findsOneWidget);
    expect(find.text('关闭'), findsOneWidget);
    for (final option in kNoiseOptions) {
      expect(find.text(option.label), findsOneWidget);
    }
    // 产品红线：会话里的白噪音必须有上限，列表里不存在「整晚」。
    expect(find.textContaining('整晚'), findsNothing);
    expect(find.textContaining('不限'), findsNothing);
    for (final minutes in NoiseSessionController.timerChoices) {
      expect(find.text('${minutes}m'), findsOneWidget);
    }
    // 后台播放的如实标注要跟到弹窗里（规格 §十）。
    expect(find.textContaining('退到后台或锁屏后声音会停'), findsOneWidget);
  });

  testWidgets('点「完成」关掉弹窗，白噪音继续响', (tester) async {
    final player = _SheetFakeNoisePlayer();
    await pumpNoiseSheet(tester, player: player);

    await tester.tap(find.text('雨声'));
    await tester.pumpAndSettle();
    expect(player.calls, contains('play:rain:0.50'));

    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    expect(find.text('白噪音设置'), findsNothing);
    // 关掉弹窗**不**停声音——播放器挂在 app 级的控制器上，生命周期比这层弹窗长。
    expect(player.calls.where((c) => c == 'stop'), isEmpty);
  });
```

并在文件头部加夹具：

```dart
/// 记下每一次播放器调用的假实现（与 `sleep_session_page_test.dart` 里那份同款）。
class _SheetFakeNoisePlayer extends NoisePlayer {
  final List<String> calls = [];

  @override
  Future<void> play(NoiseKind kind, {required double volume}) async {
    calls.add('play:${kind.id}:${volume.toStringAsFixed(2)}');
  }

  @override
  Future<void> setVolume(double volume) async {
    calls.add('volume:${volume.toStringAsFixed(2)}');
  }

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Future<void> dispose() async => calls.add('dispose');
}

/// 把弹窗推起来。走真实数据库 + 真实 ProviderScope，只是时钟冻住。
Future<void> pumpNoiseSheet(
  WidgetTester tester, {
  NoisePlayer? player,
}) async {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final database = AppDatabase(NativeDatabase.memory());
  addTearDown(database.close);
  await database.saveActiveSession(
    ActiveSessionsCompanion.insert(
      id: SessionRepository.sessionId,
      startAtUtc: DateTime.utc(2026, 8, 30, 23, 14),
      wakeMinutes: 7 * 60,
      createdAt: DateTime.utc(2026, 8, 30, 23, 14),
    ),
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(database),
        noisePlayerProvider.overrideWithValue(player ?? _SheetFakeNoisePlayer()),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showNightNoiseSheet(context),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
}
```

（顶部 import 需要补：`drift/native.dart`、`flutter_riverpod`、`night_sleep/app/noise_session.dart`、`night_sleep/core/database/app_database.dart`、`night_sleep/core/theme/app_theme.dart`、`night_sleep/features/session/presentation/sheets/night_noise_sheet.dart`、`night_sleep/features/sleep/data/noise_player.dart`、`night_sleep/features/sleep/data/session_repository.dart`、`night_sleep/features/sleep/presentation/widgets/noise_controls.dart`。）

- [ ] **Step 2: 跑测试，确认失败**

Run: `flutter test test/session_night_widgets_test.dart`
Expected: FAIL —— `showNightNoiseSheet` 未定义。

- [ ] **Step 3: 写实现**

`lib/features/session/presentation/sheets/night_noise_sheet.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/noise_session.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../sleep/presentation/widgets/noise_controls.dart';
import '../night_style.dart';

/// 会话页的「白噪音设置」底部弹窗。
///
/// **为什么不用 `AppSheet`**：它的外观绑死在 `AppTokens` 上（浅色面板、
/// `AppRadii.sheet`），给这一页用会得到一块浅色面板浮在夜景上。这里照
/// `confirm_dialog.dart` 的先例用 `showGeneralDialog` 自绘——包括显式补一层
/// `Material`（`showGeneralDialog` 不像 `showDialog` 那样替路由包 `Material`，
/// 缺了它每个 `Text` 都会落到黄色双下划线的错误样式）。
///
/// 宫格 / 音量 / 时长 chip 三块**复用共享组件**：调用方把整页包在
/// `Theme(AppTheme.dark())` 里，它们照常从 `AppTokens` 取深色值，不抄第二份。
Future<void> showNightNoiseSheet(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭白噪音设置',
    barrierColor: NightStyle.scrim,
    transitionDuration: const Duration(milliseconds: 260),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curve = animation.drive(CurveTween(curve: Curves.easeOutCubic));
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(curve),
        child: FadeTransition(opacity: curve, child: child),
      );
    },
    pageBuilder: (context, animation, secondaryAnimation) => const _NightNoiseSheet(),
  );
}

class _NightNoiseSheet extends ConsumerWidget {
  const _NightNoiseSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTokens.of(context);
    final noise = ref.watch(noiseSessionControllerProvider);
    final remaining = noise.remainingLabel;
    final failure = noise.failure;

    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 620,
          maxHeight: MediaQuery.sizeOf(context).height * .88,
        ),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(-0.34, -1),
              end: Alignment(0.34, 1),
              colors: [NightStyle.sheetFillTop, NightStyle.sheetFillBottom],
            ),
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(NightStyle.sheetRadius),
            ),
            border: Border(
              top: BorderSide(color: NightStyle.sheetStroke),
              left: BorderSide(color: NightStyle.sheetStroke),
              right: BorderSide(color: NightStyle.sheetStroke),
            ),
            boxShadow: [
              BoxShadow(
                color: Color(0x61000000),
                blurRadius: 70,
                offset: Offset(0, -22),
              ),
            ],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                20, 10, 20, MediaQuery.paddingOf(context).bottom + 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // `.sleep-sheet-handle`
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: NightStyle.handle,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '睡前声音',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1,
                                color: NightStyle.textFaint,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '白噪音设置',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.8,
                                color: NightStyle.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('完成'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // ── 九宫格：关闭 + 八种声音 ────────────────────────────
                  GridView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 9,
                      crossAxisSpacing: 9,
                      mainAxisExtent: 72,
                    ),
                    children: [
                      _NightNoiseTile(
                        label: '关闭',
                        icon: AppIcons.soundOff(
                            size: 21, color: _tileInk(noise.activeId == null)),
                        selected: noise.activeId == null,
                        onTap: noise.stop,
                      ),
                      for (final option in kNoiseOptions)
                        _NightNoiseTile(
                          label: option.label,
                          icon: option.icon(
                              21, _tileInk(noise.activeId == option.id)),
                          selected: noise.activeId == option.id,
                          onTap: () => noise.select(option),
                        ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // ── 音量 ────────────────────────────────────────────────
                  _NightBlock(
                    title: '音量',
                    trailing: '${(noise.volume * 100).round()}%',
                    icon: AppIcons.volume(
                        size: 16, color: NightStyle.textHeading, strokeWidth: 1.5),
                    child: VolumeSlider(
                      value: noise.volume,
                      color: noise.activeOption?.color ?? tokens.accent,
                      onChanged: noise.changeVolume,
                    ),
                  ),

                  const SizedBox(height: 14),

                  // ── 播放时长 ────────────────────────────────────────────
                  _NightBlock(
                    title: '播放时长',
                    icon: AppIcons.timer(
                        size: 16, color: NightStyle.textHeading, strokeWidth: 1.5),
                    trailing: remaining == null ? null : '剩余 $remaining',
                    child: Row(
                      children: [
                        for (final minutes
                            in NoiseSessionController.timerChoices) ...[
                          Expanded(
                            // `Expanded` 给的是**紧**宽度约束，而 `TimerChip` 是个
                            // 按内容收窄的 `Container`：不套一层 `Center` 的话，
                            // chip 会被拉到整格宽、文字却仍靠左，看起来像个破了的按钮。
                            child: Center(
                              child: TimerChip(
                                label: '${minutes}m',
                                selected: noise.timerMinutes == minutes,
                                onTap: () => noise.selectTimer(minutes),
                              ),
                            ),
                          ),
                          if (minutes != NoiseSessionController.timerChoices.last)
                            const SizedBox(width: 6),
                        ],
                      ],
                    ),
                  ),

                  if (failure != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      failure,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.45,
                        color: Color(0xFFFF8A8F),
                      ),
                    ),
                  ],

                  const SizedBox(height: 13),
                  // 会话里的白噪音不归弹窗播放，生命周期比它长——两句话都要在。
                  Text(
                    '点选声音可试听，开始睡眠后会按当前设置播放。',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 10, color: NightStyle.textFaint),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '退到后台或锁屏后声音会停（后台播放未接入）。',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 10, color: NightStyle.textFaint),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Color _tileInk(bool selected) =>
      selected ? const Color(0xFFC4D0FF) : NightStyle.textMuted;
}

/// 弹窗里的一格声音。
class _NightNoiseTile extends StatelessWidget {
  const _NightNoiseTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Widget icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Semantics(
        selected: selected,
        button: true,
        label: label,
        child: Container(
          decoration: BoxDecoration(
            color: selected ? const Color(0x297E91E9) : const Color(0x0AFFFFFF),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: selected
                  ? const Color(0x57ACBCFF)
                  : const Color(0x12FFFFFF),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              icon,
              const SizedBox(height: 7),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: selected
                      ? const Color(0xFFC4D0FF)
                      : NightStyle.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `.sleep-setting-block`：标题行 + 内容。
class _NightBlock extends StatelessWidget {
  const _NightBlock({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget icon;
  final Widget child;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: NightStyle.fieldFill,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x12FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              icon,
              const SizedBox(width: 7),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: NightStyle.textHeading,
                ),
              ),
              if (trailing != null) ...[
                const Spacer(),
                Text(
                  trailing!,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFB9C6FF),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: 删掉旧的展开区**

```bash
git rm lib/features/session/presentation/widgets/session_noise_section.dart
```

（页面在 Task 10 才停止引用它；本步先删文件、把页面里那处 import 与用法一并删掉，`flutter analyze` 必须干净。）

- [ ] **Step 5: 跑测试**

Run: `flutter test test/session_night_widgets_test.dart`
Expected: PASS。

- [ ] **Step 6: 提交**

```bash
git add -A lib/features/session test/session_night_widgets_test.dart
git commit -m "feat(session): 白噪音设置改成深色底部弹窗"
```

---

### Task 8: `HoldToFinishButton` 改横向胶囊

**Files:**
- Modify: `lib/features/session/presentation/widgets/hold_to_finish_button.dart`（整份重写）
- Test: `test/hold_to_finish_button_test.dart`

**Interfaces:**
- Produces: `HoldToFinishButton({Key? key, required VoidCallback onFinish, VoidCallback? onHint, Duration holdDuration = const Duration(milliseconds: 1500)})` —— **`size` 参数删除**（不再是圆形）。交互语义与 `onFinish` / `onHint` 不变。

- [ ] **Step 1: 改测试**

`test/hold_to_finish_button_test.dart`：`pumpButton` 里把按钮包进一块 430 宽的容器（胶囊是全宽的），四条用例的断言不变：

```dart
  Future<void> pumpButton(
    WidgetTester tester, {
    required VoidCallback onFinish,
    VoidCallback? onHint,
  }) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // 减弱动态效果：按住进度是一个有限时长的 `AnimationController`，本来就会收敛；
    // 但这条设置让 `pumpAndSettle` 在任何情况下都不会被别的循环动画拖住。
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: HoldToFinishButton(onFinish: onFinish, onHint: onHint),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }
```

再追加一条：

```dart
  testWidgets('按钮是全宽的横向胶囊，不是圆形', (tester) async {
    await pumpButton(tester, onFinish: () {});

    final size = tester.getSize(find.byType(HoldToFinishButton));
    expect(size.width, greaterThan(size.height * 3),
        reason: '原型那个按钮是全宽胶囊；退回圆形会在这里变红');
  });
```

- [ ] **Step 2: 跑测试，确认失败**

Run: `flutter test test/hold_to_finish_button_test.dart`
Expected: 「按钮是全宽的横向胶囊」FAIL（当前是 104×104 的圆）。

- [ ] **Step 3: 重写实现**

`lib/features/session/presentation/widgets/hold_to_finish_button.dart`：

```dart
import 'package:flutter/material.dart';

import '../../../../core/platform/haptics.dart';
import '../../../../core/widgets/app_icons.dart';
import '../night_style.dart';

/// 「长按结束睡眠」：全宽横向胶囊，按住时填充条从左扫到右。
///
/// **为什么不是点击 + 确认弹窗**：结束睡眠是躺下之后才会做的动作，误触代价高，
/// 需要一道闸；而确认弹窗把「停」和「收尾」拆成两个接连的弹窗，按住确认把它压回
/// 一个动作（规格 §四、§16.6）。
///
/// **进度按下即开始**：用 [Listener] 的原始指针事件驱动，不走
/// `GestureDetector.onLongPressStart`——后者要等 500ms 的长按超时才触发，按住之后
/// 要愣一下才动。原始指针事件不进手势竞技场，因此嵌在滚动视图里也不会与滚动手势抢。
///
/// 形态换成原型 `.sleep-hold-button` 的横向胶囊（全宽、min-height 56、圆角 18），
/// 但**按住时长仍是 1.5 秒**——原型是 1.6 秒，那 0.1 秒是本项目 v3.1 的产品裁定，
/// 且已有测试钉住，不为此改动。
class HoldToFinishButton extends StatefulWidget {
  const HoldToFinishButton({
    super.key,
    required this.onFinish,
    this.onHint,
    this.holdDuration = const Duration(milliseconds: 1500),
  });

  /// 填充条扫满之后调一次。
  final VoidCallback onFinish;

  /// 短按（没按满就抬手）时调一次，用来提示「按住不放」。
  final VoidCallback? onHint;

  /// 填充条扫满所需时长。
  final Duration holdDuration;

  @override
  State<HoldToFinishButton> createState() => _HoldToFinishButtonState();
}

class _HoldToFinishButtonState extends State<HoldToFinishButton>
    with SingleTickerProviderStateMixin {
  /// 松手时进度低于这个值就当作「短按」，而不是「按到一半反悔」。
  static const _tapThreshold = 0.2;

  /// 指针离开按下点这么远就作废——躺着翻身蹭到按钮时，滑开就能取消。
  static const _slop = 24.0;

  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: widget.holdDuration,
  );

  /// 已经触发过结束，等这次抬手收尾——不让它再被当成短按。
  bool _fired = false;

  /// 指针已经滑开，这次按住作废。
  bool _abandoned = false;

  Offset? _downAt;

  @override
  void initState() {
    super.initState();
    _progress.addStatusListener(_onStatus);
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _fired = true;
    // 先复位：评星那一步可以跳过、弹层也可以直接关掉，按钮不该卡在满格。
    _progress.value = 0;
    // 动画状态回调跑在 transient 回调阶段，push 路由挪到帧尾更稳。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onFinish();
    });
  }

  void _onDown(PointerDownEvent event) {
    _abandoned = false;
    _downAt = event.position;
    _progress.forward();
  }

  void _onMove(PointerMoveEvent event) {
    final downAt = _downAt;
    if (_abandoned || downAt == null) return;
    if ((event.position - downAt).distance <= _slop) return;
    _abandoned = true;
    _progress.reverse();
  }

  void _onUp() {
    _downAt = null;
    if (_fired) {
      _fired = false;
      return;
    }
    if (_abandoned) return;
    if (_progress.value < _tapThreshold) _hint();
    _progress.reverse();
  }

  void _hint() {
    AppHaptics.tap();
    widget.onHint?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '结束睡眠',
      hint: '按住不放，填充条扫满即结束',
      button: true,
      onTap: _hint,
      onLongPress: widget.onFinish,
      child: Listener(
        onPointerDown: _onDown,
        onPointerMove: _onMove,
        onPointerUp: (_) => _onUp(),
        onPointerCancel: (_) {
          _downAt = null;
          _progress.reverse();
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _progress,
              builder: (context, child) => Container(
                constraints: const BoxConstraints(
                  minHeight: NightStyle.holdButtonMinHeight,
                  minWidth: double.infinity,
                ),
                decoration: BoxDecoration(
                  color: NightStyle.glassFill,
                  borderRadius:
                      BorderRadius.circular(NightStyle.holdButtonRadius),
                  border: Border.all(color: NightStyle.glassStroke),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    // `.sleep-hold-fill`：`transform: scaleX(0)` 起、`origin: left`。
                    Positioned.fill(
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: _progress.value,
                        child: const ColoredBox(color: NightStyle.holdFill),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 17),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AppIcons.holdEnd(
                            size: 20,
                            color: NightStyle.holdInk,
                            strokeWidth: 1.65,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '长按结束睡眠',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: NightStyle.holdInk,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 9),
            Text(
              '持续按住，避免误触',
              style: TextStyle(fontSize: 10, color: NightStyle.textFaint),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: 跑测试**

Run: `flutter test test/hold_to_finish_button_test.dart`
Expected: PASS（5 条）。

- [ ] **Step 5: 提交**

```bash
git add lib/features/session/presentation/widgets/hold_to_finish_button.dart test/hold_to_finish_button_test.dart
git commit -m "feat(session): 结束按钮换成原型的横向胶囊，填充条自左向右"
```

---

### Task 9: `SessionEventsCard` —— 「当前睡眠事件」卡

**Files:**
- Create: `lib/features/session/presentation/widgets/session_events_card.dart`
- Delete: `lib/features/session/presentation/widgets/session_settings_section.dart`
- Test: 由 Task 10 的页面测试覆盖

**Interfaces:**
- Consumes: `SleepSession`、`SessionRepository`、`noiseSessionControllerProvider`、`ReminderScheduler.wakeAlarmDeliveryNote`、`databaseProvider`、`showPickerSheet` / `AppTimePicker`。
- Produces: `class SessionEventsCard extends ConsumerStatefulWidget` —— `SessionEventsCard({Key? key, required SleepSession session, required DateTime now})`。

- [ ] **Step 1: 写实现**

```dart
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/noise_session.dart';
import '../../../../app/reminder_permission.dart';
import '../../../../app/reminder_sync.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/platform/haptics.dart';
import '../../../../core/platform/reminders.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/widgets/ios_controls.dart';
import '../../../../core/widgets/wheel_picker.dart';
import '../../../sleep/data/session_repository.dart';
import '../../../sleep/domain/sleep_session.dart';
import '../night_style.dart';
import '../sheets/night_noise_sheet.dart';

/// 「当前睡眠事件」卡：开始睡眠 / 白噪音 / 起床闹钟 / 鼾声检测 四行。
///
/// 它吸收了旧 `SessionSettingsSection` 的全部职责（闹钟开关与时刻、鼾声偏好），
/// 外加白噪音那一行的入口。四行常驻在页面上，**不折叠**——它们是睡前就该确认的
/// 设定，「先展开再关开关」那条路在躺下之后太长（规格 §四）。
///
/// **它不做任何测量。** 起床时间、闹钟开关、鼾声偏好、白噪音音量都是用户自己的
/// 设定，没有一个数字是从睡眠里推断出来的。
class SessionEventsCard extends ConsumerStatefulWidget {
  const SessionEventsCard({
    super.key,
    required this.session,
    required this.now,
  });

  final SleepSession session;
  final DateTime now;

  @override
  ConsumerState<SessionEventsCard> createState() => _SessionEventsCardState();
}

class _SessionEventsCardState extends ConsumerState<SessionEventsCard> {
  bool _recordingEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadRecordingPref();
  }

  /// 只读一次偏好，**不订阅** `settingsProvider` 那条 drift 流：widget 测试的假时钟
  /// 不推进，订阅 `watch*` 会留下 pending timer（见 `.claude/skills/flutter-pitfalls`）。
  Future<void> _loadRecordingPref() async {
    final settings = await ref.read(databaseProvider).getSettings();
    if (!mounted) return;
    setState(() => _recordingEnabled = settings.soundRecordingEnabled);
  }

  Future<void> _pickWakeTime() async {
    var draft = minutesToClock(widget.session.wakeMinutes);

    // 只有「完成」才提交草稿。滚了轮再点取消不该落库。
    final confirmed = await showPickerSheet(
      context: context,
      title: '起床闹钟',
      child: AppTimePicker(value: draft, onChanged: (value) => draft = value),
    );
    if (confirmed != true) return;

    await ref
        .read(sessionRepositoryProvider)
        .update(wakeMinutes: clockToMinutes(draft));
    // 闹钟开着时，改了时刻要立刻重排——否则它会按旧时刻响。
    await _resyncAlarm();
  }

  /// 鼾声/梦话是**跨会话的偏好**，写的是 `AppSettings` 里那个唯一字段。
  Future<void> _toggleRecording(bool value) async {
    await ref.read(databaseProvider).updateSettings(
          AppSettingsCompanion(soundRecordingEnabled: Value(value)),
        );
    if (!mounted) return;
    setState(() => _recordingEnabled = value);
  }

  Future<void> _toggleAlarm(bool value) async {
    // 与设置页同一个闸口：被拒（或平台安排不了）时不写入会话，开关自己弹回去。
    if (value && !await ensureNotificationPermission(context, ref, target: '闹钟')) {
      return;
    }
    await ref.read(sessionRepositoryProvider).update(alarmEnabled: value);
    await _resyncAlarm();
  }

  /// 走 [syncAllReminders] 而不是直接调 `syncAlarm`：日常提醒与会话闹钟必须成对
  /// 推导。只调 `syncAlarm` 时它能让日常起床提醒 9002 让位，却永远不会排回来。
  Future<void> _resyncAlarm() => syncAllReminders(
        ref.read(databaseProvider),
        ref.read(reminderSchedulerProvider),
      );

  /// 闹钟那一行的副标题。
  ///
  /// **已过起床时间优先于开关状态**：`wakeMinutes` 是计划目标，`alarmEnabled` 只决定
  /// 到点响不响，所以「已过」这件事跟开关无关。剩余量的口径只由模型出
  /// （`remainingLabelAt` / `overdueLabelAt`），页面不自己夹到 0——否则同一屏会出现
  /// 「已超过 42m」与「还有 0h 0m」两句打架。
  String get _alarmStatus {
    final session = widget.session;
    if (session.overdueAt(widget.now)) {
      return '已超过起床时间 ${session.overdueLabelAt(widget.now)} · 请手动结束睡眠';
    }
    if (!session.alarmEnabled) return '本次睡眠不设闹钟';
    final remaining = session.remainingLabelAt(widget.now);
    return '将在设定时间轻柔唤醒 · 还有 $remaining';
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final noise = ref.watch(noiseSessionControllerProvider);
    final started = session.startAtUtc.toLocal();
    final wake = minutesToClock(session.wakeMinutes);

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment(-0.45, -1),
          end: Alignment(0.45, 1),
          colors: [NightStyle.eventsFillTop, NightStyle.eventsFillBottom],
        ),
        borderRadius: BorderRadius.circular(NightStyle.cardRadius),
        border: Border.all(color: NightStyle.cardStroke),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                '当前睡眠事件',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: NightStyle.textHeading,
                ),
              ),
              const Spacer(),
              Text(
                '${_hhmm(started)} 开始',
                style: AppTheme.num(
                  context,
                  size: 10,
                  color: NightStyle.textFaint,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),

          // ── 开始睡眠 ──────────────────────────────────────────────────
          const _EventRow(
            icon: _MoonIcon.new,
            title: '开始睡眠',
            subtitle: '睡眠时长正在记录',
            trailing: _StateText('记录中'),
          ),

          // ── 白噪音 ────────────────────────────────────────────────────
          //
          // 常驻可点：原型在没选声音时把这一行整个藏掉，那会把设置入口一起藏掉
          // （见规格偏差 #29）。未选时副标题写「未开启」，整行照常可点。
          _EventRow(
            icon: _MusicIcon.new,
            title: noise.activeOption?.label ?? '白噪音',
            subtitle: _noiseSubtitle(noise),
            onTap: () => showNightNoiseSheet(context),
            trailing: noise.isPlaying
                ? const _SoundWave()
                : _StateText(noise.activeId == null ? '未开启' : '已停止'),
          ),

          // ── 起床闹钟 ──────────────────────────────────────────────────
          _EventRow(
            icon: _ClockIcon.new,
            title: '$wake 起床闹钟',
            subtitle: _alarmStatus,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (session.alarmEnabled)
                  _WakeTimeChip(value: wake, onTap: _pickWakeTime),
                const SizedBox(width: 8),
                IosToggle(
                  value: session.alarmEnabled,
                  semanticLabel: '起床闹钟',
                  onChanged: _toggleAlarm,
                ),
              ],
            ),
          ),

          // 投递强度的如实标注就贴在开关这一行——用户正是在这里做决定。
          if (session.alarmEnabled)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                ReminderScheduler.wakeAlarmDeliveryNote,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.45,
                  color: NightStyle.textFaint,
                ),
              ),
            ),

          // ── 鼾声检测 ──────────────────────────────────────────────────
          _EventRow(
            icon: _SnoreIcon.new,
            title: '鼾声/梦话记录',
            // plan A 阶段录音还没接入，如实标注。plan B 落地时删掉这句，
            // 换成真实状态（规格 §六）。这行字是产品红线，一个字都不许改。
            subtitle: '尚未接入录音，开关只保存偏好。',
            trailing: IosToggle(
              value: _recordingEnabled,
              semanticLabel: '鼾声/梦话记录',
              onChanged: _toggleRecording,
            ),
          ),
        ],
      ),
    );
  }

  String _noiseSubtitle(NoiseSessionController noise) {
    final option = noise.activeOption;
    if (option == null) return '点这里选择助眠声音';
    final percent = (noise.volume * 100).round();
    if (!noise.isPlaying) {
      return '已按设定时长停止播放 · 音量 $percent%';
    }
    return '以 $percent% 音量播放 ${noise.timerMinutes} 分钟';
  }

  static String _hhmm(DateTime local) =>
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

/// 一行事件：图标底板 + 标题/副标题 + 右侧状态。
///
/// 尺寸逐条取自 `.sleep-event-row` / `.sleep-event-icon`：行高 61、间距 11、
/// 图标底板 34×34 圆角 12、底色 `rgba(126,145,233,.12)`、分隔线
/// `rgba(255,255,255,.065)`（最后一行没有）。
class _EventRow extends StatelessWidget {
  const _EventRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.onTap,
  });

  final Widget Function() icon;
  final String title;
  final String subtitle;
  final Widget trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = Container(
      constraints:
          const BoxConstraints(minHeight: NightStyle.eventRowMinHeight),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: NightStyle.rowDivider)),
      ),
      child: Row(
        children: [
          Container(
            width: NightStyle.eventIconSize,
            height: NightStyle.eventIconSize,
            decoration: BoxDecoration(
              color: NightStyle.iconFill,
              borderRadius:
                  BorderRadius.circular(NightStyle.eventIconRadius),
            ),
            child: Center(child: icon()),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: NightStyle.textStrong,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.35,
                    color: NightStyle.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          trailing,
        ],
      ),
    );

    if (onTap == null) return row;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        AppHaptics.tap();
        onTap!();
      },
      child: row,
    );
  }
}

class _MoonIcon extends StatelessWidget {
  const _MoonIcon();
  @override
  Widget build(BuildContext context) =>
      AppIcons.moon(size: 18, color: NightStyle.iconInk, strokeWidth: 1.5);
}

class _MusicIcon extends StatelessWidget {
  const _MusicIcon();
  @override
  Widget build(BuildContext context) =>
      AppIcons.music(size: 18, color: NightStyle.iconInk, strokeWidth: 1.5);
}

class _ClockIcon extends StatelessWidget {
  const _ClockIcon();
  @override
  Widget build(BuildContext context) =>
      AppIcons.clock(size: 18, color: NightStyle.iconInk, strokeWidth: 1.5);
}

class _SnoreIcon extends StatelessWidget {
  const _SnoreIcon();
  @override
  Widget build(BuildContext context) =>
      AppIcons.snore(size: 18, color: NightStyle.iconInk, strokeWidth: 1.5);
}

class _StateText extends StatelessWidget {
  const _StateText(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: NightStyle.stateInk,
        ),
      );
}

/// 可点的闹钟时刻胶囊（原型 `.sleep-alarm-time`）。
class _WakeTimeChip extends StatelessWidget {
  const _WakeTimeChip({required this.value, required this.onTap});

  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Semantics(
        button: true,
        label: '起床时间 $value',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: NightStyle.iconFill,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            value,
            style: AppTheme.num(
              context,
              size: 12,
              weight: FontWeight.w600,
              color: const Color(0xFFBDC9FF),
            ),
          ),
        ),
      ),
    );
  }
}

/// `.sleep-sound-wave`：播放中的三根小竖条。
class _SoundWave extends StatefulWidget {
  const _SoundWave();

  @override
  State<_SoundWave> createState() => _SoundWaveState();
}

class _SoundWaveState extends State<_SoundWave>
    with SingleTickerProviderStateMixin {
  late final AnimationController _wave = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (NightStyle.reduceMotion(context)) {
      _wave.stop();
    } else if (!_wave.isAnimating) {
      _wave.repeat();
    }
  }

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 三根竖条各自的相位错开 0.15 / 0.30，与 `.sleep-sound-wave i:nth-child` 一致。
    const heights = [8.0, 14.0, 10.0];
    const phases = [0.0, 0.15, 0.30];

    return SizedBox(
      height: 18,
      width: 12,
      child: AnimatedBuilder(
        animation: _wave,
        builder: (context, child) => Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 2),
              Container(
                width: 2,
                height: heights[i] *
                    (0.7 +
                        0.3 *
                            math.sin(
                              (_wave.value + phases[i]) * 2 * math.pi,
                            )),
                decoration: BoxDecoration(
                  color: NightStyle.stateInk,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
```

顶部还要补 `import 'dart:math' as math;`。

- [ ] **Step 2: 删掉旧文件**

```bash
git rm lib/features/session/presentation/widgets/session_settings_section.dart
```

- [ ] **Step 3: 静态检查**

Run: `dart format . && flutter analyze`
Expected: 只剩 `sleep_session_page.dart` 尚未接线的引用错误——那些在 Task 10 处理。**若报出别的错误，停下来修掉再继续。**

- [ ] **Step 4: 提交**

```bash
git add -A lib/features/session
git commit -m "feat(session): 「当前睡眠事件」卡取代设定区，四行常驻"
```

---

### Task 10: 页面重排与整页深色

**Files:**
- Modify: `lib/features/session/presentation/sleep_session_page.dart`（`_SessionBody` 整段替换）
- Delete: `lib/features/session/presentation/widgets/wake_dial.dart`
- Test: `test/sleep_session_page_test.dart`（大面积改写）

**Interfaces:**
- Consumes: Task 2/4/5/6/8/9 的全部产物。
- Produces: 页面本体结构不变（`SleepSessionPage({Key? key, DateTime? now, Duration tick})`）。

**背景：整页包在 `Theme(AppTheme.dark())` 里。** 原型的睡眠模式是**常暗**的
（setup 页那句提示写着「屏幕将保持暗色」），而我们的页面此前跟应用主题走——浅色主题下
会显示一块浅色底。包一层 dark `Theme` 之后：新写的元素走 `NightStyle`，而复用的共享组件
（白噪音宫格 / 音量条 / 时长 chip / `IosToggle` / `EmptyState`）照常从 `AppTokens` 取
深色值，两边都落在同一套深色观感上，**不用给它们抄第二份**。

由此带来的一条**已知不一致**（记进规格 §十三）：`_RejectedSheet` 与评星弹窗走的是
`AppSheet`，它把面板推在根导航器上、取的是**应用主题**而非这一页的 `Theme`，
所以浅色主题下这两块仍是浅色面板。本轮不动它们——`AppSheet` 的外观是共享组件的职责，
改它等于给全站换肤。

- [ ] **Step 1: 改测试夹具**

`test/sleep_session_page_test.dart` 的 `pumpSession` 里加两件事：

```dart
    // 会话页的背景是一个 60 秒循环的动画，**开着它 `pumpAndSettle()` 会 timed out**
    // （已实测）。夹具统一把「减弱动态效果」打开，画面停在静态层。
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
```

（放在 `tester.view.devicePixelRatio = 1.0;` 之后。）

- [ ] **Step 2: 跑测试，确认当前那些断言开始变红**

Run: `flutter test test/sleep_session_page_test.dart`
Expected: 多条 FAIL（找不到「正在睡眠」「3h 42m」「今晚的设定」等）。这个「红」正是接下来要改的清单。

- [ ] **Step 3: 改页面**

`lib/features/session/presentation/sleep_session_page.dart`：

1. 删掉 `import '../../../core/widgets/atmosphere.dart';`、`import '../../../core/widgets/glass_surface.dart';`、`import 'widgets/session_noise_section.dart';`、`import 'widgets/session_settings_section.dart';`、`import 'widgets/wake_dial.dart';`，改成：

```dart
import '../../../core/theme/app_theme.dart';
import 'night_scene.dart';
import 'night_style.dart';
import 'widgets/hold_to_finish_button.dart';
import 'widgets/night_backdrop.dart';
import 'widgets/night_scene_picker.dart';
import 'widgets/session_events_card.dart';
import 'widgets/sleep_moon_mark.dart';
```

2. `build` 改成：

```dart
  @override
  Widget build(BuildContext context) {
    final session = ref.watch(activeSessionProvider).valueOrNull;
    final scene = NightScene.fromId(session?.sceneId);

    // 会话页是**常暗**的（原型的睡眠模式就是这么设计的），而应用主题可能是浅色。
    // 包一层 dark `Theme` 之后，复用的共享组件（白噪音宫格 / 音量条 / 时长 chip /
    // `IosToggle` / `EmptyState`）照常从 `AppTokens` 取深色值，不必给它们抄第二份。
    return Theme(
      data: AppTheme.dark(),
      child: Scaffold(
        // 透明，让夜景背景透出来；这个 Scaffold 只为 Material 祖先与键盘内边距
        // 而存在，不是为了它的颜色。推入的路由继承不到外壳的任何东西。
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Positioned.fill(child: NightBackdrop(scene: scene)),
            SafeArea(
              minimum: const EdgeInsets.only(top: 20),
              child: session == null
                  ? const _NoSession()
                  : _SessionBody(
                      session: session,
                      now: _now,
                      scene: scene,
                      onSceneChanged: (picked) => ref
                          .read(sessionRepositoryProvider)
                          .update(sceneId: picked.id),
                      onFinish: () => _finish(session),
                      onFinishHint: () => ref
                          .read(toastProvider.notifier)
                          .show('按住不放，填充条扫满才结束。'),
                      scrollController: _scroll,
                    ),
            ),
          ],
        ),
      ),
    );
  }
```

3. `_SessionBody` 整段替换：

```dart
class _SessionBody extends StatelessWidget {
  const _SessionBody({
    required this.session,
    required this.now,
    required this.scene,
    required this.onSceneChanged,
    required this.onFinish,
    required this.onFinishHint,
    required this.scrollController,
  });

  final SleepSession session;
  final DateTime now;
  final NightScene scene;
  final ValueChanged<NightScene> onSceneChanged;
  final VoidCallback onFinish;
  final VoidCallback onFinishHint;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        _StatusHeader(onCollapse: () => _collapse(context)),
        const SizedBox(height: 4),
        _TimerBlock(session: session, now: now),
        const SizedBox(height: 12),
        NightScenePicker(scene: scene, onChanged: onSceneChanged),
        const SizedBox(height: 12),
        SessionEventsCard(session: session, now: now),
        const SizedBox(height: 20),
        // 结束按钮在事件卡下方：它是这一页唯一的出口，也是拇指最顺的位置。
        HoldToFinishButton(onFinish: onFinish, onHint: onFinishHint),
      ],
    );
  }
}
```

4. 删掉 `_NoiseSummaryBar`、`_BedWakeRow`、`_TimeColumn` 三个类，删掉 `_noiseOpen` /
   `_toggleNoise` / `_revealNoise` / `_scroll` 相关的状态（页面不再有展开区；`ScrollController`
   仍要留着传给 `_SessionBody`），并加上三个新类：

```dart
/// 顶部一行：左边「收起」，右边居中的状态点与「睡眠进行中」。
///
/// **「收起」是我们相对原型多留的**：原型的激活态是个占满全屏的模态，没有任何出口，
/// 而我们收起之后会话继续跑（首页显示「正在睡眠」卡）。照搬模态等于砍掉这条既有
/// 能力（规格偏差 #28）。
class _StatusHeader extends StatelessWidget {
  const _StatusHeader({required this.onCollapse});

  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          _CollapsePill(onTap: onCollapse),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const _PulseDot(),
                const SizedBox(width: 8),
                Text(
                  '睡眠进行中',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.3,
                    color: NightStyle.statusText,
                  ),
                ),
              ],
            ),
          ),
          // 右侧留一块与左侧胶囊等宽的空白，标题才真的居中（原型用
          // `.sleep-header-spacer { width: 48px }` 达到同一效果）。
          const SizedBox(width: 62),
        ],
      ),
    );
  }
}

/// `.sleep-live-status > span:first-child`：2.2 秒一轮的呼吸圆点。
class _PulseDot extends StatefulWidget {
  const _PulseDot();

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (NightStyle.reduceMotion(context)) {
      _pulse.stop();
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) => Opacity(
        // `sleepPulse { 50% { opacity: .45 } }`
        opacity: 1 - 0.55 * Curves.easeInOut.transform(_pulse.value),
        child: child,
      ),
      child: const DecoratedBox(
        decoration: BoxDecoration(
          color: NightStyle.statusDot,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: NightStyle.statusDot, blurRadius: 12)],
        ),
        child: SizedBox(width: 6, height: 6),
      ),
    );
  }
}

/// 中央：月亮 + 当前时刻 + `HH:MM:SS` + 「已进入睡眠模式」。
class _TimerBlock extends StatelessWidget {
  const _TimerBlock({required this.session, required this.now});

  final SleepSession session;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final clock = now.toLocal();
    final hhmm = '${clock.hour.toString().padLeft(2, '0')}:'
        '${clock.minute.toString().padLeft(2, '0')}';
    final elapsed = session.elapsedClockAt(now);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          const SleepMoonOrbit(size: 132, live: true),
          const SizedBox(height: 24),
          Text(
            hhmm,
            style: TextStyle(
              fontSize: 13,
              letterSpacing: 1.6,
              color: NightStyle.clockText,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            elapsed,
            style: AppTheme.num(
              context,
              size: 46,
              weight: FontWeight.w500,
              letterSpacing: 1.1,
              color: NightStyle.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '已进入睡眠模式',
            style: TextStyle(fontSize: 12, color: NightStyle.textFaint),
          ),
        ],
      ),
    );
  }
}
```

`_CollapsePill` 的样式改成原型的 `sleep-navigation-back`：

```dart
class _CollapsePill extends StatelessWidget {
  const _CollapsePill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        AppHaptics.tap();
        onTap();
      },
      child: Container(
        constraints: const BoxConstraints(minWidth: 56, minHeight: 34),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: NightStyle.glassFill,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          border: Border.all(color: NightStyle.glassStroke),
        ),
        alignment: Alignment.center,
        child: Text(
          '收起',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: NightStyle.glassInk,
          ),
        ),
      ),
    );
  }
}
```

（`AppRadii.pill` 仍要从 `core/theme/app_tokens.dart` import——圆角常量是共享的，不是被换掉的皮肤。）

5. `_NoSession` 保持原样（它已被包在 dark `Theme` 里）。

- [ ] **Step 4: 删掉日晷圆环**

```bash
git rm lib/features/session/presentation/widgets/wake_dial.dart
```

- [ ] **Step 5: 逐条改写受影响用例**

在 `test/sleep_session_page_test.dart` 里：

- `显示已睡时长与设定的起床时间` → 改名 `显示当前时刻、已过时长与设定的起床时间`：

```dart
    expect(find.text('睡眠进行中'), findsOneWidget);
    // start 23:14、已过 3h42m → 现在是 02:56，秒表读 03:42:00。
    expect(find.text('02:56'), findsOneWidget);
    expect(find.text('03:42:00'), findsOneWidget);
    // 事件卡抬头写着这一晚是从几点开始的。
    expect(find.textContaining('23:14 开始'), findsOneWidget);
    // 闹钟那一行的标题带时刻。
    expect(find.text('07:00 起床闹钟'), findsOneWidget);
```

- `超过起床时间后给出「已超过」而不是让弧溢出` → 改名 `超过起床时间后在闹钟行给出「已超过」`，断言不变（`find.textContaining('已超过起床时间')`，默认闹钟关着也要显示，因为计划目标与开关无关）。
- `闹钟关着时胶囊说自然醒后手动结束` → 断言改成 `find.text('本次睡眠不设闹钟')`。
- `闹钟开着时报剩余时间，并带上后台投递的如实标注` → 断言改成：

```dart
    expect(find.text('将在设定时间轻柔唤醒 · 还有 4h 4m'), findsOneWidget);
    // 规格点名「这句话是功能的一部分」：逐字断言，不是「页面里大概有这么句」。
    expect(
      find.text('由系统通知投递；休眠模式下可能晚几分钟，强度不如系统闹钟。'),
      findsOneWidget,
    );
```

- `超过起床时间后闹钟胶囊说「已过」，不再说「还有 0h 0m」` → 断言改成
  `expect(find.textContaining('已超过起床时间'), findsOneWidget);` 与
  `expect(find.textContaining('还有 0h'), findsNothing);`，并删掉最后那句
  `find.textContaining('起床闹钟已开')`。
- `入睡与闹钟时刻都补零到两位` → 改成 `expect(find.textContaining('09:05'), findsOneWidget);`
  （事件卡抬头的「09:05 开始」）、`expect(find.text('06:05'), findsOneWidget);`（闹钟胶囊），
  并保留两条 `findsNothing` 的反向断言。
- `推入页自己提供 Material 祖先与背景` → 把找标题的那一行换成
  `final heading = find.text('睡眠进行中');`，其余不动。
- `点「收起」回到上一页，不结束会话也不写库` → 不动。
- `设定开关常驻，点摘要条才展开白噪音区` → 删掉，换成：

```dart
  testWidgets('事件卡四行常驻，点白噪音行打开底部弹窗', (tester) async {
    final start = DateTime(2026, 8, 30, 23, 14);
    await pumpSession(
      tester,
      session: sessionAt(start),
      now: start.add(const Duration(hours: 1)),
    );

    expect(find.text('当前睡眠事件'), findsOneWidget);
    expect(find.text('开始睡眠'), findsOneWidget);
    expect(find.text('白噪音'), findsOneWidget);
    expect(find.textContaining('未开启'), findsOneWidget);
    expect(find.text('07:00 起床闹钟'), findsOneWidget);
    expect(find.text('鼾声/梦话记录'), findsOneWidget);
    expect(find.text('尚未接入录音，开关只保存偏好。'), findsOneWidget);

    await tester.tap(find.text('白噪音'));
    await tester.pumpAndSettle();

    expect(find.text('白噪音设置'), findsOneWidget);
    expect(find.text('15m'), findsOneWidget);
    expect(find.textContaining('退到后台或锁屏后声音会停'), findsOneWidget);
  });
```

- `展开白噪音区会自动把它滚进视野` → **整条删掉**（页面不再有展开区，滚动问题随之消失）。
- `展开区里的白噪音定时最长 60 分钟，没有「不限」与 90m` → 改名
  `弹窗里的白噪音定时最长 60 分钟，没有「整晚」`，开头加一步打开弹窗，断言里补
  `expect(find.textContaining('整晚'), findsNothing);`。
- `鼾声/梦话开关带上「尚未接入录音」的说明（plan A）` → 去掉开合动作，直接断言。
- `白噪音区注明后台播放未接入` → 改名 `弹窗里注明后台播放未接入`，先打开弹窗（点 `find.text('白噪音')`）。
- `拨动鼾声开关会写回设置` → 去掉开合动作，直接 `tester.tap(toggleLabeled('鼾声/梦话记录'))`。
- `闹钟开着时，投递强度标注就在那一行` → 断言保持，去掉开合动作。
- `闹钟开关被拒时回弹，且不写入会话的 alarmEnabled` → 去掉开合动作。
- 四条白噪音用例（`选中白噪音会交给播放器，再点一次停掉` / `白噪音倒计时到点会停掉，并清空会话里的选中值` /
  `收起展开区不会停掉正在播放的白噪音` / `pop 掉会话页后白噪音继续响`）→ 都要在操作前加一步
  打开弹窗（`await tester.tap(find.text('白噪音')); await tester.pumpAndSettle();`），
  第二条用例名里的「收起展开区」改成「关掉弹窗」。

- [ ] **Step 6: 加新用例**

```dart
  testWidgets('列出八种夜景氛围，选中的写回会话行', (tester) async {
    final start = DateTime(2026, 8, 30, 23, 14);
    await pumpSession(
      tester,
      session: sessionAt(start),
      now: start.add(const Duration(hours: 1)),
    );

    for (final label in ['流星夜', '极光', '深海', '月海', '云上', '萤火', '银河', '雨夜']) {
      expect(find.text(label), findsOneWidget, reason: '漏了「$label」');
    }

    await tester.tap(find.text('银河'));
    await tester.pumpAndSettle();

    final row = await database.activeSession();
    expect(row!.sceneId, 'galaxy', reason: '选了场景却没写回会话行');
  });

  testWidgets('收起过的场景在重进页面时还在', (tester) async {
    final start = DateTime(2026, 8, 30, 23, 14);
    await pumpSession(
      tester,
      session: sessionAt(start),
      now: start.add(const Duration(hours: 1)),
    );
    await tester.tap(find.text('雨夜'));
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    // 再进一次：从**同一个库**读出会话，场景必须还是雨夜。
    await pumpSession(
      tester,
      session: (await SessionRepository(database).load())!,
      now: start.add(const Duration(hours: 1)),
    );
    expect(find.byType(NightBackdrop), findsOneWidget);
    final badge = tester.widget<NightSceneChoice>(
      find.byWidgetPredicate((w) => w is NightSceneChoice && w.selected),
    );
    expect(badge.scene, NightScene.rain);
  });

  testWidgets('浅色主题下会话页仍然是深色', (tester) async {
    // 原型的睡眠模式是常暗的（setup 页写着「屏幕将保持暗色」）。这条钉住
    // 「页面自己套 dark Theme」这件事，防止有人顺手把它删掉。
    final start = DateTime(2026, 8, 30, 23, 14);
    tester.view.physicalSize = const Size(430, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await database.saveActiveSession(
      ActiveSessionsCompanion.insert(
        id: SessionRepository.sessionId,
        startAtUtc: start.toUtc(),
        wakeMinutes: 7 * 60,
        createdAt: start.toUtc(),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: MaterialApp(
          // 应用是**浅色**的。
          theme: AppTheme.light(),
          home: SleepSessionPage(now: start.add(const Duration(hours: 1))),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final context = tester.element(find.text('睡眠进行中'));
    expect(Theme.of(context).brightness, Brightness.dark);
  });
```

- [ ] **Step 7: 跑测试**

Run: `flutter test test/sleep_session_page_test.dart`
Expected: PASS。

若 `收起过的场景在重进页面时还在` 报 `pumpSession` 的 `activeSessionProvider` 覆盖与库不一致，
确认第二次调用传的是**从库里读回来的** `SleepSession`（`SessionRepository(database).load()`），
而不是原来那个对象。

- [ ] **Step 8: 全量校验**

Run: `dart format . && flutter analyze && flutter test`
Expected: 全部通过。

- [ ] **Step 9: 提交**

```bash
git add -A lib/features/session test/sleep_session_page_test.dart
git commit -m "feat(session): 会话页照原型的「睡眠进行中」态重建"
```

---

### Task 11: 文档同步、集成巡检与终检

**Files:**
- Modify: `README.md`、`CHANGELOG.md`
- Modify: `docs/superpowers/specs/2026-09-28-night-sleep-design.md`（§2.4、§3、§8、§9）
- Modify: `integration_test/app_screens_test.dart`
- Modify: `test/app_screens_test.dart`（若存在同名的 widget 版；否则跳过）

- [ ] **Step 1: 集成巡检适配循环动画**

`integration_test/app_screens_test.dart` 里凡是走到会话页之后调 `pumpAndSettle` 的地方，
换成显式 `pump`：

```dart
      // 会话页的背景是一个 60 秒循环的动画，`pumpAndSettle` 在这里永远收敛不了。
      // 用显式推帧代替，步进时长与原本的等待相当。
      await tester.pump(const Duration(milliseconds: 900));
```

并在巡检脚本顶部把这条坑写清楚，同时把巡检步骤里的「按住不放」文案改成「长按结束睡眠」、
把小字「按住不放」改成「持续按住，避免误触」。

- [ ] **Step 2: 同步主规格**

`docs/superpowers/specs/2026-09-28-night-sleep-design.md`：

- 版本行 `> 版本：3.1（2026-10-02）` → `> 版本：3.2（2026-10-02）`。
- §2.4 页面表中「会话页（`/sleep/session`）」那一行的「设计内容」列改为：
  「原型无此页（本实现新增，见偏差 #24）；**v3.2 起照原型 `SleepView` 的「睡眠进行中」态重建**（偏差 #28–#32）」，
  「产品实现要求」列补上「夜景氛围（8 种场景动画）、月亮 + `HH:MM:SS` 实时计时、
  当前睡眠事件卡、横向长按结束按钮；白噪音设置走深色底部弹窗」。
- §3 映射表加/改这些行：

```markdown
| 会话页夜景氛围与弹窗 | 页面局部令牌 `lib/features/session/presentation/night_style.dart`；场景表 `night_scene.dart`；背景 `widgets/night_backdrop.dart`；选择器 `widgets/night_scene_picker.dart`；月亮 `widgets/sleep_moon_mark.dart`；白噪音弹窗 `sheets/night_noise_sheet.dart`；事件卡 `widgets/session_events_card.dart`。**这一页不走 `AppTokens`**，理由见偏差 #32 |
```

  并把原来那行「会话页 `sleep_session_page.dart` … 日晷圆环 `wake_dial.dart`」里的
  「日晷圆环 `widgets/wake_dial.dart`」删掉（该文件已删除）。
- §8 偏差表追加 #28–#32（内容照抄本会话规格 §十一 那五行）。
- §9 测试矩阵补 `docs/superpowers/specs/2026-09-30-sleep-session-design.md` §十二 的 plan C 各行。

- [ ] **Step 3: 同步 README**

- 「当前实现范围」的「**睡眠会话**(v3.0)」段，把版式描述改成 v3.2 的：夜景氛围（8 种场景动画）、
  月亮 + `HH:MM:SS`、当前睡眠事件卡四行、横向长按结束按钮、白噪音走深色底部弹窗、整页常暗。
  鼾声那行的「尚未接入录音，开关只保存偏好」**一字不改**。
- 「未实现」表补一行：「夜间录音（plan B）尚未落地——会话页的鼾声/梦话开关仍只保存偏好」。
- 「验证记录」补本轮条数、跑测的设备/系统版本，以及**未验证项**：夜景动画在真机上的
  帧率与耗电未实测；`flutter_svg` 丢弃 `<filter>` 导致月亮外发光只能近似（已实测的现象，
  未在真机上目视核对近似效果）。
- 「界面截图巡检」一节补一句：会话页背景是常驻动画，巡检脚本里这一段不能用 `pumpAndSettle`。

- [ ] **Step 4: 写 CHANGELOG**

在 `CHANGELOG.md` 的 `## 3.1（2026-10-02）` 之前插入：

```markdown
## 3.2（2026-10-02）

会话页按新原型（Figma Make 的 `SleepView`「睡眠进行中」态）重建。**范围只到这一页**：
新原型的最终生效层同时把全站换成了扁平原生风，那部分本轮**不做**（见偏差 #32）。

**整页换成夜景。** 底色是八种场景之一的暗色渐变 + 一层 67px 网点质感，上面浮着场景动画：
流星、极光、海浪、云层、萤火、银河、雨丝、星点闪烁，参数逐条抄自原型的 `@keyframes`。
八套动画由**一个** 60 秒循环的 `AnimationController` 驱动、全部画在一个 `CustomPaint` 里
——不给 34 颗星、18 条雨丝各建一个 widget。系统开了「减弱动态效果」时停表，只留静态层。
选中的场景写进会话行（schema v5 加 `active_sessions.scene_id`），收起页面再进来、
杀掉应用重开都还是同一个夜景。

**中央读数换了一套。** 日晷圆环（已过 ÷ 计划）换成月亮 + 当前时刻 + `HH:MM:SS` 秒表 +
「已进入睡眠模式」。秒表的小时不封顶——回绕会把「忘了结束、放了两天」藏成一个正常的
00:00。「已超过起床时间」不再单独一行，挪进起床闹钟那一行的副标题，口径仍只由模型出。

**中段并成一张「当前睡眠事件」卡**：开始睡眠 / 白噪音 / 起床闹钟 / 鼾声检测四行。
白噪音的完整设置（八宫格 + 音量 + 定时）从页内展开区改成**深色底部弹窗**，
点白噪音那一行打开；关掉弹窗、收起页面、离开会话页都继续响，这条生命周期一字未改。

**结束按钮从圆形改成全宽横向胶囊**，按下时填充条自左向右扫过。**按住时长仍是 1.5 秒**
（原型 1.6 秒，那 0.1 秒是 v3.1 的产品裁定）；按下即开始、松手未满取消、手指滑开作废、
短按只提示这些语义一条没动。

**会话页从此常暗**：整页包在 `Theme(AppTheme.dark())` 里，浅色主题下进去也是深色
（原型的睡眠模式就是这么设计的）。复用的共享组件（白噪音宫格 / 音量条 / 时长 chip /
`IosToggle`）因此照常从 `AppTokens` 取深色值，不用抄第二份。

**刻意保留、与原型不同的五处**（偏差 #28–#32）：「收起」入口、白噪音行常驻可点、
起床闹钟的开关与时刻编辑、鼾声行放开关而不是「正在聆听」的状态点、
这一页用页面局部的 `NightStyle` 而不是改 `AppTokens`。

`WakeDial` 与另外两个只服务旧版式的文件（`session_settings_section.dart`、
`session_noise_section.dart`）随之删除。数据语义一个没动：空状态、时长守门 `(0, 24h]`
不落库、就地评星、丢弃、闹钟重排全部原样。
```

- [ ] **Step 5: 全量校验**

Run: `dart format . && flutter analyze && flutter test`
Expected: 全部通过。

- [ ] **Step 6: 提交**

```bash
git add README.md CHANGELOG.md docs/ integration_test/
git commit -m "docs(session): 同步会话页夜景改版后的实现范围与变更史"
```

---

## Self-Review

**Spec coverage**（对照 `2026-09-30-sleep-session-design.md` §十六）：

| 规格要求 | 落在哪 |
| --- | --- |
| 顶部状态点 + 「睡眠进行中」，收起移到左上 | Task 10 `_StatusHeader` / `_CollapsePill` |
| 月亮 + 当前时刻 + `HH:MM:SS` + 「已进入睡眠模式」 | Task 3（口径）、Task 4（月亮）、Task 10 `_TimerBlock` |
| 夜景氛围八种、动画参数照抄 CSS、减弱动态效果停表 | Task 2、Task 5 |
| 场景持久化（schema v5） | Task 1、Task 10 的 `onSceneChanged` |
| 当前睡眠事件卡四行 | Task 9 |
| 白噪音改深色底部弹窗 | Task 7 |
| 横向长按按钮，1.5 秒不变 | Task 8 |
| 页面局部令牌 `NightStyle`，`AppTokens` 不动 | Task 2（并核对：没有任何任务修改 `app_tokens.dart`） |
| `WakeDial` 删除 | Task 10 Step 4 |
| 红线四条（鼾声标注 / 投递强度标注 / 定时四档 / 不变量） | Task 9、Task 7、Task 10 Step 5 |
| 文档同步 | Task 11 |

**Placeholder scan:** 无 TBD / TODO；每个代码步骤都给到可落地的片段。几处**有意的近似**
（CSS 模糊半径换算、`alternate` 用三角波、雨丝与萤火的长延迟用公式代替逐条列举）
都在代码注释里写明，不假装是逐像素复刻。

**Type consistency:**
- `NightScene` / `NightScene.fromId` / `NightScene.fallback`：Task 2 定义，Task 5、6、10 使用。
- `NightStyle.reduceMotion(context)`：Task 2 定义，Task 4、5、8、9、10 使用。
- `NightStyle` 常量名在 Task 5/6/7/8/9/10 中逐处引用，与 Task 2 的定义一一对应。
- `AppIcons.holdEnd`：Task 4 定义，Task 8 使用。
- `SleepMoonMark` / `SleepMoonOrbit`：Task 4 定义，Task 10 使用 `SleepMoonOrbit`。
- `NightScenePicker` / `NightSceneChoice`：Task 6 定义，Task 10 使用 `NightScenePicker`，
  Task 10 的新用例使用 `NightSceneChoice`。
- `SessionEventsCard({session, now})`：Task 9 定义，Task 10 调用。
- `showNightNoiseSheet(context)`：Task 7 定义，Task 9 调用。
- `SleepSession.elapsedClockAt`：Task 3 定义，Task 10 使用。
- `SessionRepository.update(sceneId:)`：Task 1 定义，Task 10 调用。

**已知风险：**
1. Task 5 的 `MaskFilter.blur` 在软件光栅化（widget 测试）里不生效也不报错，
   所以测试只能验「不抛异常 + 相位在走」，**动画观感必须目视核对**——这一条排进
   Task 11 之后的终审批次，不塞进任何单个实现任务（见记忆 `do-not-bundle-visual-checks`）。
2. `integration_test` 不参与 `flutter test`，Task 11 Step 1 的改动**跑不到**，
   只能靠 `flutter drive` 手动验；README 里要如实标注这一点。
3. `AppIcons.soundOff` 那格「关闭」在弹窗未选中任何声音时是选中态——`noise.activeId`
   为 `null` 就是「关闭」，这与 `NoiseSheet` 的既有口径一致，不是新语义。
