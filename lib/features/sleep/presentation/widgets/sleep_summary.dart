import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../domain/sleep_entry.dart';
import '../../domain/sleep_stage.dart';
import 'stage_style.dart';

class SleepDuration extends StatelessWidget {
  const SleepDuration({super.key, required this.hours, this.size = 38});

  final double hours;
  final double size;

  @override
  Widget build(BuildContext context) {
    final minutes = (hours * 60).round();
    final style = AppTheme.num(context, size: size, weight: FontWeight.w500);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        Text('${minutes ~/ 60}', style: style),
        Text('h ', style: style.copyWith(fontSize: size * .49, height: 1.5)),
        Text('${minutes % 60}', style: style),
        Text('m', style: style.copyWith(fontSize: size * .49, height: 1.5)),
      ],
    );
  }
}

class SleepTimes extends StatelessWidget {
  const SleepTimes({super.key, required this.entry, this.size = 10});

  final SleepEntry entry;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: [
        for (final bedtime in [true, false])
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              bedtime
                  ? AppIcons.bed(size: 12, color: tokens.textSecondary)
                  : AppIcons.sun(size: 12, color: tokens.textSecondary),
              const SizedBox(width: 4),
              Text(
                '${bedtime ? entry.bedtimeLabel : entry.wakeLabel} ${bedtime ? '入睡' : '起床'}',
                style: AppTheme.num(context,
                    size: size,
                    weight: FontWeight.w400,
                    color: tokens.textSecondary),
              ),
            ],
          ),
      ],
    );
  }
}

class SleepStageSummary extends StatelessWidget {
  const SleepStageSummary(
      {super.key, required this.entry, this.horizontal = false});

  final SleepEntry entry;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final total =
        entry.stages.fold<int>(0, (sum, segment) => sum + segment.minutes);
    final stages = [
      ...SleepStageType.charted,
      if (entry.minutesFor(SleepStageType.awake) > 0) SleepStageType.awake,
    ];
    Widget stageRow(SleepStageType stage) {
      final minutes = entry.minutesFor(stage);
      final label = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: stageColor(tokens, stage),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 7),
          Text(stage.label,
              style: TextStyle(fontSize: 12, color: tokens.textSecondary)),
        ],
      );
      final duration = Text(
        total > 0 ? formatStageMinutes(minutes) : '—',
        style: AppTheme.num(context,
            size: horizontal ? 16 : 12,
            weight: FontWeight.w500,
            color: total > 0 ? tokens.accent : tokens.textMuted),
      );
      final percent = Text(
        total > 0 ? '${(minutes / total * 100).round()}%' : '未测量',
        style: AppTheme.num(context,
            size: 11, weight: FontWeight.w400, color: tokens.textMuted),
      );
      return horizontal
          ? Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  label,
                  const SizedBox(height: 7),
                  duration,
                  const SizedBox(height: 7),
                  percent
                ],
              ),
            )
          : Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(children: [
                Expanded(flex: 5, child: label),
                Expanded(flex: 4, child: duration),
                Expanded(flex: 3, child: percent),
              ]),
            );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (total > 0)
          Padding(
            padding: const EdgeInsets.only(top: 20, bottom: 15),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 8,
                child: Row(children: [
                  for (final stage in stages)
                    if (entry.minutesFor(stage) > 0)
                      Expanded(
                        flex: entry.minutesFor(stage),
                        child: ColoredBox(
                          color: stageColor(tokens, stage),
                          child: const SizedBox.expand(),
                        ),
                      ),
                ]),
              ),
            ),
          )
        else
          const SizedBox(height: 16),
        if (horizontal)
          Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: stages.map(stageRow).toList())
        else
          ...stages.map(stageRow),
        if (total == 0)
          Text(
            '这一晚没有睡眠阶段数据。手写记录只有起止时间和主观质量；深睡、浅睡、REM 要等设备测量或导入之后才会显示。',
            style:
                TextStyle(fontSize: 11, height: 1.6, color: tokens.textMuted),
          ),
      ],
    );
  }
}
