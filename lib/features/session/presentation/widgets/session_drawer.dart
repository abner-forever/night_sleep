import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/app_toast.dart';
import '../../../../app/reminder_sync.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/platform/haptics.dart';
import '../../../../core/platform/reminders.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/app_basics.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/widgets/ios_controls.dart';
import '../../../../core/widgets/wheel_picker.dart';
import '../../../settings/presentation/settings_page.dart';
import '../../../sleep/data/noise_player.dart';
import '../../../sleep/data/noise_synth.dart';
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
class SessionDrawer extends ConsumerStatefulWidget {
  const SessionDrawer({super.key, required this.session});

  final SleepSession session;

  @override
  ConsumerState<SessionDrawer> createState() => _SessionDrawerState();
}

class _SessionDrawerState extends ConsumerState<SessionDrawer> {
  /// 会话里的白噪音**必须有上限**，所以这里没有 `null`。
  ///
  /// 独立的助眠音效弹层保留「不限」与 90m——它是一个「醒着听」的入口，与夜间录音
  /// 没有交互。同一个功能两个上限，两处界面都要写清。
  static const _timerChoices = <int>[15, 30, 45, 60];

  late final NoisePlayer _player = NoisePlayer();

  int _timerMinutes = 30;
  int? _remainingSeconds;
  Timer? _countdown;

  /// 正在播放的音效 id。**不从会话里恢复**：恢复了高亮却没有真的出声，就是在
  /// 宣称一件没发生的事。会话里的 `noiseId` 只用来记住选过什么。
  String? _activeNoiseId;
  late double _volume = widget.session.noiseVolume;

  /// 上次落库的音量百分点，避免拖动时每一帧都写一次库。
  late int _persistedPercent = (_volume * 100).round();

  /// 播放失败时如实说出来，不留下一个「正在播放」的假状态。
  String? _failure;

  bool _recordingEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadRecordingPref();
  }

  @override
  void dispose() {
    _countdown?.cancel();
    // 抽屉自己持有播放器：关掉抽屉就是停掉声音。
    _player.dispose();
    super.dispose();
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
    final minutes = widget.session.wakeMinutes;
    var draft = _minutesToClock(minutes);

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
    final scheduler = ref.read(reminderSchedulerProvider);

    if (value) {
      final permission = await scheduler.requestPermission();
      // 被拒（或平台根本安排不了）时**不写入会话**，开关自己弹回去——与设置页
      // 同一条规则：一个写着「开」却什么都不会响的偏好，正是要消灭的假状态。
      if (permission != ReminderPermission.granted) {
        if (!mounted) return;
        ref.read(toastProvider.notifier).show(
              permission == ReminderPermission.unsupported
                  ? '当前设备无法安排本地通知，闹钟未开启。'
                  : '没有获得通知权限，闹钟未开启。可在系统设置中允许「夜深」发送通知。',
            );
        ref.invalidate(reminderPermissionProvider);
        return;
      }
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

  NoiseOption? get _activeNoise {
    if (_activeNoiseId == null) return null;
    for (final option in kNoiseOptions) {
      if (option.id == _activeNoiseId) return option;
    }
    return null;
  }

  Future<void> _selectNoise(NoiseOption option) async {
    final wasActive = _activeNoiseId == option.id;
    AppHaptics.select();

    if (wasActive) {
      _countdown?.cancel();
      setState(() {
        _activeNoiseId = null;
        _remainingSeconds = null;
        _failure = null;
      });
      await ref.read(sessionRepositoryProvider).update(noiseId: null);
      await _player.stop();
      return;
    }

    final kind = NoiseKind.fromId(option.id);
    if (kind == null) return;

    try {
      // 先 await 再显示为播放中：第一次选一个音还要现场合成，先翻界面会留下一个
      // 对着静音的停止按钮。
      await _player.play(kind, volume: _volume);
    } on NoisePlaybackFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _activeNoiseId = null;
        _failure = failure.message;
      });
      return;
    }
    await ref.read(sessionRepositoryProvider).update(noiseId: option.id);
    if (!mounted) return;
    setState(() {
      _activeNoiseId = option.id;
      _failure = null;
      // 没有「不限」：选中即起倒计时，白噪音不会整晚占着录音通道。
      _startTimer(_timerMinutes);
    });
  }

  void _selectTimer(int minutes) {
    AppHaptics.select();
    _countdown?.cancel();
    setState(() {
      _timerMinutes = minutes;
      _remainingSeconds = null;
      if (_activeNoiseId != null) _startTimer(minutes);
    });
  }

  void _changeVolume(double value) {
    setState(() => _volume = value);
    // 拖动要保持跟手，落库与播放器调用都不阻塞手势。
    _player.setVolume(value);
    final percent = (value * 100).round();
    if (percent != _persistedPercent) {
      _persistedPercent = percent;
      unawaited(
        ref.read(sessionRepositoryProvider).update(noiseVolume: value),
      );
    }
  }

  void _startTimer(int minutes) {
    _countdown?.cancel();
    _remainingSeconds = minutes * 60;
    _countdown =
        Timer.periodic(const Duration(seconds: 1), (_) => _countdownTick());
  }

  void _countdownTick() {
    final remaining = _remainingSeconds;
    if (remaining == null) return;
    if (remaining <= 1) {
      _countdown?.cancel();
      _player.stop();
      unawaited(ref.read(sessionRepositoryProvider).update(noiseId: null));
      setState(() {
        _remainingSeconds = null;
        _activeNoiseId = null;
      });
      return;
    }
    setState(() => _remainingSeconds = remaining - 1);
  }

  String? get _remainingLabel {
    final remaining = _remainingSeconds;
    if (remaining == null) return null;
    final minutes = remaining ~/ 60;
    final seconds = remaining % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

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
    final active = _activeNoise;
    final remaining = _remainingLabel;
    final failure = _failure;

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
                          active: option.id == _activeNoiseId,
                          onTap: () => _selectNoise(option),
                          // 四列：(宽度 - 三个间隔) / 4。
                          width: (MediaQuery.sizeOf(context).width - 110) / 4,
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  VolumeSlider(
                    value: _volume,
                    color: active?.color ?? tokens.accent,
                    onChanged: _changeVolume,
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
                      for (final minutes in _timerChoices)
                        _TimerChip(
                          label: '${minutes}m',
                          selected: _timerMinutes == minutes,
                          onTap: () => _selectTimer(minutes),
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

/// 「定时关闭」的一枚时长 chip。
///
/// 与助眠音效弹层里那颗同款；这里没有「不限」——会话里的白噪音必须到点就停。
class _TimerChip extends StatelessWidget {
  const _TimerChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? tokens.accent : tokens.bgMuted,
          borderRadius: BorderRadius.circular(AppRadii.panel),
        ),
        child: Text(
          label,
          style: AppTheme.num(
            context,
            size: 14,
            weight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? Colors.white : tokens.textSecondary,
          ),
        ),
      ),
    );
  }
}
