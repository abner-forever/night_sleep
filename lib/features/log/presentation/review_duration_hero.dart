import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/hero_surface.dart';

/// 回顾与手动补录共用的时长概览，使用新版实体面板和轻渐变。
class ReviewDurationHero extends StatelessWidget {
  const ReviewDurationHero({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.onTap,
    this.semanticLabel,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return HeroSurface(
      borderRadius: BorderRadius.circular(AppRadii.card),
      borderColor: tokens.glassBorder,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [tokens.bgCard, tokens.bgRaised],
      ),
      shadow: const [],
      padding: padding,
      onTap: onTap,
      semanticLabel: semanticLabel,
      child: child,
    );
  }
}
