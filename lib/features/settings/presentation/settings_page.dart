import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_shell.dart';
import '../../../app/app.dart';
import '../../../app/app_toast.dart';
import '../../../core/config/app_config.dart';
import '../../../core/database/app_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_basics.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/glass_surface.dart';
import '../../../core/widgets/ios_controls.dart';
import '../../../core/widgets/wheel_picker.dart';
import '../../sleep/data/sleep_repository.dart';
import '../../sleep/presentation/widgets/dur_bar.dart';

/// Settings — appearance, goal, data, reminders and insight configuration.
///
/// Every control here writes through to SQLite, so a restart preserves the
/// choice. The two entries that lead to sub-pages push routes that cover the
/// tab bar, matching the design.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  Future<void> _update(WidgetRef ref, AppSettingsCompanion values) {
    return ref.read(databaseProvider).updateSettings(values);
  }

  Future<void> _pickReminderTime(
    BuildContext context,
    WidgetRef ref, {
    required bool bedtime,
    required int currentMinutes,
  }) async {
    var draft = _minutesToClock(currentMinutes);
    await showPickerSheet(
      context: context,
      title: bedtime ? '就寝提醒时间' : '起床提醒时间',
      child: AppTimePicker(
        value: draft,
        onChanged: (value) => draft = value,
      ),
    );
    final minutes = _clockToMinutes(draft);
    await _update(
      ref,
      bedtime
          ? AppSettingsCompanion(bedtimeReminderMinutes: Value(minutes))
          : AppSettingsCompanion(wakeReminderMinutes: Value(minutes)),
    );
  }

  static String _minutesToClock(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
      '${(minutes % 60).toString().padLeft(2, '0')}';

  static int _clockToMinutes(String clock) {
    final parts = clock.split(':').map(int.parse).toList();
    return parts[0] * 60 + parts[1];
  }

  Future<void> _confirmDeleteAll(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除全部本地数据？'),
        content: const Text('所有睡眠记录、睡眠阶段、声音事件与洞察都会被永久删除，此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              '删除',
              style: TextStyle(color: AppTokens.of(context).danger),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref.read(sleepRepositoryProvider).deleteAllUserData();
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
    final bedtimeEnabled = settings?.bedtimeReminderEnabled ?? false;
    final wakeEnabled = settings?.wakeReminderEnabled ?? false;
    final bedtimeMinutes = settings?.bedtimeReminderMinutes ?? 22 * 60 + 30;
    final wakeMinutes = settings?.wakeReminderMinutes ?? 7 * 60;
    final soundEnabled = settings?.soundRecordingEnabled ?? false;

    return ListView(
      padding: EdgeInsets.fromLTRB(
        pageGutter(context),
        0,
        pageGutter(context),
        pageBottomInset(context),
      ),
      children: [
        const PageHeading(eyebrow: '偏好设置', title: '设置'),
        const SizedBox(height: 22),

        // ── Appearance ─────────────────────────────────────────────────────
        const SectionHeader('外观'),
        // Label and control are a *single* group child on purpose: two children
        // would put a hairline divider between them, and the segmented control
        // is part of this setting rather than a row of its own.
        IosListGroup(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 13, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '外观模式',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: tokens.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    themeMode == 'system'
                        ? '跟随设备系统设置'
                        : themeMode == 'dark'
                            ? '始终使用深色模式'
                            : '始终使用浅色模式',
                    style: TextStyle(fontSize: 12, color: tokens.textMuted),
                  ),
                  const SizedBox(height: 12),
                  SegmentedControl<String>(
                    expand: true,
                    segments: const [
                      SegmentOption(value: 'system', label: '跟随系统'),
                      SegmentOption(value: 'light', label: '浅色'),
                      SegmentOption(value: 'dark', label: '深色'),
                    ],
                    selected: themeMode,
                    onChanged: (mode) => _update(
                      ref,
                      AppSettingsCompanion(themeMode: Value(mode)),
                    ),
                  ),
                  const SizedBox(height: 13),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),

        // ── Sleep goal ─────────────────────────────────────────────────────
        const SectionHeader('睡眠目标'),
        GlassSurface(
          borderRadius: BorderRadius.circular(AppRadii.panel),
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                children: [
                  _StepButton(
                    label: '−',
                    onTap: () => _update(
                      ref,
                      AppSettingsCompanion(
                        sleepGoalMinutes: Value(
                            ((goalHours - 0.5).clamp(5.0, 12.0) * 60).round()),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              goalHours
                                  .toStringAsFixed(goalHours % 1 == 0 ? 0 : 1),
                              style: AppTheme.num(
                                context,
                                size: 40,
                                weight: FontWeight.w700,
                                letterSpacing: -1.2,
                              ),
                            ),
                            Text(
                              'h',
                              style:
                                  TextStyle(fontSize: 22, color: tokens.accent),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          goalHours >= 7 ? '✓ 健康范围' : '建议 7–9 小时',
                          style:
                              TextStyle(fontSize: 12, color: tokens.textMuted),
                        ),
                      ],
                    ),
                  ),
                  _StepButton(
                    label: '+',
                    onTap: () => _update(
                      ref,
                      AppSettingsCompanion(
                        sleepGoalMinutes: Value(
                            ((goalHours + 0.5).clamp(5.0, 12.0) * 60).round()),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              DurBar(duration: goalHours, max: 12),
            ],
          ),
        ),
        const SizedBox(height: 22),

        // ── Data import ────────────────────────────────────────────────────
        const SectionHeader('睡眠数据导入'),
        IosListGroup(
          onTap: () => context.go('/settings/import'),
          semanticLabel: '小米手环睡眠数据',
          footer: const Text('鼾声、梦话仍由手机夜间录音检测'),
          children: [
            IosListItem(
              haptic: false,
              child: Row(
                children: [
                  ListIconBadge(
                    background: tokens.accentSoft,
                    size: 36,
                    child: AppIcons.wave(
                        size: 19, color: tokens.accent, strokeWidth: 1.7),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '小米手环睡眠数据',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: tokens.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '导入时长、深睡、浅睡与 REM',
                          style:
                              TextStyle(fontSize: 12, color: tokens.textMuted),
                        ),
                      ],
                    ),
                  ),
                  AppIcons.chevronRight(
                      size: 18, color: tokens.textMuted, strokeWidth: 2),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),

        // ── Reminders ──────────────────────────────────────────────────────
        const SectionHeader('提醒'),
        IosListGroup(
          children: [
            IosListItem(
              child: Row(
                children: [
                  ListIconBadge(
                    background: tokens.accentSoft,
                    child: AppIcons.bed(
                        size: 16, color: tokens.accent, strokeWidth: 1.8),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '就寝提醒',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: tokens.textPrimary,
                          ),
                        ),
                        if (bedtimeEnabled)
                          Pressable(
                            haptic: false,
                            isButton: false,
                            onTap: () => _pickReminderTime(
                              context,
                              ref,
                              bedtime: true,
                              currentMinutes: bedtimeMinutes,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                _minutesToClock(bedtimeMinutes),
                                style: AppTheme.num(
                                  context,
                                  size: 12,
                                  weight: FontWeight.w600,
                                  color: tokens.accent,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  IosToggle(
                    value: bedtimeEnabled,
                    semanticLabel: '就寝提醒',
                    onChanged: (value) => _update(
                      ref,
                      AppSettingsCompanion(
                          bedtimeReminderEnabled: Value(value)),
                    ),
                  ),
                ],
              ),
            ),
            IosListItem(
              child: Row(
                children: [
                  const ListIconBadge(
                    background: Color(0x18C8B860),
                    child: _SunBadgeIcon(),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '起床提醒',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: tokens.textPrimary,
                          ),
                        ),
                        if (wakeEnabled)
                          Pressable(
                            haptic: false,
                            isButton: false,
                            onTap: () => _pickReminderTime(
                              context,
                              ref,
                              bedtime: false,
                              currentMinutes: wakeMinutes,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                _minutesToClock(wakeMinutes),
                                style: AppTheme.num(
                                  context,
                                  size: 12,
                                  weight: FontWeight.w600,
                                  color: tokens.accentViolet,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  IosToggle(
                    value: wakeEnabled,
                    semanticLabel: '起床提醒',
                    onChanged: (value) => _update(
                      ref,
                      AppSettingsCompanion(wakeReminderEnabled: Value(value)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),

        // ── Sound monitoring ───────────────────────────────────────────────
        const SectionHeader('声音监测'),
        IosListGroup(
          children: [
            IosListItem(
              child: Row(
                children: [
                  ListIconBadge(
                    background: tokens.accentViolet.withValues(alpha: 0.09),
                    child: AppIcons.snore(
                      size: 16,
                      color: tokens.accentViolet,
                      strokeWidth: 1.8,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '夜间声音录制',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: tokens.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        // Honest about the current state: the preference is
                        // stored, but recording is not implemented.
                        Text(
                          '尚未接入录音，开关只保存偏好',
                          style:
                              TextStyle(fontSize: 12, color: tokens.textMuted),
                        ),
                      ],
                    ),
                  ),
                  IosToggle(
                    value: soundEnabled,
                    semanticLabel: '夜间声音录制',
                    onChanged: (value) => _update(
                      ref,
                      AppSettingsCompanion(soundRecordingEnabled: Value(value)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),

        // ── Insight service ────────────────────────────────────────────────
        const SectionHeader('睡眠洞察'),
        IosListGroup(
          onTap: () => context.go('/settings/insight'),
          semanticLabel: '洞察服务配置',
          children: [
            IosListItem(
              haptic: false,
              child: Row(
                children: [
                  ListIconBadge(
                    background: tokens.accentSoft,
                    size: 36,
                    child: AppIcons.ai(
                        size: 19, color: tokens.accent, strokeWidth: 1.8),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '洞察服务配置',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: tokens.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          settings?.insightProvider == null
                              ? '未配置 · 当前使用本地规则估算'
                              : '${settings!.insightProvider} · ${settings.insightModel ?? ''}',
                          style:
                              TextStyle(fontSize: 12, color: tokens.textMuted),
                        ),
                      ],
                    ),
                  ),
                  AppIcons.chevronRight(
                      size: 18, color: tokens.textMuted, strokeWidth: 2),
                ],
              ),
            ),
          ],
        ),

        // ── Demo data (debug/profile builds only) ──────────────────────────
        // A single row now, not the controls themselves. Wiping and re-seeding
        // the database is a development affordance and does not belong one row
        // away from 「就寝提醒」, where it invites a mistap.
        if (AppConfig.demoDataEnabled) ...[
          const SizedBox(height: 22),
          IosListGroup(
            onTap: () => context.go('/settings/demo'),
            semanticLabel: '演示数据',
            children: [
              IosListItem(
                child: Row(
                  children: [
                    ListIconBadge(
                      background: tokens.bgMuted,
                      child: AppIcons.sparkle(
                          size: 17, color: tokens.textMuted, strokeWidth: 1.8),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '演示数据',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: tokens.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            demoCount == 0 ? '仅调试构建可见' : '$demoCount 条示例记录',
                            style: TextStyle(
                                fontSize: 12, color: tokens.textMuted),
                          ),
                        ],
                      ),
                    ),
                    AppIcons.chevronRight(
                      size: 16,
                      color: tokens.borderStrong,
                      strokeWidth: 2,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],

        // ── Danger zone ────────────────────────────────────────────────────
        const SizedBox(height: 22),
        IosListGroup(
          children: [
            IosListItem(
              onTap: () => _confirmDeleteAll(context, ref),
              child: Row(
                children: [
                  AppIcons.stop(
                      size: 16, color: tokens.danger, strokeWidth: 1.8),
                  const SizedBox(width: 12),
                  Text(
                    '删除全部本地数据',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: tokens.danger,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        // ── About ──────────────────────────────────────────────────────────
        const SizedBox(height: 22),
        GlassSurface(
          borderRadius: BorderRadius.circular(AppRadii.panel),
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              AppIcons.moon(size: 36, color: tokens.accent, strokeWidth: 1.4),
              const SizedBox(height: 8),
              Text(
                '夜深',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: tokens.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '睡眠记录与分析',
                style: TextStyle(fontSize: 14, color: tokens.textMuted),
              ),
              const SizedBox(height: 8),
              Text(
                'v2.0.0',
                style: AppTheme.num(context, size: 12, color: tokens.textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The sunrise badge keeps the design's fixed amber colour, which is outside
/// the semantic palette.
class _SunBadgeIcon extends StatelessWidget {
  const _SunBadgeIcon();

  @override
  Widget build(BuildContext context) =>
      AppIcons.sun(size: 16, color: const Color(0xFFC8B860), strokeWidth: 1.8);
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Pressable(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: tokens.bgMuted,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: tokens.textPrimary,
          ),
        ),
      ),
    );
  }
}
