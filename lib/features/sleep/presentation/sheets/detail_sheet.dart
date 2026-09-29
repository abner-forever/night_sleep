import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_toast.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/platform/haptics.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/app_basics.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/widgets/app_sheet.dart';
import '../../../../core/widgets/confirm_dialog.dart';
import '../../data/sleep_repository.dart';
import '../../domain/sleep_entry.dart';
import '../../domain/sleep_stage.dart';
import '../widgets/score_ring.dart';
import '../widgets/stage_chart.dart';
import '../widgets/stage_style.dart';
import 'sound_card.dart';

/// Opens the detail sheet for [entry].
Future<void> showSleepDetailSheet(BuildContext context, SleepEntry entry) {
  return showAppSheet<void>(
    context: context,
    builder: (context) => DetailSheet(entry: entry),
  );
}

/// Everything measured about one night.
///
/// Blocks appear only when they have real content: a night with no hypnogram
/// shows no stage section, and a night with no recording shows the "全程安静"
/// state rather than an empty player.
class DetailSheet extends ConsumerStatefulWidget {
  const DetailSheet({super.key, required this.entry});

  final SleepEntry entry;

  @override
  ConsumerState<DetailSheet> createState() => _DetailSheetState();
}

class _DetailSheetState extends ConsumerState<DetailSheet> {
  String? _expandedClipId;

  /// Demo rows are samples, not the user's own data, and they are the only rows
  /// that carry a measured hypnogram. Editing one would leave a record that is
  /// no longer demo (so 「清除演示数据」 stops matching it) while its stages still
  /// describe the old window — a night that lies about what was measured.
  bool get _isEditable => widget.entry.source != AppConfig.demoSource;

  void _edit() {
    // Captured before the sheet closes, so the push does not depend on a
    // context that is on its way out.
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.push('/log/edit', extra: widget.entry);
  }

  Future<void> _delete() async {
    final confirmed = await showConfirmDialog(
      context,
      title: '删除 ${widget.entry.dateLabel} 的记录？',
      message: '这一晚的睡眠记录、睡眠阶段与声音事件都会被永久删除，此操作无法撤销。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (confirmed != true) return;

    await ref.read(sleepRepositoryProvider).delete(widget.entry.id);
    if (!mounted) return;
    Navigator.of(context).pop();
    ref.read(toastProvider.notifier).show('记录已删除。');
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final entry = widget.entry;
    final score = entry.score;
    final insightText = entry.insightText ?? entry.estimatedSummary;

    return AppSheet(
      scrollable: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Title + score ──────────────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.dateLabel,
                        style: AppTheme.num(
                          context,
                          size: 12,
                          color: tokens.textMuted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '睡眠详情',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.9,
                          color: tokens.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (score != null) ...[
                  const SizedBox(width: 12),
                  ScoreRing(score: score),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '睡眠评分',
                        style: TextStyle(fontSize: 12, color: tokens.textMuted),
                      ),
                      Text(
                        score >= 85
                            ? '优秀'
                            : score >= 70
                                ? '良好'
                                : '一般',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color:
                              score >= 85 ? tokens.accentViolet : tokens.accent,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),

            // ── Bedtime / duration / wake ──────────────────────────────────
            Row(
              children: [
                _StatTile(
                  label: '入睡',
                  value: entry.bedtimeLabel,
                  color: tokens.accent,
                ),
                const SizedBox(width: 8),
                _StatTile(
                  label: '时长',
                  value: _durationLabel(entry),
                  color: tokens.textPrimary,
                ),
                const SizedBox(width: 8),
                _StatTile(
                  label: '起床',
                  value: entry.wakeLabel,
                  color: tokens.accentViolet,
                ),
              ],
            ),

            // ── Hypnogram ──────────────────────────────────────────────────
            if (entry.hasStages) ...[
              const SizedBox(height: 16),
              InsetPanel(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '睡眠阶段',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.14,
                        color: tokens.textMuted,
                      ),
                    ),
                    const SizedBox(height: 12),
                    StageBarChart(
                      stages: entry.stages,
                      height: 56,
                      legend: true,
                      caption:
                          '${entry.bedtimeLabel} 入睡 → ${entry.wakeLabel} 起床 · 柱高代表睡眠阶段',
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        for (final stage in SleepStageType.charted) ...[
                          Expanded(
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: tokens.bgCard,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    stage.label,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: tokens.textMuted,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${entry.stagePercent(stage)}%',
                                    style: AppTheme.num(
                                      context,
                                      size: 18,
                                      weight: FontWeight.w700,
                                      color: stageColor(tokens, stage),
                                    ),
                                  ),
                                  Text(
                                    '${entry.minutesFor(stage)}m',
                                    style: AppTheme.num(
                                      context,
                                      size: 12,
                                      color: tokens.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],

            // ── Sound events ───────────────────────────────────────────────
            const SizedBox(height: 16),
            Text(
              entry.hasSoundEvents
                  ? '声音记录 · ${entry.soundClips.length}条'
                  : '声音记录 · 无异常',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.14,
                color: tokens.textMuted,
              ),
            ),
            const SizedBox(height: 12),
            if (!entry.hasSoundEvents)
              InsetPanel(
                child: Row(
                  children: [
                    AppIcons.moon(
                        size: 22, color: tokens.textMuted, strokeWidth: 1.5),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '全程安静，无异常声音',
                        style: TextStyle(fontSize: 14, color: tokens.textMuted),
                      ),
                    ),
                  ],
                ),
              )
            else
              for (final clip in entry.soundClips) ...[
                SoundCard(
                  clip: clip,
                  expanded: _expandedClipId == clip.id,
                  onToggle: () => setState(
                    () => _expandedClipId =
                        _expandedClipId == clip.id ? null : clip.id,
                  ),
                ),
                const SizedBox(height: 8),
              ],

            // ── Insight ────────────────────────────────────────────────────
            if (insightText != null) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: tokens.accentSoft,
                  borderRadius: BorderRadius.circular(AppRadii.panel),
                  border:
                      Border.all(color: tokens.accent.withValues(alpha: 0.19)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        AppIcons.ai(
                            size: 15, color: tokens.accent, strokeWidth: 1.8),
                        const SizedBox(width: 8),
                        Text(
                          '睡眠洞察',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: tokens.accent,
                          ),
                        ),
                        if (entry.isEstimated) ...[
                          const SizedBox(width: 8),
                          Tag(
                            label: '本地估算',
                            background: tokens.bgMuted,
                            foreground: tokens.textMuted,
                            fontSize: 12,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      insightText,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: tokens.textSecondary,
                      ),
                    ),
                    if (entry.isEstimated) ...[
                      const SizedBox(height: 10),
                      Text(
                        '该评分为本地规则估算，不构成医疗建议。',
                        style: TextStyle(fontSize: 12, color: tokens.textMuted),
                      ),
                    ],
                  ],
                ),
              ),
            ],

            // ── Notes ──────────────────────────────────────────────────────
            if (entry.notes.trim().isNotEmpty) ...[
              const SizedBox(height: 16),
              InsetPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '备注',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: tokens.textMuted,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      entry.notes,
                      style: TextStyle(
                        fontSize: 14,
                        fontStyle: FontStyle.italic,
                        height: 1.5,
                        color: tokens.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // ── Actions ────────────────────────────────────────────────────
            const SizedBox(height: 24),
            if (_isEditable)
              Row(
                children: [
                  Expanded(
                    child: _SheetAction(
                      label: '编辑记录',
                      icon: AppIcons.pen(
                          size: 16, color: tokens.accent, strokeWidth: 2),
                      foreground: tokens.accent,
                      background: tokens.accentSoft,
                      onTap: _edit,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    // No glyph: the design's 24-icon set has no bin, and drawing
                    // one to fill the slot would be inventing iconography that
                    // the rest of the app does not share.
                    child: _SheetAction(
                      label: '删除记录',
                      foreground: tokens.danger,
                      background: tokens.danger.withValues(alpha: 0.12),
                      onTap: _delete,
                    ),
                  ),
                ],
              )
            else
              InsetPanel(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppIcons.sparkle(
                        size: 16, color: tokens.textMuted, strokeWidth: 1.8),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '这是演示数据，不能编辑或删除。可在「设置 › 演示数据」中一次性清除。',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: tokens.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _durationLabel(SleepEntry entry) {
    final hours = entry.durationHours.floor();
    final minutes = ((entry.durationHours - hours) * 60).round();
    return '${hours}h ${minutes}m';
  }
}

/// A full-width action button in the detail sheet's footer.
class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.label,
    required this.foreground,
    required this.background,
    required this.onTap,
    this.icon,
  });

  final String label;
  final Color foreground;
  final Color background;
  final VoidCallback onTap;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: () {
        AppHaptics.tap();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppRadii.panel),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              IconTheme.merge(
                data: IconThemeData(color: foreground),
                child: icon!,
              ),
              const SizedBox(width: 7),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: tokens.bgMuted,
          borderRadius: BorderRadius.circular(AppRadii.panel),
        ),
        child: Column(
          children: [
            Text(label,
                style: TextStyle(fontSize: 12, color: tokens.textMuted)),
            const SizedBox(height: 4),
            Text(
              value,
              style: AppTheme.num(context,
                  size: 17, weight: FontWeight.w700, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
