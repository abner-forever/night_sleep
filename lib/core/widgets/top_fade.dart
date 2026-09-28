import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// `.ios-top-fade` — the translucent band that fades page content out as it
/// scrolls under the status bar.
///
/// It appears only once the page has actually scrolled past [revealAfter]
/// pixels, animating in over the design's 320ms easing. It is a fixed overlay
/// rather than part of the scroll view, so it must not take hits.
class TopFade extends StatelessWidget {
  const TopFade({
    super.key,
    required this.visible,
    this.height = 144,
  });

  final bool visible;
  final double height;

  /// The design reveals it at `scrollTop > 12`.
  static const double revealAfter = 12;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    return IgnorePointer(
      child: AnimatedSlide(
        duration: AppDurations.standard,
        curve: AppMotion.standardCurve,
        offset: visible ? Offset.zero : const Offset(0, -10 / 144),
        child: AnimatedOpacity(
          duration: AppDurations.standard,
          curve: AppMotion.standardCurve,
          opacity: visible ? 1 : 0,
          child: SizedBox(
            height: height,
            width: double.infinity,
            // The mask wraps the blur, it does not sit inside it.
            //
            // `BackdropFilter` blurs what is painted *behind* it, outside its own
            // subtree — so a `ShaderMask` nested underneath only fades the tint
            // while the blur keeps a hard edge, which reads as a visible seam
            // across the page. Outside, the mask applies to the composited blur.
            //
            // `mask-image: linear-gradient(#000 0%, #000 34%, rgba(0,0,0,.52)
            // 68%, transparent 100%)`, mirroring the design.
            child: ShaderMask(
              shaderCallback: (rect) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black,
                  Colors.black,
                  Color(0x85000000),
                  Colors.transparent,
                ],
                stops: [0.0, 0.34, 0.68, 1.0],
              ).createShader(rect),
              blendMode: BlendMode.dstIn,
              child: ClipRect(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          tokens.bgBase.withValues(alpha: 0.92),
                          tokens.bgBase.withValues(alpha: 0.72),
                          tokens.bgBase.withValues(alpha: 0.32),
                          tokens.bgBase.withValues(alpha: 0),
                        ],
                        stops: const [0.0, 0.38, 0.70, 1.0],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
