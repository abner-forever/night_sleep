---
name: flutter-pitfalls
description: 当在本项目中编写或修改 Flutter widget、布局、主题、弹层，或编写 / 调试 widget 测试时使用——尤其是碰到阴影 boxShadow、模糊 BackdropFilter、ClipRRect 裁剪、Stack 尺寸、内容留白、Material 祖先，或 widget 测试挂死 / 超时 / 报 pending timer 的时候。
---

# 本项目的 Flutter 陷阱落点

「夜深」在 Flutter 与 CSS 的语义差异上反复栽过跟头（病历见 `CHANGELOG.md` v2.2–v2.4）。
下面每条都是**通用 Flutter 语义** + **本项目踩过的具体落点**。写布局或测试前扫一眼。

## 渲染与布局

- **`boxShadow` 写在会被自己 `ClipRRect` 裁掉的那个盒子上 → 静默丢弃。**
  阴影画在盒子边界**之外**，那块区域正好落在裁剪区外，于是画完被裁。阴影必须放在 clip
  **外面**（`glass_surface.dart`、`app_shell.dart` 的标签条）。症状：所有卡片看起来是平的。

- **`BackdropFilter` 模糊的是它子树**之外**背后的画面**，模糊在合成阶段由自带的 layer 输出。
  想让模糊淡出，`ShaderMask` 必须套在 `BackdropFilter` **外面**；套在里面只遮到了 child 内容，
  模糊 layer 本身没被遮，边缘留一条硬边（症状正是「填充淡了、模糊还在」）。落点：`top_fade.dart`。

- **`Stack`（`StackFit.loose`）按最大的**非 position**子项定尺寸**，`Positioned` 子项完全不参与
  尺寸计算，会静缩到内容大小导致溢出。落点：`GlassSurface` 的 `expandWidth`、
  `DurBar` 的 `StackFit.expand` + `Align(centerLeft)`。

- **内容留白属于滚动视图**里面**，不是外面**（`pageGutter` / `pageBottomInset`）。放外面时
  视口被压缩，留白区变成一条盖住内容的不透明带。

- **`Positioned(top: 0)` 相对的是内边距盒，不是内容盒**——主按钮的高光因此落在文字中间成了
  一道杂线。落点：`app_basics.dart` 的 `PrimaryAction`。

- **底部留白必须由标签条的**实际高度**推导**（`tabBarReserve`）。写死的值一旦偏小，
  最后一行就永远压在玻璃下面。

- **没有 `Material` 祖先的 `Text` 会落到 Flutter 的错误样式：黄色双下划线。**
  `showGeneralDialog` 不像 `showDialog` 那样包 `Material`，`Subpage` 和 `AppSheet` 都已显式补上。
  看到黄线先查材质祖先，别去翻主题。

## 测试

`integration_test/` 不参与 `flutter test`（要 `flutter drive`，见 README「界面截图巡检」）。

- **`testWidgets` 跑在 FakeAsync 里，平台通道的 Future 永不完成**——
  `await HapticFeedback.mediumImpact()` 会挂死，症状是保存按钮卡在「保存中…」。
  用 `unawaited(...)`，或改用普通 `test()` 函数体（`tool/generate_app_icons.dart` 里的
  `vg.loadPicture` 同理）。现成测试只断言数据库状态、不断言 UI 状态时抓不到这类问题。

- **同一个假时钟也会吃掉 `dart:io`**：`Directory.createTemp` / `File.writeAsBytes` /
  `File.delete` 这些**真实文件 I/O** 的 Future 在 `testWidgets` 里同样永不完成。
  2026-10-14 实测：一条用例在测试体里直接建临时目录 + 写文件，**不报错、直接挂满 10 分钟**
  才吐一行 `TimeoutException`（默认单测超时），看起来像"跑得慢"。**判据是进程 CPU 而不是
  等待时长**：`flutter_tester` 活着但 CPU 几乎不动，就是挂了。
  **改法**：UI 层别碰真文件——继承 `ClipFileStore` 覆写掉用到的那两个方法、只记「谁被删了」
  （`recording_settings_test.dart` 的 `_FakeClipStore` 是现成样板）；真要验文件删没删，
  用普通 `test()`（`test/clip_pruning_test.dart`），那里没有假时钟。
  跑单文件时可以临时加 `--timeout 60s`，免得每次白等十分钟。

- **别在 widget 测试里订阅 drift 的 `watch*` 流**：它们靠定时器驱动，FakeAsync 的假时钟不推进，
  拆解时会留下 pending timer。用 provider override 喂数据，写路径直接断言数据库。

- **`pumpPage` vs `pumpRoute` 的区别是关键**（`test/pages_widget_test.dart`）。早期测试给推入的
  二级页也套了 `Scaffold(body:)`，等于把背景和 `Material` 白送给它，于是测试全绿而真机是
  黑底 + 黄色下划线。`pumpRoute` 不套 Scaffold；`expectProperlyRendered` 断言文字的
  `DefaultTextStyle.decoration` 不是下划线，并存在 `Material` 祖先。

- 测试里带 `Timer`/无限动画的组件（波形指示器）会让 `pumpAndSettle` 超时 → 改用显式 `pump()`。

- 手势阈值：约 18px 以下会被判定为点击，测下拉要拖够距离；sheet 的阈值是速度 > 700 或
  位移 > 面板高度 28%。

- **schema 迁移测试要用裸 DDL 把旧版本「冻成文本」**（`test/schema_migration_test.dart`），
  不要用 Dart 表类建夹具：表类会随 `app_database.dart` 一起演进，夹具会悄悄不再代表旧版本，
  用例就在迁移代码一行没跑的情况下空跑通过。夹具先写出旧版本的真实库文件、再打开当前 schema
  触发 `onUpgrade`，并配两重防空跑自检——夹具必须停在旧 `user_version`，且夹具的旧表 DDL 必须
  **不含**本次新加的外键（否则「约束从无到有」测不出来）。新增/修改迁移条件时，先做变异验证
  （去掉条件看用例是否变红），确认新用例不是空跑。
