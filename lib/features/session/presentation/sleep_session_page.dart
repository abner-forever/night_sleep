import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_shell.dart';
import '../../../app/app_toast.dart';
import '../../../app/session_teardown.dart';
import '../../../core/platform/haptics.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_basics.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../sleep/data/session_repository.dart';
import '../../sleep/domain/sleep_session.dart';
import 'night_scene.dart';
import 'night_style.dart';
import 'sheets/quality_rating_sheet.dart';
import 'widgets/hold_to_finish_button.dart';
import 'widgets/night_backdrop.dart';
import 'widgets/night_scene_picker.dart';
import 'widgets/session_events_card.dart';
import 'widgets/sleep_moon_mark.dart';

/// 睡眠会话页。
///
/// **它不测量任何东西**：两个时刻来自用户按下的按钮，起床时间来自用户的设定。
/// 没有阶段、没有鼾声判定、没有「睡眠质量」的推断——那些要么由用户自己补，
/// 要么在夜间录音那一轮才谈得上。
class SleepSessionPage extends ConsumerStatefulWidget {
  const SleepSessionPage({
    super.key,
    this.now,
    this.tick = const Duration(seconds: 1),
  });

  /// 固定「现在」的**测试接缝**。
  ///
  /// 非空时页面只按这一个时刻渲染，且不起定时器。这条接缝的意义是**让读数
  /// 与执行时刻无关**：真起了定时器，`_now` 就会被真实时钟覆写，于是
  /// 「3h 42m」「23:14」这类断言会随跑测试的日期时间随机变红。
  /// （pending timer 另有人兜：拆树时 `dispose()` 会 cancel 掉它。）
  final DateTime? now;

  /// 实时模式下重绘的间隔。
  final Duration tick;

  @override
  ConsumerState<SleepSessionPage> createState() => _SleepSessionPageState();
}

class _SleepSessionPageState extends ConsumerState<SleepSessionPage> {
  Timer? _timer;
  late DateTime _now = widget.now ?? DateTime.now();

  /// 页面滚动位置。
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    // 冻住时钟时**不要**起定时器：给定时刻就不该再被真实时钟覆写，否则界面
    // 读数会随执行时刻漂移。定时器本身有 `dispose()` 兜底，但那不是这条接缝
    // 的理由——它要挡的是「覆写」，不是「pending timer」。
    if (widget.now == null) {
      _timer = Timer.periodic(widget.tick, (_) {
        if (mounted) setState(() => _now = DateTime.now());
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(activeSessionProvider).valueOrNull;
    final scene = NightScene.fromId(session?.sceneId);

    // 会话页是**常暗**的（原型的睡眠模式就是这么设计的：setup 页写着「屏幕将保持
    // 暗色」），而应用主题可能是浅色。包一层 dark `Theme` 之后，复用的共享组件
    // （白噪音宫格 / 音量条 / 时长 chip / `IosToggle` / `EmptyState`）照常从
    // `AppTokens` 取深色值，不必给它们抄第二份。
    return Theme(
      data: AppTheme.dark(),
      child: Scaffold(
        // 透明，让夜景背景透出来；这个 Scaffold 只为 Material 祖先与键盘内边距
        // 而存在，不是为了它的颜色。推入的路由继承不到外壳的任何东西。
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Positioned.fill(child: NightBackdrop(scene: scene)),
            SafeArea(
              minimum: const EdgeInsets.only(top: 20),
              child: session == null
                  ? const _NoSession()
                  : _SessionBody(
                      session: session,
                      now: _now,
                      scene: scene,
                      onSceneChanged: (picked) => ref
                          .read(sessionRepositoryProvider)
                          .update(sceneId: picked.id),
                      onFinish: () => _finish(session),
                      onFinishHint: () => ref
                          .read(toastProvider.notifier)
                          .show('按住不放，填充条扫满才结束。'),
                      scrollController: _scroll,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// 结束这次会话：评星 → 落库 → 停白噪音 → 撤闹钟 → 切到「回顾」。
  ///
  /// **时长越界时不落库。** 会产生越界的只有两种操作：点了开始就立刻点结束，
  /// 或者点了开始忘了结束、放了好几天。两种都不该静默变成一条睡眠记录，所以
  /// 这里把决定权交回用户（[SessionRepository.finish] 里还有第二道同样的守门）。
  Future<void> _finish(SleepSession session) async {
    final now = widget.now ?? DateTime.now();
    final rejection =
        validateSessionDuration(now.toUtc().difference(session.startAtUtc));

    if (rejection != SessionFinishRejection.none) {
      if (!mounted) return;
      await showAppSheet<void>(
        context: context,
        builder: (context) => _RejectedSheet(
          rejection: rejection,
          onDiscard: () => _discard(context),
        ),
      );
      return;
    }

    final quality = await showQualityRatingSheet(context);
    if (!mounted) return;

    try {
      await ref
          .read(sessionRepositoryProvider)
          .finish(now: now, quality: quality);
    } catch (error) {
      if (!mounted) return;
      ref.read(toastProvider.notifier).show('保存失败：$error');
      return;
    }

    // 记录已经落库，下面全是收尾。收尾一步都不许抛出去——一旦抛了，用户就被
    // 撂在一个没有会话、也没有任何反馈的页面上。见 [teardownSession]。
    await teardownSession(ref);

    if (!mounted) return;
    unawaited(AppHaptics.success());
    ref.read(toastProvider.notifier).show('睡眠记录已保存，补充一下今晚的感受吧。');
    ref.read(activeTabProvider.notifier).state = AppTab.log;
    context.go('/');
  }

  /// 「丢弃这次会话」：不写记录，只删会话行。
  Future<void> _discard(BuildContext sheetContext) async {
    await ref.read(sessionRepositoryProvider).discard();
    // 与结束路径**同一套收尾**（[teardownSession]）。丢弃删的是同一行会话，而
    // 9003 是设定区那个闹钟开关排的、那次调用同时让 9002 让了位：这里若不重排，
    // 一个已经不存在的会话会留着起床闹钟，日常起床提醒还继续被压着——正是
    // `reminder_sync.dart` 里那条规则要防的失败类。
    await teardownSession(ref);
    // 关掉的是**说明层**（它自己的 context），回首页走页面自己的 context——
    // 两个 context 各有各的 mounted 守卫，混着用会在弹层已拆的情况下解引用它。
    if (!mounted || !sheetContext.mounted) return;
    Navigator.of(sheetContext).pop();
    context.go('/');
  }
}

class _NoSession extends StatelessWidget {
  const _NoSession();

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: EmptyState(
          icon: AppIcons.moon(size: 30, color: tokens.accent, strokeWidth: 1.6),
          title: '没有正在进行的睡眠',
          body: '回到首页按「开始睡眠」就能开始记录今晚。',
          actionLabel: '回首页',
          onAction: () => context.go('/'),
        ),
      ),
    );
  }
}

class _SessionBody extends StatelessWidget {
  const _SessionBody({
    required this.session,
    required this.now,
    required this.scene,
    required this.onSceneChanged,
    required this.onFinish,
    required this.onFinishHint,
    required this.scrollController,
  });

  final SleepSession session;
  final DateTime now;
  final NightScene scene;
  final ValueChanged<NightScene> onSceneChanged;
  final VoidCallback onFinish;
  final VoidCallback onFinishHint;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        _StatusHeader(onCollapse: () => _collapse(context)),
        const SizedBox(height: 4),
        _TimerBlock(session: session, now: now),
        const SizedBox(height: 12),
        NightScenePicker(scene: scene, onChanged: onSceneChanged),
        const SizedBox(height: 12),
        SessionEventsCard(session: session, now: now),
        const SizedBox(height: 20),
        // 结束按钮在事件卡下方：它是这一页唯一的出口，也是拇指最顺的位置。
        HoldToFinishButton(onFinish: onFinish, onHint: onFinishHint),
      ],
    );
  }
}

/// 顶部一行：左边「收起」，右边居中的状态点与「睡眠进行中」。
///
/// **「收起」是我们相对原型多留的**：原型的激活态是个占满全屏的模态，没有任何出口，
/// 而我们收起之后会话继续跑（首页显示「正在睡眠」卡）。照搬模态等于砍掉这条既有
/// 能力（规格偏差 #28）。
class _StatusHeader extends StatelessWidget {
  const _StatusHeader({required this.onCollapse});

  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          _CollapsePill(onTap: onCollapse),
          const Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _PulseDot(),
                SizedBox(width: 8),
                Text(
                  '睡眠进行中',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.3,
                    color: NightStyle.statusText,
                  ),
                ),
              ],
            ),
          ),
          // 右侧留一块与左侧胶囊等宽的空白，标题才真的居中（原型用
          // `.sleep-header-spacer { width: 48px }` 达到同一效果）。
          const SizedBox(width: 62),
        ],
      ),
    );
  }
}

/// `.sleep-live-status > span:first-child`：2.2 秒一轮的呼吸圆点。
class _PulseDot extends StatefulWidget {
  const _PulseDot();

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (NightStyle.reduceMotion(context)) {
      _pulse.stop();
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) => Opacity(
        // `sleepPulse { 50% { opacity: .45 } }`
        opacity: 1 - 0.55 * Curves.easeInOut.transform(_pulse.value),
        child: child,
      ),
      child: const DecoratedBox(
        decoration: BoxDecoration(
          color: NightStyle.statusDot,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: NightStyle.statusDot, blurRadius: 12)],
        ),
        child: SizedBox(width: 6, height: 6),
      ),
    );
  }
}

/// 中央：月亮 + 当前时刻 + `HH:MM:SS` + 「已进入睡眠模式」。
class _TimerBlock extends StatelessWidget {
  const _TimerBlock({required this.session, required this.now});

  final SleepSession session;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final clock = now.toLocal();
    final hhmm = '${clock.hour.toString().padLeft(2, '0')}:'
        '${clock.minute.toString().padLeft(2, '0')}';
    final elapsed = session.elapsedClockAt(now);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          const SleepMoonOrbit(size: 132, live: true),
          const SizedBox(height: 24),
          Text(
            hhmm,
            style: const TextStyle(
              fontSize: 13,
              letterSpacing: 1.6,
              color: NightStyle.clockText,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            elapsed,
            style: AppTheme.num(
              context,
              size: 46,
              weight: FontWeight.w500,
              letterSpacing: 1.1,
              color: NightStyle.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            '已进入睡眠模式',
            style: TextStyle(fontSize: 12, color: NightStyle.textFaint),
          ),
        ],
      ),
    );
  }
}

///
/// 只有两种操作会产生它：点了开始就立刻点结束，或者点了开始忘了结束、放了好几天。
/// 两种都不该静默变成一条睡眠记录，所以这里**不落库**，让用户自己选。
class _RejectedSheet extends StatelessWidget {
  const _RejectedSheet({required this.rejection, required this.onDiscard});

  final SessionFinishRejection rejection;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final tooShort = rejection == SessionFinishRejection.tooShort;

    return AppSheet(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tooShort ? '这次会话太短' : '这次会话超过 24 小时',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: tokens.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              tooShort
                  ? '还没有睡够一分钟，先不记录。如果你是刚点错了，丢弃它就好。'
                  : '看起来是忘了结束睡眠。这么长的记录多半不是真的，'
                      '与其写一条不可信的时长，不如你自己补上准确的那一晚。',
              textAlign: TextAlign.center,
              style:
                  TextStyle(fontSize: 13, height: 1.5, color: tokens.textMuted),
            ),
            const SizedBox(height: 20),
            PrimaryAction(
              label: '手动补录某一晚',
              onTap: () {
                Navigator.of(context).pop();
                context.push('/log/new');
              },
            ),
            const SizedBox(height: 10),
            Pressable(
              onTap: onDiscard,
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  '丢弃这次会话',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: tokens.danger,
                  ),
                ),
              ),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
          ],
        ),
      ),
    );
  }
}

/// 左上角的「收起」：离开页面但**不结束会话**。
class _CollapsePill extends StatelessWidget {
  const _CollapsePill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        AppHaptics.tap();
        onTap();
      },
      child: Container(
        constraints: const BoxConstraints(minWidth: 56, minHeight: 34),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: NightStyle.glassFill,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          border: Border.all(color: NightStyle.glassStroke),
        ),
        alignment: Alignment.center,
        child: const Text(
          '收起',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: NightStyle.glassInk,
          ),
        ),
      ),
    );
  }
}

void _collapse(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go('/');
  }
}
