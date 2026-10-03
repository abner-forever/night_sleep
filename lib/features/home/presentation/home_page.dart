import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_shell.dart';
import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_basics.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/glass_surface.dart';
import '../../sleep/data/session_repository.dart';
import '../../sleep/data/sleep_repository.dart';
import '../../sleep/domain/sleep_entry.dart';
import '../../sleep/domain/sleep_session.dart';
import '../../sleep/domain/sleep_stage.dart';
import '../../sleep/presentation/sheets/detail_sheet.dart';
import '../../sleep/presentation/widgets/moon_arc.dart';
import '../../sleep/presentation/widgets/stage_chart.dart';
import '../../sleep/presentation/widgets/stage_style.dart';

/// 「现在」的读取接缝。
///
/// 默认现读系统时钟；测试把它冻住，好让「已睡 3h 42m」这类读数不随运行测试的
/// 日期漂移——与 `SleepSessionPage.now` 是同一条规则，只是首页是 `ConsumerWidget`，
/// 没有 state 可以放这个字段。
///
/// 返回**函数**而不是时刻：`Provider<DateTime>` 会缓存第一次读到的值，卡片上的
/// 时长就永远停在应用启动那一刻。每次 build 现读一次才是对的。
final homeNowProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Home — sleep overview, the night just gone, and the recent history.
class HomePage extends ConsumerWidget {
  const HomePage({
    super.key,
    required this.animateRing,
    required this.onRingConsumed,
    required this.onOpenNoise,
    required this.onStartSleep,
  });

  final bool animateRing;
  final VoidCallback onRingConsumed;
  final VoidCallback onOpenNoise;

  /// 开始一个新会话：写入会话行并推入会话页。没有会话时主按钮走它。
  final VoidCallback onStartSleep;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(sleepEntriesProvider);
    final session = ref.watch(activeSessionProvider).valueOrNull;
    final now = ref.watch(homeNowProvider)();

    // 外壳不再兜底留白，状态栏留白由页面自己补（见 [pageTopInset]），
    // 所以加载与错误分支也要和数据分支的 ListView 用同一套顶部与横向留白。
    final inset = EdgeInsets.only(
      top: pageTopInset(context),
      left: pageGutter(context),
      right: pageGutter(context),
    );

    return entries.when(
      loading: () => Padding(
        padding: inset,
        child: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, stack) => Padding(
        padding: inset,
        child: EmptyState(
          icon: AppIcons.moon(
              size: 30, color: Theme.of(context).colorScheme.error),
          title: '无法读取记录',
          body: '本地数据库打开失败：$error',
        ),
      ),
      data: (records) => _HomeContent(
        records: records,
        session: session,
        now: now,
        animateRing: animateRing,
        onRingConsumed: onRingConsumed,
        onOpenNoise: onOpenNoise,
        onStartSleep: onStartSleep,
      ),
    );
  }
}

class _HomeContent extends StatelessWidget {
  const _HomeContent({
    required this.records,
    required this.session,
    required this.now,
    required this.animateRing,
    required this.onRingConsumed,
    required this.onOpenNoise,
    required this.onStartSleep,
  });

  final List<SleepEntry> records;
  final SleepSession? session;
  final DateTime now;
  final bool animateRing;
  final VoidCallback onRingConsumed;
  final VoidCallback onOpenNoise;
  final VoidCallback onStartSleep;

  /// Localised `9月27日 星期日`, built by hand so the app does not need to load
  /// the zh_CN date-locale tables at startup.
  static String _todayLine(DateTime now) {
    const weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    return '${now.month}月${now.day}日 ${weekdays[now.weekday - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final today = records.isEmpty ? null : records.first;
    final hasDemoData =
        records.any((entry) => entry.source == AppConfig.demoSource);

    // Mean over the recorded nights only, capped at seven.
    final recent = records.take(7).toList();
    final averageHours = recent.isEmpty
        ? 0.0
        : recent.fold<double>(0, (sum, entry) => sum + entry.durationHours) /
            recent.length;

    if (animateRing) {
      // The reveal is consumed after this build; Home keeps its own snapshot.
      WidgetsBinding.instance.addPostFrameCallback((_) => onRingConsumed());
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(
        pageGutter(context),
        pageTopInset(context),
        pageGutter(context),
        pageBottomInset(context),
      ),
      children: [
        PageHeading(eyebrow: _todayLine(now), title: '睡眠概览'),
        const SizedBox(height: 18),
        if (hasDemoData) ...[
          const _DemoBadge(),
          const SizedBox(height: 12),
        ],
        if (today != null) ...[
          _HeroCard(entry: today, animateRing: animateRing),
          const SizedBox(height: 18),
        ],
        // 会话在跑时不再给「开始入睡」——那会开出第二个会话。主按钮位换成
        // 一张「正在睡眠」卡，点它回到会话页。
        //
        // 文案逐字取自原型首页（「开始入睡」/「开启睡眠记录、鼾声检测与白噪音」），
        // 只有一处例外：副标题**不写「鼾声检测」**——plan A 没接录音，那是我们不能
        // 承诺的能力（偏差 #7 是产品红线），改成白噪音与夜景氛围这两件真做了的事。
        if (session != null)
          _ActiveSessionCard(session: session!, now: now)
        else
          PrimaryAction(
            label: '开始入睡',
            subtitle: '开启睡眠记录、白噪音与夜景氛围',
            trailing:
                AppIcons.moon(size: 20, color: Colors.white, strokeWidth: 2),
            onTap: onStartSleep,
          ),
        // 会话进行中就不再摆空状态：它那句「开始入睡」的号召和上面那张卡
        // 是互相打架的（卡片正说明会话已经在跑），而记录为空是会话刚开始
        // 时的常态。
        if (records.isEmpty && session == null) ...[
          const SizedBox(height: 18),
          EmptyState(
            icon:
                AppIcons.moon(size: 30, color: tokens.accent, strokeWidth: 1.6),
            title: '还没有睡眠记录',
            body: '记下你的第一晚，明早回来就能看到时长、评分与趋势。',
            actionLabel: '开始入睡',
            onAction: onStartSleep,
          ),
        ],
        if (records.isNotEmpty) ...[
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: GlassSurface(
                  borderRadius: BorderRadius.circular(AppRadii.panel),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          AppIcons.moon(
                              size: 14,
                              color: tokens.textMuted,
                              strokeWidth: 1.8),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '近 7 日均时',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.4,
                                color: tokens.textMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            averageHours.toStringAsFixed(1),
                            style: AppTheme.num(context,
                                size: 24, weight: FontWeight.w700),
                          ),
                          Text(
                            'h',
                            style:
                                TextStyle(fontSize: 16, color: tokens.accent),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '推荐 7–9h',
                        style: TextStyle(fontSize: 12, color: tokens.textMuted),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GlassSurface(
                  borderRadius: BorderRadius.circular(AppRadii.panel),
                  padding: const EdgeInsets.all(16),
                  onTap: onOpenNoise,
                  semanticLabel: '助眠音效',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          AppIcons.music(
                              size: 14,
                              color: tokens.textMuted,
                              strokeWidth: 1.8),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '助眠音效',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.4,
                                color: tokens.textMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '白噪音',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: tokens.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '雨声 · 海浪 · 篝火',
                        style: TextStyle(fontSize: 12, color: tokens.textMuted),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const SectionHeader('最近记录'),
          for (final entry in records.take(5)) ...[
            RecordCard(entry: entry),
            const SizedBox(height: 12),
          ],
        ],
      ],
    );
  }
}

/// 会话进行中时占住首页主按钮位的那张卡。
///
/// 它替代「开始入睡」而不是并排放在一起：会话在跑时再给一个开始按钮，等于
/// 允许同时开出两个。卡片本身没有新能力——圆环画的是「已过时长 ÷ 计划时长」，
/// 两个数都是推导的，点它只是回到会话页。
class _ActiveSessionCard extends StatelessWidget {
  const _ActiveSessionCard({required this.session, required this.now});

  final SleepSession session;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final elapsed = session.elapsedLabelAt(now);

    return GlassSurface(
      borderRadius: BorderRadius.circular(AppRadii.panel),
      padding: const EdgeInsets.all(18),
      onTap: () => context.push('/sleep/session'),
      semanticLabel: '正在睡眠，已睡 $elapsed，回到会话页',
      child: Row(
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: session.progressAt(now),
                  strokeWidth: 3,
                  backgroundColor: tokens.border,
                  valueColor: AlwaysStoppedAnimation<Color>(tokens.accent),
                ),
                AppIcons.moon(size: 18, color: tokens.accent, strokeWidth: 1.8),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '正在睡眠',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: tokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '已睡 $elapsed',
                  style: TextStyle(fontSize: 13, color: tokens.textMuted),
                ),
              ],
            ),
          ),
          AppIcons.chevronRight(
              size: 18, color: tokens.textMuted, strokeWidth: 2),
        ],
      ),
    );
  }
}

/// Warns that sample rows are present, so a demo night is never mistaken for a
/// real recording.
class _DemoBadge extends StatelessWidget {
  const _DemoBadge();

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: tokens.bgMuted,
        borderRadius: BorderRadius.circular(AppRadii.panel),
      ),
      child: Row(
        children: [
          AppIcons.sparkle(size: 14, color: tokens.textMuted, strokeWidth: 1.8),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '正在显示演示数据，可在「设置 › 演示数据」中清除。',
              style: TextStyle(fontSize: 12, color: tokens.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

/// The "昨夜睡眠" hero card with the moon dial.
class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.entry, required this.animateRing});

  final SleepEntry entry;
  final bool animateRing;

  String _formatMinutes(int minutes) {
    if (minutes < 60) return '${minutes}m';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return rest == 0 ? '${hours}h' : '${hours}h${rest}m';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final hours = entry.durationHours.floor();
    final minutes = ((entry.durationHours - hours) * 60).round();
    final score = entry.score;

    return GlassSurface(
      borderRadius: BorderRadius.circular(AppRadii.card),
      padding: const EdgeInsets.all(20),
      onTap: () => showSleepDetailSheet(context, entry),
      semanticLabel: '查看昨夜睡眠详情',
      child: Stack(
        children: [
          // `radial-gradient(circle, accent 15%, transparent)` in the corner.
          Positioned(
            top: -40,
            right: -40,
            child: IgnorePointer(
              child: Container(
                width: 176,
                height: 176,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      tokens.accent.withValues(alpha: 0.08),
                      tokens.accent.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AppIcons.moon(
                      size: 13, color: tokens.textMuted, strokeWidth: 1.8),
                  const SizedBox(width: 6),
                  Text(
                    '昨夜睡眠',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.96,
                      color: tokens.textMuted,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '详情',
                    style: TextStyle(fontSize: 12, color: tokens.textMuted),
                  ),
                  AppIcons.chevronRight(
                      size: 14, color: tokens.textMuted, strokeWidth: 2),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  MoonArc(
                    durationHours: entry.durationHours,
                    stages: entry.stages,
                    size: 116,
                    animate: animateRing,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              '$hours',
                              style: AppTheme.num(
                                context,
                                size: 42,
                                weight: FontWeight.w700,
                                letterSpacing: -1.26,
                              ),
                            ),
                            Text(
                              'h ',
                              style:
                                  TextStyle(fontSize: 22, color: tokens.accent),
                            ),
                            Text(
                              '$minutes',
                              style: AppTheme.num(
                                context,
                                size: 42,
                                weight: FontWeight.w700,
                                letterSpacing: -1.26,
                              ),
                            ),
                            Text(
                              'm',
                              style:
                                  TextStyle(fontSize: 22, color: tokens.accent),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (score != null)
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: tokens.accentSoft,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    AppIcons.ai(
                                        size: 11,
                                        color: tokens.accent,
                                        strokeWidth: 2),
                                    const SizedBox(width: 4),
                                    Text(
                                      '$score分',
                                      style: AppTheme.num(
                                        context,
                                        size: 12,
                                        weight: FontWeight.w700,
                                        color: tokens.accent,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  // 「全程安静」把「录过、没听到」与「根本没录」
                                  // 说成同一件事，等于替用户下一个我们没有依据的
                                  // 结论。零片段就只说零片段。
                                  entry.hasSoundEvents
                                      ? '${entry.soundClips.length}条声音'
                                      : '无声音片段',
                                  style: TextStyle(
                                      fontSize: 12, color: tokens.textMuted),
                                ),
                              ),
                            ],
                          ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            AppIcons.bed(
                                size: 12,
                                color: tokens.accent,
                                strokeWidth: 1.8),
                            const SizedBox(width: 4),
                            Text(
                              entry.bedtimeLabel,
                              style: AppTheme.num(
                                context,
                                size: 12,
                                weight: FontWeight.w600,
                                color: tokens.accent,
                              ),
                            ),
                            Expanded(
                              child: Container(
                                height: 1,
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 8),
                                color: tokens.border,
                              ),
                            ),
                            AppIcons.sun(
                              size: 12,
                              color: tokens.accentViolet,
                              strokeWidth: 1.8,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              entry.wakeLabel,
                              style: AppTheme.num(
                                context,
                                size: 12,
                                weight: FontWeight.w600,
                                color: tokens.accentViolet,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (entry.hasStages) ...[
                const SizedBox(height: 20),
                Divider(height: 1, color: tokens.border),
                const SizedBox(height: 16),
                Row(
                  children: [
                    for (final stage in SleepStageType.charted)
                      Expanded(
                        child: _StageStat(
                          stage: stage,
                          value: _formatMinutes(entry.minutesFor(stage)),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                StageBarChart(
                  stages: entry.stages,
                  height: 24,
                  profile: StageBarProfile.hero,
                  gap: 1,
                ),
                const SizedBox(height: 6),
                StageLegend(stages: entry.stages),
              ] else ...[
                // The prototype's card always shows this block, because every
                // record in it carries a hypnogram. A hand-logged night does
                // not, and putting numbers in the three tiles would be
                // presenting a distribution nobody measured. So the block keeps
                // the same shape and says what is missing, rather than
                // vanishing and leaving the card looking half-built.
                const SizedBox(height: 20),
                Divider(height: 1, color: tokens.border),
                const SizedBox(height: 16),
                Row(
                  children: [
                    for (final stage in SleepStageType.charted)
                      Expanded(child: _StageStat(stage: stage, value: '—')),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppIcons.moon(
                        size: 13, color: tokens.textMuted, strokeWidth: 1.8),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '这一晚没有睡眠阶段数据。手写记录只有起止时间和主观质量；'
                        '深睡、浅睡、REM 要等设备测量或导入之后才会显示。',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: tokens.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// One of the three stage totals under the hero dial.
class _StageStat extends StatelessWidget {
  const _StageStat({required this.stage, required this.value});

  final SleepStageType stage;

  /// A formatted duration, or an em dash when nothing was measured.
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final measured = value != '—';
    final color = stageColor(tokens, stage);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 3),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: measured ? color.withValues(alpha: 0.10) : tokens.bgMuted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            stage.label,
            maxLines: 1,
            style: TextStyle(fontSize: 11, color: tokens.textMuted),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            style: AppTheme.num(
              context,
              size: 15,
              weight: FontWeight.w600,
              color: measured ? color : tokens.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// A night in the recent-records list: date, quality, duration, stage ribbon.
class RecordCard extends StatelessWidget {
  const RecordCard({super.key, required this.entry});

  final SleepEntry entry;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final score = entry.score;

    return GlassSurface(
      borderRadius: BorderRadius.circular(AppRadii.card),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      onTap: () => showSleepDetailSheet(context, entry),
      semanticLabel: '查看 ${entry.dateLabel} 的睡眠记录',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          entry.shortDateLabel,
                          style: AppTheme.num(
                            context,
                            size: 14,
                            weight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (entry.quality != null)
                          Tag(label: entry.quality!.label),
                        if (entry.hasSnore) ...[
                          const SizedBox(width: 4),
                          AppIcons.snore(
                              size: 12,
                              color: tokens.accentBlue,
                              strokeWidth: 1.6),
                        ],
                        if (entry.hasTalk) ...[
                          const SizedBox(width: 4),
                          AppIcons.bubble(
                            size: 12,
                            color: tokens.accentViolet,
                            strokeWidth: 1.6,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        AppIcons.bed(
                            size: 11,
                            color: tokens.textMuted,
                            strokeWidth: 1.8),
                        const SizedBox(width: 4),
                        Text(
                          entry.bedtimeLabel,
                          style: AppTheme.num(
                            context,
                            size: 12,
                            color: tokens.textMuted,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            '→',
                            style: TextStyle(
                                fontSize: 12, color: tokens.borderStrong),
                          ),
                        ),
                        AppIcons.sun(
                            size: 11,
                            color: tokens.textMuted,
                            strokeWidth: 1.8),
                        const SizedBox(width: 4),
                        Text(
                          entry.wakeLabel,
                          style: AppTheme.num(
                            context,
                            size: 12,
                            color: tokens.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        entry.durationHours.toStringAsFixed(1),
                        style: AppTheme.num(
                          context,
                          size: 22,
                          weight: FontWeight.w700,
                          color: durationBandColor(tokens, entry.durationHours),
                        ),
                      ),
                      const SizedBox(width: 2),
                      Text(
                        'h',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: tokens.textMuted,
                        ),
                      ),
                    ],
                  ),
                  if (score != null)
                    Text(
                      '${entry.isEstimated ? '估算' : '评分'} $score',
                      style: AppTheme.num(
                        context,
                        size: 12,
                        weight: FontWeight.w600,
                        color: scoreBandColor(tokens, score),
                      ),
                    ),
                ],
              ),
            ],
          ),
          if (entry.hasStages) ...[
            const SizedBox(height: 12),
            StageRibbon(stages: entry.stages),
            const SizedBox(height: 10),
            StageLegend(
              stages: entry.stages,
              style: StageLegendStyle.labelled,
            ),
          ],
        ],
      ),
    );
  }
}
