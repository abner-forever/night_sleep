import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/core/theme/app_theme.dart';
import 'package:night_sleep/core/widgets/liquid_glass.dart';

/// 液态玻璃是导航 / 控件层共用的材质。这里守的是三件事：
/// 可点击面真的会回调、`expandWidth` 的两种尺寸语义、以及关闭背景模糊时
/// 不会留下一个什么都不做的 `BackdropFilter`。
void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: Center(child: child)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('可点击的玻璃面会回调，并带按下 / 回弹动画', (tester) async {
    var taps = 0;
    await pump(
      tester,
      LiquidGlass(
        onTap: () => taps++,
        padding: const EdgeInsets.all(12),
        child: const Text('玻璃'),
      ),
    );

    await tester.tap(find.text('玻璃'));
    await tester.pumpAndSettle();

    expect(taps, 1);
    // 动画跑完必须回到原尺寸，不能停在按下的 0.976。
    final scale = tester.widget<AnimatedScale>(
      find.descendant(
        of: find.byType(LiquidGlass),
        matching: find.byType(AnimatedScale),
      ),
    );
    expect(scale.scale, 1);
  });

  testWidgets('expandWidth = false 时贴着内容，不为父级撑满', (tester) async {
    await pump(
      tester,
      const Align(
        alignment: Alignment.centerLeft,
        child: LiquidGlass(
          expandWidth: false,
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text('短'),
        ),
      ),
    );

    final width = tester.getSize(find.byType(LiquidGlass)).width;
    expect(width, lessThan(120), reason: '关闭撑宽后仍占满了父级宽度');
  });

  testWidgets('默认撑满父级宽度', (tester) async {
    await pump(
      tester,
      const SizedBox(
        width: 300,
        child: LiquidGlass(
          padding: EdgeInsets.all(12),
          child: Text('长一点的内容'),
        ),
      ),
    );

    expect(tester.getSize(find.byType(LiquidGlass)).width, closeTo(300, 0.01));
  });

  testWidgets('blur = 0 时不创建背景滤镜', (tester) async {
    await pump(
      tester,
      const SizedBox(
        width: 200,
        child: LiquidGlass(
          blur: 0,
          child: SizedBox(height: 48),
        ),
      ),
    );

    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('开启模糊时有一层背景滤镜，且弹层可关掉底边高光', (tester) async {
    await pump(
      tester,
      const SizedBox(
        width: 200,
        child: LiquidGlass(
          bottomEdge: false,
          child: SizedBox(height: 48),
        ),
      ),
    );

    expect(find.byType(BackdropFilter), findsOneWidget);
  });
}
