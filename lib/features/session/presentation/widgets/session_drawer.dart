import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/noise_session.dart';
import '../../../../app/reminder_permission.dart';
import '../../../../app/reminder_sync.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/platform/reminders.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/app_basics.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/widgets/ios_controls.dart';
import '../../../../core/widgets/wheel_picker.dart';
import '../../../sleep/data/session_repository.dart';
import '../../../sleep/domain/sleep_session.dart';
import '../../../sleep/presentation/widgets/noise_controls.dart';

/// 会话页的设定抽屉：今晚的设定、白噪音与说明。
///
/// 它只负责展开后的那几组设定；收合态那条可点的摘要在会话页里（`_SettingsSummary`），
/// 因为圆环要不要让位由页面决定。
///
/// **它不做任何测量。** 起床时间、闹钟开关、鼾声偏好与白噪音都是用户自己的设定，
/// 没有一个数字是从睡眠里推断出来的。
///
/// 白噪音**不归它播放**：播放器与倒计时挂在 [noiseSessionControllerProvider] 上，
/// 生命周期比这一页长——收起抽屉不会静音（使用方裁定，见 [NoiseSessionController]）。
class SessionDrawer extends ConsumerStatefulWidget {
  const SessionDrawer({super.key, required this.session});

  final SleepSession session;

  @override
  ConsumerState<SessionDrawer> createState() => _SessionDrawerState();
}

class _SessionDrawerState extends ConsumerState<SessionDrawer> {
  bool _recordingEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadRecordingPref();
  }

  /// 只读一次偏好，**不订阅** `settingsProvider` 那条 drift 流：widget 测试的假时钟
  /// 不推进，订阅 `watch*` 会留下 pending timer（见 `.claude/skills/flutter-pitfalls`）。
  /// 之后的同步由本地状态负责。
  Future<void> _loadRecordingPref() async {
    final settings = await ref.read(databaseProvider).getSettings();
    if (!mounted) return;
    setState(() => _recordingEnabled = settings.soundRecordingEnabled);
  }

  Future<void> _pickWakeTime() async {
    var draft = _minutesToClock(widget.session.wakeMinutes);

    // 只有「完成」才提交草稿。滚了轮再点取消不该落库——理由与设置页
    // `_pickReminderTime` 完全相同：用户明确放弃的那次改动不该静默生效。
    final confirmed = await showPickerSheet(
      context: context,
      title: '起床闹钟',
      child: AppTimePicker(
        value: draft,
        onChanged: (value) => draft = value,
      ),
    );
    if (confirmed != true) return;

    await ref
        .read(sessionRepositoryProvider)
        .update(wakeMinutes: _clockToMinutes(draft));
    // 闹钟开着时，改了时刻要立刻重排——否则它会按旧时刻响。
    await _resyncAlarm();
  }

  /// 鼾声/梦话是**跨会话的偏好**，写的是 `AppSettings` 里那个唯一字段。
  ///
  /// 会话表里刻意没有同名字段：存两份就会分叉（会话页关掉、设置页还写着开），
  /// 而这个项目明令禁止第二个真相来源。
  Future<void> _toggleRecording(bool value) async {
    await ref.read(databaseProvider).updateSettings(
          AppSettingsCompanion(soundRecordingEnabled: Value(value)),
        );
    if (!mounted) return;
    setState(() => _recordingEnabled = value);
  }

  Future<void> _toggleAlarm(bool value) async {
    // 与设置页同一个闸口：被拒（或平台安排不了）时不写入会话，开关自己弹回去。
    if (value &&
        !await ensureNotificationPermission(context, ref, target: '闹钟')) {
      return;
    }

    await ref.read(sessionRepositoryProvider).update(alarmEnabled: value);
    await _resyncAlarm();
  }

  /// 把闹钟与「今晚有没有会话、闹钟开着没、几点响」保持一致。
  ///
  /// 走 [syncAllReminders] 而不是直接调 [ReminderScheduler.syncAlarm]：日常提醒与会话
  /// 闹钟必须成对推导。只调 `syncAlarm` 时它能让日常起床提醒 9002 让位，却永远不会把
  /// 9002 排回来——闹钟一关，日常起床提醒也跟着不响。
  Future<void> _resyncAlarm() => syncAllReminders(
        ref.read(databaseProvider),
        ref.read(reminderSchedulerProvider),
      );

  static String _minutesToClock(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
      '${(minutes % 60).toString().padLeft(2, '0')}';

  static int _clockToMinutes(String clock) {
    final parts = clock.split(':').map(int.parse).toList();
    return parts[0] * 60 + parts[1];
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final session = widget.session;
    final noise = ref.watch(noiseSessionControllerProvider);
    final remaining = noise.remainingLabel;
    final failure = noise.failure;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── 今晚的设定 ──────────────────────────────────────────────────────
        const SectionHeader('今晚的设定'),
        IosListGroup(
          children: [
            IosListItem(
              child: Row(
                children: [
                  ListIconBadge(
                    background: tokens.accentSoft,
                    child: AppIcons.clock(
                        size: 16, color: tokens.accent, strokeWidth: 1.8),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '起床闹钟',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: tokens.textPrimary,
                          ),
                        ),
                        Pressable(
                          haptic: false,
                          isButton: false,
                          onTap: _pickWakeTime,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              _minutesToClock(session.wakeMinutes),
                              style: AppTheme.num(
                                context,
                                size: 12,
                                weight: FontWeight.w600,
                                color: tokens.accentViolet,
                              ),
                            ),
                          ),
                        ),
                        // 投递强度的如实标注就贴在开关这一行——用户正是在这里做决定。
                        // 收合态由会话页的胶囊负责，两边引用同一份字面量。
                        if (session.alarmEnabled) ...[
                          const SizedBox(height: 6),
                          Text(
                            ReminderScheduler.wakeAlarmDeliveryNote,
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.45,
                              color: tokens.textMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IosToggle(
                    value: session.alarmEnabled,
                    semanticLabel: '起床闹钟',
                    onChanged: _toggleAlarm,
                  ),
                ],
              ),
            ),
            IosListItem(
              child: Row(
                children: [
                  ListIconBadge(
                    background: tokens.accentViolet.withValues(alpha: 0.09),
                    child: AppIcons.snore(
                        size: 16, color: tokens.accentViolet, strokeWidth: 1.8),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '鼾声/梦话记录',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: tokens.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        // plan A 阶段录音还没接入，如实标注。plan B 落地时删掉这句，
                        // 换成真实状态（规格 §六）。
                        Text(
                          '尚未接入录音，开关只保存偏好。',
                          style:
                              TextStyle(fontSize: 12, color: tokens.textMuted),
                        ),
                      ],
                    ),
                  ),
                  IosToggle(
                    value: _recordingEnabled,
                    semanticLabel: '鼾声/梦话记录',
                    onChanged: _toggleRecording,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),

        // ── 白噪音 ─────────────────────────────────────────────────────────
        const SectionHeader('助眠音效'),
        IosListGroup(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final option in kNoiseOptions)
                        NoiseTile(
                          option: option,
                          active: option.id == noise.activeId,
                          onTap: () => noise.select(option),
                          // 四列：(宽度 - 三个间隔) / 4。
                          width: (MediaQuery.sizeOf(context).width - 110) / 4,
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  VolumeSlider(
                    value: noise.volume,
                    color: noise.activeOption?.color ?? tokens.accent,
                    onChanged: noise.changeVolume,
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      AppIcons.timer(
                          size: 14, color: tokens.textMuted, strokeWidth: 1.8),
                      const SizedBox(width: 6),
                      Text(
                        '定时关闭',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.96,
                          color: tokens.textMuted,
                        ),
                      ),
                      if (remaining != null) ...[
                        const Spacer(),
                        Text(
                          '剩余 $remaining',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: tokens.accent,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final minutes in NoiseSessionController.timerChoices)
                        TimerChip(
                          label: '${minutes}m',
                          selected: noise.timerMinutes == minutes,
                          onTap: () => noise.selectTimer(minutes),
                        ),
                    ],
                  ),
                  if (failure != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      failure,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.45,
                        color: tokens.danger,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),

        // ── 说明 ───────────────────────────────────────────────────────────
        const SectionHeader('说明'),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: tokens.bgMuted,
            borderRadius: BorderRadius.circular(AppRadii.panel),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppIcons.volume(
                  size: 15, color: tokens.textMuted, strokeWidth: 1.6),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '退到后台或锁屏后声音会停（后台播放未接入）。',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: tokens.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
