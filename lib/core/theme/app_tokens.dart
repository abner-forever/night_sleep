import 'package:flutter/material.dart';

/// Design tokens transcribed from the Figma Make prototype (`src/index.css`).
///
/// The prototype carried several generations of styling that override each
/// other; the values below are the *last* declared layer (the `.ios-app` block
/// near the end of `index.css`), which is what the prototype actually renders.
/// Early liquid-glass values (`#edf1fb` / `#101322`, animated orbs) were
/// superseded there and are intentionally not reproduced.
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.bgBase,
    required this.bgCard,
    required this.bgCardSolid,
    required this.bgRaised,
    required this.bgMuted,
    required this.bgInput,
    required this.bgNavbar,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.accent,
    required this.accentSoft,
    required this.accentViolet,
    required this.accentBlue,
    required this.border,
    required this.borderStrong,
    required this.glassBorder,
    required this.sheetBg,
    required this.specular,
    required this.material,
    required this.materialStrong,
    required this.danger,
    required this.warn,
    required this.caution,
    required this.stageDeep,
    required this.stageLight,
    required this.stageRem,
    required this.stageAwake,
    required this.atmosphere,
    required this.primaryActionGradient,
    required this.overlayScrim,
  });

  // ── Backgrounds ────────────────────────────────────────────────────────────
  final Color bgBase;
  final Color bgCard;
  final Color bgCardSolid;
  final Color bgRaised;
  final Color bgMuted;
  final Color bgInput;
  final Color bgNavbar;

  // ── Text ───────────────────────────────────────────────────────────────────
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  // ── Accents ────────────────────────────────────────────────────────────────
  final Color accent;
  final Color accentSoft;
  final Color accentViolet;
  final Color accentBlue;

  // ── Borders & material ─────────────────────────────────────────────────────
  final Color border;
  final Color borderStrong;
  final Color glassBorder;
  final Color sheetBg;

  /// Inner top highlight used by the glass material (`inset 0 1px 0`).
  final Color specular;
  final Color material;
  final Color materialStrong;

  // ── Semantic ───────────────────────────────────────────────────────────────
  final Color danger;
  final Color warn;
  final Color caution;

  // ── Sleep stages ───────────────────────────────────────────────────────────
  final Color stageDeep;
  final Color stageLight;
  final Color stageRem;
  final Color stageAwake;

  // ── Multi-value ────────────────────────────────────────────────────────────
  final Gradient atmosphere;
  final Gradient primaryActionGradient;
  final Color overlayScrim;

  static const light = AppTokens(
    bgBase: Color(0xFFF2F2F7),
    bgCard: Color(0xB8FFFFFF), // rgba(255,255,255,.72)
    bgCardSolid: Color(0xFFFFFFFF),
    bgRaised: Color(0xA8FFFFFF), // rgba(255,255,255,.66)
    bgMuted: Color(0xFFE9E9EF),
    bgInput: Color(0x1F767680), // rgba(118,118,128,.12)
    bgNavbar: Color(0xC7F8F8FA), // rgba(248,248,250,.78)
    textPrimary: Color(0xFF000000),
    textSecondary: Color(0xD13C3C43), // rgba(60,60,67,.82)
    textMuted: Color(0x943C3C43), // rgba(60,60,67,.58)
    accent: Color(0xFF007AFF),
    accentSoft: Color(0x1F007AFF), // rgba(0,122,255,.12)
    accentViolet: Color(0xFF5856D6),
    accentBlue: Color(0xFF5AC8FA),
    border: Color(0x2E3C3C43), // rgba(60,60,67,.18)
    borderStrong: Color(0x473C3C43), // rgba(60,60,67,.28)
    glassBorder: Color(0xA8FFFFFF), // rgba(255,255,255,.66)
    sheetBg: Color(0xE0F9F9FB), // rgba(249,249,251,.88)
    specular: Color(0xB3FFFFFF), // rgba(255,255,255,.70)
    material: Color(0xA8FFFFFF), // rgba(255,255,255,.66)
    materialStrong: Color(0xDBFAFAFC), // rgba(250,250,252,.86)
    danger: Color(0xFFE5484D),
    warn: Color(0xFFE08A3C),
    caution: Color(0xFFC8A93A),
    stageDeep: Color(0xFF5856D6),
    stageLight: Color(0xFF5AC8FA),
    stageRem: Color(0xFFAF52DE),
    stageAwake: Color(0xFFFF3B30),
    atmosphere: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFF6F8FF), Color(0xFFF2F2F7), Color(0xFFF2F2F7)],
      stops: [0.0, 0.42, 1.0],
    ),
    primaryActionGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF0A84FF), Color(0xFF5856D6)],
    ),
    overlayScrim: Color(0x4D000000), // rgba(0,0,0,.30)
  );

  static const dark = AppTokens(
    bgBase: Color(0xFF000000),
    bgCard: Color(0xB31C1C1E), // rgba(28,28,30,.70)
    bgCardSolid: Color(0xFF1C1C1E),
    bgRaised: Color(0xB82C2C2E), // rgba(44,44,46,.72)
    bgMuted: Color(0xFF2C2C2E),
    bgInput: Color(0x3D767680), // rgba(118,118,128,.24)
    bgNavbar: Color(0xC21C1C1E), // rgba(28,28,30,.76)
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xD6EBEBF5), // rgba(235,235,245,.84)
    textMuted: Color(0x8FEBEBF5), // rgba(235,235,245,.56)
    accent: Color(0xFF0A84FF),
    accentSoft: Color(0x330A84FF), // rgba(10,132,255,.20)
    accentViolet: Color(0xFF5E5CE6),
    accentBlue: Color(0xFF64D2FF),
    border: Color(0x8F545458), // rgba(84,84,88,.56)
    borderStrong: Color(0x38EBEBF5), // rgba(235,235,245,.22)
    glassBorder: Color(0x1FFFFFFF), // rgba(255,255,255,.12)
    sheetBg: Color(0xE01D1D1F), // rgba(29,29,31,.88)
    specular: Color(0x1FFFFFFF), // rgba(255,255,255,.12)
    material: Color(0xB81C1C1E), // rgba(28,28,30,.72)
    materialStrong: Color(0xE0242426), // rgba(36,36,38,.88)
    danger: Color(0xFFFF6B6F),
    warn: Color(0xFFF0A35C),
    caution: Color(0xFFDCC55A),
    stageDeep: Color(0xFF5E5CE6),
    stageLight: Color(0xFF64D2FF),
    stageRem: Color(0xFFBF5AF2),
    stageAwake: Color(0xFFFF453A),
    atmosphere: RadialGradient(
      center: Alignment(0, -1.0),
      radius: 1.1,
      colors: [Color(0xFF17233B), Color(0xFF000000)],
      stops: [0.0, 0.66],
    ),
    primaryActionGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF0A84FF), Color(0xFF5856D6)],
    ),
    overlayScrim: Color(0x4D000000),
  );

  static AppTokens of(BuildContext context) =>
      Theme.of(context).extension<AppTokens>() ?? light;

  /// Shadow used by every glass surface (`--ios-shadow`).
  List<BoxShadow> get surfaceShadow => this == dark
      ? const [
          BoxShadow(
              color: Color(0x4D000000), blurRadius: 30, offset: Offset(0, 12))
        ]
      : const [
          BoxShadow(
              color: Color(0x1A202F56), blurRadius: 28, offset: Offset(0, 10))
        ];

  @override
  AppTokens copyWith() => this;

  @override
  AppTokens lerp(ThemeExtension<AppTokens>? other, double t) {
    if (other is! AppTokens) return this;
    return t < 0.5 ? this : other;
  }
}

/// Radii, spacing and motion transcribed from the prototype's utility classes.
abstract final class AppRadii {
  /// `rounded-3xl` → 24px on glass cards.
  static const double card = 24;

  /// `rounded-2xl` → 16px.
  static const double panel = 16;

  /// List groups, segmented controls.
  static const double group = 16;

  /// Sheets (`border-radius: 26px 26px 0 0`).
  static const double sheet = 26;

  /// Floating tab bar (`border-radius: 34px`).
  static const double tabBar = 34;

  static const double pill = 999;
}

abstract final class AppDurations {
  /// `cubic-bezier(.22, 1, .36, 1)` — the prototype's standard easing.
  static const standard = Duration(milliseconds: 340);

  /// `cubic-bezier(.34, 1.56, .64, 1)` — the springy tap/press easing.
  static const springy = Duration(milliseconds: 200);

  static const selection = Duration(milliseconds: 360);
}

abstract final class AppMotion {
  static const standardCurve = Cubic(0.22, 1, 0.36, 1);
  static const springyCurve = Cubic(0.34, 1.56, 0.64, 1);
}

/// Width at which the shell swaps its floating tab bar for a sidebar and widens
/// its content padding.
///
/// It lives with the tokens because three separate places have to agree on it:
/// the shell picks the navigation形态 from it, the shell and [Subpage] both
/// derive their horizontal padding from it, and a mismatch shows up as a page
/// that jumps sideways when it is pushed.
const double kWideLayoutBreakpoint = 768;
