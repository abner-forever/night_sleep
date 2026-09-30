import 'package:flutter/material.dart';

import '../../../../core/platform/haptics.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../domain/sleep_quality.dart';
import 'stage_style.dart';

/// 1–5 星的主观质量评分行。
///
/// 表单、回顾页与结束评星弹层三处共用。`value` 为空表示**还没评过**——
/// 此时一颗星都不选中，这是这个组件唯一需要小心的状态：默认选中某一档等于
/// 应用替用户打了分。
class QualityStars extends StatelessWidget {
  const QualityStars({
    super.key,
    required this.value,
    required this.onChanged,
    this.size = 44,
  });

  final SleepQuality? value;
  final ValueChanged<SleepQuality> onChanged;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final quality in SleepQuality.values) ...[
          _Star(
            quality: quality,
            selected: value == quality,
            filledTo: value?.value ?? 0,
            size: size,
            onTap: () {
              AppHaptics.select();
              onChanged(quality);
            },
          ),
          if (quality != SleepQuality.values.last) const SizedBox(width: 10),
        ],
      ],
    );
  }
}

class _Star extends StatelessWidget {
  const _Star({
    required this.quality,
    required this.selected,
    required this.filledTo,
    required this.size,
    required this.onTap,
  });

  final SleepQuality quality;
  final bool selected;
  final int filledTo;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final color = qualityColor(tokens, quality);
    final filled = filledTo >= quality.value;
    // 版面按 44pt 的盒子设计，里面配 18pt 的星、16pt 的圆角。三者跟着 `size`
    // 等比走，换个尺寸才不会出现「大方块配小星」的错位。
    final glyph = size * 18 / 44;
    final radius = size * 16 / 44;

    return Semantics(
      // 这一行是五枚没有文字的图形；没有这个标签，读屏软件什么也念不出来，
      // 控件等于不可用。
      button: true,
      selected: selected,
      label: '睡眠质量 ${quality.label}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedScale(
          scale: selected ? 1.1 : 1,
          duration: AppDurations.springy,
          curve: AppMotion.springyCurve,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: selected ? color.withValues(alpha: 0.16) : tokens.bgMuted,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                width: 1.5,
                color: selected ? color : Colors.transparent,
              ),
            ),
            alignment: Alignment.center,
            child: AppIcons.star(
              size: glyph,
              color: filled ? color : tokens.borderStrong,
              strokeWidth: filled ? 2 : 1.5,
            ),
          ),
        ),
      ),
    );
  }
}
