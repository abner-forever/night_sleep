import 'dart:math' as math;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/noise_session.dart';
import '../../../../app/reminder_permission.dart';
import '../../../../app/reminder_sync.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/platform/haptics.dart';
import '../../../../core/platform/reminders.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/widgets/ios_controls.dart';
import '../../../../core/widgets/wheel_picker.dart';
import '../../../sleep/data/session_repository.dart';
import '../../../sleep/domain/sleep_session.dart';
import '../night_style.dart';
import '../sheets/night_noise_sheet.dart';

/// 「当前睡眠事件」卡：开始睡眠 / 白噪音 / 起床闹钟 / 鼾声检测 四行。
///
/// 它吸收了旧 `SessionSettingsSection` 的全部职责（闹钟开关与时刻、鼾声偏好），
/// 外加白噪音那一行的入口。四行常驻在页面上，**不折叠**——它们是睡前就该确认的
/// 设定，「先展开再关开关」那条路在躺下之后太长（规格 §四）。
///
/// **它不做任何测量。** 起床时间、闹钟开关、鼾声偏好、白噪音音量都是用户自己的
/// 设定，没有一个数字是从睡眠里推断出来的。
class SessionEventsCard extends ConsumerStatefulWidget {
  const SessionEventsCard({
    super.key,
    required this.session,
    required this.now,
  });

  final SleepSession session;
  final DateTime now;

  @override
  ConsumerState<SessionEventsCard> createState() => _SessionEventsCardState();
}

class _SessionEventsCardState extends ConsumerState<SessionEventsCard> {
  bool _recordingEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadRecordingPref();
  }

  /// 只读一次偏好，**不订阅** `settingsProvider` 那条 drift 流：widget 测试的假时钟
  /// 不推进，订阅 `watch*` 会留下 pending timer（见 `.claude/skills/flutter-pitfalls`）。
  Future<void> _loadRecordingPref() async {
    final settings = await ref.read(databaseProvider).getSettings();
    if (!mounted) return;
    setState(() => _recordingEnabled = settings.soundRecordingEnabled);
  }

  Future<void> _pickWakeTime() async {
    var draft = minutesToClock(widget.session.wakeMinutes);

    // 只有「完成」才提交草稿。滚了轮再点取消不该落库。
    final confirmed = await showPickerSheet(
      context: context,
      title: '起床闹钟',
      child: AppTimePicker(value: draft, onChanged: (value) => draft = value),
    );
    if (confirmed != true) return;

    await ref
        .read(sessionRepositoryProvider)
        .update(wakeMinutes: clockToMinutes(draft));
    // 闹钟开着时，改了时刻要立刻重排——否则它会按旧时刻响。
    await _resyncAlarm();
  }

  /// 鼾声/梦话是**跨会话的偏好**，写的是 `AppSettings` 里那个唯一字段。
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

  /// 走 [syncAllReminders] 而不是直接调 `syncAlarm`：日常提醒与会话闹钟必须成对
  /// 推导。只调 `syncAlarm` 时它能让日常起床提醒 9002 让位，却永远不会排回来。
  Future<void> _resyncAlarm() => syncAllReminders(
        ref.read(databaseProvider),
        ref.read(reminderSchedulerProvider),
      );

  /// 闹钟那一行的副标题。
  ///
  /// **已过起床时间优先于开关状态**：`wakeMinutes` 是计划目标，`alarmEnabled` 只决定
  /// 到点响不响，所以「已过」这件事跟开关无关。剩余量的口径只由模型出
  /// （`remainingLabelAt` / `overdueLabelAt`），页面不自己夹到 0——否则同一屏会出现
  /// 「已超过 42m」与「还有 0h 0m」两句打架。
  String get _alarmStatus {
    final session = widget.session;
    if (session.overdueAt(widget.now)) {
      return '已超过起床时间 ${session.overdueLabelAt(widget.now)} · 请手动结束睡眠';
    }
    if (!session.alarmEnabled) return '本次睡眠不设闹钟';
    final remaining = session.remainingLabelAt(widget.now);
    return '将在设定时间轻柔唤醒 · 还有 $remaining';
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final noise = ref.watch(noiseSessionControllerProvider);
    final started = session.startAtUtc.toLocal();
    final wake = minutesToClock(session.wakeMinutes);

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment(-0.45, -1),
          end: Alignment(0.45, 1),
          colors: [NightStyle.eventsFillTop, NightStyle.eventsFillBottom],
        ),
        borderRadius: BorderRadius.circular(NightStyle.cardRadius),
        border: Border.all(color: NightStyle.cardStroke),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text(
                '当前睡眠事件',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: NightStyle.textHeading,
                ),
              ),
              const Spacer(),
              Text(
                '${_hhmm(started)} 开始',
                style: AppTheme.num(
                  context,
                  size: 10,
                  color: NightStyle.textFaint,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),

          // ── 开始睡眠 ──────────────────────────────────────────────────
          _EventRow(
            icon: AppIcons.moon(
                size: 18, color: NightStyle.iconInk, strokeWidth: 1.5),
            title: '开始睡眠',
            subtitle: '睡眠时长正在记录',
            trailing: const _StateText('记录中'),
          ),

          // ── 白噪音 ────────────────────────────────────────────────────
          //
          // 常驻可点：原型在没选声音时把这一行整个藏掉，那会把设置入口一起藏掉
          // （见规格偏差 #29）。未选时右侧状态字写「未开启」，整行照常可点。
          //
          // 右侧只有两态（未开启 / 播放中）：控制器的 `_activeId` 语义是「选中**并正在
          // 播放**」（冷启动对账正是靠这条语义清掉「库里写着在播、其实没声」的假值），
          // 所以 `isPlaying == false` ⟹ `activeId == null`，「播完」与「从未选过」在界面上
          // 本就不可区分。这是**刻意的偏离**，不是漏做——Task 11 会把它写进规格。
          _EventRow(
            icon: AppIcons.music(
                size: 18, color: NightStyle.iconInk, strokeWidth: 1.5),
            title: noise.activeOption?.label ?? '白噪音',
            subtitle: _noiseSubtitle(noise),
            onTap: () => showNightNoiseSheet(context),
            trailing:
                noise.isPlaying ? const _SoundWave() : const _StateText('未开启'),
          ),

          // ── 起床闹钟 ──────────────────────────────────────────────────
          _EventRow(
            icon: AppIcons.clock(
                size: 18, color: NightStyle.iconInk, strokeWidth: 1.5),
            title: '$wake 起床闹钟',
            subtitle: _alarmStatus,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (session.alarmEnabled)
                  _WakeTimeChip(value: wake, onTap: _pickWakeTime),
                const SizedBox(width: 8),
                IosToggle(
                  value: session.alarmEnabled,
                  semanticLabel: '起床闹钟',
                  onChanged: _toggleAlarm,
                ),
              ],
            ),
          ),

          // 投递强度的如实标注就贴在开关这一行——用户正是在这里做决定。
          if (session.alarmEnabled)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text(
                ReminderScheduler.wakeAlarmDeliveryNote,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.45,
                  color: NightStyle.textFaint,
                ),
              ),
            ),

          // ── 鼾声检测 ──────────────────────────────────────────────────
          _EventRow(
            icon: AppIcons.snore(
                size: 18, color: NightStyle.iconInk, strokeWidth: 1.5),
            title: '鼾声/梦话记录',
            // plan A 阶段录音还没接入，如实标注。plan B 落地时删掉这句，
            // 换成真实状态（规格 §六）。这行字是产品红线，一个字都不许改。
            subtitle: '尚未接入录音，开关只保存偏好。',
            // 最后一行不画分隔线（原型 `.sleep-event-row:last-child`）。
            isLast: true,
            trailing: IosToggle(
              value: _recordingEnabled,
              semanticLabel: '鼾声/梦话记录',
              onChanged: _toggleRecording,
            ),
          ),
        ],
      ),
    );
  }

  /// 副标题同样只有两态，理由与右侧状态字一致（见 build 里白噪音那一行的注释）：
  /// 「播完」与「从未选过」不可区分，所以没有「已停止播放」这一句。
  String _noiseSubtitle(NoiseSessionController noise) {
    final option = noise.activeOption;
    if (option == null) return '点这里选择助眠声音';
    final percent = (noise.volume * 100).round();
    return '以 $percent% 音量播放 ${noise.timerMinutes} 分钟';
  }

  static String _hhmm(DateTime local) =>
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

/// 一行事件：图标底板 + 标题/副标题 + 右侧状态。
///
/// 尺寸逐条取自 `.sleep-event-row` / `.sleep-event-icon`：行高 61、间距 11、
/// 图标底板 34×34 圆角 12、底色 `rgba(126,145,233,.12)`、分隔线
/// `rgba(255,255,255,.065)`。分隔线只画在相邻两行**之间**：`isLast` 为真时不画
/// （原型 `.sleep-event-row:last-child { border-bottom: 0; }`），否则鼾声那行下面会多
/// 一条游离的线。
class _EventRow extends StatelessWidget {
  const _EventRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.onTap,
    this.isLast = false,
  });

  /// 直接给一个 `Widget` 而不是构造器：「开始睡眠」「记录中」那几行本来能写成
  /// `const`，但 `AppIcons.*` 是普通函数、不是常量表达式，硬要留 `const` 就得给
  /// 每个字形再包一个类。可读性不值得那点编译期收益，这个组件本身也没贵到需要缓存。
  final Widget icon;
  final String title;
  final String subtitle;
  final Widget trailing;
  final VoidCallback? onTap;

  /// 是不是这一组的最后一行。为真时不画底部分隔线。
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final row = Container(
      constraints:
          const BoxConstraints(minHeight: NightStyle.eventRowMinHeight),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: NightStyle.rowDivider)),
      ),
      child: Row(
        children: [
          Container(
            width: NightStyle.eventIconSize,
            height: NightStyle.eventIconSize,
            decoration: BoxDecoration(
              color: NightStyle.iconFill,
              borderRadius: BorderRadius.circular(NightStyle.eventIconRadius),
            ),
            child: Center(child: icon),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: NightStyle.textStrong,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.35,
                    color: NightStyle.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          trailing,
        ],
      ),
    );

    if (onTap == null) return row;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        AppHaptics.tap();
        onTap!();
      },
      child: row,
    );
  }
}

class _StateText extends StatelessWidget {
  const _StateText(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: NightStyle.stateInk,
        ),
      );
}

/// 可点的闹钟时刻胶囊（原型 `.sleep-alarm-time`）。
class _WakeTimeChip extends StatelessWidget {
  const _WakeTimeChip({required this.value, required this.onTap});

  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Semantics(
        button: true,
        label: '起床时间 $value',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: NightStyle.iconFill,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            value,
            style: AppTheme.num(
              context,
              size: 12,
              weight: FontWeight.w600,
              color: NightStyle.alarmTimeInk,
            ),
          ),
        ),
      ),
    );
  }
}

/// `.sleep-sound-wave`：播放中的三根小竖条。
class _SoundWave extends StatefulWidget {
  const _SoundWave();

  @override
  State<_SoundWave> createState() => _SoundWaveState();
}

class _SoundWaveState extends State<_SoundWave>
    with SingleTickerProviderStateMixin {
  late final AnimationController _wave = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (NightStyle.reduceMotion(context)) {
      _wave.stop();
    } else if (!_wave.isAnimating) {
      _wave.repeat();
    }
  }

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 三根竖条各自的相位错开 0.15 / 0.30，与 `.sleep-sound-wave i:nth-child` 一致。
    const heights = [8.0, 14.0, 10.0];
    const phases = [0.0, 0.15, 0.30];

    return SizedBox(
      height: 18,
      width: 12,
      child: AnimatedBuilder(
        animation: _wave,
        builder: (context, child) => Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 2),
              Container(
                width: 2,
                height: heights[i] *
                    (0.7 +
                        0.3 *
                            math.sin(
                              (_wave.value + phases[i]) * 2 * math.pi,
                            )),
                decoration: BoxDecoration(
                  color: NightStyle.stateInk,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
