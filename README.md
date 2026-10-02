# 夜深

「夜深」是一个中文、本地优先的睡眠记录 Flutter 应用。界面按
`docs/superpowers/specs/2026-09-28-night-sleep-design.md` 第 2 章的
Figma Make 原型**最终生效层**实现：iOS 玻璃材质、悬浮胶囊标签条 / 侧边栏自适应导航、
自定义描边图标集、滚轮选择器、浅色/深色主题、离线睡眠记录与 7/14/30 天统计、
睡前「开始睡眠」会话与「回顾」补感受、数据导出（CSV / JSON）与就寝/起床本地通知提醒。
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
    settings/          设置与四个子页（数据导入、数据导出、洞察配置、演示数据）
    onboarding/        首次引导
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
  最近记录卡（阶段色带 + 图例）。主按钮位是「**开始睡眠**」；有会话在跑时换成「**正在睡眠**」
  卡（点它回到会话页）。**卡片上的已睡时长是 build 快照，停在首页不会自动跳动**（只有会话页
  每秒 tick）。
- **睡眠会话**（v3.2）：首页「开始睡眠」→ 推入式全屏会话页（`/sleep/session`），
  **照原型 `SleepView` 的「睡眠进行中」态重建**。整页换成**常暗的夜景氛围**：八种场景之一
  （流星夜 / 极光 / 深海 / 月海 / 云上 / 萤火 / 银河 / 雨夜，横向选择器可切）的暗色渐变 + 网点
  质感，上面浮着场景动画（流星、极光、海浪、云层、萤火、银河、雨丝、星点）；八套动画由一个
  60 秒循环的控制器驱动、全部画在一个 `CustomPaint` 里，系统开「减弱动态效果」时停表。选中的
  场景写进会话行（schema v5 加 `active_sessions.scene_id`），收起页面再进、杀掉应用重开都还是
  同一个夜景。中央是**月亮 + 当前时刻 + `HH:MM:SS` 秒表 +「已进入睡眠模式」**（秒表小时不封顶，
  防「忘了结束」被藏成正常的 `00:00`）。中段是**「当前睡眠事件」卡四行**：开始睡眠 / 白噪音 /
  起床闹钟 / 鼾声检测（鼾声那行照旧注明「尚未接入录音，开关只保存偏好」；白噪音行常驻可点）。
  白噪音的完整设置（八宫格 + 音量 + 定时 15/30/45/60）改成**深色底部弹窗**，点白噪音行打开。
  **「结束睡眠」是全宽横向胶囊，长按 1.5 秒、填充条自左向右扫满才生效**；中途松手或手指滑开
  即作废，短按只给提示与轻震动。会话状态进 SQLite（`ActiveSessions` 单行表），跨重启存活；
  「收起」离开页面而**会话与白噪音继续跑**（关掉弹窗、收起页面都继续响）。「结束睡眠」就地评
  一次星（可跳过），一个事务里写记录（`source = 'session'`）并删会话行；时长不在 `(0, 24h]`
  内**不落库**，让用户选手动补录或丢弃。**它不测量任何东西**——两个时刻来自用户按下的按钮，
  起床时间来自设定。
  **整页常暗**：会话页自己套 `Theme(AppTheme.dark())`，浅色应用主题下进去也是深色（原型的睡眠
  模式如此设计）。**刻意与原型不同的五处**见规格偏差 #28–#32；「事件卡不叠 `backdrop-filter`」
  与「白噪音行只有两态」见偏差 #33–#34。
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
  统一走**按项目令牌自绘的 iOS 风格确认弹窗**（`core/widgets/confirm_dialog.dart` 的
  `showConfirmDialog`）——不引入 `flutter/cupertino.dart`（它自带系统配色与圆角，会绕过
  `AppTokens`）。「清除演示数据」此前**没有二次确认**，本版补上。
- **禁用按钮的页内反馈**（v2.6）：`PrimaryAction` 的 `onTap` 为空即禁用态——不再画启用态的
  顶边高光与蓝色投影、不触发触觉，但会接住点击并回调 `onBlockedTap`。导入页据此在按钮下方
  给出**页内**说明（这是二级页，全局 toast 会被外壳盖住）。启用态观感不变。
- **关于卡片**（v2.6）：文字在卡片内水平居中；版本号改读 `package_info_plus` 的真实构建值
  （`v<version> (<buildNumber>)`），不再是写死的字符串。
- **统计**：7/14/30 天分段控件、时长柱状图（含 7h 虚线目标线、可选中查看）、评分卡、
  四项汇总、梦话转录列表。
- **设置**：外观模式（跟随系统/浅色/深色）、睡眠目标步进器、数据导入入口、数据导出入口、
  就寝/起床提醒开关与时间、夜间录音开关、洞察服务配置、演示数据入口（仅调试构建）、
  删除全部本地数据、关于。
- **AI 模型列表**：按服务商从官方 `GET /models` 实时获取，用会话内的 API Key 认证；未获取前
  显示**已注明核实日期**的内置列表。DeepSeek 为默认服务商。
- **助眠音效**：8 种声音在设备上**实时合成**（`noise_synth.dart`：白/棕/粉噪、雨、海浪、
  篝火、森林、风扇），渲染成 20 秒无缝循环的 WAV 后交给播放器循环播放；音量、定时、
  切换与失败提示均已接通。不打包任何第三方音频。
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
| 小米手环数据导入 | 未接入。需真实导出样本或官方接口文档，导入按钮禁用并说明原因 |
| AI 洞察服务 | 未接入。服务商/模型选择可持久化；API Key 仅存内存，安全存储未接入；余额查询未接入 |
| Android 平台 | 平台目录未生成（`.metadata` 只有 ios / macos / web）。接入时需补 `RECEIVE_BOOT_COMPLETED` 权限与 `ScheduledNotificationReceiver` / `ScheduledNotificationBootReceiver` 两个 receiver（否则设备重启后提醒不再重排），以及录音的 `RECORD_AUDIO` 权限与 `FOREGROUND_SERVICE_MICROPHONE` 前台服务（后台录音，plan B） |

## 真机安装（需要你自己做的一步）

本机钥匙串里没有代码签名证书，Xcode 也没登录 Apple ID，所以 `flutter build ios`（真机包）
会停在：

```
No valid code signing certificates were found
```

这一步是账号级的，必须在 Xcode 里交互完成：

1. `open ios/Runner.xcworkspace`
2. Xcode → Settings → Accounts → `+` → 登录你的 Apple ID
3. 左侧选 Runner target → Signing & Capabilities → 勾选 *Automatically manage signing*，
   在 Team 里选你的团队（免费 Apple ID 也可以，会生成个人开发证书）

完成后我就能直接 `flutter run -d <设备 id>` 装到你手机上。

⚠️ 另一个可能的前提：本机 Xcode 是 **16.2（iOS 18.2 SDK）**，而你的 iPhone 跑的是
**iOS 27.0**。签名解决后，如果安装时报 *Unsupported OS version*，那就是 Xcode 太旧，
需要换成带 iOS 27 SDK 的版本。

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

覆盖：首页（未滚动/已滚动）、回顾、统计（7 天与 30 天）、设置、三个二级页
（数据导入、洞察服务配置、演示数据；**导出页不在巡检脚本内**）、
睡眠详情（含展开的声音卡）、助眠音效面板、**会话页**（v3.2 补：夜景全貌与场景选择器、
长按结束时的横向填充按钮、白噪音底部弹窗、长按到底后的评星弹层）。`integration_test/`
不参与 `flutter test`。
（手动补录页**不在**巡检脚本内。v3.0 把脚本里的「记录」改成了「回顾」，但**那一轮没有重跑
`flutter drive`**——见「验证记录」的未验证项。）

会话页那几步有两个实测到的坑：**（1）动画只在推帧时前进**——集成测试的 live binding 里，
`await Future.delayed` 光等时钟过去，按钮的填充条会停在原地，所以长按那两步走
`tester.pump(100ms)` 的循环（脚本里的 `holdFinishButton`），不是单纯等时间。
**（2）走到会话页之后不能用 `pumpAndSettle`**——这一页挂着一个 60 秒循环的夜景动画控制器，
`pumpAndSettle` 永远等不到「没有动画」的那一刻、会 `timed out`；`settle` 辅助函数因此先看页面
上有没有 `HoldToFinishButton`，在会话页就改用显式推帧（步进时长与原本的等待相当）。

三点实测到的注意：

- `flutter drive` 的 `takeScreenshot` 通道在本机**不可靠**：同一条命令有时出图有时一张不出，
  日志停在 `request_data message is taking a long time to complete`。所以巡检只负责**导航并停留**，
  截图交给外面的 `simctl` 循环——`simctl` 一次都没漏。
- 驱动时**必须**设 `NO_PROXY=127.0.0.1,localhost`。VM Service 连的是本机端口，
  被代理拦掉会表现为「连不上 VM Service」。
- 深色模式：`xcrun simctl ui $DEV appearance dark` 后重跑一遍即可。应用默认「跟随系统」，
  会跟着切。

## 构建 iOS / macOS 的网络前提

Flutter 3.47 用 Swift Package Manager 解析插件依赖，而 `sqlite3` 的构建钩子还会从
GitHub Releases 下载预编译库。**本机实测直连即可跑通**，代理是可选的：

```bash
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn   # 引擎产物

flutter build macos --debug
flutter build ios --simulator --no-codesign                     # 无需签名
flutter build ios --no-codesign                                 # 真机包，仍需在 Xcode 里配开发团队
```

- **代理是可选的**：若直连拉不到引擎产物、或 SPM 的 git 克隆超时，再补上本机代理
  `export HTTPS_PROXY=http://127.0.0.1:7890 HTTP_PROXY=http://127.0.0.1:7890`。
  本轮终验时 `127.0.0.1:7890` **并没有在监听**，两条构建都是去掉代理变量、只留
  `FLUTTER_STORAGE_BASE_URL` 直连跑通的——所以别把代理当成前提写进脚本。
- `sqlite3` 的构建钩子偶发 GitHub Releases 下载超时，原样重跑即过。

真机包在签名前会停下：需要在 Xcode 的 Runner target 里选择你的 Apple 开发团队。

## 平台配置

Bundle ID、Android application ID、签名和发布账号保持 Flutter 默认占位配置
（`com.example.nightSleep`），待项目方提供后配置。**通知权限仅在用户打开提醒开关时申请**
（未在首次启动时弹窗）；麦克风权限仍未申请；除「获取可用模型」外不上传任何数据
（导出会把文件交给系统分享面板，**去向由你选择**，应用自己不发起传输）。

## 验证记录

本机环境：macOS 14.8.9（23J631，Intel），Flutter 3.47.5 stable。

**v3.2（2026-10-02：会话页照原型「睡眠进行中」态重建）最近一次复跑：**

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
    助眠音效已实现（合成），但**实际发声效果没有听过**——需要真机或模拟器人工试听
- **AI 模型列表**：DeepSeek 与 Anthropic 的模型 ID 已对照官方文档核实（2026-09-27），
  OpenAI 文档无法访问故未内置任何模型名，需用「获取可用模型」实时拉取
