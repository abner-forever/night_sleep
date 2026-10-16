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
    required this.good,
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

  /// 正向判断（达标 / 恢复良好）用的薄荷绿。
  ///
  /// 原型末层只在结论条那个圆点上硬编码了 `#86d8c6`（`.sleep-insight-mark`），
  /// 那是画在**深色 hero 卡**上的值——浅底上它对比度不够，所以浅色另取 `#2e9e83`。
  /// 只落在「达标 / 恢复良好」这一类判断上；**不要拿它去换 `durationBandColor`**
  /// ——那会把三页的柱子与时长数字整片重新染色，那不是这一条要的事。
  final Color good;

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
    good: Color(0xFF2E9E83),
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
    good: Color(0xFF86D8C6),
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

  /// 安静实体面的填充（`.quiet-surface` / `.home-utility-card` / `.stats-metric-card` …）。
  ///
  /// 浅色就是 `--ios-material-strong`；深色被原型 `.theme-dark.ios-app` 那一段
  /// 改写成不透明的 `rgba(28,28,30,.84)`——比 `materialStrong` 更实、更暗。
  Color get quietFill =>
      this == dark ? const Color(0xD61C1C1E) : materialStrong;

  /// 安静实体面的阴影。比玻璃那层浅得多：它的存在理由就是**不参与氛围**。
  List<BoxShadow> get quietShadow => this == dark
      ? const [
          BoxShadow(
              color: Color(0x29000000), blurRadius: 24, offset: Offset(0, 8))
        ]
      : const [
          BoxShadow(
              color: Color(0x0E24355B), blurRadius: 18, offset: Offset(0, 5))
        ];

  @override
  AppTokens copyWith() => this;

  @override
  AppTokens lerp(ThemeExtension<AppTokens>? other, double t) {
    if (other is! AppTokens) return this;
    return t < 0.5 ? this : other;
  }
}

/// CSS `color-mix(in srgb, a pA%, b)` 的等价物（`b` 的占比是 `1 - pA`）。
///
/// **不要用 `Color.alphaBlend` 顶替。** 两者只有在 `a` **完全不透明**时才相等：
/// `alphaBlend` 的语义是「把 a 盖在 b 上」，于是 b 的权重变成 `1 - pA·aA`；
/// 而 `color-mix` 是**按各自不透明度加权求平均**，b 的权重就是 `1 - pA`。
///
/// 原型大量使用 `--accent-soft`，而它恰恰**不是**不透明的（浅色 α=.12、深色 α=.20）。
/// 照 `alphaBlend` 写出来，混进去的蓝会比设计浓约 8 倍——2026-10-16 在真机上
/// 一眼看出来的「全部数据页 hero 太蓝」就是这一处。
///
/// `color-mix(in srgb, X p%, transparent)` 用 `colorMix(X, p, Colors.transparent)` 表达；
/// 把结果再叠到某个实底上时，才轮到 `Color.alphaBlend`。
Color colorMix(Color a, double percentA, Color b) {
  final p = percentA.clamp(0.0, 1.0);
  final q = 1 - p;
  final alpha = p * a.a + q * b.a;
  if (alpha <= 0) return const Color(0x00000000);
  double channel(double ca, double cb) => (p * a.a * ca + q * b.a * cb) / alpha;
  return Color.from(
    alpha: alpha,
    red: channel(a.r, b.r),
    green: channel(a.g, b.g),
    blue: channel(a.b, b.b),
  );
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

  /// 滚轮选中行底色的圆角（v3.23 新增，**非原型**）。
  ///
  /// 原型在选中行上下画的是 `wheel-selection-rail` 两条 1px 线（见规格 §8 偏差
  /// #15），使用方要的是 iOS 闹钟那种**底色**横条，所以有了这个值。比 `panel`
  /// 小：它套的是一条 36px 高的横条，16 会圆到只剩 4px 直边，看着像药丸。
  static const double wheelHighlight = 12;

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
