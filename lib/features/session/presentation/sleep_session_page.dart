import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_shell.dart';
import '../../../app/app_toast.dart';
import '../../../app/noise_session.dart';
import '../../../app/reminder_sync.dart';
import '../../../core/database/app_database.dart';
import '../../../core/platform/haptics.dart';
import '../../../core/platform/reminders.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_basics.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/atmosphere.dart';
import '../../../core/widgets/glass_surface.dart';
import '../../sleep/data/session_repository.dart';
import '../../sleep/domain/sleep_session.dart';
import 'sheets/quality_rating_sheet.dart';
import 'widgets/session_drawer.dart';
import 'widgets/wake_dial.dart';

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

  /// 设定抽屉展开着没。收合态才画圆环——展开后它让位给抽屉，
  /// 但「入睡 ─── 闹钟」那一行两种状态都留着。
  bool _drawerOpen = false;

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(activeSessionProvider).valueOrNull;

    return Atmosphere(
      child: Scaffold(
        // 透明，让 atmosphere 透出来；这个 Scaffold 只为 Material 祖先与键盘
        // 内边距而存在，不是为了它的颜色。推入的路由继承不到外壳的任何东西。
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: session == null
              ? const _NoSession()
              : _SessionBody(
                  session: session,
                  now: _now,
                  drawerOpen: _drawerOpen,
                  onToggleDrawer: () =>
                      setState(() => _drawerOpen = !_drawerOpen),
                  onFinish: () => _finish(session),
                ),
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

    // 会话结束了声音还在响说不通；两条出口（落库 / 丢弃）都要停。
    await ref.read(noiseSessionControllerProvider).stop();

    // 取消通知排在事务**之后**，且是尽力而为。顺序不能反：先撤通知再写库，
    // 一旦写库失败，用户就得到「闹钟没了、记录也没有」的最坏组合；反过来的
    // 失败最多多响一次，而 9003 是一次性通知，响过就没了。
    //
    // 走 [syncAllReminders] 而不是只调 `syncSessionAlarm`：后者不对称——能让
    // 日常起床提醒 9002 让位，却永远不会把 9002 排回来。
    await syncAllReminders(
      ref.read(databaseProvider),
      ref.read(reminderSchedulerProvider),
    );

    if (!mounted) return;
    unawaited(AppHaptics.success());
    ref.read(toastProvider.notifier).show('睡眠记录已保存，补充一下今晚的感受吧。');
    ref.read(activeTabProvider.notifier).state = AppTab.log;
    context.go('/');
  }

  /// 「丢弃这次会话」：不写记录，只删会话行。
  Future<void> _discard(BuildContext sheetContext) async {
    await ref.read(sessionRepositoryProvider).discard();
    // 会话没了，白噪音也不该继续。
    await ref.read(noiseSessionControllerProvider).stop();
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
    required this.drawerOpen,
    required this.onToggleDrawer,
    required this.onFinish,
  });

  final SleepSession session;
  final DateTime now;
  final bool drawerOpen;
  final VoidCallback onToggleDrawer;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final overdue = session.overdueAt(now);

    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.paddingOf(context).top + 8,
        16,
        24,
      ),
      children: [
        Row(
          children: [
            _CollapsePill(onTap: () => _collapse(context)),
            const Spacer(),
            Text(
              '夜深 · 睡眠中',
              style: TextStyle(fontSize: 12, color: tokens.textMuted),
            ),
          ],
        ),
        const SizedBox(height: 18),
        // 状态一行：这是「此刻在跑一个会话」的正面确认，收起态也看得见。
        // 中文文案，不是数字，所以不走 `AppTheme.num`（那个 helper 带
        // tabular figures）。
        Text(
          '正在睡眠',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            color: tokens.textPrimary,
          ),
        ),
        const SizedBox(height: 14),
        // 展开设定抽屉时圆环让位；「入睡 ─── 闹钟」那一行则两种状态都留着。
        if (!drawerOpen) ...[
          Center(
            child: WakeDial(
              progress: session.progressAt(now),
              label: session.elapsedLabelAt(now),
              sublabel:
                  overdue ? '已超过起床时间 ${session.overdueLabelAt(now)}' : '已入睡',
              semanticLabel: overdue
                  ? '已睡 ${session.elapsedLabelAt(now)}，'
                      '已超过起床时间 ${session.overdueLabelAt(now)}'
                  : '已睡 ${session.elapsedLabelAt(now)}',
            ),
          ),
          const SizedBox(height: 22),
        ],
        _BedWakeRow(session: session),
        const SizedBox(height: 12),
        if (!drawerOpen) ...[
          _AlarmChip(session: session, now: now),
          const SizedBox(height: 12),
        ],
        _SettingsSummary(
          session: session,
          open: drawerOpen,
          onTap: onToggleDrawer,
        ),
        if (drawerOpen) ...[
          const SizedBox(height: 14),
          SessionDrawer(session: session),
        ],
        const SizedBox(height: 22),
        _EndButton(onTap: onFinish),
      ],
    );
  }
}

/// 底部的「结束睡眠」。
///
/// 与详情页的「删除记录」同一观感：玻璃底 + `danger` 色的描边与文字。收合态与
/// 展开态都在——结束会话不该藏在抽屉里。
class _EndButton extends StatelessWidget {
  const _EndButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return GlassSurface(
      borderRadius: BorderRadius.circular(AppRadii.panel),
      borderColor: tokens.danger.withValues(alpha: 0.38),
      semanticLabel: '结束睡眠',
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AppIcons.sun(size: 17, color: tokens.danger, strokeWidth: 1.9),
          const SizedBox(width: 8),
          Text(
            '结束睡眠',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: tokens.danger,
            ),
          ),
        ],
      ),
    );
  }
}

/// 时长越界时的说明层。
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
    final tokens = AppTokens.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        AppHaptics.tap();
        onTap();
      },
      child: Container(
        constraints: const BoxConstraints(minHeight: 36),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: tokens.material,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          border: Border.all(color: tokens.glassBorder),
        ),
        alignment: Alignment.center,
        child: Text(
          '收起',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: tokens.accent,
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

/// `入睡 23:14 ─────── 闹钟 07:00`。
///
/// **收合态就必须看得见**：睡前设完的起床时间若藏在抽屉里，等于设完就再也
/// 看不到自己设了什么。
class _BedWakeRow extends StatelessWidget {
  const _BedWakeRow({required this.session});

  final SleepSession session;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final start = session.startAtUtc.toLocal();
    final hour = session.wakeMinutes ~/ 60;
    final minute = session.wakeMinutes % 60;

    return GlassSurface(
      borderRadius: BorderRadius.circular(AppRadii.panel),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          _TimeColumn(label: '入睡', value: _hhmm(start), color: tokens.accent),
          Expanded(
            child: Container(
              height: 1,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              color: tokens.border,
            ),
          ),
          _TimeColumn(
            label: '闹钟',
            value: '${hour.toString().padLeft(2, '0')}:'
                '${minute.toString().padLeft(2, '0')}',
            color: tokens.accentViolet,
            alignEnd: true,
          ),
        ],
      ),
    );
  }

  static String _hhmm(DateTime local) =>
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

class _TimeColumn extends StatelessWidget {
  const _TimeColumn({
    required this.label,
    required this.value,
    required this.color,
    this.alignEnd = false,
  });

  final String label;
  final String value;
  final Color color;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: tokens.textMuted)),
        const SizedBox(height: 2),
        Text(
          value,
          style: AppTheme.num(context,
              size: 15, weight: FontWeight.w700, color: color),
        ),
      ],
    );
  }
}

/// 闹钟状态胶囊。开着报剩余时间，关着说明自然醒后手动结束。
class _AlarmChip extends StatelessWidget {
  const _AlarmChip({required this.session, required this.now});

  final SleepSession session;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final on = session.alarmEnabled;

    final remaining = session.plannedDuration - session.elapsedAt(now);
    final minutes = remaining.inMinutes < 0 ? 0 : remaining.inMinutes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: on ? tokens.accentSoft : tokens.bgMuted,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              AppIcons.timer(
                size: 15,
                color: on ? tokens.accent : tokens.textMuted,
                strokeWidth: 1.8,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  on
                      ? '起床闹钟已开 · 还有 ${minutes ~/ 60}h ${minutes % 60}m'
                      : '闹钟已关 · 自然醒后手动结束',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: on ? tokens.accent : tokens.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (on) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppIcons.volume(
                  size: 13, color: tokens.textMuted, strokeWidth: 1.6),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  // 与抽屉里那一行引用同一份字面量——两边各写一遍，
                  // 迟早有一处在该说话的时候不说。
                  ReminderScheduler.wakeAlarmDeliveryNote,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.45,
                    color: tokens.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// 收合态底部那条摘要，同时也是设定抽屉的把手。
///
/// **点它打开**，不做纯上拉手势——躺着的时候拖拽不好使（规格 §四）。
/// 它始终留在页面上：展开后点同一条即可收起，脚下的「入睡 ─── 闹钟」不会跟着消失。
class _SettingsSummary extends StatelessWidget {
  const _SettingsSummary({
    required this.session,
    required this.open,
    required this.onTap,
  });

  final SleepSession session;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final percent = (session.noiseVolume * 100).round();

    return GlassSurface(
      borderRadius: BorderRadius.circular(AppRadii.panel),
      onTap: onTap,
      semanticLabel: open ? '收起今晚的设定' : '展开今晚的设定',
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 抽屉把手。
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: tokens.borderStrong,
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              AppIcons.volume(size: 16, color: tokens.accent, strokeWidth: 1.7),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '白噪音 · 音量 $percent%',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: tokens.textPrimary,
                  ),
                ),
              ),
              Text(
                open ? '收起' : '调整',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: tokens.accent,
                ),
              ),
              const SizedBox(width: 4),
              (open ? AppIcons.chevronDown : AppIcons.chevronUp)(
                size: 16,
                color: tokens.textMuted,
                strokeWidth: 2,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
