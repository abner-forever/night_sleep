# 架构与实现参考

本文是 `CLAUDE.md` 的配套参考，收纳「写代码时需要查、但不必每次会话都加载」的细节。
约束与产品红线留在 `CLAUDE.md`。

## 分层

`features/<feature>/{presentation,domain,data}`；主题、路由、数据库、平台服务在 `core/`。

**Widget 不直接碰数据库。** `SleepRepository.loadAll()` 用 3 条批量查询组装 `SleepEntry`
聚合（阶段 / 声音片段 / 洞察各一条，不是 N+1），派生的墙上时钟标签、醒来日归档、阶段合计
只在这一处算。UI 唯一数据源是 `sleepEntriesProvider`。

## 状态（Riverpod）

| Provider | 位置 | 说明 |
| --- | --- | --- |
| `databaseProvider` | `core/database/app_database.dart` | 默认抛错，**必须**在 `main.dart` 里 override |
| `recordsProvider` / `recordProvider(id)` | 同上 | drift 原始行的流 |
| `sleepRepositoryProvider` | `features/sleep/data/sleep_repository.dart` | |
| `sleepEntriesProvider` | 同上 | 页面观察的口子 |
| `settingsProvider` / `themeModeProvider` | `app/app.dart` | |
| `activeTabProvider` | `app/app_shell.dart` | 放 provider 而非 widget state，因为保存记录后要跳回首页 |

## 路由

`go_router`（`app/app.dart`）。四个主入口不是路由，是 `AppScaffold` 内的 tab 切换；
二级页声明为 `/` 的**子路由**，这样 push 会盖住整个外壳——设计就是这么隐藏标签条的。
编辑页的夜晚通过 `state.extra` 传快照而不是重新查库：用户点的是他看到的那个快照。

**推入的路由什么都继承不到**：没有 `Scaffold`（无背景、无 `Material` 祖先）、没有外壳留白、
没有氛围渐变。所以每个 push 页面都走 `core/widgets/subpage.dart` 的 `Subpage`。
底部弹层同理，材质祖先由 `AppSheet` 提供。

**一处例外：会话页**（`/sleep/session`）。它照样是 `/` 的子路由，但**不适合 `Subpage`**——那一页
常暗、背景是整屏夜景而不是 `Atmosphere`，共享的返回胶囊与文字颜色都取不到对的值。所以它自套
`Theme(AppTheme.dark())` + 透明 `Scaffold`，把 `Subpage` 提供的那四样（背景 / `Material` 祖先 /
`SafeArea` / 限宽）自己实现了一遍。

**2026-10-14 起它的呈现是个「从底部升起的整屏面板」**：这条路由改成了 `pageBuilder` +
`CustomTransitionPage(opaque: false)`，竖向转场，面板顶部标题行整行可下拉滑走。仍然是路由而不是
`AppSheet` 那种 dialog——理由（`context.go('/')` 不会 pop dialog 路由）写在 `app.dart` 的注释与
规格偏差 #56 里。`Subpage` 那条规则管不到它，但它仍受「路由什么都继承不到」这条约束。

**开屏页挂在 `AppScaffold` 的 `Stack` 最上层，不是路由**（`splash_screen.dart`）。冷启动约
1.6 秒，`_splashFinished` 是 State 字段而非 provider——`AppScaffold` 是 `/` 的 builder，push
子页时 State 被复用，来回跳转不会让它重播。收起条件是「时间轴播完 **且** `settings` 已读到
第一帧」（判据是 `AsyncValue.isLoading` 为假，成功与失败都算结论），否则会「先闪一下主界面
再跳出引导」。因为它在 `Stack` 里，任何 push 在其之上的路由都会盖住它——只在冷启动停在 `/`
时生效，将来若加路由恢复或 deep link 要改挂 `MaterialApp.builder`。

## 片段分析管线（v3.37 换过判定引擎）

三层，搬动任何一层之前先看清边界：

| 层 | 文件 | 能不能单测 |
| --- | --- | --- |
| **判定规则**（分 → 结论 / 弃权） | `features/sleep/domain/clip_yamnet.dart` | **能，而且是唯一能被完整测的一层**。不 import `tflite_flutter`、不碰 `dart:io`——模型在 `flutter test` 里根本加载不了 |
| **跑模型**（波形 → 分） | `features/sleep/data/yamnet_scorer.dart` | 不能。要原生库与模型文件 |
| **I/O**（读文件、起 isolate、写库） | `features/sleep/data/clip_analyzer.dart` | 注入假 `ClipScorer` 后能，且**从 isolate 那一跳开始走生产路径** |

- **判定是 YAMNet**（AudioSet 521 类，`Snoring`=38 / `Speech`=0），按**整段均分**判，
  阈值 `YamnetParams`（鼾声 0.40 / 人声 0.70）。**永不输出「杂音」**。
  2026-10-16 之前那套手写声学阈值已删除，理由见
  [specs/2026-10-14-night-clip-auto-analysis-design.md](superpowers/specs/2026-10-14-night-clip-auto-analysis-design.md) §五·补。
- **整批只起一个 isolate、只加载一次模型**（一晚约 5.3 秒，实测读数见验证记录 v3.37）。
  `ClipAnalyzer._serialised` 保证同一时刻只跑一批：`analyseRecord` 是**不 await** 地从
  会话结束与详情页两处踢出去的，撞车时两份 4 MB 模型是实打实的代价。
- **模型字节在主 isolate 读**（`rootBundle` 要走平台通道，后台 isolate 收不到），
  再跟着批处理送进 isolate。闭包捕获要当心——写 `_scorerFactory` 就是捕获 `this`，
  连数据库句柄一起被塞进消息，`SendPort.send()` 会报「object is unsendable」。
- **`measureClip` / `AudioFeatures` 还在，但不参与判定**：它们是实测特征，
  `tool/analyse_clips.dart` 拿它们给人肉眼核对。**别把它们摆进「自动判断依据」**。
- `assets/model/yamnet.tflite`（3.94 MiB）**进包也进仓库**；它的**许可证未落实**，
  是发布阻塞项，见 README「未实现」表。

## 数据库

Drift + SQLite，schema **v8**（`schemaVersion => 8`，`onUpgrade` 在 `app_database.dart`）。
外键级联删除；`source ∈ {manual, import, demo}` 隔离演示数据。

> **本文的版本号曾经停在 v3 很久**（CLAUDE.md 一直标着「落后于代码」）。这次顺手对齐到 v8，
> 但逐版细节仍以 `app_database.dart` 与 README 的迁移列表为准——那里才是每次改 schema 时
> 一定会被更新的地方。

- **v3 的关键改动**：`Insights.recordId` 补上了 `ON DELETE CASCADE` 外键（v2 里没有）。
  v2 时 `deleteDemoData()` 会留下孤儿洞察行（记录删了、洞察还在），重装演示数据时固定 id
  `demo-N-insight` 必然主键冲突，异常从没有 handler 的事务里抛出——轻则「点了没反应」，
  重则让冷启动在 `runApp` 之前抛异常。v3 的迁移**先删孤儿、再 `alterTable` 重建表**
  （顺序不可颠倒：迁移期间 `PRAGMA foreign_keys` 是关的，先重建会把孤儿拷进新表），
  因此这次升级会**自动修复已在现场损坏的库**。

- 入睡/醒来存 **UTC 瞬时值 + 录入时区**，墙上时间读取时派生 → 改系统时区不毁数据。
- 记录按**醒来所在本地日期**归档；跨午夜算一天。
- 统计平均值分母是**窗口内有记录的天数**，不是日历天数。
- `SleepRepository.save()` 的 `stages` 可空是**故意的**：`null` = 「保持已有阶段不变」。
  记录表单没有阶段字段，若不这样约定，一次无关的修正就会把设备测到的整晚阶段抹掉。
  `createdAt` 由仓库从已存行读回而非调用方传入，编辑不会改写「最初记录时间」。
- `AppSettings` **不存 API Key**（规格要求平台安全存储，尚未接入；至少不落 SQLite）。

## 实现细节备忘

- 宽屏断点 `kWideLayoutBreakpoint = 768`，定义在 `core/theme/app_tokens.dart`，路由外壳与
  二级页共用同一个值，不要另写常量。
- **设置的信息架构（v3.5）**：根页只做导航（常用 / 数据与智能 / 数据与隐私 / 关于），外观与
  「睡眠目标 + 提醒 + 声音检测」各自一个二级页。提醒的读写与调度行为与搬家前**完全一致**；
  两条产品红线逐字保留（「尚未接入录音，开关只保存偏好」、权限被拒的「去系统设置」行）。
  下拉选择器统一走 `core/widgets/app_menu_field.dart` 的 `AppMenuField`（菜单由
  `PopupMenuButton` 渲染到应用 overlay，树内会被 `GlassSurface` 的 `ClipRRect` 裁掉）。
- `AppHaptics` 在 macOS 桌面 / Web 上是 no-op，与原型 guarded `try/catch` 一致。
- 助眠音效是**打包的实景录音**（2026-10-03 起）：`assets/noise/` 下 5 条 `.m4a`
  （单声道 22.05 kHz 80 kbps，44–75 秒循环，接缝的 2 秒等功率交叉淡化在生成时烘焙进文件），
  由 `tool/generate_noise_assets.dart` 生成，`noise_player.dart` 用 `setAsset` 播放。
  **原 DSP 合成器 `noise_synth.dart` 已删除。** 素材的可商用授权**尚未落实**，
  发布前必须确认或更换——见 [specs/2026-10-03-noise-real-recordings-design.md](superpowers/specs/2026-10-03-noise-real-recordings-design.md) §3.1。
- **`lib/` 里读打包资源的只有一处**：`yamnet_scorer.dart` 的 `loadYamnetModelBytes()`
  （`rootBundle.load`）。助眠音效不走 `rootBundle`，走 `just_audio` 的 `setAsset`。
  这一处的模型字节**只能在主 isolate 读**——后台 isolate 收不到平台推来的消息。
