import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app.dart';
import '../../../app/reminder_permission.dart';
import '../../../app/reminder_sync.dart';
import '../../../core/database/app_database.dart';
import '../../../core/platform/reminders.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_basics.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/glass_surface.dart';
import '../../../core/widgets/ios_controls.dart';
import '../../../core/widgets/subpage.dart';
import '../../../core/widgets/wheel_picker.dart';
import 'settings_page.dart';
import 'widgets/goal_slider.dart';
import 'widgets/settings_footnote.dart';

/// 睡眠设置（`/settings/sleep`）。
///
/// v3.5 起从设置根页收进这一页，原型把三块放在一起：**每晚睡眠目标**、
/// **提醒**、**声音检测**。就寝 / 起床提醒的读写与调度逻辑是从设置根页
/// 原样搬过来的，行为一个字没改（含权限被拒时不写偏好、开关回弹）。
class SleepSettingsPage extends ConsumerWidget {
  const SleepSettingsPage({super.key});

  Future<void> _update(WidgetRef ref, AppSettingsCompanion values) {
    return ref.read(databaseProvider).updateSettings(values);
  }

  /// 切换一个提醒开关。
  ///
  /// 开启前先走 [ensureNotificationPermission]：被拒（或平台根本安排不了）时它
  /// **不改动已存的偏好**并返回 false，这里直接返回，让开关自己弹回去——一个写着
  /// 「开」却什么都不会响的偏好，正是规格书要消灭的那类假状态。
  Future<void> _setReminder(
    BuildContext context,
    WidgetRef ref, {
    required bool bedtime,
    required bool value,
  }) async {
    if (value &&
        !await ensureNotificationPermission(context, ref, target: '提醒')) {
      return;
    }

    // **打开时把界面显示的那个时刻一并落库。**
    //
    // `*ReminderMinutes` 是可空列，且全新安装时是 NULL——全项目没有任何地方给它
    // 播种，界面只是用 `?? 默认值` 显示了一个从没存过的时刻。若这里只写 enabled，
    // 计划里就没有这一项：`sync` 只 cancel、不 schedule，开关显示「开」却永远不会响。
    // 那正是规格书要消灭的假状态，而且启动回收也救不了它（回收只在权限为 `denied`
    // 且偏好为真时才动手）。
    final stored = await ref.read(databaseProvider).getSettings();
    final minutes = bedtime
        ? (stored.bedtimeReminderMinutes ?? SettingsPage.defaultBedtimeMinutes)
        : (stored.wakeReminderMinutes ?? SettingsPage.defaultWakeMinutes);

    await _update(
      ref,
      bedtime
          ? AppSettingsCompanion(
              bedtimeReminderEnabled: Value(value),
              bedtimeReminderMinutes: Value(minutes),
            )
          : AppSettingsCompanion(
              wakeReminderEnabled: Value(value),
              wakeReminderMinutes: Value(minutes),
            ),
    );
    ref.invalidate(reminderPermissionProvider);
    await _syncReminders(ref);
  }

  /// 把已调度的通知重排成与数据库里的偏好一致。
  ///
  /// 走 [syncAllReminders] 而不是直接调 [ReminderScheduler.sync]：日常提醒与会话闹钟
  /// 必须成对推导。只调 `sync` 会把会话闹钟开着时本该让位的 9002 排回来（同一分钟
  /// 响两条）；只调 `syncSessionAlarm` 又会让 9002 再也不回来。
  ///
  /// 刻意**不复用** `reconcileReminders`：那条启动路径带着「权限为 `denied` 就回收
  /// 偏好」的分支，会在这里把用户刚改的开关写回 false，还会用 try/catch 吞掉异常；
  /// 这一页有自己的权限处理（开启前先申请、失败就弹回开关），不该被启动路径的回收
  /// 策略覆盖。
  Future<void> _syncReminders(WidgetRef ref) async {
    await syncAllReminders(
      ref.read(databaseProvider),
      ref.read(reminderSchedulerProvider),
    );
  }

  Future<void> _pickReminderTime(
    BuildContext context,
    WidgetRef ref, {
    required bool bedtime,
    required int currentMinutes,
  }) async {
    var draft = minutesToClock(currentMinutes);
    // 只有「完成」才提交草稿。
    //
    // 弹层里的滚动立刻改的是 `draft`，与「用户确认过」是两件事；不看返回值的话，
    // 滚了轮再点「取消」也会落库并重排——用户明确放弃的那次改动照样生效，而且是静默生效。
    final confirmed = await showPickerSheet(
      context: context,
      title: bedtime ? '就寝提醒时间' : '起床提醒时间',
      child: AppTimePicker(
        value: draft,
        onChanged: (value) => draft = value,
      ),
    );
    if (confirmed != true) return;

    final minutes = clockToMinutes(draft);
    await _update(
      ref,
      bedtime
          ? AppSettingsCompanion(bedtimeReminderMinutes: Value(minutes))
          : AppSettingsCompanion(wakeReminderMinutes: Value(minutes)),
    );
    await _syncReminders(ref);
  }

  /// 把小时数写成界面与读屏共用的文字：「8 小时」「8 小时 30 分钟」。
  static String formatGoal(double hours) {
    final whole = hours.floor();
    final minutes = ((hours - whole) * 60).round();
    return minutes == 0 ? '$whole 小时' : '$whole 小时 $minutes 分钟';
  }

  /// 目标落在推荐区间内的一句反馈。
  static String goalFeedback(double hours) {
    if (hours >= 7 && hours <= 9) return '在成年人推荐的睡眠范围内';
    return hours < 7 ? '再多睡一会儿会更有利于恢复' : '充足睡眠，也要保持规律作息';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTokens.of(context);
    final settings = ref.watch(settingsProvider).valueOrNull;

    final goalHours = (settings?.sleepGoalMinutes ?? 480) / 60;
    final bedtimeEnabled = settings?.bedtimeReminderEnabled ?? false;
    final wakeEnabled = settings?.wakeReminderEnabled ?? false;
    final bedtimeMinutes =
        settings?.bedtimeReminderMinutes ?? SettingsPage.defaultBedtimeMinutes;
    final wakeMinutes =
        settings?.wakeReminderMinutes ?? SettingsPage.defaultWakeMinutes;
    final soundEnabled = settings?.soundRecordingEnabled ?? false;
    final permission = ref.watch(reminderPermissionProvider).valueOrNull;

    return Subpage(
      title: '睡眠设置',
      backLabel: '设置',
      children: [
        // ── 每晚睡眠目标 ─────────────────────────────────────────────────────
        const SectionHeader('每晚睡眠目标'),
        GlassSurface(
          borderRadius: BorderRadius.circular(AppRadii.panel),
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
          child: Column(
            children: [
              SizedBox(
                height: 54,
                child: Center(
                  child: Container(
                    width: 50,
                    height: 50,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: tokens.accentSoft,
                      // 原型是 `box-shadow: 0 0 0 8px accent 5%` 的一圈，
                      // 不是投影（blurRadius 0 + spread 才是那个形状）。
                      boxShadow: [
                        BoxShadow(
                          color: tokens.accent.withValues(alpha: 0.05),
                          spreadRadius: 8,
                        ),
                      ],
                    ),
                    child: AppIcons.moon(
                      size: 26,
                      color: tokens.accent,
                      strokeWidth: 1.6,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _GoalValue(hours: goalHours),
              const SizedBox(height: 8),
              Text(
                goalFeedback(goalHours),
                style: TextStyle(fontSize: 12, color: tokens.textMuted),
              ),
              const SizedBox(height: 28),
              GoalSlider(
                value: goalHours,
                format: formatGoal,
                onChanged: (hours) => _update(
                  ref,
                  AppSettingsCompanion(
                    sleepGoalMinutes: Value((hours * 60).round()),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              // 三个标签各自贴左 / 居中 / 贴右，用 `Stack` 定位而不是
              // `space-between`：等宽只对两端的文字成立，中间那个会被挤偏。
              const Stack(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _GoalScaleLabel('5 小时'),
                  ),
                  Align(
                    alignment: Alignment.center,
                    child: _GoalScaleLabel('推荐 7–9 小时', accent: true),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: _GoalScaleLabel('12 小时'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  for (final hours in const [7, 8, 9]) ...[
                    if (hours != 7) const SizedBox(width: 8),
                    Expanded(
                      child: _GoalPreset(
                        hours: hours,
                        selected: goalHours == hours,
                        onTap: () => _update(
                          ref,
                          AppSettingsCompanion(
                            sleepGoalMinutes: Value(hours * 60),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),

        // ── 提醒 ────────────────────────────────────────────────────────────
        const SectionHeader('提醒'),
        IosListGroup(
          children: [
            IosListItem(
              child: Row(
                children: [
                  ListIconBadge(
                    background: tokens.accentSoft,
                    size: 36,
                    child: AppIcons.bed(
                        size: 17, color: tokens.accent, strokeWidth: 1.8),
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
                                minutesToClock(bedtimeMinutes),
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
                    onChanged: (value) => _setReminder(
                      context,
                      ref,
                      bedtime: true,
                      value: value,
                    ),
                  ),
                ],
              ),
            ),
            IosListItem(
              child: Row(
                children: [
                  ListIconBadge(
                    background: tokens.accentViolet.withValues(alpha: 0.13),
                    size: 36,
                    child: AppIcons.sun(
                        size: 17, color: tokens.accentViolet, strokeWidth: 1.8),
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
                                minutesToClock(wakeMinutes),
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
                    onChanged: (value) => _setReminder(
                      context,
                      ref,
                      bedtime: false,
                      value: value,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        // **只在 `denied` 时显示这一行。**
        //
        // 不看「不是 granted」：`unsupported` 时这行文案（「未获得通知权限」）是**假话**
        // ——那台设备上取不到可用时区，是应用侧的问题，跟权限无关；而且那个按钮点了也
        // 不会有任何反应（`openSystemSettings()` 在 `!_ready` 时直接返回）。一行假话
        // 加一个无效按钮，比不给提示更糟。
        //
        // `denied` 的文案仍然中性、不预设历史：插件分不清「从未询问」与「已被拒绝」。
        if (permission == ReminderPermission.denied) ...[
          const SizedBox(height: 10),
          IosListGroup(
            onTap: () =>
                ref.read(reminderSchedulerProvider).openSystemSettings(),
            semanticLabel: '去系统设置开启通知权限',
            children: [
              IosListItem(
                haptic: false,
                child: Row(
                  children: [
                    AppIcons.bed(
                        size: 16, color: tokens.textMuted, strokeWidth: 1.8),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '未获得通知权限。提醒开关打开后若收不到通知，'
                        '请到这里允许「夜深」发送通知。',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: tokens.textMuted,
                        ),
                      ),
                    ),
                    AppIcons.chevronRight(
                        size: 16, color: tokens.borderStrong, strokeWidth: 2),
                  ],
                ),
              ),
            ],
          ),
        ],
        const SettingsFootnote('提醒会根据设置的时间在本机发送通知。'),
        const SizedBox(height: 22),

        // ── 声音检测 ────────────────────────────────────────────────────────
        const SectionHeader('声音检测'),
        IosListGroup(
          children: [
            IosListItem(
              child: Row(
                children: [
                  ListIconBadge(
                    background: tokens.accentViolet.withValues(alpha: 0.13),
                    size: 36,
                    child: AppIcons.snore(
                      size: 17,
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
                        // 新版原型这里写的是「检测打鼾、梦话并生成洞察」——那是我们
                        // **没有的能力**（录音仍未接入，偏差 #7 是产品红线）。照抄
                        // 就等于让应用当场说谎，所以维持既有说法。
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
      ],
    );
  }
}

/// 卡片中央的大号目标值：`8 小时` / `8 小时 30 分钟`。
///
/// 小时数是 42px、`-0.04em` 字距的 tabular 数字；单位退回 15px、字距归零
/// （原型 `.sleep-goal-value span`），半小时那一截与小时数同字号。
class _GoalValue extends StatelessWidget {
  const _GoalValue({required this.hours});

  final double hours;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final whole = hours.floor();
    final minutes = ((hours - whole) * 60).round();

    final unit = TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: tokens.textSecondary,
    );

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          '$whole',
          style: AppTheme.num(
            context,
            size: 42,
            weight: FontWeight.w700,
            letterSpacing: -1.68,
          ),
        ),
        const SizedBox(width: 3),
        Text('小时', style: unit),
        if (minutes != 0) ...[
          const SizedBox(width: 4),
          Text(
            '$minutes',
            style: AppTheme.num(
              context,
              size: 42,
              weight: FontWeight.w700,
              letterSpacing: -1.68,
            ),
          ),
          const SizedBox(width: 3),
          Text('分钟', style: unit),
        ],
      ],
    );
  }
}

/// 滑块下面那行刻度小字（10px）。
class _GoalScaleLabel extends StatelessWidget {
  const _GoalScaleLabel(this.text, {this.accent = false});

  final String text;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Text(
      text,
      style: TextStyle(
        fontSize: 10,
        fontWeight: accent ? FontWeight.w600 : FontWeight.w400,
        color: accent ? tokens.accent : tokens.textMuted,
      ),
    );
  }
}

/// 7 / 8 / 9 小时的快捷按钮。
class _GoalPreset extends StatelessWidget {
  const _GoalPreset({
    required this.hours,
    required this.selected,
    required this.onTap,
  });

  final int hours;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Pressable(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 34),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? tokens.accentSoft : tokens.bgInput,
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        child: Text(
          '$hours 小时',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? tokens.accent : tokens.textSecondary,
          ),
        ),
      ),
    );
  }
}
