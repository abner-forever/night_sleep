import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/app/app_shell.dart';
import 'package:night_sleep/core/theme/app_theme.dart';
import 'package:night_sleep/core/widgets/app_sheet.dart';
import 'package:night_sleep/core/widgets/bottom_fade.dart';
import 'package:night_sleep/core/widgets/top_fade.dart';

/// 底部模糊带：`TopFade` 的镜像，但常驻。
///
/// 这里断的是**结构与色标顺序**，不是合成结果——`ShaderMask` 与
/// `BackdropFilter` 叠加以后到底谁被洗掉多少，只有真机/模拟器上看得出来。
/// 结构断言能钉住的是最容易犯的那个错：**把顶部带的代码抄下来却忘了反向**，
/// 那会让带子「上重下轻」，而且不报任何错。
void main() {
  Future<BottomFade> pumpBand(WidgetTester tester,
      {double height = 121}) async {
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

  /// 带子内那条填充渐变（上→下），**连停点一起**返回。带子里只有一个带
  /// `LinearGradient` 的 `DecoratedBox`；`Positioned.fill` 的空 `DecoratedBox`
  /// 不在此列。
  ///
  /// 返回整个 `LinearGradient` 而不是 `colors`：只断颜色的话，「照抄顶部带的
  /// 0.38 / 0.70、忘了镜像成 0.30 / 0.62」这种错会保持全绿——遮罩侧正为同一个
  /// 失败模式收紧成了精确断言。
  LinearGradient fillGradient(WidgetTester tester) {
    final boxes = tester.widgetList<DecoratedBox>(
      find.descendant(
        of: find.byType(BottomFade),
        matching: find.byType(DecoratedBox),
      ),
    );
    return boxes
        .map((box) => box.decoration)
        .whereType<BoxDecoration>()
        .map((decoration) => decoration.gradient)
        .whereType<LinearGradient>()
        .single;
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

    final gradient = fillGradient(tester);
    final colors = gradient.colors;
    expect(colors.length, 4);
    expect(colors.first.a, 0, reason: '带子顶边必须完全透明，否则会切出一条横线');
    expect(colors.last.a, closeTo(0.78, 0.01));
    // 透明度单调递增：上轻下重。抄顶部带时不反向就会在这里变红。
    for (var i = 1; i < colors.length; i++) {
      expect(colors[i].a, greaterThan(colors[i - 1].a));
    }
    // 停点同样逐个精确：底部带是顶部带的**镜像**，只断颜色的话，
    // 「照抄顶部带的 0.38 / 0.70、忘了镜像成 0.30 / 0.62」会整条溜过去。
    expect(gradient.stops, [0.0, 0.30, 0.62, 1.0]);
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

  testWidgets('新版手机底栏不再叠加底部模糊带', (tester) async {
    await pumpShell(tester);
    expect(find.byType(BottomFade), findsNothing);
    expect(find.byKey(const ValueKey('app-bottom-navigation')), findsOneWidget);
  });

  testWidgets('宽屏使用侧栏', (tester) async {
    await pumpShell(tester, size: const Size(1024, 900));
    expect(find.byType(BottomFade), findsNothing);
    expect(find.byKey(const ValueKey('app-bottom-navigation')), findsNothing);
  });

  testWidgets('弹层打开时顶部渐隐与底栏都按设计收起', (tester) async {
    await pumpShell(tester);

    // 先把页面滚起来，让顶部带处于「该显示」的状态。否则拿 `TopFade` 当对照组时
    // 它本来就是收起的，证明不了 `openSheetCount` 真的接进了外壳。
    await tester.drag(find.byType(ListView), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(tester.widget<TopFade>(find.byType(TopFade)).visible, isTrue);

    // 设计稿的 `.ios-app:has(.sheet-overlay…) .ios-tab-bar` 会在弹层
    // 打开时隐藏底栏；这里同时钉住顶部渐隐和底栏两块。
    addTearDown(() => openSheetCount.value = 0);
    openSheetCount.value = 1;
    await tester.pumpAndSettle();

    expect(
      tester.widget<TopFade>(find.byType(TopFade)).visible,
      isFalse,
      reason: '对照组：顶部带确实响应了 openSheetCount',
    );
    expect(
      find.byKey(const ValueKey('app-bottom-navigation')),
      findsNothing,
    );
  });

  // 同样按 iPhone 的几何来量（安全区 34pt、胶囊离底 20pt），所以钉住 iOS。
  testWidgets(
    '底栏上方的内容仍可点击',
    (tester) async {
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
      await tester.tapAt(const Offset(200, 874 - 120));
      expect(taps, 1);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}
