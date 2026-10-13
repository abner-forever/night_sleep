# 夜深

「夜深」是一个中文、本地优先的睡眠记录 Flutter 应用。界面按
`docs/superpowers/specs/2026-09-28-night-sleep-design.md` 第 2 章的
Figma Make 原型**最终生效层**实现：iOS 玻璃材质、悬浮胶囊标签条 / 侧边栏自适应导航、
自定义描边图标集、滚轮选择器、浅色/深色主题、离线睡眠记录与 7/14/30 天统计、
睡前会话（**入睡前**那一屏 + 进去之后的「睡眠进行中」）与「回顾」补感受、数据导出
（CSV / JSON）、就寝/起床本地通知提醒与**夜间录音**。
应用显示名为「夜深」（iOS / macOS / Web）。

## 环境要求

- Flutter stable（本机基线 `3.47.5`，Dart `3.13.4`）
- macOS / iOS 目标需要 Xcode；**macOS 与 iOS 构建当前不需要 CocoaPods**——Flutter 3.47 用
  Swift Package Manager 解析插件依赖（构建日志中可见 `Xcode is fetching Swift Package
  Manager dependencies`）
- Android 目标需要 Android SDK 与 **JDK 17**（`flutter_local_notifications` 22.3.1 要求
  Java 17）。本工作区实测：SDK 在 `%LOCALAPPDATA%\Android\Sdk`（platforms 31/33/34、
  build-tools 34/35、cmdline-tools、platform-tools、emulator、`licenses/`），JDK 为
  Temurin **17.0.15**。**Android Studio 不是必需的**——有 SDK + JDK 就能
  `flutter build apk`。
  > **2026-10-12 订正**：本节此前写「本工作区尚未安装 Android SDK」且「仓库里没有
  > `android/` 目录」。两句现在都不成立：SDK 早就装了（没查过），`android/` 也已按
  > `flutter create --platforms=android .` 生成（SDK 版本 `3.47.5`，与
  > `.metadata` 里记的 `create_revision` 同源）。接入细节见
  > [安卓平台接入设计](docs/superpowers/specs/2026-10-12-android-platform-design.md)。
- **注意本机可能同时存在多个 Flutter SDK**。本项目基线是 `3.47.5`（Dart `3.13.4`）；
  `pubspec.lock` 要求 `dart >=3.13.0`、`flutter >=3.44.0`。若 `flutter --version` 报的是
  更低的版本，`flutter pub get` 会直接以
  `Because night_sleep requires SDK version >=3.3.0 <4.0.0, version solving failed` 失败——
  那个报错说的是 `pubspec.yaml` 的 `environment.sdk` 下界，**不是**版本号比较出了问题。
  用绝对路径调用正确的那个：`C:\src\flutter-3.47.5\bin\flutter.bat`。
- **`dart run build_runner build` 是跑 `flutter analyze` / `flutter test` 的前置**：
  `lib/core/database/app_database.g.dart` 已 gitignore，新检出里没有它，
  不生成会得到几百条 `Undefined name 'ActiveSessionsCompanion'` 之类的报错。

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
    database/          Drift schema v6 与迁移
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
  暗色…」提示。**v3.10 起这一屏按可用高度排版**：按钮与那行提示钉在底部安全区之上（不参与滚动，
  任何机型上都不会被切），上面的标签行 / 月亮 / 卡片拿剩下的高度——够高就给 hero 设计的 285，
  挤的时候一路收到它自己的内容高度，`402×874`、`393×852`、`430×932` 上都**一屏放下、不用滚**。
  这一屏**什么都不写库**：场景、闹钟开关与时刻都只是草稿，收起再进来就回到初值；
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
  入睡前那一屏做完了。鼾声那行副标题改为录音服务的**实际状态**（录音中 / 白噪音播放中 · 暂不录音 /
  停止原因），真在录时挂一颗小灯。
  **「结束睡眠」是全宽横向胶囊，长按 1.5 秒、填充条自左向右扫满才生效**；中途松手或手指滑开
  即作废，短按只给提示与轻震动。会话状态进 SQLite（`ActiveSessions` 单行表），跨重启存活；
  「收起」离开页面而**会话与白噪音继续跑**（关掉弹窗、收起页面都继续响）。「结束睡眠」就地评
  一次星（可跳过），一个事务里写记录（`source = 'session'`）并删会话行；时长不在 `(0, 24h]`
  内**不落库**，让用户选手动补录或丢弃。**它不测量任何东西**——两个时刻来自用户按下的按钮，
  起床时间来自设定。
  **整页常暗**：会话页两态都自己套 `Theme(AppTheme.dark())`，浅色应用主题下进去也是深色（原型的
  睡眠模式如此设计）。**刻意与原型不同的地方**见规格偏差 #28–#38；「事件卡不叠 `backdrop-filter`」
  见偏差 #34（睡眠进行中那一屏要整夜挂着，不叠每帧重算的模糊）。
- **夜间录音**（v3.9，2026-10-03，plan B）：会话期间真实采集环境声音——`record` 7.1.1 的
  16kHz 单声道**流式 PCM16**，每 **100ms** 聚合一格 RMS（dBFS），按振幅切成「**有声响的片段**」，
  一条片段一个 WAV 文件落进 `SoundClips`（目录 `getApplicationSupportDirectory()/clips/`）。
  **不做任何自动分类 / 转写 / 结论**：录到的是「有声响的片段」，是鼾声还是梦话由用户自己标。
  详情页声音卡可**真实回放**、可标注为打鼾 / 梦话 / 杂音；**未标注的显示「待标注」，不是「杂音」**。
  片段在会话进行中先记进 `active_sessions.clip_journal`（每录完一段更新一次），`finish()` 在
  同一事务里落成 `SoundClips` 行——**App 被杀重启后清单还在**。默认保留**最近 7 晚**（按醒来
  那天归档），超期删文件、`localUri` 置空、**行保留**（只清 `source='recording'`）；启动时另删
  孤儿文件。设置页给出当前占用与「删除全部录音」。**白噪音播放期间不录音**，会话页显示
  「白噪音播放中 · 暂不录音」——**这段空档是真的覆盖缺口**（偏差 #49）。schema v5 → v6 加了三列
  可空列（不重建表）。取舍、实测与七个阈值默认值见
  [specs/2026-10-03-night-audio-recording-design.md](docs/superpowers/specs/2026-10-03-night-audio-recording-design.md)。
  ⚠️ **真机整夜后台存活、切片阈值、界面目视均未验证**（见[验证记录](docs/verification-log.md)）。
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
    夜间声音录制开关（副标题 v3.9 起改为「录下有声响的片段，由你听过之后自己标注」，
    并新增当前占用与「删除全部录音」；打开开关前申请麦克风权限、被拒回弹并给「去系统设置」）。
  提醒的读写与调度行为**与搬家前完全一致**。导出的仍是 CSV / JSON 两个动作，见「数据导出」。
- **清除缓存**（v3.7，设置根页「关于」上方）：清掉 `getTemporaryDirectory()` 下**可再生成的
  临时文件**。**2026-10-03 起那里只剩一样东西**：导出时写给系统分享面板的 CSV / JSON 副本
  ——白噪音改成打包资源后不再往临时目录写 WAV，所以全新安装、还没导出过时读数为 `0 B`
  是**如实的**。副标题显示**真实占用**，读不到就说「暂时读不到占用」，清完显示「暂无缓存」。
  **v3.10 起点一下先弹二次确认**（与另外四处不可撤销的删除同一个 `showConfirmDialog`，
  破坏性配色）：弹窗里点名删的是什么、不动的又是什么。
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
  与设置页共用。**真机到点投递未验证**（见[验证记录](docs/verification-log.md)）。
- **助眠音效素材**：由 `tool/generate_noise_assets.dart` 从源录音生成，产出
  `assets/noise/` 下 5 条 `.m4a`。ffmpeg 滤镜链（单声道化 → 响度归一 → 折回式无缝接缝 →
  AAC 编码）里有**三处写错会静默失效**的细节——`asplit` 不能省、接缝要折回而不是淡入、
  归一天花板要给交叉淡化留 2 dB——都写在脚本头注释与规格 §5.2 里。
  跑法：`dart run tool/generate_noise_assets.dart [源素材目录]`（默认 `~/Downloads/白噪音素材`）。
- **应用图标**：由 `assets/branding/app-icon.svg` 生成，`tool/generate_app_icons.dart` 一次
  产出 iOS 15 张 + macOS 7 张 + **Android 15 张与 1 个自适应声明文件**。**三条渲染路径**：
  iOS 满幅直角、无 alpha 通道（色型 2，由系统套遮罩）；macOS 按 Apple 图标网格烘焙圆角与留白
  （实体 824×824、四边留白 100、半径 185.4）并加投影，**保留 alpha**（色型 6）——因为 macOS
  **不套遮罩**，圆角得写在文件里；Android 分两套（见下）。回归断言见
  `test/app_icons_asset_test.dart`，偏差见规格 #16。
- **Android 启动图标（v3.11）是两套并存**：`mipmap-*/ic_launcher.png`（48/72/96/144/192，
  满幅直角、不透明，给 **API < 26**）与 `mipmap-anydpi-v26/ic_launcher.xml`（**自适应图标**，
  给 API ≥ 26）。自适应图标是两层：**底**铺满 108dp 画布（纯渐变，`ic_launcher_background.png`）、
  **前景**缩进中央 72dp（月亮与声波，`ic_launcher_foreground.png`，四周透明），系统自己套遮罩
  （圆形 / 方圆形 / 圆角方形由启动器决定）。两处容易做错、且**只有装到手机上才发现**的地方：
  主体被遮罩切掉、主体混进底层——都由 `test/app_icons_asset_test.dart` 的 4 条断言钉住
  （**含变异验证**：摘掉生成器里的「重新居中」，断言立刻报出最远墨迹 45.1 > 半径 36.0）。
  前景不是按固定比例缩的，而是**按墨迹外接圆定标**——源图的墨迹几乎铺满 1024 画布，
  按「1024 → 72dp」那个比例缩进来外接圆会超出可见区 1.3%，圆形遮罩会切掉第二道声波的尾端。
- **数据**：SQLite（Drift）schema **v6**，含阶段、声音片段、洞察、会话（`ActiveSessions`
  单行表）四张新表与 v1→v2→v3→v4→v5→v6 迁移；外键级联删除；仓库用 3 条批量查询组装聚合。
  v3 给 `Insights.recordId` 补上 `ON DELETE CASCADE` 外键（此前没有，`deleteDemoData` 会留下
  孤儿洞察行，重装演示数据时主键冲突、异常还被静默吞掉），迁移**先清孤儿再重建表**，因此升级
  会**自动修好已在现场损坏的库**。v4 建会话表，并把 `SleepRecords.quality` 改为**可空**
  （会话评星可跳过 → 质量能表示「未评分」）——`alterTable` 重建了有子表引用的 `sleepRecords`，
  迁移后子表外键仍级联（有测试钉住）。v5 给 `active_sessions` 加 `scene_id` 可空列（会话页夜景
  场景的持久化，`null` = 默认「流星夜」）。v6 给 `active_sessions` 加 `clip_journal`、给
  `sound_clips` 加 `waveform_envelope` / `labeled_at_utc` 三列可空列（夜间录音，**只 `addColumn`、
  不重建表**；两条下界不同——`sound_clips` 两列 `from >= 2 && from < 6`，`active_sessions` 一列
  `from >= 4 && from < 6`）。

## 罗盘

设置 → 工具 → 罗盘（`/settings/compass`），包含二十四山、后天八卦、天池磁针、实时角度、方向锁定、手机倾斜与校准提示。
iOS 使用 Core Motion 的磁北参考系，融合陀螺仪、重力与校准磁场；读数表示**手机顶部相对磁北的方位**，不计算磁偏角或真北，也不申请定位权限。
页面关闭和应用进入后台时停止采样，回到前台重新连接。模拟器、macOS、Web 和无硬件设备显示不可用或等待状态，不生成假方向。
Android **已接入（v3.12，2026-10-13）**：`android/app/src/main/kotlin/com/example/night_sleep/CompassStreamHandler.kt`
是一条手写的 Kotlin `EventChannel`（通道名同为 `night_sleep/compass`），**逐项复刻 iOS 那套算法**——
`TYPE_MAGNETIC_FIELD` + `TYPE_GRAVITY` + `TYPE_GYROSCOPE`，由**陀螺仪**驱动发射、限流 30 Hz。
与 iOS **唯一的符号差异**是重力矢量：Android 平放屏幕朝上时报 Z = **+9.81**（CoreMotion 报 −1.0），
所以取 `up = +normalize(gravity)` 而**不**取负；照抄 iOS 那个负号会让 `tilt = 180°`、
`tilt < 60` 永不成立、**方位角永远是空**，页面永远停在「请将手机屏幕朝上」。
`accuracy` 也要换算（Android `0..3` → iOS `−1..2`），且 `0..3` 之外要夹到 `−1`——
Android 另有一个 `SENSOR_STATUS_NO_CONTACT = −1`，朴素的减法会得到 −2，
而 Dart 的门槛是 `!= −1`，**−2 不等于 −1，会把「磁力计没接触」的读数当成有效方位发出去**。
`compass_page.dart` **一行未改**：本页早就把「平台未实现」（→「当前平台暂不支持罗盘」）与
「设备没有传感器」（→「此设备没有可用的罗盘传感器」）分成了两支，Android 照 iOS 发
`error(code: "unavailable")` 即可落到后者。读传感器**不需要任何权限**，清单因此未加条目。
**未解决，不得当成已验证**：真机上我们的读数与系统自带 `com.miui.compass` 差 **43°**
（手机**证明过静止**：前后两次读数 12 秒内差 0.2°、陀螺仪速率 0.000）。
怀疑是磁力计的硬铁校准未建立（实测竖直分量约为该纬度物理值的两倍），**这是假设不是结论**，
判定用的「转过已知角度」试验**尚未跑**。**横屏的 90°/270° 折算也未验证**——
这台机器自动旋转是关的（`accelerometer_rotation=0`），`getRotation()` 恒为 `ROTATION_0`。
Kotlin 侧**没有任何单元测试**（本仓库没有 Kotlin 测试设施）；Dart 侧新增的 4 个用例
**只钉得住键名、类型、null 与否与错误 code，钉不住任何数值**。
罗盘独立开发验证：43 项相关单元/组件测试通过，Dart 静态分析无问题，iOS 模拟器构建成功；模拟器原生通道已确认返回不可用而非假方位。
合入最新 master 后复验（2026-10-02）：完整测试集 347/347 通过，Dart 静态分析无问题；罗盘入口测试已适配共享路由和睡眠会话状态。

## 未实现（不得视为已完成）

| 能力 | 现状 |
| --- | --- |
| 夜间录音 / 鼾声梦话检测 | **录音已接入（v3.9，plan B），但真机整夜后台存活未验证；鼾声/梦话检测仍没有**。会话期间按振幅切片、一条片段一个 WAV 落进 `SoundClips`；详情页声音卡可回放、可**手动**标注为打鼾 / 梦话 / 杂音。**没有任何自动识别 / 转写 / 结论**——这是刻意的（M3 第 3 条），不是待办；是鼾声还是梦话由用户自己听、自己标。**未验证**：真机整夜后台存活（锁屏后 Dart isolate 是否持续收到 PCM、片段是否持续落盘——**这是整条路的前提**）、七个切片阈值在真实样本上的表现、界面目视核对。另：**白噪音播放期间不录音**（那段是真的覆盖缺口） |
| 白噪音的后台播放 / 锁屏控制 | 未接入。会话白噪音在**收起页面后仍继续响**（播放器提到 app 级），但退到后台或锁屏后声音会停，界面已如实标注 |
| 助眠音效素材的可商用授权 | **未落实（发布阻塞项）**。5 条录音来自爱给网（aigei.com），使用方 2026-10-03 裁定为「尚未确认、仅供个人试用」。代码、`pubspec.yaml`、README 与规格均已如实标注，规格 §10 第 3 条**不关闭**。发布前必须确认授权、换素材或退回合成 |
| 小米手环数据导入 | 未接入。需真实导出样本或官方接口文档，导入按钮禁用并说明原因 |
| AI 洞察服务 | **部分接入（v3.7）**。已能查余额（**仅 DeepSeek**）、做连通性测试、在睡眠详情里重新生成一晚的模型总结并落库；API Key 存**系统钥匙串**（v3.7 起，重启后仍在，设置页有「清除密钥」）。**仍未做**：Claude 的对话与余额（Messages API 形状不同且无 key 可实测）、余额的持久化与历史曲线、**发送前「将要发送哪些数据」的逐项确认界面**（规格 M4 第 3 条的后半句）。OpenAI 的对话路径与 DeepSeek 同一份代码，但**没有 key 实测过**（见[验证记录](docs/verification-log.md)） |
| **Android 平台** | **平台目录已生成（v3.11，2026-10-12）**：`android/` 由 `flutter create --platforms=android .`（Flutter 3.47.5）产出，清单里补了 `RECEIVE_BOOT_COMPLETED` 与 `ScheduledNotificationReceiver` / `ScheduledNotificationBootReceiver` 两个 receiver，gradle 开了 core library desugaring。**「提醒不会因为重启而失效」这条现在成立**（此前是「开关看着有效、实际不响」）。**真机安装启动已在 v3.12 跑通**（MI 9 / API 30），**界面层的系统栏与安全区已在 v3.13 适配**（两条系统栏透明、页面背景铺到物理边缘，见「验证记录」v3.13）。**仍未做**：通知真的投递、前台录音在 Android 上录得下来——**一律未验证**。见下方「Android 上的已知缺口」 |
| Android 上的已知缺口（v3.11 起逐条列出，**不得视为已完成**） | ① **后台 / 锁屏录音**：清单里声明了 `FOREGROUND_SERVICE` 与 `FOREGROUND_SERVICE_MICROPHONE`，但**没有前台服务实现**——退到后台或锁屏后录音仍然停止。**声明了不等于能用**。② **「去系统设置」在 Android 上是死按钮**：`app_settings.dart` 对非 iOS/macOS 退回 `app-settings:`，Android 没有等价 scheme，点了没反应（麦克风权限被拒时那一行）。③ **`android:allowBackup` 未改**：备份开着意味着数据库与录音片段可能被上传到用户自己的 Google Drive，而应用承诺「不会上传」。三个处置方案见规格 §5.4，**待使用方裁定**。④ **发布阻塞**：applicationId 仍是占位 `com.example.night_sleep`；release 构建用 debug 签名（模板默认）；`FOREGROUND_SERVICE_MICROPHONE` 在没有对应服务前不应带着上架（Google Play 有单独用途申报） |
| ~~启动图标是 Flutter 默认 logo~~ | **v3.11 已修**：`tool/generate_app_icons.dart` 现在同时产出 Android 的传统位图（API < 26）与自适应图标（API ≥ 26，两层 + 声明文件）。见上方「Android 启动图标」。 |

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
`flutter drive`**——见[验证记录](docs/verification-log.md)的未验证项。）

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

## 构建 Android 的网络前提

Android 构建要拉三样东西，各有各的坑（2026-10-12 实测）：

1. **Gradle 发行包**（`android/gradle/wrapper/gradle-wrapper.properties` 里的
   `distributionUrl`）。走 `services.gradle.org`，实测只有 **177 KB/s 且会中途断**，
   `.part` 文件停在 4 MB 就不动了。**不要改仓库里的 `distributionUrl`**（那是模板文件，
   改成国内镜像会污染仓库）——手工下好放进 wrapper 的缓存目录即可：

   ```bash
   D="$HOME/.gradle/wrapper/dists/gradle-9.3.1-all/9ot9r568e8zfvvd4mn8rbu1j0"
   curl -L -o "$D/gradle-9.3.1-all.zip" \
     https://mirrors.cloud.tencent.com/gradle/gradle-9.3.1-all.zip
   ```

   （目录名 `9ot9r568e8zfvvd4mn8rbu1j0` 是 Gradle 按 `distributionUrl` 算出来的哈希，
   换版本时以实际目录名为准。）腾讯镜像实测 **4 MB/s**；阿里云的 `/gradle/` 路径是 404。

2. **Maven 依赖**（AGP、Kotlin、各插件的 AAR）。走 `dl.google.com` 与
   `repo.maven.apache.org`，**实测会长时间停滞**：Gradle daemon 挂着一批 established
   连接却收不到数据，10 分钟内 Maven 缓存零写入、构建停在 `assembleDebug` 不动。
   诊断信号就是这个——

   ```bash
   find ~/.gradle/caches/modules-2/files-2.1 -type f -newermt "-5 minutes" | wc -l
   ```

   持续为 0 就是卡住了。解法是**临时**把仓库地址改写到阿里云镜像，用 `-I` 内联传进去，
   **不写 `~/.gradle/init.d/`**（那是常驻配置，会改到本机所有 Gradle 工程）：

   ```bash
   # 脚本内容见本仓库 docs/superpowers/plans/2026-10-12-android-platform.md Task 5
   ./android/gradlew.bat -p android -I "$TEMP/cn-mirrors.gradle" assembleDebug
   ```

3. **Flutter 引擎产物**：`export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`。
   **这条不是可选项，漏了的症状最阴**：引擎的 ABI jar（`io.flutter:*_debug`）来自
   `storage.googleapis.com/download.flutter.io`，**不在上面那个 `cn-mirrors.gradle` 改写的
   三个域名里**。缺了它，`:app:compileDebugKotlin` 会**挂住十几分钟、日志零输出、一句错都不报**
   （daemon 只烧几秒 CPU，日志停在配置阶段之后），极易误判成「机器慢」。
   **诊断杀手锏是加 `--offline`**：它会把「挂住」立刻变成「明确告诉你缺哪个包」——

   ```
   Could not download arm64_v8a_debug-….jar (io.flutter:arm64_v8a_debug:…):
     No cached version available for offline mode
   ```

   另外两条同批踩到的：**绕过 Flutter CLI 直接 `gradlew assembleRelease` 会失败**，
   报 `GeneratedPluginRegistrant.java: 找不到符号 …integration_test`——那个注册文件由 CLI 生成
   且**按构建模式过滤**（release 排除 dev 依赖），绕过 CLI 就复用了上次 debug 留下的旧文件；
   解法是先跑一次 `flutter build apk --release` 让它把注册文件生成对。
   而 `flutter build apk` **又传不了 `-Pkotlin.incremental=false`**，会撞上
   `Could not close incremental caches … .tab`（疑杀软占句柄）。**两条路互为补充，缺一不可**。

4. **NDK 是硬需求，且它自己也走 `dl.google.com`**。本工程间接依赖 `jni`
   （经 `path_provider_android`），那个包带 CMake 原生构建，所以模板里的
   `ndkVersion = flutter.ndkVersion`（= `28.2.13676358`）**不是摆设**。
   实测 AGP 会自己去装它，而 `dl.google.com` 只有 264 KB/s，748 MB 会卡在
   `Preparing "Install NDK (Side by side) ..."` 不动（`$SDK/ndk/28.2.13676358/`
   下只有一个空的 `.installer`）。手工装：

   ```bash
   curl -L -o ndk.zip https://mirrors.cloud.tencent.com/AndroidSDK/android-ndk-r28b-windows.zip
   # 解开后把 android-ndk-r28b/ 的内容放进
   #   %LOCALAPPDATA%\Android\Sdk\ndk\28.2.13676358\
   # （先删掉那个空的 .installer），其中 source.properties 的 Pkg.Revision
   #   正是 28.2.13676358，目录名必须与它逐字一致
   ```

   腾讯镜像实测 **4 MB/s**。

5. **`platforms;android-35` 与 `platforms;android-36` 都不是预装的**（本机原本只有
   31/33/34），而本工程**两个都要**：`compileSdk = flutter.compileSdkVersion` = 36，
   而 `audio_session`/`just_audio`/`sqlite3_flutter_libs`/`flutter_timezone`/`jni` 等模块
   各自写死 `compileSdk 35`，AGP 会为它们分别去装。**这一步的失败长相很误导**：

   ```
   java.util.zip.ZipException: Archive is not a ZIP archive
   ...
   Failed to install the following SDK components: platforms;android-36
   ```

   别被 `ZipException` 带偏去查解压工具：真实原因是下载**被截断**
   （实测 `.temp/` 下那个包只有 500 KB，而完整包是 62 MB）。手工装：

   ```bash
   curl -L -o p36.zip https://mirrors.cloud.tencent.com/AndroidSDK/platform-36_r02.zip
   curl -L -o p35.zip https://mirrors.cloud.tencent.com/AndroidSDK/platform-35_r02.zip
   # 都解开到 %LOCALAPPDATA%\Android\Sdk\platforms\ 下（包内就是 android-36/、android-35/）
   ```

   判断「已装好」的可靠依据是 `platforms/android-3X/android.jar`（27 MB 上下）在不在——
   **失败的安装会留下一个只有 `.installer` 的空目录**，看上去像装了其实没有。

> 编辑器的 Gradle 同步会**静默吃掉**这些下载失败——它只在右下角转圈，不报错。
> 所以「Android Studio 里点一下就好了」在这里不成立，要看上面的缓存计数。
> 顺带：这一整套 `dl.google.com` 的下载（CI 里也会遇到）**只有本机这个网络才需要绕过**，
> 干净的 CI 环境直连即可——所以解法都写在文档里、**一行都没有进仓库**。

## 平台配置

Bundle ID、Android application ID 与发布账号保持 Flutter 默认占位配置，
**但三端并不同名**——iOS / macOS 是 `com.example.nightSleep`（Flutter 的 iOS 模板把
`night_sleep` 转成了 camelCase），Android 是 `com.example.night_sleep`（Android 模板保留
snake_case）。两者是两个独立的商店身份，不要求一致；待项目方提供后一并替换
（总规格 §10 第 1 条）。真机签名团队已配置（见「真机安装」）。**通知权限仅在用户打开提醒开关时申请**
（未在首次启动时弹窗）；**麦克风权限仅在你打开夜间录音开关时申请（v3.9 起）**。**v3.7 起应用会联网**：共 4 处对外请求
（获取可用模型、连通性测试、查询余额、生成洞察），**全部由用户点击触发**，全部只发结构化
睡眠字段（**不含用户备注**），密钥只进请求头、不落日志不落盘；导出仍是把文件交给系统分享
面板、**去向由你选择**，应用自己不发起传输。

## 验证记录

**本节只留最近一版。** 逐版的实测结果与**未验证清单**在
[`docs/verification-log.md`](docs/verification-log.md)（按时间倒序，最新在最上面）——
README 是「怎么跑、能干什么」，那份文档才是「验到了哪一步、还有什么没验」。

**v3.13（2026-10-13：Android 系统栏与安全区）——Windows 11 / Flutter 3.47.5 / Android SDK 36：**

真机同上：Xiaomi MI 9（`cepheus`，adb serial `e0e60672`），**Android 11（API 30）/ MIUI 12.5.6 / arm64-v8a**。

- `flutter analyze` 无问题；`flutter test` **609/609 通过**（v3.12 是 592，净增 17）。
- **跑过的（真机，改前 / 改后是同一台机器、同一个页面）**：
  - 顶部：`x=30` 一列逐像素采样，`y<75` 由 `(181,181,186)` 变成 `(241,241,248)` 一类的
    页面背景——**灰带整条消失**；浅色主题下状态栏图标仍是深色。
  - 底部：黑带消失，页面背景铺到 `y=2339`；胶囊底边 `y=2296`、手势条上沿 `y=2310`。
  - 推入页（`外观`，走 `Subpage` 的 `SafeArea`）同样两条栏透明。
  - **浅色应用主题下进常暗的会话页**：状态栏图标如期变白、背景铺到导航栏后面。
  - **应用内切深色而系统仍是浅色**：状态栏与手势条图标双双变白。
- **没跑过的**：**API 29 以下的设备**（引擎 `SDK_INT >= 29` 的门槛让 `edgeToEdge` 成为
  空操作，应维持旧样子）；**API 35 及以上**（本轮用的几个字段在那条线以上是 deprecated
  no-op，系统自己强制 edge-to-edge，预期一样但那是另一套行为）；**iOS / macOS**
  （**状态栏样式的来源被改了**——从跟随系统外观改成跟随应用主题，是本意但没跑过）；
  **三键导航**（安全区约 48dp，胶囊会整个让开——推断，未实测）；**横屏**。
  判据与逐条截图对照见[安卓平台接入设计](docs/superpowers/specs/2026-10-12-android-platform-design.md) §6.4–6.5。
- **本机构建**：`flutter build apk` 撞上 Kotlin 增量缓存时，异常里那句
  `Could not close incremental caches … different roots` 就是根因——**pub 缓存在 `C:`、
  工程在 `D:`**，增量缓存存的是绝对路径，跨盘建不起来（此前记的「疑为杀软占住 `.tab`」
  只是同一现象的另一种猜测）。**绕开 CLI、`cd android` 后直接跑 `gradlew assembleDebug`**，
  带 `-Pkotlin.incremental=false` 与 `-Pkotlin.compiler.execution.strategy=in-process`，
  48 秒完成。**`gradlew` 的 `APP_HOME` 取的是当前目录**（不是脚本所在目录），
  从仓库根跑 `./android/gradlew` 会报 `ClassNotFoundException: GradleWrapperMain`——
  而 wrapper jar 其实好好地在 `android/gradle/wrapper/`。详见「构建 Android 的网络前提」。
