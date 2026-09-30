import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/platform/haptics.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_basics.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/atmosphere.dart';
import '../../../core/widgets/glass_surface.dart';
import '../../sleep/data/session_repository.dart';
import '../../sleep/domain/sleep_session.dart';
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
              : _SessionBody(session: session, now: _now),
        ),
      ),
    );
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
  const _SessionBody({required this.session, required this.now});

  final SleepSession session;
  final DateTime now;

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
        _BedWakeRow(session: session),
        const SizedBox(height: 12),
        _AlarmChip(session: session, now: now),
      ],
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
                  '由系统通知投递；休眠模式下可能晚几分钟，强度不如系统闹钟。',
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
