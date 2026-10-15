# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 这是什么

「夜深」——中文、本地优先的睡眠记录 Flutter 应用（iOS / macOS 已构建；**Android 平台目录已
生成、真机跑通**——v3.11 生成工程、v3.12 装到 MI 9 上跑通、v3.13 适配系统栏，但后台录音与
通知投递仍未实现；**Web 只有骨架、从未构建**。逐条现状见 README「未实现」表）。
界面按 Figma Make 原型的**最终生效层**实现。

**动手前先读 `docs/superpowers/specs/2026-09-28-night-sleep-design.md` 第 8 章「与原型的有意偏差」。**
那张表现有 66 条（`#1`–`#65` 外加一条 `#16b`；`#7` / `#31` / `#35` / `#44` 标着「作废」，是历史
不是待办；`#34` 排在 `#39` 之后，别按位置找）。每条都写了理由，**却不保证都写了回归方法**。

表里反复引用的那句是**「没有的东西就显示为没有」**（#3 / #7 / #26 / #33 一族）。落到具体能力上：
不伪造睡眠阶段（#10）、没有真实音频就不画波形（#2 / #13 / #27，措辞是「没有测量就不画」）、
不显示读不到的余额（#3）、不猜小米导入字段（#4；公开实现的阶段映射已被实测证明是错的，见
[`2026-10-13-xiaomi-band-sleep-integration-design.md`](docs/superpowers/specs/2026-10-13-xiaomi-band-sleep-integration-design.md) §五）。
这些是产品红线，不是待办——原型里它们是演示数据，规格书明令不得当真实能力实现。
`README.md` 的「未实现」表同样不要当成已完成。

新增或修改能力后，同步更新该规格（偏差表 / 测试矩阵）与 `README.md`（实现范围），
版本变更记入 `CHANGELOG.md`。

**`CHANGELOG.md` 只记项目级变动**：新增了什么功能、修好了什么问题、行为变了什么。
**纯文档改动不进 CHANGELOG**（README / 规格 / 计划的搬迁与重排——git 历史就是记录）。
每条三五行为宜，细节指向规格或验证记录，别写成设计文档。

**验收记录只有一处**：本轮实跑结果与**未验证项**一律写进
[`docs/verification-log.md`](docs/verification-log.md)（按时间倒序，最新在最上面）。
**每条的抬头自带它当时那台机器与环境**——文件开头那句「本机环境：macOS」只管 v3.11 之前的条目，
v3.11 起都是在 Windows 上做的。
**`README.md` 里不再保留任何一版**——连指针式的一段都不留（v3.17 起；v3.14 曾拆成
「README 留最近一版 + 更早的进 docs」两处，2026-10-13 使用方要求**全部搬走**）。
**「未验证」那一半不许省**——它是规格书「不得把没做过的事写成已完成」那条红线的凭据。

新的设计规格落 `docs/superpowers/specs/`，新的实现计划落 `docs/superpowers/plans/`，
文件名一律 `YYYY-MM-DD-<topic>.md`。规格是活文档：创建时定日期，之后原地更新，不新开文件，
变更史记入 `CHANGELOG.md`。

**先分清改动的大小，别把小改动做成大工程。** 判定标准是一句话：**这个决策能不能从代码和现有
规格里推出来？** 推得出来就直接改——不写计划、不写 spec、**也不先复述一遍要改什么**。用户报的
bug、改一句文案、调一处样式、加个开关，都属于这一类：看一眼代码，改，跑一遍测试，说结果。
一次需求花多长时间取决于改动本身，不取决于流程；**「直接改」是默认档**，据此分三档：

| 档 | 触发条件 | 产物 |
| --- | --- | --- |
| **直接改**（默认档） | 单点、单文件、现有测试能验证 | **不开 plan、不写 spec、不先复述方案**；改完跑 `dart format .` / `flutter analyze` / `flutter test`；功能 / 修复再在 `CHANGELOG.md` 记一行（纯文档改动不记） |
| **只开 plan** | 跨几处或多平台、有「不许破坏 X」的硬约束、需要先红后绿地钉测试 | 一份短 plan 挂到**已有规格**的对应章节（原地更新），**不新开 spec** |
| **spec + plan** | 新能力、新架构、影响产品语义、需要权衡取舍 | 新 spec + 新 plan |

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

`docs/architecture.md` **落后于代码几处**，动手前以代码为准：provider 表不是全集（只列了首批
7 个，`lib/` 里实际有三十多个）；schema 版本号也不是当前的（代码是 v7，README 已对齐、
architecture.md 还停在 v3）；`source` 的取值除
`manual / import / demo` 外还有 `session`（会话落库的记录）；密钥早已进系统钥匙串（v3.7 起），
文档里「尚未接入安全存储」那句是旧的。

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
