import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/theme/app_tokens.dart';

final privacyPolicyUrl =
    Uri.parse('https://abner-forever.github.io/night_sleep/#/privacy');

class PrivacyPolicyPage extends StatefulWidget {
  const PrivacyPolicyPage({super.key});

  @override
  State<PrivacyPolicyPage> createState() => _PrivacyPolicyPageState();
}

class _PrivacyPolicyPageState extends State<PrivacyPolicyPage> {
  late final WebViewController _controller;
  Uri? _pageUrl;
  Timer? _timeout;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_pageUrl != null) return;
    final theme = Theme.of(context).brightness.name;
    _pageUrl =
        privacyPolicyUrl.replace(fragment: '/privacy?app=1&theme=$theme');
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    final backgroundColor = AppTokens.of(context).bgBase;
    try {
      await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await _controller.setBackgroundColor(backgroundColor);
      await _controller.setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: _navigate,
        onPageStarted: (_) {
          if (!mounted) return;
          setState(() => _loading = true);
          _startTimeout();
        },
        onPageFinished: (_) {
          _timeout?.cancel();
          if (mounted) setState(() => _loading = false);
        },
        onWebResourceError: (error) {
          if (error.isForMainFrame != false) _showError();
        },
        onHttpError: (error) {
          final uri = error.request?.uri ?? error.response?.uri;
          if (uri?.scheme == 'https' &&
              uri?.origin == privacyPolicyUrl.origin &&
              uri?.path == privacyPolicyUrl.path) {
            _showError();
          }
        },
      ));
      if (mounted) await _load();
    } catch (_) {
      _showError();
    }
  }

  Future<NavigationDecision> _navigate(NavigationRequest request) async {
    final uri = Uri.tryParse(request.url);
    if (uri == null) return NavigationDecision.prevent;
    if (uri.scheme == 'https' &&
        uri.origin == privacyPolicyUrl.origin &&
        uri.path == privacyPolicyUrl.path &&
        uri.fragment.split('?').first == '/privacy') {
      return NavigationDecision.navigate;
    }
    if (request.isMainFrame && {'https', 'mailto'}.contains(uri.scheme)) {
      try {
        final opened =
            await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!opened) _showLinkError();
      } catch (_) {
        _showLinkError();
      }
    }
    return NavigationDecision.prevent;
  }

  void _showLinkError() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('暂时无法打开链接，请稍后重试。')),
    );
  }

  void _startTimeout() {
    _timeout?.cancel();
    _timeout = Timer(const Duration(seconds: 25), _showError);
  }

  void _showError() {
    _timeout?.cancel();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _failed = true;
    });
  }

  Future<void> _load() async {
    setState(() {
      _failed = false;
      _loading = true;
    });
    _startTimeout();
    try {
      await _controller.loadRequest(_pageUrl!);
    } catch (_) {
      _showError();
    }
  }

  @override
  void dispose() {
    _timeout?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Scaffold(
      backgroundColor: tokens.bgBase,
      appBar: AppBar(
        backgroundColor: tokens.bgBase,
        foregroundColor: tokens.textPrimary,
        surfaceTintColor: Colors.transparent,
        title: const Text('隐私协议'),
        leading: IconButton(
          tooltip: '返回',
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Stack(
          children: [
            Positioned.fill(
              child: Offstage(
                offstage: _failed,
                child: WebViewWidget(controller: _controller),
              ),
            ),
            if (_loading)
              LinearProgressIndicator(
                  color: tokens.accent, backgroundColor: tokens.accentSoft),
            if (_failed)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('隐私协议加载失败',
                          style: TextStyle(color: tokens.textPrimary)),
                      const SizedBox(height: 8),
                      Text('请检查网络连接后重试。',
                          style: TextStyle(color: tokens.textMuted)),
                      const SizedBox(height: 16),
                      TextButton(onPressed: _load, child: const Text('重新加载')),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
