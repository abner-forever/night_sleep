import 'package:flutter/material.dart';

import '../../../../core/platform/haptics.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../domain/sleep_quality.dart';
import 'stage_style.dart';

/// 1–5 档的主观质量选择行——五个文字药丸。
///
/// 表单、回顾页与结束评星弹层三处共用。`value` 为空表示**还没评过**——
/// 此时五个药丸一个都不高亮，这是这个组件唯一需要小心的状态：默认选中某一档
/// 等于应用替用户打了分（偏差 #26，见 `log_page.dart` 里同一条）。
///
/// 选中后在**同一行右侧**给出这一档的 [SleepQuality.feedback]；**未选时不显示
/// 这句话，也不显示占位符**——「没有的东西就显示为没有」。
class QualityChoice extends StatelessWidget {
  const QualityChoice({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final SleepQuality? value;
  final ValueChanged<SleepQuality> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final selected = value;

    return Row(
      children: [
        // 药丸给 `Expanded`：五个药丸加右侧那句反馈在 390 宽下本来就不够一行，
        // 排不下时 `Wrap` 换行，而不是把这一行顶出屏幕。
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 8,
            children: [
              for (final quality in SleepQuality.values)
                _ChoicePill(
                  quality: quality,
                  selected: quality == selected,
                  onTap: () {
                    AppHaptics.select();
                    onChanged(quality);
                  },
                ),
            ],
          ),
        ),
        if (selected != null) ...[
          const SizedBox(width: 12),
          Text(
            selected.feedback,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: qualityColor(tokens, selected),
            ),
          ),
        ],
      ],
    );
  }
}

/// 一枚药丸。选中态照原型：底色是这一档语义色的 14%，1.5px 同色描边，
/// 整枚弹到 1.1 倍。
class _ChoicePill extends StatelessWidget {
  const _ChoicePill({
    required this.quality,
    required this.selected,
    required this.onTap,
  });

  final SleepQuality quality;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final color = qualityColor(tokens, quality);

    return Semantics(
      // 每一枚都是一句主观看法的入口；没有这个标签，读屏软件念不出点的是哪一档，
      // 控件等于不可用。文案与可见文字一致——`睡眠质量 精力充沛`。
      //
      // **`excludeSemantics` 是必须的**：五星那会儿子树里只有一个没有文字的图标，
      // 现在里面是一枚写着档位名的 `Text`，它的语义会与这里的 `label` **合并**成
      // 「睡眠质量 一般 一般」。排除子树的语义，节点上就只剩这一句完整的话。
      container: true,
      excludeSemantics: true,
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
            // 未选中时描边取透明而不是不画：否则选中那一刻整枚会跳 1.5px。
            //
            // 左右各 9px 是量出来的：五个药丸加四道 6px 间隔在 390 宽的手机上
            // 一共 310px，而卡片内能给 318px——再宽 1px 就会挤成两行。
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
            decoration: BoxDecoration(
              color: selected ? color.withValues(alpha: 0.14) : tokens.bgMuted,
              borderRadius: BorderRadius.circular(AppRadii.pill),
              border: Border.all(
                width: 1.5,
                color: selected ? color : Colors.transparent,
              ),
            ),
            child: Text(
              quality.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? color : tokens.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
