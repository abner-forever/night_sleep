# 底部模糊带实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在屏幕底部加一条常驻的渐变模糊带，让滚到浮动标签条附近的内容糊掉、淡出。

**Architecture:** 新增 `core/widgets/bottom_fade.dart` 的 `BottomFade`，是既有 `TopFade` 的镜像（同一套
`ShaderMask` + `BackdropFilter` + 填充渐变），但**常驻**、无动画。它只负责画一条指定高度的带子；
高度由 `AppShell` 按 `tabBarReserve(context) + 20` 推出后传入，`core/` 因此不反向依赖 `app/`。
带子在 `Stack` 里排在 `_TabBar` **之前**——`BackdropFilter` 模糊的是它之前画好的画面，排在后面会
把玻璃胶囊本身糊掉。

**Tech Stack:** Flutter / Dart，无新增依赖。

**设计依据:** [docs/superpowers/specs/2026-09-29-bottom-fade-design.md](../specs/2026-09-29-bottom-fade-design.md)

---

## Global Constraints

- 界面文案、注释、文档一律**中文**；代码标识符英文。**历史英文注释不要顺手翻译**，
  但本次改到哪一句，那一句就按事实重写成中文或英文皆可——**不许留与代码不符的注释**。
- 颜色一律从 `AppTokens.of(context)` 取（本任务用到 `tokens.bgBase` / `tokens.accent`），
  **不在 widget 里写死色值**。
- **不改 `lib/**/*.g.dart`**；本轮不碰数据库，不需要 `build_runner`。
- **不要设 `PUB_HOSTED_URL` / `FLUTTER_STORAGE_BASE_URL`**（会把 `pubspec.lock` 的 129 条
  `url: "https://pub.dev"` 改写成镜像地址，制造与依赖无关的巨型 diff）。
- **不要改 `AppDurations.standard`**（340ms，多处共用）。本轮无动画，不需要新时长常量。
- **不要引入 `flutter/cupertino.dart`**。
- 测试里**不要 `await HapticFeedback.*`**（FakeAsync 下永不完成）；**不要订阅 drift 的 `watch*` 流**；
  推入的二级页测试不要套 `Scaffold`；带 `Timer`/无限动画的组件用显式 `pump()` 而非 `pumpAndSettle`。
- 每个任务结束跑 `dart format .`、`flutter analyze`、`flutter test`，**全绿才算完成**。
- **基线：本轮开工前 `flutter test` 为 221/221 通过**（含 `test/tab_bar_inset_test.dart` 的 4 条）。
- **每个任务结束都要提交**（SDD 的审查包按 commit 区间生成，不提交就没法审），
  在 `master` 上直接提交、**不要 push**。用户要求这一整批（含 v2.7 的标签条间距）最后
  一次性收尾，推送与否由主会话决定。提交信息用中文、`type(scope): 摘要` 格式
  （仓库既有风格），正文写「为什么」而不是逐条罗列改了什么。
- 每个任务结束把改了哪些文件、跑了什么、结果如何**如实**报回，包括没跑成的部分。

---

## 文件结构

| 文件 | 职责 | 动作 |
| --- | --- | --- |
| `lib/core/widgets/bottom_fade.dart` | 底部模糊带组件本身：一条指定高度的带子，不关心自己在哪 | 新建 |
| `lib/app/app_shell.dart` | 决定带子放哪、多高、什么时候不出现（宽屏） | 改 |
| `test/bottom_fade_test.dart` | 组件本身 + 接入外壳两组用例 | 新建 |
| `docs/superpowers/specs/2026-09-28-night-sleep-design.md` | 主规格：§2.2、§8、§9 | 改 |
| `README.md` | 实现范围 + 验证记录 | 改 |
| `CHANGELOG.md` | 2.8 | 改 |

---

### Task 1: `BottomFade` 组件本身

**Files:**
- Create: `lib/core/widgets/bottom_fade.dart`
- Create: `test/bottom_fade_test.dart`

**Interfaces:**
- Consumes: 无（只用 `AppTokens`）。
- Produces: `class BottomFade extends StatelessWidget`，构造签名
  `const BottomFade({super.key, required double height})`。Task 2 依赖它。

**先读这两个文件再动手**（本任务是把它们的写法镜像过来，不要凭记忆写）：
`lib/core/widgets/top_fade.dart`（全文，107 行）、`lib/core/theme/app_tokens.dart`（确认
`bgBase` / `accent` 两个字段名与 `AppMotion` 是否存在）。

- [ ] **Step 1: 写失败的测试**

新建 `test/bottom_fade_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/core/theme/app_theme.dart';
import 'package:night_sleep/core/widgets/bottom_fade.dart';

/// 底部模糊带：`TopFade` 的镜像，但常驻。
///
/// 这里断的是**结构与色标顺序**，不是合成结果——`ShaderMask` 与
/// `BackdropFilter` 叠加以后到底谁被洗掉多少，只有真机/模拟器上看得出来。
/// 结构断言能钉住的是最容易犯的那个错：**把顶部带的代码抄下来却忘了反向**，
/// 那会让带子「上重下轻」，而且不报任何错。
void main() {
  Future<BottomFade> pumpBand(WidgetTester tester, {double height = 121}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: BottomFade(height: height),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.widget<BottomFade>(find.byType(BottomFade));
  }

  /// 带子内那条填充渐变的色标（上→下）。带子里只有一个带 `LinearGradient`
  /// 的 `DecoratedBox`；`Positioned.fill` 的空 `DecoratedBox` 不在此列。
  List<Color> fillColors(WidgetTester tester) {
    final boxes = tester.widgetList<DecoratedBox>(
      find.descendant(
        of: find.byType(BottomFade),
        matching: find.byType(DecoratedBox),
      ),
    );
    final gradient = boxes
        .map((box) => box.decoration)
        .whereType<BoxDecoration>()
        .map((decoration) => decoration.gradient)
        .whereType<LinearGradient>()
        .single;
    return gradient.colors;
  }

  testWidgets('遮罩套在 BackdropFilter 外面', (tester) async {
    await pumpBand(tester);

    // 套在里面时只淡化填充，模糊会留一条硬边（top_fade.dart 记着这个坑）。
    expect(
      find.ancestor(
        of: find.byType(BackdropFilter),
        matching: find.byType(ShaderMask),
      ),
      findsOneWidget,
    );
  });

  testWidgets('模糊半径与顶部带一致', (tester) async {
    await pumpBand(tester);

    final filter = tester
        .widget<BackdropFilter>(find.descendant(
          of: find.byType(BottomFade),
          matching: find.byType(BackdropFilter),
        ))
        .filter;
    expect(filter, equals(ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14)));
  });

  testWidgets('填充渐变上透明、下最重，最重一档是 78%', (tester) async {
    await pumpBand(tester);

    final colors = fillColors(tester);
    expect(colors.length, 4);
    expect(colors.first.a, 0, reason: '带子顶边必须完全透明，否则会切出一条横线');
    expect(colors.last.a, closeTo(0.78, 0.01));
    // 透明度单调递增：上轻下重。抄顶部带时不反向就会在这里变红。
    for (var i = 1; i < colors.length; i++) {
      expect(colors[i].a, greaterThan(colors[i - 1].a));
    }
  });

  testWidgets('遮罩方向与填充相反：上透明、下不透明', (tester) async {
    await pumpBand(tester);

    // `ShaderMask.shaderCallback` 返回的是 `Shader`，拿不到原始 `LinearGradient`，
    // 所以遮罩的色标由 `BottomFade` 公开成常量（`@visibleForTesting`）供这里断言。
    // 组件内部用的就是这两个常量，因此这条断言不是「另抄一份」。
    expect(find.byType(ShaderMask), findsOneWidget);
    expect(BottomFade.maskColors.first.a, 0);
    expect(BottomFade.maskColors.last.a, 1);
    // 非递减即可：末两档是 `#000 66% → #000 100%` 的**平段**（顶部带平台段的镜像），
    // 要求严格递增会恒假。方向由上面两个端点钉死。
    for (var i = 1; i < BottomFade.maskColors.length; i++) {
      expect(
        BottomFade.maskColors[i].a,
        greaterThanOrEqualTo(BottomFade.maskColors[i - 1].a),
      );
    }
    // 停点必须逐个精确：只对长度的话，「照抄顶部带的 0.34 / 0.68、忘了镜像成
    // 0.32 / 0.66」这种错会整条溜过去。
    expect(BottomFade.maskStops, [0.0, 0.32, 0.66, 1.0]);
  });

  testWidgets('高度由调用方决定，带子自己撑满宽度', (tester) async {
    await pumpBand(tester, height: 77);

    final rect = tester.getRect(find.byType(BottomFade));
    expect(rect.height, 77);
    expect(rect.width, tester.getRect(find.byType(Scaffold)).width);
  });

  testWidgets('整条带不拦手势', (tester) async {
    await pumpBand(tester);

    expect(
      find.descendant(
        of: find.byType(BottomFade),
        matching: find.byType(IgnorePointer),
      ),
      findsOneWidget,
    );
  });
}
```

注意：`ui.ImageFilter` 需要 `import 'dart:ui' as ui;`，写测试时补上这一行 import。

- [ ] **Step 2: 跑测试，确认它失败（文件还不存在）**

Run: `flutter test test/bottom_fade_test.dart`
Expected: 编译错误 —— `Target of URI doesn't exist: 'package:night_sleep/core/widgets/bottom_fade.dart'`

- [ ] **Step 3: 写实现**

新建 `lib/core/widgets/bottom_fade.dart`。**逐字照搬 `top_fade.dart` 的结构**（`IgnorePointer` →
`SizedBox` → `ShaderMask` → `ClipRect` → `Stack`），只改三处：高度由参数给、没有可见性动画、
渐变整体反向。

```dart
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// 屏幕底部的模糊带：把滚到浮动标签条附近的内容糊掉、淡出。
///
/// 是 `top_fade.dart` 的镜像，但**常驻**——没有 `visible` 参数，也没有淡入淡出，
/// 因此不需要动效常量。高度由调用方按标签条的实际预留量推导后传入
/// （`app_shell.dart` 里是 `tabBarReserve(context) + 20`），这里不写死：
/// 标签条的浮起量一变，带子必须跟着走，否则两者在别的机型上会脱节。
///
/// 方向与顶部带**完全相反**：遮罩与填充两重衰减都朝上（越靠近屏幕底边越实）。
/// 直接抄顶部带的参数会得到「上重下轻」的逆向观感，而且不会报任何错。
class BottomFade extends StatelessWidget {
  const BottomFade({super.key, required this.height});

  final double height;

  /// 遮罩渐变的色标（上→下）与停点。
  ///
  /// 公开只为让测试钉住**方向**：`ShaderMask.shaderCallback` 返回的是 `Shader`，
  /// 测试拿不到原始渐变。组件内部用的就是这两个常量，不是另抄的一份。
  @visibleForTesting
  static const List<Color> maskColors = [
    Colors.transparent,
    Color(0x85000000),
    Colors.black,
    Colors.black,
  ];

  @visibleForTesting
  static const List<double> maskStops = [0.0, 0.32, 0.66, 1.0];

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    return IgnorePointer(
      child: SizedBox(
        height: height,
        width: double.infinity,
        // 遮罩套在 BackdropFilter **外面**。
        //
        // `BackdropFilter` 模糊的是它子树**之外**、身后已经画好的画面，套在里面的
        // ShaderMask 只管得到填充，模糊会留一条硬边，读起来像页面上的一道接缝。
        // `mask-image: linear-gradient(transparent 0%, rgba(0,0,0,.52) 32%, #000 66%, #000 100%)`。
        child: ShaderMask(
          shaderCallback: (rect) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: maskColors,
            stops: maskStops,
          ).createShader(rect),
          blendMode: BlendMode.dstIn,
          child: ClipRect(
            child: Stack(
              children: [
                BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                  // `StackFit.loose` 下 Stack 按最大的非 position 子项定尺寸，
                  // 这里必须撑满，否则整条带会静缩到内容大小。
                  child: const SizedBox.expand(),
                ),
                // `saturate(125%)` 的近似，与顶部带同一个手法、同一个浓度：
                // `ImageFilter` 没有内置的 saturate 构造器。
                Positioned.fill(
                  child: ColoredBox(
                    color: tokens.accent.withValues(alpha: 0.04),
                  ),
                ),
                // 填充从顶部 0 升到底边 78%，是顶部带那条曲线按 0.78/0.92 缩放后的镜像。
                // 同样必须 `Positioned.fill`：无子节点的 DecoratedBox 在 loose 下会
                // 缩成 0×0，渐变整条消失。
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          tokens.bgBase.withValues(alpha: 0),
                          tokens.bgBase.withValues(alpha: 0.27),
                          tokens.bgBase.withValues(alpha: 0.61),
                          tokens.bgBase.withValues(alpha: 0.78),
                        ],
                        stops: const [0.0, 0.30, 0.62, 1.0],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: 跑测试，确认全绿**

Run: `flutter test test/bottom_fade_test.dart`
Expected: `All tests passed!`

若「遮罩方向」那条报 `BottomFade.maskColors` 未定义，说明实现里没照抄那两个常量；
它们必须是 `static const` 且被 `shaderCallback` **直接引用**——测试断言的常量与组件画出来的
必须是同一份，另抄一份就不算数（这条写进实现的注释里了）。

- [ ] **Step 5: 变异验证（必做，把结果报回来）**

对每个断言各破坏一次，确认对应用例**真的变红**，改回后复绿：

| 破坏方式 | 预期变红的用例 |
| --- | --- |
| 把 `ShaderMask` 挪到 `ClipRect` 里（套在 `BackdropFilter` 内部） | 「遮罩套在 BackdropFilter 外面」 |
| 把填充渐变四个颜色顺序整个反过来 | 「填充渐变上透明、下最重」 |
| 把遮罩渐变的颜色顺序反过来 | 「遮罩方向与填充相反」 |
| 把遮罩停点改回顶部带的 `0.34 / 0.68`（忘了镜像） | 「遮罩方向与填充相反」（停点精确断言那条） |
| 去掉 `IgnorePointer` | 「整条带不拦手势」 |

- [ ] **Step 6: 全量检查**

Run: `dart format . && flutter analyze && flutter test`

必须：`0 changed` / `No issues found` / **227 通过**（221 + 本任务 6 条）。
条数对不上就如实报回来，不要改测试去凑数。

---

### Task 2: 接入 `AppShell`

**Files:**
- Modify: `lib/app/app_shell.dart`（`_AppShellState.build` 的 `Stack`，约 143-160 行）
- Modify: `test/bottom_fade_test.dart`（追加一组「接入外壳」用例）

**Interfaces:**
- Consumes: Task 1 的 `BottomFade(height: ...)`；既有 `tabBarReserve(BuildContext)`、
  `AppTab`、`kWellLayoutBreakpoint` 同名的 `kWideLayoutBreakpoint`（定义在 `core/theme/app_tokens.dart`）。
- Produces: 无新接口。

- [ ] **Step 1: 写失败的测试**

在 `test/bottom_fade_test.dart` 末尾追加（**同一个文件**，不要新建文件）：

```dart
  // ---- 接入外壳 ----
  //
  // 与 `test/tab_bar_inset_test.dart` 同构：`Scaffold` → `SafeArea(top: false,
  // bottom: false)` → `AppShell`。底部安全区不会被 `SafeArea` 摘掉，外壳因此
  // 读得到 34px，与真机一致。
  Widget shell({required double safeBottom, required Size size}) => MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            padding: EdgeInsets.only(bottom: safeBottom),
          ),
          child: Scaffold(
            body: SafeArea(
              top: false,
              bottom: false,
              child: AppShell(
                current: AppTab.home,
                onSelect: (_) {},
                child: Builder(
                  builder: (context) => ListView(
                    padding: EdgeInsets.only(bottom: pageBottomInset(context)),
                    children: const [SizedBox(height: 2000)],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  Future<void> pumpShell(
    WidgetTester tester, {
    double safeBottom = 34,
    Size size = const Size(402, 874),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(shell(safeBottom: safeBottom, size: size));
    await tester.pumpAndSettle();
  }

  testWidgets('手机布局下贴着屏幕底边，高度 = 底部预留 + 20', (tester) async {
    await pumpShell(tester);

    final band = tester.getRect(find.byType(BottomFade));
    expect(band.bottom, tester.getRect(find.byType(AppShell)).bottom);
    // iPhone 16 Pro：预留 101（胶囊 65 + 浮起 20 + 呼吸 16）+ 20。
    expect(band.height, 121);
    // 与页面底部留白同源：留白一变，带子必须跟着变。
    final reserve = tester
        .widget<ListView>(find.byType(ListView))
        .padding!
        .resolve(TextDirection.ltr)
        .bottom;
    expect(band.height, closeTo(reserve + 20, 0.01));
  });

  testWidgets('无安全区（macOS / Web）时高度 113', (tester) async {
    await pumpShell(tester, safeBottom: 0);

    // 预留 93（65 + 12 + 16）+ 20。
    expect(tester.getRect(find.byType(BottomFade)).height, 113);
  });

  testWidgets('带子排在标签条之前，胶囊在带子之上', (tester) async {
    await pumpShell(tester);

    // `Stack` 的子项顺序就是绘制顺序（后画的在上）。带子必须**不是**最后一项，
    // 否则它会去模糊画在它之前的玻璃胶囊。
    final stack = tester.widget<Stack>(
      find
          .ancestor(of: find.byType(BottomFade), matching: find.byType(Stack))
          .first,
    );
    final bandIndex = stack.children.indexWhere(
      (child) => child is Positioned && child.child is BottomFade,
    );
    expect(bandIndex, isNonNegative, reason: '带子没有被 Positioned 包住');
    expect(
      bandIndex,
      lessThan(stack.children.length - 1),
      reason: '带子排到了最后一项——它会去模糊玻璃胶囊本身',
    );
  });

  testWidgets('宽屏（≥768px）不渲染带子', (tester) async {
    await pumpShell(tester, size: const Size(1024, 900));

    expect(find.byType(BottomFade), findsNothing);
  });

  testWidgets('带子盖住的位置仍能点到内容', (tester) async {
    var taps = 0;
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(402, 874),
            padding: EdgeInsets.only(bottom: 34),
          ),
          child: Scaffold(
            body: SafeArea(
              top: false,
              bottom: false,
              child: AppShell(
                current: AppTab.home,
                onSelect: (_) {},
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => taps++,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 屏幕底上方 8pt：在带子（高 121）里面，但在**胶囊之下**——胶囊占离底
    // 20–85pt，点在那里会被标签条接走，测的就不是这条带了。
    await tester.tapAt(const Offset(200, 874 - 8));
    expect(taps, 1);
  });
```

注意 import 需要补：`package:night_sleep/app/app_shell.dart`、
`package:night_sleep/core/widgets/bottom_fade.dart`（已有）。

- [ ] **Step 2: 跑测试，确认它失败**

Run: `flutter test test/bottom_fade_test.dart`
Expected: 前 6 条（Task 1 的）通过；新加的「接入外壳」全红，报 `Expected: exactly one matching
candidate of type BottomFade` 之类的找不到。

- [ ] **Step 3: 接入外壳**

改 `lib/app/app_shell.dart` 的 `_AppShellState.build`。**只加一个 `Positioned`，位置在
`_TabBar` 之前、`TopFade` 之后**：

```dart
                  if (!isWide)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      // 高度由标签条的实际预留量推导：预留多少，带子就盖住多少，
                      // 再多 20px 供内容化开。写死 120 会在别的机型上脱节。
                      // 排在 `_TabBar` **之前**——`BackdropFilter` 模糊的是它之前
                      // 画好的画面，排在后面会把玻璃胶囊本身糊掉。
                      child: BottomFade(height: tabBarReserve(context) + 20),
                    ),
```

并在文件头部 import 里加 `import '../core/widgets/bottom_fade.dart';`（放在
`import '../core/widgets/app_sheet.dart' show openSheetCount;` 之后，保持字母序）。

**不要**给宽屏加这条带子，**不要**做滚动联动或淡入淡出（设计已裁定常驻），
**不要**改 `top_fade.dart` 或 `_TabBar` 的任何代码。

- [ ] **Step 4: 跑测试，确认全绿**

Run: `flutter test test/bottom_fade_test.dart && flutter test test/tab_bar_inset_test.dart`
Expected: 两组全绿（11 + 4 条）。

- [ ] **Step 5: 变异验证（必做，把结果报回来）**

| 破坏方式 | 预期变红的用例 |
| --- | --- |
| 把 `BottomFade` 的 `Positioned` 挪到 `_TabBar` **之后** | 「带子排在标签条之前」 |
| 高度改成写死的 `120` | 「高度 = 底部预留 + 20」（`closeTo(reserve + 20)` 那条） |
| 去掉 `if (!isWide)` 守卫 | 「宽屏不渲染带子」 |
| 给 `BottomFade` 外面套一层 `AbsorbPointer` | 「带子盖住的位置仍能点到内容」 |

四组都要真的试出来。**哪一条没变红就如实报回来**——那说明该用例名不副实，
由主会话决定改成什么断言，不要改实现去迁就测试。

- [ ] **Step 6: 全量检查**

Run: `dart format . && flutter analyze && flutter test`

必须：`0 changed` / `No issues found` / **232 通过**（227 + 本任务 5 条）。

---

### Task 3: 文档同步

**Files:**
- Modify: `docs/superpowers/specs/2026-09-28-night-sleep-design.md`（§2.2、§8、§9）
- Modify: `README.md`（当前实现范围、验证记录）
- Modify: `CHANGELOG.md`

- [ ] **Step 1: 主规格 §2.2**

在「标签条尺寸」那条 bullet 之后、`- **页面的横向、**顶部**与底部留白都由页面自己的滚动视图提供**`
那一行**之前**插入：

```markdown
- **底部模糊带**（v2.8，原型无此元素）：屏幕底部常驻一条渐变带，把滚到浮动标签条附近的内容
  模糊并淡出。高度由标签条的预留量推导——`BottomFade(height: tabBarReserve(context) + 20)`，
  iPhone 16 Pro 上 121px（胶囊顶边之上因此有 36px 的过渡段），无安全区处 113px。
  `BackdropFilter` 用与顶部带相同的 `blur(14)`，填充是 `bgBase` 从顶边 0 升到底边 **0.78**
  （比顶部带的 0.92 弱一档）。**方向与顶部带完全相反**：遮罩上透明下黑、填充上 0 下重，
  两重衰减都朝上；照抄顶部带的参数会画出「上重下轻」的逆向带且不报错。
  它在 `Stack` 里排在 `_TabBar` **之前**——`BackdropFilter` 模糊的是它之前画好的画面，
  排在后面会把玻璃胶囊本身糊掉。宽屏（≥768px）不渲染，与 `.ios-top-fade` 同规则；
  底部弹层打开时**不收起**（蒙层本来就盖住整屏）。
```

- [ ] **Step 2: 主规格 §8 偏差表**

在 #21 那一行**之后**追加（编号接续，不要插到前面去）：

```markdown
| 22 | 原型底部没有任何遮挡过渡，内容滚到标签条下方时完全清晰 | 新增一条常驻的底部模糊带（`core/widgets/bottom_fade.dart`），高度 = 标签条预留量 + 20、`blur(14)`、`bgBase` 0→78% | 原型的标签条是**悬空**在内容之上的：内容从它下面和两侧穿过去，没有任何「这里到底了」的提示，实机上读起来像内容被硬切断（用户在实机使用后提出）。原型源文件未入库，本条为**新增**而非「原型有而未实现」。**它同时是唯一一处无法靠断言判断的取舍**：带子画在胶囊之下，胶囊的 backdrop 因此会看到被洗过一遍的内容（有效 alpha 从胶囊顶边约 0.13 升到底边约 0.71），观感需人工核对。回归方法：`test/bottom_fade_test.dart`——把遮罩方向反过来、把带子排到 `_TabBar` 之后、或把高度写死，对应用例必须变红（已变异验证）。 |
```

- [ ] **Step 3: 主规格 §9 测试矩阵**

在「标签条浮起量」那一行**之后**追加：

```markdown
| Widget 测试 | 底部模糊带：遮罩套在 `BackdropFilter` 外面（结构断言，防硬边）、模糊半径 14、填充上透明下 78% 且单调递增、遮罩方向相反、高度 = 底部预留 + 20（含无安全区的 113）、宽屏不渲染、整条带不拦手势 | ✅ `test/bottom_fade_test.dart`（含变异验证：遮罩方向反转、带子排到标签条之后、高度写死，均变红） |
```

- [ ] **Step 4: README**

「当前实现范围」里，在 v2.7 的「标签条浮起量」那条 bullet **之后**插入：

```markdown
- **底部模糊带**（v2.8，原型无此元素）：屏幕底部常驻一条渐变模糊带（`core/widgets/bottom_fade.dart`），
  让滚到浮动标签条附近的内容糊掉、淡出。高度由标签条预留量推导（`tabBarReserve + 20`，iPhone 上 121pt），
  填充 0→78%、`blur(14)`，方向与顶部渐变带相反。宽屏不渲染；弹层打开时照常显示。
```

「验证记录」按**实际结果**改（不要照抄这句）：`flutter test` 的条数用 `flutter test` 输出的真实数字，
格式与既有条目一致（本轮从 221 起，本计划预计新增 11 条），并在「界面巡检」小节如实写明
**本轮是否跑过模拟器截图核对**——如果没跑，就照实写「只有几何/结构断言」。

- [ ] **Step 5: CHANGELOG**

在 `## 2.7（2026-09-29）` 之前插入：

```markdown
## 2.8（2026-09-29）

用户实机要求：**底部也加一条轻微的渐变模糊带**，让滚到标签条附近的内容糊掉。原型没有这个元素
（源文件未入库，无法核实；用户确认原型没有），因此计入偏差表 #22。

新增 `core/widgets/bottom_fade.dart` 的 `BottomFade`，是 `top_fade.dart` 的镜像，但**常驻**
（没有 `visible`，没有淡入淡出）。高度不写死：由 `AppShell` 按 `tabBarReserve(context) + 20` 推出
后传入（iPhone 16 Pro 上 121pt），标签条的浮起量再变时带子自动跟走。填充是 `bgBase` 从顶边 0
升到底边 78%，`blur(14)` 与顶部带同半径。

三处容易做反的地方在这次都被断言钉住了：**渐变整体要反向**（照抄顶部带会画出「上重下轻」的逆向带
且不报任何错）、**带子在 `Stack` 里排在 `_TabBar` 之前**（`BackdropFilter` 模糊的是它之前画好的
画面，排在后面会把玻璃胶囊自己糊掉）、**遮罩必须套在 `BackdropFilter` 外面**（套在里面只淡化填充、
模糊留一条硬边，顶部带犯过这个错）。回归方法：`test/bottom_fade_test.dart`，三种破坏各让对应用例
变红（已变异验证）。

**已知取舍**：带子画在胶囊之下，胶囊的 backdrop 会看到被洗过一遍的内容（有效 alpha 从胶囊顶边约
0.13 升到底边约 0.71），胶囊下半部因此比过去更「实」。这是本轮唯一靠断言判断不了的一项，需人工核对。
```

- [ ] **Step 6: 检查**

Run: `dart format . && flutter analyze && flutter test`

必须全绿，且条数与 Task 2 结束时一致（本轮不改代码）。另外**逐条核对**上面四处文档改动里的每个数字
是否与实现一致：`+ 20`、121 / 113、`blur(14)`、0.78、0.27 / 0.61、遮罩停点 0.32 / 0.66、
胶囊顶边 0.13 / 底边 0.71。**任何一个对不上就以代码为准改文档，并如实报回来。**

---

## 自检记录

**规格覆盖**：设计文档「组件」→任务 1；「放置与 z 序」「几何」「边界情况」→任务 2；
「渐变方向」→任务 1（实现）+ 任务 2（接入）；「已知副作用」→任务 3 的文档条目；
「规格改动清单」→任务 3；「测试矩阵」→任务 1 / 2 的 11 条用例。**无遗漏。**

**已知的未核实项**（**实现者必须先跑通再写代码，不要照抄**）：

1. **镜像方向的合成结果没有任何断言能证明。** 结构断言与常量断言都只能证明「色标顺序是对的」，
   证明不了画面就是「下重上轻」。设计文档已把「跑一次模拟器截图核对」列为待核实事项，
   **不属本计划范围**（本计划不碰模拟器）。
2. **遮罩的色标只能靠组件公开的常量来测，这是本计划里最弱的一环。**
   `ShaderMask.shaderCallback` 返回的是 `Shader`，测试拿不到它背后的 `LinearGradient`，
   所以让 `BottomFade` 把色标与停点公开成 `static const`、组件内部直接引用它们
   （**初版计划里写成 `as LinearGradient` 强转，那是错的**，`createShader` 的返回值不是
   `Gradient`，会在运行期抛类型错误）。更硬的做法是把带子渲染成图再采样像素，
   本轮不做（`toImage` 在 `testWidgets` 的 FakeAsync 下需要 `runAsync`，风险大于收益）。
3. **胶囊 backdrop 被洗过之后的观感**（见「已知副作用」），只能人工核对。

**类型一致性**：`BottomFade({required double height})` 在任务 1 定义、任务 2 调用，
两处命名与参数一致；`tabBarReserve` / `pageBottomInset` / `AppTab` 均为既有接口，未改名。
