# 夜深

「夜深」是一个中文、本地优先的睡眠记录 Flutter 应用。界面按
`docs/superpowers/specs/2026-09-28-night-sleep-design.md` 第 2 章的
Figma Make 原型**最终生效层**实现：iOS 玻璃材质、悬浮胶囊标签条 / 侧边栏自适应导航、
自定义描边图标集、滚轮选择器、浅色/深色主题、离线睡眠记录与 7/14/30 天统计、
数据导出（CSV / JSON）与就寝/起床本地通知提醒。

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
  app/                 应用入口、导航外壳、标签状态、提示条
  core/
    config/            构建开关（演示数据）
    database/          Drift schema v3 与迁移
    platform/          触觉反馈
    theme/             设计令牌与 ThemeData
    widgets/           玻璃材质、iOS 控件、弹层、二级页外壳、滚轮、图标、图表基础件
  features/
    home/              首页
    log/               记录（新增与编辑共用同一表单）
    stats/             统计
    settings/          设置与四个子页（数据导入、数据导出、洞察配置、演示数据）
    onboarding/        首次引导
    sleep/
      domain/          记录聚合、阶段、声音、评分、统计口径、时间窗口
      data/            仓库（行 → 聚合）与演示种子
      presentation/    睡眠盘、评分环、阶段图、详情弹层、声音卡、助眠音效弹层
test/                  领域计算测试
```

## 当前实现范围

- **设计系统**：完整令牌（`app_tokens.dart`）、玻璃材质、iOS 开关/分段控件/列表组、底部弹层、
  滚轮选择器、自绘描边图标集（原型图标逐字用原 SVG path；垃圾桶为 v2.6 新增，见下）。
- **首页**：圆形睡眠盘（4 同心弧，首次进入自绘动画）、昨夜概览、7 日均时、助眠音效入口、
  最近记录卡（阶段色带 + 图例）。
- **记录**：实时时长预览（随滚轮变化重绘）、日期/入睡/起床滚轮、1–5 星质量、四类事件开关、
  备注；时长由起止时间派生并校验 `0 < 时长 ≤ 24h`。
- **顶部渐变**：一级页面滚动超过 12px 后，顶部浮出 144px 的 `blur(14px)` 渐变带
  （宽屏和弹层打开时自动停用），与设计的 `.ios-top-fade` 一致；带顶到**屏幕物理顶端**
  （状态栏那段也参与模糊，不再有硬分界），滚动超 12px 后 320ms 淡入上移。
  `ImageFilter` 没有内置的 saturate 构造器，本轮用一层极淡的 accent 叠加（`alpha 0.04`）**近似**
  （也可用 `ColorFilter.matrix` 自行构造饱和度矩阵）；与 `glass_surface.dart` 同一手法。
  外壳不再套顶部 `SafeArea`，状态栏留白改由各页滚动视图按 `pageTopInset` 施加。
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
- **应用图标**：由 `assets/branding/app-icon.svg` 生成，`tool/generate_app_icons.dart` 一次
  产出 iOS 15 张 + macOS 7 张，全部无 alpha 通道、无自带圆角。
- **数据**：SQLite（Drift）schema v3，含阶段、声音片段、洞察三张新表与 v1→v2→v3 迁移；
  外键级联删除；仓库用 3 条批量查询组装聚合。v3 给 `Insights.recordId` 补上 `ON DELETE CASCADE`
  外键（此前没有，`deleteDemoData` 会留下孤儿洞察行，重装演示数据时主键冲突、异常还被静默吞掉），
  迁移**先清孤儿再重建表**，因此升级会**自动修好已在现场损坏的库**。

## 未实现（不得视为已完成）

| 能力 | 现状 |
| --- | --- |
| 夜间录音 / 鼾声梦话检测 | 未接入。设置开关只保存偏好，**录音本身仍未实现**，界面已注明 |
| 小米手环数据导入 | 未接入。需真实导出样本或官方接口文档，导入按钮禁用并说明原因 |
| AI 洞察服务 | 未接入。服务商/模型选择可持久化；API Key 仅存内存，安全存储未接入；余额查询未接入 |
| Android 平台 | 平台目录未生成（`.metadata` 只有 ios / macos / web）。接入时需补 `RECEIVE_BOOT_COMPLETED` 权限与 `ScheduledNotificationReceiver` / `ScheduledNotificationBootReceiver` 两个 receiver，否则设备重启后提醒不再重排 |

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

覆盖：首页（未滚动/已滚动）、记录、统计（7 天与 30 天）、设置、三个二级页
（数据导入、洞察服务配置、演示数据；**导出页不在巡检脚本内**）、
睡眠详情（含展开的声音卡）、助眠音效面板。`integration_test/` 不参与 `flutter test`。

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

本机环境：macOS 14.8.9（23J631，Intel），Flutter 3.47.5 stable。最近一次复跑：**2026-09-29**。

- `dart format --set-exit-if-changed .` → 无改动（80 文件，0 changed）
- `flutter analyze` → **No issues found**
- `flutter test` → **216/216 通过**（本轮从 176 起，逐步增至 216：schema v3 迁移 5、
  演示数据重装与幂等 2、冷启动播种兜底 4、图标取色 4、顶部渐变与安全区/错误分支留白 3、
  关于卡片居中与版本号 2、自绘确认弹窗 7（另有演示数据页的确认 1，落在 `pages_widget_test`）、
  删除图标 2、`PrimaryAction` 禁用态 10；
  各测试文件覆盖的场景见
  [规格第 9 章](docs/superpowers/specs/2026-09-28-night-sleep-design.md)）。
  本轮多处断言做了**变异验证**（拆掉实现会真的变红），不是「不可能失败的断言」
- **构建**：v2.5 那次 `flutter build macos --debug` / `flutter build ios --simulator --no-codesign`
  成功产物的记录仍适用；**本轮（v2.6）没有重跑任何构建**。因此本轮新增的
  `package_info_plus` 依赖虽然连 `macos/Flutter/GeneratedPluginRegistrant.swift` 一并提交了，
  但它在新构建里的原生注册、以及设置页版本号的实际取值**都没有在构建/运行中验证过**
  （测试里用的是包自带的 `setMockInitialValues`）
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
- **未验证（不得视为已完成）**：
  - **通知投递**：没有真机 / 模拟器人工确认过「到点了真的会响」。Dart 侧的调度契约
    被测试钉住，但通知是否真的投递、前台是否展示、时区是否选对，都仍需人工确认
  - **系统分享面板**：导出经 `share_plus` 交付，面板的实际弹出与去向选择**没有实测过**；
    导出内容的字节（BOM、CRLF、RFC 4180 转义、不含本地路径与 `AppSettings`）由单元测试覆盖
  - **macOS 未签名调试构建的通知授权行为**：本机钥匙串里没有签名证书，权限可能拿不到或不持久。
    实现按 `permission()` 的真实返回降级（界面照实显示），但这一项只能人工验证
  - **`package_info_plus` 的实际返回值**：只验证过它的 API 形状与「取不到时不显示版本号」的
    降级分支；`version` / `buildNumber` 在**真机 macOS / iOS 上映射到 `CFBundleShortVersionString`
    / `CFBundleVersion` 的对应关系没有实测**（测试用 mock 注入）
  - **本轮 UI 的目视观感**：见上「界面巡检」——确认弹窗、垃圾桶、禁用按钮提示、关于卡片
    都未经眼
  - 真机交互、窄屏宽屏溢出检查：**尚未执行**
    （宽屏侧边栏布局只在 macOS 桌面构建里跑过，未逐屏核对）
  - Android / Web 构建：**尚未执行**（Android 平台目录也不存在，见「未实现」表）
  - 外部服务、小米数据、夜间录音：未接入，不能视为已完成。
    助眠音效已实现（合成），但**实际发声效果没有听过**——需要真机或模拟器人工试听
- **AI 模型列表**：DeepSeek 与 Anthropic 的模型 ID 已对照官方文档核实（2026-09-27），
  OpenAI 文档无法访问故未内置任何模型名，需用「获取可用模型」实时拉取
