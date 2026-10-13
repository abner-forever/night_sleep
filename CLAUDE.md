# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 这是什么

「夜深」——中文、本地优先的睡眠记录 Flutter 应用（iOS / macOS 已构建；Web 有骨架、
**Android 平台目录未生成**，两者均未构建，见 README「未实现」表）。
界面按 Figma Make 原型的**最终生效层**实现。

**动手前先读 `docs/superpowers/specs/2026-09-28-night-sleep-design.md` 第 8 章「与原型的有意偏差」。**
里面 22 条都是刻意为之的，
每条附了理由和回归方法。其中「不伪造睡眠阶段 / 不画没有真实音频的波形 / 不显示读不到的余额 /
不猜小米导入字段」这几条是产品红线，不是待办：原型里这些是演示数据，规格书明令不得当真实能力实现。
`README.md` 的「未实现」表同样不要当成已完成。

新增或修改能力后，同步更新该规格（偏差表 / 测试矩阵）与 `README.md`（实现范围），
版本变更记入 `CHANGELOG.md`。

**验收记录分两处**（v3.14 拆的，理由见 [`docs/verification-log.md`](docs/verification-log.md) 开头）：
本轮实跑结果与**未验证项**写进 `README.md` 的「验证记录」，同时把**被顶下来的上一版**
挪进 `docs/verification-log.md`（按时间倒序）。**「未验证」那一半不许省**——它是规格书
「不得把没做过的事写成已完成」那条红线的凭据。

新的设计规格落 `docs/superpowers/specs/`，新的实现计划落 `docs/superpowers/plans/`，
文件名一律 `YYYY-MM-DD-<topic>.md`。规格是活文档：创建时定日期，之后原地更新，不新开文件，
变更史记入 `CHANGELOG.md`。

**不是每个改动都要 spec + plan。** 判定标准是一句话：**这个决策能不能从代码和现有规格里
推出来？** 据此分三档：

| 档 | 触发条件 | 产物 |
| --- | --- | --- |
| **直接改** | 单点、单文件、现有测试能验证 | 不开 plan；跑 `dart format .` / `flutter analyze` / `flutter test`，CHANGELOG 记一行 |
| **只开 plan** | 跨几处或多平台、有「不许破坏 X」的硬约束、需要先红后绿地钉测试 | plan 挂到**已有规格**的对应章节（原地更新），**不新开 spec** |
| **spec + plan** | 新能力、新架构、影响产品语义、需要权衡取舍 | 新 spec + 新 plan |

plan 的厚度跟着改动量走——不要为了格式齐整，把单点修改写成几百行。

编排强度同样跟档位走：`subagent-driven-development` 那套「每个任务派实现者 + 审查者」只用于
**spec + plan** 档。`只开 plan` 档在当前会话里直接做，审查**集中在阶段末尾做一次**，不要逐任务派
subagent——每个 subagent 都要从头重读 CLAUDE.md / 规格 / 源码，对小改动是纯开销。

## 常用命令

```bash
flutter pub get
dart run build_runner build     # 生成 lib/core/database/app_database.g.dart，改表结构后必跑
dart format .
flutter analyze
flutter test                     # 整套测试
flutter test test/sleep_score_test.dart                      # 单个文件
flutter test test/sleep_score_test.dart --plain-name "分档阈值"  # 单个用例（子串匹配）
flutter run -d macos
```

国内网络下的 pub 镜像、iOS / macOS 构建的网络前提与代理，以及演示数据开关 `DEMO_DATA`，
见 README「运行与生成」与「构建 iOS / macOS 的网络前提」两节。

**不要改 `lib/**/*.g.dart`**（已 gitignore，由 Drift 生成）。也不要往 `~/.zshrc` 等
shell profile 里写环境变量——需要时用命令行前置的临时变量。

## 架构

分层约定、Riverpod provider 表、路由规则、数据库 schema 与迁移决策，见
[`docs/architecture.md`](docs/architecture.md)。

**三条最容易违反的**：Widget 不直接碰数据库（UI 唯一数据源是 `sleepEntriesProvider`）；
每个 push 页面都走 `Subpage`（推入的路由继承不到 `Scaffold` 与 `Material` 祖先）；
`SleepRepository.save()` 的 `stages` 传 `null` 表示「保持已有阶段不变」，不是「清空」。

## 写 Flutter 代码前

渲染与布局陷阱（`boxShadow` 被 clip 吃掉、`BackdropFilter` 的遮罩顺序、`Stack` 尺寸、
滚动视图留白、`Positioned` 的参照盒、`Material` 祖先缺失导致黄线）与 widget 测试陷阱
（FakeAsync 挂死、drift `watch*` 的 pending timer、`pumpPage` vs `pumpRoute`、迁移测试冻结裸
DDL）见 **[`.claude/skills/flutter-pitfalls/SKILL.md`](.claude/skills/flutter-pitfalls/SKILL.md)**
——写 widget / 布局 / widget 测试时会自动加载。没自动加载就主动读一次。

`integration_test/` 不参与 `flutter test`（要 `flutter drive`，见 README「界面截图巡检」）。

## 其他约定

- 界面文案、注释、文档一律中文；代码标识符英文。
- `analysis_options.yaml` 开了 `avoid_print`、`prefer_const_constructors`——CLI 工具与巡检脚本
  需要 print 时用 `// ignore: avoid_print`。分析器排除 `build/ ios/ web/ macos/`。
- 设计令牌只有一份（`app_tokens.dart` 的 `AppTokens` 主题扩展）。颜色/圆角/动效曲线从
  `AppTokens.of(context)` 取，不要在 widget 里写死色值。
- 「获取可用模型」调服务商 `GET /models`：API Key 只走请求头，不落日志、不持久化，
  **错误信息也不回显响应体**（服务商可能把请求头原样引回来）。

其余实现细节（宽屏断点、`AppHaptics`、助眠音效合成参数）见
[`docs/architecture.md`](docs/architecture.md)。
