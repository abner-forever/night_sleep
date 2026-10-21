import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/hero_surface.dart';

/// 回顾那一页的 hero——柔和晨光（规格 §2.2）。
///
/// **回顾 Tab 与手动补录页共用这一个**：两处是同一件事的两个宿主，同一张卡各画
/// 一份时，任何一处改色都会让另一处悄悄脱节（`event_tiles.dart` 里记过同一条）。
/// 内容由调用方给：手动补录页放时长预览（月亮弧 + 小时数），回顾 Tab 放那一晚的
/// 记录头（日期、起止、来源，点开换一晚）。
///
/// 底色是两层：一条 `accent-soft` 混 `material-strong` 的斜向底，上面叠一团落在
/// **右上角**的柔和暖光。颜色全部现算——
/// 描边从 `accent` 与 `glassBorder` 混出来，底色从 `accentSoft` 与 `materialStrong`
/// 混出来，**一个写死的档位色都没有**（只有原型本身就是字面量的那几处渐变与阴影
/// 是常量，规格已逐条给出）。
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
    // 深色主题另有一套底线与暖光浓度（规格 §2.2 末段）。
    final dark = tokens == AppTokens.dark;

    return HeroSurface(
      borderRadius: BorderRadius.circular(AppRadii.card),
      // 描边 = `accent` 13% 混 `--glass-border`。
      borderColor: colorMix(tokens.accent, 0.13, tokens.glassBorder),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: dark
            ? const [Color(0xEB272B41), Color(0xE61C1C1E)]
            : [
                // `color-mix(accent-soft 42%, material-strong)`。
                //
                // **必须用 `colorMix` 而不是 `alphaBlend`**：`accent-soft` 自带
                // α=.12，`color-mix` 是按不透明度加权的平均，`alphaBlend` 会把它
                // 当成不透明色盖上去，混出来的是一块明显的天蓝而不是这层淡蓝白。
                colorMix(tokens.accentSoft, 0.42, tokens.materialStrong),
                tokens.materialStrong,
              ],
      ),
      shadow: const [
        // `0 10px 28px rgba(39,57,96,.08)`。
        BoxShadow(
          color: Color(0x14273960),
          blurRadius: 28,
          offset: Offset(0, 10),
        ),
      ],
      glow: HeroGlow(
        size: 240,
        top: -140,
        right: -100,
        colors: dark
            ? const [
                Color(0x14E09B56),
                Color(0x06E09B56),
                Color(0x00E09B56),
              ]
            : const [
                Color(0x20FFC66F),
                Color(0x08FFC66F),
                Color(0x00FFC66F),
              ],
        stops: const [0, 0.32, 0.70],
      ),
      padding: padding,
      onTap: onTap,
      semanticLabel: semanticLabel,
      child: child,
    );
  }
}
