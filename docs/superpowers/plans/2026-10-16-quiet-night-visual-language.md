# 实现计划：静谧夜色 + 柔和晨光

对应规格：[2026-10-16-quiet-night-visual-language.md](../specs/2026-10-16-quiet-night-visual-language.md)
落地版本：v3.34

## 目标

把原型末层的**三层材质**与**每页一张 hero 卡**铺到首页 / 回顾 / 统计 / 设置，
按新原型**整体重做**「全部睡眠数据」页，并补上原型没有、使用方点名要的四项。

## 不做什么（见规格 §「不做什么」）

不换字体、不动圆角基数（24 / 16）、不给首页补阶段环、不让结论条推断没测过的东西、
不动 §5.2 的三条计算口径。

## 全局约束（每个任务都适用）

- 令牌只从 `AppTokens.of(context)` 取；**唯一的新增是 `good`**（规格 §3.2）。
- 文案、注释、文档一律中文；标识符英文。
- 改完跑 `dart format .` / `flutter analyze` / `flutter test`。
- **不许把没做过的事写成已完成**：本节里没验的，验收记录要留在「未验证」。

---

## 任务 1：底座——令牌、`QuietSurface`、`HeroSurface`

**产物**

- `lib/core/theme/app_tokens.dart`：新增 `good` 字段 + 浅色 `#2E9E83` / 深色 `#86D8C6`，
  两套常量各加一份（`copyWith` 是空操作、`lerp` 是硬切，没有派生路径）。
  `surfaceShadow` 的 `this == dark` 身份比较不受影响。
- `lib/core/widgets/quiet_surface.dart`：新增 `QuietSurface`，API 与 `GlassSurface` 对齐
  （`child` / `borderRadius` / `padding` / `margin` / `onTap` / `semanticLabel` / `expandWidth`），
  但**不接 `BackdropFilter`**、**不画顶部高光与斜向扫光**。
- `lib/core/widgets/hero_surface.dart`：新增 `HeroSurface`，五张 hero 卡共用一份绘制路径——
  渐变底、1px 描边、阴影、可选的**角光晕**（`alignment` / 尺寸 / 颜色 / 是否呼吸）、
  可选的**星点**、可选的**局部令牌覆盖**（`AppTokens? tokenOverride`，见规格 §2.1）。

**钉住**：无。

**注意**：`GlassSurface` 一个字节不改。三层材质的差别全在「用哪一个」，不在「改哪一个」。

---

## 任务 2：领域与纯函数

**产物**

- `lib/features/sleep/domain/sleep_history.dart`：`HistoryGrouping` 标签改 `周 / 月 / 年`；
  新增 `HistoryWindow` + `windowOf()` / `latestAnchor()` / `isLatestWindow()`；
  保留周一起算、`DateTime(y, m, d - n)` 构造、周标签带年份、平均分只计已评分、
  平均时长分母是记录条数；`startOf` / `endOf` 提为可直接测的纯函数。
  旧的 `SleepHistory.from` / `SleepHistoryGroup` 一并删除（只被这一页用）。
- `lib/features/sleep/domain/sleep_quality.dart`：五个 `label` 改成
  `精疲力尽 / 疲惫 / 一般 / 清醒 / 精力充沛`；新增 `feedback`（规格 §3.3 那张表）。
- `lib/features/home/domain/home_insight.dart`（新增）：
  `greetingFor(DateTime)` 与 `durationInsight(...)` / `durationAdvice(...)`，纯函数、可单测。

**钉住**：`test/sleep_history_test.dart` 扩写（周期窗口边界、锚点在周期内任一天得到同一窗口、
空窗口）；`test/home_insight_test.dart` 新增（问候四个时段边界、结论条四条分岔 + 建议两分岔）。

---

## 任务 3：首页

**产物**（`lib/features/home/presentation/home_page.dart`）

- 眉题改成 `问候 · 日期`（时间取既有的 `homeNowProvider`）。
- 昨夜卡换成 `SleepHeroCard`：夜色 hero + 角月晕（呼吸）+ 星点 + **结论条** + 原有内容；
  阶段三块仍只在 `entry.hasStages` 时出现（偏差 #10）。
- 两张功能卡换 `QuietSurface`（半径 16）。
- 最近记录改成**一个扁平列表容器**（半径 18、行间 1px 分隔线）；
  `RecordCard` 收成页内私有行组件（全仓只有首页用它），行内内容不变。
- 结论条文案与圆点用 `good` 色。

**不许**：为了让 hero「满」一点而给无阶段记录补阶段块。

---

## 任务 4：回顾的两处表单

**产物**

- `lib/features/sleep/presentation/widgets/quality_rating.dart`：
  `QualityStars` → `QualityChoice`（五个文字药丸 + 选中态 + 即时反馈位），
  无障碍标签仍是 `睡眠质量 {label}`（新标签）。
- 三个调用点一起换：`review_page.dart` / `log_page.dart` / `sheets/quality_rating_sheet.dart`。
- 两处表单：时长预览卡换晨光 hero，事件宫格 / 时间三行 / 备注换 `QuietSurface`，
  事件选中态用「事件色 11% 混 bgCard + 1.5px 事件色 38% 描边」。
- 回顾页补会话结束横幅（`review-session-banner` 的形态）。

**不许**：给 `quality` 预设任何一档（偏差 #26）；未选时显示反馈句或占位符。

---

## 任务 5：统计页

**产物**（`lib/features/stats/presentation/stats_page.dart`）

- 柱状图卡换 `StatsDataHero`，评分卡换 `StatsScoreCard`，
  四项汇总卡与梦话卡换 `QuietSurface`。
- 右上角入口文案 `全部数据` → `查看所有数据`。
- **不动**柱状图的几何：`slot >= 24` 的事件图标闸、`chartFloor/Ceiling`、`barGap` 都不改
  ——v3.33 刚为 14/30 天的溢出钉过回归用例，不能碰回去。

---

## 任务 6：全部睡眠数据页整体重做

**产物**

- `lib/features/stats/presentation/all_sleep_data_page.dart` 按规格 §4.5 重写。
- `lib/app/app.dart` 的路由不变（`/stats/all`）。

**必须守住**：`估算 NN` / `评分 NN` 的区分、演示记录报数、空库整页空状态、
周期内无记录另有空状态、向后翻页在最新周期时禁用（偏差 #71）。

**钉住**：`test/all_sleep_data_page_test.dart` 重写；`test/pages_widget_test.dart`
的入口用例跟上文案。

---

## 任务 7：设置页

**产物**：睡眠目标卡换 `SettingsGoalHero`；设置类分组列表换 `QuietSurface`。
**不动**根页只做导航这条 IA（偏差 #43）。

---

## 任务 8：收口

- `README.md`「实现范围」跟进（新页面形态、命名质量状态）。
- `CHANGELOG.md` 记 v3.34（功能与行为，指向规格）。
- `docs/verification-log.md` 按时间倒序加一条，**「未验证」那一半照规格 §八 写全**。
- `docs/superpowers/plans/ARCHIVE.md` 本轮做完后补一行。

## 编排

任务 1、2 先做（其余全依赖它们）。任务 3 / 4 / 5 / 6 / 7 之间文件不重叠，可并行。
任务 8 最后统一做。
