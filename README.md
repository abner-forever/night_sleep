# 夜深

「夜深」是一个中文、本地优先的睡眠记录 Flutter 应用。界面按
`docs/superpowers/specs/2026-09-28-night-sleep-design.md` 第 2 章的
Figma Make 原型**最终生效层**实现：iOS 玻璃材质、悬浮胶囊标签条 / 侧边栏自适应导航、
自定义描边图标集、滚轮选择器、浅色/深色主题、离线睡眠记录与 7/14/30 天统计、
睡前会话（**入睡前**那一屏 + 进去之后的「睡眠进行中」）与「回顾」补感受、数据导出
（CSV / JSON）与就寝/起床本地通知提醒。
应用显示名为「夜深」（iOS / macOS / Web）。

## 环境要求

- Flutter stable（本机基线 `3.47.5`，Dart `3.13.4`）
- macOS / iOS 目标需要 Xcode；**macOS 与 iOS 构建当前不需要 CocoaPods**——Flutter 3.47 用
  Swift Package Manager 解析插件依赖（构建日志中可见 `Xcode is fetching Swift Package
  Manager dependencies`）
- Android 目标需要 Android Studio、SDK 和 JDK（本工作区尚未安装 Android SDK）。另外
  **仓库里没有 `android/` 目录**——`.metadata` 只登记了 ios / macos / web 三个平台。
  接入 Android 时先 `flutter create --platforms=android .` 生成平台目录，
  并补齐通知重启相关的权限与 receiver（见「未实现」表）

## 运行与生成

```bash
flutter pub get
dart run build_runner build          # 生成 lib/core/database/app_database.g.dart
dart format .
flutter analyze
flutter test
flutter run -d macos                 # 或 -d chrome / -d <device>
```

演示数据只在 `DEMO_DATA` 为真时安装，默认等于 `kDebugMode`：

```bash
flutter run -d macos --dart-define=DEMO_DATA=true    # 强制开启
flutter build macos --dart-define=DEMO_DATA=false    # 发布构建强制关闭
```

国内网络下 `pub get` 与 `build_runner` 需要镜像，否则会卡在 pub.dev 超时：

```bash
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
```

⚠️ **只在这个 shell 里临时设置，别写进 profile；包已在本地缓存时更不要设。**
`PUB_HOSTED_URL` 会把 `pubspec.lock` 里 129 条 `url: "https://pub.dev"` 一并改写成镜像地址，
制造一个与依赖本身无关的巨型 diff。依赖齐了就直接 `flutter pub get`。

`lib/core/database/app_database.g.dart` 由 Drift 生成，不手工修改。

## 项目结构

```text
lib/
  app/                 应用入口、导航外壳、标签状态、提示条；会话白噪音控制器
                       (noise_session.dart)、启动提醒重排、通知权限闸口
  core/
    config/            构建开关（演示数据）
    database/          Drift schema v5 与迁移
    platform/          触觉反馈、就寝/起床提醒与会话闹钟调度
    theme/             设计令牌与 ThemeData
    widgets/           玻璃材质、iOS 控件、弹层、二级页外壳、滚轮、图标、图表基础件
  features/
    home/              首页（开始睡眠 / 正在睡眠卡）
    log/               回顾页、换一晚选择器、手动补录页、编辑表单（共用 LogPage）
    session/           睡眠会话页、夜景氛围（场景表/背景/选择器/月亮）、事件卡、白噪音弹窗、就地评星
    stats/             统计
    settings/          设置（根页三段导航）与六个子页（外观、睡眠设置、数据导入、
                       数据导出、洞察配置、演示数据）；睡眠目标滑块、页脚小字
    onboarding/        开屏页（启动时一屏）与首次引导
    sleep/
      domain/          记录聚合、阶段、声音、评分、统计口径、时间窗口、会话模型
      data/            仓库（行 → 聚合）、会话仓库、演示种子
      presentation/    睡眠盘、评分环、阶段图、详情弹层、声音卡、助眠音效弹层
test/                  领域计算与页面测试
```

## 当前实现范围

- **设计系统**：完整令牌（`app_tokens.dart`）、玻璃材质、iOS 开关/分段控件/列表组、底部弹层、
  滚轮选择器、自绘描边图标集（原型图标逐字用原 SVG path；垃圾桶为 v2.6 新增，见下）。
- **应用显示名**（v3.0）：iOS / macOS / Web 三处均**配置**为「夜深」（`CFBundleDisplayName` /
  `title` / manifest），而决定构建产物路径的 `PRODUCT_NAME` / `CFBundleName` 仍是
  `night_sleep`——改成中文会让 macOS 的 `.app` 包名与可执行文件名变成中文。
  **Dock 与 iOS 桌面读 `CFBundleDisplayName`（已改）；macOS 菜单栏读的是 `CFBundleName`
  （仍为 `night_sleep`），可能仍显示英文名，待人工核对。** 见
  `docs/superpowers/specs/2026-09-30-sleep-session-design.md` §一（应用显示名）与
  `test/app_display_name_test.dart`。
- **首页**：圆形睡眠盘（4 同心弧，首次进入自绘动画）、昨夜概览、7 日均时、助眠音效入口、
  最近记录卡（阶段色带 + 图例）。主按钮位是「**开始入睡**」（v3.3 起照原型改的文案）；
  有会话在跑时换成「**正在睡眠**」卡（点它回到会话页）。**点「开始入睡」只是进页面、不写任何
  东西**——记录起点在页内那颗「开始睡眠」上。**卡片上的已睡时长是 build 快照，停在首页不会
  自动跳动**（只有会话页每秒 tick）。
- **睡眠会话**（v3.3）：首页「开始入睡」→ 推入式全屏会话页（`/sleep/session`），
  **一个路由两态**，照原型 `SleepView` 的两个分支做：
  **入睡前**（没有会话行时）= 晚安 / 准备好休息了吗？ / 月亮轨道 / 夜景氛围选择器 /
  常用白噪音四格（雨声·海浪·棕噪音·风扇，点选即试听；窄屏自动竖排）/ 白噪音·起床闹钟·鼾声检测三行
  （白噪音那一行与右上角「完整设置」都能打开深色底部弹窗）/「开始睡眠」按钮 /「屏幕将保持
  暗色…」提示。这一屏**什么都不写库**：场景、闹钟开关与时刻都只是草稿，收起再进来就回到初值；
  按下「**开始睡眠**」才把这一整份草稿一次写进会话行（`startAtUtc` 就是那一刻），页面随即
  自己翻到进行中态。闹钟开关在拨动当场就过通知权限闸口（被拒则回弹、给说明，但不拦着开始）。
  **进行中**（v3.2 的版式，v3.3 起照原型收紧为**只回显**）：整页换成**常暗的夜景氛围**：八种场景之一
  （流星夜 / 极光 / 深海 / 月海 / 云上 / 萤火 / 银河 / 雨夜，横向选择器可切）的暗色渐变 + 网点
  质感，上面浮着场景动画（流星、极光、海浪、云层、萤火、银河、雨丝、星点）；八套动画由一个
  60 秒循环的控制器驱动、全部画在一个 `CustomPaint` 里，系统开「减弱动态效果」时停表。选中的
  场景写进会话行（schema v5 加 `active_sessions.scene_id`），收起页面再进、杀掉应用重开都还是
  同一个夜景。中央是**月亮 + 当前时刻 + `HH:MM:SS` 秒表 +「已进入睡眠模式」**（秒表小时不封顶，
  防「忘了结束」被藏成正常的 `00:00`）。中段是**「当前睡眠事件」卡**：开始睡眠 /（在放时的）
  白噪音 /（闹钟开着或已睡过头时的）起床闹钟 / 鼾声检测——**只回显、不再可点**，睡前设定都在
  入睡前那一屏做完了。鼾声那行照旧注明「尚未接入录音，开关只保存偏好」。
  **「结束睡眠」是全宽横向胶囊，长按 1.5 秒、填充条自左向右扫满才生效**；中途松手或手指滑开
  即作废，短按只给提示与轻震动。会话状态进 SQLite（`ActiveSessions` 单行表），跨重启存活；
  「收起」离开页面而**会话与白噪音继续跑**（关掉弹窗、收起页面都继续响）。「结束睡眠」就地评
  一次星（可跳过），一个事务里写记录（`source = 'session'`）并删会话行；时长不在 `(0, 24h]`
  内**不落库**，让用户选手动补录或丢弃。**它不测量任何东西**——两个时刻来自用户按下的按钮，
  起床时间来自设定。
  **整页常暗**：会话页两态都自己套 `Theme(AppTheme.dark())`，浅色应用主题下进去也是深色（原型的
  睡眠模式如此设计）。**刻意与原型不同的地方**见规格偏差 #28–#38；「事件卡不叠 `backdrop-filter`」
  见偏差 #34（睡眠进行中那一屏要整夜挂着，不叠每帧重算的模糊）。
- **回顾**（v3.0，取代原「记录」Tab）：对最近一条**真实**记录补充主观感受（质量、四类事件、
  备注），记录头可点开选择器换一晚，**不改起止时刻**。演示记录不参与补充。**手动补录降级为
  二级页 `/log/new`**（入口在回顾页底部）：实时时长预览、日期/入睡/起床滚轮、1–5 星质量、
  四类事件开关、备注；时长由起止时间派生并校验 `0 < 时长 ≤ 24h`（**不选质量就不写质量**）。
- **顶部渐变**：一级页面滚动超过 12px 后，顶部浮出 144px 的 `blur(14px)` 渐变带
  （宽屏和弹层打开时自动停用），与设计的 `.ios-top-fade` 一致；带顶到**屏幕物理顶端**
  （状态栏那段也参与模糊，不再有硬分界），滚动超 12px 后 320ms 淡入上移。
  `ImageFilter` 没有内置的 saturate 构造器，本轮用一层极淡的 accent 叠加（`alpha 0.04`）**近似**
  （也可用 `ColorFilter.matrix` 自行构造饱和度矩阵）；与 `glass_surface.dart` 同一手法。
  外壳不再套顶部 `SafeArea`，状态栏留白改由各页滚动视图按 `pageTopInset` 施加。
- **标签条浮起量**（v2.7）：浮起量改为 `max(12px, 安全区底部 − 14px)`，iPhone 带 home indicator
  时胶囊底边离屏幕底 **20pt**（原型照搬安全区，是 34pt，实机看着悬空），macOS / Web 仍是 12px。
  浮起量与页面底部留白现在**同源**（`app_shell.dart` 的 `tabBarFloat`，`tabBarReserve` 复用），
  顺带修正常量 `_tabBarHeight` 比实测多算的 0.5px（胶囊实测 65px）。
- **底部模糊带**（v2.8，原型无此元素）：屏幕底部常驻一条渐变模糊带（`core/widgets/bottom_fade.dart`），
  让滚到浮动标签条附近的内容糊掉、淡出。高度由标签条预留量推导（`tabBarReserve + 20`，iPhone 上 121pt），
  填充 0→78%、`blur(14)`，方向与顶部渐变带相反。宽屏不渲染；弹层打开时照常显示。
- **弹层手势**：底部弹层支持点击蒙层关闭、点击把手关闭、把手跟手下拉超过阈值关闭；蒙层是独立
  的淡入层，不随面板从底部滑入。
- **编辑与删除**：睡眠详情的底部提供「编辑记录」「删除记录」。编辑复用记录表单并预填原值，
  保存写回**同一条**记录（不改 `createdAt`，不新增副本，也不覆盖已有睡眠阶段）；删除需二次确认，
  经外键级联一并清掉该晚的阶段与声音事件。演示数据不提供这两个入口，并说明可在设置中整体清除。
- **删除图标与确认弹窗**（v2.6）：应用内两处删除入口改用**自绘的垃圾桶图标**
  （`AppIcons.trash`，替换此前借用的播放控制「停止」方块），「删除全部本地数据」那一行另补
  `tokens.danger` 语义色的图标底板。三处危险操作（删除记录、删除全部数据、**清除演示数据**）
  统一走 `core/widgets/confirm_dialog.dart` 的 `showConfirmDialog`。该弹窗 v2.6 起是按令牌
  自绘，**v3.6 起改用 iOS 系统组件 `CupertinoAlertDialog`**——布局、模糊表面、圆角、分隔线与
  弹簧转场交给 SDK，代价是**弹窗底色与分隔线色不再来自 `AppTokens`**（亮度、动作色
  `accent` / `danger`、蒙层色仍接令牌；取舍见规格偏差 #20）。「清除演示数据」此前**没有二次
  确认**，v2.6 补上。
- **禁用按钮的页内反馈**（v2.6）：`PrimaryAction` 的 `onTap` 为空即禁用态——不再画启用态的
  顶边高光与蓝色投影、不触发触觉，但会接住点击并回调 `onBlockedTap`。导入页据此在按钮下方
  给出**页内**说明（这是二级页，全局 toast 会被外壳盖住）。启用态观感不变。
- **关于**（v2.6；**v3.5 起照新版原型改成设置根页「关于」分组里的一行**）：moon 徽章 +
  「夜深 / 睡眠记录与分析」+ 右侧版本号。版本号读 `package_info_plus` 的真实构建值
  （`v<version> (<buildNumber>)`），不再是写死的字符串；那块大号居中卡片已随重排移除。
- **统计**：7/14/30 天分段控件、时长柱状图（含 7h 虚线目标线、可选中查看）、评分卡、
  四项汇总、梦话转录列表。
- **设置**（v3.5 起照新版原型重排为**三段导航式列表**）：根页只有
  **常用**（外观、睡眠设置、罗盘）、**数据与智能**（睡眠数据导入、睡眠洞察）、
  **数据与隐私**（睡眠数据导出、删除全部本地数据、演示数据（仅调试构建）、**清除缓存**）、
  **关于**（一行，版本号读 `package_info_plus`）。外观与睡眠设置各自收进二级页：
  - **外观**（`/settings/appearance`）：一行「显示模式」+ **行内下拉**（跟随系统 / 浅色 / 深色），
    写 `AppSettings.themeMode`，取值口径不变。
  - **睡眠设置**（`/settings/sleep`）：每晚睡眠目标（**自绘滑块** 5–12h、步长 0.5 +
    7/8/9 快捷按钮）、就寝 / 起床提醒（开关 + 时刻 + 权限被拒时的「去系统设置」行）、
    夜间声音录制开关（副标题仍是「尚未接入录音，开关只保存偏好」）。
  提醒的读写与调度行为**与搬家前完全一致**。导出的仍是 CSV / JSON 两个动作，见「数据导出」。
- **清除缓存**（v3.7，设置根页「关于」上方）：清掉 `getTemporaryDirectory()` 下**可再生成的
  临时文件**。**2026-10-03 起那里只剩一样东西**：导出时写给系统分享面板的 CSV / JSON 副本
  ——白噪音改成打包资源后不再往临时目录写 WAV，所以全新安装、还没导出过时读数为 `0 B`
  是**如实的**。副标题显示**真实占用**，读不到就说「暂时读不到占用」，清完显示「暂无缓存」。
  **不碰**睡眠记录、录音与数据库（那是「删除全部本地数据」），也**不碰**钥匙串里的 API Key
  （那是「清除密钥」）——三条清理路径各自只干一件事。
- **睡眠洞察**（`/settings/insight`，v3.7 起真的能发请求）：选服务商与模型之外，
  **DeepSeek 可查余额**（`GET /user/balance`，读数现拉现显在按钮上）、**可做连通性测试**
  （用当前模型发一次最小对话请求；**推理模型只返回推理过程、正文为空也算连通**，
  界面上写明了这句）。睡眠详情里可为**任意一晚**重新生成模型总结，走 JSON 模式拿
  `{score, summary}` 并落库；**失败只在页内报错，不写库、不覆盖已有洞察**。
  OpenAI 只有对话路径（无余额接口）；**Claude 两个都不支持**，界面上没有对应按钮。
  API Key 存**系统钥匙串**（`flutter_secure_storage`；macOS 上走旧版钥匙串，见规格偏差 #8），
  重启后仍在，设置页提供「清除密钥」。
- **开屏页**（v3.5，原型 `SplashScreen`）：冷启动一屏深蓝渐变 + 月亮 logo 描线 + 星点 +
  「夜深 / 听见夜晚，看见睡眠」+ 底部进度条，约 **1.6 秒**后收起；首次安装随后才轮到引导页。
  它是**有限时长的单条动画**（没有循环、没有 `Timer`），整屏从第一帧就不透明。
  iOS 的系统启动图与 web manifest 底色一并改成同一个深色（`#07102D`），避免冷启动白闪。
- **AI 模型列表**：按服务商从官方 `GET /models` 实时获取，用会话内的 API Key 认证；未获取前
  显示**已注明核实日期**的内置列表。DeepSeek 为默认服务商。
- **助眠音效**：**5 条实景录音**（海浪 / 篝火 / 森林 / 溪流 / 风），打包在 `assets/noise/`
  （单声道 22.05 kHz 80 kbps、44–75 秒无缝循环、合 3.40 MB），由
  `tool/generate_noise_assets.dart` 从源素材生成；音量、定时、切换与失败提示均已接通。
  **2026-10-03 之前**这里是设备内**实时合成**的 8 种噪音（`noise_synth.dart`），该合成器
  与它那套 DSP 测试已一并删除。改动经过、取舍与实测数字见
  [specs/2026-10-03-noise-real-recordings-design.md](docs/superpowers/specs/2026-10-03-noise-real-recordings-design.md)。
  ⚠️ **素材授权尚未落实**：录音来自爱给网（aigei.com），使用方裁定为「尚未确认、仅供个人
  试用」。**发布前必须确认可商用授权、换素材或退回合成**，规格 §10 第 3 条据此**不关闭**。
  （历史：这条路径曾有两个踩过就静默出错的坑——临时目录要先建、`AudioPlayer.play()` 不能
  await，见会话规格 §17.7；改打包资源后第一条已随之消失。）
- **数据导出**：设置页「睡眠数据导出」→ 二级页 `/settings/export`。CSV 两张表
  （记录 16 列 + 阶段 6 列，UTF-8 BOM、CRLF、RFC 4180 转义、按入睡时刻升序）、
  JSON 完整嵌套存档，经系统分享面板交付。只导出**真实**记录（演示记录排除并计数说明）；
  JSON **不写 `localUri`**（改写成 `hasLocalAudio` 布尔）、**不含 `AppSettings`**
  ——设备偏好与密钥都不进文件。格式规则全在 `sleep_export.dart`（纯函数，无数据库、无插件）。
- **就寝/起床提醒**：接真实本地通知（`flutter_local_notifications` + `timezone`）。
  调度是**幂等全量重排**（固定 id 9001/9002 先取消再排），并在每次启动重排，
  因此调度与偏好没有各自独立的生命周期。权限被拒时**不写入偏好**、开关回弹；
  权限为 `denied` 时给出「去系统设置」入口；启动时若发现偏好为真而权限已是 `denied`
  （用户在系统设置里撤销过），把偏好写回 `false`。Android 用 `inexactAllowWhileIdle`
  （刻意不申请精确闹钟权限）。
- **会话起床闹钟**（v3.0）：新 id `9003`，走 `scheduleOnce`（**不传**
  `matchDateTimeComponents`，**一次性**而非每天重复），排定时刻复用 `nextOccurrence` 的
  夏令时口径。会话活跃且闹钟开启时，**日常起床提醒 `9002` 让位**（就寝提醒 `9001` 不受影响）；
  会话结束/丢弃后 `9002` 按偏好排回。iOS / macOS **请求** `interruptionLevel: timeSensitive`
  （**工程里没有配套的 Time Sensitive Notifications entitlement，按当前产物该级别会被系统
  降级、穿不了专注模式**——见「未验证」），Android 用 `inexactAllowWhileIdle`。
  界面上如实标注「由系统通知投递；休眠模式下可能晚几分钟，
  强度不如系统闹钟」——这句标注只出现在「起床闹钟」那一行，**全页仅此一处**
  （`ReminderScheduler.wakeAlarmDeliveryNote`）。权限闸口 `ensureNotificationPermission`
  与设置页共用。**真机到点投递未验证**（见「验证记录」）。
- **助眠音效素材**：由 `tool/generate_noise_assets.dart` 从源录音生成，产出
  `assets/noise/` 下 5 条 `.m4a`。ffmpeg 滤镜链（单声道化 → 响度归一 → 折回式无缝接缝 →
  AAC 编码）里有**三处写错会静默失效**的细节——`asplit` 不能省、接缝要折回而不是淡入、
  归一天花板要给交叉淡化留 2 dB——都写在脚本头注释与规格 §5.2 里。
  跑法：`dart run tool/generate_noise_assets.dart [源素材目录]`（默认 `~/Downloads/白噪音素材`）。
- **应用图标**：由 `assets/branding/app-icon.svg` 生成，`tool/generate_app_icons.dart` 一次
  产出 iOS 15 张 + macOS 7 张。**v2.9 起是两条渲染路径**：iOS 满幅直角、无 alpha 通道（色型 2，
  由系统套遮罩）；macOS 按 Apple 图标网格烘焙圆角与留白（实体 824×824、四边留白 100、半径 185.4）
  并加投影，**保留 alpha**（色型 6）——因为 macOS **不套遮罩**，圆角得写在文件里。回归断言见
  `test/app_icons_asset_test.dart`，偏差见规格 #16。
- **数据**：SQLite（Drift）schema **v5**，含阶段、声音片段、洞察、会话（`ActiveSessions`
  单行表）四张新表与 v1→v2→v3→v4→v5 迁移；外键级联删除；仓库用 3 条批量查询组装聚合。
  v3 给 `Insights.recordId` 补上 `ON DELETE CASCADE` 外键（此前没有，`deleteDemoData` 会留下
  孤儿洞察行，重装演示数据时主键冲突、异常还被静默吞掉），迁移**先清孤儿再重建表**，因此升级
  会**自动修好已在现场损坏的库**。v4 建会话表，并把 `SleepRecords.quality` 改为**可空**
  （会话评星可跳过 → 质量能表示「未评分」）——`alterTable` 重建了有子表引用的 `sleepRecords`，
  迁移后子表外键仍级联（有测试钉住）。v5 给 `active_sessions` 加 `scene_id` 可空列（会话页夜景
  场景的持久化，`null` = 默认「流星夜」）。

## 罗盘

设置 → 工具 → 罗盘（`/settings/compass`），包含二十四山、后天八卦、天池磁针、实时角度、方向锁定、手机倾斜与校准提示。
iOS 使用 Core Motion 的磁北参考系，融合陀螺仪、重力与校准磁场；读数表示**手机顶部相对磁北的方位**，不计算磁偏角或真北，也不申请定位权限。
页面关闭和应用进入后台时停止采样，回到前台重新连接。模拟器、macOS、Web 和无硬件设备显示不可用或等待状态，不生成假方向。
Android 尚无平台目录，因此未接入传感器。方向精度与权限行为仍需 iPhone 真机验证。
罗盘独立开发验证：43 项相关单元/组件测试通过，Dart 静态分析无问题，iOS 模拟器构建成功；模拟器原生通道已确认返回不可用而非假方位。
合入最新 master 后复验（2026-10-02）：完整测试集 347/347 通过，Dart 静态分析无问题；罗盘入口测试已适配共享路由和睡眠会话状态。

## 未实现（不得视为已完成）

| 能力 | 现状 |
| --- | --- |
| 夜间录音 / 鼾声梦话检测 | **未接入（plan B 才做）**。设置页与会话页那个开关**只保存偏好**，**录音本身仍未实现**，界面已如实注明「尚未接入录音，开关只保存偏好」。**不测量任何东西** |
| 白噪音的后台播放 / 锁屏控制 | 未接入。会话白噪音在**收起页面后仍继续响**（播放器提到 app 级），但退到后台或锁屏后声音会停，界面已如实标注 |
| 助眠音效素材的可商用授权 | **未落实（发布阻塞项）**。5 条录音来自爱给网（aigei.com），使用方 2026-10-03 裁定为「尚未确认、仅供个人试用」。代码、`pubspec.yaml`、README 与规格均已如实标注，规格 §10 第 3 条**不关闭**。发布前必须确认授权、换素材或退回合成 |
| 小米手环数据导入 | 未接入。需真实导出样本或官方接口文档，导入按钮禁用并说明原因 |
| AI 洞察服务 | **部分接入（v3.7）**。已能查余额（**仅 DeepSeek**）、做连通性测试、在睡眠详情里重新生成一晚的模型总结并落库；API Key 存**系统钥匙串**（v3.7 起，重启后仍在，设置页有「清除密钥」）。**仍未做**：Claude 的对话与余额（Messages API 形状不同且无 key 可实测）、余额的持久化与历史曲线、**发送前「将要发送哪些数据」的逐项确认界面**（规格 M4 第 3 条的后半句）。OpenAI 的对话路径与 DeepSeek 同一份代码，但**没有 key 实测过**（见「验证记录」） |
| Android 平台 | 平台目录未生成（`.metadata` 只有 ios / macos / web）。接入时需补 `RECEIVE_BOOT_COMPLETED` 权限与 `ScheduledNotificationReceiver` / `ScheduledNotificationBootReceiver` 两个 receiver（否则设备重启后提醒不再重排），以及录音的 `RECORD_AUDIO` 权限与 `FOREGROUND_SERVICE_MICROPHONE` 前台服务（后台录音，plan B） |

## 真机安装

签名已在本机配好：钥匙串里有 `Apple Development: 1661287843@qq.com` 证书，Xcode 已登录该
Apple ID，工程里写死了 `DEVELOPMENT_TEAM = UK9L3XHV39`。所以 `flutter run -d <设备 id>`
理论上可直接装到真机——**但真机安装本身尚未实测**。

换机器 / 换 Apple ID 时需要在 Xcode 里重配一次（本步是账号级的，只能交互完成）：

1. `open ios/Runner.xcworkspace`
2. Xcode → Settings → Accounts → `+` → 登录你的 Apple ID
3. 左侧选 Runner target → Signing & Capabilities → 勾选 *Automatically manage signing*，
   在 Team 里选你的团队（免费 Apple ID 也可以，会生成个人开发证书）

未配好时 `flutter build ios`（真机包）会停在
`No valid code signing certificates were found`。

⚠️ 另一个可能的前提：本机 Xcode 是 **16.2（iOS 18.2 SDK）**，而你的 iPhone 跑的是
**iOS 27.0**。如果安装时报 *Unsupported OS version*，那就是 Xcode 太旧，需要换成带
iOS 27 SDK 的版本。

> 工程文件已随 Xcode 16 升到新的对象格式（`objectVersion 60`），**旧版 Xcode 打不开**。

## 界面截图巡检

模拟器可以截图，所以界面观感不必只靠人眼扫：

```bash
DEV=$(xcrun simctl list devices available | grep -m1 -o '[0-9A-F-]\{36\}')
xcrun simctl ui $DEV appearance light          # 或 dark

# 一边跑巡检（每屏停留 5 秒），一边在外面循环截屏
( for i in $(seq -w 1 70); do
    xcrun simctl io $DEV screenshot /tmp/tour/$i.png; sleep 1.3
  done ) &

export NO_PROXY=127.0.0.1,localhost
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/app_screens_test.dart \
  -d $DEV
```

覆盖：首页（未滚动/已滚动）、回顾、统计（7 天与 30 天）、设置、**五个二级页**
（v3.5 起加上**外观**与**睡眠设置**；另有数据导入、睡眠洞察、演示数据；
**导出页与罗盘不在巡检脚本内**）、
睡眠详情（含展开的声音卡）、助眠音效面板、**会话页两态**（v3.2 补进行中：夜景全貌与场景
选择器、长按结束时的横向填充按钮、长按到底后的评星弹层；**v3.3 补入睡前**：晚安那一屏、
从「完整设置」打开的白噪音底部弹窗、**在弹窗里真的选中一个音再停掉**、按下「开始睡眠」
翻到进行中）。`integration_test/`
不参与 `flutter test`。

**桌面平台也能跑（不必开模拟器）**，`-d macos` 即可；`integration_test/` 下还有一条
**不需要界面**的用例，专门钉住助眠音那条平台路径：

```bash
export NO_PROXY=127.0.0.1,localhost
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/noise_playback_test.dart -d macos
```

它会把一条**打包素材**交给平台解码并起播（音量 0，不出声），断言播放器进到可播状态。
**为什么非要有它**：那条路径整条都在平台侧（`setAsset` → 资源包 → 解码器 → 播放器），
widget 测试里的假播放器一步都走不到，巡检脚本又只开弹窗、从不选声音——两个缺陷就是从这个
缝里漏出去的（会话规格 §17.7）。素材换成本地打包录音后，这条用例改钉「资源真的能被解码」，
原先那条「合成的 WAV 有没有落盘」随之作废。
（手动补录页**不在**巡检脚本内。v3.0 把脚本里的「记录」改成了「回顾」，但**那一轮没有重跑
`flutter drive`**——见「验证记录」的未验证项。）

会话页那几步有两个实测到的坑：**（1）动画只在推帧时前进**——集成测试的 live binding 里，
`await Future.delayed` 光等时钟过去，按钮的填充条会停在原地，所以长按那两步走
`tester.pump(100ms)` 的循环（脚本里的 `holdFinishButton`），不是单纯等时间。
**（2）走到会话页之后不能用 `pumpAndSettle`**——两态都挂着一个 60 秒循环的夜景动画控制器，
`pumpAndSettle` 永远等不到「没有动画」的那一刻、会 `timed out`；`settle` 辅助函数因此先看页面
上有没有 `HoldToFinishButton` 或「准备好休息了吗？」，在会话页就改用显式推帧（步进时长与原本
的等待相当）。

三点实测到的注意：

- `flutter drive` 的 `takeScreenshot` 通道在本机**不可靠**：同一条命令有时出图有时一张不出，
  日志停在 `request_data message is taking a long time to complete`。所以巡检只负责**导航并停留**，
  截图交给外面的 `simctl` 循环——`simctl` 一次都没漏。
- 驱动时**必须**设 `NO_PROXY=127.0.0.1,localhost`。VM Service 连的是本机端口，
  被代理拦掉会表现为「连不上 VM Service」。
- **macOS 上还会撞到系统的文件夹授权框**（2026-10-03 实测）：巡检跑起来之后，
  「`night_sleep` 想访问『文稿』文件夹」的 TCC 弹框会盖住应用窗口，而本机没给 osascript
  辅助访问权限、**点不掉系统对话框**——抓到的帧全是那个弹框，应用一步都拍不到。
  这台机器上「巡检在 macOS 跑不完」多半是它，而不是脚本本身（脚本那次其实
  `All tests passed`，只不过窗口被挡住）。**要跑 macOS 巡检，先手动把那个授权框点掉
  （或改从非「文稿」目录跑），再开始抓拍。**
- **跑之前先把息屏和锁屏挡住**（`caffeinate -d &`，或临时把「需要密码」关掉）：
  锁屏之后 Flutter 不再产帧，而巡检每一步都在推帧，整趟会**静默停摆**，日志停在
  `request_data message is taking a long time to complete`，看上去像是卡在某一屏。
  2026-10-03 实测撞到一次（机器 00:5x 自动锁屏，巡检随后一动不动）。
  上面那条「助眠音效面板卡住 95 秒每帧相同」很可能也是同一回事。
- 深色模式：`xcrun simctl ui $DEV appearance dark` 后重跑一遍即可。应用默认「跟随系统」，
  会跟着切。

## 构建 iOS / macOS 的网络前提

Flutter 3.47 用 Swift Package Manager 解析插件依赖，而 `sqlite3` 的构建钩子还会从
GitHub Releases 下载预编译库。**本机实测直连即可跑通**，代理是可选的：

```bash
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn   # 引擎产物

flutter build macos --debug
flutter build ios --simulator --no-codesign                     # 无需签名
flutter build ios --no-codesign                                 # 真机包；签名已配好，可加 --no-codesign 跳过
```

- **代理是可选的**：若直连拉不到引擎产物、或 SPM 的 git 克隆超时，再补上本机代理
  `export HTTPS_PROXY=http://127.0.0.1:7890 HTTP_PROXY=http://127.0.0.1:7890`。
  本轮终验时 `127.0.0.1:7890` **并没有在监听**，两条构建都是去掉代理变量、只留
  `FLUTTER_STORAGE_BASE_URL` 直连跑通的——所以别把代理当成前提写进脚本。
- `sqlite3` 的构建钩子偶发 GitHub Releases 下载超时，原样重跑即过。

真机签名已配好（团队 `UK9L3XHV39`，见「真机安装」）；若要跳过签名仍可加 `--no-codesign`。

## 平台配置

Bundle ID、Android application ID 与发布账号保持 Flutter 默认占位配置
（`com.example.nightSleep`），待项目方提供后配置；真机签名团队已配置（见「真机安装」）。**通知权限仅在用户打开提醒开关时申请**
（未在首次启动时弹窗）；麦克风权限仍未申请。**v3.7 起应用会联网**：共 4 处对外请求
（获取可用模型、连通性测试、查询余额、生成洞察），**全部由用户点击触发**，全部只发结构化
睡眠字段（**不含用户备注**），密钥只进请求头、不落日志不落盘；导出仍是把文件交给系统分享
面板、**去向由你选择**，应用自己不发起传输。

## 验证记录

本机环境：macOS 14.8.9（23J631，Intel），Flutter 3.47.5 stable。

**v3.8（2026-10-03：助眠音效换成打包实景录音）最近一次复跑：**

- `dart format .` → 无额外改动；`flutter analyze` → **No issues found**
- `flutter test` → **469/469 通过**（上一版 479；净减 10：删掉合成器的 `noise_synth_test.dart`，
  新增 `noise_asset_test.dart` 5 条，其余为既有用例的 import 与名称跟改）
- **变异验证**：把音效格宽度从「面板宽度 ÷ 条数」换回「屏幕宽度 ÷ 条数」，
  `test/noise_sheet_test.dart` 的「宽屏下面板限宽，五格仍是一行且不溢出」**立刻变红**；
  还原后复绿
- **素材生成管线逐条量过**（ffmpeg 9.0，`ebur128=peak=true`）：

  | 文件 | 时长 | 响度 | 真峰 | 循环点样本阶跃 / 该文件步进 p99 | 字节 |
  | --- | --- | --- | --- | --- | --- |
  | `forest.m4a` | 75.000 s | −22.1 LUFS | −3.0 dBFS | 2470 / 4031 | 745 KB |
  | `fire.m4a` | 71.000 s | −23.0 LUFS | −1.9 dBFS | 1632 / 5828 | 800 KB |
  | `ocean.m4a` | 75.000 s | −22.2 LUFS | −2.8 dBFS | 789 / 4208 | 742 KB |
  | `stream.m4a` | 75.000 s | −22.1 LUFS | −3.0 dBFS | 1532 / 4190 | 761 KB |
  | `wind.m4a` | 44.000 s | −22.3 LUFS | −5.2 dBFS | 122 / 1071 | 435 KB |

  合计 **3.40 MB**；**响度跨度 0.9 LU**（源素材是 14 LU）；真峰全部 ≤ −1.9 dBFS，无削波；
  接缝阶跃全部落在各自步进分布的 p99 以内，即听不出接缝。解码长度精确等于标称时长，
  说明 `m4a` 的 edit list 已裁掉 AAC priming，接缝处不会多出静音。
- **打包资源真能被解码并起播**（macOS，真平台）：
  `flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/noise_playback_test.dart -d macos` → **All tests passed**。
  这条覆盖的是 widget 测试一步都走不到的路径：`setAsset` → 资源包 → 平台解码器 →
  `ProcessingState.ready`（音量 0，不出声）。它同时证明了**素材确实打进了应用包**
  （pubspec 的 `assets/noise/` 写错的话，这里会以加载失败收场）。
- **尚未做**：**听感未核对**（五条的主观可用性、切换时 0.9 LU 的响度差、循环接缝是否可闻）；
  **素材授权未落实**（见「未实现」表）；5 格新布局**无截图核对**（只有几何断言）。

**v3.7（2026-10-03：DeepSeek 余额查询 / 连通性测试 / 详情页重新生成）最近一次复跑：**

- `dart format .` → 无额外改动；`flutter analyze` → **No issues found**
- `flutter test` → **479/479 通过**（上一版 424；本轮净增 55 条：`insight_service_test.dart`
  18 条、`insight_prompt_test.dart` 7 条、`sleep_insight_test.dart` 9 条、
  `insight_credentials_test.dart` 6 条、`app_cache_test.dart` 7 条，
  `pages_widget_test.dart` 补 5 条交互用例，`model_catalog_test.dart` 补 2 条能力表用例，
  另把配置页那条「标注未接入项」改写为「给出实测支持的动作」）
- **清除缓存在真实目录上验证过**（macOS，临时 `integration_test` 脚本，跑完已删）：
  `size()` 读出 8 个白噪音 WAV 共 **6.7 MB**（`du` 报 6.8 MB 磁盘占用，差值来自块对齐），
  > 2026-10-03 注：白噪音改成打包资源后不再进临时目录，这份读数的**内容**不再可复现
  > （`size()` / `clear()` 的语义本身没变）。留下的只有导出副本，未导出时读数为 0 B。
  `clear()` 之后目录里 **0 个文件**、再读为 `0 B`。同一次还顺手确认了 `getTemporaryDirectory()`
  在 macOS 上就是 `~/Library/Caches/<bundle id>`（与 `noise_player.dart` 的注释一致）。
- **钥匙串在真实平台上验证过**（macOS，临时 `integration_test` 脚本，跑完已删）：
  写 → 读 → 覆盖写 → 删全部通过；并且**换一个进程仍读得到**（先跑 `PHASE=write` 的进程写入，
  再用 `security find-generic-password -s flutter_secure_storage_service -a insight_api_key`
  确认条目真的进了系统钥匙串，最后跑 `PHASE=read` 的**另一个进程**读回同一串值）。
  「重启后仍在」这句话就是靠这一步成立的，不是靠推断。**未在 iOS / Android 实测**。
  macOS 走的是旧版钥匙串、**没有加** `keychain-access-groups`（见规格偏差 #8 里的取舍）。
- **开发期会遇到一次钥匙串授权框**，原因已查清并实测过：`flutter build macos --debug`
  产出的是临时签名（`codesign -dv` 报 `Signature=adhoc`、`TeamIdentifier=not set`），
  designated requirement 就是 **cdhash**，每重新编译一次就变一次，旧钥匙串条目的 ACL
  随之对不上。表现是「写入钥匙串之后又重编过」时，下次读会弹一次
  「想要使用您存储在钥匙串的…中的机密信息」，点**始终允许**即可（把新哈希加进 ACL）。
  用写入时的同一个二进制启动**不会弹**（已实测）。正常使用不会遇到这件事，
  只有开发期反复重建会遇到。
- **用户实机复测后补修两条**（第二次是靠读用户机器上的真实库定的性：`app_settings` 存着
  `deepseek / deepseek-v4-pro`、`insights.provider` 全部是 `demo` —— 设置一直是对的，
  缺的是**会话内存里的密钥**，而调试期间应用重启了几次）：
  1. 设置根页那一行改走 `resolveInsightSelection()` 并**说出密钥在不在**（「未填 API Key
     （重启后需重填）」），不再读裸列显示与事实不符的「未配置」；
  2. 详情页「重新生成」**按钮常驻**，跑不了时变灰 + 一句指名道姓的说明，点它不发请求。
- 回归用例：`sleep_insight_test.dart` 的「全新安装也照样给按钮」「没填 API Key 时按钮仍在
  但变灰」，`pages_widget_test.dart` 的两条根页副标题用例。
- **活体冒烟（用真实 key 打真接口，一次性脚本，跑完已删；脚本与仓库都不含该 key）**：
  余额读取成功、连通性通过、生成返回 `score=82` 与一段中文总结。这一条是本轮唯一能证明
  「地址、请求体、响应解析在真实服务商上确实成立」的证据——其余测试全部用 `MockClient`。
- **已变异验证**：`SleepEntry.scoreSource` 退回只看 `isUsable` → 「模型没给分时回退到
  本地估算」变红；连通性判定改成要求 `content` 非空 → 「推理模型正文为空也算连通」变红。
- **未实测**：OpenAI 的对话路径（与 DeepSeek 同一份代码，但没有 OpenAI 的 key）；
  Claude 的对话与余额（**刻意未实现**，见规格偏差 #46）。
- **未目视核对**：详情页常显的洞察区块、配置页三个动作按钮的浅色/深色观感与排版，
  以及 `¥` 读数在窄屏下的换行，**只有几何/结构断言**（同 v3.5 / v3.6 的待办）。

**上一版（v3.6，2026-10-03：确认弹窗改用 iOS 系统组件）复跑：**

- `dart format .` → 无额外改动；`flutter analyze` → **No issues found**
- `flutter test` → **424/424 通过**。本轮只重写 `test/confirm_dialog_test.dart`（仍是 7 条，
  断言对象从「自绘特征」换成「系统组件特征」：`CupertinoAlertDialog` 在位、取消/蒙层返回
  `false`、确认返回 `true`、取消在左确认在右、破坏性取 `danger` 非破坏性取 `accent`、
  深色下亮度跟随应用而非系统）。三处调用方一字未改，`pages_widget_test.dart` 与
  `record_edit_delete_test.dart` 里依赖文案/可见性的确认用例**直接复用、无需改动**。
  **已变异验证**：把实现退回 HEAD 的自绘版本，「系统组件」「破坏性取 danger」「深色亮度」
  3 条立刻变红，而 4 条返回语义/按钮次序的用例与实现无关、保持绿。
- **构建**：本轮**没有重跑任何构建**，只跑了 `flutter test` 与 `flutter analyze`。
- **未目视核对**：新弹窗底色是半透明材质叠在模糊背景上，浅色/深色下的实际观感与它同全仓
  其余玻璃材质的协调度**只有几何/结构断言**，需人工核对（同 v3.5 设置页的待办）。

**上一版（v3.5，2026-10-03：设置页信息架构重排 + 两个新二级页 + 开屏页）复跑：**

- `dart format .` → 无额外改动；`flutter analyze` → **No issues found**
- `flutter test` → **424/424 通过**（本轮净增 9 条：新增开屏 5 条；设置页那两组重写后
  净增 3 条——删掉 3 条随版式作废的旧用例，补上 6 条新的二级页用例；又补 1 条
  「下拉箭头贴右」的几何回归）
- 三条新断言做了**变异验证**，逐条确认能变红：
  - 把滑块 `_snap` 退回直接 `clamp`（去掉 0.5 小时吸附）→「按 0.5 小时吸附，两端不越界」
    报「滑块在 0.13 处落库 342 分钟，没有吸附到 0.5 小时」
  - 开屏收起条件去掉 `settingsAsync.isLoading` →「设置还没读到第一帧时，开屏不会先收起」
    报找不到 `SplashScreen`
  - 把声音检测的副标题换成原型那句「检测打鼾、梦话并生成洞察」→ 红线用例报找不到
    「尚未接入录音」
- **提醒相关的 9 条既有用例全部通过在**（挂载点从设置根页改到 `/settings/sleep`），
  行为一字未改：权限被拒回弹、开启时连同默认时刻落库、全量重排、`denied` 时的「去系统设置」、
  「删除全部本地数据」的会话收尾。
- **巡检脚本已按新文案更新**（`integration_test/app_screens_test.dart` 新增「外观」「睡眠设置」
  两步，导入/洞察两步改用新行名），`flutter analyze` 覆盖了它的编译；**未实跑**
  （要 `flutter drive` + 设备）。
- **目视核对（macOS，`flutter run -d macos`）**：**开屏页通过了**。深蓝渐变、两圈轨道环、
  星点、圆角图标（moon + 两道声波弧的描线都在）、`夜深`（宽字距）与`听见夜晚，看见睡眠`、
  底部进度条，逐项在位，与原型一致。证据图：`screenshots/v3.5-splash.png`（文案与进度条都在
  的那一帧）、`v3.5-splash-early.png`（只到轨道环与星点的早期帧，可见入场是从无到有）。
- **设置根页与「外观」「睡眠设置」两个新二级页仍未目视核对**：macOS 巡检跑到一半弹出了系统
  的「`night_sleep` 想访问『文稿』文件夹」授权框，它盖住了应用窗口，而本机没给 osascript
  辅助访问权限、点不掉系统对话框，抓到的帧全是那个弹框。这一条同时解释了由来已久的
  「巡检在 macOS 上跑不完」——**那多半不是脚本的问题**（见「界面截图巡检」新增的注意点）。
  行内下拉在 390px 与 iPad 横屏下的换行、自绘滑块的拖拽手感，因此**仍然只有几何与结构断言**。
- **已知项**：开屏挂在 `AppScaffold` 的 `Stack` 里，冷启动若有深链直达子页会被盖住
  （当前没有深链）。

**v3.4（2026-10-03：iPad 横屏下的两处弹层缺陷）最近一次复跑：**

- `dart format .` → 格式化改动文件；`flutter analyze` → **No issues found**
- `flutter test` → **415/415 通过**（v3.3 那次的 413 之后净增 2 条回归用例）
- 两条新回归都做了**变异验证**：把音效格宽度换回「屏幕宽度」→
  「宽屏下面板限宽，八格仍是四列两行且不溢出」报 1 行 8 格；把弹层浮起 24px 加回去 →
  「宽屏下面板限宽 560，但下沿仍贴屏幕底」报 `810 ≠ 834`
- **目视核对（使用方自验，iPad 横屏）**：音效格那一处已确认修好；弹层贴底那一处是同一轮
  提出后新改的，**本机只做了 1194×834 的 golden 渲染**（面板贴底、四列两行、音量条与定时
  chips 都在位），**未在真机重新核对**。**仍未覆盖**：真实 iPad 上的安全区取值、深浅两套
  主题、以及 iPhone 横屏。

**同日补丁（2026-10-03 晚：白噪音在 macOS 上放不出声——两处缺陷）最近一次复跑：**

- `dart format` / `flutter analyze` → **No issues found**
- `flutter test` → **413/413 通过**（未增删用例：两处修复都在平台侧，widget 测试用的是假
  播放器，本来也盖不到——这正是它们能漏出去的原因）
- `flutter drive --target=integration_test/noise_playback_test.dart -d macos` → **All tests
  passed**（真合成 → 真落盘 → 真起播，音量 0 不出声；**2026-10-03 当日的记录**，素材换成打包
  录音后这条链路已消失）。**并做了正反对照**：先清掉缓存目录
  （实测 `getTemporaryDirectory()` 返回时 `exists=false`，就是报错里那个路径），去掉
  `directory.create(recursive: true)` 那一行再跑，同一条用例报的正是截图里那句
  `无法生成音频：PathNotFoundException … errno = 2`；恢复后冷跑通过，缓存目录里落下
  `noise-fan.wav` 882,044 字节（20 秒 × 22050Hz × 16 位 + 44 字节头）。
- **巡检（`integration_test/app_screens_test.dart`，macOS）本轮跑了两次，都没跑完**：
  - 第一次**暴露了新加那一步自己的错**：`find.text('风扇')` 同时命中弹窗宫格与**底下那一屏**
    的常用白噪音四格（弹窗是叠上去的，下面那棵树还在），`ensureVisible` 抛
    `Bad state: Too many elements`，还把后面三步一起带塌
    （`TOUR skipped session-*`）。已改成用 `GridView` 限定范围——整个 `lib/` 里只有这个弹窗
    用 `GridView`。
  - 第二次跑到 00:5x 时**机器自动锁屏**：锁屏后不再产帧，每一步都在推帧的巡检随即停摆，
    日志停在 `request_data message is taking a long time to complete`。这条已记进
    「界面截图巡检」的注意点（**先 `caffeinate -d`**）。
  - 所以**巡检全趟通过这一条仍然没有被验证**——与 v3.0 / v3.2 / v3.3 那几条同类，
    继续挂在下面的「未验证」里。两次都没写库（`active_sessions` 为空、DB 文件时间戳未变）。

**v3.3（2026-10-03：会话页补「入睡前」态，记录起点挪进页内）最近一次复跑：**

- `dart format .` → `Formatted 122 files (6 changed)`（本轮改动的文件）
- `flutter analyze` → **No issues found**
- `flutter test` → **413/413 通过**（v3.2 那次的 400 之后，净增 13 条：新增 20 条、删掉 7 条
  被新语义取代的旧用例）。本轮新增/补测（新断言逐条做了变异验证）：
  - **入睡前态 10 条**（`test/session_setup_page_test.dart`）：hero 三段文案与「开始睡眠」按钮
    在位、旧的「没有正在进行的睡眠」空状态**不再存在**；**进页面不写库**；**点「开始睡眠」才
    写会话行**且 `startAtUtc` 就是按下的那一刻；草稿（场景 / 白噪音 / 音量）随行一次写进去；
    收起不写库、停掉试听、回上一页；草稿不跨页存活；闹钟权限被拒与通过两条；
    宽屏 1200 下两态都居中限宽 680
  - **数据 3 条**（`test/session_repository_test.dart`）：`start()` 一次写全草稿；
    不传时默认值不被新参数带偏；**首次并发读设置不炸**——最后这条是**既有缺陷**的回归
    （`getSettings()` 的「先读后插」在并发首读时撞 `UNIQUE constraint failed:
    app_settings.id`，正是入睡前态一帧两个读者稳定触发的）
  - **夜景组件 4 条**（`test/session_night_widgets_test.dart`）：入睡前变体多一行
    「夜景氛围 / 左右滑动切换」而进行中变体没有；选中卡是**绕中心** `scale(.98)`
    （订正照抄错层，见会话规格 §17.6）；另两条白噪音生命周期用例从会话页搬过来（那边
    的点按入口已被收紧掉）
  - **媒体查询 3 条**（`test/session_setup_page_test.dart`）：窄屏（375）常用白噪音四格**竖排**
    （标签在图标下方）、宽屏（430）并排；高屏（≥860）hero 撑到 285、矮屏更矮——这条挡的是
    「把 285 写死、不再看屏高」
  - **首页入口 1 条**（`test/pages_widget_test.dart`）：点「开始入睡」**只推入页面、不写会话行**，
    收起后库里仍为空（走真实路由，顺带覆盖 `app.dart` 注册的 `path: 'sleep/session'`）
- **本轮没有重跑任何构建**（`flutter build macos` / `flutter build ios`），也**没有重跑
  `flutter drive` 巡检**：巡检脚本已按新流程改写（入睡前那一屏 → 「完整设置」弹窗 →
  「开始睡眠」→ 长按/评星），但**一次都没执行过**，见「未验证」。
- 逐句核对了原型 `index.css` 的**最终生效层**（第 1730–1960 行那段
  `/* ── Immersive sleep controls ── */` 覆盖了前面第 1557 行起的同名规则），并借此订正了两处
  照抄错层：场景卡选中态（`scale(.98)` 而非 `translateY(-2px)`）与内容限宽（两态都是 680）。

**上一版（v3.2，2026-10-02：会话页照原型「睡眠进行中」态重建）复跑：**

- `dart format .` → 只有 `test/pages_widget_test.dart` 有**既存**的格式漂移（不属于本轮改动，
  已 `git checkout` 还原、未提交）；本轮改动的文件本身无需格式化
- `flutter analyze` → **No issues found**
- `flutter test` → **400/400 通过**（v3.0 那次的 337 之后，v3.1 与 v3.2 累计新增 63 条）。本轮
  新增/补测：夜景几何 19（`test/night_backdrop_test.dart` 16 + `test/night_scene_test.dart` 3，
  含「流星只在 `meteor` / `moon` / `galaxy` 三场景可见」这条**订正**）、月亮标记 6
  （`test/sleep_moon_mark_test.dart`，含「丢弃 `<filter>` 后不打印 unhandled element」）、
  会话页夜景 widget 7（`test/session_night_widgets_test.dart`：8 种场景、`disableAnimations`
  停表、弹窗九宫格与四档时长、**浅色应用主题下弹窗内仍是深色令牌**）、长按按钮 7
  （`test/hold_to_finish_button_test.dart`，含
  「**开启「减弱动态效果」时 1.5 秒守卫仍按真实时长计时**」这条**行为修复**的回归、
  「**按满触发后指针被取消，再短按仍给提示**」这条 `onPointerCancel` 复位的回归）、
  v4→v5 迁移 4（`test/schema_migration_test.dart` 的 `v4 → v5` 组）、场景持久化
  （`test/session_repository_test.dart`）与 `SleepSession.elapsedClockAt`
  （`test/sleep_session_test.dart`）；会话页自身补到 33 条
  （`test/sleep_session_page_test.dart`，含「浅色主题下会话页仍然是深色」这条**真的跑浅色主题**
  的回归）。新断言逐条做了变异验证。
- **构建**：本轮**没有重跑任何构建**（`flutter build macos` / `flutter build ios`），只跑了
  `flutter test` 与 `flutter analyze`。

**上一版（v3.0，2026-10-02：会话 + 回顾 + 起床闹钟 + 显示名）终审修复后复跑：**

- `dart format --set-exit-if-changed .` → 无改动
- `flutter analyze` → **No issues found**
- `flutter test` → **337/337 通过**。本轮新增/补测（未逐条列举，完整场景见规格第 9 章）：
  v3→v4 迁移 6（`test/schema_migration_test.dart`，含「重建后 `quality` 可空」
  「既有记录/阶段/片段/洞察/设置一行不动」「子表外键仍级联」「再次打开不重跑」）、
  会话领域 13（`test/sleep_session_test.dart`）、会话仓库 16
  （`test/session_repository_test.dart`，含 `finish` 不写阶段、时长守门、冷启动恢复）、
  会话页 widget 28（`test/sleep_session_page_test.dart`，含诚实文案在位、闹钟被拒回弹、
  白噪音收起/离开页面仍继续、闹钟胶囊已过起床时间不再说「还有 0h 0m」）、
  回顾页 10（`test/review_page_test.dart`）、会话闹钟（`test/reminder_scheduler_test.dart`
  的起床闹钟组、`test/reminder_sync_test.dart` 的会话闹钟组 7，含「调度器没就绪时不排
  9003」）、显示名 5（`test/app_display_name_test.dart`）；首页与手动补录页的改动落在
  `test/pages_widget_test.dart`。终审修复波另补「删除全部本地数据」的收尾断言
  （`test/reminder_settings_test.dart`：残留会话被清、9002/9003 重新推导、白噪音停掉）。
  **新断言逐条做了变异验证**（拆掉实现会真的变红）。
- 上一版（v2.9，2026-09-29）复跑记录：**238/238 通过**（当时从 176 起，逐步增至 216，终审修复波再补 1 至 217：
  schema v3 迁移 6（含 `record_id` 为空的洞察存活分支）、
  演示数据重装与幂等 2、冷启动播种兜底 4、图标取色 4、顶部渐变与安全区/错误分支留白 3、
  关于卡片居中与版本号 2、自绘确认弹窗 7（另有演示数据页的确认 1，落在 `pages_widget_test`）、
  删除图标 2、`PrimaryAction` 禁用态 10；
  v2.7 再补 4：标签条浮起量与页面底部留白同源、胶囊实测高度 65px（`test/tab_bar_inset_test.dart`）；
  v2.8 再补 12：底部模糊带的遮罩层级（套在 `BackdropFilter` 外面）与遮罩方向、模糊半径 14、
  填充 0→78% 且单调递增、高度 = 底部预留 + 20（含无安全区的 113）、宽屏不渲染、整条带不拦手势
  （`test/bottom_fade_test.dart`）；
  v2.9 再补 5：应用图标几何分平台断言（实体四角透明、中心不透明、实体包围盒 824×824 且四边留白 100、
  iOS 仍满幅、无 alpha 通道（色型 2）；另有一条覆盖七个尺寸——文件名与真实像素尺寸绑定、实体宽随尺寸
  等比、实体下方投影存在、圆角半径带宽。`test/app_icons_asset_test.dart`）；
  各测试文件覆盖的场景见
  [规格第 9 章](docs/superpowers/specs/2026-09-28-night-sleep-design.md)）。
  本轮多处断言做了**变异验证**（拆掉实现会真的变红），不是「不可能失败的断言」

- **构建**：v2.5 那次 `flutter build macos --debug` / `flutter build ios --simulator --no-codesign`
  成功产物的记录仍适用；**本轮（v2.6）没有重跑任何构建**。因此本轮新增的
  `package_info_plus` 依赖虽然连 `macos/Flutter/GeneratedPluginRegistrant.swift` 一并提交了，
  但它在新构建里的原生注册、以及设置页版本号的实际取值**都没有在构建/运行中验证过**
  （测试里用的是包自带的 `setMockInitialValues`）
- **应用图标构建（v2.9）**：`flutter build macos --debug` 于 **2026-09-29** 成功，
  `build/macos/Build/Products/Debug/night_sleep.app/Contents/Resources/AppIcon.icns` 的时间戳为
  **2026-09-29 18:56:15**（源 PNG 为 18:12:25，确认本次重建吃到了新产物）。用 `iconutil` 把该
  `.icns` 抠出来量了 256px 那一档：色型 6、实体 206×206、四边留白各 25、**画布角与实体角 alpha 均为 0**、
  中心 255——即**构建产物里确实带着烘焙好的圆角**，不是只有源文件对。
  **但 Dock 里实际画出来的样子仍未经人眼确认**（本任务不做目视，见下「未验证」）——断言与量产物
  只能保证文件几何正确，保证不了 Dock 的绘制；清缓存步骤见 CHANGELOG 2.9
- **界面巡检**：
  - v2.5 那轮完整巡检（iOS 模拟器截图，浅色/深色各一遍，逐屏看过首页/记录/统计/设置/
    二级页/睡眠详情/助眠音效面板）的记录仍适用。
  - 本轮**只有任务 5（顶部渐变）真的跑了模拟器**：用临时巡览脚本（已删）依次切到四个一级页
    各下拉 300px，宿主机 `xcrun simctl io screenshot` 循环采样，iPhone 16 Pro、浅色与深色
    各看一遍，确认顶部硬分界消失、未滚动时标题不被状态栏压住。
  - **本轮其余新增/改动的界面没有做目视确认**：自绘确认弹窗（含浅色下卡片描边是否可见）、
    垃圾桶图标、禁用按钮的页内提示、关于卡片的居中与版本号行——这些只有几何/结构断言，
    没有截图核对。这是有意的取舍：有一位实现者曾在跑模拟器截图时卡死 600 秒，
    此后本轮禁止后续任务碰模拟器，目视集中留待下一轮。
  - v2.7（标签条浮起量 34pt → 20pt）**同样只有几何断言**：只截了一张模拟器截图用于确认
    改动前的现状，改完后没有再看一眼，实际观感需人工确认。
  - v2.8（底部模糊带）**已在 2026-09-29 下午补做目视核对**（iPhone 16 Pro 模拟器，手段沿用上节
    「界面截图巡检」：宿主机 `xcrun simctl io booted screenshot` 循环采样 +
    `flutter drive --target=integration_test/app_screens_test.dart`）。要看的三件事都通过：
    (1) **带子顶边（离屏幕底 121pt）没有硬边**——离带顶约 20pt 处的「最近记录」标题（离底约 91.7pt）
    在两套主题下都清晰，该处的有效 wash 只有约 9%（遮罩与填充在带顶附近都接近 0），越往屏幕底越重，
    是连续过渡；(2) **方向对**（越靠近屏幕底越实）——浅色统计页上胶囊下方那段的「平均时长」只剩
    很淡的残影，深色首页上胶囊下方的内容被洗到接近 `bgBase`（黑），而带子上方的内容
    （「推荐 7–9h」「雨声·海浪·篝火」）保持清晰；(3) **胶囊下半部没有发闷、没丢玻璃透感**——
    浅色下胶囊仍通透，深色下胶囊仍读作正常的玻璃条（`bgNavbar` 76% 填充主导）。
    **覆盖面（不是逐页逐屏核对）**：浅色看过首页（滚动后）、统计页、睡眠详情/助眠音效弹层
    （弹层盖在带子之上、**不被**底部带模糊，属预期行为）；**深色只看过首页静置态**。
    两条如实记下的偏差：**深色那一遍不是巡游览到的**——把模拟器切 dark 对 app 无效，因为 app 里存的
    外观偏好是「浅色」（`app_settings.theme_mode = 'light'`，这是正确行为、不是缺陷）；深色帧是把该
    偏好**临时**改成 dark、用 `flutter run` 起应用截的，截完已还原为 light（演示数据 5 条未受影响）；
    巡检中途在助眠音效面板**卡住不动**（95 秒内每帧完全相同），已终止——上节本来就记过
    `flutter drive` 这条通道在本机不可靠。
    证据图（`screenshots/`，**该目录在 `.gitignore` 里、未入库**，这三张只存在于本机工作树；
    均为 1206×460 的底部裁剪，来自同一次采样的原始帧，未重新生成或美化）：
    `screenshots/v2.8-light-home-scrolled.png`（浅色首页滚动后，「最近记录」清晰、其下化开）、
    `screenshots/v2.8-light-stats.png`（浅色统计页，最底部「平均时长」只剩残影）、
    `screenshots/v2.8-dark-home.png`（深色首页，胶囊下方洗到接近黑）。
  - v3.1（会话页重排）**已目视核对**（2026-10-02，iPhone 16 Pro 模拟器 iOS 18.3、深色、
    宿主机 `simctl` 每 1.3 秒采样）。看过的：**收合态整页**（圆环 → 圆形「结束」按钮 + 外圈
    进度环 → 「按住不放」→ 今晚的设定两个开关，鼾声那行注明「尚未接入录音，开关只保存偏好」
    → `白噪音 · 音量 50% 更多 ⌄`）；**按住中的进度环**（红色弧从 12 点顺时针扫到约 40%，
    松手退回）；**展开的白噪音区**（八宫格 + 音量 + 定时 + 说明**整块都在屏幕内**）；
    **按住到底后的评星弹层**（且跑完后「回顾」页确实多出一条 `来自：睡眠会话` 的记录）。
    **展开区落在屏幕外**这个问题正是这次目视发现的：点了「更多」只看到箭头翻面，内容全在
    折叠线以下（60m 那颗 chip 落在 1112.5，屏幕高 932），已按此加了自动滚动（见规格 §四）。
    一条如实记下的：第一遍用 `Future.delayed` 模拟按住时，环停在 40% 走不完——集成测试的
    live binding 里动画只在推帧时前进（见上节），改用推帧循环后才拍到了评星那一帧。
    会话页已补进常驻巡检脚本，**末尾一轮跑通**（`flutter drive`，02:34，`All tests passed`；
    只跳过 `settings-demo` 与 `detail-sheet` 两步，原因与本次改动无关）。
- **未验证（不得视为已完成）**：
  - **v3.0 新增的未验证项**（逐条不得当成已完成）：
    - **起床闹钟是否真的到点投递**：Dart 侧的调度契约（`scheduleOnce` 不重复、9003 不被
      `sync` 抹掉、`_resume` 映射）由测试钉住，但**「到点真的响了」需真机确认**——与下一条
      通知投递是同一类问题
    - **`timeSensitive` 当前并不会穿透专注模式**：iOS / macOS **请求**了
      `interruptionLevel: timeSensitive`，但工程里没有配套的 Time Sensitive
      Notifications entitlement（`ios/` 下没有任何 `.entitlements`，
      `macos/Runner/*.entitlements` 也没有
      `com.apple.developer.usernotifications.time-sensitive`），按 Apple 的规则该级别会被
      系统降级。**解锁需要**：加 entitlement、在 App ID 上开启该能力，并真机开专注模式实测
    - **宽屏（macOS 侧边栏）下的会话页与回顾页**：会话页是推入式全屏页，**没有在宽屏下逐屏
      核对版式**（不能默认窄屏版式拉伸后可用）
    - **Dock / 桌面 / 菜单栏显示名的实际观感**：`CFBundleDisplayName` 改成了「夜深」，
      但 plist 改了不等于系统重读了缓存；**没有人看过 Dock / 桌面实际画出来的名字**。
      另外 **macOS 菜单栏读的是 `CFBundleName`（工程里仍是 `night_sleep`），可能仍显示英文名**，
      需人工核对（`PRODUCT_NAME` 与构建路径不受影响）
    - **`integration_test/` 的「记录 → 回顾」改动没有跑过 `flutter drive`**：该目录不参与
      `flutter test`，本轮的「记录 Tab → 回顾」改名与相关巡检脚本改动**只做了静态检查**，
      需要人工跑一次 `flutter drive`（见「界面截图巡检」）确认巡检仍能走通
  - **v3.2 新增的未验证项**（逐条不得当成已完成）：
    - **夜景动画的观感、真机帧率与耗电未实测**：八套场景动画只用单测钉了「几何算式」与
      「减弱动态效果时停表」，**测试盖不住观感**，需在真机/模拟器上目视核对动画节律、是否
      掉帧、整夜挂着的耗电
    - **`flutter_svg` 丢弃 `<filter>` 导致的近似未目视核对**：月亮原本的外发光靠 SVG 的
      `<filter>`，`flutter_svg` 2.3 会**静默丢弃**它（已实测），改用轨道径向光晕近似——
      近似效果与原型的差距没有人看过
    - **`integration_test/` 不参与 `flutter test`**：本轮对巡检脚本的改动（走到会话页之后改用
      显式推帧、打开并收掉白噪音弹窗）**跑不到**，需人工 `flutter drive` 手动验——与上面
      v3.0 那条「记录 → 回顾」未跑 `flutter drive` 是同一类
    - **事件卡不叠 `backdrop-filter`（偏差 #34）的观感**：这是为整夜挂着省算力的取舍，实际
      读起来是否仍与原型接近，未目视核对
    - **`_RejectedSheet`（时长越界说明层）与评星弹窗在浅色应用主题下仍是浅色面板**（已知不一致）：
      这两块走 `AppSheet`、取**应用主题**，而会话页其余部分是页面自套的 `Theme(AppTheme.dark())`，
      所以浅色主题下会看到一次深浅跳变。本轮**刻意不动**：`AppSheet` 的外观是共享组件的职责，
      改它等于给全站换肤（与偏差 #32 同一理由）。见会话规格 §十三。
      （**白噪音弹窗不在此列**：它走 `showGeneralDialog` + `NightStyle`，并在 `pageBuilder` 里
      显式又包了一层 `Theme(AppTheme.dark())`，浅色主题下也是深色面板。）
  - **v3.3 新增的未验证项**（逐条不得当成已完成）：
    - **入睡前那一屏：已在 macOS 上看过一次，iOS 真机/模拟器仍未看。**
      2026-10-03 用 `flutter run -d macos`（真实 Impeller/Metal 引擎）起应用，在一个约 412pt 宽、
      约 890pt 高的窗口里把这一屏看全了：收起胶囊 / 「睡眠模式」/ 月亮轨道 / 晚安 /
      「准备好休息了吗？」 / 「放下今天，让夜晚慢下来。」/ deck 的夜景氛围选择器（流星夜选中态、
      横向滚动）/ 常用白噪音四格 / 白噪音（未开启）/ 起床闹钟（关，无时刻胶囊）/ 鼾声检测
      （带「尚未接入录音」那句）/ 渐变「开始睡眠」按钮 / 底部提示，**一屏内全部装得下，没有滚动**，
      `flutter run` 日志里**没有异常、没有 RenderFlex overflow**——deck 那层
      `backdrop-filter: blur(24) saturate(130%)`（`ImageFilter.compose` + 色彩矩阵）在真实引擎上
      没有报错。**仍未验证**：小屏（iPhone 那类 ~758pt 可用高度）下按钮与提示是否要滚动才够得着；
      深色观感之外的动效节律与整夜耗电。
    - **`integration_test/` 的巡检脚本改动未执行**：脚本已按新流程改写（入睡前 → 完整设置弹窗 →
      「开始睡眠」→ 长按 → 评星），但**没跑过 `flutter drive`**；与 v3.0 / v3.2 那两条同类
    - **「开始睡眠」按钮在真机首屏是否无需滚动就能点到**：入睡前那一屏比原先长（hero + 设定卡 +
      按钮 + 提示），测试用的是一块超高视口（2000pt），真机（852pt 上下）里按钮是否落在首屏内
      没人看过。若被折到屏幕外，用户要滚一下才能开始——这是本轮引入的真实风险
  - **通知投递**：没有真机 / 模拟器人工确认过「到点了真的会响」。Dart 侧的调度契约
    被测试钉住，但通知是否真的投递、前台是否展示、时区是否选对，都仍需人工确认
  - **系统分享面板**：导出经 `share_plus` 交付，面板的实际弹出与去向选择**没有实测过**；
    导出内容的字节（BOM、CRLF、RFC 4180 转义、不含本地路径与 `AppSettings`）由单元测试覆盖
  - **macOS 未签名调试构建的通知授权行为**：本机钥匙串里没有签名证书，权限可能拿不到或不持久。
    实现按 `permission()` 的真实返回降级（界面照实显示），但这一项只能人工验证
  - **`package_info_plus` 的实际返回值**：只验证过它的 API 形状与「取不到时不显示版本号」的
    降级分支；`version` / `buildNumber` 在**真机 macOS / iOS 上映射到 `CFBundleShortVersionString`
    / `CFBundleVersion` 的对应关系没有实测**（测试用 mock 注入）
  - **本轮 UI 的目视观感**：见上「界面巡检」——确认弹窗、垃圾桶、禁用按钮提示、关于卡片、
    标签条浮起量（v2.7）仍未经眼。底部模糊带（v2.8）已在 2026-09-29 看过一遍（浅色：首页滚动后 /
    统计页 / 详情与助眠音效弹层；深色：首页静置态），但**深色只有首页这一屏、没有逐页核对**，
    浅色下详情/音效弹层以外的二级页（设置、数据导入、洞察服务、演示数据）也未见，故仍有未覆盖面
  - **macOS Dock 图标的目视确认（v2.9）**：产物已重建、其几何也经像素核对（见上「应用图标构建」），
    但**没有人看过 Dock 里实际画出来的样子**——Dock 图标缓存、macOS 版本差异都可能在文件正确的前提下
    画出别的东西。**需人工确认后**才能把 v2.9 这条划掉
  - 真机交互、窄屏宽屏溢出检查：**尚未执行**
    （宽屏侧边栏布局只在 macOS 桌面构建里跑过，未逐屏核对）
  - Android / Web 构建：**尚未执行**（Android 平台目录也不存在，见「未实现」表）
  - 外部服务、小米数据、夜间录音：未接入，不能视为已完成。
    助眠音效已实现（**2026-10-03 起是打包的实景录音**，此前为设备内合成）。
    **起播这条链路**已在 macOS 上由 `integration_test/noise_playback_test.dart` 跑通
    （旧版钉「合成 → 落盘 → 起播」，新版钉「打包资源 → 解码 → 起播」）；
    但**实际发声效果仍没有听过**——那条用例是音量 0，需要人工试听才知道像不像、
    五条之间的响度差与循环接缝听不听得出来
- **AI 模型列表**：DeepSeek 与 Anthropic 的模型 ID 已对照官方文档核实（2026-09-27），
  OpenAI 文档无法访问故未内置任何模型名，需用「获取可用模型」实时拉取
