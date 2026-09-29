import 'dart:ui' as ui;

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
