import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../app/app.dart';
import '../../../app/app_shell.dart';
import '../../../app/app_toast.dart';
import '../../../core/database/app_database.dart' show AppSetting;
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_basics.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/ios_controls.dart';
import '../data/app_cache.dart';
import '../data/insight_credentials.dart';
import '../data/model_catalog.dart';
import '../data/app_update_controller.dart';
import '../domain/app_release.dart';
import 'about_page.dart';
import 'appearance_settings_page.dart';

/// 根页「睡眠洞察」那一行的副标题。
///
/// 走 [resolveInsightSelection]，与配置页、详情页**同一份默认值解析**：库里
/// `insightProvider` / `insightModel` 在全新安装时就是 `null`（DeepSeek 与其内置
/// 模型只是默认值），读裸列会把「能用的配置」显示成「未配置」——这正是用户报回来的
/// 「填了 key 却说未配置」。密钥那一半单独说：它在钥匙串里（偏差 #8），
/// 有没有配齐只有这一行看得见。
String _insightSubtitle(AppSetting? settings, bool keySet) {
  final selection = resolveInsightSelection(
    providerId: settings?.insightProvider,
    model: settings?.insightModel,
  );
  final model = selection.model ?? '无可用模型';
  final base = '${selection.provider.label} · $model';
  if (keySet) return base;
  return '$base · 未填 API Key';
}

/// Settings — the root of the settings tab.
///
/// v3.5 起照新版原型重排成**三段导航式列表**：常用 / 数据与智能 / 数据与隐私，
/// 外加一张「关于」。外观与睡眠目标不再是平铺在根页上的控件，而是收进了各自的
/// 二级页（`/settings/appearance`、`/settings/sleep`）——根页因此短到一屏放得下。
///
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  /// 从未存过时刻时界面显示的默认值。
  ///
  /// **显示与写库必须用同一个常量。** 分开写的话，界面显示 22:30 而库里是 NULL，
  /// 一片祥和之下开关打开后什么都不会响。
  ///
  /// 提醒控件已搬进 `/settings/sleep`，这两个常量**留在这里不动**：它们描述的是
  /// 设置域的默认值，而且测试里有近十处引用。
  static const defaultBedtimeMinutes = 22 * 60 + 30; // 22:30
  static const defaultWakeMinutes = 7 * 60; // 07:00

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTokens.of(context);
    final settings = ref.watch(settingsProvider).valueOrNull;
    // 密钥在钥匙串里，界面上没有别处能看出「配没配」。这一行必须把它说出来，
    // 否则用户只会看到「未配置」而不知道差的是哪一样。
    final insightKeySet = ref.watch(insightApiKeyProvider).trim().isNotEmpty;

    final themeMode = settings?.themeMode ?? 'system';
    final goalHours = (settings?.sleepGoalMinutes ?? 480) / 60;

    return ListView(
      padding: EdgeInsets.fromLTRB(
        pageGutter(context),
        pageTopInset(context),
        pageGutter(context),
        pageBottomInset(context),
      ),
      children: [
        const PageHeading(eyebrow: '偏好设置', title: '设置'),
        const SizedBox(height: 22),

        // ── 常用 ────────────────────────────────────────────────────────────
        const SectionHeader('常用'),
        IosListGroup(
          quiet: true,
          children: [
            _NavRow(
              background: tokens.accentSoft,
              icon: AppIcons.sparkle(
                  size: 18, color: tokens.accent, strokeWidth: 1.8),
              title: '外观',
              subtitle: AppearanceSettingsPage.labelFor(themeMode),
              onTap: () => context.go('/settings/appearance'),
            ),
            _NavRow(
              background: tokens.accentViolet.withValues(alpha: 0.13),
              icon: AppIcons.sleep(
                  size: 18, color: tokens.accentViolet, strokeWidth: 1.8),
              title: '睡眠设置',
              subtitle: '目标 ${_goalLabel(goalHours)} · 提醒与声音检测',
              onTap: () => context.go('/settings/sleep'),
            ),
            _NavRow(
              background: tokens.accentSoft,
              icon: Text(
                '✦',
                style: TextStyle(fontSize: 18, color: tokens.accent),
              ),
              title: '罗盘',
              subtitle: '使用手机传感器判断当前方位',
              onTap: () => context.go('/settings/compass'),
            ),
          ],
        ),
        const SizedBox(height: 22),

        // ── 数据与智能 ──────────────────────────────────────────────────────
        const SectionHeader('数据与智能'),
        IosListGroup(
          quiet: true,
          children: [
            _NavRow(
              background: tokens.accentSoft,
              icon: AppIcons.wave(
                  size: 18, color: tokens.accent, strokeWidth: 1.7),
              title: '睡眠数据导入',
              subtitle: '小米手环睡眠数据',
              onTap: () => context.go('/settings/import'),
            ),
            _NavRow(
              background: tokens.accentViolet.withValues(alpha: 0.13),
              icon: AppIcons.ai(
                  size: 18, color: tokens.accentViolet, strokeWidth: 1.8),
              title: '睡眠洞察',
              subtitle: _insightSubtitle(settings, insightKeySet),
              onTap: () => context.go('/settings/insight'),
            ),
          ],
        ),
        const SizedBox(height: 22),

        // ── 数据与隐私 ──────────────────────────────────────────────────────
        const SectionHeader('数据与隐私'),
        IosListGroup(
          quiet: true,
          children: [
            _NavRow(
              background: tokens.accentSoft,
              icon: AppIcons.wave(
                  size: 18, color: tokens.accent, strokeWidth: 1.7),
              title: '睡眠数据管理',
              subtitle: '备份、恢复与本地数据管理',
              onTap: () => context.go('/settings/export'),
            ),
            // 「关于」上方的最后一行。清的是**可再生成的临时文件**，不碰记录、
            // 录音与密钥——那三样各自有去处，见 `app_cache.dart` 的说明。
            const _ClearCacheRow(),
          ],
        ),
        const SizedBox(height: 22),

        // ── 关于 ────────────────────────────────────────────────────────────
        const SectionHeader('关于'),
        IosListGroup(
          quiet: true,
          children: [
            IosListItem(
              haptic: false,
              onTap: () => context.go('/settings/about'),
              child: Row(
                children: [
                  ListIconBadge(
                    background: tokens.accentSoft,
                    size: 36,
                    child: AppIcons.moon(
                        size: 18, color: tokens.accent, strokeWidth: 1.7),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '夜深',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: tokens.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '睡眠记录与分析',
                          style: TextStyle(
                            fontSize: 12,
                            color: tokens.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const _VersionLabel(),
                  const SizedBox(width: 6),
                  AppIcons.chevronRight(
                      size: 18, color: tokens.textMuted, strokeWidth: 2),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 「目标 8 小时」里的那段小时数，带半分时不写 `.5` 而写「8.5」——
  /// 副标题只有一行，`SleepSettingsPage.formatGoal` 那套「8 小时 30 分钟」在这里太长。
  static String _goalLabel(double hours) =>
      hours % 1 == 0 ? '${hours.toInt()}' : hours.toStringAsFixed(1);
}

/// 一条**导航行**：图标底板 + 两行文案 + 右侧箭头，整行可点。
/// 「清除缓存」那一行。
///
/// 有状态是因为占用大小要先读一次文件系统。读不到时**如实说读不到**，不显示
/// 一个编出来的「0 B」——那会让人以为已经清干净了。
///
/// **清之前要过二次确认**（v3.10 起）：删是不可撤销的，哪怕删的只是可再生成的临时文件。
class _ClearCacheRow extends ConsumerStatefulWidget {
  const _ClearCacheRow();

  @override
  ConsumerState<_ClearCacheRow> createState() => _ClearCacheRowState();
}

class _ClearCacheRowState extends ConsumerState<_ClearCacheRow> {
  int? _bytes;
  bool _reading = true;
  bool _failed = false;
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_read());
  }

  Future<void> _read() async {
    try {
      final bytes = await ref.read(appCacheProvider).size();
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _failed = false;
        _reading = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _reading = false;
      });
    }
  }

  Future<void> _clear() async {
    if (_clearing) return;

    // 与另外四处删除一样过二次确认（用户 2026-10-03 要求补上这道闸）。
    //
    // **文案要把范围说清**：这一行叫「清除缓存」，但用户心里那个词是「清缓存会不会
    // 把记录清了」，所以不写「数据」这种含糊词，直接点名删的是什么、不动的又是什么。
    // 破坏性取 `true`：删掉的东西本身不可撤销（哪怕它们可以再生成）。
    final confirmed = await showConfirmDialog(
      context,
      title: '清除缓存？',
      message: '只删掉导出副本这类可以再生成的临时文件，睡眠记录与录音片段都不会动。'
          '删除后无法恢复。',
      confirmLabel: '清除',
      destructive: true,
    );
    if (confirmed != true) return;
    if (!mounted) return;

    setState(() => _clearing = true);
    try {
      final freed = await ref.read(appCacheProvider).clear();
      if (!mounted) return;
      setState(() {
        _clearing = false;
        _bytes = 0;
      });
      ref.read(toastProvider.notifier).show(
            freed > 0 ? '已清除 ${formatCacheSize(freed)} 缓存。' : '没有可清除的缓存。',
          );
      // 清完再量一次：万一有删不掉的（正在播放的那个 WAV），读数才对得上。
      await _read();
    } on Object {
      if (!mounted) return;
      setState(() => _clearing = false);
      ref.read(toastProvider.notifier).show('清除失败，请稍后再试。');
    }
  }

  String get _subtitle {
    if (_clearing) return '正在清除…';
    if (_reading) return '正在计算占用…';
    if (_failed) return '暂时读不到占用';
    final bytes = _bytes ?? 0;
    if (bytes == 0) return '暂无缓存';
    return '导出副本等可再生成的临时文件 · ${formatCacheSize(bytes)}';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return _NavRow(
      background: tokens.bgMuted,
      icon:
          AppIcons.sparkle(size: 18, color: tokens.textMuted, strokeWidth: 1.8),
      title: '清除缓存',
      subtitle: _subtitle,
      onTap: _clear,
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.background,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final Color background;
  final Widget icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return IosListItem(
      haptic: false,
      onTap: onTap,
      child: Row(
        children: [
          ListIconBadge(background: background, size: 36, child: icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: tokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: tokens.textMuted),
                ),
              ],
            ),
          ),
          AppIcons.chevronRight(
            size: 18,
            color: tokens.textMuted,
            strokeWidth: 2,
          ),
        ],
      ),
    );
  }
}

/// 「关于」那一行右侧的版本号。
///
/// 版本号来自构建信息，而 `PackageInfo.fromPlatform()` **只在 State 首次构建时取一次**
/// （`late final` 字段初始化器，首次访问即首次 `build`）：
///
/// - 直接把它写在 `build` 里当 `FutureBuilder(future: ...)` 的实参，设置页每次
///   重建（切主题、调目标都会）就会拿到一个新 future，`FutureBuilder` 在
///   `didUpdateWidget` 里比的正是 future 实例，于是退回等待态，版本号闪掉一格。
/// - 反过来把它缓存成进程级变量也不行：`dart:async` 对**已经完成**的 future
///   补挂监听时，是用那个 future **创建时**的 zone 去 `scheduleMicrotask`
///   （`_Future._addListener`）。跨 zone 复用会让回调永远不执行——测试里一个
///   `testWidgets` 取的 future 到下一个用例就再也不回调，正是这个原因。
///
/// 跟着 State 走则两条都避开：实例随页面挂载建一次，重建复用，卸载即弃。
class _VersionLabel extends ConsumerStatefulWidget {
  const _VersionLabel();

  @override
  ConsumerState<_VersionLabel> createState() => _VersionLabelState();
}

class _VersionLabelState extends ConsumerState<_VersionLabel> {
  late final Future<PackageInfo> _info = PackageInfo.fromPlatform();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(ref.read(appUpdateProvider.notifier).check());
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final update = ref.watch(appUpdateProvider);
    if (update.release != null) return const NewVersionBadge();
    return FutureBuilder<PackageInfo>(
      future: _info,
      builder: (context, snapshot) {
        final info = snapshot.data;
        // 拿不到构建信息就不编一个版本号——留空比显示错的强。平台通道不可用时
        // `fromPlatform()` 要么抛 `MissingPluginException`，要么那个 future
        // 干脆不完成，两条路都落在这里。
        if (info == null) return const SizedBox.shrink();
        return Text(
          formatAppVersion(info.version),
          style: AppTheme.num(context, size: 12, color: tokens.textMuted),
        );
      },
    );
  }
}
