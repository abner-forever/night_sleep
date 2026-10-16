# 全部睡眠数据 + 导出表格预览 实现计划

**状态：** 已落地（v3.31）。逐条实跑结果与**未验证项**见[验证记录](../../verification-log.md) v3.31。

**Goal:** 导出页多一个「预览表格」入口，能逐格看到将写进 CSV 的内容；统计页右上角多一个
「全部数据」入口，进二级页按周 / 按月 / 按年翻阅全部记录。

**设计依据：** [2026-10-15-sleep-data-browsing-design.md](../specs/2026-10-15-sleep-data-browsing-design.md)

**Tech Stack:** Flutter / Riverpod / go_router。**不新增依赖、不动 schema、不跑 `build_runner`。**

## Global Constraints

- 界面文案、注释、文档一律中文；代码标识符英文。
- 令牌只从 `AppTokens.of(context)` 取；推入页一律走 `Subpage`；**不放写路径**（两页都是只读）。
- 预览与文件**同源**：单元格只在 `SleepExporter.tables()` 里产生，界面不得自己格式化。
- 「没有的东西就显示为没有」：未评分不写评分、组内无评分不显示平均分、预览截断必须说出来。
- **不许把没做过的事写成已完成**：没目视核对的一律留在规格 §六与 `docs/verification-log.md`。

---

## Task 1: 领域层——`tables()` 与 `SleepHistory`

**Files:**
- Modify: `lib/features/settings/domain/sleep_export.dart`
- Create: `lib/features/sleep/domain/sleep_history.dart`
- Modify: `lib/features/sleep/domain/sleep_math.dart`
- Test: `test/sleep_export_test.dart`、`test/sleep_history_test.dart`（新）、`test/sleep_math_test.dart`

- [x] `ExportTableKind`（记录 / 阶段）、`ExportTable`（fileName / header / rows）
- [x] `SleepExporter.tables()`：文件名 + 表头 + 行都在这里产生；`csv()` 改为它的序列化
- [x] 往返断言：解析 `csv()` 的产物 == `tables()` 的表头与行（含引号 / 逗号 / 换行的备注）
- [x] `HistoryGrouping` / `SleepHistoryGroup` / `SleepHistory.from`：按醒来本地日归组，
      周一起算（`DateTime(y, m, d - (weekday - 1))`，**不用 `subtract(Duration)`**），
      组间与组内都最新在前，平均分只计已评分
- [x] `formatWeekday`（`周三`，手写七项，不引 intl 本地化数据）

**验收边界：** `flutter test test/sleep_export_test.dart test/sleep_history_test.dart test/sleep_math_test.dart`

---

## Task 2: 导出表格预览页

**Files:**
- Create: `lib/features/settings/presentation/export_preview_page.dart`
- Modify: `lib/features/settings/presentation/export_page.dart`（新增「预览表格」行，无数据时禁用）
- Modify: `lib/app/app.dart`（路由 `settings/export/preview`）
- Test: `test/export_preview_page_test.dart`（新）

- [x] 分段控件切换记录 / 阶段两张表
- [x] 真实文件名 + 总行数一行灰字
- [x] 表格：表头 + 行，横向滚动，列宽固定、单元格内换行；`GlassSurface(expandWidth: false)`
- [x] 50 行上限 + 「预览只显示前 50 行，文件包含全部 N 行」
- [x] 空状态 + 被排除的演示条数
- [x] 导出页入口行（第一行，无数据时与两个导出动作一起禁用）

**验收边界：** widget 测试（`pumpRoute`，断言无 `Scaffold` 也渲染正常）。

---

## Task 3: 全部睡眠数据页

**Files:**
- Create: `lib/features/stats/presentation/all_sleep_data_page.dart`
- Modify: `lib/features/stats/presentation/stats_page.dart`（标题行右上角入口）
- Modify: `lib/app/app.dart`（路由 `/stats/all`）
- Test: `test/all_sleep_data_page_test.dart`（新）、`test/pages_widget_test.dart`

- [x] 顶部汇总卡：记录数 / 平均时长 / 平均评分（无评分写「未评分」）+ 覆盖范围
- [x] 分段控件：按周 / 按月 / 按年，默认按月
- [x] 组抬头 + `IosListGroup` 装组内记录行；点一行开详情弹层
- [x] 空状态
- [x] 统计页入口（有记录才出现）；真路由测试：点进去 → 落到 `/stats/all` → 返回仍在统计页

**验收边界：** widget 测试 + 真实路由用例。

---

## Task 4: 收尾

- [x] `dart format .` / `flutter analyze` / `flutter test`（整包）
- [x] 总规格 §8 偏差表加 **#66**（全部数据页，原型无）、**#67**（导出表格预览，原型无）；
      §2.4 改统计与导出页两行；§3 映射表补两行；§9 测试矩阵补行
- [x] [导出与提醒规格](../specs/2026-09-28-export-and-reminders-design.md) 的「导出页」一节补预览入口
- [x] `README.md`「现在能做什么」的统计与数据导出两节各补一句
- [x] `CHANGELOG.md` 记 v3.31；`docs/verification-log.md` 记本轮实跑结果与**未验证项**
- [x] `docs/superpowers/plans/ARCHIVE.md` 索引补一行

**验收边界：** 三个命令全绿 + 文档四处同步。

---

## 落地结果（v3.31）

计划外的两处，都是实现时才发现必须做的：

1. **导出排序要变成全序。** `exportableOf` 原本只按入睡时刻排，同一时刻的两条先后**未定义**；
   而预览与文件是两次独立的排序调用——未定义就等于两者可以不一致，正好破坏这一轮的核心承诺。
   加了 id 兜底，并补一条用例（两种传入顺序得到同一个结果）。
2. **`AppTheme.num` 不接受 `height`**，表格单元格不能用它；改用 `TextStyle` + `AppTheme.tabular`
   的等宽数字。列宽也从「拍脑袋」改成按**实际最长内容**给足——窄一格就会折行，整张表行高参差。

实跑：`dart format .`（199 文件 / 0 changed）、`flutter analyze`（No issues found）、
`flutter test`（**761 条全过**，本轮新增 43 条）。

---

## 独立复核后的修补（同日晚）

另起一个 agent 读规格与代码做对抗性复核，它提出的六条里有四条成立、两条是潜在缺口，
已全部处理：估算分数不许顶着「评分」出场（跟首页 `isEstimated ? '估算' : '评分'` 同一句）、
导出页「读不到 ≠ 没有」（三态各有各的说法）、演示记录在汇总卡里报出条数、
**打不中「组的平均取自本组」的弱夹具**（改成各组平均与全库平均故意不同）、
`SleepHistory` 的同一入睡时刻定序、以及验收记录里那三个凑不到一起的条数。
它明确否掉的三类猜测：日历边界（跨月 / 跨年的周、12 月与闰年 2 月的月末）实测无误、
`tables()` 是原 `csv()` 的忠实序列化、布局上没有新陷阱。
