import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/platform/haptics.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_basics.dart';

enum _OnboardingScene { journal, sound, trend }

class _Slide {
  const _Slide({
    required this.scene,
    required this.title,
    required this.body,
  });

  final _OnboardingScene scene;
  final String title;
  final String body;
}

const _slides = [
  _Slide(
    scene: _OnboardingScene.journal,
    title: '记录你的每一夜',
    body: '花一分钟记下入睡与起床时间、感受和梦境，「夜深」就能帮你建立专属的睡眠规律。',
  ),
  _Slide(
    scene: _OnboardingScene.sound,
    title: '聆听夜间的声音',
    body: '开启夜间录音后，自动检测打鼾与梦话，并生成可回放的片段与睡眠洞察。',
  ),
  _Slide(
    scene: _OnboardingScene.trend,
    title: '看见长期的趋势',
    body: '深睡、浅睡、REM 与评分随时间可视化，让你的作息改善有据可依。',
  ),
];

/// First-run introduction. The three scenes mirror the latest design source.
class OnboardingOverlay extends StatefulWidget {
  const OnboardingOverlay({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<OnboardingOverlay> createState() => _OnboardingOverlayState();
}

class _OnboardingOverlayState extends State<OnboardingOverlay> {
  int _step = 0;

  bool get _isLast => _step == _slides.length - 1;

  void _next() {
    AppHaptics.select();
    if (_isLast) {
      widget.onDone();
    } else {
      setState(() => _step++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final padding = MediaQuery.paddingOf(context);
    final slide = _slides[_step];

    return Positioned.fill(
      child: ColoredBox(
        color: tokens.bgBase,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            padding.left + 24,
            (padding.top > 24 ? padding.top : 24) + 8,
            padding.right + 24,
            padding.bottom + 24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: Pressable(
                  haptic: false,
                  onTap: () {
                    AppHaptics.select();
                    widget.onDone();
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      '跳过',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: tokens.textMuted,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: AnimatedSwitcher(
                      duration: AppDurations.selection,
                      switchInCurve: AppMotion.standardCurve,
                      child: Column(
                        key: ValueKey(_step),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 340),
                            child: OnboardingArtwork(scene: slide.scene),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            slide.title,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.78,
                              color: tokens.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 352),
                            child: Text(
                              slide.body,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 15,
                                height: 1.55,
                                color: tokens.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _slides.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      width: i == _step ? 22 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: i == _step ? tokens.accent : tokens.borderStrong,
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 20),
              PrimaryAction(
                label: _isLast ? '开始使用' : '下一步',
                onTap: _next,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class OnboardingArtwork extends StatelessWidget {
  const OnboardingArtwork({super.key, required this.scene});

  final Object scene;

  @override
  Widget build(BuildContext context) {
    final resolved = switch (scene) {
      _OnboardingScene.journal => _OnboardingScene.journal,
      _OnboardingScene.sound => _OnboardingScene.sound,
      _OnboardingScene.trend => _OnboardingScene.trend,
      _ => _OnboardingScene.journal,
    };
    return AspectRatio(
      aspectRatio: 320 / 260,
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: 320,
          height: 260,
          child: switch (resolved) {
            _OnboardingScene.journal => const _JournalArt(),
            _OnboardingScene.sound => const _SoundArt(),
            _OnboardingScene.trend => const _TrendArt(),
          },
        ),
      ),
    );
  }
}

class _ArtBackdrop extends StatelessWidget {
  const _ArtBackdrop({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, 0.45),
                radius: 0.48,
                colors: [
                  tokens.accentSoft.withValues(alpha: 0.78),
                  tokens.accentSoft.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: 18,
          right: 18,
          top: 8,
          bottom: 8,
          child: CustomPaint(
            painter: _OrbitPainter(tokens.borderStrong),
          ),
        ),
        const Positioned(left: 49, top: 54, child: _ArtStar(size: 6)),
        Positioned(
          right: 42,
          top: 66,
          child: _ArtStar(size: 7, color: tokens.accentViolet),
        ),
        Positioned(
          right: 52,
          bottom: 48,
          child: _ArtStar(size: 5, color: tokens.accent),
        ),
        child,
      ],
    );
  }
}

class _JournalArt extends StatelessWidget {
  const _JournalArt();

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return _ArtBackdrop(
      child: Stack(
        children: [
          Positioned(
            left: 70,
            top: 56,
            width: 190,
            height: 160,
            child: Container(
              decoration: BoxDecoration(
                color: tokens.textPrimary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(30),
              ),
            ),
          ),
          Positioned(
            left: 58,
            top: 44,
            width: 190,
            height: 160,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [tokens.accent, tokens.accentViolet],
                ),
              ),
            ),
          ),
          Positioned(
            left: 79,
            top: 116,
            width: 148,
            height: 106,
            child: Container(
              padding: const EdgeInsets.fromLTRB(22, 27, 20, 18),
              decoration: BoxDecoration(
                color: tokens.bgCardSolid,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _PaperLine(width: 82, color: tokens.accent),
                  const SizedBox(height: 13),
                  _PaperLine(width: 102, color: tokens.borderStrong),
                  const SizedBox(height: 13),
                  _PaperLine(width: 58, color: tokens.borderStrong),
                ],
              ),
            ),
          ),
          Positioned(
            left: 80,
            top: 58,
            width: 36,
            height: 36,
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: tokens.bgCardSolid,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.white.withValues(alpha: 0.35),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 12,
                  top: 1,
                  width: 35,
                  height: 35,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: tokens.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 182,
            top: 171,
            width: 50,
            height: 50,
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tokens.good,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: tokens.good.withValues(alpha: 0.28),
                    blurRadius: 14,
                    offset: const Offset(0, 7),
                  ),
                ],
              ),
              child: const CustomPaint(
                size: Size(23, 23),
                painter: _CheckPainter(Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SoundArt extends StatelessWidget {
  const _SoundArt();

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    const bars = [18.0, 30.0, 46.0, 26.0, 38.0, 22.0, 12.0];
    return _ArtBackdrop(
      child: Stack(
        children: [
          Positioned(
            left: 66,
            top: 60,
            width: 198,
            height: 150,
            child: Container(
              decoration: BoxDecoration(
                color: tokens.textPrimary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(42),
              ),
            ),
          ),
          Positioned(
            left: 56,
            top: 50,
            width: 198,
            height: 150,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(42),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [tokens.accentViolet, tokens.accent],
                ),
              ),
            ),
          ),
          Positioned(
            left: 78,
            top: 151,
            width: 154,
            height: 70,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.92),
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(28),
                  top: Radius.circular(28),
                ),
              ),
            ),
          ),
          Positioned(
            left: 104,
            top: 154,
            width: 128,
            height: 58,
            child: Container(
              decoration: BoxDecoration(
                color: tokens.accent.withValues(alpha: 0.18),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(36),
                  bottom: Radius.circular(22),
                ),
              ),
            ),
          ),
          const Positioned(
            left: 109,
            top: 102,
            width: 54,
            height: 54,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color(0xFFFFD9C9),
                shape: BoxShape.circle,
              ),
            ),
          ),
          const Positioned(
            left: 109,
            top: 100,
            width: 54,
            height: 25,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color(0xFF6D5D7E),
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(30),
                  bottom: Radius.circular(16),
                ),
              ),
            ),
          ),
          Positioned(
            left: 93,
            top: 211,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                for (var i = 0; i < bars.length; i++) ...[
                  if (i > 0) const SizedBox(width: 7),
                  Container(
                    width: 8,
                    height: bars[i],
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.86),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Positioned(
            left: 44,
            top: 110,
            child: SizedBox(
              width: 26,
              height: 62,
              child: CustomPaint(
                painter: _WavePainter(
                  color: tokens.accentBlue,
                  mirrored: true,
                ),
              ),
            ),
          ),
          Positioned(
            right: 40,
            top: 110,
            child: SizedBox(
              width: 26,
              height: 62,
              child: CustomPaint(
                painter: _WavePainter(color: tokens.accentBlue),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendArt extends StatelessWidget {
  const _TrendArt();

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return _ArtBackdrop(
      child: Stack(
        children: [
          Positioned(
            left: 62,
            top: 48,
            width: 204,
            height: 164,
            child: Container(
              decoration: BoxDecoration(
                color: tokens.textPrimary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(34),
              ),
            ),
          ),
          Positioned(
            left: 52,
            top: 38,
            width: 204,
            height: 164,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(34),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [tokens.accent, tokens.accentViolet],
                ),
              ),
              child: Stack(
                children: [
                  Positioned(
                    left: 26,
                    top: 24,
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: tokens.bgCardSolid,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 54,
                    top: 20,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: tokens.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const Positioned(
                    left: 28,
                    right: 24,
                    top: 82,
                    bottom: 26,
                    child: CustomPaint(painter: _TrendPainter()),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 43,
            top: 52,
            width: 76,
            height: 48,
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tokens.bgCardSolid,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: tokens.accent.withValues(alpha: 0.18),
                    blurRadius: 22,
                    offset: const Offset(0, 9),
                  ),
                ],
              ),
              child: Text(
                '92',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: tokens.accent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaperLine extends StatelessWidget {
  const _PaperLine({required this.width, required this.color});

  final double width;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 7,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

class _ArtStar extends StatelessWidget {
  const _ArtStar({required this.size, this.color = const Color(0xFF62C8F2)});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _OrbitPainter extends CustomPainter {
  const _OrbitPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * 0.40;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    const segments = 38;
    for (var i = 0; i < segments; i++) {
      final start = (i * 2 * math.pi / segments) + 0.018;
      const sweep = (2 * math.pi / segments) * 0.48 - 0.018;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        sweep,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_OrbitPainter oldDelegate) => oldDelegate.color != color;
}

class _WavePainter extends CustomPainter {
  const _WavePainter({required this.color, this.mirrored = false});

  final Color color;
  final bool mirrored;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(mirrored ? size.width : 0, 8)
      ..quadraticBezierTo(
        mirrored ? size.width * 0.2 : size.width * 0.8,
        size.height * 0.2,
        mirrored ? size.width * 0.55 : size.width * 0.45,
        size.height * 0.5,
      )
      ..quadraticBezierTo(
        mirrored ? size.width * 0.15 : size.width * 0.85,
        size.height * 0.8,
        mirrored ? size.width : 0,
        size.height - 8,
      );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_WavePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.mirrored != mirrored;
}

class _TrendPainter extends CustomPainter {
  const _TrendPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.16)
      ..strokeWidth = 1;
    for (final fraction in [0.0, 0.5, 1.0]) {
      final y = size.height * fraction;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final points = [
      Offset(0, size.height * 0.74),
      Offset(size.width * 0.22, size.height * 0.52),
      Offset(size.width * 0.40, size.height * 0.61),
      Offset(size.width * 0.61, size.height * 0.25),
      Offset(size.width * 0.79, size.height * 0.40),
      Offset(size.width, size.height * 0.08),
    ];
    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final previous = points[i - 1];
      final point = points[i];
      final midX = (previous.dx + point.dx) / 2;
      line.cubicTo(
        midX,
        previous.dy,
        midX,
        point.dy,
        point.dx,
        point.dy,
      );
    }
    final area = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      area,
      Paint()..color = Colors.white.withValues(alpha: 0.13),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round,
    );
    for (final point in points) {
      canvas.drawCircle(
        point,
        3.2,
        Paint()..color = Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(_TrendPainter oldDelegate) => false;
}

class _CheckPainter extends CustomPainter {
  const _CheckPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * 0.16, size.height * 0.52)
      ..lineTo(size.width * 0.42, size.height * 0.76)
      ..lineTo(size.width * 0.86, size.height * 0.24);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter oldDelegate) => oldDelegate.color != color;
}
