import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// `.liquid-atmosphere` — the page backdrop every screen sits on.
///
/// The glass surfaces are translucent, so this gradient is what they are
/// actually showing through. Any route that does not render it (a pushed
/// sub-page, a sheet host) reads as a flat, wrong-coloured page even though its
/// own widgets are correct.
class Atmosphere extends StatelessWidget {
  const Atmosphere({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(gradient: AppTokens.of(context).atmosphere),
      child: child,
    );
  }
}
