import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/app_toast.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/ios_controls.dart';
import '../../../core/widgets/subpage.dart';
import '../data/app_update_controller.dart';
import '../domain/app_release.dart';
import 'widgets/app_update_sheet.dart';

final appStoreUrlProvider = Provider<Uri?>((ref) => null);

class AboutPage extends ConsumerStatefulWidget {
  const AboutPage({super.key});

  @override
  ConsumerState<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends ConsumerState<AboutPage> {
  bool _checking = false;
  bool _sheetOpen = false;

  void _showMessage(String message) =>
      ref.read(toastProvider.notifier).show(message);

  Future<void> _showUpdate() async {
    if (_sheetOpen) return;
    _sheetOpen = true;
    try {
      await showAppSheet<void>(
          context: context, builder: (_) => const AppUpdateSheet());
    } finally {
      _sheetOpen = false;
    }
  }

  Future<void> _checkForUpdates() async {
    if (_checking) return;
    final platform = ref.read(appUpdatePlatformProvider);
    final update = ref.read(appUpdateProvider);
    if (platform == TargetPlatform.android &&
        update.phase == UpdatePhase.checking) {
      return;
    }
    if (platform == TargetPlatform.android &&
        update.release != null &&
        {
          UpdatePhase.downloading,
          UpdatePhase.installing,
          UpdatePhase.ready,
          UpdatePhase.permission
        }.contains(update.phase)) {
      await _showUpdate();
      return;
    }

    setState(() => _checking = true);
    try {
      if (platform == TargetPlatform.iOS) {
        final url = ref.read(appStoreUrlProvider);
        if (url == null) {
          _showMessage('暂未开放 App Store 更新');
        } else if (!await launchUrl(url,
                mode: LaunchMode.externalApplication) &&
            mounted) {
          _showMessage('暂时无法打开 App Store，请稍后重试。');
        }
        return;
      }
      if (platform != TargetPlatform.android) {
        _showMessage('当前平台暂不支持检查更新。');
        return;
      }
      await ref.read(appUpdateProvider.notifier).check(force: true);
      if (!mounted) return;
      final result = ref.read(appUpdateProvider);
      if (result.phase == UpdatePhase.current) {
        _showMessage('当前是最新版');
      } else if (result.phase == UpdatePhase.available) {
        setState(() => _checking = false);
        await _showUpdate();
      } else if (result.phase == UpdatePhase.failed) {
        _showMessage(result.message ?? '检查失败，请稍后重试。');
      }
    } catch (_) {
      if (mounted) _showMessage('检查失败，请稍后重试。');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final info = ref.watch(appPackageInfoProvider);
    final update = ref.watch(appUpdateProvider);
    final checking = _checking || update.phase == UpdatePhase.checking;

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Subpage(
            title: '关于夜深',
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Column(
                  children: [
                    ListIconBadge(
                      background: tokens.accentSoft,
                      size: 80,
                      radius: 24,
                      child: AppIcons.moon(
                          size: 42, color: tokens.accent, strokeWidth: 1.5),
                    ),
                    const SizedBox(height: 16),
                    Text('夜深',
                        style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: tokens.textPrimary)),
                    const SizedBox(height: 6),
                    Text('睡眠记录与分析',
                        style:
                            TextStyle(fontSize: 14, color: tokens.textMuted)),
                  ],
                ),
              ),
              IosListGroup(
                quiet: true,
                children: [
                  Semantics(
                    button: true,
                    enabled: !checking,
                    label: '检查更新',
                    child: IosListItem(
                      key: const ValueKey('about-version'),
                      onTap: checking ? null : _checkForUpdates,
                      child: Row(
                        children: [
                          Text('版本号',
                              style: TextStyle(
                                  fontSize: 14, color: tokens.textPrimary)),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Wrap(
                              alignment: WrapAlignment.end,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                Text(
                                  info.when(
                                    data: (value) =>
                                        formatAppVersion(value.version),
                                    loading: () => '读取中…',
                                    error: (_, __) => '暂时无法读取',
                                  ),
                                  style: TextStyle(
                                      fontSize: 13, color: tokens.textMuted),
                                ),
                                if (update.release != null)
                                  const NewVersionBadge(),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (checking)
                            SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: tokens.accent))
                          else
                            AppIcons.chevronRight(
                                size: 18,
                                color: tokens.textMuted,
                                strokeWidth: 2),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              IosListGroup(
                quiet: true,
                children: [
                  _AboutLink(
                    title: '隐私协议',
                    onTap: () => context.push('/settings/about/privacy'),
                  ),
                  _AboutLink(
                    title: '软件著作权',
                    onTap: () => _showMessage('暂未提供软件著作权登记信息。'),
                  ),
                  _AboutLink(
                    title: 'APP 备案号',
                    onTap: () => _showMessage('暂未提供 APP 备案信息。'),
                  ),
                ],
              ),
            ],
          ),
          const ToastOverlay(),
        ],
      ),
    );
  }
}

class _AboutLink extends StatelessWidget {
  const _AboutLink({required this.title, required this.onTap});

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return IosListItem(
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Text(title,
                style: TextStyle(fontSize: 14, color: tokens.textPrimary)),
          ),
          AppIcons.chevronRight(
              size: 18, color: tokens.textMuted, strokeWidth: 2),
        ],
      ),
    );
  }
}

class NewVersionBadge extends StatelessWidget {
  const NewVersionBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: tokens.accentSoft, borderRadius: BorderRadius.circular(20)),
      child: Text('有新版本',
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: tokens.accent)),
    );
  }
}
