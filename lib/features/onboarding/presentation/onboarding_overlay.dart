import 'package:flutter/material.dart';

import '../../../core/platform/haptics.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_basics.dart';
import '../../../core/widgets/app_icons.dart';

/// The three first-run slides.
class _Slide {
  const _Slide({
    required this.icon,
    required this.title,
    required this.body,
  });

  final Widget Function(double size, Color color) icon;
  final String title;
  final String body;
}

const _slides = [
  _Slide(
    icon: _penIcon,
    title: '记录你的每一夜',
    body: '花一分钟记下入睡与起床时间、感受和梦境，「夜深」就能帮你建立专属的睡眠规律。',
  ),
  _Slide(
    icon: _snoreIcon,
    title: '聆听夜间的声音',
    body: '开启夜间录音后，自动检测打鼾与梦话，并生成可回放的片段与睡眠洞察。',
  ),
  _Slide(
    icon: _chartIcon,
    title: '看见长期的趋势',
    body: '深睡、浅睡、REM 与评分随时间可视化，让你的作息改善有据可依。',
  ),
];

Widget _penIcon(double size, Color color) =>
    AppIcons.pen(size: size, color: color, strokeWidth: 1.5);
Widget _snoreIcon(double size, Color color) =>
    AppIcons.snore(size: size, color: color, strokeWidth: 1.5);
Widget _chartIcon(double size, Color color) =>
    AppIcons.chart(size: size, color: color, strokeWidth: 1.5);

/// First-run introduction. Rendered above everything until dismissed; the
/// dismissal is persisted so it appears once per install.
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
    final padding = MediaQuery.of(context).padding;
    final slide = _slides[_step];

    return Positioned.fill(
      child: ColoredBox(
        color: tokens.bgBase,
        child: Padding(
          padding: EdgeInsets.only(
            top: padding.top > 24 ? padding.top : 24,
            bottom: padding.bottom + 24,
            left: 24,
            right: 24,
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
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 360),
                  switchInCurve: AppMotion.standardCurve,
                  child: Column(
                    key: ValueKey(_step),
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 108,
                        height: 108,
                        decoration: BoxDecoration(
                          color: tokens.accentSoft,
                          borderRadius: BorderRadius.circular(32),
                        ),
                        alignment: Alignment.center,
                        child: slide.icon(46, tokens.accent),
                      ),
                      const SizedBox(height: 24),
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
                      const SizedBox(height: 16),
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
                trailing: AppIcons.chevronRight(
                  size: 18,
                  color: Colors.white,
                  strokeWidth: 2.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
