import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/core/theme/app_theme.dart';
import 'package:night_sleep/features/settings/presentation/privacy_policy_page.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'fakes/fake_webview.dart';

void main() {
  late FakeWebViewPlatform webview;

  setUp(() {
    webview = FakeWebViewPlatform();
    WebViewPlatform.instance = webview;
  });

  Future<void> pumpPage(WidgetTester tester,
      {ThemeMode themeMode = ThemeMode.light}) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      home: const PrivacyPolicyPage(),
    ));
    await tester.pump();
  }

  Future<void> disposePage(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox());

  testWidgets('opens HTTPS policy without app data and finishes loading',
      (tester) async {
    await pumpPage(tester, themeMode: ThemeMode.dark);
    final request = webview.controller.requests.single;
    expect(request.uri.origin, 'https://abner-forever.github.io');
    expect(request.uri.path, '/night_sleep/');
    expect(request.uri.fragment, '/privacy?app=1&theme=dark');
    expect(request.headers, isEmpty);
    expect(request.body, isNull);
    expect(webview.controller.javaScriptMode, JavaScriptMode.unrestricted);
    expect(find.byType(WebViewWidget), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    webview.delegate.onPageFinished(request.uri.toString());
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('隐私协议加载失败'), findsNothing);
    await disposePage(tester);
  });

  testWidgets(
      'main frame failures show retry and resource failures are ignored',
      (tester) async {
    await pumpPage(tester);
    webview.delegate.onWebResourceError(const WebResourceError(
      errorCode: -1,
      description: 'image failed',
      isForMainFrame: false,
    ));
    await tester.pump();
    expect(find.text('隐私协议加载失败'), findsNothing);
    webview.delegate.onWebResourceError(const WebResourceError(
      errorCode: -2,
      description: 'offline',
      isForMainFrame: true,
    ));
    webview.delegate.onPageFinished('');
    await tester.pump();
    expect(find.text('隐私协议加载失败'), findsOneWidget);
    await tester.tap(find.text('重新加载'));
    await tester.pump();
    expect(webview.controller.requests.length, 2);
    expect(find.text('隐私协议加载失败'), findsNothing);
    webview.delegate.onPageFinished('');
    await tester.pump();
    await disposePage(tester);
  });

  testWidgets('HTTP failures and timeouts allow retry', (tester) async {
    await pumpPage(tester);
    webview.delegate.onHttpError(HttpResponseError(
      request: WebResourceRequest(uri: privacyPolicyUrl),
      response: WebResourceResponse(uri: privacyPolicyUrl, statusCode: 404),
    ));
    await tester.pump();
    expect(find.text('隐私协议加载失败'), findsOneWidget);
    await tester.tap(find.text('重新加载'));
    await tester.pump(const Duration(seconds: 26));
    expect(find.text('隐私协议加载失败'), findsOneWidget);
    await disposePage(tester);
  });

  testWidgets('email and provider policies open using the system',
      (tester) async {
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    await pumpPage(tester);
    for (final url in [
      'mailto:1661287843@qq.com',
      'https://docs.github.com/zh/site-policy/privacy-policies/github-general-privacy-statement',
    ]) {
      expect(
        await webview.delegate.onNavigationRequest(
            NavigationRequest(url: url, isMainFrame: true)),
        NavigationDecision.prevent,
      );
      final arguments = calls.last.arguments as Map;
      expect(arguments['url'], url);
      expect(arguments['useWebView'], isFalse);
      expect(arguments['useSafariVC'], isFalse);
    }
    await disposePage(tester);
  });

  testWidgets('allows policy navigation and rejects unsafe URLs',
      (tester) async {
    await pumpPage(tester);
    final navigate = webview.delegate.onNavigationRequest;
    expect(
      await navigate(NavigationRequest(
          url: privacyPolicyUrl.toString(), isMainFrame: true)),
      NavigationDecision.navigate,
    );
    for (final url in [
      'javascript:alert(1)',
      'file:///private/data',
      'intent://install',
      'http://abner-forever.github.io/night_sleep/#/privacy',
    ]) {
      expect(
        await navigate(NavigationRequest(url: url, isMainFrame: true)),
        NavigationDecision.prevent,
      );
    }
    await disposePage(tester);
  });
}
