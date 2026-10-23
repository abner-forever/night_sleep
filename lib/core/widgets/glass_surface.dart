import 'package:flutter/material.dart';

import 'quiet_surface.dart';

/// 保留原有调用接口，统一使用新版实体卡片材质。
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
  final double blur;
  final Color? tint;
  final Color? borderColor;
  final List<BoxShadow>? shadow;
  final Clip clipBehavior;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final bool expandWidth;

  @override
  Widget build(BuildContext context) => QuietSurface(
        borderRadius: borderRadius,
        padding: padding,
        margin: margin,
        tint: tint,
        borderColor: borderColor,
        shadow: shadow,
        clipBehavior: clipBehavior,
        onTap: onTap,
        semanticLabel: semanticLabel,
        expandWidth: expandWidth,
        child: child,
      );
}
