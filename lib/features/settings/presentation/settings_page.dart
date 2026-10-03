import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../app/app.dart';
import '../../../app/app_shell.dart';
import '../../../app/app_toast.dart';
import '../../../app/session_teardown.dart';
import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_basics.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/ios_controls.dart';
import '../../sleep/data/sleep_repository.dart';
import 'appearance_settings_page.dart';

/// Settings — the root of the settings tab.
///
/// v3.5 起照新版原型重排成**三段导航式列表**：常用 / 数据与智能 / 数据与隐私，
/// 外加一张「关于」。外观与睡眠目标不再是平铺在根页上的控件，而是收进了各自的
/// 二级页（`/settings/appearance`、`/settings/sleep`）——根页因此短到一屏放得下。
///
/// 原型根页只有「外观 / 睡眠设置 / 睡眠数据导入 / 睡眠洞察 / 关于」五条，本实现
/// 另有四条必须保留的入口（原型没有、但规格或既有能力要求）：
/// **导出**（偏差 #18）、**删除全部本地数据**（规格 §7）、**演示数据**（调试构建）
/// 三条收进「数据与隐私」；**罗盘**并入「常用」。
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

  Future<void> _confirmDeleteAll(BuildContext context, WidgetRef ref) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '删除全部本地数据？',
      message: '所有睡眠记录、睡眠阶段、声音事件与洞察都会被永久删除，此操作无法撤销。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (confirmed != true) return;

    await ref.read(sleepRepositoryProvider).deleteAllUserData();
    // 与「结束 / 丢弃会话」**同一套收尾**（[teardownSession]）。删掉 active_sessions
    // 行不会自己撤销 9003、也不会把被压着的日常起床提醒 9002 排回来：少了这一步，
    // 「开始会话 → 开起床闹钟 → 收起会话页 → 删除全部本地数据」之后，第二天早上
    // 07:00 仍会弹「该起床了」，9002 要继续等到下次冷启动才恢复。
    await teardownSession(ref);
    if (!context.mounted) return;
    ref.read(toastProvider.notifier).show('本地数据已全部删除。');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTokens.of(context);
    final settings = ref.watch(settingsProvider).valueOrNull;
    final entries = ref.watch(sleepEntriesProvider).valueOrNull ?? const [];
    final demoCount =
        entries.where((entry) => entry.source == AppConfig.demoSource).length;

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
              subtitle: settings?.insightProvider == null
                  ? '未配置 · 当前使用本地规则估算'
                  : '${settings!.insightProvider} · ${settings.insightModel ?? ''}',
              onTap: () => context.go('/settings/insight'),
            ),
          ],
        ),
        const SizedBox(height: 22),

        // ── 数据与隐私 ──────────────────────────────────────────────────────
        const SectionHeader('数据与隐私'),
        IosListGroup(
          children: [
            _NavRow(
              background: tokens.accentSoft,
              icon: AppIcons.wave(
                  size: 18, color: tokens.accent, strokeWidth: 1.7),
              title: '睡眠数据导出',
              subtitle: 'CSV（记录与阶段）或 JSON（完整存档）',
              onTap: () => context.go('/settings/export'),
            ),
            IosListItem(
              onTap: () => _confirmDeleteAll(context, ref),
              child: Row(
                children: [
                  ListIconBadge(
                    // 令牌里只有 danger、没有 dangerSoft，低透明度底色按既有做法现算。
                    background: tokens.danger.withValues(alpha: 0.12),
                    size: 36,
                    child: AppIcons.trash(
                        size: 17, color: tokens.danger, strokeWidth: 1.8),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '删除全部本地数据',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: tokens.danger,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 演示数据是开发期功能，原型里没有，只在调试构建出现；换库、清库、
            // 重装演示数据这些动作不该挨着「就寝提醒」摆，单独一行更不容易误触。
            if (AppConfig.demoDataEnabled)
              _NavRow(
                background: tokens.bgMuted,
                icon: AppIcons.sparkle(
                    size: 18, color: tokens.textMuted, strokeWidth: 1.8),
                title: '演示数据',
                subtitle: demoCount == 0 ? '仅调试构建可见' : '$demoCount 条示例记录',
                onTap: () => context.go('/settings/demo'),
              ),
          ],
        ),
        const SizedBox(height: 22),

        // ── 关于 ────────────────────────────────────────────────────────────
        const SectionHeader('关于'),
        IosListGroup(
          children: [
            IosListItem(
              haptic: false,
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
class _VersionLabel extends StatefulWidget {
  const _VersionLabel();

  @override
  State<_VersionLabel> createState() => _VersionLabelState();
}

class _VersionLabelState extends State<_VersionLabel> {
  late final Future<PackageInfo> _info = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return FutureBuilder<PackageInfo>(
      future: _info,
      builder: (context, snapshot) {
        final info = snapshot.data;
        // 拿不到构建信息就不编一个版本号——留空比显示错的强。平台通道不可用时
        // `fromPlatform()` 要么抛 `MissingPluginException`，要么那个 future
        // 干脆不完成，两条路都落在这里。
        if (info == null) return const SizedBox.shrink();
        return Text(
          'v${info.version} (${info.buildNumber})',
          style: AppTheme.num(context, size: 12, color: tokens.textMuted),
        );
      },
    );
  }
}
