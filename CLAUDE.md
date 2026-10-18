# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 这是什么

「夜深」——中文、**本地优先**的睡眠记录 Flutter 应用，数据留在设备上、不上传。
iOS / macOS / Android 都已构建、都在真机或模拟器上跑通过；**Web 只有骨架、从未构建**。
界面按 Figma Make 原型的**最终生效层**实现。

能做的事：离线睡眠记录与 7 / 14 / 30 天统计（全部记录可按周 / 月 / 年翻阅）、睡前会话
（入睡前 / 睡眠进行中两态）、「回顾」补感受、夜间录音 + 端侧鼾声判定、数据导出（CSV / JSON，
导出前可逐格预览）、就寝 / 起床本地通知、助眠音效、罗盘。当前版本 v0.42。

### 产品红线：「没有的东西就显示为没有」

原型里那些是**演示数据**，不是待实现的能力。落到具体实现上：

- **不伪造睡眠阶段**——阶段三块（深睡 / 浅睡 / REM）只在该记录确有阶段数据时出现。
- **没有测量就不画**——没有真实音频就不画波形；模型按整段给结论，**就绝不画事件区间**。
- **不显示读不到的余额**；**不猜小米导入的字段**（公开实现的阶段映射已被实测证明是错的）。
- **片段判定会对「有声音、但没测到鼾声/人声」的片段自动标「杂音」**（2026-10-18 使用方
  明确要求）。它说的是「机器在整段上没找到够格的证据」，不是「已证明这不是鼾声」；
  依据行摆两类分与判定线，让人能直接否掉。
- **只说「疑似」、不给概率**——依据行摆的是测出来的分与判定线，让人能直接否掉它。
- **人标的永远优先，机器永不覆盖人标的。** 数字静音 / 读不出来 / 从没分析过，三种「沉默」
  各有各的说法，不能混成一句「杂音」。

**说的时候要准**：没跑过的别写成跑过，跑绿了就说跑绿了、哪条没验就写哪条。这条管的是**你说的话**。

## 常用命令

```bash
flutter pub get
dart run build_runner build     # 生成 lib/core/database/app_database.g.dart
dart format .
flutter analyze
flutter test                     # 整套（约 840 条用例）
flutter test test/sleep_score_test.dart                       # 单个文件
flutter test test/sleep_score_test.dart --plain-name "时长阶梯"  # 单个用例（子串匹配）
flutter run -d macos             # 或 -d chrome / -d <真机或模拟器>
```

**新检出要先跑一次 `build_runner`**：`app_database.g.dart` 已 gitignore，缺了它 `flutter analyze` /
`flutter test` 会报几百条 `Undefined name 'ActiveSessionsCompanion'` 之类的错；改表结构后同理。

**演示数据**只在 `DEMO_DATA` 为真时安装，默认等于 `kDebugMode`（见 `core/config/app_config.dart`）：

```bash
flutter run -d macos --dart-define=DEMO_DATA=true     # 强制开启
flutter build macos --dart-define=DEMO_DATA=false     # 发布构建强制关闭
```

`integration_test/` **不在裸跑 `flutter test` 的扫描范围里**（它只扫 `test/`），要**指名文件 +
指定设备**：

```bash
export NO_PROXY=127.0.0.1,localhost        # 不设会表现为「连不上 VM Service」
flutter test integration_test/app_screens_test.dart -d <device>     # 界面截图巡检
```

## 改动分级：先分清大小，别把小改动做成大工程

判定标准是一句话：**这个决策能不能从代码和现有约束里推出来？** 推得出来就直接改——不写计划、
不写 spec、**也不先复述一遍要改什么**。用户报的 bug、改一句文案、调一处样式、加个开关都属此类：
看一眼代码，改，跑一遍测试，说结果。一次需求花多长时间取决于改动本身，不取决于流程。

| 档 | 触发条件 | 产物 |
| --- | --- | --- |
| **直接改**（默认档） | 单点、单文件、现有测试能验证 | 不开 plan、不写 spec、不先复述方案；改完跑 `dart format .` / `flutter analyze` / `flutter test` |
| **只开 plan** | 跨几处或多平台、有「不许破坏 X」的硬约束、需要先红后绿地钉测试 | 一份短 plan 挂到**已有规格**的对应章节（原地更新），不新开 spec |
| **spec + plan** | 新能力、新架构、影响产品语义、需要权衡取舍 | 新 spec + 新 plan |

**拿不准就往低档走。** plan 的厚度跟着改动量走，不要为了格式齐整把单点修改写成几百行。
规格与计划放 `docs/superpowers/specs/` 与 `docs/superpowers/plans/`，文件名一律
`YYYY-MM-DD-<topic>.md`；规格是活文档，创建时定日期、之后原地更新、不新开文件。
**计划不删**，做完留着备查。

编排强度同样跟档位走：「每个任务派一个实现者 + 一个审查者」那套**只用于 spec + plan 档**。
`只开 plan` 档在当前会话里直接做，审查集中在阶段末尾做一次——每个 subagent 都要从头重读
CLAUDE.md 与源码，对小改动是纯开销。

**需求写完只记一条 `CHANGELOG.md`**：新增了什么、修好了什么、行为变了什么，每条三五行为宜。
**纯文档改动不进 CHANGELOG**（git 历史就是记录）。**不要顺手同步 README、规格、验证记录**，
也不要为一个需求补一份计划——只有一种情况必须动它们：**你的改动让那里已经写下的一句话变成了假话**。
那时改的也是**那一句话**。

## 架构

### 分层

```
lib/
  app/          路由外壳与跨 feature 的编排（app.dart 的 router、app_shell.dart 的标签壳、
                toast、夜间录音控制器、白噪音会话控制器、提醒重排、通知权限闸口）
  core/         config（构建开关）/ database（Drift）/ platform（触觉、提醒、系统栏、
                前台服务、钥匙串）/ theme（设计令牌）/ widgets（共享件）
  features/<feature>/{presentation,domain,data}
```

`features/` 下**三个层次按需出现，不是每层都有**：只有 `settings` 与 `sleep` 三层齐全；
`log`、`onboarding`、`session`、`stats` 只有 `presentation`（含 `presentation/sheets`、
`presentation/widgets` 子目录）；`home`、`compass` 有 `domain` + `presentation`。

**`lib/app/` 是第四个归属，不是 `core/` 也不是某个 feature**——它拥有 router、外壳与一批
跨 feature 的 provider。`settingsProvider`、`activeTabProvider`、录音控制器都在那里。

**Widget 不直接碰数据库。** `SleepRepository.loadAll()` 用 3 条批量查询组装 `SleepEntry`
聚合（阶段 / 声音片段 / 洞察各一条，不是 N+1），派生的墙上时钟标签、醒来日归档、阶段合计
只在这一处算。UI 唯一数据源是 `sleepEntriesProvider`。

### 状态（Riverpod）

`lib/` 下约 **35 个顶层 provider**，不逐个列。摸清位置比背名字重要：

- **数据库层**（`core/database/app_database.dart`）：`databaseProvider` 的 body 是
  `throw StateError(...)`，**必须在 `main.dart` 里 override**；同处还有 `recordsProvider`、
  `clipsProvider`、`recordProvider(id)`、`activeSessionWatchProvider`。
- **仓库层**：`sleepRepositoryProvider` / `sleepEntriesProvider`（`features/sleep/data/sleep_repository.dart`）、
  `sessionRepositoryProvider` / `activeSessionProvider`（`session_repository.dart`）、
  `clipAnalyzerProvider`、`clipFileStoreProvider`、`nightRecorderProvider` / `pcmInputProvider`。
- **外壳与编排**（`lib/app/`）：`settingsProvider`、`themeModeProvider`、`activeTabProvider`
  （放 provider 而非 widget state，因为保存记录后要跳回首页）、`toastProvider`、
  `nightRecordingControllerProvider`、`noisePlayerProvider` / `noiseSessionControllerProvider`、
  `reminderPermissionProvider`。
- **平台**（`core/platform/`）：`reminderSchedulerProvider`、`nightAudioServiceProvider`、
  `appSettingsLauncherProvider`。

`main.dart` 里 override 了三个：`databaseProvider`、`insightApiKeySeedProvider`（密钥必须在这里
`await` 读到，否则输入框会先空一下）、`reminderSchedulerProvider`（Web 上必须给
`NoopReminderScheduler`，因为 `defaultTargetPlatform` 在 Web 上报告的是宿主系统、
会绕过 provider 自己的 `kIsWeb` 守卫）。

**`NotifierProvider`（`toastProvider`、`insightApiKeyProvider`）与 `ChangeNotifierProvider`
（录音、白噪音、片段回放）并存，是有意的分工**——前者是纯值，后者本来就是要 dispose 的控制器。
代码里**没有 `AsyncNotifierProvider`**。

⚠️ 两个**同名但不是 provider** 的干扰项：`features/settings/data/model_catalog.dart` 的
`InsightProvider` 是普通数据类，`insight_service.dart` 的 `pingProvider(...)` 是函数。

### 路由

`go_router`（`lib/app/app.dart`）。**只有一条根路由 `/`**（builder 是 `AppScaffold`），
**其余全部声明为它的子路由**——这样 push 会盖住整个外壳，设计就是这么隐藏标签条的。

四个主入口（首页 / 回顾 / 统计 / 设置）**不是路由**，是 `AppScaffold` 内按 `AppTab` 枚举的 tab 切换。

```
/log/new  /log/edit  /stats/all  /settings/{appearance,sleep,import,export,export/preview,insight,demo,compass}
/sleep/session
```

（`/settings/export/preview` 是 `/settings/export` 的**兄弟**而非子路由；编辑页的夜晚通过
`state.extra` 传快照，不重新查库——用户点的是他看到的那个快照。）

**推入的路由什么都继承不到**：没有 `Scaffold`（无背景、无 `Material` 祖先）、没有外壳留白、
没有氛围渐变。所以**每个 push 页面都走 `core/widgets/subpage.dart` 的 `Subpage`**，
它补齐那四样（氛围背景 / 透明 `Scaffold` 提供 `Material` 祖先 / `SafeArea` / 限宽）。
底部弹层的材质祖先同理由 `AppSheet` 提供。

**一处例外：会话页 `/sleep/session`**。它照样是 `/` 的子路由，但**不适合 `Subpage`**——那一页
常暗、背景是整屏夜景而不是 `Atmosphere`，共享的返回胶囊与文字颜色都取不到对的值；而且它的限宽是
**680px**（原型 `.sleep-*` 外壳），`Subpage` 是 720px。它自套 `Theme(AppTheme.dark())` + 透明
`Scaffold`，把那四样自己实现了一遍。

**它的呈现是「从底部升起的整屏面板」**：这条路由用 `pageBuilder` +
`CustomTransitionPage(opaque: false)`，竖向转场，面板顶部标题行整行可下拉滑走。仍是路由而不是
`AppSheet` 那种 dialog——`context.go('/')` 不会 pop dialog 路由。**`key: state.pageKey` 是必需的**，
漏了草稿与计时器会在重建时重置。

**开屏页挂在 `AppScaffold` 的 `Stack` 最上层，不是路由**（`onboarding/presentation/splash_screen.dart`）。
收起条件是「时间轴播完 **且** `settings` 已读到第一帧」（判据是 `AsyncValue.isLoading` 为假，
成功与失败都算结论），否则会「先闪一下主界面再跳出引导」。`_splashFinished` 是 State 字段而非
provider——`AppScaffold` 是 `/` 的 builder，push 子页时 State 被复用，来回跳转不会重播。
因为它在 `Stack` 里，任何 push 在其之上的路由都会盖住它：只在冷启动停在 `/` 时生效，
将来若加路由恢复或 deep link 要改挂 `MaterialApp.builder`。

### 数据库

Drift + SQLite，**`schemaVersion => 8`**（`core/database/app_database.dart`），**6 张表**：
`SleepRecords`、`SleepStageSegments`、`SoundClips`、`Insights`、`ActiveSessions`（单行表）、
`AppSettings`。`beforeOpen` 里开 `PRAGMA foreign_keys = ON`；外键级联删除；
`source ∈ {manual, import, demo, session}` 隔离演示数据与会话落库的记录。

**迁移的下界是承重的，别把 `onUpgrade` 的分支当成一律 `from < N`。** 三种写法并存：
`from < N`、`from >= 2 && from < N`、`from >= 4 && from < N`。理由都一样——从更早版本升上来的
库，表是用**当前**定义 `createTable` 出来的、已经带着新列，再 `addColumn` 就是
`duplicate column name`。改动前先读懂那些下界注释。

逐版一句话：**v2** 建三张子表 + 补四列；**v3** `Insights.recordId` 补 `ON DELETE CASCADE`
（**先删孤儿、再 `alterTable` 重建**，顺序不可颠倒：迁移期间 `PRAGMA foreign_keys` 是关的，
先重建会把孤儿拷进新表），因此这次升级会**自动修复已在现场损坏的库**；**v4** 建会话表并把
`SleepRecords.quality` 改为可空；**v5** 加 `active_sessions.scene_id`；**v6** 加
`clip_journal` / `waveform_envelope` / `labeled_at_utc`；**v7** 加 `sound_clips.auto_analysis`；
**v8** 是**唯一一条改数据的迁移**——把旧引擎写下的 `auto_analysis` 清空、`analysis_status` 退回
`pending`，好让下一次冷启动用新引擎重算（**只动机器那一列**，用户标的 `kind` 与
`labeled_at_utc` 一个字节都不碰）。**换判定引擎就照 v8 的样子做。**

其余口径：

- 入睡 / 醒来存 **UTC 瞬时值 + 录入时区**，墙上时间读取时派生 → 改系统时区不毁数据。
- 记录按**醒来所在本地日期**归档；跨午夜算一天。
- 统计平均值的分母是**窗口内有记录的天数**，不是日历天数。
- **`SleepRepository.save()` 的 `stages` 可空是故意的**：`null` = 「保持已有阶段不变」，
  不是「清空」（传一个列表、哪怕是空列表，才是整份替换）。记录表单没有阶段字段，若不这样约定，
  一次无关的修正就会把设备测到的整晚阶段抹掉。`createdAt` 由仓库从已存行读回而非调用方传入，
  编辑不会改写「最初记录时间」。
- `AppSettings` **不存 API Key**——密钥在系统钥匙串（`flutter_secure_storage`）。

### 片段分析管线（鼾声 / 人声）

三层，搬动任何一层之前先看清边界：

| 层 | 文件 | 能不能单测 |
| --- | --- | --- |
| **判定规则**（分 → 结论 / 弃权） | `features/sleep/domain/clip_yamnet.dart` | **能，而且是唯一能被完整测的一层**。**不许 import `tflite_flutter`**、不碰 `dart:io`——模型在 `flutter test` 里根本加载不了，一旦引入它这一层一条都测不了 |
| **跑模型**（波形 → 分） | `features/sleep/data/yamnet_scorer.dart` | 不能。要原生库与模型文件 |
| **I/O**（读文件、起 isolate、写库） | `features/sleep/data/clip_analyzer.dart` | 注入假 `ClipScorer` 后能，且从 isolate 那一跳开始走生产路径 |

- **判定是 YAMNet**（AudioSet 521 类，`kSnoringIndex = 38` / `kSpeechIndex = 0`），
  每段按 **0.975 秒一窗**（`kYamnetWindowSamples = 15600`，16 kHz 原始波形，hop 7800）喂进模型，
  以**整段均分**为主判据（鼾声那一路另有一条「连续两窗都在像鼾声」的短事件补充判据）：
  `YamnetParams.snoreThreshold = 0.40`、`voiceThreshold = 0.70`；**两条都没过就记「杂音」**
  （有声音的片段不再留「待标注」；**数字静音**、读不出来、没分析过才留）。
  ⚠️ **0.70 这一档从来没被量过**；**均分有盲区**（11.8 秒里只有 3.5 秒是鼾声会被摊薄）
  ——2026-10-18 起鼾声那一路补了「连续两窗」判据，但短于一秒的孤立事件仍可能被记成杂音；
  人声那一路没补。
- **整批只起一个 isolate、只加载一次模型**（一晚约 5.3 秒）。`ClipAnalyzer._serialised` 保证
  同一时刻只跑一批：`analyseRecord` 是**不 await** 地从会话结束与详情页两处踢出去的，
  撞车时两份 4 MB 模型是实打实的代价。
- **模型字节在主 isolate 读**（`rootBundle` 要走平台通道，后台 isolate 收不到），再跟着批处理
  送进 isolate。**闭包捕获要当心**——写 `_scorerFactory` 就是捕获 `this`，连数据库句柄一起被塞进
  消息，`SendPort.send()` 会报「object is unsendable」。
- **`measureClip` / `AudioFeatures` 还在，但不参与判定**：它们是**实测特征**，
  `tool/analyse_clips.dart` 拿它们给人肉眼核对。**别把它们摆进「自动判断依据」。**
- `assets/model/yamnet.tflite` **进包也进仓库**（判定在端侧跑，文件必须在包里）。
  真机上的评估入口是 `integration_test/yamnet_eval_test.dart`——**模型不能在 `dart run` 里跑**。

## 写 Flutter 代码前

「夜深」在 Flutter 与 CSS 的语义差异上反复栽过跟头。下面每条都是**通用 Flutter 语义** +
**本项目踩过的具体落点**。

**渲染与布局**

- **`boxShadow` 写在会被自己 `ClipRRect` 裁掉的那个盒子上 → 静默丢弃。** 阴影画在盒子边界
  **之外**，那块区域正好落在裁剪区外。阴影必须放在 clip **外面**（`glass_surface.dart`、
  `app_shell.dart` 的标签条）。症状：所有卡片看起来是平的。
- **`BackdropFilter` 模糊的是它子树**之外**背后的画面。** 想让模糊淡出，`ShaderMask` 必须套在
  `BackdropFilter` **外面**；套在里面只遮到 child 内容，模糊 layer 本身没被遮，边缘留一条硬边
  （症状正是「填充淡了、模糊还在」）。落点：`top_fade.dart`。
- **`Stack`（`StackFit.loose`）按最大的**非 position**子项定尺寸**，`Positioned` 子项完全不参与
  尺寸计算，会静缩到内容大小导致溢出。落点：`GlassSurface` 的 `expandWidth`。
- **内容留白属于滚动视图**里面**，不是外面**（`pageGutter` / `pageBottomInset`）。放外面时视口被
  压缩，留白区变成一条盖住内容的不透明带。
- **`Positioned(top: 0)` 相对的是内边距盒，不是内容盒**——主按钮的高光因此落在文字中间成了一道
  杂线。落点：`app_basics.dart` 的 `PrimaryAction`。
- **底部留白必须由标签条的**实际高度**推导**（`tabBarReserve`）。写死的值一旦偏小，最后一行就
  永远压在玻璃下面。
- **没有 `Material` 祖先的 `Text` 会落到 Flutter 的错误样式：黄色双下划线。**
  `showGeneralDialog` 不像 `showDialog` 那样包 `Material`，`Subpage` 和 `AppSheet` 都已显式补上。
  看到黄线先查材质祖先，别去翻主题。

**测试**

- **`testWidgets` 跑在 FakeAsync 里，平台通道的 Future 永不完成**——
  `await HapticFeedback.mediumImpact()` 会挂死，症状是保存按钮卡在「保存中…」。用
  `unawaited(...)`，或改用普通 `test()`。
- **同一个假时钟也会吃掉 `dart:io`**：`Directory.createTemp` / `File.writeAsBytes` /
  `File.delete` 这些**真实文件 I/O** 的 Future 在 `testWidgets` 里同样永不完成——**不报错、
  直接挂满 10 分钟**才吐一行 `TimeoutException`，看起来像「跑得慢」。
  **判据是进程 CPU 而不是等待时长**：`flutter_tester` 活着但 CPU 几乎不动，就是挂了。
  **改法**：UI 层别碰真文件——继承 `ClipFileStore` 覆写掉用到的那两个方法、只记「谁被删了」
  （`recording_settings_test.dart` 的 `_FakeClipStore` 是现成样板）；真要验文件删没删，
  用普通 `test()`。跑单文件时可以临时加 `--timeout 60s`。
- **别在 widget 测试里订阅 drift 的 `watch*` 流**：它们靠定时器驱动，FakeAsync 的假时钟不推进，
  拆解时会留下 pending timer。用 provider override 喂数据，写路径直接断言数据库。
- **`pumpPage` vs `pumpRoute` 的区别是关键**（`test/pages_widget_test.dart`）。早期测试给推入的
  二级页也套了 `Scaffold(body:)`，等于把背景和 `Material` 白送给它，于是测试全绿而真机是黑底 +
  黄色下划线。`pumpRoute` 不套 Scaffold；`expectProperlyRendered` 断言文字的
  `DefaultTextStyle.decoration` 不是下划线，并存在 `Material` 祖先。
- 带 `Timer` / 无限动画的组件（波形指示器、夜景）会让 `pumpAndSettle` 超时 → 改用显式 `pump()`。
- 手势阈值：约 18px 以下会被判定为点击，测下拉要拖够距离；sheet 的阈值是速度 > 700 或
  位移 > 面板高度 28%。
- **schema 迁移测试要用裸 DDL 把旧版本「冻成文本」**（`test/schema_migration_test.dart`），
  不要用 Dart 表类建夹具：表类会随 `app_database.dart` 一起演进，夹具会悄悄不再代表旧版本，
  用例就在迁移代码一行没跑的情况下空跑通过。夹具先写出旧版本的真实库文件、再打开当前 schema
  触发 `onUpgrade`，并配两重防空跑自检。**新增或修改迁移条件时先做变异验证**（去掉条件看用例
  是否变红），确认新用例不是空跑。

**integration_test 的坑**：动画只在推帧时前进，长按那类步骤要走 `tester.pump(100ms)` 循环而不是
`Future.delayed`；走到会话页之后**不能用 `pumpAndSettle`**（60 秒循环的夜景动画永远等不到静止）。
`binding.takeScreenshot` 在本机不可靠（`test_driver/` 那个截图 sink 因此已删——它从来没有被
调用过），巡检只负责导航并停留、截图交给外面的 `simctl` 循环；跑的时候**必须设
`NO_PROXY=127.0.0.1,localhost`**。

## 构建与网络前提

国内网络下这一节大概率用得上；干净的 CI 环境通常直连即可。

**约定：这些绕过办法一行都不要进仓库。** 不要改仓库里的 `distributionUrl`、不要写
`~/.gradle/init.d/`、不要往 `~/.zshrc` 等 shell profile 写环境变量——需要时用命令行前置的临时
变量或 `-I <临时脚本>`。**唯一例外是跨盘引起的 Kotlin 增量编译问题**：它每次 `flutter run` 都必然
复现，那两行已固化进 `android/gradle.properties` 并注明了成因（本机 pub 缓存在 `C:`、工程在
`D:`，Kotlin 增量缓存存的是源码根绝对路径，跨盘建不出公共根）。**单盘机器和 CI 上可以把那两行
连同注释一起删掉。** 同文件里的 `kotlin.jvm.target.validation.mode=warning` 是被 `tflite_flutter`
逼出来的（它写死 Java 11，Flutter 给插件默认 17），**那条依赖一旦不走了，这行跟着一起删**。

**Android 构建莫名挂住（不报错、日志不动）时，按这个顺序查**：

1. **`FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn` 漏了**——症状最阴：引擎的 ABI jar
   来自 `storage.googleapis.com`，不在任何镜像改写里，`:app:compileDebugKotlin` 会**挂住十几分钟、
   日志零输出**，极易误判成「机器慢」。**诊断杀手锏是加 `--offline`**，它把「挂住」立刻变成
   「明确告诉你缺哪个包」。
2. **Maven 依赖停滞**——`find ~/.gradle/caches/modules-2/files-2.1 -type f -newermt "-5 minutes" | wc -l`
   持续为 0 就是卡住了（Gradle daemon 挂着一批 established 连接却收不到数据）。
   临时用 `-I` 传阿里云镜像脚本，**不要写 `~/.gradle/init.d/`**。
3. **Gradle 发行包**——`services.gradle.org` 实测只有 177 KB/s 且会中途断；手工下好放进 wrapper
   的缓存目录（腾讯镜像实测 4 MB/s）。
4. **NDK 与 `platforms;android-35/36`** 都走 `dl.google.com`，实测 264 KB/s 且会下到一半截断。
   失败长相很误导：`ZipException: Archive is not a ZIP archive`，**别去查解压工具**，真实原因是
   下载被截断。判断「已装好」的可靠依据是 `platforms/android-3X/android.jar`（27 MB 上下）在不在
   ——失败的安装会留下一个只有 `.installer` 的空目录。

**iOS / macOS**：Flutter 3.47 用 Swift Package Manager 解析插件依赖，**本机实测直连即可跑通**，
代理是可选的（`127.0.0.1:7890` 终验时并没有在监听）。`sqlite3` 的构建钩子偶发 GitHub Releases
下载超时，原样重跑即过。`flutter build ios --simulator --no-codesign` 无需签名。

**国内 pub 镜像**（`PUB_HOSTED_URL` / `FLUTTER_STORAGE_BASE_URL`）**只在这个 shell 里临时设**：
`PUB_HOSTED_URL` 会把 `pubspec.lock` 里上百条 `url: "https://pub.dev"` 一并改写成镜像地址，
制造一个与依赖本身无关的巨型 diff。依赖齐了就直接 `flutter pub get`。

**两个已登记的发布阻塞项，别当成已经解决**：① `assets/noise/` 五条助眠音效的可商用授权
（来自爱给网，使用方裁定为「尚未确认、仅供个人试用」）；② `assets/model/yamnet.tflite`
这个**转换件**的许可证——模型文件内嵌元数据与上游 YAMNet 权重都是 Apache-2.0，但 MediaPipe 的
文档**没有正面声明**。两者发布前必须拿到正面声明、换掉或退回合成。

## 其他约定

- **不要改 `lib/**/*.g.dart`**（已 gitignore，由 Drift 生成）。
- 界面文案、注释、文档**一律中文**；代码标识符英文。**既有一批文件仍是英文注释**
  （`core/theme`、`core/widgets`、`core/platform`、`compass` 等处）——随改动顺手对齐即可，
  不要为了统一去批量重写。
- `analysis_options.yaml` 开了 `avoid_print`、`prefer_const_constructors`、`prefer_const_declarations`
  ——CLI 工具与巡检脚本需要 print 时用 `// ignore: avoid_print`。分析器排除
  `build/ ios/ web/ macos/ android/`。
- **设计令牌只有一份**（`core/theme/app_tokens.dart` 的 `AppTokens` 主题扩展，另有
  `AppRadii` / `AppDurations` / `AppMotion`）。颜色 / 圆角 / 动效曲线从 `AppTokens.of(context)` 取，
  **不要在 widget 里写死色值**。宽屏断点 `kWideLayoutBreakpoint = 768` 也定义在那里，
  外壳与二级页共用同一个值，不要另写常量。
- **`tool/` 下两个脚本产出的是生成物**：`generate_app_icons.dart`（iOS / macOS / Android 三套图标）
  与 `generate_noise_assets.dart`（`assets/noise/`）。**要改图标或音效就改生成器再跑一遍，
  别手改产物。**（同目录的 `analyse_clips.dart` / `eval_clips.dart` 是**复核**用的，只读、不改文件。）
- **模型权限与用户数据**：「获取可用模型」调服务商 `GET /models`：API Key 只走请求头，
  不落日志、不持久化，**错误信息也不回显响应体**（服务商可能把请求头原样引回来）。
  洞察提示词只送结构化睡眠字段，**用户自由文本 `notes` 不发送**。
