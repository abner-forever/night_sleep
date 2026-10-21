import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The product icon shared by in-app brand surfaces.
class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    this.size = 40,
    this.cornerRadius = 12,
  });

  static const assetPath = 'assets/branding/app-icon.svg';

  final double size;
  final double cornerRadius;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(cornerRadius),
        child: SvgPicture.asset(
          assetPath,
          fit: BoxFit.cover,
          excludeFromSemantics: true,
        ),
      ),
    );
  }
}
