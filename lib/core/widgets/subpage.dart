import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../platform/haptics.dart';
import '../theme/app_tokens.dart';
import 'atmosphere.dart';

/// Shared chrome for a page pushed **over** the tab shell: a back pill, the page
/// title, and a scrolling content column.
///
/// A pushed route inherits nothing. It has no [Scaffold], so it has no
/// background and no [Material] ancestor; it has no shell padding; and it has no
/// atmosphere gradient. All four have to come from here:
///
///  * no background → the page paints on bare black;
///  * no `Material` ancestor → every [Text] falls back to Flutter's error style,
///    which renders as a **yellow double underline**;
///  * no padding → content jams against the screen edges and the status bar.
///
/// Every page reached by a push goes through here so that stays in one place.
class Subpage extends StatelessWidget {
  const Subpage({
    super.key,
    required this.title,
    required this.children,
    this.backLabel = '返回',
  });

  final String title;
  final List<Widget> children;
  final String backLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    final isWide = MediaQuery.sizeOf(context).width >= kWideLayoutBreakpoint;

    return Atmosphere(
      child: Scaffold(
        // Transparent so the atmosphere shows through; the Scaffold is here for
        // the Material ancestor and the keyboard inset handling, not its colour.
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: _content(context, tokens, isWide),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, AppTokens tokens, bool isWide) {
    final horizontal = isWide ? 52.0 : 16.0;

    return ListView(
      padding: EdgeInsets.fromLTRB(
        horizontal,
        isWide ? 48 : 24,
        horizontal,
        40,
      ),
      children: [
        Row(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                AppHaptics.tap();
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/');
                }
              },
              child: Container(
                constraints: const BoxConstraints(minHeight: 36),
                padding: const EdgeInsets.only(left: 12, right: 16),
                decoration: BoxDecoration(
                  color: tokens.material,
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                  border: Border.all(color: tokens.glassBorder),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF1C2C52).withValues(alpha: 0.10),
                      blurRadius: 7,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // The chevron is drawn inline as the prototype does, so it
                    // keeps its 2.2 stroke and tight 9×15 proportion.
                    SizedBox(
                      width: 9,
                      height: 15,
                      child:
                          CustomPaint(painter: _ChevronPainter(tokens.accent)),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      backLabel,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.375,
                        color: tokens.accent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.6,
                  color: tokens.textPrimary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        ...children,
      ],
    );
  }
}

class _ChevronPainter extends CustomPainter {
  const _ChevronPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // `polyline points="8,1 1,7.5 8,14"` in a 9×15 box.
    final path = Path()
      ..moveTo(8, 1)
      ..lineTo(1, 7.5)
      ..lineTo(8, 14);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_ChevronPainter oldDelegate) => oldDelegate.color != color;
}
