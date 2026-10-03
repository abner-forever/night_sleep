# 夜深：Flutter 睡眠记录 App 项目规格说明书

> 版本：3.7（2026-10-03）
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
- **底部弹层**：遮罩 `rgba(0,0,0,.30)` + `blur(14px)`；面板 `--sheet-bg` + `blur(38px)`；宽屏限宽 `min(560px, 100vw-48px)`、**下沿一律贴屏幕底**、只圆上方两角 26px（原型那条「宽屏浮起 24px、四角 26px」是桌面浏览器的规则，不采用，见第 8 章 #40）。
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
| 首页 | 圆形睡眠盘（4 同心弧）、昨夜概览、近 7 日均时、助眠音效入口、最近记录卡 | 展示最近一晚及近期趋势；无记录时明确的新增入口。**v3.0 起主按钮位是会话入口**（有会话时换成「正在睡眠」卡，见偏差 #24）；**v3.3 起文案是原型的「开始入睡」，且点击只进页面、不写库**（记录起点在页内「开始睡眠」，见偏差 #39） |
| 回顾（原「记录」Tab） | 实时时长预览、日期/入睡/起床滚轮、1–5 星主观质量、四类事件开关、备注 | 「记录」Tab 改为「**回顾**」Tab（`AppTab.log` 的 id 不变、label 改）：对最近一条**真实**记录补充主观感受，可切换回顾哪一晚，**不改起止时刻**；手动录入降级为二级页 `/log/new`，入口在回顾页底部。演示记录不参与补充。见偏差 #23 |
| 会话页（`/sleep/session`） | 原型 `SleepView` 的**两个分支**都在了：**v3.2 起**照「睡眠进行中」态重建（偏差 #28–#34），**v3.3 起**补上「入睡前」态（偏差 #35–#38、#39），于是首页按钮点击即记录这条语义被推翻 | 推入式全屏页，**一个路由两态**：没有会话时是**入睡前**（晚安 / 准备好休息了吗？ / 夜景氛围 / 常用白噪音 / 白噪音·起床闹钟·鼾声三行 / 「开始睡眠」按钮，什么都不写库）；有会话时是**进行中**（8 种场景动画的夜景氛围、月亮 + `HH:MM:SS` 实时计时、当前睡眠事件卡只回显、横向长按结束按钮）。白噪音设置走深色底部弹窗（八宫格 + 音量 + 定时 15/30/45/60，默认 30），入口只在入睡前态。整页常暗（不论应用主题）。**它不测量任何东西**；会话状态进 SQLite、跨重启存活；「收起」离开页面而会话继续跑（白噪音也随之继续响） |
| 睡眠详情 | 时长盘、阶段柱状图与占比、声音事件卡（可展开）、洞察、备注 | 仅展示确有来源的区块；缺失区块显示解释性空状态；底部提供编辑与删除入口。**v3.7 起「睡眠洞察」区块常显**，并在配置了服务商 / 模型 / 密钥时给出「重新生成」（偏差 #47） |
| 统计 | 7/14/30 天分段控件、时长柱状图（含 7h 目标线）、评分卡、四项汇总、梦话转录 | 平均值分母只计有记录的天数；无数据不显示虚假趋势 |
| 设置（根页） | 常用（外观、睡眠设置、罗盘）、数据与智能（睡眠数据导入、睡眠洞察）、数据与隐私（睡眠数据导出、删除全部本地数据、演示数据、**清除缓存**）、关于 | **v3.5 起根页只做导航**：外观与「睡眠目标 / 提醒 / 声音检测」各自收进二级页，一屏放得下。**v3.7 起「关于」上方多一行「清除缓存」**，副标题显示**真实占用**（读不到就如实说读不到），点一下清掉可再生成的临时文件。设置持久化；未接入的功能必须标注，不得伪装可用；演示数据属于开发期功能，收进独立二级页。**「睡眠洞察」这一条 v3.7 起不再是纯占位**：DeepSeek 的余额查询与连通性测试都是真的（偏差 #3 / #45），其余服务商按能力表如实标注 |
| 外观（`/settings/appearance`，v3.5 新增） | 显示模式一行 + **行内下拉**（跟随系统 / 浅色 / 深色，选中项带对勾） | 写 `AppSettings.themeMode`，取值口径 `system` / `light` / `dark` 不变——换的只是控件形态（原型把它从分段控件改成了下拉菜单）。规格见[设置页 IA 与开屏页](2026-10-03-settings-ia-and-splash-design.md) |
| 睡眠设置（`/settings/sleep`，v3.5 新增） | 每晚睡眠目标（自绘滑块 5–12h、step 0.5 + 7/8/9 快捷按钮）、提醒（就寝 / 起床，开关 + 时刻 + 权限被拒行）、声音检测 | 提醒的权限处理、写库与全量重排**一字未改**，只是换了宿主页面。**录音仍未接入，副标题照旧如实标注**（偏差 #44） |
| 开屏页（v3.5 新增） | 深蓝渐变 + 月亮 logo 描线 + 星点 + 「夜深 / 听见夜晚，看见睡眠」+ 底部进度条 | 冷启动约 **1.6 秒**，播完才轮到引导页（原型的顺序与时长见偏差 #41 / #42）。它挂在 `AppScaffold` 的 `Stack` 最上层，只在冷启动停在 `/` 时生效 |
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
| `StageChart` / 阶段色带 / 图例 | 同上目录 `stage_chart.dart` |
| `EmptyState` / `primary-action` / 标签 | `lib/core/widgets/app_basics.dart` |
| `app-toast` | `lib/app/app_toast.dart` |
| `ios-tab-bar` / `ios-sidebar` | `lib/app/app_shell.dart` |
| 二级页外壳（返回胶囊 + 标题 + 内容列） | `lib/core/widgets/subpage.dart`（`Subpage`）；宽屏断点 `kWideLayoutBreakpoint` 与令牌同处 `app_tokens.dart`，路由外壳与二级页共用同一个值 |
| 设置的信息架构（v3.5 三段导航 + 两个二级页） | `lib/features/settings/presentation/settings_page.dart`（根页）、`appearance_settings_page.dart`（`/settings/appearance`）、`sleep_settings_page.dart`（`/settings/sleep`）；睡眠目标的自绘滑块在 `presentation/widgets/goal_slider.dart`，页脚小字在 `presentation/widgets/settings_footnote.dart` |
| 行内下拉选择器（`ai-select-trigger` / `appearance-select-trigger`） | `lib/core/widgets/app_menu_field.dart`（`AppMenuField`），洞察配置页与外观页共用 |
| 洞察服务的对外请求（原型无对应，v3.7） | 服务商能力表在 `lib/features/settings/data/model_catalog.dart`（`chatUri` / `balanceUri` / `supportsChat` / `supportsBalance`）；余额、连通性、生成三个请求在 `data/insight_service.dart`（`fetchProviderBalance` / `pingProvider` / `generateSummary`，都接受可注入的 `http.Client`）；提示词构造在 `lib/features/sleep/domain/insight_prompt.dart`（纯函数）；会话内密钥与测试用 client 在 `data/insight_credentials.dart` 的 `insightApiKeyProvider` 与 `insight_service.dart` 的 `insightHttpClientProvider`；落库走 `SleepRepository.saveInsight`（固定 id `'$recordId-insight'`，upsert） |
| 开屏页（原型 `SplashScreen`） | `lib/features/onboarding/presentation/splash_screen.dart`；接线在 `lib/app/app.dart` 的 `AppScaffold`（`Stack` 最上层） |
| 记录编辑路由 | `lib/features/log/presentation/log_edit_page.dart`（`/log/edit`），表单本身由 `LogPage(editing:)` 复用 |
| 助眠音效（原型用 Web Audio 合成） | `lib/features/sleep/data/noise_synth.dart`（DSP 与 WAV 编码）、`noise_player.dart`（渲染缓存与播放） |
| 导出页（原型无对应） | `lib/features/settings/presentation/export_page.dart`（`/settings/export`）；格式规则（CSV 两张表 / JSON 存档）在 `lib/features/settings/domain/sleep_export.dart`，交付在 `data/export_sharer.dart`（`share_plus`） |
| 就寝/起床提醒（原型只有装饰性开关） | `lib/core/platform/reminders.dart`（权限、时区与调度，含 `nextOccurrence` 的夏令时口径）、`lib/app/reminder_sync.dart`（启动全量重排与「偏好 → 计划」映射） |
| 会话起床闹钟（一次性，原型无对应） | `ReminderScheduler.wakeAlarmId`（9003）与 `scheduleOnce`（`lib/core/platform/reminders.dart`，**不传** `matchDateTimeComponents`）；「有无会话 → 排/取消」在 `lib/app/reminder_sync.dart` 的 `syncSessionAlarm`；投递强度文案常量 `wakeAlarmDeliveryNote` |
| 通知权限闸口（设置页与会话页共用） | `lib/app/reminder_permission.dart`（`ensureNotificationPermission`） |
| 睡眠会话页 | `lib/features/session/presentation/sleep_session_page.dart`（路由 `/sleep/session`，一个路由两态）；**入睡前态** `presentation/widgets/session_setup.dart`、共用的「收起」胶囊 `presentation/widgets/collapse_pill.dart`；长按结束按钮 `presentation/widgets/hold_to_finish_button.dart`、就地评星 `sheets/quality_rating_sheet.dart`。**日晷圆环 `widgets/wake_dial.dart` 已删**（v3.2：圆环不再显示，只有这一页用它）；旧版式的 `widgets/session_settings_section.dart` / `widgets/session_noise_section.dart` 随之删除 |
| 会话页夜景氛围与弹窗 | 页面局部令牌 `lib/features/session/presentation/night_style.dart`；场景表 `night_scene.dart`；背景 `widgets/night_backdrop.dart`；选择器 `widgets/night_scene_picker.dart`；月亮 `widgets/sleep_moon_mark.dart`；白噪音弹窗 `sheets/night_noise_sheet.dart`；事件卡 `widgets/session_events_card.dart`。**这一页不走 `AppTokens`**，理由见偏差 #32 |
| 会话状态与仓库 | 领域模型 `lib/features/sleep/domain/sleep_session.dart`；读写 `lib/features/sleep/data/session_repository.dart`（`start` / `update` / `finish` / `discard`） |
| 会话白噪音（比页面长命） | `lib/app/noise_session.dart`（`noiseSessionControllerProvider` 持有播放器与倒计时） |
| 回顾页与手动补录（原型无对应） | `lib/features/log/presentation/review_page.dart`（换一晚选择器 `review_night_picker.dart`）、`log_new_page.dart`（`/log/new`） |
| 应用图标 | `assets/branding/app-icon.svg` → `tool/generate_app_icons.dart` → 两个平台的 `AppIcon.appiconset`。**v2.9 起是两条渲染路径**：iOS 满幅直角 + 无 alpha 通道（色型 2）；macOS 按 Apple 网格烘焙圆角留白 + 保留 alpha（色型 6）。见偏差 #16 |
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
7. **手动录入降级为二级页**（v3.0）：原先的「记录」Tab 是一张手动录入表单，v3.0 起改为
   「回顾」Tab（补主观感受），手动录入搬到 `/log/new`——**这条能力没有消失**，只是不再占
   一个标签位（见偏差 #23）。

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

### M3：夜间声音与助眠音效 —— 进行中（会话页已落地；夜间录音见 plan B）

**当前进展（v3.2，2026-10-02）：**
- **已落地**：睡前入口与**睡眠会话页**（入睡前 / 进行中两态，v3.3 起）。该页 **v3.2 起照原型 `SleepView`「睡眠进行中」态
  重建**：夜景氛围（8 种场景动画）、月亮 + `HH:MM:SS`、当前睡眠事件卡四行、横向长按结束按钮、
  白噪音深色底部弹窗；一次性的**起床闹钟**与鼾声/梦话偏好开关仍在。**v3.0 的日晷圆环 / `入睡 ───
  闹钟` 行 / 白噪音展开区版式已被取代**（`wake_dial.dart` 已删），见偏差 #24 / #28–#34 与会话规格 §16。
  助眠音效（第 4 条）此前已完成。
- **仍未开始**：**夜间录音本身**（下面前 3、5 条），排成独立的一轮（plan B）。会话期间
  录不了音，界面上的「鼾声/梦话记录」开关仍只是偏好，并如实标注（偏差 #7 在 plan B 落地前
  仍然有效）。后台录音所需的 `RECORD_AUDIO` / 前台服务在 Android 平台目录生成前无从落地。

1. 用户显式开始/结束夜间录音；默认不录音。
2. 音频文件存于应用私有目录；记录路径、时长、关联记录。
3. 无验证过的分类模型时，只提供真实片段的回放与手动标注，不自动生成鼾声、梦话转写或分析。
4. 助眠音效：8 种噪音**已可在设备上合成并播放**，音量与定时已接通；失败会在面板内说明。
   尚未做的是后台播放与锁屏控制。
   > **「并播放」这三个字到 2026-10-03 才为真。** 此前这条能且只能走通「合成」那半段：
   > 临时目录在 macOS 上要先建、`AudioPlayer.play()` 不能 await，两处叠加导致选中声音后
   > 要么报 `PathNotFoundException`、要么界面停在「没选中」。两处都不是当轮引入的，而是
   > 这条路径**从来没被走过**（widget 测试用假播放器，巡检只开弹窗不选声音）。根因、修法
   > 与真机回归见会话规格 §17.7 与 `integration_test/noise_playback_test.dart`。
5. 录音保留期限与一键删除。

### M4：AI 洞察 —— 未开始

1. 在真实数据与授权前提下生成洞察；明确区分规则统计、模型推断与用户主观记录。
2. 保留服务商/模型选择概念，以实际可调用的 API 契约为准；不使用原型中的固定余额或模拟响应。
3. API Key 使用平台安全存储，**不写入 SQLite、日志、导出文件**；传输前告知数据范围并取得同意。
   **v3.7：存储这一半已完成**（系统钥匙串 + 「清除密钥」入口，见偏差 #8）；
   **「传输前告知并取得同意」这一半仍未做**——目前只有设置页那张「安全提示」卡片与
   偏差 #47 里写明的不发送备注，还没有一个在发送前逐项列出「将要发送哪些数据」的确认界面。
4. 请求失败、超时、取消与配额不足有可恢复状态。

**当前实现（v3.7）：** 服务商与模型选择持久化到 `AppSettings`；模型列表可由用户主动从服务商实时拉取
（见偏差 #14）；**DeepSeek 支持余额查询**（偏差 #3）**与连通性测试**（偏差 #45）；睡眠详情可为任意
一晚**重新生成模型总结并落库**（偏差 #47）。API Key 存**系统钥匙串**（偏差 #8），重启后仍在，
不进 `AppSettings`（那张表永远不存密钥，见 §5.1）。Claude 未接连通性与生成（偏差 #46）。
第 4 条只做到「失败有页内可读反馈、不破坏已有数据」：**取消与配额不足没有单独的状态**，
超时按失败处理。

## 5. 数据模型与计算口径

### 5.1 表结构（schema v5）

| 表 | 核心字段 | 约束 |
| --- | --- | --- |
| `SleepRecords` | `id`、`startAtUtc`、`endAtUtc`、`timeZoneId`、`quality`、`notes`、`tagsJson`、`source`、`flaggedSnore`/`flaggedTalk`/`flaggedRestless`/`flaggedNightmare`、`createdAt`、`updatedAt` | 时长派生不存储；质量 1–5 **或空**（未评分，v4 起可空）；`source ∈ {manual, import, demo, session}` |
| `SleepStageSegments` | `id`、`recordId`、`stage`、`startAtUtc`、`endAtUtc`、`source` | 外键级联删除；阶段不被反推 |
| `SoundClips` | `id`、`recordId`、`kind`、`startedAtUtc`、`durationMs`、`localUri`、`transcript`、`analysis`、`analysisStatus`、`source` | 转录/分析可空；状态区分 pending / analysed / failed |
| `Insights` | `id`、`recordId`、`kind`、`content`、`provider`、`model`、`score`、`generatedAtUtc`、`status` | `recordId` 外键级联删除（schema v3 起）；仅保存真实生成结果；失败状态不作有效结论 |
| `AppSettings` | `themeMode`、`sleepGoalMinutes`、提醒开关与时间、`soundRecordingEnabled`、`onboarded`、`insightProvider`、`insightModel` | **不存 API Key** |
| `ActiveSessions`（v4 新增；v5 加 `scene_id`） | `id`、`startAtUtc`、`timeZoneId`、`wakeMinutes`、`alarmEnabled`、`noiseId`、`noiseVolume`、`sceneId`（v5 新增，可空）、`createdAt` | **单行表**，主键固定 `'active'`（沿用 `AppSettings` 的 `id = 'default'` 约定），于是「同时两个会话」在结构上不可能。**刻意不含 `soundRecordingEnabled`**：那是跨会话偏好，唯一一份在 `AppSettings`。`sceneId` 存场景 id 字符串（与 `noiseId` 同一做法），`null` = 默认「流星夜」，读不到认识的 id 按默认处理 |

**v2 → v3 迁移**：`Insights.recordId` 在 v2 里没有外键，`deleteDemoData()` 因此会留下
`record_id` 指向已删记录的孤儿洞察行；重装演示数据时固定 id（`demo-N-insight`）与这些孤儿
主键冲突，异常从没有 handler 的事务里抛出（曾经连冷启动都被它打断）。v3 的迁移**先删孤儿、
再用 `alterTable` 重建 `insights` 补上 `ON DELETE CASCADE`**（顺序不可颠倒：迁移期间
`PRAGMA foreign_keys` 是关的，先重建会把孤儿原样拷进新表，让新表宣称一条自己并不满足的约束）。
因此这次升级**会自动修好已在现场损坏的库**。

**v3 → v4 迁移**：`onUpgrade` 新增 `if (from < 4)`，做两件事：

1. `m.createTable(activeSessions)` —— 建会话表。
2. `m.alterTable(TableMigration(sleepRecords))` —— **SQLite 不能原地改一列的可空性**，
   drift 的 `alterTable` 走的是「建新表 → 拷数据 → 删旧表 → 改名」，把 `quality` 的
   `NOT NULL` 放开。

第 2 步是本项目第一次重建一张**有子表引用它**的表（`sleepStageSegments` / `soundClips` /
`insights` 都指向 `sleepRecords`）。迁移期间 `PRAGMA foreign_keys` 是关着的（`beforeOpen`
要等迁移跑完才打开），子表里存的 `record_id` 是文本值、重建前后不变，所以改名之后引用仍然
成立——但这正是 v3 那次踩过坑的同一类位置（**顺序与开关状态**），必须有测试钉住：迁移后级联
删除仍然生效、孤儿行为与 v3 一致。没有数据回填。

**v4 → v5 迁移**：`onUpgrade` 新增 `if (from < 5)`，`active_sessions` 加一列**可空**的
`scene_id TEXT`（drift 的 `addColumn`）。既有会话行的其余字段一个不差，`scene_id` 读出来是
`null`（= 默认「流星夜」），写入新值再读回成功。可空列不需要重建表，比 v4 那次轻。

### 5.2 计算口径

- 统计以本地日历天分组；跨午夜记录按**醒来日期**计入一天。
- 平均值分母为**窗口内有记录的天数**，不是日历天数——漏记不会稀释平均。
- 目标达成天数也只对有记录的日子计数。
- 所有时长使用时间戳差值，避免夏令时转换错误。
- 阶段可见性：仅当存在真实阶段数据时绘制柱状图与占比；缺失时整块不显示。
- 本地评分（`estimateScore`）是**规则计算**，非模型推断，界面标注「本地估算」并附免责声明。
- **质量为空时不产生评分**：`quality` 为 `null`（未评分）时 `SleepEntry.scoreSource` 返回
  `none`、`score` 与 `estimatedSummary` 均为 `null`，`estimateScore` **根本不会被调用**
  （不是被喂一个假值）。统计的平均分把未评分的记录排除在**分子与分母**之外，全部未评分时
  平均分为 `null`。绝不填一个「一般」占位——那等于替用户说了一句他没说过的话。
- 保存记录时 `stages` 传 `null` 表示「保持已有阶段不变」。记录表单没有阶段字段，若不这样约定，
  一次无关的修正就会把设备测到的整晚睡眠阶段抹掉。只有导入器与录音器可以替换阶段。
- 编辑写回原 `id`，`createdAt` 由仓库从已存行读回而非由调用方传入，因此「最初记录时间」不会被
  编辑改写；`updatedAt` 每次都更新。

## 6. 技术方案

- **客户端：** Flutter / Dart；基线 `Flutter 3.47.5`（stable，Dart 3.13.4）。
- **状态与路由：** Riverpod 管理状态（`sleepEntriesProvider` 是 UI 唯一数据源）；`go_router` 管理四个主入口与设置子页。
- **本地存储：** Drift + SQLite，schema v5 带迁移，外键级联；演示数据与真实数据以 `source` 隔离。
- **分层：** `features/<feature>/presentation|domain|data`；主题、路由、数据库、平台服务在 `core/`。Widget 不直接读写数据库——`SleepRepository` 一次性组装 `SleepEntry` 聚合（3 条批量查询，非 N+1）。
- **自适应：** 按可用宽度决定布局（断点 768px），非硬编码设备类型。
- **图标：** `flutter_svg` 渲染原型原始 SVG path，不替换为近似系统图标。
- **网络：** 对外请求共 **4 处，全部由用户点击触发**，全部走 `http` 包，全部在同一处实现
  （`model_catalog.dart` / `insight_service.dart`）：
  「获取可用模型」（`GET /models`）、「连通性测试」（`POST /chat/completions`，`max_tokens: 16`）、
  「查询余额」（`GET /user/balance`，仅 DeepSeek）、「重新生成」（`POST /chat/completions`，
  JSON 模式、`max_tokens: 2048`）。四条共用同一套规矩：请求头携带钥匙串里的 API Key（偏差 #8），仅用于该请求；
  不写日志、不持久化，**错误信息也不回显响应体**（服务商的错误载荷可能把请求头原样引回来——
  实测 DeepSeek 的 401 就把 key 的掩码形式写回了响应体，这条不是假想）。
  导出、提醒与安全存储引入的依赖（`flutter_local_notifications` / `timezone` / `flutter_timezone` /
  `share_plus` / `flutter_secure_storage`）**都不发起网络请求**。**发送范围**见偏差 #47：
  只发结构化字段，不发用户备注。
- **字体：** 系统字体 + tabular figures，不打包字体文件。

## 7. 隐私、权限与可靠性

- 睡眠记录与录音默认仅存本地；任何联网传输需明确展示数据范围并由用户主动发起。
  **v3.7 起确实会联网**，四条请求全部由用户点击触发（见 §6），发送内容只有结构化字段，
  **用户备注不进提示词**（偏差 #47）。**仍欠的一步**：还没有一个界面在发送前把「将要发送哪些
  数据」逐项摆给用户看——目前只有这段规格与「安全提示」卡片在说明，正式上线前必须补上。
- 麦克风、通知、文件访问只在使用相应功能时申请；未接入的能力不得申请权限。
- **麦克风与夜间录音（plan B 用，先写着）**：录音只在用户打开会话页的录音开关后进行，
  默认不录。音频片段存于**应用私有目录**，只在本机、不上传；默认保留**最近 7 晚**，超期
  片段删除文件、但保留 `SoundClips` 行并把 `localUri` 置空（事件记录还在，详情页如实显示
  「未保留在本地」）。设置页给出当前占用与「删除全部录音」入口；「删除全部本地数据」会一并
  清掉录音。麦克风权限只在用户打开录音开关时申请，被拒则开关回弹、不写入偏好。
  **当前（2026-09-30，plan A）录音尚未接入**，这一条是 plan B 的既定口径。
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
| 3 | 三家服务商各带固定余额（`¥18.60` / `$12.48` / `$8.20`） | 原型那三个数仍然不采用；**DeepSeek 改为真实查询**（`GET /user/balance`，点「查询余额」现拉现显），OpenAI / Claude 维持「余额查询未接入」 | 原型余额是演示值。**v3.7 订正一条已被推翻的前提**：旧稿写「无服务商提供可调用的余额接口」——2026-10-03 用真实 key 实测 `https://api.deepseek.com/user/balance` 返回 200 与 `{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"…"}]}`，所以 DeepSeek 有接口可查；OpenAI / Claude 仍无公开可调用的余额接口，继续如实标注。读数**不持久化**、不画历史曲线；金额原样保留服务商给的**字符串**，不转 `double` 再格式化（否则可能显示出一个与返回值不同的数字）。回归方法：`test/insight_service_test.dart` 的 `fetchProviderBalance` 组、`test/model_catalog_test.dart` 的服务商能力组——给 Claude 填一个余额地址、或给 OpenAI 补一个没实测过的接口，都会变红。 |
| 4 | 小米手环导入有一键「导入成功」 | 完整还原布局，但导入按钮禁用并说明缺什么 | 规格书要求拿到真实导出样本或官方接口文档后才实现，不得猜测字段或伪造成功。 |
| 5 | 助眠音效用 Web Audio 实时合成 8 种噪音 | **同样在设备上合成**（`noise_synth.dart`），渲染为 20 秒无缝循环的 WAV 后循环播放；不打包任何第三方音频 | 这是与原型最接近的实现方式，而且没有素材授权与署名负担。「没有音频时不得显示播放中」的约束仍然成立：只有播放器接受了才会切到播放态，失败会在面板内如实报错。 |
| 6 | 无记录时首页仍展示完整演示数据 | 演示数据仅在 `DEMO_DATA` 开启时安装，且首页显示「正在显示演示数据」提示条 | 规格书要求演示数据与真实数据隔离且发布构建默认关闭。 |
| 7 | 夜间录音开关看起来已生效 | **plan B 落地前仍然有效**：开关保存偏好，副标题写明「尚未接入录音，开关只保存偏好」。**plan B 落地后本条作废**，录音的真实状态改由偏差 #27 描述 | 开关的真实能力必须与系统权限状态一致。录音还没接入时不能删掉这句话——删了应用就开始撒谎，那正是本条当初存在的意义。 |
| 8 | 设置里「洞察服务」的 API Key 存 `localStorage` | **v3.7 起存系统钥匙串**（`flutter_secure_storage`：iOS / macOS 钥匙串、Android Keystore），并配一个「清除密钥」入口；仍然**不进** SQLite / 日志 / 导出 | 规格书要求密钥使用平台安全存储。原型那个 `localStorage` 是明文的，还会被备份与导出带走，不能照抄。**v3.7 之前**这里写的是「仅存内存，尚未接入安全存储」——那是一个如实标注的缺口，本版补上。**macOS 上刻意关掉 data protection keychain**（`MacOsOptions(usesDataProtectionKeychain: false)`）：开着它就必须加 `keychain-access-groups` entitlement，而那个 entitlement 需要 provisioning profile，插件的 README 写明加了之后构建产物**只能在构建它的那台 Mac 上启动**；本项目没有 App Group、不跨应用共享，用不上这个能力。**代价如实记，且已在 macOS 上实测清楚**：旧版钥匙串的 ACL 绑定**应用代码签名**，而 `flutter build macos --debug` 产出的是**临时签名**（实测 `codesign -dv` 报 `Signature=adhoc`、`TeamIdentifier=not set`），其 designated requirement 就是 `cdhash`——**二进制的哈希**。于是每重新编译一次，哈希就变一次，下一次读钥匙串系统会弹一次「想要使用您存储在钥匙串的…中的机密信息」（可输密码，或点「始终允许」把新哈希加进该条目的 ACL）。**已验证**：用写入钥匙串的同一个二进制启动，不弹框；只在「写入之后又重新编译过」时才弹一次。正常使用（填一次、之后照常开关应用、不重编）不会遇到；开发期每次重建会遇到一次。要彻底免掉这条路，只能换成 data protection keychain + `keychain-access-groups`，代价见上。回归方法：`test/insight_credentials_test.dart`（内存与钥匙串同步、值没变不重复写、清空不留空串、写失败不影响本次运行）+ 平台侧钥匙串往返（**已在 macOS 上验证跨进程可读**，见 README「验证记录」）。 |
| 9 | 原型后期覆盖中关闭了动态光晕（`.liquid-orb{opacity:0}`），仅保留静态渐变背景 | 实现静态渐变，不做光晕动画 | 与原型最终生效层一致；早期液态玻璃为该文件被覆盖的历史层。 |
| 10 | 首页「昨夜睡眠」卡恒有深睡/浅睡/REM 圆环与阶段块（原型数据全部带阶段） | 圆环与阶段块**仅在该记录确有阶段数据时出现**：手动记录的卡片只有时长弧和「全程安静」等真实内容 | 手动记录没有任何阶段测量来源。若补齐阶段环，等于把用户填的时长伪造成深睡/浅睡分布。想看完整形态需要真实/导入的阶段数据，或保留演示数据。 |
| 11 | 原型没有编辑/删除入口 | 睡眠详情底部提供「编辑记录」「删除记录」，但**演示数据不提供**，改为说明可在设置中整体清除 | 演示行是唯一带真实测量的样例。改动其时长会让阶段与窗口互相矛盾，且 `source` 一旦不再是 `demo`，「清除演示数据」就再也匹配不到它——用户会得到一条既非演示、又谈不上真实的记录。 |
| 12 | 原型图标集无垃圾桶 | **本版推翻旧结论**：新画一个垃圾桶（`AppIcons.trash`，与其余访问器同形），「删除记录」与「删除全部数据」两处都用它；后者另补 `tokens.danger` 语义色的图标底板 | 旧实现**自相矛盾**：同一应用里「删除记录」严格遵守旧 #12（纯文字、无图标，`detail_sheet.dart` 还专门写了注释解释「不为此发明图标」），「删除全部数据」却借了播放控制的**「停止」方块**（`AppIcons.stop`，一个 `<rect rx="2">`）凑数——语义完全对不上，用户报的「风格不搭」正是这个矛盾。**实现侧** 28 个访问器（逐字取自原型 SVG）里不含垃圾桶/叉号/减号/清扫类，所以是**新画**，不是「启用已有」。回归方法：`test/pages_widget_test.dart` 的危险操作行用例与 `test/record_edit_delete_test.dart` 的图标身份断言——把任一调用点换回 `AppIcons.stop` 都会变红（已变异验证）。 |
| 13 | 原型为每个声音片段硬编码同一条 38 柱波形 | 演示片段有确定性包络（打鼾为缓慢起伏、梦话为断续爆发），**真实记录一律没有包络**，画等高轨道 | 演示之夜整体是合成的（阶段、转写同样是示例），且界面标注为演示、可一键清除。真实片段若要波形，只能来自解码后的文件——[SoundClip.waveformEnvelope] 为 null 时不许画形状。 |
| 14 | 原型 `data.ts` 里写死三家服务商的模型名与余额 | 不写死未经核实的模型名；DeepSeek 与 Anthropic 用**对照官方文档核实过**的 ID 并注明核实日期，OpenAI 文档不可访问故留空，改由「获取可用模型」调 `GET /models` 实时拉取 | 模型 ID 变动快于发版。一个看着合理但不存在的名字比空列表更糟：用户选中它、请求 404、还会以为是应用的问题。余额仍然不显示（偏差 #3）。 |
| 15 | 原型的时间选择器有 `wheel-selection-rail`（选中行上下各一条 1px 强调色线） | 不绘制 | 按使用方要求去掉。原型的版本是 30% accent 混入 `--border-strong` 的灰蓝色，比先前实现的纯 accent 淡得多——若要恢复，改的是颜色而不是这个元素。 |
| 16 | 原型没有应用图标文件 | 用设计原型 `index.html` 引用的 `app-icon.svg`（新月 + 两道声波），由脚本生成 iOS/macOS 全部尺寸。**v2.9 起两个平台不再共用同一份像素**：iOS 保持满幅直角 + 压掉 alpha；macOS 按 Apple 图标网格**烘焙**圆角与留白——实体 824×824 居中、四边留白 100、圆角半径 185.4——再加一层向下偏移的投影（1024 基准：偏移 `(0, 14)`、模糊 σ=10、颜色 `0x80000000`——由系统图标的 `alpha>8` 包络反推后扫参逼近，目标包络 `L84 T96 R84 B72`，本组得 `L85 T99 R85 B71`），**保留 alpha 通道** | 图标来自设计本身，不是自绘。**本版订正一条错了的前提**：旧稿写「生成时去掉原图的 `rx="236"`（iOS 和 macOS 都会自己套遮罩）」——**macOS 不会**。把系统 app 的 `.icns` 抠出来实测（Calculator、Notes 结果一致）：`alpha>128` 的实体恰为 206/256 = **0.8047**，即 Apple 网格的 824/1024，且四边留白全等——**圆角与留白是烘焙在图标文件里的**，macOS 只负责原样绘制。于是满幅直角图标在 Dock 里被撑成一个方块（用户报「为什么没有圆角」）。另需说明：「压掉 alpha」是针对 **iOS 提交**的规则（App Store 拒收带 alpha 的应用图标），macOS 的圆角图标**必须有** alpha——两条规则分平台，不冲突。**已知项**：Apple 在新系统上改了应用图标体系（改由系统套新遮罩），届时这里烘焙的圆角有被二次遮罩的可能；当前基线是 macOS 14，升级系统后需回头复核。回归方法：`test/app_icons_asset_test.dart` 的 5 条资产断言（跑在普通 `flutter test` 里，**不在生成器里**——生成器不参与 `flutter test`，放那儿只在手动重生成时才执行）——实体**自身**四角透明、中心不透明、`alpha>128` 的实体包围盒 = 824×824 且四边留白 100、实体下方有投影、圆角半径带宽、七个尺寸的文件名↔真实像素尺寸绑定与实体宽等比、iOS 图标仍满幅且无 alpha 通道；摘掉 `clipRRect`、半径改 60、删掉投影都会让断言变红（已变异验证）。 |
| 17 | 原型的音效时长无限循环 | 每条循环 20 秒，接缝做了等功率交叉淡化 | 循环必须无缝，否则每次重播都会「咔」一声。生成器按种类固定种子，因此同一条循环每次渲染结果一致。 |
| 18 | 原型没有导出功能（纯前端演示，数据不落地） | 新增导出（`/settings/export`）：CSV 两张表（记录 + 阶段）+ JSON 完整存档，经系统分享面板交付 | 规格 M2 要求本地导出，而原型的记录只活在内存里、无导出可言。回归方法：确认设置页有「睡眠数据导出」区块（`lib/features/settings/presentation/settings_page.dart` 的 `SectionHeader('睡眠数据导出')`），且导出的 CSV 首字节是 BOM（`test/sleep_export_test.dart` 的 BOM 用例）。 |
| 19 | 原型的提醒开关是纯装饰——开关状态不驱动任何调度 | 接真实本地通知：权限被拒时**不写入偏好**、开关回弹；权限为 `denied` 时给出「去系统设置」入口；启动时回收被撤销的授权（把偏好写回 `false`） | 一个写着「开」却不会响的开关，正是规格书说的「设置状态与实际能力不一致」。回归方法：拒绝通知权限后确认 `bedtimeReminderEnabled` 仍为 `false`（`test/reminder_settings_test.dart`）；把启动回收条件改回 `!= granted` 会让 `test/reminder_sync_test.dart` 的 `unsupported` 用例变红。 |
| 20 | 原型的二次确认走 Material 默认外观（Android 观感） | 用 iOS **系统组件** `CupertinoAlertDialog`（`lib/core/widgets/confirm_dialog.dart` 的 `showConfirmDialog` 内部）；应用内三处危险操作统一走它。**能接回令牌的接回令牌，接不回的系统值如实记**（见「理由」） | 整个应用是 iOS/令牌体系，唯独确认弹窗走了 Material 默认外观。**v2.6 曾按令牌自绘**（`showGeneralDialog` + `DecoratedBox` 卡片 + 手画两条 0.5 发丝线 + 手写转场），理由是 `CupertinoAlertDialog` 自带系统色与圆角会绕过 `AppTokens`。**v3.6 起按用户明确要求换成系统组件**：布局、模糊表面、圆角、`0.3` 分隔线、文字排版与 `1.3 → 1.0` 弹簧转场全部交给 SDK。代价如实记——**弹窗底色（半透明 `0xCCF2F2F2`/`0xCC2D2D2D`）、分隔线色（`CupertinoColors.separator`）、圆角不再来自 `AppTokens`**。仍接回令牌的部分：**亮度**（取 `Theme.of(context).brightness` 而非 `MediaQuery.platformBrightness`，否则用户把外观设成深色时弹窗会是浅底）、`primaryColor → tokens.accent`、两个动作的 `textStyle.color → accent/danger`（`CupertinoDialogAction.textStyle` 在系统色解析**之后**才 merge，能盖掉写死的 `systemRed`，已核对 SDK `dialog.dart:2336-2341`）、蒙层色 `tokens.overlayScrim`。**保留行为**：`barrierDismissible: true`（系统默认 `false`），因为三处调用方依赖「点蒙层 = 取消 = 返回 `false`」。三处统一为：删除单条记录、删除全部本地数据、**清除演示数据**——第三处 v2.6 前**根本没有二次确认**（点一下就删）。回归方法：`test/confirm_dialog_test.dart`——主锚是 `find.byType(CupertinoAlertDialog)`；退回任一自绘实现，「系统组件」「破坏性取 `danger`」「深色亮度跟随应用」3 条立刻变红（已变异验证），而「取消/确认/蒙层返回 `false`/`true`」「取消在左确认在右」4 条与实现无关、保持绿。 |
| 21 | 悬浮标签条的浮起量是 `bottom: max(12px, env(safe-area-inset-bottom))` | 改为 `max(12px, 安全区底部 − 14px)`（`app_shell.dart` 的 `tabBarFloat`）：iPhone 带 home indicator 时浮起量从 34px 收到 20px，macOS / Web 等无安全区的平台仍是 12px | 安全区底部那 34px 是留给系统手势的**整块**空间，而 home indicator 本身只画在底部 8–13px；照搬安全区会让玻璃胶囊离屏幕底边悬空一大截（用户实机上报「间距偏大」）。回收 14px 后胶囊底边高于指示条约 7px，既贴着屏幕又不压到系统部件。**浮起量与页面底部留白必须同源**（`tabBarFloat` 一处出、`tabBarReserve` 复用），否则最后一行会压进玻璃。回归方法：`test/tab_bar_inset_test.dart` 量渲染出来的胶囊矩形——把 `_tabBarFloatRelief` 改回 0，两条用例立刻变红（已变异验证）。 |
| 22 | 原型底部没有任何遮挡过渡，内容滚到标签条下方时完全清晰 | 新增一条常驻的底部模糊带（`core/widgets/bottom_fade.dart`），高度 = 标签条预留量 + 20、`blur(14)`、`bgBase` 0→78% | 原型的标签条是**悬空**在内容之上的：内容从它下面和两侧穿过去，没有任何「这里到底了」的提示，实机上读起来像内容被硬切断（用户在实机使用后提出）。原型源文件未入库，本条为**新增**而非「原型有而未实现」。**它同时是唯一一处无法靠断言判断的取舍**：带子画在胶囊之下，胶囊的 backdrop 因此会看到被洗过一遍的内容（有效 alpha 从胶囊顶边约 0.13 升到底边约 0.71），观感需人工核对——**已于 2026-09-29 目视核对**（浅色：首页滚动后 / 统计页 / 详情与助眠音效弹层；深色仅首页静置态；见 §9 视觉检查行与 README「界面巡检」）。回归方法：`test/bottom_fade_test.dart`——把遮罩方向反过来、把带子排到 `_TabBar` 之后、或把高度写死，对应用例必须变红（已变异验证）。 |
| 23 | 「记录」Tab 是一张手动录入表单（日期/入睡/起床滚轮 + 质量 + 事件 + 备注） | 「记录」Tab 改为「**回顾**」Tab：对最近一条**真实**记录补充主观感受；手动录入降级为二级页 `/log/new`，入口在回顾页底部 | 手动录入假设用户记得住昨晚的入睡时刻，而那正是睡前那一刻才有的信息。改由「开始睡眠」在睡前采集起点后，录入表单的职责就只剩下「补上忘记录的那一晚」，不该再占一个标签位。**手动补录这条能力没有消失**，只是换了入口层级。 |
| 24 | 原型没有独立的会话页（它的 `SleepView` 是首页里的一个模态） | 新增：首页主按钮 → 全屏会话页（路由 `/sleep/session`），会话状态存 SQLite，跨重启存活。**v3.2 起该页照原型 `SleepView`「睡眠进行中」态重建**，**v3.3 起连「入睡前」态一起做**（见偏差 #28–#34 与会话规格 §16、#35–#39 与 §17）；v3.0 的「日晷圆环 / 白噪音展开区 / 起床闹钟 / 鼾声梦话开关」版式**已被取代**（`wake_dial.dart` 已删） | 用户明确提出的新能力：会话要跨页面、跨重启活着（原型那个模态做不到），所以做成独立路由。**它不测量任何东西**：显示的时长与时刻都来自用户自己按下的时刻与设定的闹钟，不是推断。 |
| 25 | 原型没有闹钟（提醒开关是纯装饰，见偏差 #19） | 起床闹钟接真实本地通知（新 id 9003，**一次性**排定，与日常重复提醒共用调度器但不同 API），iOS **请求** `timeSensitive`（但工程缺配套的 Time Sensitive Notifications entitlement，按当前产物该级别会被系统降级）、Android 用 `inexactAllowWhileIdle`，界面注明强度不如系统闹钟 | 与 #19 同一条理由：一个写着「开」却不会响的开关是规格书禁止的。不用 `critical` / 精确闹钟权限是**刻意的取舍**，且必须写在界面上，否则用户会以为它和系统闹钟一样强。**未验证**：真机到点投递未实测；`timeSensitive` 因缺 entitlement 当前并不能穿透专注模式（见 README「验证记录」）。 |
| 26 | 原型的主观质量是 1–5 的必填档，无「未评分」态；记录表单默认选中「良好」 | `quality` 改为**可空**（schema v4 重建表放开 `NOT NULL`）。表单初始**无选中**；不选就不写质量，记录**没有评分**（`scoreSource` 为 `none`），统计的平均分把它排除。会话结束时就地评一次星，可跳过 | 「默认选中良好」是应用替用户说了一句他没说过的话，并且让 `estimateScore` 里 35 分权重的质量项凭空拿到 17.5 分。这条与偏差 #3「不显示读不到的余额」、#7「开关不得声称没有的能力」同源：**没有的东西就显示为没有**。代价是一次表重建，回归方法见 §5.1 与 §9 的迁移行。 |
| 27 | 原型的声音片段是演示数据，波形是每条硬编码的同一条 38 柱形状（见偏差 #2、#13） | **plan B 起改写真录音**：会话期间按振幅切片，一条片段一个文件进 `SoundClips`；片段**不自动分类**，由用户听过之后标注；`kind` 初值 `noise`，界面显示为「待标注」。振幅序列即该片段的**实测包络**，可以画真实波形。**当前（plan A）尚未落地** | 用户要求真实录音。不自动分类是因为项目没有、也没有验证过任何分类模型，M3 第 3 条明令此时只提供回放与手动标注。**#2 的规则不变、结论变了**：以前真实录音没有包络所以不画形状，现在包络是测出来的，就可以画——「没有测量就不画」这条一字未改。 |
| 28 | 原型的「睡眠进行中」态**没有任何退出入口**——它是个占满全屏的模态，只有「长按结束睡眠」一条路 | 左上角保留**「收起」胶囊**（沿用原型 setup 态 `sleep-navigation-back` 的样式），`pop()` 回应用而**会话继续跑** | 我们的会话是持久化实体，收起后还在跑（首页显示「正在睡眠」卡）。照搬模态就等于砍掉「收起」这条既有能力：用户想边睡边看别的，只能结束会话 |
| 29 | 未选白噪音时，「当前睡眠事件」卡里那一行**整个不渲染** | **（v3.3 撤销，改为照原型）** 只在真有声音在放时渲染，且不再可点——设置入口搬进入睡前态 | 当初的前提是「我们没有 setup 态」。v3.3 补上入睡前态之后这条理由消失了（会话规格 §17.4） |
| 30 | 「起床闹钟」那一行只是展示（`07:30 起床闹钟` + 状态字），改时刻在 setup 态 | **（v3.3 撤销，改为照原型）** 只在闹钟开着（或已经睡过头）时渲染，右侧只写「已设置」；**副标题与投递强度标注原样保留** | 同 #29。保留副标题是因为「已超过起床时间 · 请手动结束睡眠」是这一屏唯一会告诉睡过头的人怎么做的一句话，没设闹钟就把它一起藏掉是能力倒退 |
| 31 | 「鼾声检测」行右侧是一个**状态点**，副标题写「正在聆听睡眠声音」 | 右侧仍是**开关**，副标题维持「尚未接入录音，开关只保存偏好。」 | plan A 没接录音（偏差 #7 是产品红线）。「正在聆听」是一句当场就假的话——状态点没有任何真实状态可显示，只能显示一个我们并不具备的能力 |
| 32 | 原型是一份全局 `index.css`，`.sleep-mode` 的暗色变量与 `.glass` 等材质同处一层，改一处全站跟着变 | 会话页的材质与调色板收进**页面局部**的 `night_style.dart`，`AppTokens` 一个字节不动 | **2026-10-03 订正一条错前提**：原型确实一度把全站换成扁平原生风（`.glass` 不再模糊/描边/投影、底色改 `#f4f5f8`、主按钮改纯色），但**那一层在最终生效层里又被推翻**——末层的 `.ios-app .glass` / `.ios-list-group` / `.primary-action` / `.ios-navigation-back` 都还原成玻璃材质与 `#0A84FF→#5856D6`，`:root` 最终值是 `--bg-base: #f2f2f7` / `#000000`，与本项目 `AppTokens` **逐值一致**。所以「`AppTokens` 不动」不是因为令牌过时，而是因为**令牌本来就是对的**；会话页之所以仍用页面局部常量，是因为它整夜挂在暗色场景里、与主题无关。约定不破：**一个概念仍只有一处**，只是这一处落在这一页 |
| 33 | 原型的白噪音事件行有**三态**：未开启 / 播放中 / 已停止 | 「当前睡眠事件」卡里的白噪音行**只有「在放」这一态**（v3.3 起：没在放整行不渲染，与原型一致），刻意不做「已停止」 | 控制器的 `noiseId` 语义就是「选中**并正在播放**」——冷启动对账正是靠这条语义清掉假值。于是「播完」与「从未选过」在界面上本就不可区分，再画一个「已停止」就是在显示一个我们并未追踪的状态。同源于偏差 #3 / #7：**没有的东西就显示为没有** |
| 35 | 入睡前态的鼾声行副标题是「仅在本机识别并保存声音片段」 | 维持「尚未接入录音，开关只保存偏好。」 | plan A 没接录音（#7 是产品红线）。原型那句话**宣称的识别能力并不存在**，是我们不能说的话。同源于 #31 |
| 36 | 入睡前态默认：鼾声**开**、起床闹钟**开**且 `07:30` | 鼾声取 `AppSettings.soundRecordingEnabled`（默认关）；闹钟默认**关**，时刻取设置里的起床提醒时刻，没设过则是 `07:00` | 替用户排一个他从没设过的真实通知、或默认打开一个我们并不具备的能力，都是「没有的东西显示成有」（#3 / #7 同源）。原型那两个默认值是演示数据的形状，不是产品裁定 |
| 37 | 入睡前态的四格「常用白噪音」点选**不**试听，「完整设置」里点选才试听 | 两处都即选即播；收起页面（离开入睡前态）会停掉试听 | 控制器的语义就是「选中**并正在播放**」（#33 同一条），再做一套「只选中不出声」的状态等于多一个真源。原型的 setup 分支卸载时也 `stop()` |
| 38 | 入睡前态的播放时长有「整晚」 | 仍只有 15 / 30 / 45 / 60 | 既有裁定（会话规格 §四 / §六）：整晚的噪音会一直占着录音通道，plan B 之后更是硬冲突 |
| 39 | 首页主按钮「**开始入睡**」点下去就进入睡眠模式，进页面还没开始记（要点页内的「开始睡眠」） | **照原型**：主按钮只推入页面、**不写库**，`startAtUtc` 是页内「开始睡眠」被按下的时刻 | 这是本轮的核心改动，不是偏离原型而是**回到原型**——v3.0 把它简化成「点首页即开始」，等于把「按错了」「进来看一眼」都记成了一晚睡眠。副标题一处例外：原型写「开启睡眠记录、**鼾声检测**与白噪音」，我们写「开启睡眠记录、白噪音与夜景氛围」——plan A 没接录音（#7），不能把「鼾声检测」写进这句承诺 |
| 34 | 原型激活态的 `.sleep-events` 有 `backdrop-filter: blur(18px)` | 「当前睡眠事件」卡**不叠 `backdrop-filter`**，用半透明深色底 + 描边 | 这一页底下是每帧重绘的整屏动画背景，卡片上再叠一层 `backdrop-filter` 会让该区域**每帧重新模糊**；而这一页要整夜挂着，代价不划算。这是带着理由的取舍，不是漏做。观感未在真机核对（见 README「验证记录」） |
| 40 | 底部弹层宽屏时**浮起 24px**、四角 26px（`.sheet-panel` 的桌面规则） | **下沿一律贴屏幕底**，只圆上方两角；宽屏仍限宽 560px | 桌面规则照搬到 iPad 横屏上，面板与屏幕底之间会留出一条遮罩，面板像是悬空断在屏幕底之上——使用方实测后裁定（同一次实测还发现音效格按屏幕宽度算宽，宽屏下每格 271px 撑爆面板，见 `noise_sheet.dart`）。iPhone 本来就贴底，两平台现在一致。回归方法：`test/app_sheet_test.dart` 的「宽屏下面板限宽 560，但下沿仍贴屏幕底」——把浮起加回去必红（已变异验证：还原后 810 ≠ 834）。 |
| 41 | 开屏页与引导页的 `z-index` **同为 200**，而引导页在 DOM 里更靠后——首次启动时引导页把开屏**整个盖住**，那屏开屏等于没播 | **先开屏、后引导**：开屏播完才渲染引导页 | 原型的层叠疏漏，显然的意图是先给品牌、再给引导。回归方法：`test/splash_screen_test.dart` 的「开屏排在引导页之前，播完才轮到引导页」——把开屏排到引导页前面必红 |
| 42 | 开屏 3.2 秒，且整屏在开头 8% 从透明淡入 | **1.6 秒**；整屏从第一帧就不透明，只在最后 12% 淡出 | 原型那 3.2 秒是网页首屏加载的遮盖，而原生应用在它之前已有系统启动图，照抄等于每次冷启动白等 3 秒（使用方裁定）。淡入那一段是给「往已渲染好的网页上叠一层」用的，照抄会变成「先闪一下浅色界面再变深」，所以只保留收尾的淡出。回归方法：`test/splash_screen_test.dart` 逐条断言播完回调与收起时机 |
| 43 | 设置根页只有五条（外观 / 睡眠设置 / 睡眠数据导入 / 睡眠洞察 / 关于） | 另保留五条：**睡眠数据导出**（偏差 #18）、**删除全部本地数据**（§7）、**演示数据**（调试构建）、**清除缓存**（v3.7）、**罗盘**（本实现既有），并为此新增「数据与隐私」分组 | 原型是纯前端演示、数据不落地，所以既没有导出、也没有可清的缓存；我们有真实库与真实的临时文件，这几条是硬要求。罗盘并入「常用」。**「清除缓存」的边界必须只有一个语义**：它只删 `getTemporaryDirectory()` 下**可再生成的临时文件**（白噪音的 8 个 WAV 循环、导出时写给分享面板的副本），**不碰**记录 / 录音 / 数据库（那是「删除全部本地数据」）与钥匙串里的 API Key（那是设置页的「清除密钥」）。所以它在界面上必须**显示真实占用**，读不到就说读不到，绝不显示一个编出来的 `0 B`。回归方法：`test/pages_widget_test.dart` 的「根页只剩三段导航行，控件都收进了二级页」逐条点名这五行，并断言外观 / 提醒 / 声音检测的控件**不在**根页；`test/app_cache_test.dart` 用真实文件系统钉删除与统计的语义 |
| 44 | 新版原型里声音检测的副标题写「检测打鼾、梦话并生成洞察」 | 维持「**尚未接入录音，开关只保存偏好**」 | 与 #7 / #31 同源：录音**仍未接入**，照抄那句话等于让应用当场宣称一个它没有的能力。回归方法：`test/pages_widget_test.dart` 的「睡眠设置页把提醒与声音检测都收在一起，并保留两条红线」——把它换回原型文案必红（已变异验证） |
| 45 | 原型没有连通性测试 | 新增「连通性测试」：用**当前服务商 + 当前模型**发一次 `max_tokens: 16` 的真实对话请求，判定是「200 且返回了补全结构」，**正文为空也算连通** | 「获取可用模型」只证明了 key 能列模型，证明不了所选模型真的能被调用。判定**不能**要求 `content` 非空：实测 `deepseek-flash` 是推理模型，16 token 预算下正文全落在 `reasoning_content`、`content` 是空串且 `finish_reason: length`——按「必须有正文」判定会把一把好钥匙报成坏钥匙。界面成功文案因此也写明这层含义。回归方法：`test/insight_service_test.dart` 的 `pingProvider` 组（含「推理模型正文为空仍算连通」一条）。变异验证：把判定改成要求非空正文，该条立刻变红。 |
| 46 | 原型三家服务商一视同仁 | DeepSeek 与 OpenAI 共用同一条 OpenAI 兼容的请求路径；**Claude 不接连通性测试、也不接生成**——界面上根本没有那两个按钮 | Anthropic 的 Messages API 请求体与响应体形状都与 OpenAI 兼容协议不同，而手边没有可实测的 key。本项目对没跑过的外部契约一贯是不写（同 #4「不猜小米导入字段」）。做法是能力表里留 `chatUri` / `balanceUri` 为 `null`，由它统一决定按钮出不出——这是**有理由的缺省，不是漏做**。回归方法：`test/model_catalog_test.dart` 服务商能力组里 Claude 四条 `isFalse` / `isNull` 断言。 |
| 47 | 原型没有生成入口 | 睡眠详情「睡眠洞察」区块**常显**并给出「重新生成」，**所有记录都给**（演示与真实都可）。模型走 JSON 模式返回 `{score, summary}`；**失败只在页内报错，不写库、不覆盖已有洞察**；失败不落 `failed` 行 | 最需要这个入口的恰恰是「这一晚还没有洞察」的记录，所以区块不能再是「有内容才渲染」。失败不覆盖是同一条红线（#3 / #7「没有的东西显示为没有」）的延伸：一次网络抖动不该把用户手里的结论抹掉。**数据范围**：提示词只含日期、入睡/起床、时长、主观质量、用户自己标记的不适、设备测到的阶段占比与声音事件计数；**用户自由文本 `notes` 不发送**——它是唯一可能装着任意内容的字段，而本轮还没有让用户看过「哪些数据会离开设备」的界面，少发一点比多发一点稳妥。**一条同源的既有缺陷一并修掉**：`SleepEntry.scoreSource` 此前只看 `isUsable`，于是「模型写了总结但没给分」的洞察会把评分整个吞掉（模型分为空、本地估算又轮不到，详情页评分环凭空消失）；现改为**只有带回评分的洞察才顶掉本地估算**。回归方法：`test/insight_prompt_test.dart`（备注不得出现、未评分不得填占位）、`test/sleep_insight_test.dart`（失败不覆盖、评分回退）。变异验证：把 `scoreSource` 改回只看 `isUsable`，「模型没给分时回退到本地估算」立刻变红。**实机复测后补修一条**：`insightProvider` / `insightModel` 在全新安装时**本来就是 `null`**（DeepSeek 与其内置模型只是设置页**显示的**默认值），详情页读裸列便判成「未配置」，把按钮换成了「去配置」提示——一个已经填好 key、余额与连通性都跑通的用户因此看不到入口。现统一走 `resolveInsightSelection()`（`model_catalog.dart`）：**同一份默认值解析，配置页与详情页共用**，两处不会再对「选中的是哪个模型」有不同说法；被挡住时的提示也改为**指名差的是哪一样**。回归用例：`test/sleep_insight_test.dart` 的「全新安装（provider / model 都还是 null）也照样给按钮」。 |

## 9. 测试与验收矩阵

每个里程碑至少执行 `dart format .`、`flutter analyze`、`flutter test`，并在 README 记录实际运行的设备/系统版本和未验证能力。

| 类型 | 重点场景 | 当前状态 |
| --- | --- | --- |
| 单元测试 | 跨午夜/夏令时时长、统计分母 | ✅ `test/sleep_math_test.dart` |
| 单元测试 | 模型列表解析、错误映射、密钥不外泄、无密钥不发请求、中文解码；**服务商能力表（v3.7）**：只有实测过的服务商才拿到余额 / 对话地址，Claude 两个都是 `null` | ✅ `test/model_catalog_test.dart` |
| 单元测试 | **洞察服务（v3.7）**：余额解析（币种、金额原样保留字符串、`is_available:false`、未知币种不猜符号、结构不对时给可读失败）、没有余额接口的服务商**不发请求**；连通性（200 + **空正文**算通、「200 但无补全结构」不算通、401 文案、**响应体里带着 key 时失败文案一个字都不带出来**）；生成（请求体带 `max_tokens: 2048` 与 `response_format: json_object`、评分越界置 null、非 JSON 正文退化为正文、空回复算失败） | ✅ `test/insight_service_test.dart` |
| 单元测试 | **提示词数据范围（v3.7）**：只带真实字段，未评分写「未评分」不填占位；无阶段 / 无声音时对应段落整段不出现；**用户备注不进提示词**；系统提示要求 JSON 且禁止编造与医疗结论 | ✅ `test/insight_prompt_test.dart` |
| 数据 / Widget | **洞察生成与落库（v3.7）**：`saveInsight` 同一条记录只有一行（重新生成是覆盖而非新增）；**模型没给分时回退到本地估算而不是把评分吞掉**；`copyWith` 只换洞察；详情页未配置时**不出现按钮**并说明怎么配置、配置齐全后生成并回显「模型生成 · 服务商 · 模型」、**失败时页内报错且不写库、不抹掉已有洞察** | ✅ `test/sleep_insight_test.dart` |
| Widget 测试 | **洞察配置页的三个动作（v3.7）**：余额读数显示在按钮上；连通性测试真的打到 `/chat/completions` 并在页内说明「空正文也算连通」；DeepSeek 显示可点的余额与连通性按钮，而非「未接入」；**有密钥时才出现「清除密钥」，清了就消失且钥匙串被删** | ✅ `test/pages_widget_test.dart` |
| 单元测试 | **密钥存储（v3.7）**：启动时把钥匙串里的值读进来；输入后**内存立刻可用**且异步写进钥匙串；值没变不重复写；清空输入等于删条目（不留空串）；`clear()` 内存与钥匙串一起清；**写失败不影响本次运行**（下一次启动才需要重填） | ✅ `test/insight_credentials_test.dart` |
| 单元测试 | **清除缓存（v3.7）**：真实文件系统上跑真实实现——统计递归进子目录；空目录算 0；清除连子目录一起删并**报出释放的字节数**；清两次第二次报 0（不报假数字）；目录不存在时读 0、清是空操作；**不认识的目录/文件也一并清掉**（临时目录里的一切本来就可以丢，按名字匹配的清单会漏）；`formatCacheSize` 的分档 | ✅ `test/app_cache_test.dart` |
| Widget 测试 | **清除缓存那一行（v3.7）**：显示真实占用、点完变成「暂无缓存」；**读不到占用时显示「暂时读不到占用」而不是编一个 `0 B`** | ✅ `test/pages_widget_test.dart`（设置页组） |
| 集成（真机/真平台） | 真实缓存目录的 `size()` / `clear()`：macOS 上实测 8 个白噪音 WAV（6.8 MB 磁盘占用）→ 读数 `6.7 MB`（二进制单位）→ 清完目录为空、再读为 0 | ✅ 临时 `integration_test` 脚本（跑完已删，结论记在 README「验证记录」） |
| 集成（真机/真平台） | 钥匙串往返：写、读、覆盖写、删；**另起一个进程仍读得到**（这正是「重启后仍在」的证据）。macOS 上已实测；未在 iOS 真机跑 | ✅ 临时 `integration_test` 脚本（跑完已删，结论记在 README「验证记录」） |
| Widget 测试 | 弹层蒙层独立淡入、点击把手/蒙层关闭、下拉阈值与回弹、打开计数、不可关闭时忽略手势、宽屏下限宽 560 但下沿仍贴屏幕底（浮起 24px 已按偏差 #40 作废） | ✅ `test/app_sheet_test.dart`（含变异验证：把浮起加回去变红） |
| Widget 测试 | 推入路由的材质祖先与错误下划线、无阶段记录的主卡片、演示数据二级页 | ✅ `test/pages_widget_test.dart` |
| 单元测试 | `estimateScore` 边界（4/5/6/7/9/10/12 小时）、事件与质量权重、分档阈值 | ✅ `test/sleep_score_test.dart` |
| 单元测试 | `buildSleepWindow` 跨午夜与同日、时钟/日期格式化往返 | ✅ `test/sleep_window_test.dart` |
| 单元测试 | `SleepStatistics` 平均值分母、图表上下界、柱高钳制、计数口径 | ✅ `test/sleep_statistics_test.dart` |
| 数据测试 | 演示数据安装与来源标记、清除演示数据、CRUD 往返、醒来日归档、级联删除、全部删除 | ✅ `test/sleep_data_test.dart` |
| 数据测试 | schema v1→v2→v3 迁移：用**真实的旧版库文件**升级。v1 段校验旧数据保留、`source` 不重置、新列默认值、新表可读写、重复打开不重跑；v2 段校验**孤儿洞察行被清除**、仍有关联的洞察保留、**`record_id` 为空的洞察存活**（含记录表为空、`IS NOT NULL` 守卫真正吃重的情形）、迁移后外键真的存在且级联生效、已损坏的库（`records=0 / insights=5`）能被修好 | ✅ `test/schema_migration_test.dart`（含防止夹具空跑的自检：夹具必须停在 v2，且 `insights` 确实不带外键） |
| 数据测试 | 演示数据**重装与幂等**：清除后重装条数一致、不留孤儿洞察、连装两次结果不变（所有写入路径 upsert） | ✅ `test/sleep_data_test.dart` |
| 数据测试 | 冷启动播种失败**不中断启动**：`installDemoSeedIfNeeded` 在写入失败时只记日志不外抛，开关关闭时连库都不查，判据是「有没有 demo 行」而非「表是否为空」 | ✅ `test/demo_seed_startup_test.dart`（含变异验证：拆掉 try/catch、把判据改成 `isEmpty` 都会变红） |
| Widget 测试 | 四页空状态与数据态、表单保存、二次确认、二级页内边距、下拉不受裁剪 | ✅ `test/pages_widget_test.dart` |
| Widget 测试 | **设置根页（v3.5）**：只剩三段导航行 + 四条必须保留的入口（导出 / 删除全部数据 / 演示数据 / 罗盘）；外观与睡眠目标的控件**不在**根页；关于行的版本号仍取 `PackageInfo` | ✅ `test/pages_widget_test.dart`（「设置页」组） |
| Widget 测试 | **外观页（v3.5）**：行内下拉切换写回 `themeMode`；副标题与页脚逐字在位；**箭头贴住触发器右端**（量渲染矩形，已变异验证）；`expectProperlyRendered` 守卫 `Material` 祖先；控制器的 `_MenuField` 提升为公共 `AppMenuField` 后洞察页那条「下拉不受卡片裁剪」仍绿 | ✅ `test/pages_widget_test.dart`（「设置二级页」组） |
| Widget 测试 | **睡眠目标滑块（v3.5）**：快捷按钮写回 540；滑块在任意位置落库的分钟数都是 30 的整数倍（吸附 0.5h）、两端夹在 5 / 12 小时；`Semantics` 的增大 / 减小一步是 0.5 小时；数值在卡片内水平居中 | ✅ `test/pages_widget_test.dart`（含变异验证：`_snap` 退回直接 `clamp` 必红） |
| Widget 测试 | **睡眠设置页（v3.5）**：提醒 / 声音检测都收在这一页；两条产品红线逐字在位（「尚未接入录音，开关只保存偏好」；权限被拒的「去系统设置」行） | ✅ `test/pages_widget_test.dart`（含变异验证：副标题换回原型文案必红）、`test/reminder_settings_test.dart` |
| Widget 测试 | **开屏页（v3.5）**：品牌文案在位；播完回调**恰好一次**；开启「减弱动态效果」时尽快播完且不排帧；`AppScaffold` 里开屏先于引导页；设置未读到第一帧时不收起；已引导过的用户开屏后直接进外壳 | ✅ `test/splash_screen_test.dart`（5 条；含变异验证：收起条件去掉 `settingsAsync.isLoading` 必红） |
| Widget 测试 | 分段控件胶囊与分段同宽、位移成整数倍 | ✅ `test/segmented_control_test.dart` |
| Widget 测试 | 编辑/删除：入口有无、演示数据不可编辑、表单预填、写回同一 id、不改 `createdAt`、不清空阶段、删除二次确认 | ✅ `test/record_edit_delete_test.dart` |
| 集成 | 记录卡 → 详情 → 编辑 → 保存 → 回到外壳，走真实 go_router 与 `extra` 传递 | ✅ 同上（数据经 provider 覆盖而非 drift 流） |
| 单元测试 | 合成波形：确定性、互异性、不削波、无直流、接缝连续、频谱走向、瞬态、包络、森林含鸟鸣、WAV 头与钳制 | ✅ `test/noise_synth_test.dart` |
| Widget 测试 | 助眠音效面板：播放交接、停止、切换、失败如实报错、音量写回、关闭释放；**宽屏（iPad 横屏）下八格仍是四列两行且不溢出**——格子宽度按面板自身宽度算，不是屏幕宽度（含变异验证：换回屏幕宽度必红） | ✅ `test/noise_sheet_test.dart` |
| 单元测试 | 导出内容：BOM 与 CRLF、RFC 4180 转义可无损还原、记录/阶段两张表、按入睡时刻升序、演示记录排除并计数、JSON 用 schema 字段名且不写 `localUri` / `AppSettings` | ✅ `test/sleep_export_test.dart` |
| Widget 测试 | 导出页：条数只数真实记录、无记录时禁用并说明、CSV/JSON 两个动作、失败如实报错、取消分享不报错 | ✅ `test/export_page_test.dart` |
| 单元/Widget 测试 | 提醒：幂等全量重排契约与固定 id、`nextOccurrence` 的夏令时口径、权限被拒时不写偏好且开关回弹、`denied` 时的「去系统设置」入口、启动回收被撤销授权、`unsupported` 时不动偏好 | ✅ `test/reminder_scheduler_test.dart`、`test/reminder_settings_test.dart`、`test/reminder_sync_test.dart` |
| 单元/Widget 测试 | 图标取色：`AppIcons.svgFor` 逐字节断言颜色写进 `stroke`、不出现黑色、不留 `currentColor`；漏传 `color` 触发断言；记录页四类事件图标在**深色下**未选中取 `textMuted`、选中取语义色 | ✅ `test/pages_widget_test.dart`（纯函数 + 记录页渲染护栏） |
| Widget 测试 | 关于卡片：文字在卡片内**水平居中**（防 `Stack` 静缩后被左锚定）、版本号取自 `PackageInfo` 而非写死常量 | ✅ `test/pages_widget_test.dart` |
| Widget 测试 | 确认弹窗（v3.6 起为系统组件 `CupertinoAlertDialog`）：用的确实是 `CupertinoAlertDialog`、取消与点蒙层返回 `false`、确认返回 `true`、取消在左确认在右、破坏性操作取 `danger` 非破坏性取 `accent`、深色下亮度跟随应用、三处入口文案不变 | ✅ `test/confirm_dialog_test.dart`（7 条）、`test/pages_widget_test.dart` |
| Widget 测试 | 顶部渐变带贴在**屏幕物理顶端**（不被顶部安全区推下去）；四个一级页的 `error`/`loading` 分支仍给状态栏留白 | ✅ `test/pages_widget_test.dart` |
| Widget 测试 | `PrimaryAction` 禁用态：不画顶边高光与蓝色投影、不触发触觉，但接住点击并给出**页内**提示（不走会被二级页盖住的全局 toast）；启用态观感与手感逐项不变 | ✅ `test/primary_action_test.dart` |
| Widget 测试 | 删除入口用**垃圾桶**图标（非借用的停止方块）且带 `danger` 底板——身份断言经变异验证（换回 `stop` 必红） | ✅ `test/pages_widget_test.dart`、`test/record_edit_delete_test.dart` |
| Widget 测试 | 标签条浮起量：带 home indicator 的设备上胶囊底边离屏幕底 **20pt**、无安全区 12pt、小安全区不被回收量削到下限以下；页面底部留白始终等于「浮起量 + 胶囊**实测**高度 + 16」（量渲染出的矩形，不量函数返回值） | ✅ `test/tab_bar_inset_test.dart`（含变异验证：`_tabBarFloatRelief` 归零，两条用例变红） |
| Widget 测试 | 底部模糊带：遮罩套在 `BackdropFilter` 外面（结构断言，防硬边）、模糊半径 14、填充上透明下 78% 且单调递增、遮罩方向相反、高度 = 底部预留 + 20（含无安全区的 113）、宽屏不渲染、整条带不拦手势 | ✅ `test/bottom_fade_test.dart`（含变异验证：遮罩方向反转、带子排到标签条之后、高度写死，均变红） |
| 单元测试 | 应用图标几何（分平台）：macOS 图标**实体自身四角透明**（`alpha>128` 包围盒的四角，是「有圆角 / 无圆角」的分水岭；画布角 `(0,0)` 量的是留白、**测不出**圆角）、中心**不透明**、实体左边缘**内侧**中点（取 `left + 1`：正好压在边界上的那一列带抗锯齿，1024 上实测 alpha 244）**不透明**（反向护栏：防「整个画没」）、实体包围盒 = 824×824 且四边留白各 100、实体下方有投影、圆角半径带宽（挡住「半径退回 60」）；另按七个尺寸逐一断言文件名与真实像素尺寸绑定、实体宽随尺寸等比；iOS 图标仍是 1024 满幅**且 PNG 无 alpha 通道**（色型 2，防误伤） | ✅ `test/app_icons_asset_test.dart`（5 条，跑在普通 `flutter test` 里；含变异验证：摘掉 `clipRRect`、半径改 60、删掉投影，都会让断言变红） |
| 数据迁移 | v3 → v4：`ActiveSessions` 建表成功；`sleepRecords` 重建后 **`quality` 确实可空**（写入 `null` 成功）且**既有记录、阶段、设置一行不动**；重建后子表外键仍级联（插阶段行后删记录，级联带走）；重复打开不重跑；全新库直接建到 v4 | ✅ `test/schema_migration_test.dart`（`v3 → v4` 组 5 条） |
| 领域 | 未评分：`quality` 为 `null` 时 `scoreSource` 为 `none`、`score` 与 `estimatedSummary` 为 `null`（**不调用 `estimateScore`**）；统计的平均分把未评分排除在分母外、全部未评分时平均分为 `null` | ✅ `test/sleep_data_test.dart`（「未评分不伪造分数」组） |
| 数据 | 会话开始/结束：写记录用 `startAtUtc` 与结束时刻的真值、`source = 'session'`、按醒来日归档、结束时 session 行被删、`finish` **不写任何阶段**、级联与「删除全部本地数据」清掉残留会话、冷启动重启后会话仍在 | ✅ `test/session_repository_test.dart`（16 条） |
| 数据 | 时长守门：0 时长与 > 24h **不落库**、不写记录、会话仍在 | ✅ `test/session_repository_test.dart`、`test/sleep_session_test.dart`（结束守门组） |
| 通知 | `scheduleOnce` 排出 9003 且走**一次性**通道；`sync` **不动** 9003（变异验证）；会话活跃且闹钟开启时排 9003 并让日常起床提醒 `9002` 让位、就寝提醒 `9001` 不受影响；无会话/闹钟关着时 9003 被排掉、`9002` 排回；排定时刻复用 `nextOccurrence`（跨午夜与跨夏令时落在同一墙上时刻） | ✅ `test/reminder_scheduler_test.dart`（起床闹钟组、`nextOccurrence` 组）、`test/reminder_sync_test.dart`（会话闹钟组 6 条） |
| 数据 | 「鼾声/梦话记录」**只有一个真相来源**：会话页开关写的是 `AppSettings.soundRecordingEnabled` | ✅ `test/sleep_session_page_test.dart`（拨动鼾声开关写回设置） |
| Widget | 会话页（**v3.3 版式**）：中央 `HH:MM:SS` 秒表 + 月亮；「当前睡眠事件」卡**只回显**——没在放白噪音就没有那一行、闹钟关着就没闹钟行、两行都不再可点；鼾声开关带「尚未接入录音」说明；闹钟开着时报剩余时间**并带上后台投递的如实标注**（文案缺失必红）、**没设闹钟但已睡过头时报「已超过起床时间 · 请手动结束睡眠」**（两句不许打架，剩余量只由模型出）。**v3.2 之前**的「点摘要条展开白噪音区 / 圆环进度随已过时长变化」随版式替换作废（见会话规格 §16.2、§17.4） | ✅ `test/sleep_session_page_test.dart` |
| Widget | 会话页结束方式：**长按 1.5 秒、横向填充条扫满才结束**；未按满松手不结束且无副作用；短按不生效并给出提示；按下即开始（不必等长按超时） | ✅ `test/hold_to_finish_button_test.dart`、`test/sleep_session_page_test.dart`（结束按钮组） |
| Widget | 会话页评星：结束先问一次星级；跳过 → 落库记录质量为 `null` 且**没有评分**；评了 → 质量写进记录；时长越界不落库并给出手动补录/丢弃两个出口 | ✅ `test/sleep_session_page_test.dart`（结束流程组） |
| Widget | 会话白噪音：播放器收到选中、再点一次停掉、倒计时到点停掉并清空会话里的选中值；关掉弹窗不停、**pop 掉会话页仍继续响**（播放器挂在 app 级控制器上）；弹窗里的定时只有 15/30/45/60、没有「不限」与 90m | ✅ `test/session_night_widgets_test.dart` |
| Widget | 回顾页：默认最近一条真实记录；只有演示数据时不可补充并说明；无记录空状态；记录头可换一晚且**演示记录不出现**；未评分的记录星级一颗都不选中；保存写回**同一条 id**、不改起止时刻、**不清空已有阶段** | ✅ `test/review_page_test.dart`（10 条） |
| Widget | 首页：无会话时主按钮是「**开始入睡**」，点它**只推入会话页、不写会话行**（走真实路由）；有会话时显示「正在睡眠」卡且可回到会话页；`LogPage` 恒以 `Subpage` 呈现（Tab 分支已删）、保存后 `pop()`、回顾页底部入口真的落在 `/log/new` | ✅ `test/pages_widget_test.dart` |
| 单元/配置 | 显示名：iOS plist 的 `CFBundleDisplayName` 为 `夜深`；macOS plist 有该键；web 的 `title`、`apple-mobile-web-app-title`、manifest 的 `name` / `short_name` 均为 `夜深`；且 `PRODUCT_NAME` / `CFBundleName` **仍为 `night_sleep`**（反向护栏，防误伤构建路径） | ✅ `test/app_display_name_test.dart`（5 条） |
| 数据迁移 | v4 → v5：`active_sessions` 加 `scene_id` 可空列；既有会话行其余字段一个不差；写入 `null` 成功；重复打开不重跑 | ✅ `test/schema_migration_test.dart` |
| 数据 | 场景持久化：选中场景写进 `active_sessions.scene_id`；重开会话读回同一个 id；库里是不认识的 id 时按默认「流星夜」处理（不抛）；`discard` / `finish` 后新一轮会话回到默认 | ✅ `test/session_repository_test.dart` |
| 单元 | `SleepSession.elapsedClockAt`：`00:00:00` 起步、跨小时、跨午夜、超 24 小时不回绕 | ✅ `test/sleep_session_test.dart` |
| 单元 | 夜景几何纯函数：八套场景底色、光晕、星点、**流星只在 `meteor` / `moon` / `galaxy` 三场景可见**（订正本节旧稿） | ✅ `test/night_scene_test.dart`、`test/night_backdrop_test.dart`（16 条） |
| 单元 | 月亮标记：SVG path / 渐变逐字取自原型、**丢弃 `<filter>` 后不打印 unhandled element**、轨道光晕近似层在位 | ✅ `test/sleep_moon_mark_test.dart`（6 条） |
| Widget | 会话页夜景：选择器列出且**只有 8 种**场景、点选写回会话行、再进页面仍是它；`MediaQuery.disableAnimations` 为真时背景**停表**（变异验证） | ✅ `test/session_night_widgets_test.dart` |
| Widget | 会话页事件卡：**没在放白噪音时整行不渲染**、在放时右侧是波形（**不存在「已停止」态**，偏差 #33） | ✅ `test/sleep_session_page_test.dart`、`test/session_night_widgets_test.dart` |
| Widget | 会话页：中央显示 `HH:MM:SS` 秒表；鼾声行「尚未接入录音，开关只保存偏好。」**逐字在位**（产品红线）；「收起」常驻可点且 pop 后会话仍在；起床闹钟行只在闹钟开着/已睡过头时出现、右侧只有状态字 | ✅ `test/sleep_session_page_test.dart` |
| 数据 | `start()` 一次写全入睡前草稿：`alarmEnabled` / `sceneId` / `noiseId` / `noiseVolume` 传什么读回来就是什么；不传时默认值不被新参数带偏 | ✅ `test/session_repository_test.dart` |
| 数据 | **首次并发读设置不炸**：两个 `getSettings()` 同时跑（入睡前态一帧里就有两个读者），后一个 `insert` 必须让路（`InsertMode.insertOrIgnore`） | ✅ `test/session_repository_test.dart` |
| Widget | **入睡前态**：报出「晚安 / 准备好休息了吗？ / 放下今天，让夜晚慢下来。 / 睡眠模式 / 夜景氛围 / 常用白噪音 / 开始睡眠 / 屏幕将保持暗色，轻触夜景即可切换氛围」；旧的「没有正在进行的睡眠」空状态不再存在 | ✅ `test/session_setup_page_test.dart` |
| Widget | **记录起点在页内**：挂上 `/sleep/session` 什么都不写库；点「开始睡眠」才写会话行，`startAtUtc` 就是按下的时刻；草稿（场景 / 白噪音 / 音量）随行一次写进去；收起不写库、停掉试听、回上一页；草稿不跨页存活 | ✅ `test/session_setup_page_test.dart` |
| Widget | 入睡前态的闹钟草稿：权限被拒时开关弹回、给说明、不写库，但不拦着开始这一晚；权限通过时时刻胶囊显示设置里的起床提醒时刻，开始睡眠后写进会话行并走 `syncAllReminders`（9003 与 9002 成对推导） | ✅ `test/session_setup_page_test.dart` |
| Widget | 场景选择器两种外壳：入睡前态多一行「夜景氛围 / 左右滑动切换」，进行中态（`compact`）两条都不在；选中卡是**绕中心** `scale(.98)`（订正照抄错层，见会话规格 §17.6） | ✅ `test/session_night_widgets_test.dart` |
| Widget | 入睡前态的两条媒体查询：窄屏（≤390）四格竖排 + 内边距 13，高屏（≥860）hero 撑到 285（照最终生效层 `index.css:1937` 起那两条） | ✅ `test/session_setup_page_test.dart` |
| 单元 | `activeSessionProvider` 接线：写下会话行之后它会把新会话推上来（不挂树的 `ProviderContainer`；`testWidgets` 里订阅 drift 流会留下 pending timer） | ✅ `test/session_setup_page_test.dart` |
| Widget | 会话页**常暗**：应用主题为**浅色**时，会话页内读到的 `Theme.of(context).brightness` 仍是 `dark`（防有人删掉页面自套的 `Theme`） | ✅ `test/sleep_session_page_test.dart`（「浅色主题下会话页仍然是深色」） |
| Widget | 长按结束：横向胶囊、按住满 1.5s 触发、未满松手不结束、滑开作废、短按只提示；**开启「减弱动态效果」时 1.5 秒守卫仍按真实时长计时**（`AnimationBehavior.preserve`，属 bug 修复回归） | ✅ `test/hold_to_finish_button_test.dart`（6 条） |
| 集成/真机 | iOS/Android/macOS 核心流程；通知权限；锁屏录音与中断 | macOS 构建、iOS 模拟器构建已验证；**真机、通知投递与分享面板未验证** |
| 视觉检查 | 对照 Figma Make 四页在手机/宽屏、浅色/深色核对层级、间距、字体与安全区 | **部分**：v2.5 的巡检覆盖了四个一级页与详情/音效面板；v2.6 那一版追加确认了顶部渐变顶到物理顶端后硬分界消失（iPhone 16 Pro 模拟器，浅色/深色各一遍）。**v2.6 其余新增/改动的界面（自绘确认弹窗、垃圾桶图标、禁用按钮的页内提示、关于卡片）没有做目视核对**，只有几何/结构断言。v2.7 的标签条浮起量同样**只有几何断言**（`test/tab_bar_inset_test.dart`），没有截图核对；v2.8 的底部模糊带已在 2026-09-29 补做目视核对（iPhone 16 Pro 模拟器；浅色看过首页滚动后 / 统计页 / 睡眠详情与助眠音效弹层，**深色仅首页静置态**）：带子顶边（离屏幕底 121pt）无硬边（离带顶约 20pt 的标题处有效 wash 约 9%，越靠屏底越重）、方向为「下重上轻」（越靠近屏幕底越实）、胶囊下半部未发闷（深色下 `bgNavbar` 76% 填充主导）。**仍未逐页逐屏核对，深色覆盖面只有首页**；证据图见 `screenshots/v2.8-*.png`。**v3.3 的入睡前态（月亮 / 场景选择器 / 设定卡三段、点「开始睡眠」翻进行中、收起不写库）只有几何与结构断言，未目视核对**。**v3.2 的会话页夜景（八套场景动画 + 月亮）只有几何/结构断言，未目视核对**：动画观感、真机帧率与耗电，以及 `flutter_svg` 丢弃 `<filter>` 后月亮外发光近似层的实际观感，均需人工核对，见 README「验证记录」。**v3.5 的开屏页已目视核对通过**（macOS，渐变 / 轨道环 / 星点 / logo 与两道声波 / 文案 / 进度条逐项在位，证据 `screenshots/v3.5-splash.png`）；**设置根页与两个新二级页仍未核对**——巡检被系统的「`night_sleep` 想访问『文稿』文件夹」授权框盖住窗口，本机点不掉系统对话框，行内下拉在 390px 与 iPad 横屏下的换行、自绘滑块的拖拽手感因此仍只有几何与结构断言。**v3.6 起确认弹窗改成系统 `CupertinoAlertDialog`（半透明材质叠在模糊背景上），同样只有几何/结构断言**——浅色/深色下的实际观感，以及它与全仓其余玻璃材质的协调度，仍需人工核对 |

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
   的用途串）。**麦克风的用途文案已起草、待确认**——草稿见
   `2026-09-30-sleep-session-design.md` §六；**plan A 尚未接入录音**，因此 `Info.plist` /
   manifest 里还没有落地这根用途串，它随 plan B 一起生效。

缺少这些资料时可完成界面、接口与本地基础能力，但不能声明外部集成已完成。
