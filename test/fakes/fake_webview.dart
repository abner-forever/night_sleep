import 'package:flutter/widgets.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

class FakeWebViewPlatform extends WebViewPlatform {
  late FakeWebViewController controller;
  late FakeNavigationDelegate delegate;

  @override
  PlatformWebViewController createPlatformWebViewController(
      PlatformWebViewControllerCreationParams params) {
    return controller = FakeWebViewController(params);
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
      PlatformNavigationDelegateCreationParams params) {
    return delegate = FakeNavigationDelegate(params);
  }

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
      PlatformWebViewWidgetCreationParams params) {
    return FakeWebViewWidget(params);
  }
}

class FakeWebViewController extends PlatformWebViewController {
  FakeWebViewController(super.params) : super.implementation();

  final requests = <LoadRequestParams>[];
  JavaScriptMode? javaScriptMode;

  @override
  Future<void> loadRequest(LoadRequestParams params) async =>
      requests.add(params);

  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async =>
      javaScriptMode = mode;

  @override
  Future<void> setBackgroundColor(Color color) async {}

  @override
  Future<void> setPlatformNavigationDelegate(
      PlatformNavigationDelegate handler) async {}
}

class FakeNavigationDelegate extends PlatformNavigationDelegate {
  FakeNavigationDelegate(super.params) : super.implementation();

  late NavigationRequestCallback onNavigationRequest;
  late PageEventCallback onPageStarted;
  late PageEventCallback onPageFinished;
  late WebResourceErrorCallback onWebResourceError;
  late HttpResponseErrorCallback onHttpError;

  @override
  Future<void> setOnNavigationRequest(
          NavigationRequestCallback callback) async =>
      onNavigationRequest = callback;

  @override
  Future<void> setOnPageStarted(PageEventCallback callback) async =>
      onPageStarted = callback;

  @override
  Future<void> setOnPageFinished(PageEventCallback callback) async =>
      onPageFinished = callback;

  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback callback) async =>
      onWebResourceError = callback;

  @override
  Future<void> setOnHttpError(HttpResponseErrorCallback callback) async =>
      onHttpError = callback;
}

class FakeWebViewWidget extends PlatformWebViewWidget {
  FakeWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
