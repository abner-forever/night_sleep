# 夜深：Flutter 睡眠记录 App 项目规格说明书

> 版本：2.8（2026-09-29）
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
- **悬浮标签条**：左右下各 12px 外边距（或安全区）；圆角 34px；`blur(28px) saturate(160%)`；滑动胶囊 `accent 14%`，420ms `cubic-bezier(.22,1,.36,1)`。底部浮起量比原型的 `max(12px, env(safe-area-inset-bottom))` 低 14px，见第 8 章偏差 #21。
- **主按钮**：高 58px、圆角 16px、`linear-gradient(135deg,#0A84FF,#5856D6)`。
- **动效曲线**：标准 `cubic-bezier(.22,1,.36,1)`；回弹 `cubic-bezier(.34,1.56,.64,1)`；按压缩放 `.972`。
- **顶部渐变**（`.ios-top-fade`）：高 144px、`blur(14px)` + `saturate(125%)`，填充四段 `bg-base`
  （92% / 72% / 32% / 透明），并用 `mask-image` 收边；滚动超过 12px 后 320ms 淡入上移；
  ≥768px 与弹层打开时停用。**遮罩必须套在 `BackdropFilter` 外面**：模糊作用于「身后的画面」，
  在它子树里的遮罩管不到它，只会让填充淡出而模糊留一条硬边。
  **本版已落实**（`top_fade.dart`）：`ImageFilter` 没有内置的 saturate 构造器，本轮用一层极淡的
  accent 叠加（`alpha 0.04`）**近似**（也可用 `ColorFilter.matrix` 自行构造饱和度矩阵，经
  `ImageFilter.compose` 与 blur 合成）——与 `glass_surface.dart` 的做法一致；
  淡入时长另立 `_fadeDuration = 320ms`（`AppDurations.standard` 是 340ms 且被多处共用，
  改它会波及无关动效，故不动）。渐变的原点必须顶到**屏幕物理顶端**：外壳不再套顶部
  `SafeArea`，状态栏留白改由各页滚动视图施加（见本节「页面的横向留白与底部留白」）。
- **标签条尺寸**：内层 `min-height: 56px`（含自身 3px/2px 内边距），外层内边距 4px 6px，
  另有 1px 描边，**实测渲染高度 65px**（v2.7 的量测测试所得；此前常量写成 65.5，比实物多
  0.5px），加上浮起量 `tabBarFloat`（原型是 `max(12px, 安全区底部)`，本实现低 14px，见偏差 #21）。
  页面底部留白必须由**实际高度**推导，写死的数值一旦小于它就会让最后一行永远压在玻璃下面。
  浮起量由 `tabBarFloat` 一处出、`tabBarReserve` 与 `_TabBar` 共用：两处各算一遍时，
  单改一侧就会让留白与胶囊脱节。
- **底部模糊带**（v2.8，原型无此元素）：屏幕底部常驻一条渐变带，把滚到浮动标签条附近的内容
  模糊并淡出。高度由标签条的预留量推导——`BottomFade(height: tabBarReserve(context) + 20)`，
  iPhone 16 Pro 上 121px（胶囊顶边之上因此有 36px 的过渡段），无安全区处 113px。
  `BackdropFilter` 用与顶部带相同的 `blur(14)`，填充是 `bgBase` 从顶边 0 升到底边 **0.78**
  （比顶部带的 0.92 弱一档）。**方向与顶部带完全相反**：遮罩上透明下黑、填充上 0 下重，
  两重衰减都朝上；照抄顶部带的参数会画出「上重下轻」的逆向带且不报错。
  它在 `Stack` 里排在 `_TabBar` **之前**——`BackdropFilter` 模糊的是它之前画好的画面，
  排在后面会把玻璃胶囊本身糊掉。宽屏（≥768px）不渲染，与 `.ios-top-fade` 同规则；
  底部弹层打开时**不收起**（蒙层本来就盖住整屏）。
- **页面的横向、**顶部**与底部留白都由页面自己的滚动视图提供**（`pageGutter` / `pageTopInset`
  / `pageBottomInset`），不放在滚动视图外面。放外面时视口被压缩，留白区变成一条不透明带、
  内容在带子上方被切断；放里面时视口直达屏幕边缘，内容按设计从悬浮玻璃下穿过，最后一行
  仍能滚到玻璃之上。**顶部安全区尤其不能由外壳的 `SafeArea` 兜**：那会把整条 `.ios-top-fade`
  连同内容一起推下状态栏，渐变在状态栏那段完全缺失、却在安全区下沿以满值 alpha 起始，
  留下一条硬分界。改由 `pageTopInset` 施加后，视口顶到物理顶端，渐变才有整段 144px 可模糊。
- **字体**：系统字体（Apple 平台即 SF Pro / 苹方）；数字使用 tabular figures（对应 `.num`）。

### 2.3 图标

24×24 描边 SVG（`stroke-width` 默认 1.6、圆角端点），首页/记录/统计三个标签在选中时切换为
实心变体，设置无实心变体，改用加粗描边（2.1）。

> **数量口径（本版订正）**：旧稿写「24 个图标」，是把两个不同的数字混为一谈。
> **我们从未核实过原型图标集里到底有几个图标**——那个 24 是转述，没有出处，不要当成事实。
> 实现侧可核实的是 `lib/core/widgets/app_icons.dart` 里的**具名图标访问器**：
> 加本轮新增的 `trash` 之前是 28 个，现在是 **29 个**（另有渲染核心 `glyph` 与标签用的
> `filledTabGlyph`，二者不是独立的图标）。两者不是同一件事：实现里包含原型没有的
> （导出、垃圾桶等），不代表原型也这么多。

### 2.4 页面与组件

| 区域 | 设计内容 | 产品实现要求 |
| --- | --- | --- |
| 首页 | 圆形睡眠盘（4 同心弧）、昨夜概览、近 7 日均时、助眠音效入口、最近记录卡 | 展示最近一晚及近期趋势；无记录时明确的新增入口 |
| 记录 | 实时时长预览、日期/入睡/起床滚轮、1–5 星主观质量、四类事件开关、备注 | 时长由起止时间派生，不由用户填写；保存前校验合理性 |
| 睡眠详情 | 时长盘、阶段柱状图与占比、声音事件卡（可展开）、洞察、备注 | 仅展示确有来源的区块；缺失区块显示解释性空状态；底部提供编辑与删除入口 |
| 统计 | 7/14/30 天分段控件、时长柱状图（含 7h 目标线）、评分卡、四项汇总、梦话转录 | 平均值分母只计有记录的天数；无数据不显示虚假趋势 |
| 设置 | 外观、目标、数据导入、提醒、声音监测、洞察服务、删除数据 | 设置持久化；未接入的功能必须标注，不得伪装可用；演示数据属于开发期功能，收进独立二级页 |
| 导出页（`/settings/export`） | 原型无此页（导出为本实现新增，见偏差 #18） | 二级页：先说明将导出几条真实记录、演示记录被排除，再给 CSV（记录 + 阶段两张表）与 JSON（完整嵌套存档）两个动作，经系统分享面板交付；无记录时禁用动作并如实说明 |
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
| 导出页（原型无对应） | `lib/features/settings/presentation/export_page.dart`（`/settings/export`）；格式规则（CSV 两张表 / JSON 存档）在 `lib/features/settings/domain/sleep_export.dart`，交付在 `data/export_sharer.dart`（`share_plus`） |
| 就寝/起床提醒（原型只有装饰性开关） | `lib/core/platform/reminders.dart`（权限、时区与调度，含 `nextOccurrence` 的夏令时口径）、`lib/app/reminder_sync.dart`（启动全量重排与「偏好 → 计划」映射） |
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

### M2：提醒与本地数据导入/导出 —— 已完成（小米导入除外）

1. 就寝与起床提醒 —— **已完成**。申请通知权限前解释用途，拒绝时设置状态与实际能力一致：
   **权限被拒时不写入偏好、开关回弹**；启动时若发现偏好为真而权限已是 `denied`
   （用户在系统设置里撤销过），把偏好写回 `false`，而不是留一个说谎的开关。权限为
   `denied` 时设置页给出「去系统设置」入口。调度是**幂等全量重排**（固定 id 9001/9002
   先取消再排），每次启动重排，因此调度与偏好没有各自独立的生命周期。Android 端刻意用
   `inexactAllowWhileIdle`，不申请精确闹钟权限。
2. 本地导出 CSV / JSON —— **已完成**。CSV 两张表（记录 16 列 + 阶段 6 列，UTF-8 BOM、
   CRLF、RFC 4180 转义、按入睡时刻升序），JSON 为完整嵌套存档；经系统分享面板交付。
   两个刻意的取舍：**JSON 不写 `localUri`**（改写成 `hasLocalAudio` 布尔——音频文件本身
   不进导出，路径只会悬空，而导出是要分享出去的）、**不导出 `AppSettings`**（设备偏好跨设备
   回灌会污染，顺带把 API Key 从结构上排除）。导出只含**真实**记录，演示记录一律不进文件
   并计数说明。导入前的条数 / 重复项 / 错误项预览属于第 3 条，仍未实现。
3. 外部睡眠数据导入适配器：原始文件 → 字段校验 → 预览 → 去重 → 事务写入。
   **小米手环导入需拿到真实导出样本或官方接口文档后才实现**（见第 8 章）。

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

### 5.1 表结构（schema v3）

| 表 | 核心字段 | 约束 |
| --- | --- | --- |
| `SleepRecords` | `id`、`startAtUtc`、`endAtUtc`、`timeZoneId`、`quality`、`notes`、`tagsJson`、`source`、`flaggedSnore`/`flaggedTalk`/`flaggedRestless`/`flaggedNightmare`、`createdAt`、`updatedAt` | 时长派生不存储；质量 1–5；`source ∈ {manual, import, demo}` |
| `SleepStageSegments` | `id`、`recordId`、`stage`、`startAtUtc`、`endAtUtc`、`source` | 外键级联删除；阶段不被反推 |
| `SoundClips` | `id`、`recordId`、`kind`、`startedAtUtc`、`durationMs`、`localUri`、`transcript`、`analysis`、`analysisStatus`、`source` | 转录/分析可空；状态区分 pending / analysed / failed |
| `Insights` | `id`、`recordId`、`kind`、`content`、`provider`、`model`、`score`、`generatedAtUtc`、`status` | `recordId` 外键级联删除（schema v3 起）；仅保存真实生成结果；失败状态不作有效结论 |
| `AppSettings` | `themeMode`、`sleepGoalMinutes`、提醒开关与时间、`soundRecordingEnabled`、`onboarded`、`insightProvider`、`insightModel` | **不存 API Key** |

**v2 → v3 迁移**：`Insights.recordId` 在 v2 里没有外键，`deleteDemoData()` 因此会留下
`record_id` 指向已删记录的孤儿洞察行；重装演示数据时固定 id（`demo-N-insight`）与这些孤儿
主键冲突，异常从没有 handler 的事务里抛出（曾经连冷启动都被它打断）。v3 的迁移**先删孤儿、
再用 `alterTable` 重建 `insights` 补上 `ON DELETE CASCADE`**（顺序不可颠倒：迁移期间
`PRAGMA foreign_keys` 是关的，先重建会把孤儿原样拷进新表，让新表宣称一条自己并不满足的约束）。
因此这次升级**会自动修好已在现场损坏的库**。

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
- **本地存储：** Drift + SQLite，schema v3 带迁移，外键级联；演示数据与真实数据以 `source` 隔离。
- **分层：** `features/<feature>/presentation|domain|data`；主题、路由、数据库、平台服务在 `core/`。Widget 不直接读写数据库——`SleepRepository` 一次性组装 `SleepEntry` 聚合（3 条批量查询，非 N+1）。
- **自适应：** 按可用宽度决定布局（断点 768px），非硬编码设备类型。
- **图标：** `flutter_svg` 渲染原型原始 SVG path，不替换为近似系统图标。
- **网络：** 目前只有一处对外请求——「获取可用模型」调用服务商的 `GET /models`（`http` 包）。
  请求头携带会话内的 API Key，仅用于该请求；不写日志、不持久化，错误信息也不回显响应体
  （服务商的错误载荷可能把请求头原样引回来）。
  导出与提醒引入的四个依赖（`flutter_local_notifications` / `timezone` / `flutter_timezone` /
  `share_plus`）**都不发起网络请求**，因此这条结论不变：**应用对外的请求仍然只有「获取可用模型」一处**。
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
| 12 | 原型图标集无垃圾桶 | **本版推翻旧结论**：新画一个垃圾桶（`AppIcons.trash`，与其余访问器同形），「删除记录」与「删除全部数据」两处都用它；后者另补 `tokens.danger` 语义色的图标底板 | 旧实现**自相矛盾**：同一应用里「删除记录」严格遵守旧 #12（纯文字、无图标，`detail_sheet.dart` 还专门写了注释解释「不为此发明图标」），「删除全部数据」却借了播放控制的**「停止」方块**（`AppIcons.stop`，一个 `<rect rx="2">`）凑数——语义完全对不上，用户报的「风格不搭」正是这个矛盾。**实现侧** 28 个访问器（逐字取自原型 SVG）里不含垃圾桶/叉号/减号/清扫类，所以是**新画**，不是「启用已有」。回归方法：`test/pages_widget_test.dart` 的危险操作行用例与 `test/record_edit_delete_test.dart` 的图标身份断言——把任一调用点换回 `AppIcons.stop` 都会变红（已变异验证）。 |
| 13 | 原型为每个声音片段硬编码同一条 38 柱波形 | 演示片段有确定性包络（打鼾为缓慢起伏、梦话为断续爆发），**真实记录一律没有包络**，画等高轨道 | 演示之夜整体是合成的（阶段、转写同样是示例），且界面标注为演示、可一键清除。真实片段若要波形，只能来自解码后的文件——[SoundClip.waveformEnvelope] 为 null 时不许画形状。 |
| 14 | 原型 `data.ts` 里写死三家服务商的模型名与余额 | 不写死未经核实的模型名；DeepSeek 与 Anthropic 用**对照官方文档核实过**的 ID 并注明核实日期，OpenAI 文档不可访问故留空，改由「获取可用模型」调 `GET /models` 实时拉取 | 模型 ID 变动快于发版。一个看着合理但不存在的名字比空列表更糟：用户选中它、请求 404、还会以为是应用的问题。余额仍然不显示（偏差 #3）。 |
| 15 | 原型的时间选择器有 `wheel-selection-rail`（选中行上下各一条 1px 强调色线） | 不绘制 | 按使用方要求去掉。原型的版本是 30% accent 混入 `--border-strong` 的灰蓝色，比先前实现的纯 accent 淡得多——若要恢复，改的是颜色而不是这个元素。 |
| 16 | 原型没有应用图标文件 | 用设计原型 `index.html` 引用的 `app-icon.svg`（新月 + 两道声波），由脚本生成 iOS/macOS 全部尺寸 | 图标来自设计本身，不是自绘。生成时去掉原图的 `rx="236"` 圆角（系统会自己套遮罩）并压掉 alpha 通道（App Store 会因此拒收）。 |
| 17 | 原型的音效时长无限循环 | 每条循环 20 秒，接缝做了等功率交叉淡化 | 循环必须无缝，否则每次重播都会「咔」一声。生成器按种类固定种子，因此同一条循环每次渲染结果一致。 |
| 18 | 原型没有导出功能（纯前端演示，数据不落地） | 新增导出（`/settings/export`）：CSV 两张表（记录 + 阶段）+ JSON 完整存档，经系统分享面板交付 | 规格 M2 要求本地导出，而原型的记录只活在内存里、无导出可言。回归方法：确认设置页有「睡眠数据导出」区块（`lib/features/settings/presentation/settings_page.dart` 的 `SectionHeader('睡眠数据导出')`），且导出的 CSV 首字节是 BOM（`test/sleep_export_test.dart` 的 BOM 用例）。 |
| 19 | 原型的提醒开关是纯装饰——开关状态不驱动任何调度 | 接真实本地通知：权限被拒时**不写入偏好**、开关回弹；权限为 `denied` 时给出「去系统设置」入口；启动时回收被撤销的授权（把偏好写回 `false`） | 一个写着「开」却不会响的开关，正是规格书说的「设置状态与实际能力不一致」。回归方法：拒绝通知权限后确认 `bedtimeReminderEnabled` 仍为 `false`（`test/reminder_settings_test.dart`）；把启动回收条件改回 `!= granted` 会让 `test/reminder_sync_test.dart` 的 `unsupported` 用例变红。 |
| 20 | 原型的二次确认走 Material 默认外观（Android 观感） | 按项目令牌**自绘** iOS 风格确认弹窗（`lib/core/widgets/confirm_dialog.dart` 的 `showConfirmDialog`），**不引入 `flutter/cupertino.dart`**；应用内三处危险操作统一走它 | 整个应用是 iOS/令牌体系，唯独确认弹窗走了 Material 默认的配色与圆角。`CupertinoAlertDialog` 自带系统色与圆角，会**绕过 `AppTokens`**，与「设计令牌只有一份」的硬约定冲突，所以自绘。三处统一为：删除单条记录、删除全部本地数据、**清除演示数据**——第三处此前**根本没有二次确认**（点一下就删）。自绘走 `showGeneralDialog`，必须自己补 `Material` 祖先，否则所有 `Text` 落到黄色双下划线错误样式（`confirm_dialog.dart` 已显式补上）。回归方法：`test/confirm_dialog_test.dart`（`Material` 祖先、取消返回 `false`、破坏性取 `danger`、内容区与按钮区两条 0.5 发丝线——与全仓其余分隔线同口径）；把任一处改回 `showDialog`/`AlertDialog`，或在 `demo_data_page` 摘掉确认块，都会让对应用例变红（已变异验证）。 |
| 21 | 悬浮标签条的浮起量是 `bottom: max(12px, env(safe-area-inset-bottom))` | 改为 `max(12px, 安全区底部 − 14px)`（`app_shell.dart` 的 `tabBarFloat`）：iPhone 带 home indicator 时浮起量从 34px 收到 20px，macOS / Web 等无安全区的平台仍是 12px | 安全区底部那 34px 是留给系统手势的**整块**空间，而 home indicator 本身只画在底部 8–13px；照搬安全区会让玻璃胶囊离屏幕底边悬空一大截（用户实机上报「间距偏大」）。回收 14px 后胶囊底边高于指示条约 7px，既贴着屏幕又不压到系统部件。**浮起量与页面底部留白必须同源**（`tabBarFloat` 一处出、`tabBarReserve` 复用），否则最后一行会压进玻璃。回归方法：`test/tab_bar_inset_test.dart` 量渲染出来的胶囊矩形——把 `_tabBarFloatRelief` 改回 0，两条用例立刻变红（已变异验证）。 |
| 22 | 原型底部没有任何遮挡过渡，内容滚到标签条下方时完全清晰 | 新增一条常驻的底部模糊带（`core/widgets/bottom_fade.dart`），高度 = 标签条预留量 + 20、`blur(14)`、`bgBase` 0→78% | 原型的标签条是**悬空**在内容之上的：内容从它下面和两侧穿过去，没有任何「这里到底了」的提示，实机上读起来像内容被硬切断（用户在实机使用后提出）。原型源文件未入库，本条为**新增**而非「原型有而未实现」。**它同时是唯一一处无法靠断言判断的取舍**：带子画在胶囊之下，胶囊的 backdrop 因此会看到被洗过一遍的内容（有效 alpha 从胶囊顶边约 0.13 升到底边约 0.71），观感需人工核对——**已于 2026-09-29 目视核对**（浅色：首页滚动后 / 统计页 / 详情与助眠音效弹层；深色仅首页静置态；见 §9 视觉检查行与 README「界面巡检」）。回归方法：`test/bottom_fade_test.dart`——把遮罩方向反过来、把带子排到 `_TabBar` 之后、或把高度写死，对应用例必须变红（已变异验证）。 |

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
| 数据测试 | schema v1→v2→v3 迁移：用**真实的旧版库文件**升级。v1 段校验旧数据保留、`source` 不重置、新列默认值、新表可读写、重复打开不重跑；v2 段校验**孤儿洞察行被清除**、仍有关联的洞察保留、**`record_id` 为空的洞察存活**（含记录表为空、`IS NOT NULL` 守卫真正吃重的情形）、迁移后外键真的存在且级联生效、已损坏的库（`records=0 / insights=5`）能被修好 | ✅ `test/schema_migration_test.dart`（含防止夹具空跑的自检：夹具必须停在 v2，且 `insights` 确实不带外键） |
| 数据测试 | 演示数据**重装与幂等**：清除后重装条数一致、不留孤儿洞察、连装两次结果不变（所有写入路径 upsert） | ✅ `test/sleep_data_test.dart` |
| 数据测试 | 冷启动播种失败**不中断启动**：`installDemoSeedIfNeeded` 在写入失败时只记日志不外抛，开关关闭时连库都不查，判据是「有没有 demo 行」而非「表是否为空」 | ✅ `test/demo_seed_startup_test.dart`（含变异验证：拆掉 try/catch、把判据改成 `isEmpty` 都会变红） |
| Widget 测试 | 四页空状态与数据态、表单保存、设置写回、二次确认、二级页内边距、下拉不受裁剪 | ✅ `test/pages_widget_test.dart` |
| Widget 测试 | 分段控件胶囊与分段同宽、位移成整数倍 | ✅ `test/segmented_control_test.dart` |
| Widget 测试 | 编辑/删除：入口有无、演示数据不可编辑、表单预填、写回同一 id、不改 `createdAt`、不清空阶段、删除二次确认 | ✅ `test/record_edit_delete_test.dart` |
| 集成 | 记录卡 → 详情 → 编辑 → 保存 → 回到外壳，走真实 go_router 与 `extra` 传递 | ✅ 同上（数据经 provider 覆盖而非 drift 流） |
| 单元测试 | 合成波形：确定性、互异性、不削波、无直流、接缝连续、频谱走向、瞬态、包络、森林含鸟鸣、WAV 头与钳制 | ✅ `test/noise_synth_test.dart` |
| Widget 测试 | 助眠音效面板：播放交接、停止、切换、失败如实报错、音量写回、关闭释放 | ✅ `test/noise_sheet_test.dart` |
| 单元测试 | 导出内容：BOM 与 CRLF、RFC 4180 转义可无损还原、记录/阶段两张表、按入睡时刻升序、演示记录排除并计数、JSON 用 schema 字段名且不写 `localUri` / `AppSettings` | ✅ `test/sleep_export_test.dart` |
| Widget 测试 | 导出页：条数只数真实记录、无记录时禁用并说明、CSV/JSON 两个动作、失败如实报错、取消分享不报错 | ✅ `test/export_page_test.dart` |
| 单元/Widget 测试 | 提醒：幂等全量重排契约与固定 id、`nextOccurrence` 的夏令时口径、权限被拒时不写偏好且开关回弹、`denied` 时的「去系统设置」入口、启动回收被撤销授权、`unsupported` 时不动偏好 | ✅ `test/reminder_scheduler_test.dart`、`test/reminder_settings_test.dart`、`test/reminder_sync_test.dart` |
| 单元/Widget 测试 | 图标取色：`AppIcons.svgFor` 逐字节断言颜色写进 `stroke`、不出现黑色、不留 `currentColor`；漏传 `color` 触发断言；记录页四类事件图标在**深色下**未选中取 `textMuted`、选中取语义色 | ✅ `test/pages_widget_test.dart`（纯函数 + 记录页渲染护栏） |
| Widget 测试 | 关于卡片：文字在卡片内**水平居中**（防 `Stack` 静缩后被左锚定）、版本号取自 `PackageInfo` 而非写死常量 | ✅ `test/pages_widget_test.dart` |
| Widget 测试 | 自绘确认弹窗：有 `Material` 祖先、文字不带错误下划线、取消与点蒙层返回 `false`、破坏性操作取 `danger`、内容区与按钮区各一条分隔线、三处入口文案不变 | ✅ `test/confirm_dialog_test.dart`、`test/pages_widget_test.dart` |
| Widget 测试 | 顶部渐变带贴在**屏幕物理顶端**（不被顶部安全区推下去）；四个一级页的 `error`/`loading` 分支仍给状态栏留白 | ✅ `test/pages_widget_test.dart` |
| Widget 测试 | `PrimaryAction` 禁用态：不画顶边高光与蓝色投影、不触发触觉，但接住点击并给出**页内**提示（不走会被二级页盖住的全局 toast）；启用态观感与手感逐项不变 | ✅ `test/primary_action_test.dart` |
| Widget 测试 | 删除入口用**垃圾桶**图标（非借用的停止方块）且带 `danger` 底板——身份断言经变异验证（换回 `stop` 必红） | ✅ `test/pages_widget_test.dart`、`test/record_edit_delete_test.dart` |
| Widget 测试 | 标签条浮起量：带 home indicator 的设备上胶囊底边离屏幕底 **20pt**、无安全区 12pt、小安全区不被回收量削到下限以下；页面底部留白始终等于「浮起量 + 胶囊**实测**高度 + 16」（量渲染出的矩形，不量函数返回值） | ✅ `test/tab_bar_inset_test.dart`（含变异验证：`_tabBarFloatRelief` 归零，两条用例变红） |
| Widget 测试 | 底部模糊带：遮罩套在 `BackdropFilter` 外面（结构断言，防硬边）、模糊半径 14、填充上透明下 78% 且单调递增、遮罩方向相反、高度 = 底部预留 + 20（含无安全区的 113）、宽屏不渲染、整条带不拦手势 | ✅ `test/bottom_fade_test.dart`（含变异验证：遮罩方向反转、带子排到标签条之后、高度写死，均变红） |
| 集成/真机 | iOS/Android/macOS 核心流程；通知权限；锁屏录音与中断 | macOS 构建、iOS 模拟器构建已验证；**真机、通知投递与分享面板未验证** |
| 视觉检查 | 对照 Figma Make 四页在手机/宽屏、浅色/深色核对层级、间距、字体与安全区 | **部分**：v2.5 的巡检覆盖了四个一级页与详情/音效面板；v2.6 那一版追加确认了顶部渐变顶到物理顶端后硬分界消失（iPhone 16 Pro 模拟器，浅色/深色各一遍）。**v2.6 其余新增/改动的界面（自绘确认弹窗、垃圾桶图标、禁用按钮的页内提示、关于卡片）没有做目视核对**，只有几何/结构断言。v2.7 的标签条浮起量同样**只有几何断言**（`test/tab_bar_inset_test.dart`），没有截图核对；v2.8 的底部模糊带已在 2026-09-29 补做目视核对（iPhone 16 Pro 模拟器；浅色看过首页滚动后 / 统计页 / 睡眠详情与助眠音效弹层，**深色仅首页静置态**）：带子顶边（离屏幕底 121pt）无硬边（离带顶约 20pt 的标题处有效 wash 约 9%，越靠屏底越重）、方向为「下重上轻」（越靠近屏幕底越实）、胶囊下半部未发闷（深色下 `bgNavbar` 76% 填充主导）。**仍未逐页逐屏核对，深色覆盖面只有首页**；证据图见 `screenshots/v2.8-*.png` |

通过构建不等于录音后台能力、小米数据接入或 AI 服务已完成。

## 10. 尚需用户提供的外部资料

1. iOS Bundle ID、Android application ID、签名与发布账号（开发阶段使用占位配置）。
2. 小米睡眠数据的真实导出文件样本或官方授权接口文档。
3. 助眠音效的可商用素材及授权信息（或确认采用程序合成）。
4. 若启用 AI：服务商、模型、API 文档、计费方式，以及允许发送的数据范围。
5. 若启用自动鼾声/梦话识别：可用模型或服务、准确率目标、数据处理与隐私要求。
6. 麦克风权限的用途说明文案（需与真实用途一致，用于 `Info.plist` / manifest）。
   **通知已接入**：其用途说明是设置页里的开关与「去系统设置」入口文案，见
   `lib/core/platform/reminders.dart` 与 `settings_page.dart`（通知权限不需要 `Info.plist`
   的用途串）；麦克风的用途文案仍待提供。

缺少这些资料时可完成界面、接口与本地基础能力，但不能声明外部集成已完成。
