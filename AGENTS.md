# Repository guidelines

## 项目与目录

「夜深」是中文、本地优先的睡眠记录应用，使用 Flutter / Dart，支持 Android 和 iOS 手机、平板。`website/` 是独立的 React / Vite 官网，`server/` 是 NestJS 应用服务，二者都不是 Flutter Web。

- `lib/main.dart`：启动、数据库与通知初始化、密钥读取及 Riverpod overrides。
- `lib/app/`：GoRouter、标签外壳与跨功能编排，包括录音、音效会话和提醒。
- `lib/core/`：Drift 数据库、平台适配、主题令牌和共享控件。
- `lib/features/<feature>/`：按需组织 `presentation/`、`domain/`、`data/`，不强求每个功能都有三层。
- `test/`：领域、数据库和 Widget 测试；`integration_test/`：需设备的界面巡检与平台验证。
- `server/`：NestJS 11 应用服务，当前提供天气接口；密钥只从服务端环境变量读取。
- `tool/`：资源生成器、音频复核及 Android 发布脚本；`.github/workflows/`：Android 发布与官网部署。
- `docs/release-plan.md`、`docs/android-signing.md`：发布及签名细则；`README.md`：使用与环境说明；`CLAUDE.md`：更详细的架构与历史踩坑说明。涉及具体行为时以当前源码、工作流及用户要求核实。

## 开发命令

CI 使用 Flutter `3.47.5`、Java 17；官网使用 Node.js 22。iOS 插件通过 CocoaPods 解析，`pubspec.yaml` 已关闭 Swift Package Manager。

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter devices
flutter run -d <device-id>
flutter test test/sleep_score_test.dart
flutter test
flutter build apk --debug
flutter build ios --simulator --no-codesign
```

首次检出或修改 Drift 表后必须生成代码。`lib/**/*.g.dart` 已忽略，不手改、不提交。演示数据由 `DEMO_DATA` 控制，默认只在 debug 构建开启；发布 APK 必须使用 `--dart-define=DEMO_DATA=false`。

官网命令在 `website/` 执行：`npm ci`、`npm run dev`、`npm run check`、`npm run build`。`check` 是 Node 测试，不是 lint 或类型检查。

应用服务命令在 `server/` 执行：`npm ci`、`npm run dev`、`npm run typecheck`、`npm test`、`npm run build`。

## 实现约定

- Dart 遵循 `analysis_options.yaml` 和 `dart format`，代码标识符用英文，新增界面文案、注释和文档用中文。保持改动集中，不批量重写无关代码或注释。
- Widget 不直接操作数据库；睡眠记录通过 `SleepRepository` 聚合，列表 UI 使用 `sleepEntriesProvider`。复用已有 Riverpod provider 与控制器，跨功能编排归 `lib/app/`。
- 数据库变更须维护迁移及旧库测试；先理解 `onUpgrade` 的版本下界，避免早期库用当前表定义建表后再次添加同名列。迁移夹具用固定的旧版 DDL，不用当前 Dart 表类模拟旧表。
- 颜色、圆角、动效与宽屏断点复用 `lib/core/theme/app_tokens.dart`。二级页通常用 `Subpage`，弹层用 `AppSheet`，确保背景、Material 祖先及安全区完整。
- 首页、回顾、统计、设置是外壳 tab；推入页面是 `/` 的子路由。睡眠会话页保留独立深色主题及 `CustomTransitionPage`，不得丢失 `state.pageKey`。
- 音频判定规则留在纯领域层，不引入 `tflite_flutter` 或文件 I/O；模型推理、文件读取与写库各守边界。模型字节在主 isolate 读取。
- 图标、音效的生成物通过 `tool/generate_app_icons.dart`、`tool/generate_noise_assets.dart` 更新，先改生成器。构建目录、截图临时产物、签名密钥和口令不入库。
- 网络镜像只用临时环境变量，不提交镜像导致的锁文件改写，不改仓库下载地址或全局 Gradle / shell 配置。
- 小修直接实现并验证；新能力或架构取舍才补必要规格与计划。功能变更简记 `CHANGELOG.md`，纯文档改动不记；其他文档仅在既有描述因本次改动失实时更新。

## 产品与隐私约束

- 「没有的东西就显示为没有」：不伪造睡眠阶段、波形、事件区间、服务商余额或导入字段；演示数据不代表实际测量能力。
- 自动声音判定只称「疑似」，分数不是概率；人工标注优先，机器不得覆盖。有声但未达判定线可标「杂音」；数字静音、读取失败和未分析不能混同为杂音。
- 睡眠记录和音频留在设备上。可选联网洞察只发送必要的结构化睡眠字段，不发送自由文本备注或音频。
- API Key 使用系统安全存储，只通过请求头发送，不进入睡眠数据库、导出或日志；错误提示不得回显可能含密钥的响应体。
- 权限在用户启用对应功能时申请。平台静音或录音失败时如实展示状态，不继续声称正在录音。

## Release branches

- Work on feature branches or `beta`. Merging or pushing application changes to `beta` automatically publishes an Android Beta after checks pass.
- Merge or push to `main` only when the user explicitly requests a formal release. Application changes on `main` automatically publish a stable Android version. Do not promote Beta work to `main` as routine cleanup.
- Do not manually create release tags or increment Beta sequences/build numbers. The Android workflow derives versions from release history and Conventional Commits, verifies the APK, then creates the tag and Release for the exact source commit.
- Use `fix:` for patches, `feat:` for minor releases, and `!` / `BREAKING CHANGE:` for breaking changes. Before 1.0, breaking changes increment the minor version. `pubspec.yaml` supplies the minimum target version for an intentional version jump.
- After a formal release, synchronize `main` back into `beta` before continuing development.
- The website deploys independently from both release branches. Its primary Android download is always the latest stable version; Beta is a separate optional entry and must never replace a missing stable download.
- Website changes on `beta` or `main` trigger deployment; the workflow always builds website source from `beta`. Do not merge application changes to `main` just to deploy the website.

## Validation

- Release automation: `python3 -m unittest discover -s tool -p 'test_*release.py'` and `python3 -m unittest discover -s tool -p 'test_*signing.py'`.
- Website: run `npm run check` and `npm run build` in `website/`.
- 应用服务：在 `server/` 运行 `npm run typecheck`、`npm test` 和 `npm run build`；涉及真实天气上游时另做接口联调，不把密钥写入仓库。
- Flutter changes: run `dart analyze` and relevant Flutter tests.
- 对修改的 Dart 文件运行 `dart format <paths>`；跨功能或公共基础设施变更需运行完整 `flutter test`。集成测试不包含在默认测试扫描内，使用 `NO_PROXY=127.0.0.1,localhost flutter test integration_test/app_screens_test.dart -d <device-id>` 等指定文件与设备的命令。
- Widget 测试用 provider overrides / fake 隔离平台通道、真实文件 I/O 和 Drift watch 流；无限动画用显式 `pump()`，不要等待 `pumpAndSettle()`。页面测试不得额外包 Scaffold 来掩盖真实路由缺少 Material 或背景的问题。
- UI 改动按受影响页面验证手机 / 宽屏及深浅主题；构建或测试通过不等同于视觉、后台录音或真机安装验证。汇报实际执行的检查及未验证项。
- 纯文档改动检查 `git diff --check` 和内容准确性，无需运行应用构建。
