import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/app/app_shell.dart';
import 'package:night_sleep/core/theme/app_theme.dart';

/// 标签条的浮起量与页面底部留白是一对：浮起量决定玻璃胶囊下边缘离屏幕底边
/// 多远，页面底部留白要能盖住胶囊的整条高度。两者共用 `tabBarFloat`
/// （`app_shell.dart`），任一侧单独改动都会立刻表现为「最后一行压进玻璃」
/// 或「玻璃上方空出一条」。
///
/// 这里断言的是**渲染出来的几何**，不是那两个函数的返回值：`SafeArea`
/// / `Scaffold` 会不会把底部安全区摘掉、`Stack` 会不会静缩，都只有真渲染
/// 一次才看得出来。
void main() {
  const screen = Size(402, 874);

  /// 与 `AppScaffold` 同构：`Scaffold` → `SafeArea(top: false, bottom: false)`
  /// → `AppShell`。`SafeArea` 的 `bottom: false` 不会摘掉底部安全区，
  /// 外壳因此仍读得到它 —— 这正是真机上标签条拿到 34px 的路径。
  Widget harness(double safeBottom) => MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(size: screen)
              .copyWith(padding: EdgeInsets.only(bottom: safeBottom)),
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

  Future<void> pump(WidgetTester tester, double safeBottom) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness(safeBottom));
    await tester.pumpAndSettle();
  }

  /// 玻璃胶囊的矩形。取标签文字最近的 `ClipRRect` 祖先：胶囊自身就在
  /// `ClipRRect` 里，而它与文字之间不再夹别的 `ClipRRect`。
  Rect pill(WidgetTester tester) => tester.getRect(
        find
            .ancestor(of: find.text('首页'), matching: find.byType(ClipRRect))
            .first,
      );

  double shellBottom(WidgetTester tester) =>
      tester.getRect(find.byType(AppShell)).bottom;

  double reserve(WidgetTester tester) => tester
      .widget<ListView>(find.byType(ListView))
      .padding!
      .resolve(TextDirection.ltr)
      .bottom;

  testWidgets('带 home indicator 的设备：胶囊底边离屏幕底 20pt', (tester) async {
    await pump(tester, 34);

    final gap = shellBottom(tester) - pill(tester).bottom;
    expect(gap, 20);
    // home indicator 画在底部 8–13px，胶囊必须整条避开它。
    expect(gap, greaterThanOrEqualTo(16));
  });

  testWidgets('无安全区（macOS / Web）：仍保留下限 12pt', (tester) async {
    await pump(tester, 0);

    expect(shellBottom(tester) - pill(tester).bottom, 12);
  });

  testWidgets('小安全区：回收量不会把浮起量削到下限以下', (tester) async {
    await pump(tester, 20);

    // 20 − 14 = 6，抬回下限。
    expect(shellBottom(tester) - pill(tester).bottom, 12);
  });

  testWidgets('页面底部留白始终盖住整条胶囊', (tester) async {
    for (final safeBottom in [0.0, 20.0, 34.0]) {
      await pump(tester, safeBottom);

      final pillRect = pill(tester);
      final gap = shellBottom(tester) - pillRect.bottom;
      expect(
        reserve(tester),
        closeTo(gap + pillRect.height + 16, 0.01),
        reason: '底部留白与浮起量脱节（safeBottom=$safeBottom）——'
            '留白算小了最后一行压进玻璃，算大了玻璃上方空出一条',
      );
    }
  });
}
