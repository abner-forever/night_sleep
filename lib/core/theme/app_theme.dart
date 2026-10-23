import 'package:flutter/material.dart';

import 'app_tokens.dart';

/// Builds the app's [ThemeData] from [AppTokens].
///
/// The prototype is an iOS-native design rendered in CSS, so typography leans
/// on the platform system font (SF Pro / PingFang SC on Apple platforms)
/// instead of bundling a family. Numerals opt into tabular figures to match the
/// prototype's `.num` class, which keeps clock digits and metrics from jittering
/// as values change.
abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light, AppTokens.light);

  static ThemeData dark() => _build(Brightness.dark, AppTokens.dark);

  static ThemeData _build(Brightness brightness, AppTokens tokens) {
    final base = ThemeData(brightness: brightness, useMaterial3: true);
    final text = _textTheme(tokens);

    return base.copyWith(
      extensions: [tokens],
      scaffoldBackgroundColor: tokens.bgBase,
      canvasColor: tokens.bgBase,
      colorScheme: base.colorScheme.copyWith(
        brightness: brightness,
        primary: tokens.accent,
        onPrimary: Colors.white,
        secondary: tokens.accentViolet,
        surface: tokens.bgCardSolid,
        onSurface: tokens.textPrimary,
        error: tokens.danger,
        outline: tokens.border,
      ),
      textTheme: text,
      primaryTextTheme: text,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      // The prototype fades the top of the scroll content instead of drawing a
      // hard divider under the header.
      appBarTheme: AppBarTheme(
        toolbarHeight: kSubpageNavigationHeight,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        foregroundColor: tokens.textPrimary,
      ),
      dividerTheme: DividerThemeData(
        color: tokens.border,
        thickness: 0.5,
        space: 0.5,
      ),
      // Dialogs are replaced by bottom sheets throughout, but a sane default
      // keeps any future dialog legible.
      dialogTheme: DialogThemeData(
        backgroundColor: tokens.sheetBg,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.sheet),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: tokens.sheetBg,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadii.sheet),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: tokens.bgCardSolid,
        contentTextStyle: text.bodyMedium?.copyWith(
          color: tokens.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        behavior: SnackBarBehavior.floating,
        shape: const StadiumBorder(),
        elevation: 0,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: tokens.accent,
        selectionColor: tokens.accentSoft,
        selectionHandleColor: tokens.accent,
      ),
    );
  }

  /// `tabular-nums` + tight tracking, mirroring the prototype's `.num` class.
  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];

  static TextStyle num(
    BuildContext context, {
    double size = 14,
    FontWeight weight = FontWeight.w600,
    Color? color,
    double letterSpacing = -0.02,
  }) {
    final tokens = AppTokens.of(context);
    return TextStyle(
      fontSize: size,
      fontWeight: weight,
      color: color ?? tokens.textPrimary,
      letterSpacing: letterSpacing,
      fontFeatures: tabular,
      height: 1.1,
    );
  }

  static TextTheme _textTheme(AppTokens tokens) {
    TextStyle t(
      double size,
      FontWeight weight, {
      double spacing = -0.02,
      double height = 1.3,
      Color? color,
    }) =>
        TextStyle(
          fontSize: size,
          fontWeight: weight,
          letterSpacing: spacing,
          height: height,
          color: color ?? tokens.textPrimary,
        );

    return TextTheme(
      displaySmall: t(29, FontWeight.w700, spacing: -0.8, height: 1.2),
      headlineMedium: t(28, FontWeight.w600, spacing: -0.7, height: 1.2),
      headlineSmall: t(20, FontWeight.w700, spacing: -0.5),
      titleLarge: t(17, FontWeight.w700, spacing: -0.4),
      titleMedium: t(15, FontWeight.w600, spacing: -0.2),
      titleSmall: t(14, FontWeight.w600, spacing: -0.15),
      bodyLarge: t(16, FontWeight.w400, spacing: -0.2, height: 1.45),
      bodyMedium: t(14, FontWeight.w400, spacing: -0.1, height: 1.45),
      bodySmall: t(12, FontWeight.w400,
          spacing: 0, height: 1.4, color: tokens.textMuted),
      labelLarge: t(15, FontWeight.w600, spacing: -0.3),
      labelMedium: t(12, FontWeight.w600, spacing: 0.1),
      // Section headers in the prototype are 12px, semibold, .08em tracking.
      labelSmall:
          t(12, FontWeight.w600, spacing: 0.96, color: tokens.textMuted),
    );
  }
}
