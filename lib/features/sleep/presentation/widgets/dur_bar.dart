import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';
import 'stage_style.dart';

/// `DurBar` — a slim progress bar for a duration against a maximum, coloured by
/// the shared duration cue. Used under the sleep-goal stepper in Settings.
class DurBar extends StatelessWidget {
  const DurBar({
    super.key,
    required this.duration,
    this.max = 10,
    this.height = 6,
  });

  final double duration;
  final double max;
  final double height;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final fraction = max <= 0 ? 0.0 : (duration / max).clamp(0.0, 1.0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.pill),
      child: SizedBox(
        height: height,
        // `StackFit.expand` is load-bearing. With the default loose fit the
        // Stack sizes itself to its only non-positioned child — the fractional
        // fill — so the whole track came out `fraction` wide and was then
        // centred by the enclosing Column, which read as a bar growing out of
        // the middle.
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: tokens.border),
            Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: fraction,
                child: AnimatedContainer(
                  duration: AppDurations.standard,
                  curve: AppMotion.standardCurve,
                  decoration: BoxDecoration(
                    color: durationBandColor(tokens, duration),
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
