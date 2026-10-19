import 'dart:math' as math;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/night_recording.dart';
import '../../../../app/noise_session.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/platform/reminders.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/widgets/ios_controls.dart';
import '../../../../core/widgets/wheel_picker.dart';
import '../../../sleep/data/night_recorder.dart' show NightRecordingState;
import '../../../sleep/domain/sleep_session.dart';
import '../night_style.dart';

/// 「当前睡眠事件」卡：开始睡眠 / 白噪音 / 起床闹钟 / 鼾声检测。
///
/// **v3.3 起照原型收紧，它只回显、不再可点。** 睡前设定全部搬去了入睡前那一屏
/// （`session_setup.dart`）：场景、常用白噪音、白噪音完整设置、起床闹钟开关与时刻，
/// 都在那里一次定好。这一屏要陪着用户过一整夜，多一个可点的入口就多一次夜间误触的
/// 机会，而且躺下之后再改闹钟本来就是「开始之前没想清楚」。于是：
///
/// - **白噪音行**只在真的有声音在放时出现（原型 `{selectedNoise && …}`）；
/// - **起床闹钟行**只在闹钟开着时出现（原型 `{alarmEnabled && …}`），右侧只写「已设置」；
/// - **鼾声行**保留开关，副标题改为录音服务的**实际状态**。偏差 #31 当初挡住这颗
///   状态点，理由是「状态点没有真实状态可显示」；plan B 之后那个理由消失了——
///   灯只在录音服务确实在录时亮，它现在说的是真话。
///
/// **它不做任何测量。** 片段计数来自录音服务实测到的片段条数；起床时间、闹钟开关、
/// 鼾声偏好、白噪音音量都是用户自己的设定，没有一个数字是从睡眠里推断出来的。
class SessionEventsCard extends ConsumerStatefulWidget {
  const SessionEventsCard({
    super.key,
    required this.session,
    required this.now,
    this.compact = false,
  });

  final SleepSession session;
  final DateTime now;

  /// 高度受限时收紧行间距，文字和状态保持完整。
  final bool compact;

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

  /// 鼾声/梦话是**跨会话的偏好**，写的是 `AppSettings` 里那个唯一字段。
  Future<void> _toggleRecording(bool value) async {
    await ref.read(databaseProvider).updateSettings(
          AppSettingsCompanion(soundRecordingEnabled: Value(value)),
        );
    // 写完之后立刻让录音重新对齐：关掉开关就该当场停录，而不是录到这一晚结束。
    // 一个「已经关掉却还在录」的麦克风是这一整块最不能有的状态。
    await ref.read(nightRecordingControllerProvider.notifier).refresh();
    if (!mounted) return;
    setState(() => _recordingEnabled = value);
  }

  /// 鼾声那一行的副标题：**写录音服务的实际状态，不是偏好值**。
  ///
  /// 这行字从前是「尚未接入录音，开关只保存偏好」——plan B 落地后那句话成了假话。
  /// 换成真实状态之后，界面上的每一个字都对应一件正在发生或确实没有发生的事；
  /// 尤其是白噪音那段空档必须写出来，否则用户会以为自己整晚都被录着（规格 §六、§十一）。
  String _recordingSubtitle(NightRecordingController recording) {
    return switch (recording.status.state) {
      NightRecordingState.recording => recording.clipCount == 0
          ? '录音中 · 还没录到有声响的片段'
          : '录音中 · 已录到 ${recording.clipCount} 段',
      NightRecordingState.waitingForNoise => '白噪音播放中 · 暂不录音',
      // **这一句是这一整块最要紧的一行字。** 实测（MI 9 / Android 11）上，应用一离开
      // 前台，平台就把录音端口静音并持续交付零样本，而 `record` 插件不会报任何中断
      // ——不知道这件事的话，界面会整夜写着「录音中」，用户第二天才发现什么都没录到，
      // 却分不清是自己一夜没出声还是根本没在录。见 `docs/verification-log.md` v3.19。
      NightRecordingState.silenced => recording.status.reason ?? '麦克风没有在收音。',
      NightRecordingState.stopped => recording.status.reason ?? '录音已停止。',
      NightRecordingState.idle => _recordingEnabled
          // 开关开着却没在录：会话还没起来。与其说一句「已开启」，不如如实说
          // 它现在没在录。
          ? '已开启，但现在没有在录。'
          // 措辞避开「未开启」三个字：这一页另一处状态字用的是它，两句话撞在一起
          // 会让「哪一行在说哪件事」变得要靠猜。
          : '没开。打开后会在夜里录下有声响的片段。',
    };
  }

  /// 闹钟那一行的副标题。
  ///
  /// **已过起床时间优先**：`wakeMinutes` 是计划目标，`alarmEnabled` 只决定到点响不响，
  /// 所以「已过」这件事跟开关无关。剩余量的口径只由模型出（`remainingLabelAt` /
  /// `overdueLabelAt`），页面不自己夹到 0——否则同一屏会出现「已超过 42m」与
  /// 「还有 0h 0m」两句打架。
  ///
  /// 这一行只在闹钟开着时渲染（见 `build`），所以没有「本次睡眠不设闹钟」那一支。
  String get _alarmStatus {
    final session = widget.session;
    if (session.overdueAt(widget.now)) {
      return '已超过起床时间 ${session.overdueLabelAt(widget.now)} · 请手动结束睡眠';
    }
    final remaining = session.remainingLabelAt(widget.now);
    return '将在设定时间轻柔唤醒 · 还有 $remaining';
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final noise = ref.watch(noiseSessionControllerProvider);
    // 录音的**实际状态**，不是偏好值。它是 `ChangeNotifierProvider`（不是 drift 流），
    // 订阅它不会在 widget 测试里留下 pending timer。
    final recording = ref.watch(nightRecordingControllerProvider);
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
      padding: widget.compact
          ? const EdgeInsets.fromLTRB(14, 8, 14, 8)
          : const EdgeInsets.fromLTRB(16, 14, 16, 16),
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
            compact: widget.compact,
            icon: AppIcons.moon(
                size: 18, color: NightStyle.iconInk, strokeWidth: 1.5),
            title: '开始睡眠',
            subtitle: '睡眠时长正在记录',
            trailing: const _StateText('记录中'),
          ),

          // ── 白噪音 ────────────────────────────────────────────────────
          //
          // **只在真有声音在放时才出现**（原型 `{selectedNoise && …}`）。控制器的
          // `_activeId` 语义就是「选中**并正在播放**」（冷启动对账正是靠这条语义清掉
          // 「库里写着在播、其实没声」的假值），所以「没有这一行」与「没在播」是同一件事：
          // 「播完」与「从未选过」在界面上本就不可区分，再画一个「已停止」就是在显示一个
          // 我们并未追踪的状态（偏差 #33）。
          if (noise.activeId != null)
            _EventRow(
              compact: widget.compact,
              icon: AppIcons.music(
                  size: 18, color: NightStyle.iconInk, strokeWidth: 1.5),
              title: noise.activeOption?.label ?? '白噪音',
              subtitle: _noiseSubtitle(noise),
              trailing: const _SoundWave(),
            ),

          // ── 起床闹钟 ──────────────────────────────────────────────────
          //
          // 闹钟开着时出现（原型 `{alarmEnabled && …}`），右侧只写状态——时刻与开关
          // 都在入睡前那一屏定好了，这里不再给可点的胶囊与开关（偏差 #30 撤销）。
          // **副标题一个字不改**：剩余时间、「已超过起床时间」与手动结束的指令、以及
          // 投递强度标注都是这一屏真正要对用户说的话（后者是产品红线）。
          //
          // **睡过头时即使没设闹钟也要出现**：`wakeMinutes` 是用户自己定的计划目标，
          // 「已经过了这个点、请手动结束」是这一屏唯一会告诉他的动作指令（§16.5 把它
          // 挪到了这里）。因为没设闹钟就把这句话一起藏掉，等于把睡过头的人留在
          // 一个只会一直计时的页面上。右侧这时不写「已设置」——那会是假话。
          if (session.alarmEnabled || session.overdueAt(widget.now))
            _EventRow(
              compact: widget.compact,
              icon: AppIcons.clock(
                  size: 18, color: NightStyle.iconInk, strokeWidth: 1.5),
              title: '$wake 起床闹钟',
              subtitle: _alarmStatus,
              trailing: session.alarmEnabled
                  ? const _StateText('已设置')
                  : const SizedBox.shrink(),
            ),

          // 投递强度的如实标注就贴在那一行下面：用户正是在这里做决定。
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
            compact: widget.compact,
            icon: AppIcons.snore(
                size: 18, color: NightStyle.iconInk, strokeWidth: 1.5),
            title: '鼾声/梦话记录',
            // 副标题写**录音服务的实际状态**，不是那个偏好值。从前那句
            // 「尚未接入录音，开关只保存偏好」在 plan B 落地后已经成了假话（偏差 #7
            // 作废）；现在每一个字都对应一件正在发生或确实没发生的事。
            subtitle: _recordingSubtitle(recording),
            // 最后一行不画分隔线（原型 `.sleep-event-row:last-child`）。
            isLast: true,
            // 真在录的时候挂一盏灯。**它只在 `recording` 这一态亮**——一盏写着
            // 「正在聆听」却什么都没在听的灯，正是偏差 #31 当初要挡的东西。
            live: recording.status.isRecording,
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

  /// 这一行只在真的在放时渲染（见 `build`），所以副标题只有一种写法：
  /// 音量与定时都是用户自己设的那两个数。
  String _noiseSubtitle(NoiseSessionController noise) {
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
    this.isLast = false,
    this.live = false,
    this.compact = false,
  });

  /// 真在录的时候挂一盏灯。
  ///
  /// **只在录音服务确实处于录音态时为真**，不是把那个开关回显一遍——一盏写着
  /// 「正在聆听」却什么都没在听的灯，正是偏差 #31 当初要挡的东西。
  final bool live;
  final bool compact;

  /// 直接给一个 `Widget` 而不是构造器：「开始睡眠」「记录中」那几行本来能写成
  /// `const`，但 `AppIcons.*` 是普通函数、不是常量表达式，硬要留 `const` 就得给
  /// 每个字形再包一个类。可读性不值得那点编译期收益，这个组件本身也没贵到需要缓存。
  final Widget icon;
  final String title;
  final String subtitle;
  final Widget trailing;

  /// 是不是这一组的最后一行。为真时不画底部分隔线。
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
          minHeight: compact ? 48 : NightStyle.eventRowMinHeight),
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
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: NightStyle.textStrong,
                        ),
                      ),
                    ),
                    if (live) ...[
                      const SizedBox(width: 6),
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: NightStyle.liveDot,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
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
