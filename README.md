# 夜深

「夜深」是一个中文、本地优先的睡眠记录 Flutter 应用。界面按
`docs/superpowers/specs/2026-09-28-night-sleep-design.md` 第 2 章的
Figma Make 原型**最终生效层**实现：iOS 玻璃材质、悬浮胶囊标签条 / 侧边栏自适应导航、
自定义 24 图标集、滚轮选择器、浅色/深色主题、离线睡眠记录与 7/14/30 天统计。

## 环境要求

- Flutter stable（本机基线 `3.47.5`，Dart `3.13.4`）
- macOS / iOS 目标需要 Xcode；**macOS 与 iOS 构建当前不需要 CocoaPods**——Flutter 3.47 用
  Swift Package Manager 解析插件依赖（构建日志中可见 `Xcode is fetching Swift Package
  Manager dependencies`）
- Android 目标需要 Android Studio、SDK 和 JDK（本工作区尚未安装 Android SDK）

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

`lib/core/database/app_database.g.dart` 由 Drift 生成，不手工修改。

## 项目结构

```text
lib/
  app/                 应用入口、导航外壳、标签状态、提示条
  core/
    config/            构建开关（演示数据）
    database/          Drift schema v2 与迁移
    platform/          触觉反馈
    theme/             设计令牌与 ThemeData
    widgets/           玻璃材质、iOS 控件、弹层、二级页外壳、滚轮、图标、图表基础件
  features/
    home/              首页
    log/               记录（新增与编辑共用同一表单）
    stats/             统计
    settings/          设置与三个子页（数据导入、洞察配置、演示数据）
    onboarding/        首次引导
    sleep/
      domain/          记录聚合、阶段、声音、评分、统计口径、时间窗口
      data/            仓库（行 → 聚合）与演示种子
      presentation/    睡眠盘、评分环、阶段图、详情弹层、声音卡、助眠音效弹层
test/                  领域计算测试
```

## 当前实现范围

- **设计系统**：完整令牌（`app_tokens.dart`）、玻璃材质、iOS 开关/分段控件/列表组、底部弹层、
  滚轮选择器、24 个原型图标（原始 SVG path）。
- **首页**：圆形睡眠盘（4 同心弧，首次进入自绘动画）、昨夜概览、7 日均时、助眠音效入口、
  最近记录卡（阶段色带 + 图例）。
- **记录**：实时时长预览（随滚轮变化重绘）、日期/入睡/起床滚轮、1–5 星质量、四类事件开关、
  备注；时长由起止时间派生并校验 `0 < 时长 ≤ 24h`。
- **顶部渐变**：一级页面滚动超过 12px 后，顶部浮出 144px 的 `blur(14px)` 渐变带
  （宽屏和弹层打开时自动停用），与设计的 `.ios-top-fade` 一致。
- **弹层手势**：底部弹层支持点击蒙层关闭、点击把手关闭、把手跟手下拉超过阈值关闭；蒙层是独立
  的淡入层，不随面板从底部滑入。
- **编辑与删除**：睡眠详情的底部提供「编辑记录」「删除记录」。编辑复用记录表单并预填原值，
  保存写回**同一条**记录（不改 `createdAt`，不新增副本，也不覆盖已有睡眠阶段）；删除需二次确认，
  经外键级联一并清掉该晚的阶段与声音事件。演示数据不提供这两个入口，并说明可在设置中整体清除。
- **统计**：7/14/30 天分段控件、时长柱状图（含 7h 虚线目标线、可选中查看）、评分卡、
  四项汇总、梦话转录列表。
- **设置**：外观模式（跟随系统/浅色/深色）、睡眠目标步进器、数据导入入口、就寝/起床提醒
  开关与时间、夜间录音开关、洞察服务配置、演示数据入口（仅调试构建）、删除全部本地数据、关于。
- **AI 模型列表**：按服务商从官方 `GET /models` 实时获取，用会话内的 API Key 认证；未获取前
  显示**已注明核实日期**的内置列表。DeepSeek 为默认服务商。
- **助眠音效**：8 种声音在设备上**实时合成**（`noise_synth.dart`：白/棕/粉噪、雨、海浪、
  篝火、森林、风扇），渲染成 20 秒无缝循环的 WAV 后交给播放器循环播放；音量、定时、
  切换与失败提示均已接通。不打包任何第三方音频。
- **应用图标**：由 `assets/branding/app-icon.svg` 生成，`tool/generate_app_icons.dart` 一次
  产出 iOS 15 张 + macOS 7 张，全部无 alpha 通道、无自带圆角。
- **数据**：SQLite（Drift）schema v2，含阶段、声音片段、洞察三张新表与 v1→v2 迁移；
  外键级联删除；仓库用 3 条批量查询组装聚合。

## 未实现（不得视为已完成）

| 能力 | 现状 |
| --- | --- |
| 夜间录音 / 鼾声梦话检测 | 未接入。设置开关只保存偏好，界面已注明 |
| 小米手环数据导入 | 未接入。需真实导出样本或官方接口文档，导入按钮禁用并说明原因 |
| AI 洞察服务 | 未接入。服务商/模型选择可持久化；API Key 仅存内存，安全存储未接入；余额查询未接入 |
| 通知提醒 | 未接入。仅持久化偏好 |
| 导出 CSV / JSON | 未实现 |

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

覆盖：首页（未滚动/已滚动）、记录、统计（7 天与 30 天）、设置、三个二级页、
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
GitHub Releases 下载预编译库。因此在本机网络下构建 iOS 需要：

```bash
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn   # 引擎产物
export PUB_HOSTED_URL=https://pub.flutter-io.cn                 # pub
# Flutter 引擎产物与 SPM 的 git 克隆都走代理
export HTTPS_PROXY=http://127.0.0.1:7890 HTTP_PROXY=http://127.0.0.1:7890

flutter build ios --simulator --no-codesign                     # 无需签名
flutter build ios --no-codesign                                 # 真机包，仍需在 Xcode 里配开发团队
```

真机包在签名前会停下：需要在 Xcode 的 Runner target 里选择你的 Apple 开发团队。

## 平台配置

Bundle ID、Android application ID、签名和发布账号保持 Flutter 默认占位配置
（`com.example.nightSleep`），待项目方提供后配置。当前不申请通知或麦克风权限，也不上传任何数据。

## 验证记录

本机环境：macOS 14.8.9（23J631，Intel），Flutter 3.47.5 stable。最近一次复跑：2026-09-28。

- `flutter analyze` → **No issues found**
- `flutter test` → **132/132 通过**（各测试文件覆盖的场景见[规格第 9 章](docs/superpowers/specs/2026-09-28-night-sleep-design.md)）
- `flutter build macos --debug` → 成功产出 `night_sleep.app`
- `flutter build ios --simulator --no-codesign` → 成功产出 `Runner.app`
  （universal：x86_64 + arm64；新图标已编译进 `Assets.car`，抽出校验过）
- `flutter build ios --no-codesign` → **停在签名**：需要项目方在 Xcode 中配置开发团队
- **界面巡检**（iOS 模拟器截图，见下节）。浅色与深色各完整走一遍，逐屏看过：
  首页（未滚动/已滚动）、记录、统计（7 天/30 天）、设置、三个二级页、
  睡眠详情（含展开的声音卡与波形）、助眠音效面板。两套外观下均未发现新问题。
  此前报告的问题确认已修复：
  统计页分段胶囊宽度、二级页黑底与黄色下划线、音量条与进度条从左侧生长、
  事件标签边框完整、「外观模式」左对齐且分段控件上方无分隔线、
  顶部渐变无硬边、主按钮无杂线、标签条上方无不透明带、弹层文案无黄色下划线
- 真机交互、窄屏宽屏溢出检查：**尚未执行**
  （宽屏侧边栏布局只在 macOS 桌面构建里跑过，未逐屏核对）
- Android / Web 构建：**尚未执行**
- 外部服务、小米数据、夜间录音：未接入，不能视为已完成。
  助眠音效已实现（合成），但**实际发声效果没有听过**——需要真机或模拟器人工试听
- **AI 模型列表**：DeepSeek 与 Anthropic 的模型 ID 已对照官方文档核实（2026-09-27），
  OpenAI 文档无法访问故未内置任何模型名，需用「获取可用模型」实时拉取
