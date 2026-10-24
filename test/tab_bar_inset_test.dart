import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/app/app_shell.dart';
import 'package:night_sleep/core/theme/app_theme.dart';

void main() {
  const screen = Size(402, 874);

  Future<void> pump(
    WidgetTester tester, {
    required double safeBottom,
    Size size = screen,
    TextScaler textScaler = TextScaler.noScaling,
    ThemeMode themeMode = ThemeMode.light,
    ValueChanged<AppTab>? onSelect,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          padding: EdgeInsets.only(bottom: safeBottom),
          textScaler: textScaler,
        ),
        child: Scaffold(
          body: AppShell(
            current: AppTab.home,
            onSelect: onSelect ?? (_) {},
            child: Builder(
              builder: (context) => ListView(
                padding: EdgeInsets.only(bottom: pageBottomInset(context)),
                children: const [SizedBox(height: 2000)],
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  final navigation = find.byKey(const ValueKey('app-bottom-navigation'));

  testWidgets('底栏内容下移且保留底部安全距离，总高度不变', (tester) async {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      for (final safeBottom in [0.0, 16.0, 20.0, 34.0]) {
        await pump(tester, safeBottom: safeBottom, themeMode: mode);
        final bar = tester.getRect(navigation);
        expect(bar.left, 0);
        expect(bar.right, screen.width);
        expect(bar.bottom, screen.height);
        final bottomInset = safeBottom < 10 ? 10 : safeBottom;
        expect(bar.height, 54 + bottomInset);
        final label = tester.getRect(find.text('首页'));
        expect(screen.height - label.bottom,
            greaterThanOrEqualTo(bottomInset - 4));
        expect(screen.height - label.bottom, closeTo(bottomInset + 4.5, 0.01));
        final reserve = tester
            .widget<ListView>(find.byType(ListView))
            .padding!
            .resolve(TextDirection.ltr)
            .bottom;
        expect(reserve, closeTo(bar.height + 16, 0.01));
        expect(tester.takeException(), isNull);
      }
    }
  }, variant: TargetPlatformVariant.all());

  testWidgets('点击切换仍交给原有外壳回调', (tester) async {
    AppTab? selected;
    await pump(tester, safeBottom: 34, onSelect: (tab) => selected = tab);
    await tester.tap(find.text('回顾'));
    expect(selected, AppTab.log);
  });

  testWidgets('选中标签切换为设计稿的 24px 实心图标', (tester) async {
    await pump(tester, safeBottom: 34);

    expect(find.byKey(const ValueKey('home-true')), findsOneWidget);
    expect(find.byKey(const ValueKey('log-false')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-false')), findsOneWidget);
    for (final tab in AppTab.values) {
      final glyph = find.byKey(ValueKey('${tab.id}-${tab == AppTab.home}'));
      expect(glyph, findsOneWidget);
    }
    expect(tester.getSize(find.byType(SvgPicture).first), const Size(24, 24));
  });

  testWidgets('大字体下底栏文字不溢出', (tester) async {
    await pump(tester, safeBottom: 34, textScaler: const TextScaler.linear(2));
    expect(tester.takeException(), isNull);
    expect(tester.getRect(find.text('首页')).bottom,
        lessThanOrEqualTo(screen.height - 30));
    final reserve = tester
        .widget<ListView>(find.byType(ListView))
        .padding!
        .resolve(TextDirection.ltr)
        .bottom;
    expect(reserve, closeTo(tester.getRect(navigation).height + 16, 0.01));
  });

  testWidgets('宽屏使用侧栏并取消底栏预留', (tester) async {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      await pump(tester,
          safeBottom: 20, size: const Size(1024, 900), themeMode: mode);
      expect(navigation, findsNothing);
      expect(find.text('首页'), findsOneWidget);
      expect(
          tester
              .widget<ListView>(find.byType(ListView))
              .padding!
              .resolve(TextDirection.ltr)
              .bottom,
          60);
      expect(tester.takeException(), isNull);
    }
  });
}
