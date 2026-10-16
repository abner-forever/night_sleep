# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 这是什么

「夜深」——中文、本地优先的睡眠记录 Flutter 应用。iOS / macOS / Android 都已构建、都在真机或
模拟器上跑通过（v3.12 起在 MI 9 上跑，v3.26 起后台录音走 Android 前台服务，v3.35 拿到
「整夜录到的都是真音频」的证据）；**Web 只有骨架、从未构建**。逐条现状见 README「未实现」表
——那里写的是「还差什么」，**不要当成已完成**。界面按 Figma Make 原型的**最终生效层**实现。

**动手前先读 `docs/superpowers/specs/2026-09-28-night-sleep-design.md` 第 8 章「与原型的有意偏差」。**
那张表现有 68 条（`#1`–`#71` 外加一条 `#16b`，另加 v3.37 的 `#72`–`#73`；`#7` / `#31` / `#35` /
`#44` 标着「作废」，是历史不是待办；`#34` 排在 `#39` 之后，别按位置找）。每条都写了理由，
**却不保证都写了回归方法**。

表里反复引用的那句是**「没有的东西就显示为没有」**（#3 / #7 / #26 / #33 一族）。落到具体能力上：
不伪造睡眠阶段（#10）、没有真实音频就不画波形（#2 / #13 / #27，措辞是「没有测量就不画」）、
不显示读不到的余额（#3）、不猜小米导入字段（#4；公开实现的阶段映射已被实测证明是错的，见
[`2026-10-13-xiaomi-band-sleep-integration-design.md`](docs/superpowers/specs/2026-10-13-xiaomi-band-sleep-integration-design.md) §五）。
这些是产品红线，不是待办——原型里它们是演示数据，规格书明令不得当真实能力实现。

**需求写完，只写一条 `CHANGELOG.md` 就够了。** 新增了什么功能、修好了什么问题、行为变了什么，
每条三五行为宜。**纯文档改动不进 CHANGELOG**（README / 规格 / 计划的搬迁与重排——git 历史
就是记录）。

**不要顺手去同步 README、规格、验证记录，也不为一个需求补一份计划。** 只有一种情况必须动
它们：**你的改动让那里已经写下的一句话变成了假话**——README 的「未实现」表说某能力还没有、
而你刚把它做出来了；规格里某条裁定被你改了。那时改的也是**那一句话**，不是补一份文档。

**说的时候要准**：没跑过的别写成跑过，跑绿了就说跑绿了、哪条没验就写哪条。这条是产品红线，
不是文档要求——它管的是**你说的话**，不是要你每次留一份档案。

三份长文档都还在，**想写长了再写**：`docs/verification-log.md`（某次验收跑出了什么、
哪些没验，按时间倒序，每条的抬头自带当时那台机器与环境）、`docs/superpowers/specs/`
（设计规格）、`docs/superpowers/plans/`（实现计划 + 一页索引 `ARCHIVE.md`）。
文件名一律 `YYYY-MM-DD-<topic>.md`；规格是活文档，创建时定日期、之后原地更新、不新开文件。

**先分清改动的大小，别把小改动做成大工程。** 判定标准是一句话：**这个决策能不能从代码和现有
规格里推出来？** 推得出来就直接改——不写计划、不写 spec、**也不先复述一遍要改什么**。用户报的
bug、改一句文案、调一处样式、加个开关，都属于这一类：看一眼代码，改，跑一遍测试，说结果。
一次需求花多长时间取决于改动本身，不取决于流程；**「直接改」是默认档**，据此分三档：

| 档 | 触发条件 | 产物 |
| --- | --- | --- |
| **直接改**（默认档） | 单点、单文件、现有测试能验证 | **不开 plan、不写 spec、不先复述方案**；改完跑 `dart format .` / `flutter analyze` / `flutter test` |
| **只开 plan** | 跨几处或多平台、有「不许破坏 X」的硬约束、需要先红后绿地钉测试 | 一份短 plan 挂到**已有规格**的对应章节（原地更新），**不新开 spec** |
| **spec + plan** | 新能力、新架构、影响产品语义、需要权衡取舍 | 新 spec + 新 plan |

**三档的差别只在「要不要先写方案」；三档做完都只记一条 `CHANGELOG`。**

**拿不准就往低档走。** 不要为小改动写计划、写长篇方案说明或逐条复述将要改什么。

plan 的厚度跟着改动量走——不要为了格式齐整，把单点修改写成几百行。计划**不删**，做完留在
`plans/` 里备查；已完成的那些有一页索引（[`plans/ARCHIVE.md`](docs/superpowers/plans/ARCHIVE.md)，
每份几行摘要 + 落地版本对照表），想不起某件事当初为什么这么做时先翻它。

编排强度同样跟档位走：「每个任务派一个实现者 + 一个审查者」那套只用于
**spec + plan** 档。`只开 plan` 档在当前会话里直接做，审查**集中在阶段末尾做一次**，不要逐任务派
subagent——每个 subagent 都要从头重读 CLAUDE.md / 规格 / 源码，对小改动是纯开销。

## 常用命令

```bash
flutter pub get
dart run build_runner build     # 生成 lib/core/database/app_database.g.dart
dart format .
flutter analyze
flutter test                     # 整套测试
flutter test test/sleep_score_test.dart                      # 单个文件
flutter test test/sleep_score_test.dart --plain-name "分档阈值"  # 单个用例（子串匹配）
flutter run -d macos             # 或 -d chrome / -d <真机或模拟器>
```

**新检出要先跑一次 `build_runner`**：`app_database.g.dart` 已 gitignore，缺了它 `flutter analyze` /
`flutter test` 会报几百条 `Undefined name 'ActiveSessionsCompanion'` 之类的错；改表结构后同理。

国内网络下的 pub 镜像、iOS / macOS 与 **Android** 构建的网络前提与代理，以及演示数据开关
`DEMO_DATA`，见 README「运行与生成」与「构建网络前提」（后者分 iOS / macOS 与 Android 两小节）。
**Android 构建莫名挂住（不报错、日志不动）时先去读那一节的 Android 小节**——记的是实测出来的
绕过办法，不是通用建议。

**不要改 `lib/**/*.g.dart`**（已 gitignore，由 Drift 生成）。也不要往 `~/.zshrc` 等
shell profile 里写环境变量，或改 `~/.gradle/init.d/`、仓库里的 `distributionUrl` 这类常驻配置
——需要时用命令行前置的临时变量或 `-I <临时脚本>`。

## 架构

分层约定、Riverpod provider 表、路由规则、数据库 schema 与迁移决策，见
[`docs/architecture.md`](docs/architecture.md)。

**三条最容易违反的**：Widget 不直接碰数据库（UI 唯一数据源是 `sleepEntriesProvider`）；
每个 push 页面都走 `Subpage`（推入的路由继承不到 `Scaffold` 与 `Material` 祖先）；
`SleepRepository.save()` 的 `stages` 传 `null` 表示「保持已有阶段不变」，不是「清空」。

**片段自动分析（鼾声 / 人声）分三层，别搅在一起**：判定规则在
`features/sleep/domain/clip_yamnet.dart`（纯函数，**不许 import `tflite_flutter`**，
否则它在 `flutter test` 里一条都测不了）；跑模型在 `data/yamnet_scorer.dart`；
读文件 / 起 isolate / 写库在 `data/clip_analyzer.dart`。模型
`assets/model/yamnet.tflite` 进包也进仓库，**它的许可证未落实，是发布阻塞项**。
真机上的评估入口是 `integration_test/yamnet_eval_test.dart`（`dart run` 起不了 TFLite）。
详情见 [`docs/architecture.md`](docs/architecture.md)。

`docs/architecture.md` **仍落后于代码几处**，动手前以代码为准：provider 表不是全集（只列了首批
7 个，`lib/` 里实际有三十多个）；`source` 的取值除 `manual / import / demo` 外还有
`session`（会话落库的记录）；密钥早已进系统钥匙串（v3.7 起），文档里「尚未接入安全存储」
那句是旧的。（schema 版本号 v3.37 顺手对齐到了 v8。）

## 写 Flutter 代码前

渲染与布局陷阱（`boxShadow` 被 clip 吃掉、`BackdropFilter` 的遮罩顺序、`Stack` 尺寸、
滚动视图留白、`Positioned` 的参照盒、`Material` 祖先缺失导致黄线）与 widget 测试陷阱
（FakeAsync 挂死、drift `watch*` 的 pending timer、`pumpPage` vs `pumpRoute`、迁移测试冻结裸
DDL）见 **[`.claude/skills/flutter-pitfalls/SKILL.md`](.claude/skills/flutter-pitfalls/SKILL.md)**
——写 widget / 布局 / widget 测试时会自动加载。没自动加载就主动读一次。

`integration_test/` 不参与 `flutter test`（要 `flutter drive`，见 README「界面截图巡检」）。

`tool/` 下两个脚本产出的是**生成物**：`generate_app_icons.dart`（iOS / macOS / Android 三套图标，
Android 那套两形式见偏差 #16b）与 `generate_noise_assets.dart`（`assets/noise/` 五条循环素材）。
要改图标或音效就改生成器再跑一遍，别手改产物。跑法见 README「运行与生成」。
**助眠音效素材的可商用授权尚未落实，是发布阻塞项。**
（同目录下另外两个——`analyse_clips.dart` / `eval_clips.dart`——是**复核**用的，只读、不改文件，
用法见 README「复核自动分析的两个脚本」。）

**两个已登记的发布阻塞项**：助眠音效素材的可商用授权，以及 `assets/model/yamnet.tflite`
的许可证（YAMNet 权重是 Apache-2.0，但 MediaPipe 那份**转换件**官方文档没有正面声明）。
两条都在 README「未实现」表里，**别当成已经解决**。

## 其他约定

- 界面文案、注释、文档一律中文；代码标识符英文。**既有一批文件仍是英文注释**
  （`core/theme`、`core/widgets`、`core/platform`、`compass` 等处）——随改动顺手对齐即可，
  不要为了统一去批量重写。
- `analysis_options.yaml` 开了 `avoid_print`、`prefer_const_constructors`——CLI 工具与巡检脚本
  需要 print 时用 `// ignore: avoid_print`。分析器排除 `build/ ios/ web/ macos/ android/`。
- 设计令牌只有一份（`app_tokens.dart` 的 `AppTokens` 主题扩展）。颜色/圆角/动效曲线从
  `AppTokens.of(context)` 取，不要在 widget 里写死色值。
- 「获取可用模型」调服务商 `GET /models`：API Key 只走请求头，不落日志、不持久化，
  **错误信息也不回显响应体**（服务商可能把请求头原样引回来）。

其余实现细节（宽屏断点、`AppHaptics`、助眠音效素材的循环长度与接缝淡化参数）见
[`docs/architecture.md`](docs/architecture.md)。
