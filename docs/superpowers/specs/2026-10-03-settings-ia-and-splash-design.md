# 设置页信息架构重排与开屏页设计（2026-10-03）

> 日期：2026-10-03
> 状态：已实现（v3.5，2026-10-03）
> 范围：设置根页改成三段导航式列表、新增「外观」与「睡眠设置」两个二级页、新增冷启动开屏页
> 设计基准：[夜深项目规格说明书](2026-09-28-night-sleep-design.md)。本文新增偏差 #41–#44，
> 并改写其 §2.4「页面与组件」里的设置一行、§9 的若干回归行。
> 原型：[Figma Make：睡眠记录 APP 设计](https://www.figma.com/make/hKbqp1qjtcNQmmiDtVvXpk/%E7%9D%A1%E7%9C%A0%E8%AE%B0%E5%BD%95APP%E8%AE%BE%E8%AE%A1)
> （`SettingsView` = `App.tsx:1508-1760`、`SplashScreen` = `1785-1822`、`Onboarding` = `1829-1851`）

## 来源与现状

使用方给出更新后的原型，指明三处变化并要求实现：

1. **设置页排版重排** —— 从「六七个大区块平铺」改成三段导航式列表。
2. **外观收进二级页**，根页只留一行「外观」。
3. **睡眠数据（目标 / 提醒 / 声音检测）收进二级页**，根页只留一行「睡眠设置」。
4. **新增开屏页**。

### 一条改变了判断的事实：令牌没有变

原型 `index.css` 是**分层覆盖**的，早期那版「全站换成扁平原生风」（底色 `#f4f5f8`、
`.glass` 不再模糊/描边/投影、主按钮改纯色）**在最终生效层里又被推翻了**：文件末尾的
`.ios-app .glass` / `.ios-list-group` / `.primary-action` / `.ios-navigation-back` 都还原成
玻璃材质与 `#0A84FF → #5856D6` 渐变，`:root` 的最终值是 `--bg-base: #f2f2f7` / `#000000`、
`--ios-material: rgba(255,255,255,.66)` / `rgba(28,28,30,.72)`。

**这些值与 `lib/core/theme/app_tokens.dart` 的 `AppTokens` 逐值一致**（规格 §2.1 那张表就是从
这一层抄的）。所以本轮**一个字节的新配色都不引入**，视觉全部走既有令牌与组件；主规格偏差
#32 里「新原型最终生效层把全站换成了扁平原生风」那句前提**在更新后的原型上已不成立**，
本轮据实订正（#32 关于会话页用页面局部令牌的结论本身不变）。

## 已裁定的决策（使用方已确认）

| # | 议题 | 裁定 | 理由 |
| --- | --- | --- | --- |
| 1 | 开屏停留多久 | **约 1.6 秒**（原型是 3.2 秒） | 原型那 3.2 秒是网页首屏加载的遮盖；原生应用在它之前已有系统启动图，照抄等于每次冷启动白等 3 秒。压缩办法是总时长对半砍，**各元素的出场时刻仍照原型的百分比**，节奏一致、只是快一倍 |
| 2 | 原型根页没有、但必须保留的入口放哪 | 根页**新增「数据与隐私」分组**（睡眠数据导出、删除全部本地数据、演示数据）；**罗盘并入「常用」** | 导出（偏差 #18）与「删除全部本地数据」（规格 §7）是硬要求，罗盘是本实现既有能力。新增一个分组比把它们塞进「数据与智能」更贴合它们各自的语义 |
| 3 | 控件形态跟到哪一步 | **照原型换**：外观用行内下拉菜单，睡眠目标用滑块（5–12h，step 0.5）+ 7/8/9 快捷按钮 | 这两处正是「排版更新」的一部分；保留旧的 ± 步进器会让二级页看上去还是旧版 |

## 实现结构

| 区域 | 实现 | 说明 |
| --- | --- | --- |
| 设置根页 | `features/settings/presentation/settings_page.dart` | 四组：常用 / 数据与智能 / 数据与隐私 / 关于。每行是「图标底板 + 两行文案 + 右侧箭头」的导航行（私有 `_NavRow`） |
| 外观二级页 | `settings/presentation/appearance_settings_page.dart`，路由 `/settings/appearance` | 一行「显示模式」+ 行内下拉 + 页脚；写 `AppSettings.themeMode`，取值口径 `system` / `light` / `dark` 不变 |
| 睡眠设置二级页 | `settings/presentation/sleep_settings_page.dart`，路由 `/settings/sleep` | 每晚睡眠目标卡（月亮徽章 + 大号数值 + 滑块 + 快捷按钮）、提醒（含权限被拒行）、声音检测 |
| 睡眠目标滑块 | `settings/presentation/widgets/goal_slider.dart` | **自绘**（`GestureDetector` + `CustomPaint` + `Semantics`） |
| 行内下拉 | `core/widgets/app_menu_field.dart`（`AppMenuField`） | 由洞察配置页原来的私有 `_MenuField` 提升而来，新增「行内收缩」一支；菜单仍由 `PopupMenuButton` 渲染到应用 overlay（卡片内会被 `GlassSurface` 的 `ClipRRect` 裁掉） |
| 页脚小字 | `settings/presentation/widgets/settings_footnote.dart` | 原型 `settings-footnote`，左右各 12px 与组内文字列对齐 |
| 开屏页 | `features/onboarding/presentation/splash_screen.dart` | 挂在 `app/app.dart` 的 `AppScaffold` `Stack` **最上层** |
| 原生启动底色 | `ios/Runner/Base.lproj/LaunchScreen.storyboard`、`web/manifest.json` | 从白 / `#0175C2` 改成开屏底色 `#07102D`，否则冷启动会先闪一下亮色 |

### 开屏页的几处实现口径

- **只有一个有限时长的 `AnimationController`（1.6 秒），没有 `Timer`、没有 `repeat()`。**
  原型的星点闪烁 / 光晕脉动 / 轨道环自转都是 `infinite`，照抄会让 `pumpAndSettle()` 永不
  收敛（`sleep_moon_mark.dart` 的 `_sync()` 注释记的就是这个坑），挂真外壳的用例还会在
  结束时报 pending timer。这里一律改成在这条时间轴上能跑完的有限形式。
- **收起条件是「时间轴播完」且「`settings` 已经读到第一帧」。** 只看计时器的话，
  `settingsProvider` 这条异步流若还没吐出第一帧，外壳会先露出来、引导页随后再盖上去——
  用户看到的是「闪一下主界面再跳出引导」。判据用 `AsyncValue.isLoading` 而不是
  `valueOrNull != null`：读取**失败**时也算「有结论了」，否则库里一出错开屏就永远收不起来。
- **`_splashFinished` 是 `AppScaffold` 的 State 字段，不是 provider。** `AppScaffold` 是 `/`
  路由的 builder，push 子页时它留在 Navigator 里、State 被复用，所以来回跳转不会让开屏重播；
  放进 provider 一旦被 invalidate 就会重播。
- 两条声波（`splash-wave-one` / `splash-wave-two`）由 `CustomPainter` 按 `PathMetric.extractPath`
  逐段画出来，对应原型的 `stroke-dashoffset` 描线；logo 本体是内联 SVG 字符串
  （本项目运行时从不读资源包，`pubspec.yaml` 没有 `assets:` 段）。

## 与原型的有意偏差（主规格 §8 的 #41–#44）

| # | 原型行为 | 本实现 | 理由 |
| --- | --- | --- | --- |
| 41 | 开屏页与引导页的 `z-index` **同为 200**，而引导页在 DOM 里更靠后——首次启动时引导页把开屏**整个盖住**，那屏开屏等于没播 | **先开屏、后引导**：开屏播完才渲染引导页 | 原型的层叠疏漏，显然的意图是先给品牌、再给引导。回归方法：`test/splash_screen_test.dart` 的「开屏排在引导页之前」——把开屏排到引导页前面（`Stack` 里更早）必红 |
| 42 | 开屏 3.2 秒，且整屏在开头 8% 从透明淡入 | **1.6 秒**；整屏从第一帧就是不透明的，只在最后 12% 淡出 | 时长理由见上表决策 1。淡入那一段是给「往已渲染好的网页上叠一层」用的；原生冷启动时应用外壳还没出来，照抄会变成「先闪一下浅色界面再变深」，所以只保留收尾的淡出。回归方法：`test/splash_screen_test.dart` 逐条断言播完回调与收起时机 |
| 43 | 设置根页只有五条（外观 / 睡眠设置 / 睡眠数据导入 / 睡眠洞察 / 关于） | 另保留四条：**睡眠数据导出**（偏差 #18）、**删除全部本地数据**（规格 §7）、**演示数据**（调试构建）、**罗盘**（本实现既有），并为此新增「数据与隐私」分组 | 原型是纯前端演示，数据不落地，所以没有导出与删除；我们有真实库，这两条是硬要求。罗盘并入「常用」。回归方法：`test/pages_widget_test.dart` 的「根页只剩三段导航行」逐条点名这四行 |
| 44 | 声音检测的副标题写「检测打鼾、梦话并生成洞察」 | 维持「**尚未接入录音，开关只保存偏好**」 | 与原偏差 #7 / #31 同源：录音**仍未接入**，照抄那句话等于让应用当场宣称一个它没有的能力。回归方法：`test/pages_widget_test.dart` 的「睡眠设置页把提醒与声音检测都收在一起，并保留两条红线」——把它换回原型文案必红（已变异验证） |

## 测试与验收

| 类型 | 重点 | 状态 |
| --- | --- | --- |
| Widget | 开屏：品牌文案在位、播完回调**恰好一次**、开启「减弱动态效果」时尽快播完且不排帧、`AppScaffold` 里开屏先于引导页、设置未读到第一帧时不收起 | ✅ `test/splash_screen_test.dart`（5 条） |
| Widget | 根页只剩三段导航行 + 四条保留入口；外观与睡眠目标的控件**不在**根页；版本号仍取 `PackageInfo` | ✅ `test/pages_widget_test.dart`（「设置页」组） |
| Widget | 外观页：行内下拉切换写回 `themeMode`；页脚与副标题逐字在位；**箭头贴住触发器的右端**（行内版式靠 `spaceBetween`，不是 `Expanded`）；`expectProperlyRendered`（推入页自带 `Material` 祖先） | ✅ `test/pages_widget_test.dart`（「设置二级页」组；含变异验证：箭头改回左对齐报 21.4 ≠ 12） |
| Widget | 睡眠目标：快捷按钮写回 540；滑块在任意位置落库的分钟数都是 30 的整数倍（吸附 0.5h）、两端夹在 5 / 12 小时；`Semantics` 的增大 / 减小一步是 0.5 小时；卡片内数值水平居中 | ✅ 同上（含变异验证：去掉吸附必红） |
| Widget | 睡眠设置页把提醒 / 声音检测收在一起，**两条红线逐字在位** | ✅ 同上（含变异验证：换成原型文案必红） |
| 数据 | 提醒的读写与调度行为**一字未改**（权限被拒回弹、开启时连同默认时刻落库、全量重排、权限被拒行、删除全部数据的收尾） | ✅ `test/reminder_settings_test.dart`（9 条，挂载点改到新页） |
| 集成 | 巡检脚本按新文案走「外观 / 睡眠设置 / 睡眠数据导入 / 睡眠洞察 / 演示数据」五个二级页 | ✅ `integration_test/app_screens_test.dart`（`flutter drive`，本轮未实跑） |

**验证记录（2026-10-03）：** `dart format .` 无改动；`flutter analyze` **No issues found**；
`flutter test` **424/424 通过**。

**目视核对（macOS）**：**开屏页通过**——深蓝渐变、两圈轨道环、星点、圆角图标（moon + 两道
声波弧的描线都在）、`夜深` 与 `听见夜晚，看见睡眠`、底部进度条逐项在位，与原型一致
（证据图 `screenshots/v3.5-splash.png`、`v3.5-splash-early.png`）。
**设置根页与两个新二级页未核对**：巡检跑到一半被系统的「`night_sleep` 想访问『文稿』文件夹」
授权框盖住窗口，本机没有辅助访问权限、点不掉系统对话框。行内下拉在窄屏 / iPad 横屏下的换行、
自绘滑块的拖拽手感，仍然只有几何与结构断言。

## 已知项与未做

1. **开屏与深链**：开屏挂在 `AppScaffold` 的 `Stack` 里，任何 push 在其之上的路由都会盖住它。
   当前应用没有冷启动深链，所以只在「冷启动停在 `/`」时生效；将来若加路由恢复或 deep link，
   要改挂 `MaterialApp.builder`。
2. **`settingsProvider` 永不吐值**：那种情况下开屏不会收起（没有兜底 Timer，有 Timer 就会
   给每个挂真外壳的测试留下 pending timer）。本地 Drift 流要么吐值要么报错，两条都算「有结论」。
3. **`docs/architecture.md` 的 schema 版本号**仍是 v3，实际早已到 v5——本轮未动。
