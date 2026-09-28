import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../domain/sleep_stage.dart';
import 'stage_style.dart';

/// Which height profile a hypnogram uses.
///
/// The prototype carries two slightly different `hm` maps: the detail sheet
/// uses `{awake:10, light:35, deep:80, rem:58}`, the Home hero uses
/// `{awake:10, light:40, deep:100, rem:70}`. Both are kept so each surface
/// matches its own reference.
enum StageBarProfile {
  detail({
    SleepStageType.awake: 10,
    SleepStageType.light: 35,
    SleepStageType.deep: 80,
    SleepStageType.rem: 58
  }),
  hero({
    SleepStageType.awake: 10,
    SleepStageType.light: 40,
    SleepStageType.deep: 100,
    SleepStageType.rem: 70
  });

  const StageBarProfile(this.weights);

  final Map<SleepStageType, double> weights;
}

/// A hypnogram: one bar per segment, width by duration, height by stage.
///
/// Renders nothing when the record has no measured stages — the design has no
/// "assume a normal night" fallback, and the spec forbids inventing stages.
class StageBarChart extends StatelessWidget {
  const StageBarChart({
    super.key,
    required this.stages,
    this.height = 56,
    this.profile = StageBarProfile.detail,
    this.legend = false,
    this.caption,
    this.barRadius = 2,
    this.gap = 1,
  });

  final List<SleepStageSegment> stages;
  final double height;
  final StageBarProfile profile;
  final bool legend;
  final String? caption;
  final double barRadius;
  final double gap;

  bool get _hasAwake =>
      stages.any((segment) => segment.stage == SleepStageType.awake);

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final total = stages.fold<int>(0, (sum, segment) => sum + segment.minutes);
    if (total <= 0) return const SizedBox.shrink();

    final present = SleepStageType.charted
        .where((stage) => stages.any((segment) => segment.stage == stage))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < stages.length; i++) ...[
                if (i > 0) SizedBox(width: gap),
                Expanded(
                  flex: stages[i].minutes,
                  child: FractionallySizedBox(
                    alignment: Alignment.bottomCenter,
                    heightFactor:
                        (profile.weights[stages[i].stage] ?? 50) / 100,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: stageColor(tokens, stages[i].stage)
                            .withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(barRadius),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (legend && present.isNotEmpty) ...[
          const SizedBox(height: 12),
          StageLegend(stages: stages, includeAwake: _hasAwake),
        ],
        if (caption != null) ...[
          const SizedBox(height: 12),
          Text(
            caption!,
            style: TextStyle(
              fontSize: 12,
              color: tokens.textMuted,
              fontFeatures: AppTheme.tabular,
            ),
          ),
        ],
      ],
    );
  }
}

/// Swatch, label and total minutes for each stage present in [stages].
class StageLegend extends StatelessWidget {
  const StageLegend({
    super.key,
    required this.stages,
    this.includeAwake = false,
    this.style = StageLegendStyle.plain,
  });

  final List<SleepStageSegment> stages;
  final bool includeAwake;

  /// `plain` matches the detail sheet (muted label + secondary minutes);
  /// `labelled` matches the Home record cards.
  final StageLegendStyle style;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final totals = stageTotals(stages);

    final stagesToShow = [
      if (includeAwake) SleepStageType.awake,
      ...SleepStageType.charted,
    ].where((stage) => (totals[stage] ?? 0) > 0).toList();

    if (stagesToShow.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: style == StageLegendStyle.labelled ? 12 : 16,
      runSpacing: 6,
      children: [
        for (final stage in stagesToShow)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: stageColor(tokens, stage),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                stage.label,
                style: TextStyle(fontSize: 12, color: tokens.textMuted),
              ),
              const SizedBox(width: 4),
              Text(
                formatStageMinutes(totals[stage] ?? 0),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: tokens.textSecondary,
                  fontFeatures: AppTheme.tabular,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

enum StageLegendStyle { plain, labelled }

/// `StageRibbon` — the full-height multi-colour pill on a record card: each
/// segment takes width proportional to its duration, with only the outer ends
/// rounded.
class StageRibbon extends StatelessWidget {
  const StageRibbon({
    super.key,
    required this.stages,
    this.height = 6,
    this.gap = 1.5,
    this.opacity = 0.88,
  });

  final List<SleepStageSegment> stages;
  final double height;
  final double gap;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final total = stages.fold<int>(0, (sum, segment) => sum + segment.minutes);
    if (total <= 0) return const SizedBox.shrink();

    const pill = Radius.circular(AppRadii.pill);

    return SizedBox(
      height: height,
      child: Row(
        children: [
          for (var i = 0; i < stages.length; i++) ...[
            if (i > 0) SizedBox(width: gap),
            Expanded(
              flex: stages[i].minutes,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: stageColor(tokens, stages[i].stage)
                      .withValues(alpha: opacity),
                  borderRadius: BorderRadius.horizontal(
                    left: i == 0 ? pill : Radius.zero,
                    right: i == stages.length - 1 ? pill : Radius.zero,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
