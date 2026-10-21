import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:night_sleep/core/theme/app_theme.dart';
import 'package:night_sleep/features/settings/data/app_update_controller.dart';
import 'package:night_sleep/features/settings/presentation/about_page.dart';
import 'package:night_sleep/features/settings/presentation/privacy_policy_page.dart';
import 'package:night_sleep/features/settings/presentation/widgets/app_update_sheet.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'app_update_test.dart' show FakeInstaller, FakeUpdates, installed;
import 'fakes/fake_webview.dart';

void main() {
  Future<FakeUpdates> pumpAbout(
    WidgetTester tester, {
    TargetPlatform platform = TargetPlatform.android,
    FakeUpdates? service,
    FakeInstaller? installer,
    Size size = const Size(390, 844),
    ThemeMode themeMode = ThemeMode.light,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final updater = service ?? FakeUpdates();
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const AboutPage()),
      GoRoute(
          path: '/settings/about/privacy',
          builder: (_, __) => const PrivacyPolicyPage()),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appUpdatePlatformProvider.overrideWithValue(platform),
        appPackageInfoProvider.overrideWith((ref) async => installed()),
        appUpdateServiceProvider.overrideWithValue(updater),
        appInstallerProvider.overrideWithValue(installer ?? FakeInstaller()),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: themeMode,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        routerConfig: router,
      ),
    ));
    await tester.pumpAndSettle();
    return updater;
  }

  Future<void> tapVersion(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('about-version')));
    await tester.pumpAndSettle();
  }

  Future<void> dismissToast(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  }

  testWidgets('about displays a readable version and legal entries',
      (tester) async {
    final updater = await pumpAbout(tester);
    expect(find.text('关于夜深'), findsOneWidget);
    expect(find.text('版本号'), findsOneWidget);
    expect(find.text('0.49.0（Beta 2）'), findsOneWidget);
    expect(find.text('隐私协议'), findsOneWidget);
    expect(find.text('软件著作权'), findsOneWidget);
    expect(find.text('APP 备案号'), findsOneWidget);
    for (final label in [
      '构建号',
      '版本渠道',
      '应用信息',
      '版本更新',
      'App Store 敬请期待',
      '立即更新'
    ]) {
      expect(find.text(label), findsNothing);
    }
    expect(find.byType(AppUpdateSheet), findsNothing);
    expect(updater.checks, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('privacy opens the website in app and returns to about',
      (tester) async {
    final webview = FakeWebViewPlatform();
    WebViewPlatform.instance = webview;
    final updater = await pumpAbout(tester);
    await tester.tap(find.text('隐私协议'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(PrivacyPolicyPage), findsOneWidget);
    expect(
        webview.controller.requests.single.uri.host, 'abner-forever.github.io');
    webview.delegate.onPageFinished('');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.byType(AboutPage), findsOneWidget);
    expect(updater.checks, 0);
  });

  testWidgets('unconfigured legal entries explain on tap', (tester) async {
    await pumpAbout(tester);
    await tester.tap(find.text('软件著作权'));
    await tester.pumpAndSettle();
    expect(find.text('暂未提供软件著作权登记信息。'), findsOneWidget);
    await dismissToast(tester);
    await tester.tap(find.text('APP 备案号'));
    await tester.pumpAndSettle();
    expect(find.text('暂未提供 APP 备案信息。'), findsOneWidget);
    await dismissToast(tester);
  });

  testWidgets('tapping version checks and only then opens update actions',
      (tester) async {
    final updater = await pumpAbout(tester);
    await tapVersion(tester);
    expect(updater.checks, 1);
    expect(find.byType(AppUpdateSheet), findsOneWidget);
    expect(find.text('发现新版本'), findsOneWidget);
    expect(find.text('0.49.0（Beta 3）'), findsOneWidget);
    expect(find.text('改善睡眠记录体验'), findsOneWidget);
    expect(find.text('立即更新'), findsOneWidget);
    expect(updater.downloads, 0);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(find.byType(AppUpdateSheet), findsNothing);
    expect(find.text('有新版本'), findsOneWidget);
    await tapVersion(tester);
    expect(updater.checks, 2);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
  });

  testWidgets('no update shows current-version toast after tapping',
      (tester) async {
    final updater = FakeUpdates()..available = null;
    await pumpAbout(tester, service: updater);
    expect(find.text('当前是最新版'), findsNothing);
    await tapVersion(tester);
    expect(find.text('当前是最新版'), findsOneWidget);
    expect(find.byType(AppUpdateSheet), findsNothing);
    expect(updater.checks, 1);
    await dismissToast(tester);
    expect(find.text('当前是最新版'), findsNothing);
    await tapVersion(tester);
    expect(updater.checks, 2);
    await dismissToast(tester);
  });

  testWidgets('failed check prompts and version remains available to retry',
      (tester) async {
    final updater = FakeUpdates()..failure = Exception('offline');
    await pumpAbout(tester, service: updater);
    await tapVersion(tester);
    expect(find.text('检查失败，请检查网络后重试。'), findsOneWidget);
    expect(find.text('当前是最新版'), findsNothing);
    await dismissToast(tester);
    updater.failure = null;
    await tapVersion(tester);
    expect(find.byType(AppUpdateSheet), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
  });

  testWidgets('iOS only prompts after version is tapped', (tester) async {
    final updater = await pumpAbout(tester, platform: TargetPlatform.iOS);
    expect(find.textContaining('App Store'), findsNothing);
    await tapVersion(tester);
    expect(find.text('暂未开放 App Store 更新'), findsOneWidget);
    expect(find.text('App Store 敬请期待'), findsNothing);
    expect(find.byType(AppUpdateSheet), findsNothing);
    expect(updater.checks, 0);
    await dismissToast(tester);
  });

  testWidgets('closing progress and tapping version restores active download',
      (tester) async {
    final updater = FakeUpdates()..pendingDownload = Completer<File>();
    final installer = FakeInstaller();
    await pumpAbout(tester, service: updater, installer: installer);
    await tapVersion(tester);
    await tester.tap(find.text('立即更新'));
    await tester.pumpAndSettle();
    expect(find.text('33%'), findsOneWidget);
    await tester.tapAt(const Offset(8, 80));
    await tester.pumpAndSettle();
    expect(find.byType(AppUpdateSheet), findsNothing);
    await tapVersion(tester);
    expect(find.text('33%'), findsOneWidget);
    expect(updater.checks, 1);
    expect(updater.downloads, 1);
    await tester.tap(find.text('取消下载'));
    await tester.pumpAndSettle();
    expect(find.byType(AppUpdateSheet), findsNothing);
    expect(installer.calls, 0);
  });

  testWidgets(
      'small dark display and large text fit version and update actions',
      (tester) async {
    await pumpAbout(tester,
        size: const Size(320, 640), themeMode: ThemeMode.dark, textScale: 1.5);
    expect(tester.takeException(), isNull);
    await tapVersion(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('立即更新'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
  });
}
