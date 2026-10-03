import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import 'app_icons.dart';

/// 紧凑下拉选择器——原型里的 `ai-select-trigger` / `appearance-select-trigger`。
///
/// 菜单由 [PopupMenuButton] 渲染，**不画在树内**：调用点常常落在
/// `GlassSurface` 里，而它的 `ClipRRect` 会把树内浮层裁掉，设计里那个悬空菜单
/// 因此只能活在应用 overlay 上（洞察配置页那片卡片注释记的就是这个坑）。
///
/// 两种版式，由 [expand] 选：
/// * `true`（默认）——标签在上、字段在下的竖排，字段撑满父级宽度。调用方必须用
///   `Expanded` 之类**有界宽度**把它包住，否则内部的 `Expanded` 会报
///   「无界约束下使用 flex」。
/// * `false`——只有触发器本身，按内容收缩（配合 [minWidth]），用作列表行内
///   右对齐的下拉。这一支不用 flex 子项，因此在**无界**宽度的行里也安全。
class AppMenuField extends StatelessWidget {
  const AppMenuField({
    super.key,
    required this.value,
    required this.options,
    required this.selected,
    required this.onPick,
    this.label,
    this.enabled = true,
    this.expand = true,
    this.minWidth = 0,
  });

  /// 字段上方的标签，仅在 [expand] 为真时渲染。
  final String? label;

  /// 触发器上显示的文字。
  final String value;

  final List<String> options;

  /// 当前选中项；为 `null` 时不画对勾。
  final String? selected;

  final ValueChanged<int> onPick;

  /// 为假时只渲染一枚不可用的触发器，不接下拉。
  final bool enabled;

  final bool expand;

  /// [expand] 为假时的最小宽度。
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    final trigger = Container(
      constraints: BoxConstraints(minWidth: minWidth),
      padding: EdgeInsets.symmetric(
        horizontal: 12,
        vertical: expand ? 10 : 9,
      ),
      decoration: BoxDecoration(
        color: tokens.bgInput,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        // 箭头贴右靠的是这一行。竖排版式里文字由 `Expanded` 吃满剩余宽度，
        // 箭头自然被顶到最右，`start` 与 `spaceBetween` 没有区别；
        // **行内版式没有 flex 子项**，而 `Container` 的 `minWidth` 会让 `Row` 比
        // 内容宽出一截——不显式 `spaceBetween` 的话，多出来的宽度全留在右边，
        // 箭头就浮在文字后面而不是贴着右端（原型 `.appearance-select-trigger`
        // 正是 `justify-content: space-between`）。
        mainAxisAlignment:
            expand ? MainAxisAlignment.start : MainAxisAlignment.spaceBetween,
        children: [
          _value(tokens),
          // 行内版式两侧挨在一起会粘住，按原型的 `gap: 8px` 留出间距；
          // 它是 `spaceBetween` 之外的**最小**间距。
          if (!expand) const SizedBox(width: 8),
          AppIcons.chevronDown(
            size: 15,
            color: tokens.textMuted,
            strokeWidth: 2,
          ),
        ],
      ),
    );

    // 「没有可选项」是一个真实状态——服务商的模型列表还没拉回来——那时的空弹层
    // 读起来像控件坏了，而不像「还没取到」。
    final field = enabled
        ? PopupMenuButton<int>(
            tooltip: '',
            position: PopupMenuPosition.under,
            color: tokens.bgCardSolid,
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: tokens.border),
            ),
            onSelected: onPick,
            itemBuilder: (context) => [
              for (var i = 0; i < options.length; i++)
                PopupMenuItem<int>(
                  value: i,
                  height: 42,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          options[i],
                          style: TextStyle(
                            fontSize: 14,
                            color: options[i] == selected
                                ? tokens.accent
                                : tokens.textPrimary,
                          ),
                        ),
                      ),
                      if (options[i] == selected)
                        AppIcons.check(
                          size: 14,
                          color: tokens.accent,
                          strokeWidth: 2.5,
                        ),
                    ],
                  ),
                ),
            ],
            child: trigger,
          )
        : trigger;

    if (label == null) return field;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label!,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: tokens.textMuted,
          ),
        ),
        const SizedBox(height: 6),
        field,
      ],
    );
  }

  /// 触发器上的当前值。竖排版式把它交给 `Expanded` 撑开，行内版式让它按内容收缩。
  Widget _value(AppTokens tokens) {
    final text = Text(
      value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: expand ? 14 : 13,
        fontWeight: expand ? FontWeight.w500 : FontWeight.w600,
        color: enabled ? tokens.textPrimary : tokens.textMuted,
      ),
    );
    return expand ? Expanded(child: text) : text;
  }
}
