import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import 'app_basics.dart';

/// 新版实体卡片：实底、细边框，并保留表单所需的 Material 祖先。
class QuietSurface extends StatelessWidget {
  const QuietSurface({
    super.key,
    required this.child,
    this.borderRadius,
    this.padding,
    this.margin,
    this.tint,
    this.borderColor,
    this.borderWidth = 1,
    this.shadow,
    this.clipBehavior = Clip.antiAlias,
    this.onTap,
    this.semanticLabel,
    this.expandWidth = true,
    this.animateChanges = false,
  });

  final Widget child;
  final BorderRadiusGeometry? borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  /// 覆盖填充色；用于带强调色的实体面板。
  final Color? tint;
  final Color? borderColor;

  /// 描边宽度。默认 1px（原型的 `--glass-border`）；选中态那种 1.5px 的强调描边
  /// （`.review-event-option`）从这里走。
  final double borderWidth;
  final List<BoxShadow>? shadow;
  final Clip clipBehavior;
  final VoidCallback? onTap;
  final String? semanticLabel;

  /// 铺满可用宽度而不是贴合内容。
  ///
  /// 默认开着，理由与 [GlassSurface.expandWidth] 相同：一列里的卡片是个块级元素。
  final bool expandWidth;

  /// 填充 / 描边变了要不要补一帧过渡。
  ///
  /// 默认关掉：大多数卡片的外观不随交互变化。**选中态要开**——四宫格事件卡
  /// 那种「点一下整张换底换边」如果瞬变，看起来像换了一张卡而不是按了一下。
  final bool animateChanges;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final radius = borderRadius ?? BorderRadius.circular(AppRadii.card);

    // 阴影画在裁剪**之外**：声明在同一个被 `ClipRRect` 裁掉的盒子上时，
    // `boxShadow` 会被静默丢掉（`glass_surface.dart` 里记过同一条）。
    Widget surface = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: shadow ?? tokens.quietShadow,
      ),
      child: ClipRRect(
        borderRadius: radius,
        clipBehavior: clipBehavior,
        // 需要过渡时用 `AnimatedContainer`；不需要时它的 duration 是零，
        // 等价于原来的 `Container`，不会多挂一个不动的 ticker。
        child: AnimatedContainer(
          duration: animateChanges ? AppDurations.control : Duration.zero,
          curve: AppMotion.standardCurve,
          decoration: BoxDecoration(
            color: tint ?? tokens.quietFill,
            borderRadius: radius,
          ),
          // 描边走 `foregroundDecoration`，与 `GlassSurface` 同一个理由：
          // 画在下层会被内容压住，卡片上下缘看起来像被啃掉一截。
          foregroundDecoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: borderColor ?? tokens.glassBorder,
              width: borderWidth,
            ),
          ),
          // 文本域与墨水效果要求一个 `Material` 祖先；给一个透明的即可，
          // 于是任何 QuietSurface 都能直接装输入框。
          child: Material(
            type: MaterialType.transparency,
            child: Padding(
              padding: padding ?? EdgeInsets.zero,
              child: child,
            ),
          ),
        ),
      ),
    );

    if (onTap != null) {
      surface = Pressable(
        onTap: onTap,
        semanticLabel: semanticLabel,
        child: surface,
      );
    } else if (semanticLabel != null) {
      surface =
          Semantics(label: semanticLabel, container: true, child: surface);
    }

    if (expandWidth) {
      surface = SizedBox(width: double.infinity, child: surface);
    }

    return margin == null ? surface : Padding(padding: margin!, child: surface);
  }
}
