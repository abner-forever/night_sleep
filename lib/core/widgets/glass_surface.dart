import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../platform/haptics.dart';
import '../theme/app_tokens.dart';

/// The prototype's `.glass` material: a translucent, blurred surface with a
/// bright inner top edge and a diagonal specular sweep.
///
/// The CSS also applies `saturate(155%)` inside `backdrop-filter`. Flutter's
/// [BackdropFilter] takes a single [ui.ImageFilter], so the saturation boost is
/// approximated with a faint warm-white overlay rather than a second filter
/// stack — visually equivalent here because the surface always sits over the
/// same low-saturation atmosphere gradient.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius,
    this.padding,
    this.margin,
    this.blur = 24,
    this.tint,
    this.borderColor,
    this.shadow,
    this.clipBehavior = Clip.antiAlias,
    this.onTap,
    this.semanticLabel,
    this.expandWidth = true,
  });

  final Widget child;
  final BorderRadiusGeometry? borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  /// Backdrop blur radius (`blur(24px)` on cards, `blur(38px)` on sheets).
  final double blur;

  /// Overrides the material fill; used for accent-tinted panels.
  final Color? tint;
  final Color? borderColor;
  final List<BoxShadow>? shadow;
  final Clip clipBehavior;
  final VoidCallback? onTap;
  final String? semanticLabel;

  /// Fills the available width instead of hugging its content.
  ///
  /// On by default because a card in a vertical column is a block: without it
  /// the surface sizes to whatever the content happens to measure — the Stack
  /// takes its size from its single non-positioned child — so a card holding
  /// only a centred icon and two short lines collapses to the width of its text
  /// and sits against the left edge. Content that expands on its own (a `Row`
  /// with an `Expanded`, a stretched `Column`) hid this, which is why only some
  /// cards looked wrong.
  final bool expandWidth;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final radius = borderRadius ?? BorderRadius.circular(AppRadii.card);

    // The shadow lives OUTSIDE the clip. A `boxShadow` declared on the same
    // box that is being clipped away by its own `ClipRRect` is silently
    // discarded, which is what flattened every card in the app.
    Widget surface = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: shadow ?? tokens.surfaceShadow,
      ),
      child: ClipRRect(
        borderRadius: radius,
        clipBehavior: clipBehavior,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            decoration: BoxDecoration(
              color: tint ?? tokens.material,
              borderRadius: radius,
            ),
            // The border is a `foregroundDecoration` so it paints *above* the
            // specular highlight below. Painted underneath, the highlight eats
            // the top edge and a tinted border looks cut off.
            foregroundDecoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: borderColor ?? tokens.glassBorder),
            ),
            child: Stack(
              children: [
                // `inset 0 1px 0 var(--ios-specular)` — the lit top edge.
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          tokens.specular,
                          tokens.specular.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
                // `::before` — the 115° specular sweep across the face.
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: radius,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white.withValues(alpha: 0.12),
                            Colors.transparent,
                            Colors.transparent,
                            Colors.white.withValues(alpha: 0.04),
                          ],
                          stops: const [0.0, 0.26, 0.72, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),
                // A Material ancestor is required by text fields and ink
                // effects. Supplying a transparent one here means any
                // GlassSurface can host an input (the notes field, the API-key
                // field) without every caller having to remember to wrap it.
                Material(
                  type: MaterialType.transparency,
                  child: Padding(
                    padding: padding ?? EdgeInsets.zero,
                    child: child,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (onTap != null) {
      surface = _TappableSurface(
        onTap: onTap!,
        semanticLabel: semanticLabel,
        child: surface,
      );
    } else if (semanticLabel != null) {
      surface =
          Semantics(label: semanticLabel, container: true, child: surface);
    }

    if (expandWidth) {
      // `double.infinity` is clamped to the parent's max width, so this is a
      // no-op inside a tight-width parent and a block-fill everywhere else.
      surface = SizedBox(width: double.infinity, child: surface);
    }

    return margin == null ? surface : Padding(padding: margin!, child: surface);
  }
}

/// Applies the prototype's springy press feedback (`tap-scale:active`) plus the
/// light haptic the design fires on the same interactions.
class _TappableSurface extends StatefulWidget {
  const _TappableSurface({
    required this.child,
    required this.onTap,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback onTap;
  final String? semanticLabel;

  @override
  State<_TappableSurface> createState() => _TappableSurfaceState();
}

class _TappableSurfaceState extends State<_TappableSurface> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.semanticLabel,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: () {
          // Every tappable card in the app routes through here; without this
          // the press had a scale animation but no tactile answer.
          AppHaptics.tap();
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _pressed ? 0.972 : 1,
          duration: const Duration(milliseconds: 180),
          curve: AppMotion.standardCurve,
          child: widget.child,
        ),
      ),
    );
  }
}
