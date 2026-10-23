import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:night_sleep/app/app.dart';
import 'package:night_sleep/app/app_shell.dart';
import 'package:night_sleep/core/database/app_database.dart';
import 'package:night_sleep/core/theme/app_tokens.dart';
import 'package:night_sleep/core/widgets/app_sheet.dart';
import 'package:night_sleep/core/widgets/subpage.dart';
import 'package:night_sleep/features/onboarding/presentation/onboarding_overlay.dart';
import 'package:night_sleep/features/onboarding/presentation/splash_screen.dart';
import 'package:night_sleep/features/home/presentation/home_page.dart';
import 'package:night_sleep/main.dart' as app;
import 'package:night_sleep/features/sleep/presentation/sheets/detail_sheet.dart';
import 'package:night_sleep/features/sleep/data/sleep_repository.dart';
import 'package:night_sleep/features/session/presentation/sleep_session_page.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const holdSeconds = int.fromEnvironment('VISUAL_HOLD_SECONDS');
  const homePullOnly = bool.fromEnvironment('HOME_PULL_ONLY');

  Future<void> settle(WidgetTester tester) async {
    for (var frame = 0; frame < 5; frame++) {
      await tester.pump(const Duration(milliseconds: 150));
      await tester.runAsync(() => Future<void>.delayed(
            const Duration(milliseconds: 50),
          ));
    }
  }

  Future<void> checkpoint(WidgetTester tester, String name) async {
    await settle(tester);
    expect(tester.takeException(), isNull, reason: name);
    debugPrint('VISUAL_CHECKPOINT $name');
    if (holdSeconds > 0) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        final bytes = await binding.takeScreenshot(name);
        final directory = Directory(
            '${(await getApplicationSupportDirectory()).path}/visual-v19');
        await directory.create(recursive: true);
        final file =
            await File('${directory.path}/$name.png').writeAsBytes(bytes);
        debugPrint('VISUAL_SAVED ${file.path}');
      });
    }
  }

  Future<void> checkEdges(WidgetTester tester, String name) async {
    await checkpoint(tester, name);
    final subpage = find.byType(Subpage);
    final sheet = find.byType(AppSheet);
    final scope = sheet.evaluate().isNotEmpty
        ? sheet.last
        : subpage.evaluate().isNotEmpty
            ? subpage.last
            : null;
    final candidates = scope == null
        ? find.byType(Scrollable)
        : find.descendant(of: scope, matching: find.byType(Scrollable));
    final vertical = candidates.evaluate().where((element) {
      final direction = (element.widget as Scrollable).axisDirection;
      return direction == AxisDirection.down || direction == AxisDirection.up;
    });
    if (vertical.isEmpty) return;
    final scroll = (vertical.first as StatefulElement).state as ScrollableState;
    if (subpage.evaluate().isNotEmpty && sheet.evaluate().isEmpty) {
      final context = tester.element(subpage.last);
      final media = MediaQuery.of(context);
      final viewport = tester.getRect(find.descendant(
          of: subpage.last, matching: find.byType(CustomScrollView)));
      expect(viewport.bottom,
          closeTo(media.size.height - media.viewInsets.bottom, 1),
          reason: '$name：二级页不能在底部安全区上沿截断滚动内容');
    }
    for (var frame = 0; frame < 3; frame++) {
      scroll.position.jumpTo(scroll.position.maxScrollExtent);
      await tester.pump(const Duration(milliseconds: 150));
    }
    await checkpoint(tester, '$name-bottom');
    scroll.position.jumpTo(0);
    await settle(tester);
  }

  testWidgets('基础视觉升级保留导航、主题持久化与弹层关闭行为', (tester) async {
    await tester.runAsync(app.main);
    await tester.pump(const Duration(seconds: 1));
    for (var frame = 0;
        frame < 30 && find.byType(SplashScreen).evaluate().isNotEmpty;
        frame++) {
      await tester.pump(const Duration(milliseconds: 300));
      await tester.runAsync(() => Future<void>.delayed(
            const Duration(milliseconds: 50),
          ));
    }
    expect(find.byType(SplashScreen), findsNothing);
    for (var step = 0; step < 3; step++) {
      final next = find.text('下一步');
      final finish = find.text('开始使用');
      if (finish.evaluate().isNotEmpty) {
        await tester.tap(finish);
      } else if (next.evaluate().isNotEmpty) {
        await tester.tap(next);
      } else {
        break;
      }
      await tester.pump(const Duration(milliseconds: 600));
    }

    for (var frame = 0;
        frame < 20 && find.byType(OnboardingOverlay).evaluate().isNotEmpty;
        frame++) {
      await tester.pump(const Duration(milliseconds: 300));
      await tester.runAsync(() => Future<void>.delayed(
            const Duration(milliseconds: 50),
          ));
    }
    expect(find.byType(OnboardingOverlay), findsNothing);

    expect(find.byType(AppScaffold), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppScaffold)),
    );
    final database = container.read(databaseProvider);
    final originalSettings = (await tester.runAsync(database.getSettings))!;
    final originalRecords = (await tester.runAsync(database.allRecords))!;
    final router = tester
        .widget<MaterialApp>(find.byType(MaterialApp))
        .routerConfig! as GoRouter;

    try {
      for (final mode in ['light', 'dark']) {
        await tester.runAsync(() => database.updateSettings(
              AppSettingsCompanion(themeMode: Value(mode)),
            ));
        await tester.pump(const Duration(seconds: 1));
        router.go('/');
        container.read(activeTabProvider.notifier).state = AppTab.home;
        await tester.pump(const Duration(seconds: 1));
        expect(AppTokens.of(tester.element(find.byType(AppScaffold))),
            mode == 'light' ? AppTokens.light : AppTokens.dark);
        final homeScroll =
            tester.state<ScrollableState>(find.byType(Scrollable).last);
        homeScroll.position.jumpTo(0);
        await checkEdges(tester, 'home-$mode');
        if (MediaQuery.sizeOf(tester.element(find.byType(HomePage))).width <
            kWideLayoutBreakpoint) {
          final gesture = await tester
              .startGesture(tester.getCenter(find.byType(Scrollable).last));
          try {
            await gesture.moveBy(const Offset(0, 300));
            await checkpoint(tester, 'home-pull-$mode');
            expect(find.byKey(const ValueKey('home-pull-background')),
                findsOneWidget);
            await gesture.moveBy(const Offset(0, 400));
            await checkpoint(tester, 'home-pull-extended-$mode');
          } finally {
            await gesture.up();
            await tester.pump();
            await tester.pump(const Duration(seconds: 2));
            await settle(tester);
          }
          expect(
              find.byKey(const ValueKey('home-pull-background')), findsNothing);
        }
        if (homePullOnly) continue;
        await Scrollable.ensureVisible(
          tester.element(find.text('最近 7 条平均时长')),
          alignment: 0.4,
        );
        await checkpoint(tester, 'home-utilities-$mode');
        homeScroll.position.jumpTo(0);
        await settle(tester);

        final entries = container.read(sleepEntriesProvider).valueOrNull ?? [];
        if (entries.isNotEmpty) {
          await tester.tap(find.text('昨夜睡眠'));
          await settle(tester);
          expect(find.byType(DetailSheet), findsOneWidget);
          await checkEdges(tester, 'detail-$mode');
          await tester.tap(find.byKey(const ValueKey('sleep-detail-back')));
          await settle(tester);
          expect(find.byType(DetailSheet), findsNothing);
        }

        await tester.tap(find.text('设置').last);
        await tester.pump(const Duration(milliseconds: 600));
        expect(container.read(activeTabProvider), AppTab.settings);
        await checkEdges(tester, 'settings-$mode');

        await tester.tap(find.text('外观'));
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.byType(Subpage), findsOneWidget);
        expect(find.text('显示模式'), findsWidgets);
        await checkEdges(tester, 'appearance-$mode');
        await tester.tap(find.byKey(const ValueKey('subpage-back')));
        await tester.pump(const Duration(milliseconds: 600));
        expect(container.read(activeTabProvider), AppTab.settings);

        for (final destination in <(String, String)>[
          ('sleep-settings', '/settings/sleep'),
          ('sleep-import', '/settings/import'),
          ('insight', '/settings/insight'),
          ('data-management', '/settings/export'),
          ('backup-restore', '/settings/restore'),
          ('export-preview', '/settings/export/preview'),
          ('demo-settings', '/settings/demo'),
          ('about', '/settings/about'),
          ('privacy', '/settings/about/privacy'),
          ('compass', '/settings/compass'),
          ('history', '/stats/all'),
        ]) {
          router.push(destination.$2);
          await tester.pump(const Duration(milliseconds: 800));
          await checkEdges(tester, '${destination.$1}-$mode');
          router.pop();
          await settle(tester);
        }

        router.push('/settings/insight');
        await settle(tester);
        final input = find.byType(TextField).first;
        await tester.ensureVisible(input);
        await tester.tap(input);
        await tester.pump(const Duration(milliseconds: 800));
        await checkpoint(tester, 'insight-keyboard-$mode');
        FocusManager.instance.primaryFocus?.unfocus();
        await settle(tester);
        router.pop();
        await settle(tester);

        router.push('/sleep/session');
        await settle(tester);
        await checkpoint(tester, 'session-setup-$mode');
        expect(find.byType(SleepSessionPage), findsOneWidget);
        expect(find.text('开始睡眠').hitTestable(), findsOneWidget);
        await tester.tap(find.descendant(
          of: find.byType(SleepSessionPage),
          matching: find.text('完整设置'),
        ));
        await tester.pump(const Duration(milliseconds: 600));
        await checkpoint(tester, 'session-sounds-$mode');
        expect(find.text('白噪音设置'), findsOneWidget);
        Navigator.of(tester.element(find.text('白噪音设置'))).pop();
        await settle(tester);
        await tester.tap(find.text('收起'));
        await settle(tester);

        container.read(activeTabProvider.notifier).state = AppTab.stats;
        await checkEdges(tester, 'statistics-$mode');

        container.read(activeTabProvider.notifier).state = AppTab.log;
        await checkEdges(tester, 'review-$mode');
        router.push('/log/new');
        await settle(tester);
        await checkEdges(tester, 'manual-entry-$mode');
        await tester.ensureVisible(find.text('保存记录'));
        await checkpoint(tester, 'manual-entry-bottom-$mode');
        await tester.tap(find.byKey(const ValueKey('subpage-back')));
        await settle(tester);

        container.read(activeTabProvider.notifier).state = AppTab.home;
        await tester.pump(const Duration(milliseconds: 600));
        await Scrollable.ensureVisible(
          tester.element(find.text('助眠音效').first),
          alignment: 0.4,
        );
        await settle(tester);
        expect(find.text('助眠音效').first.hitTestable(), findsOneWidget);
        await tester.tap(find.text('助眠音效').first);
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.byType(AppSheet), findsOneWidget);
        await checkEdges(tester, 'sound-sheet-$mode');
        await tester.tap(find.text('关闭').first);
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.byType(AppSheet), findsNothing);
        expect(openSheetCount.value, 0);
      }
      expect(
          (await tester.runAsync(database.allRecords))!
              .map((record) => record.id),
          originalRecords.map((record) => record.id));
    } finally {
      await tester.runAsync(() => database.updateSettings(
            AppSettingsCompanion(themeMode: Value(originalSettings.themeMode)),
          ));
      router.go('/');
      container.read(activeTabProvider.notifier).state = AppTab.home;
      await tester.pump(const Duration(milliseconds: 600));
    }
  });
}
