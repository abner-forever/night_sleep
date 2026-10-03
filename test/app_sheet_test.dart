import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/core/theme/app_theme.dart';
import 'package:night_sleep/core/theme/app_tokens.dart';
import 'package:night_sleep/core/widgets/app_sheet.dart';

/// The bottom sheet's three dismiss gestures and its scrim.
///
/// The scrim used to be a child of the panel, so it inherited the panel's
/// slide-up transition and looked like it was being dragged in from the bottom
/// edge. It is now a sibling that fades on its own, and the panel owns an
/// explicit finger-following drag rather than relying on
/// `showModalBottomSheet`'s built-in one.
void main() {
  Future<void> openSheet(
    WidgetTester tester, {
    VoidCallback? onClosed,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () async {
                  await showAppSheet<void>(
                    context: context,
                    builder: (context) => const AppSheet(
                      child: SizedBox(height: 120, width: 400),
                    ),
                  );
                  onClosed?.call();
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
  }

  /// The grabber: a 28px band at the top of the panel.
  Offset handlePoint(WidgetTester tester) {
    final rect = tester.getRect(find.byType(AppSheet));
    return Offset(rect.center.dx, rect.top + 12);
  }

  testWidgets('打开时只滑入面板，蒙层独立淡入', (tester) async {
    await openSheet(tester);

    // The panel is a descendant of the SlideTransition; the scrim is not, so it
    // cannot ride up with it.
    final panelInsideSlide = find.ancestor(
      of: find.byType(AppSheet),
      matching: find.byType(SlideTransition),
    );
    expect(panelInsideSlide, findsWidgets, reason: '面板应随滑入动画进入');

    expect(
      find.descendant(
        of: find.byType(FadeTransition),
        matching: find.byType(BackdropFilter),
      ),
      findsWidgets,
      reason: '蒙层应是一个独立的淡入层',
    );
  });

  testWidgets('点击把手即可关闭', (tester) async {
    var closed = false;
    await openSheet(tester, onClosed: () => closed = true);

    await tester.tapAt(handlePoint(tester));
    await tester.pumpAndSettle();

    expect(closed, isTrue);
    expect(find.byType(AppSheet), findsNothing);
  });

  testWidgets('把手下拉超过阈值后松手会关闭', (tester) async {
    var closed = false;
    await openSheet(tester, onClosed: () => closed = true);

    await tester.dragFrom(handlePoint(tester), const Offset(0, 200));
    await tester.pumpAndSettle();

    expect(closed, isTrue, reason: '下拉足够远应关闭');
  });

  testWidgets('小幅下拉后松手会回弹，面板保持打开', (tester) async {
    var closed = false;
    await openSheet(tester, onClosed: () => closed = true);

    // 60px: past the ~18px touch slop, so this is a real drag rather than a tap
    // on the handle — a shorter pull gets classified as a tap and closes the
    // sheet, which would test the wrong thing. It is still well under the 28%
    // dismissal threshold, and slow enough that velocity cannot decide it.
    await tester.timedDragFrom(
      handlePoint(tester),
      const Offset(0, 60),
      const Duration(milliseconds: 800),
    );
    await tester.pumpAndSettle();

    expect(closed, isFalse, reason: '距离不足应回弹而不是关闭');
    expect(find.byType(AppSheet), findsOneWidget);
  });

  testWidgets('面板内的文字渲染在 Material 上，不带错误下划线', (tester) async {
    // `showGeneralDialog` wraps its route in nothing, so unlike `showDialog`
    // there is no `Material` ancestor unless the sheet supplies one. Without it
    // every `Text` in the panel falls back to Flutter's error style — a yellow
    // double underline — which is exactly what shipped once. Asserting on the
    // resolved style is the only thing that catches it: the text still laid out
    // and the geometry tests all passed.
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showAppSheet<void>(
                  context: context,
                  builder: (context) => const AppSheet(
                    child: SizedBox(
                      height: 120,
                      width: 400,
                      child: Text('面板里的文案'),
                    ),
                  ),
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    final label = find.text('面板里的文案');
    expect(label, findsOneWidget);
    expect(
      DefaultTextStyle.of(tester.element(label)).style.decoration,
      isNot(TextDecoration.underline),
      reason: '面板文字带了下划线，说明缺少 Material 祖先',
    );
    expect(
      find.ancestor(of: label, matching: find.byType(Material)),
      findsWidgets,
      reason: '弹层必须自己提供 Material 祖先',
    );
  });

  testWidgets('点击蒙层关闭', (tester) async {
    var closed = false;
    await openSheet(tester, onClosed: () => closed = true);

    // Well above the panel.
    await tester.tapAt(const Offset(200, 60));
    await tester.pumpAndSettle();

    expect(closed, isTrue);
  });

  testWidgets('打开期间 openSheetCount 会计数，关闭后归零', (tester) async {
    expect(openSheetCount.value, 0);

    await openSheet(tester);
    expect(openSheetCount.value, 1, reason: '顶部渐变依赖这个计数被停用');

    await tester.tapAt(handlePoint(tester));
    await tester.pumpAndSettle();
    // One more turn of the event loop: `showAppSheet` decrements in a `finally`
    // that runs after the route's future completes, which is a microtask past
    // the last frame.
    await tester.pump();
    expect(openSheetCount.value, 0);
  });

  testWidgets('不可关闭的弹层忽略把手与蒙层手势', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showAppSheet<void>(
                  context: context,
                  isDismissible: false,
                  builder: (context) => const AppSheet(
                    child: SizedBox(height: 120, width: 400),
                  ),
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    await tester.tapAt(handlePoint(tester));
    await tester.pumpAndSettle();
    expect(find.byType(AppSheet), findsOneWidget, reason: '不可关闭时点击把手无效');

    await tester.dragFrom(handlePoint(tester), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(find.byType(AppSheet), findsOneWidget, reason: '不可关闭时拖拽无效');
  });

  testWidgets('宽屏下面板限宽 560，但下沿仍贴屏幕底', (tester) async {
    // 原型那条「宽屏浮起 24px」是桌面浏览器里的规则。照搬到 iPad 横屏上，
    // 面板与屏幕底之间会留出一条遮罩——面板看起来悬空断在屏幕底之上
    // （使用方实测后裁定一律贴底）。限宽留着：面板不跟着屏幕拉满。
    tester.view.physicalSize = const Size(1194, 834);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await openSheet(tester);

    final rect = tester.getRect(find.byType(AppSheet));
    expect(rect.width, 560, reason: '宽屏下面板应限宽 560');
    expect(rect.center.dx, 597, reason: '限宽后面板仍居中');
    expect(rect.bottom, 834, reason: '面板下沿必须贴屏幕底，不许浮起');
  });

  testWidgets('AppSheet 在多主题下都能取到设计令牌', (tester) async {
    for (final theme in [AppTheme.light(), AppTheme.dark()]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(
            body: AppSheet(child: SizedBox(height: 80, width: 300)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(AppTokens.of(tester.element(find.byType(AppSheet))), isNotNull);
    }
  });
}
