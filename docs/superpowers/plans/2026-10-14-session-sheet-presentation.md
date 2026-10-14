# 会话页改成「从底部升起的整屏面板」

**日期：** 2026-10-14 　**档位：** 只开 plan（跨 3 个 lib 文件 + 硬约束 + 先红后绿）。
**规格原地更新，不新开 spec**——落点是总规格偏差 **#24 / #28 / 新增 #56**、§2.4 页面表、§9 测试矩阵，
以及会话规格 §四。版本记入 `CHANGELOG.md` 的 **3.25**。

## 要解决的问题

使用方：**「点击开始入睡打开的这个睡眠页面，改成底部弹出展示，点击收起回到底部消失可以吗」**。

现状 `/sleep/session` 是 go_router 的推入式全屏页（`app.dart` 的 `builder:`），走平台默认转场
（iOS / macOS 右侧推入、Android Zoom）。这一页照原型 `SleepView` 做，是沉浸式睡眠模式：整屏常暗、
整屏动画夜景、文案明写「屏幕将保持暗色」，并且排版是**按可用高度算出来的「一屏放下」**。

## 拍板的四个决定

| # | 决定 | 影响 |
| --- | --- | --- |
| 1 | **整屏升起、顶部不留缝** | 改动面砍掉一大半：夜景铺满、系统栏深色覆盖、`SafeArea`、680 限宽、按高度排版全都不用动——这些恰恰是面板变矮时会坏掉的地方 |
| 2 | **两态都走这个呈现** | 入睡前与进行中共用同一套转场与手势 |
| 3 | 关闭方式 = 既有「收起」+ **下拉**；**不**点蒙层关闭 | 蒙层不另做：`ModalRoute` 无条件建一层 `ModalBarrier`，它吃指针 |
| 4 | 下拉区 = **标题行整行**（含「收起」胶囊）；拉动时**露出首页** | 需要 `opaque: false`，以及遮罩 |

## 实现

### 1. 路由转场（`lib/app/app.dart`）

`builder:` → `pageBuilder:`，返回 `CustomTransitionPage`：

- `key: state.pageKey`
- `opaque: false`（决定 4 的机械保证）
- `transitionDuration` / `reverseTransitionDuration` = `AppDurations.standard`（340ms）
- `transitionsBuilder`：竖向 `SlideTransition`，曲线 `AppMotion.standardCurve`

**为什么保住路由、不用 `showAppSheet`**：那一页里有 `context.go('/')`（结束、丢弃）与
`context.push('/log/new')`，而 `go` 不会 pop 一个 dialog 路由——结束会话会在一个仍然可见的弹层
底下导航。另外两个测试夹具把会话页当**初始路由**挂载，换掉就得整批重写。

### 2. 拖拽宿主（`sleep_session_page.dart`）

- `_SleepSessionPageState` 加 `SingleTickerProviderStateMixin` + `AnimationController.unbounded`
- `AnimatedBuilder`（**必须带 `child:`**）+ `Transform.translate`
- 松手判定复用底部弹层的阈值，常量从 `app_sheet.dart` 提成公开的
  `kPanelDismissVelocity` / `kPanelDismissFraction`
- **pop 前不复位位移**：退出动画接着从当前位置往下滑
- 回弹动画化（`app_sheet.dart` 那处回弹是硬跳，整屏面板硬跳太明显）

### 3. 手势挂在标题行上，**标题行留在滚动视图内**

提出来钉在顶部会让 `spaceBetween` 的间隙从 2 个变 1 个、hero 整体上移半个余量，
`test/session_setup_page_test.dart` 的「430×800 时 hero ≥ 210」直接红——做不到「视觉零改动」。
挂在行上就够：手势竞技场**先 accept 的赢**，标题行的竖直识别器比 `Scrollable` 的更深、先入队。

「收起」胶囊不排除在拖拽区之外：整行包住，靠竞技场让 tap 赢（胶囊的 `onTap` 更深、先入队）。

### 4. 两份标题行合并成 `SessionHeader`

`session_setup.dart` 的 `_header()` 与 `sleep_session_page.dart` 的 `_StatusHeader` 结构本来就相同，
合并成一个「壳 + 中段」组件，两个中段（`_SetupKicker` / `_LiveKicker`）逐字搬过去，节点树与合并前
逐节点相同。`_PulseDot` 一并搬进新文件。

### 5. 关闭按当前态分派（最容易漏）

`_collapseCurrentState()`：没有会话 → `_collapseSetup()`（停试听、不写库，偏差 #37）；
有会话 → `_collapse()`（会话继续跑、白噪音继续响，偏差 #28）。胶囊与下拉走同一条。

### 6. 遮罩（计划外补的）

`_dragScrim()`：模糊 14 + `NightStyle.scrim`，浓度跟着手指走。**不随面板位移**。静止时
`Opacity` 为 0 会跳过整棵子树，所以整夜挂着不花钱；顺带让系统栏在拖动全程保持深色
（`AnnotatedRegion` 因此仍覆盖屏幕顶端）。

## 不许破坏的清单

| 约束 | 钉住它的测试 |
| --- | --- |
| 进页面不写库 / 点「开始睡眠」才写 / 草稿不跨页存活 | `session_setup_page_test.dart` |
| 进行中态收起后白噪音继续响 | `sleep_session_page_test.dart` |
| 入睡前态收起停试听 | `session_setup_page_test.dart` |
| 系统栏深色 | `sleep_session_page_test.dart` + `system_bar_probe.dart` |
| 夜景铺满 / 一屏放下 / hero 连续取值 | 两个会话测试文件 |
| 结束 / 丢弃路径的 `context.go('/')` | `sleep_session_page_test.dart` |
| 嵌套弹层（白噪音 / 时间轮 / 评星 / 丢弃说明） | `session_setup_page_test.dart`、`sleep_session_page_test.dart` |
| 长按结束不受影响 | `hold_to_finish_button_test.dart`、`sleep_session_page_test.dart` |
| 端到端「点开始入睡 → 收起回首页」 | `pages_widget_test.dart`、`sleep_session_page_test.dart` |

## 新增测试

`test/session_sheet_test.dart`，9 条，走真实 `NightSleepApp`（另起一份路由会把要验的东西架空）：
路由非不透明且底下的首页仍在树上、从底部升起（头几帧在屏幕下方 → 落到顶边）、静止时铺满整屏、
进行中态下拉过阈值 → 滑走回首页且**不停**白噪音、入睡前态下拉 → **先停**试听且不写库、
小幅下拉回弹、「收起」胶囊整体位于下拉区之内、点它仍是点击、拖动中系统栏仍是深色。

## 验证

1. `dart format .` → `flutter analyze` → `flutter test`（637/637）
2. 先红：把 `pageBuilder` 换回 `builder:`，九条全红
3. 手走一遍：首页 →「开始入睡」→ 标题行下拉（不足阈值回弹）→ 拉过阈值（滑走、后面是首页）
   →「收起」→ 再进 →「开始睡眠」→ 进行中态下拉 → 长按结束
4. **真机未做**：下拉手感、`opaque: false` 的整夜绘制开销、遮罩观感、iOS 左缘返回手势消失后的
   观感——都记在 [`docs/verification-log.md`](../verification-log.md) 的 v3.25 条

## 落地结果

四份文档同步更新：总规格偏差表（#24 / #28 原地改写 + **新增 #56** + §2.4 页面表 + §9 测试矩阵
新增一行）、会话规格 §四、`README.md`（「弹层手势」段与会话页一节）、`docs/architecture.md`
（`Subpage` 规则那处例外）。版本见 `CHANGELOG.md` 3.25。

**一条被当天推翻的预判**：「漏写 `key: state.pageKey` 会重挂页面、清掉草稿」——变异验证没有复现
（`Page.canUpdate` 比 `other.key == key`，`null == null` 为真）。`key` 仍保留，但**没有测试钉住**。
