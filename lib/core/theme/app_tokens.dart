import 'package:flutter/material.dart';

/// Figma Make Version 19 的颜色与材质令牌。
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

  Color get primaryActionFill => const Color(0xFF3478F6);

  static const light = AppTokens(
    bgBase: Color(0xFFF1F7FB),
    bgCard: Color(0xFFFFFFFF),
    bgCardSolid: Color(0xFFFFFFFF),
    bgRaised: Color(0xFFF6FAFF),
    bgMuted: Color(0xFFEAF1F8),
    bgInput: Color(0xFFEDF3F9),
    bgNavbar: Color(0xF0F9FDFF),
    textPrimary: Color(0xFF172033),
    textSecondary: Color(0xFF53657A),
    textMuted: Color(0xFF8290A1),
    accent: Color(0xFF3478F6),
    accentSoft: Color(0xFFE4EFFF),
    accentViolet: Color(0xFF8B6CFA),
    accentBlue: Color(0xFF43C7D9),
    border: Color(0xFFE5EDF4),
    borderStrong: Color(0xFFCBD9E8),
    glassBorder: Color(0xFFE5EDF4),
    sheetBg: Color(0xFFF8FCFF),
    specular: Color(0xB3FFFFFF), // rgba(255,255,255,.70)
    material: Color(0xFFFFFFFF),
    materialStrong: Color(0xFFFFFFFF),
    danger: Color(0xFFEF6376),
    warn: Color(0xFFE29A48),
    caution: Color(0xFFC59B36),
    good: Color(0xFF42C99A),
    stageDeep: Color(0xFF3478F6),
    stageLight: Color(0xFF65C8F3),
    stageRem: Color(0xFF8B6CFA),
    stageAwake: Color(0xFF42C99A),
    atmosphere: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFF1F7FB), Color(0xFFF1F7FB)],
    ),
    primaryActionGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF3478F6), Color(0xFF3478F6)],
    ),
    overlayScrim: Color(0x59091729),
  );

  static const dark = AppTokens(
    bgBase: Color(0xFF091729),
    bgCard: Color(0xFF11243D),
    bgCardSolid: Color(0xFF11243D),
    bgRaised: Color(0xFF18314E),
    bgMuted: Color(0xFF19334F),
    bgInput: Color(0xFF19334F),
    bgNavbar: Color(0xF0091729),
    textPrimary: Color(0xFFF4F8FF),
    textSecondary: Color(0xFFC0D0E5),
    textMuted: Color(0xFF8FA7C4),
    accent: Color(0xFF77ADFF),
    accentSoft: Color(0xFF1C3B62),
    accentViolet: Color(0xFFAB8CFF),
    accentBlue: Color(0xFF60CFE8),
    border: Color(0x1FBCD5F8),
    borderStrong: Color(0x3BBCD5F8),
    glassBorder: Color(0x1FBCD5F8),
    sheetBg: Color(0xFF11243D),
    specular: Color(0x1FFFFFFF), // rgba(255,255,255,.12)
    material: Color(0xFF11243D),
    materialStrong: Color(0xFF11243D),
    danger: Color(0xFFEF6376),
    warn: Color(0xFFE29A48),
    caution: Color(0xFFC59B36),
    good: Color(0xFF42C99A),
    stageDeep: Color(0xFF77ADFF),
    stageLight: Color(0xFF65C8F3),
    stageRem: Color(0xFFAB8CFF),
    stageAwake: Color(0xFF42C99A),
    atmosphere: LinearGradient(
      colors: [Color(0xFF091729), Color(0xFF091729)],
    ),
    primaryActionGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF3478F6), Color(0xFF3478F6)],
    ),
    overlayScrim: Color(0x59091729),
  );

  static AppTokens of(BuildContext context) =>
      Theme.of(context).extension<AppTokens>() ?? light;

  List<BoxShadow> get surfaceShadow => const [];

  Color get quietFill => bgCardSolid;

  List<BoxShadow> get quietShadow => const [];

  // ── 液态玻璃（导航 / 控件层） ──────────────────────────────────────────────
  //
  // 这些值只给 `LiquidGlass` 用。与 `specular` / `glassBorder` 分开，是因为
  // 液态玻璃要的是一圈**有厚度的**边缘：浅色底上纯白描边会整条消失，必须
  // 另配一条深色外缘线；深色底上则反过来，只留一层很淡的白边。

  /// 顶部内缘的镜面高光——比 [specular] 更亮、更集中。
  Color get liquidSpecular =>
      this == dark ? const Color(0x33FFFFFF) : const Color(0xE6FFFFFF);

  /// 外缘细线。浅色模式用深灰，否则白线落在浅色页面上等于没有边界。
  Color get liquidEdge =>
      this == dark ? const Color(0x24FFFFFF) : const Color(0x293C3C43);

  /// 内缘描边的过渡色（从顶部高光走到这里，再收到底部）。
  Color get liquidRim =>
      this == dark ? const Color(0x1FFFFFFF) : const Color(0xB3FFFFFF);

  /// 底部 / 侧边的收边，比 [liquidRim] 暗一档。
  Color get liquidRimSoft =>
      this == dark ? const Color(0x0FFFFFFF) : const Color(0x4DFFFFFF);

  /// 内缘那圈宽而模糊的柔光，模拟光在玻璃厚度里散开。
  Color get liquidGlow =>
      this == dark ? const Color(0x14FFFFFF) : const Color(0x33FFFFFF);

  /// 色散边缘的冷色。只用在斜向扫光最淡的那一角，别把整圈染色。
  Color get liquidFringeCool =>
      this == dark ? const Color(0x1464D2FF) : const Color(0x1A5AC8FA);

  /// 色散边缘的暖色，与 [liquidFringeCool] 相对。
  Color get liquidFringeWarm =>
      this == dark ? const Color(0x12BF5AF2) : const Color(0x145856D6);

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

/// Figma Make Version 19 的公共圆角。
abstract final class AppRadii {
  static const double card = 19;

  /// `rounded-2xl` → 16px.
  static const double panel = 16;

  static const double group = 19;

  static const double sheet = 24;

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

  /// 选中态底色 / 描边的过渡。比 `standard` 短：控件状态要跟手，不能拖。
  static const control = Duration(milliseconds: 200);

  /// 底部弹层进场。比退场慢一点——进场是「升起来」，退场要「走得干脆」。
  static const sheetIn = Duration(milliseconds: 340);

  /// 底部弹层退场（点蒙层、点把手、下滑甩走都走它）。
  static const sheetOut = Duration(milliseconds: 240);

  /// 弹层被拉下一截、没够着关闭阈值后弹回原位。
  static const sheetSettle = Duration(milliseconds: 260);
}

abstract final class AppMotion {
  static const standardCurve = Cubic(0.22, 1, 0.36, 1);
  static const springyCurve = Cubic(0.34, 1.56, 0.64, 1);

  /// 弹层进场：起手快、落定稳（ease-out-expo 一类）。
  ///
  /// **不带回弹。** 面板下沿贴着屏幕底，任何过冲都会把它抬起一条缝，
  /// 露出后面的画面——那不是弹簧，是断片。
  static const sheetEnterCurve = Cubic(0.16, 1, 0.3, 1);

  /// 弹层退场：加速离场，不拖泥带水。
  static const sheetExitCurve = Cubic(0.4, 0, 1, 1);
}

/// Width at which the shell swaps its floating tab bar for a sidebar and widens
/// its content padding.
///
/// It lives with the tokens because three separate places have to agree on it:
/// the shell picks the navigation形态 from it, the shell and [Subpage] both
/// derive their horizontal padding from it, and a mismatch shows up as a page
/// that jumps sideways when it is pushed.
const double kWideLayoutBreakpoint = 768;

const double kSubpageNavigationHeight = 44;

const double kBottomNavigationHeight = 50;

/// 首页手机端夜景头部的顶部色。外壳的柔化模糊带也用它，避免白色叠加。
const Color homeHeaderTopColor = Color(0xFF0B3979);
