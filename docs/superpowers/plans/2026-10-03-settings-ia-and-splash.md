# 设置页 IA 重排与开屏页 实现记录（2026-10-03）

> **这是落地记录，不是事前的任务书。** 设计口径见
> [设置页信息架构重排与开屏页设计](../specs/2026-10-03-settings-ia-and-splash-design.md)。
> 编排档位：**spec + plan**（新能力 + 信息架构变更 + 新路由），但改动集中在一个 feature 目录、
> 没有跨端并行，因此**没有逐任务派实现者 / 审查者**，审查一次做完。

**目标：** 把更新后的原型落进实现——设置根页改成三段导航式列表、外观与睡眠设置各收进一个
二级页、冷启动多一屏开屏。视觉令牌一个字节不改。

**不新增任何依赖。**

## Global Constraints

- 界面文案、注释、文档一律中文；代码标识符英文。
- 颜色 / 圆角 / 动效曲线从 `AppTokens.of(context)` 取，**不在 widget 里写死色值**。唯一的例外是
  开屏页：它照会话页 `night_style.dart` 的先例用**页面局部**常量（规格偏差 #32 的同一条理由）。
- 每个推入页面走 `Subpage`（推入的路由继承不到 `Scaffold` 与 `Material` 祖先）。
- 提醒的读写与调度行为**一字不改**，只是换了宿主页面。
- 两条产品红线逐字保留：声音检测的「尚未接入录音，开关只保存偏好」、权限被拒的「去系统设置」行。

## 落地步骤（实际执行顺序）

1. **公共下拉**：`lib/core/widgets/app_menu_field.dart`（由洞察配置页的私有 `_MenuField` 提升，
   保留它原有的竖排版式，新增 `expand: false` 的行内收缩支路）。
2. **外观页**：`appearance_settings_page.dart`。
3. **自绘滑块**：`widgets/goal_slider.dart`（`GestureDetector` + `CustomPaint` + `Semantics`）。
4. **睡眠设置页**：`sleep_settings_page.dart`（提醒逻辑整段搬过来）。
5. **设置根页重写**：`settings_page.dart`（三段导航 + 关于行）。
6. **开屏页**：`splash_screen.dart` + `app.dart` 接线。
7. **删死代码**：`dur_bar.dart`（只有旧设置页一个调用点）。
8. **原生底色**：iOS `LaunchScreen.storyboard`、`web/manifest.json`。
9. **测试**：改 `pages_widget_test.dart` / `reminder_settings_test.dart`，新增 `splash_screen_test.dart`。
10. **文档**：本规格、主规格 §2.4 / §8 / §9、README、CHANGELOG、`docs/architecture.md`。

## 途中发现并处理的问题

- **开屏的收起时机**：最初只按计时器收起。`settingsProvider` 是异步流，还没吐第一帧时外壳会
  先露出来、引导页随后再盖上去。改成「播完 **且** `settings` 有结论」，判据取 `isLoading`
  （覆盖成功与失败两种终态）。
- **不引入兜底 Timer**：挂真外壳的测试会在结束时报 pending timer。改为只依赖 `AsyncValue`。
- **测试推进方式**：`AnimationController` 的起点是 ticker **第一次 tick** 的时刻，
  `pumpWidget` 之后必须再 `pump()` 一次起表，否则接着的 `pump(时长)` 会把起点定在那一帧上。
  写测试时踩过一次，已在 `test/splash_screen_test.dart` 的辅助函数里写明。
- **`_MenuField` 提升不是平移**：洞察页是「标签在上、字段在下」的竖排且调用方用 `Expanded` 包着；
  外观页要的是行内右对齐。提升时保留原版式不动，另加一条**不使用 flex 子项**的收缩支路
  （行内版式落在无界宽度的 `Row` 里，用 `Expanded` 会报无界约束下使用 flex）。
- **行内下拉的箭头一度没贴右**（使用方在终审时指出）：没有 flex 子项时，`Container` 的
  `minWidth` 撑出来的富余宽度被 `Row` 的默认 `start` 全留在右边，箭头离右端 21.4px 而不是
  内边距的 12px。补 `MainAxisAlignment.spaceBetween`（原型 `.appearance-select-trigger` 的
  `justify-content: space-between`）后归位，并补了一条量渲染矩形的回归。

## 验证（实际跑过的）

| 项 | 结果 |
| --- | --- |
| `dart format .` | 无额外改动 |
| `flutter analyze` | **No issues found** |
| `flutter test` | **424/424 通过**（新增 5 条开屏用例、6 条二级页用例，并在终审时补 1 条「下拉箭头贴右」的几何回归） |
| 变异验证 1 | 去掉滑块吸附（`_snap` 退回直接 clamp）→「按 0.5 小时吸附」变红 ✅ |
| 变异验证 2 | 开屏收起条件去掉 `settingsAsync.isLoading` →「设置还没读到第一帧时」变红 ✅ |
| 变异验证 3 | 声音检测副标题换成原型那句「检测打鼾、梦话并生成洞察」→ 红线用例变红 ✅ |
| `flutter test integration_test/` | **未跑**（要 `flutter drive` + 真机/模拟器）；`flutter analyze` 已覆盖编译 |
| 目视核对（macOS） | **开屏页通过**：渐变 / 轨道环 / 星点 / logo 与两道声波 / 文案 / 进度条逐项在位（`screenshots/v3.5-splash.png`）。**设置根页与两个新二级页未通过**：巡检被系统「`night_sleep` 想访问『文稿』文件夹」的授权框盖住窗口，本机没给辅助访问权限、点不掉系统对话框 |
