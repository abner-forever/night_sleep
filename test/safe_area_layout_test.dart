import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/core/theme/app_theme.dart';
import 'package:night_sleep/core/widgets/app_sheet.dart';
import 'package:night_sleep/core/widgets/subpage.dart';
import 'package:night_sleep/features/onboarding/presentation/onboarding_overlay.dart';

void main() {
  final cases = [
    (
      size: const Size(390, 844),
      padding: const FakeViewPadding(top: 59, bottom: 34),
      keyboard: 0.0,
    ),
    (
      size: const Size(852, 393),
      padding: const FakeViewPadding(left: 59, right: 59, bottom: 21),
      keyboard: 0.0,
    ),
    (
      size: const Size(1024, 900),
      padding: const FakeViewPadding(top: 24, bottom: 20),
      keyboard: 0.0,
    ),
    (
      size: const Size(390, 844),
      padding: const FakeViewPadding(top: 59, bottom: 34),
      keyboard: 300.0,
    ),
  ];

  Future<void> scrollToEnd(WidgetTester tester) async {
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
    for (var frame = 0; frame < 3; frame++) {
      scroll.position.jumpTo(scroll.position.maxScrollExtent);
      await tester.pump();
    }
  }

  for (final configuration in cases) {
    for (final brightness in Brightness.values) {
      final name =
          '${configuration.size} / ${configuration.keyboard} / $brightness';

      void configure(WidgetTester tester) {
        tester.view.physicalSize = configuration.size;
        tester.view.devicePixelRatio = 1;
        tester.view.viewPadding = configuration.padding;
        tester.view.padding = FakeViewPadding(
          top: configuration.padding.top,
          left: configuration.padding.left,
          right: configuration.padding.right,
          bottom: configuration.keyboard > 0 ? 0 : configuration.padding.bottom,
        );
        tester.view.viewInsets =
            FakeViewPadding(bottom: configuration.keyboard);
        addTearDown(tester.view.reset);
      }

      final theme =
          brightness == Brightness.dark ? AppTheme.dark() : AppTheme.light();

      testWidgets('引导页在横屏与安全区内完整显示操作：$name', (tester) async {
        configure(tester);
        await tester.pumpWidget(MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Stack(children: [OnboardingOverlay(onDone: () {})]),
          ),
        ));
        final skip = tester.getRect(find.text('跳过'));
        expect(skip.top, greaterThanOrEqualTo(configuration.padding.top));
        expect(skip.right,
            lessThan(configuration.size.width - configuration.padding.right));
        expect(
            tester.getRect(find.text('下一步')).bottom,
            lessThan(configuration.size.height -
                configuration.keyboard -
                (configuration.keyboard > 0
                    ? 0
                    : configuration.padding.bottom)));
        expect(find.text('下一步').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('二级页滚动视口铺到底部，末尾内容完整避开安全区：$name', (tester) async {
        configure(tester);
        await tester.pumpWidget(MaterialApp(
          theme: theme,
          home: Subpage(
            title: '安全区检查',
            children: [
              const SizedBox(height: 1200),
              SizedBox(
                key: const ValueKey('last-item'),
                height: 100,
                child: TextButton(onPressed: () {}, child: const Text('末尾操作')),
              ),
            ],
          ),
        ));
        await tester.pump();

        final viewport = tester.getRect(find.byType(CustomScrollView));
        expect(viewport.bottom,
            configuration.size.height - configuration.keyboard);
        expect(viewport.left, configuration.padding.left);
        expect(viewport.right,
            configuration.size.width - configuration.padding.right);
        expect(tester.getTopLeft(find.byKey(const ValueKey('subpage-back'))).dy,
            configuration.padding.top);

        await scrollToEnd(tester);
        final bottomInset =
            configuration.keyboard > 0 ? 0 : configuration.padding.bottom;
        final last = tester.getRect(find.byKey(const ValueKey('last-item')));
        expect(viewport.bottom - last.bottom, closeTo(bottomInset + 24, 0.01));
        expect(find.text('末尾操作').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      for (final expanded in [false, true]) {
        testWidgets('弹层避开顶部、横向切口与键盘，末尾可操作：$expanded / $name', (tester) async {
          configure(tester);
          await tester.pumpWidget(MaterialApp(
            theme: theme,
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: TextButton(
                    onPressed: () => showAppSheet<void>(
                      context: context,
                      expanded: expanded,
                      builder: (context) => AppSheet(
                        expanded: expanded,
                        scrollable: true,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('弹层顶部'),
                            const SizedBox(height: 1200),
                            TextButton(
                                onPressed: () {}, child: const Text('弹层末尾')),
                          ],
                        ),
                      ),
                    ),
                    child: const Text('打开'),
                  ),
                ),
              ),
            ),
          ));
          await tester.tap(find.text('打开'));
          await tester.pumpAndSettle();
          final panel = tester.getRect(find.byType(AppSheet));
          expect(panel.left, greaterThanOrEqualTo(configuration.padding.left));
          expect(
              panel.right,
              lessThanOrEqualTo(
                  configuration.size.width - configuration.padding.right));
          expect(
              panel.bottom,
              lessThanOrEqualTo(
                  configuration.size.height - configuration.keyboard));
          expect(tester.getTopLeft(find.text('弹层顶部')).dy,
              greaterThanOrEqualTo(configuration.padding.top));

          await scrollToEnd(tester);
          final last = tester.getRect(find.text('弹层末尾'));
          final bottomInset =
              configuration.keyboard > 0 ? 0 : configuration.padding.bottom;
          expect(last.bottom, lessThanOrEqualTo(panel.bottom - bottomInset));
          expect(find.text('弹层末尾').hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
