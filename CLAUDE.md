# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 这是什么

「夜深」——中文、本地优先的睡眠记录 Flutter 应用（iOS / macOS 已构建；Web 有骨架、
**Android 平台目录未生成**，两者均未构建，见 README「未实现」表）。
界面按 Figma Make 原型的**最终生效层**实现。

**动手前先读 `docs/superpowers/specs/2026-09-28-night-sleep-design.md` 第 8 章「与原型的有意偏差」。**
里面 20 条都是刻意为之的，
每条附了理由和回归方法。其中「不伪造睡眠阶段 / 不画没有真实音频的波形 / 不显示读不到的余额 /
不猜小米导入字段」这几条是产品红线，不是待办：原型里这些是演示数据，规格书明令不得当真实能力实现。
`README.md` 的「未实现」表同样不要当成已完成。

新增或修改能力后，同步更新该规格（偏差表 / 测试矩阵）与 `README.md`（实现范围 / 验证记录），
版本变更记入 `CHANGELOG.md`。

新的设计规格落 `docs/superpowers/specs/`，新的实现计划落 `docs/superpowers/plans/`，
文件名一律 `YYYY-MM-DD-<topic>.md`。规格是活文档：创建时定日期，之后原地更新，不新开文件，
变更史记入 `CHANGELOG.md`。

## 常用命令

```bash
flutter pub get
dart run build_runner build     # 生成 lib/core/database/app_database.g.dart，改表结构后必跑
dart format .
flutter analyze
flutter test                     # 整套测试
flutter test test/sleep_score_test.dart                      # 单个文件
flutter test test/sleep_score_test.dart --plain-name "分档阈值"  # 单个用例（子串匹配）
flutter run -d macos
```

国内网络下的 pub 镜像、iOS / macOS 构建的网络前提与代理，以及演示数据开关 `DEMO_DATA`，
见 README「运行与生成」与「构建 iOS / macOS 的网络前提」两节。

**不要改 `lib/**/*.g.dart`**（已 gitignore，由 Drift 生成）。也不要往 `~/.zshrc` 等
shell profile 里写环境变量——需要时用命令行前置的临时变量。

## 架构

### 分层

`features/<feature>/{presentation,domain,data}`；主题、路由、数据库、平台服务在 `core/`。

**Widget 不直接碰数据库。** `SleepRepository.loadAll()` 用 3 条批量查询组装 `SleepEntry`
聚合（阶段 / 声音片段 / 洞察各一条，不是 N+1），派生的墙上时钟标签、醒来日归档、阶段合计
只在这一处算。UI 唯一数据源是 `sleepEntriesProvider`。

### 状态（Riverpod）

| Provider | 位置 | 说明 |
| --- | --- | --- |
| `databaseProvider` | `core/database/app_database.dart` | 默认抛错，**必须**在 `main.dart` 里 override |
| `recordsProvider` / `recordProvider(id)` | 同上 | drift 原始行的流 |
| `sleepRepositoryProvider` | `features/sleep/data/sleep_repository.dart` | |
| `sleepEntriesProvider` | 同上 | 页面观察的口子 |
| `settingsProvider` / `themeModeProvider` | `app/app.dart` | |
| `activeTabProvider` | `app/app_shell.dart` | 放 provider 而非 widget state，因为保存记录后要跳回首页 |

### 路由

`go_router`（`app/app.dart`）。四个主入口不是路由，是 `AppScaffold` 内的 tab 切换；
二级页声明为 `/` 的**子路由**，这样 push 会盖住整个外壳——设计就是这么隐藏标签条的。
编辑页的夜晚通过 `state.extra` 传快照而不是重新查库：用户点的是他看到的那个快照。

**推入的路由什么都继承不到**：没有 `Scaffold`（无背景、无 `Material` 祖先）、没有外壳留白、
没有氛围渐变。所以每个 push 页面都走 `core/widgets/subpage.dart` 的 `Subpage`。
底部弹层同理，材质祖先由 `AppSheet` 提供——详见下节。

### 数据库

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

## Flutter 与 CSS 语义不同——本项目反复栽在这里

这四类 bug 各犯过至少一次，`CHANGELOG.md` 里 v2.2–v2.4 的变更记录就是它们的病历：

- **`boxShadow` 写在会被自己 `ClipRRect` 裁掉的那个盒子上 → 静默丢弃。** 阴影必须放在 clip
  **外面**（`glass_surface.dart`、`app_shell.dart` 的标签条）。症状是所有卡片看起来是平的。
- **`BackdropFilter` 模糊的是它子树**之外**背后**的画面。** 想让模糊淡出，`ShaderMask` 必须
  套在 `BackdropFilter` **外面**；套在里面只淡化了填充，模糊留一条硬边（`top_fade.dart`）。
- **`Stack`（`StackFit.loose`）按最大的**非 position**子项定尺寸**，会静缩到内容大小
  （`GlassSurface` 的 `expandWidth`、`DurBar` 的 `StackFit.expand` + `Align(centerLeft)`）。
- **内容留白属于滚动视图**里面**，不是外面**（`pageGutter` / `pageBottomInset`）。放外面时
  视口被压缩，留白区变成一条盖住内容的不透明带。
- 同理，`Positioned(top: 0)` 相对的是**内边距盒**，不是内容盒——主按钮的高光因此落在
  文字中间成了一道杂线（`app_basics.dart` 的 `PrimaryAction`）。
- 底部留白必须由标签条的**实际高度**推导（`tabBarReserve`），写死的值一旦偏小，
  最后一行就永远压在玻璃下面。

**没有 `Material` 祖先的 `Text` 会落到 Flutter 的错误样式：黄色双下划线。**
`showGeneralDialog` 不像 `showDialog` 那样包 `Material`，`Subpage` 和 `AppSheet` 都已显式补上。
看到黄线先查材质祖先，别去翻主题。

## 测试注意

`integration_test/` 不参与 `flutter test`（要 `flutter drive`，见 README「界面截图巡检」）。

坑，都踩过：

- **`testWidgets` 跑在 FakeAsync 里，平台通道的 Future 永不完成**——
  `await HapticFeedback.mediumImpact()` 会挂死，症状是保存按钮卡在「保存中…」。
  用 `unawaited(...)`，或改用普通 `test()` 函数体（`tool/generate_app_icons.dart` 里的
  `vg.loadPicture` 同理）。现成测试只断言数据库状态、不断言 UI 状态时抓不到这类问题。
- **别在 widget 测试里订阅 drift 的 `watch*` 流**：它们靠定时器驱动，FakeAsync 的假时钟不推进，
  拆解时会留下 pending timer。用 provider override 喂数据，写路径直接断言数据库。
- **`pumpPage` vs `pumpRoute` 的区别是关键**（`test/pages_widget_test.dart`）。早期测试给推入的
  二级页也套了 `Scaffold(body:)`，等于把背景和 `Material` 白送给它，于是测试全绿而真机是
  黑底 + 黄色下划线。`pumpRoute` 不套 Scaffold；`expectProperlyRendered` 断言文字的
  `DefaultTextStyle.decoration` 不是下划线，并存在 `Material` 祖先。
- 测试里带 `Timer`/无限动画的组件（波形指示器）会让 `pumpAndSettle` 超时 → 改用显式 `pump()`。
- 手势阈值：约 18px 以下会被判定为点击，测下拉要拖够距离；sheet 的阈值是速度 > 700 或
  位移 > 面板高度 28%。
- **schema 迁移测试要用裸 DDL 把旧版本「冻成文本」**（`test/schema_migration_test.dart`），
  不要用 Dart 表类建夹具：表类会随 `app_database.dart` 一起演进，夹具会悄悄不再代表旧版本，
  用例就在迁移代码一行没跑的情况下空跑通过。夹具先写出旧版本的真实库文件、再打开当前 schema
  触发 `onUpgrade`，并配两重防空跑自检——夹具必须停在旧 `user_version`，且夹具的旧表 DDL 必须
  **不含**本次新加的外键（否则「约束从无到有」测不出来）。新增/修改迁移条件时，先做变异验证
  （去掉条件看用例是否变红），确认新用例不是空跑。

## 其他约定

- 界面文案、注释、文档一律中文；代码标识符英文。
- `analysis_options.yaml` 开了 `avoid_print`、`prefer_const_constructors`——CLI 工具与巡检脚本
  需要 print 时用 `// ignore: avoid_print`。分析器排除 `build/ ios/ web/ macos/`。
- 宽屏断点 `kWideLayoutBreakpoint = 768`，定义在 `core/theme/app_tokens.dart`，路由外壳与
  二级页共用同一个值，不要另写常量。
- `AppHaptics` 在 macOS 桌面 / Web 上是 no-op，与原型 guarded `try/catch` 一致。
- 设计令牌只有一份（`app_tokens.dart` 的 `AppTokens` 主题扩展）。颜色/圆角/动效曲线从
  `AppTokens.of(context)` 取，不要在 widget 里写死色值。
- 助眠音效是**实时合成**的（`noise_synth.dart`：22050Hz、20 秒循环、等功率接缝交叉淡化、
  按种类固定种子），不打包任何第三方音频。
- 「获取可用模型」调服务商 `GET /models`：API Key 只走请求头，不落日志、不持久化，
  **错误信息也不回显响应体**（服务商可能把请求头原样引回来）。
