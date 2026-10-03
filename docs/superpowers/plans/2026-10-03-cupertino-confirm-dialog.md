# 确认弹窗改用 iOS 系统组件（实现计划）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把三处二次确认弹窗从「按令牌自绘的 iOS 风格组件」换成 **`CupertinoAlertDialog` 真系统组件**，推翻规格偏差 #20 中「不引入 `flutter/cupertino.dart`」的裁定；`showConfirmDialog` 的**函数签名与返回值语义不变**，三处调用点一行不改。

**Architecture:** 只动 `lib/core/widgets/confirm_dialog.dart` 一个文件——它目前是自绘实现（`showGeneralDialog` + `DecoratedBox` 卡片 + 手工分隔线 + 手工转场），改成 `showCupertinoDialog` + `CupertinoAlertDialog` + `CupertinoDialogAction`。新增一条 `CupertinoTheme` 薄映射，把**能过令牌的部分**（亮度、`primaryColor`、动作文字色）仍接回 `AppTokens`；**接不回的部分**（弹窗底色、分隔线色、圆角、模糊表面）按系统值走，这是这次替换的既定代价，写进偏差 #20。

**Tech Stack:** Flutter 3.47.5 / Dart、`flutter/cupertino.dart`（SDK 内置，无新依赖）

**设计依据:** [docs/superpowers/specs/2026-09-29-fix-round-design.md](../specs/2026-09-29-fix-round-design.md) §5；[2026-09-28-night-sleep-design.md](../specs/2026-09-28-night-sleep-design.md) §8 偏差 #20

## Global Constraints

- 界面文案、注释、文档一律**中文**；代码标识符英文。
- **不改 `lib/**/*.g.dart`**。本计划不碰表结构，无需 `build_runner`。
- **不要设 `PUB_HOSTED_URL` / `FLUTTER_STORAGE_BASE_URL`**（理由见上一份 plan，会污染 `pubspec.lock`）。
- `showConfirmDialog` 的**签名与返回值语义冻结**：取消 / 点蒙层一律返回 `false`，三处调用方的
  `if (confirmed != true) return;` 必须继续成立。
- 测试里**不要 `await HapticFeedback.*`**，**不要订阅 drift 的 `watch*` 流**。
- 每个任务结束时跑 `dart format .`、`flutter analyze`、`flutter test`，**全绿才提交**。
- 基线：本轮开工前 `flutter test` 全绿（含 `confirm_dialog_test.dart` 7 条、`pages_widget_test.dart`
  的确认弹窗 2 条）。

## 已核实的事实（来自 Flutter 3.47.5 SDK 源码，非记忆）

| 事实 | 出处 |
| --- | --- |
| `CupertinoDialogAction.textStyle` 在颜色解析**之后** `.merge()`，能覆盖 destructive 的 `systemRed` | `cupertino/dialog.dart:2336-2341` |
| `CupertinoDialogAction` 把样式落成 `DefaultTextStyle(style: textStyle, …)`，断言可直接读渲染色 | `cupertino/dialog.dart:2312-2318` |
| 弹窗底色 `_kDialogColor` = `0xCCF2F2F2`(浅) / `0xCC2D2D2D`(深)，**半透明、叠在模糊背景之上** | `cupertino/dialog.dart:118-121` |
| 分隔线色 `CupertinoColors.separator`、粗细 `_kDividerThickness = 0.3`——**不可主题化** | `dialog.dart:378, 86` |
| 弹窗定宽 `_kCupertinoDialogWidth = 270`；外边距 `horizontal 40 / vertical 24` | `dialog.dart:92, 443` |
| 标题 17/w600/-0.5、正文 13/w400/1.35，色均取 `CupertinoColors.label` | `dialog.dart:36-54, 338-343` |
| 恰好两个按钮 → **左右并排**，中间一条竖分隔线 | `dialog.dart:2394+`（`_AlertDialogActionsLayout`） |
| `showCupertinoDialog` 转场：`FadeTransition` + `ScaleTransition(1.3 → 1.0)`，`SpringSimulation`（iOS 标准弹簧），250ms | `cupertino/route.dart:1526-1550` |
| `showCupertinoDialog` 默认 `barrierDismissible: false`、`useRootNavigator: true` | `cupertino/route.dart:1410-1419` |
| `MaterialApp` 默认带上 `DefaultCupertinoLocalizations.delegate`，`CupertinoAlertDialog` 在纯 MaterialApp 下可正常构建 | `material/app.dart`、`dialog.dart:427` |

## 保留的既有裁定（这次不改）

- **`barrierDismissible: true`**：系统 alert 默认点蒙层不关，但本应用三处调用方都依赖
  「点蒙层 = 取消 = 返回 false」这个既有行为，测试也钉着它。**保持 true**，不顺手改成系统默认。
- **取消在左、确认在右**：`CupertinoAlertDialog` 按传入顺序排布，传参顺序保持 `[取消, 确认]`。
- **蒙层色 `tokens.overlayScrim`**：`barrierColor` 是公开可传参，继续接令牌，与 `AppSheet` 同源。

## 文件结构

| 文件 | 职责 | 动作 |
| --- | --- | --- |
| `lib/core/widgets/confirm_dialog.dart` | 改为 `CupertinoAlertDialog` 实现 | **重写** |
| `test/confirm_dialog_test.dart` | 护栏改成钉新契约（系统组件、返回语义、按钮次序、动作配色） | **重写** |
| `test/pages_widget_test.dart` | 只依赖文案与可见性，**预期不用改** | 核对 |
| `docs/superpowers/specs/2026-09-29-fix-round-design.md` | §5 加「v3.6 后续变更」批注（原文保留） | 改 |
| `docs/superpowers/specs/2026-09-28-night-sleep-design.md` | 偏差 #20 重写；§9 测试矩阵与视觉检查行同步 | 改 |
| `README.md` | 实现范围 v2.6 段、验证记录 | 改 |
| `CHANGELOG.md` | 新增条目 | 改 |

---

## 任务 1：重写 `confirm_dialog.dart`

**Files:** `lib/core/widgets/confirm_dialog.dart`

- [x] **1.1** 引入 `package:flutter/cupertino.dart`（与 `material.dart` 并存，无符号冲突）。
- [x] **1.2** `showCupertinoDialog<bool>` 取代 `showGeneralDialog<bool>`；去掉手写
      `transitionBuilder`（系统自带 iOS 弹簧）与 `Material` 补层（Cupertino 自管文字样式）。
- [x] **1.3** `builder` 里包一层 `CupertinoTheme(data: CupertinoThemeData(brightness: Theme.of(context).brightness, primaryColor: tokens.accent))`：
      亮度决定底色/文字的深浅，`primaryColor` 是**非破坏性动作的默认色**。
- [x] **1.4** `CupertinoAlertDialog(title: Text(title), content: Text(message), actions: [取消, 确认])`。
- [x] **1.5** 两个 `CupertinoDialogAction` 显式传 `textStyle: TextStyle(color: …)`——取消 `tokens.accent`、
      确认 `destructive ? tokens.danger : tokens.accent`，确认那枚加 `isDefaultAction: true`（iOS 的加粗默认动作）。
      **只传 color，不传 fontSize**：SDK 文档明确要求「非默认字号才传 textStyle」，传了会绕过它的缩放策略。
- [x] **1.6** 保留 `final confirmed = await …; return confirmed == true;`，返回语义不变。

**验收：** `flutter analyze` 无告警；`confirm_dialog_test.dart` 重写后全绿（任务 2）。

## 任务 2：重写 `test/confirm_dialog_test.dart`

**Files:** `test/confirm_dialog_test.dart`

新的护栏（旧的 4 条「自绘特征」断言——`Material` 祖先、`ColoredBox` 双分隔线、`AppRadii.sheet` 卡片——**全部作废**，它们描述的是刚被替换掉的实现）：

- [x] **2.1** **用的是系统组件**：`find.byType(CupertinoAlertDialog)` 命中一枚。这是整份测试的主回归锚——
      退回任何自绘实现立刻变红。
- [x] **2.2** **返回值语义不变**：取消 → `false`；确认 → `true`；点蒙层 → `false`（不能是 `null`）。
- [x] **2.3** **按钮次序不变**：取消 `dx <` 确认 `dx`。
- [x] **2.4** **动作配色仍接令牌**：读渲染出来的 `DefaultTextStyle.of(element).style.color`——
      破坏性确认 = `tokens.danger`、非破坏性确认 = `tokens.accent`。
- [x] **2.5** **文案原样渲染**：标题、正文、两个按钮文案各命中一次。
- [x] **2.6** （可选）深色下 `CupertinoTheme` 亮度跟随 app：`AppTheme.dark()` 下断言弹窗底色解析为深色值。

**验收：** `flutter test test/confirm_dialog_test.dart` 全绿。

## 任务 3：跑全量测试，核对另两处调用方

**Files:** `test/pages_widget_test.dart`（预期只读）

- [x] **3.1** `flutter test` 全绿。`pages_widget_test.dart` 的「删除全部数据前要求二次确认」与
      「取消清除演示数据的确认后…」只断言**文案与可见性**，预期不受影响。
- [x] **3.2** 若出现「找不到 `CupertinoDialogAction`」类失败，先查 `MaterialApp` 是否带
      `DefaultCupertinoLocalizations`（模块测试里用了裸 `WidgetsApp` 的话需要补）。
- [x] **3.3** 变异验证：把 `CupertinoAlertDialog` 换回任一自绘 widget，2.1 必须变红。

## 任务 4：同步文档（CLAUDE.md 硬要求）

- [x] **4.1** `2026-09-28-night-sleep-design.md` §8 偏差 #20 重写为「用系统 `CupertinoAlertDialog`」，
      理由如实记：**接不回令牌的部分**（底色/分隔线/圆角/模糊表面）按系统值；动作色与亮度仍过令牌；
      写明这次是对用户明确要求的响应。
- [x] **4.2** 同规格 §9 测试矩阵与视觉检查行同步（自绘特征断言作废，新增系统组件断言）。
- [x] **4.3** `2026-09-29-fix-round-design.md` §5 加一条**后续变更批注**指向偏差 #20：那是一份有日期的
      轮次记录，把当年的「不引入 cupertino」原地改写成相反说法等于篡改历史，因此**保留原文 + 批注**。
- [x] **4.4** `README.md` 实现范围 v2.6 段与验证记录同步；`CHANGELOG.md` 记一条。
- [x] **4.5** 本计划的日期条款：`docs/superpowers/` 下文件名日期用创建日（2026-10-03）。
