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

## 数据库

Drift + SQLite，schema v3（`schemaVersion => 3`，`onUpgrade` 在 `app_database.dart`）。
外键级联删除；`source ∈ {manual, import, demo}` 隔离演示数据。

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
- `AppHaptics` 在 macOS 桌面 / Web 上是 no-op，与原型 guarded `try/catch` 一致。
- 助眠音效是**实时合成**的（`noise_synth.dart`：22050Hz、20 秒循环、等功率接缝交叉淡化、
  按种类固定种子），不打包任何第三方音频。
