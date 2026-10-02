import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// 会话页常驻的「今晚的设定」：起床闹钟与鼾声/梦话记录。
///
/// 两个开关**常驻在结束按钮下方**，不藏进展开区——它们是睡前就该确认的设定，
/// 「先展开再关开关」那条路在躺下之后太长（规格 §四）。
///
/// **闹钟那一行合并了旧版胶囊的三条信息**：剩余时间、已关提示、投递强度标注。
/// 同一件事只留一处显示，也顺带消掉「上方日晷写已超过、下方写还有 0h 0m」那种打架。
///
/// **它不做任何测量。** 起床时间、闹钟开关、鼾声偏好都是用户自己的设定，
/// 没有一个数字是从睡眠里推断出来的。
class SessionSettingsSection extends ConsumerStatefulWidget {
  const SessionSettingsSection({
    super.key,
    required this.session,
    required this.now,
  });

  final SleepSession session;
  final DateTime now;

  @override
  ConsumerState<SessionSettingsSection> createState() =>
      _SessionSettingsSectionState();
}

class _SessionSettingsSectionState
    extends ConsumerState<SessionSettingsSection> {
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
    var draft = minutesToClock(widget.session.wakeMinutes);

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
        .update(wakeMinutes: clockToMinutes(draft));
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

  /// 闹钟状态的措辞。剩余量的口径只有模型一份（`remainingLabelAt`）：这里不再自己
  /// 夹到 0，否则同一屏上方日晷说「已超过起床时间 42m」、下方说「还有 0h 0m」。
  String get _alarmStatus {
    if (!widget.session.alarmEnabled) return '已关闭 · 自然醒后手动结束';
    final remaining = widget.session.remainingLabelAt(widget.now);
    if (remaining == null) return '已过起床时间 · 请手动结束睡眠';
    return '还有 $remaining';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final session = widget.session;
    final muted12 = TextStyle(fontSize: 12, color: tokens.textMuted);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Pressable(
                              haptic: false,
                              isButton: false,
                              onTap: _pickWakeTime,
                              child: Text(
                                minutesToClock(session.wakeMinutes),
                                style: AppTheme.num(
                                  context,
                                  size: 12,
                                  weight: FontWeight.w600,
                                  color: tokens.accentViolet,
                                ),
                              ),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 5),
                              child: Text('·', style: muted12),
                            ),
                            Expanded(
                              child: Text(
                                _alarmStatus,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: muted12,
                              ),
                            ),
                          ],
                        ),
                        // 投递强度的如实标注就贴在开关这一行——用户正是在这里做决定。
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
                          style: muted12,
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
      ],
    );
  }
}
