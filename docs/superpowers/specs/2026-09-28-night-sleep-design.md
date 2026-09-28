# 夜深：Flutter 睡眠记录 App 项目规格说明书

> 版本：2.4（2026-09-28）
> 用途：本项目的实现与验收基准。
> 设计原型：[Figma Make：睡眠记录 APP 设计](https://www.figma.com/make/hKbqp1qjtcNQmmiDtVvXpk/%E7%9D%A1%E7%9C%A0%E8%AE%B0%E5%BD%95APP%E8%AE%BE%E8%AE%A1)
> 变更史见 [CHANGELOG.md](../../../CHANGELOG.md)

## 1. 产品目标与交付原则

开发一款名为「夜深」的中文睡眠记录应用：先交付可在 iPhone / macOS 上真实使用的离线记录与统计，再兼容 Android 手机和平板。设计原型是视觉、信息架构和交互的参考；原型的 React 代码、演示睡眠数据、模拟播放、模拟 AI 余额及导入反馈均不能直接当作真实产品能力。

交付顺序遵循下面的里程碑。每个里程碑必须可运行、可验证，不为尚无数据来源的睡眠阶段、声音事件或 AI 结论编造结果。优先保证数据正确、隐私和跨端可用，再逐步补齐高级能力。

### 成功标准

- 用户可在无网络时新增、查看、编辑和删除真实睡眠记录；退出并重启后数据仍在。
- 首页和统计只基于本地真实记录计算，空数据、单条数据、跨日睡眠等场景显示正确。
- iOS 与 Android 手机可完成核心流程；平板与桌面有适配布局，不是拉伸的手机页面。
- 系统、浅色、深色三种外观模式可切换并持久化。
- 权限被拒、无网络、导入失败、录音中断等场景有清晰反馈，不丢失已有数据。
- 界面与原型最终生效层一致：玻璃材质、圆角层级、悬浮标签条 / 侧边栏、自定义图标集、滚轮选择器。

## 2. 设计基准

原型包含四个主入口：**首页、记录、统计、设置**。手机使用悬浮胶囊标签条；宽屏（≥768px）使用侧边栏，内容区最大宽度 720px。

### 2.1 令牌（取自 `index.css` 最终生效层）

| 类别 | 令牌 | 浅色 | 深色 |
| --- | --- | --- | --- |
| 背景 | `bg-base` | `#F2F2F7` | `#000000` |
| | `bg-card` | `rgba(255,255,255,.72)` | `rgba(28,28,30,.70)` |
| | `bg-card-solid` | `#FFFFFF` | `#1C1C1E` |
| | `bg-muted` | `#E9E9EF` | `#2C2C2E` |
| | `bg-navbar` | `rgba(248,248,250,.78)` | `rgba(28,28,30,.76)` |
| 文字 | `text-primary` | `#000000` | `#FFFFFF` |
| | `text-secondary` | `rgba(60,60,67,.82)` | `rgba(235,235,245,.84)` |
| | `text-muted` | `rgba(60,60,67,.58)` | `rgba(235,235,245,.56)` |
| 强调 | `accent` | `#007AFF` | `#0A84FF` |
| | `accent-violet` | `#5856D6` | `#5E5CE6` |
| | `accent-blue` | `#5AC8FA` | `#64D2FF` |
| 玻璃 | `material` | `rgba(255,255,255,.66)` | `rgba(28,28,30,.72)` |
| | `glass-border` | `rgba(255,255,255,.66)` | `rgba(255,255,255,.12)` |
| | `specular`（内高光） | `rgba(255,255,255,.70)` | `rgba(255,255,255,.12)` |
| 语义 | `danger` / `warn` / `caution` | `#E5484D` / `#E08A3C` / `#C8A93A` | `#FF6B6F` / `#F0A35C` / `#DCC55A` |
| 睡眠阶段 | 深睡 / 浅睡 / REM / 清醒 | `#5856D6` / `#5AC8FA` / `#AF52DE` / `#FF3B30` | `#5E5CE6` / `#64D2FF` / `#BF5AF2` / `#FF453A` |

### 2.2 材质与几何

- **玻璃卡片**：`backdrop-filter: blur(24px)`；填充 `--ios-material`；1px `--glass-border` 描边；内阴影 `inset 0 1px 0 var(--ios-specular)`；外阴影 `0 10px 28px rgba(32,47,86,.10)`（深色 `0 12px 30px rgba(0,0,0,.30)`）；另有 115° 斜向高光扫过。
- **圆角**：玻璃卡 `24px`；内嵌面板 `16px`；列表组 `16px`；弹层顶部 `26px`；标签条 `34px`。
- **底部弹层**：遮罩 `rgba(0,0,0,.30)` + `blur(14px)`；面板 `--sheet-bg` + `blur(38px)`；宽屏浮起 24px、宽 `min(560px, 100vw-48px)`、四角 26px。
- **悬浮标签条**：左右下各 12px 外边距（或安全区）；圆角 34px；`blur(28px) saturate(160%)`；滑动胶囊 `accent 14%`，420ms `cubic-bezier(.22,1,.36,1)`。
- **主按钮**：高 58px、圆角 16px、`linear-gradient(135deg,#0A84FF,#5856D6)`。
- **动效曲线**：标准 `cubic-bezier(.22,1,.36,1)`；回弹 `cubic-bezier(.34,1.56,.64,1)`；按压缩放 `.972`。
- **顶部渐变**（`.ios-top-fade`）：高 144px、`blur(14px) saturate(125%)`，填充四段 `bg-base`
  （92% / 72% / 32% / 透明），并用 `mask-image` 收边；滚动超过 12px 后 320ms 淡入上移；
  ≥768px 与弹层打开时停用。**遮罩必须套在 `BackdropFilter` 外面**：模糊作用于「身后的画面」，
  在它子树里的遮罩管不到它，只会让填充淡出而模糊留一条硬边。
- **标签条尺寸**：内层 `min-height: 56px`（含自身 3px/2px 内边距），外层内边距 4px 6px，
  合计约 64px，加上 `max(12px, 安全区底部)` 的浮起量。页面底部留白必须由**实际高度**推导，
  写死的数值一旦小于它就会让最后一行永远压在玻璃下面。
- **页面的横向留白与底部留白都由页面自己的滚动视图提供**（`pageGutter` / `pageBottomInset`），
  不放在滚动视图外面。放外面时视口被压缩，留白区变成一条不透明带、内容在带子上方被切断；
  放里面时视口直达屏幕边缘，内容按设计从悬浮玻璃下穿过，最后一行仍能滚到玻璃之上。
- **字体**：系统字体（Apple 平台即 SF Pro / 苹方）；数字使用 tabular figures（对应 `.num`）。

### 2.3 图标

24 个自定义 24×24 描边 SVG（`stroke-width` 默认 1.6、圆角端点）。首页/记录/统计三个标签在选中时切换为实心变体，设置无实心变体，改用加粗描边（2.1）。

### 2.4 页面与组件

| 区域 | 设计内容 | 产品实现要求 |
| --- | --- | --- |
| 首页 | 圆形睡眠盘（4 同心弧）、昨夜概览、近 7 日均时、助眠音效入口、最近记录卡 | 展示最近一晚及近期趋势；无记录时明确的新增入口 |
| 记录 | 实时时长预览、日期/入睡/起床滚轮、1–5 星主观质量、四类事件开关、备注 | 时长由起止时间派生，不由用户填写；保存前校验合理性 |
| 睡眠详情 | 时长盘、阶段柱状图与占比、声音事件卡（可展开）、洞察、备注 | 仅展示确有来源的区块；缺失区块显示解释性空状态；底部提供编辑与删除入口 |
| 统计 | 7/14/30 天分段控件、时长柱状图（含 7h 目标线）、评分卡、四项汇总、梦话转录 | 平均值分母只计有记录的天数；无数据不显示虚假趋势 |
| 设置 | 外观、目标、数据导入、提醒、声音监测、洞察服务、删除数据 | 设置持久化；未接入的功能必须标注，不得伪装可用；演示数据属于开发期功能，收进独立二级页 |
| 弹层/控件 | 滚轮选择器（44px 行高、5 行可见、吸附）、底部弹层、音量条、标签条 | 采用 Flutter 原生可访问控件或等效实现，遵守安全区域 |

## 3. 设计到代码的映射

| 设计侧 | 代码位置 |
| --- | --- |
| `:root` / `.ios-app` 令牌 | `lib/core/theme/app_tokens.dart`（`AppTokens` 主题扩展 + `AppRadii` / `AppDurations` / `AppMotion`） |
| `.glass` / `.ios-app .glass` | `lib/core/widgets/glass_surface.dart` |
| `tap-scale`、`focus-ring` | `lib/core/widgets/app_basics.dart`（`Pressable`）、`GlassSurface.onTap` |
| `ios-toggle` | `lib/core/widgets/ios_controls.dart`（`IosToggle`） |
| `ios-segmented-control` | 同上（`SegmentedControl`） |
| `ios-list-group` / `ios-list-item` | 同上（`IosListGroup` / `IosListItem` / `ListIconBadge`） |
| `sheet-overlay` / `sheet-panel` | `lib/core/widgets/app_sheet.dart`（`showAppSheet` / `AppSheet` / `SheetToolbar`） |
| `wheel-column` / `TimePicker` / `DatePicker` / `PickerSheet` | `lib/core/widgets/wheel_picker.dart` |
| `src/icons.tsx` | `lib/core/widgets/app_icons.dart`（逐字使用原 SVG path） |
| `MoonArc` | `lib/features/sleep/presentation/widgets/moon_arc.dart` |
| `AIRing` | 同上目录 `score_ring.dart` |
| `DurBar` | 同上目录 `dur_bar.dart` |
| `StageChart` / 阶段色带 / 图例 | 同上目录 `stage_chart.dart` |
| `EmptyState` / `primary-action` / 标签 | `lib/core/widgets/app_basics.dart` |
| `app-toast` | `lib/app/app_toast.dart` |
| `ios-tab-bar` / `ios-sidebar` | `lib/app/app_shell.dart` |
| 二级页外壳（返回胶囊 + 标题 + 内容列） | `lib/core/widgets/subpage.dart`（`Subpage`）；宽屏断点 `kWideLayoutBreakpoint` 与令牌同处 `app_tokens.dart`，路由外壳与二级页共用同一个值 |
| 记录编辑路由 | `lib/features/log/presentation/log_edit_page.dart`（`/log/edit`），表单本身由 `LogPage(editing:)` 复用 |
| 助眠音效（原型用 Web Audio 合成） | `lib/features/sleep/data/noise_synth.dart`（DSP 与 WAV 编码）、`noise_player.dart`（渲染缓存与播放） |
| 应用图标 | `assets/branding/app-icon.svg` → `tool/generate_app_icons.dart` → 两个平台的 `AppIcon.appiconset` |
| `SEED_RECORDS` | `lib/features/sleep/data/demo_seed.dart` |
| `estimateScore` / `estimateSummary` | `lib/features/sleep/domain/sleep_score.dart` |
| `STAGE_LBL` / `Q_LBL` / `durationColor` / `scoreColor` | `lib/features/sleep/domain/sleep_stage.dart`、`sleep_quality.dart`、`sleep_score.dart`、`presentation/widgets/stage_style.dart` |

## 4. 功能范围与分期

### M0：工程骨架与设计系统 —— 已完成

1. Flutter 工程，目标平台 iOS / macOS / Web / Android（`--platforms` 可增量添加）。
2. 四个主入口、手机标签条 / 宽屏侧边栏自适应、完整令牌与组件库、空状态、弹层、滚轮选择器。
3. 演示数据开关：`AppConfig.demoDataEnabled` 默认取 `kDebugMode`，可用 `--dart-define=DEMO_DATA=` 覆盖；演示行统一 `source = 'demo'`，可在设置中一键清除，发布构建默认关闭。
4. `README.md`：环境要求、运行命令、项目结构、当前实现范围。

**验收：** 四入口可导航；浅色/深色无溢出；`flutter analyze` 零问题；基础测试通过。

### M1：真实离线睡眠记录 —— 已完成（导入除外）

1. 新增、编辑、删除与查看睡眠记录；日期、入睡时刻、醒来时刻、主观质量 1–5、备注、四类事件标记。
2. 入睡/醒来以 UTC 瞬时值 + 录入时区保存；时长由两者派生；记录按**醒来所在本地日期**归档。
3. 校验醒来晚于入睡、时长 `0 < 时长 ≤ 24h`；删除需二次确认。
4. 首页、详情、统计读取同一数据源；统计含 7/14/30 天的平均时长、记录天数、评分与事件计数。
5. 目标时长与外观模式持久化；无记录 / 单条记录均有完整状态。
6. 编辑与删除入口位于睡眠详情弹层底部；编辑复用记录表单（`LogPage(editing:)`），以独立路由
   `/log/edit` 推入，因此编辑会话的生命周期与路由一致，标签栏在返回后原样保留。

### M2：提醒与本地数据导入/导出 —— 未开始

1. 就寝与起床提醒；申请通知权限前解释用途，拒绝时设置状态与实际能力一致。当前仅持久化偏好，**未接入通知**。
2. 本地导出 CSV / JSON；导入前预览条数、重复项与错误项。
3. 外部睡眠数据导入适配器：原始文件 → 字段校验 → 预览 → 去重 → 事务写入。**小米手环导入需拿到真实导出样本或官方接口文档后才实现**（见第 8 章）。

### M3：夜间声音与助眠音效 —— 未开始（仅 UI）

1. 用户显式开始/结束夜间录音；默认不录音。
2. 音频文件存于应用私有目录；记录路径、时长、关联记录。
3. 无验证过的分类模型时，只提供真实片段的回放与手动标注，不自动生成鼾声、梦话转写或分析。
4. 助眠音效：8 种噪音**已可在设备上合成并播放**，音量与定时已接通；失败会在面板内说明。
   尚未做的是后台播放与锁屏控制。
5. 录音保留期限与一键删除。

### M4：AI 洞察 —— 未开始

1. 在真实数据与授权前提下生成洞察；明确区分规则统计、模型推断与用户主观记录。
2. 保留服务商/模型选择概念，以实际可调用的 API 契约为准；不使用原型中的固定余额或模拟响应。
3. API Key 使用平台安全存储，**不写入 SQLite、日志、导出文件**；传输前告知数据范围并取得同意。
4. 请求失败、超时、取消与配额不足有可恢复状态。

**当前实现：** 服务商与模型选择持久化到 `AppSettings`；模型列表可由用户主动从服务商实时拉取
（见偏差 #14）；API Key 仅存于当前会话内存（安全存储未接入）；余额查询未接入。

## 5. 数据模型与计算口径

### 5.1 表结构（schema v2）

| 表 | 核心字段 | 约束 |
| --- | --- | --- |
| `SleepRecords` | `id`、`startAtUtc`、`endAtUtc`、`timeZoneId`、`quality`、`notes`、`tagsJson`、`source`、`flaggedSnore`/`flaggedTalk`/`flaggedRestless`/`flaggedNightmare`、`createdAt`、`updatedAt` | 时长派生不存储；质量 1–5；`source ∈ {manual, import, demo}` |
| `SleepStageSegments` | `id`、`recordId`、`stage`、`startAtUtc`、`endAtUtc`、`source` | 外键级联删除；阶段不被反推 |
| `SoundClips` | `id`、`recordId`、`kind`、`startedAtUtc`、`durationMs`、`localUri`、`transcript`、`analysis`、`analysisStatus`、`source` | 转录/分析可空；状态区分 pending / analysed / failed |
| `Insights` | `id`、`recordId`、`kind`、`content`、`provider`、`model`、`score`、`generatedAtUtc`、`status` | 仅保存真实生成结果；失败状态不作有效结论 |
| `AppSettings` | `themeMode`、`sleepGoalMinutes`、提醒开关与时间、`soundRecordingEnabled`、`onboarded`、`insightProvider`、`insightModel` | **不存 API Key** |

### 5.2 计算口径

- 统计以本地日历天分组；跨午夜记录按**醒来日期**计入一天。
- 平均值分母为**窗口内有记录的天数**，不是日历天数——漏记不会稀释平均。
- 目标达成天数也只对有记录的日子计数。
- 所有时长使用时间戳差值，避免夏令时转换错误。
- 阶段可见性：仅当存在真实阶段数据时绘制柱状图与占比；缺失时整块不显示。
- 本地评分（`estimateScore`）是**规则计算**，非模型推断，界面标注「本地估算」并附免责声明。
- 保存记录时 `stages` 传 `null` 表示「保持已有阶段不变」。记录表单没有阶段字段，若不这样约定，
  一次无关的修正就会把设备测到的整晚睡眠阶段抹掉。只有导入器与录音器可以替换阶段。
- 编辑写回原 `id`，`createdAt` 由仓库从已存行读回而非由调用方传入，因此「最初记录时间」不会被
  编辑改写；`updatedAt` 每次都更新。

## 6. 技术方案

- **客户端：** Flutter / Dart；基线 `Flutter 3.47.5`（stable，Dart 3.13.4）。
- **状态与路由：** Riverpod 管理状态（`sleepEntriesProvider` 是 UI 唯一数据源）；`go_router` 管理四个主入口与设置子页。
- **本地存储：** Drift + SQLite，schema v2 带迁移，外键级联；演示数据与真实数据以 `source` 隔离。
- **分层：** `features/<feature>/presentation|domain|data`；主题、路由、数据库、平台服务在 `core/`。Widget 不直接读写数据库——`SleepRepository` 一次性组装 `SleepEntry` 聚合（3 条批量查询，非 N+1）。
- **自适应：** 按可用宽度决定布局（断点 768px），非硬编码设备类型。
- **图标：** `flutter_svg` 渲染原型原始 SVG path，不替换为近似系统图标。
- **网络：** 目前只有一处对外请求——「获取可用模型」调用服务商的 `GET /models`（`http` 包）。
  请求头携带会话内的 API Key，仅用于该请求；不写日志、不持久化，错误信息也不回显响应体
  （服务商的错误载荷可能把请求头原样引回来）。
- **字体：** 系统字体 + tabular figures，不打包字体文件。

## 7. 隐私、权限与可靠性

- 睡眠记录与录音默认仅存本地；任何联网传输需明确展示数据范围并由用户主动发起。
- 麦克风、通知、文件访问只在使用相应功能时申请；未接入的能力不得申请权限。
- 提供「删除全部本地数据」及二次确认；数据库记录与关联音频一并清理（外键级联）。
- AI 洞察与声音检测不展示为医疗结论；评分与洞察均附免责说明。
- 数据库升级必须有迁移；中断后能恢复到可用状态，不留下「正在录音」的假状态。
- 遵守系统动态字体、屏幕阅读器语义、触控目标与对比度；颜色不作阶段或评分的唯一信息来源（柱状图附文字图例）。

## 8. 与原型的有意偏差

以下偏差是刻意的，均有明确理由。改动前请先读本节。

| # | 原型行为 | 本实现 | 理由 |
| --- | --- | --- | --- |
| 1 | `estimateScore` 的时长阶梯先判 `>= 6` 再判 `> 9`，导致 `> 9` 分支**永不可达**——睡 10 小时在该项得 81 分（上限 45），与紧邻注释「peaking in the 7–9h healthy band」矛盾 | 按注释意图调整判断顺序，超过 9 小时递减 | 代码与注释矛盾，注释描述了唯一合理的健康区间语义。回归方法：把 `> 9` 分支移回 `>= 6` 之前。 |
| 2 | 每个声音片段硬编码同一条 38 柱波形（原型不播放真实音频） | 有音频时画等高的中立波形轨道，无音频时显示「这段录音未保留在本地」 | 绘制一段文件未必具有的节奏等于伪造数据；规格书禁止无真实音频时出现假波形。真实包络线待音频接入后从解码结果派生。 |
| 3 | 三家服务商各带固定余额（`¥18.60` / `$12.48` / `$8.20`） | 不显示余额，按钮标注「余额查询未接入」 | 原型余额是演示值，且无服务商提供可调用的余额接口。 |
| 4 | 小米手环导入有一键「导入成功」 | 完整还原布局，但导入按钮禁用并说明缺什么 | 规格书要求拿到真实导出样本或官方接口文档后才实现，不得猜测字段或伪造成功。 |
| 5 | 助眠音效用 Web Audio 实时合成 8 种噪音 | **同样在设备上合成**（`noise_synth.dart`），渲染为 20 秒无缝循环的 WAV 后循环播放；不打包任何第三方音频 | 这是与原型最接近的实现方式，而且没有素材授权与署名负担。「没有音频时不得显示播放中」的约束仍然成立：只有播放器接受了才会切到播放态，失败会在面板内如实报错。 |
| 6 | 无记录时首页仍展示完整演示数据 | 演示数据仅在 `DEMO_DATA` 开启时安装，且首页显示「正在显示演示数据」提示条 | 规格书要求演示数据与真实数据隔离且发布构建默认关闭。 |
| 7 | 夜间录音开关看起来已生效 | 开关保存偏好，副标题写明「尚未接入录音，开关只保存偏好」 | 开关的真实能力必须与系统权限状态一致。 |
| 8 | 设置里「洞察服务」的 API Key 存 `localStorage` | 仅存内存，并提示尚未接入安全存储 | 规格书要求密钥使用平台安全存储，不得进入 SQLite / 日志 / 导出。 |
| 9 | 原型后期覆盖中关闭了动态光晕（`.liquid-orb{opacity:0}`），仅保留静态渐变背景 | 实现静态渐变，不做光晕动画 | 与原型最终生效层一致；早期液态玻璃为该文件被覆盖的历史层。 |
| 10 | 首页「昨夜睡眠」卡恒有深睡/浅睡/REM 圆环与阶段块（原型数据全部带阶段） | 圆环与阶段块**仅在该记录确有阶段数据时出现**：手动记录的卡片只有时长弧和「全程安静」等真实内容 | 手动记录没有任何阶段测量来源。若补齐阶段环，等于把用户填的时长伪造成深睡/浅睡分布。想看完整形态需要真实/导入的阶段数据，或保留演示数据。 |
| 11 | 原型没有编辑/删除入口 | 睡眠详情底部提供「编辑记录」「删除记录」，但**演示数据不提供**，改为说明可在设置中整体清除 | 演示行是唯一带真实测量的样例。改动其时长会让阶段与窗口互相矛盾，且 `source` 一旦不再是 `demo`，「清除演示数据」就再也匹配不到它——用户会得到一条既非演示、又谈不上真实的记录。 |
| 12 | 原型图标集无垃圾桶 | 删除按钮为纯文字，不画图标补齐 | 设计的 24 个图标是固定集合；自绘一个垃圾桶等于引入一套应用其余部分没有的图标语言。 |
| 13 | 原型为每个声音片段硬编码同一条 38 柱波形 | 演示片段有确定性包络（打鼾为缓慢起伏、梦话为断续爆发），**真实记录一律没有包络**，画等高轨道 | 演示之夜整体是合成的（阶段、转写同样是示例），且界面标注为演示、可一键清除。真实片段若要波形，只能来自解码后的文件——[SoundClip.waveformEnvelope] 为 null 时不许画形状。 |
| 14 | 原型 `data.ts` 里写死三家服务商的模型名与余额 | 不写死未经核实的模型名；DeepSeek 与 Anthropic 用**对照官方文档核实过**的 ID 并注明核实日期，OpenAI 文档不可访问故留空，改由「获取可用模型」调 `GET /models` 实时拉取 | 模型 ID 变动快于发版。一个看着合理但不存在的名字比空列表更糟：用户选中它、请求 404、还会以为是应用的问题。余额仍然不显示（偏差 #3）。 |
| 15 | 原型的时间选择器有 `wheel-selection-rail`（选中行上下各一条 1px 强调色线） | 不绘制 | 按使用方要求去掉。原型的版本是 30% accent 混入 `--border-strong` 的灰蓝色，比先前实现的纯 accent 淡得多——若要恢复，改的是颜色而不是这个元素。 |
| 16 | 原型没有应用图标文件 | 用设计原型 `index.html` 引用的 `app-icon.svg`（新月 + 两道声波），由脚本生成 iOS/macOS 全部尺寸 | 图标来自设计本身，不是自绘。生成时去掉原图的 `rx="236"` 圆角（系统会自己套遮罩）并压掉 alpha 通道（App Store 会因此拒收）。 |
| 17 | 原型的音效时长无限循环 | 每条循环 20 秒，接缝做了等功率交叉淡化 | 循环必须无缝，否则每次重播都会「咔」一声。生成器按种类固定种子，因此同一条循环每次渲染结果一致。 |

## 9. 测试与验收矩阵

每个里程碑至少执行 `dart format .`、`flutter analyze`、`flutter test`，并在 README 记录实际运行的设备/系统版本和未验证能力。

| 类型 | 重点场景 | 当前状态 |
| --- | --- | --- |
| 单元测试 | 跨午夜/夏令时时长、统计分母 | ✅ `test/sleep_math_test.dart` |
| 单元测试 | 模型列表解析、错误映射、密钥不外泄、无密钥不发请求、中文解码 | ✅ `test/model_catalog_test.dart` |
| Widget 测试 | 弹层蒙层独立淡入、点击把手/蒙层关闭、下拉阈值与回弹、打开计数、不可关闭时忽略手势 | ✅ `test/app_sheet_test.dart` |
| Widget 测试 | 推入路由的材质祖先与错误下划线、无阶段记录的主卡片、演示数据二级页 | ✅ `test/pages_widget_test.dart` |
| 单元测试 | `estimateScore` 边界（4/5/6/7/9/10/12 小时）、事件与质量权重、分档阈值 | ✅ `test/sleep_score_test.dart` |
| 单元测试 | `buildSleepWindow` 跨午夜与同日、时钟/日期格式化往返 | ✅ `test/sleep_window_test.dart` |
| 单元测试 | `SleepStatistics` 平均值分母、图表上下界、柱高钳制、计数口径 | ✅ `test/sleep_statistics_test.dart` |
| 数据测试 | 演示数据安装与来源标记、清除演示数据、CRUD 往返、醒来日归档、级联删除、全部删除 | ✅ `test/sleep_data_test.dart` |
| 数据测试 | schema v1→v2 迁移：用真实 v1 库文件升级，校验旧数据保留、`source` 不重置、新列默认值、新表可读写、重复打开不重跑 | ✅ `test/schema_migration_test.dart`（含防止夹具空跑的自检） |
| Widget 测试 | 四页空状态与数据态、表单保存、设置写回、二次确认、二级页内边距、下拉不受裁剪 | ✅ `test/pages_widget_test.dart` |
| Widget 测试 | 分段控件胶囊与分段同宽、位移成整数倍 | ✅ `test/segmented_control_test.dart` |
| Widget 测试 | 编辑/删除：入口有无、演示数据不可编辑、表单预填、写回同一 id、不改 `createdAt`、不清空阶段、删除二次确认 | ✅ `test/record_edit_delete_test.dart` |
| 集成 | 记录卡 → 详情 → 编辑 → 保存 → 回到外壳，走真实 go_router 与 `extra` 传递 | ✅ 同上（数据经 provider 覆盖而非 drift 流） |
| 单元测试 | 合成波形：确定性、互异性、不削波、无直流、接缝连续、频谱走向、瞬态、包络、森林含鸟鸣、WAV 头与钳制 | ✅ `test/noise_synth_test.dart` |
| Widget 测试 | 助眠音效面板：播放交接、停止、切换、失败如实报错、音量写回、关闭释放 | ✅ `test/noise_sheet_test.dart` |
| 集成/真机 | iOS/Android/macOS 核心流程；通知权限；锁屏录音与中断 | macOS 构建、iOS 模拟器构建已验证；**真机与试听未做** |
| 视觉检查 | 对照 Figma Make 四页在手机/宽屏、浅色/深色核对层级、间距、字体与安全区 | **待补**（自动化测试覆盖几何与结构，人工视觉核对未做） |

通过构建不等于录音后台能力、小米数据接入或 AI 服务已完成。

## 10. 尚需用户提供的外部资料

1. iOS Bundle ID、Android application ID、签名与发布账号（开发阶段使用占位配置）。
2. 小米睡眠数据的真实导出文件样本或官方授权接口文档。
3. 助眠音效的可商用素材及授权信息（或确认采用程序合成）。
4. 若启用 AI：服务商、模型、API 文档、计费方式，以及允许发送的数据范围。
5. 若启用自动鼾声/梦话识别：可用模型或服务、准确率目标、数据处理与隐私要求。
6. 麦克风与通知权限的用途说明文案（需与真实用途一致，用于 `Info.plist` / manifest）。

缺少这些资料时可完成界面、接口与本地基础能力，但不能声明外部集成已完成。
