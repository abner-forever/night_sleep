# Android 系统栏与安全区适配实现计划

日期：2026-10-13
规格：[2026-10-12-android-platform-design.md](../specs/2026-10-12-android-platform-design.md) §六（原地新增）
档位：**只开 plan**（跨 Dart 与真机两侧、有「不许破坏 iOS 那一套」的硬约束，但决策完全能从
现有规格与实测推出来——不动产品语义，不新开 spec）

## 目标

用户原话：**「顶部状态栏现在是灰色的（light 模式下）；底部的安全区域是被截断的，不像 iOS
那样的安全区适配」**。两条都要在真机上消失。

> **计划里原本还写着一条硬约束：「iOS / macOS 的行为一个字都不许变」。**
> **这条没做到，也不该做到**——`appSystemUiOverlayRegion` 挂在 `MaterialApp.builder` 上，
> 是无条件的，于是 iOS 的状态栏前景色从「跟随系统外观」变成了「跟随应用主题」。
> 那正是本意（应用有自己独立的外观开关，系统栏跟随系统的话，深色页面上会压出一排看不见的
> 黑字），但当初写下这条约束时没想清楚，而 iOS / macOS 本轮**一次都没跑过**。
> 如实记在规格 §6.5 与「未验证」里，没有当成已完成。

## 编排说明（为什么这轮不派 subagent）

按 CLAUDE.md 的档位表，「只开 plan」档在当前会话里直接做，审查集中在末尾做一次。
这轮尤其如此：改动是**一条连续的因果链**（读引擎字节码定根因 → 声明样式 → 真机量像素 →
按实测调标签条），把它拆给不同 subagent 只会让每个都从头读一遍规格与截图，而它们改的
是同一批文件。

## 交付顺序

### Task 1：先定根因，再改代码

不靠猜。逐条量：

1. `adb shell dumpsys window windows` → 应用窗口 `mFrame=[0,0][1080,2340]`（全屏），
   但内容区止于 `y=2296`。
2. 截图逐像素采样 → 顶部 `y<75` 是 `(181,181,186)`；`y≥75` 是 `(240,242,248)`。
   **比值约 0.75**——那层蒙层约 25% 黑，且加在**页面自己
   的背景**上，说明内容其实已经画到顶了。
3. 反向确认引擎行为：`javap` 读 `flutter.jar` 里的 `PlatformPlugin` ——
   `mEnabledOverlays = 0x500`（有 `LAYOUT_FULLSCREEN`，**没有** `LAYOUT_HIDE_NAVIGATION`），
   且 `setSystemChromeSystemUIOverlayStyle` 会一路把 `*ContrastEnforced` 传到 `Window`。
   这两条决定了修法。

### Task 2：样式声明（Dart）

新增 `lib/core/platform/system_bars.dart`：`enableEdgeToEdge()` +
`appSystemUiOverlayStyle(Brightness)` + `appSystemUiOverlayRegion`。
`main.dart` 第一帧之前调前者，`app.dart` 的 `MaterialApp.builder` 挂后者，
`sleep_session_page.dart` 那一层固定的 `SystemUiOverlayStyle.light` 换成同一份函数
（那个预设把导航栏写成不透明黑）。

### Task 3：真机跑一遍，按实测调几何

构建 → 安装 → 截图。顶部灰带与底部黑带如期消失，但**胶囊底边与手势条上沿都落在
`y=2312`**——`tabBarFloat` 在 Android 上算出 12dp，而手势条画在安全区（16dp）的下沿。

改 `app_shell.dart`：回收量按平台分叉（iOS 14 / Android 0），并在注释里写清
「安全区里空着的那一段两个平台不一样高」。**这是全工程唯一按平台分叉的布局常量**，
所以理由必须写在代码里。

### Task 4：测试

- 新增 `test/system_bars_test.dart`：字段断言（含把上游预设那个坑钉住的一条）+
  `MaterialApp` 里 `AnnotatedRegion` 真拿到的值（浅色 / 深色 / 系统深色而应用锁浅色）。
- `test/tab_bar_inset_test.dart`：每条用例改用 `TargetPlatformVariant` 写明平台。
  **不这么做的话 iOS 那一支永远不会被跑到**——`flutter_test` 会把
  `defaultTargetPlatform` 恒钉成 android。
- `test/bottom_fade_test.dart`：两条断言 iPhone 具体数字的用例钉到 iOS。

### Task 5：真机逐条验收

竖屏 × 浅色 / 深色、tab 页 / 推入页 / 常暗的会话页，各截一张。判据写进规格 §6.4。

### Task 6：文档同步

规格 §六（新）、总规格偏差表 #21 改写 + #51（新）、README「验证记录」、CHANGELOG。

## 审查

集中在末尾做一次，**不逐任务派 subagent**。审查者的输入只有规格 §六与真机截图，
要回答的是：「照这个规格重新实现一遍，能不能得到同一张截图」。

## 这轮不做的（已记进规格 §6.4「未验证」）

- API 29 以下设备（引擎门槛，应维持旧样子）；
- 三键导航（安全区约 48dp，胶囊会整个让开——推断，未实测）；
- 横屏。
