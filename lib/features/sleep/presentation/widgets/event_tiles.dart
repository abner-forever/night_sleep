import 'package:flutter/material.dart';

import '../../../../core/platform/haptics.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/widgets/quiet_surface.dart';
import '../../domain/sleep_score.dart';

/// 单个睡眠事件格子（打鼾 / 说梦话 / 辗转难眠 / 噩梦）。
///
/// 表单与回顾页共用同一套图标与语义色，所以它从 `log_page.dart` 的私有类提成
/// 公开组件——两处各画一份时，任何一处改色都会让另一处悄悄脱节。
class EventTile extends StatelessWidget {
  const EventTile({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;

  /// 在这里现场构建，而不是外面造好再传进来。颜色是在构造 `SvgPicture.string`
  /// 的那一刻就被烤进 SVG 文本的，事后再套一层 `IconTheme` 改不动它——这就是
  /// 原先那次尝试毫无作用、每个 tile 在深色模式下都是黑色的原因。
  final Widget Function(Color color) icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    // 四宫格是**安静实体面**（原型 `.review-event-option`），不是玻璃。
    // 选中态照原型：`color-mix(事件色 11%, bgCard)` 当底色 + 1.5px 事件色 38%
    // 描边；未选中交给安静面自己的底与 1px `glassBorder`。
    return QuietSurface(
      borderRadius: BorderRadius.circular(AppRadii.panel),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      tint: selected
          ? Color.alphaBlend(color.withValues(alpha: 0.11), tokens.bgCard)
          : null,
      borderColor: selected ? color.withValues(alpha: 0.38) : null,
      borderWidth: selected ? 1.5 : 1,
      onTap: () {
        AppHaptics.select();
        onTap();
      },
      child: Row(
        children: [
          icon(selected ? color : tokens.textMuted),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: selected ? color : tokens.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 四类事件的 2×2 网格，表单与回顾页共用。
///
/// 图标与语义色固定在这里，调用方只传当前勾选状态与变更回调，避免两处各写一份
/// 图标映射后悄悄分叉。
class EventTileGrid extends StatelessWidget {
  const EventTileGrid({
    super.key,
    required this.events,
    required this.onChanged,
  });

  final LoggedEvents events;
  final ValueChanged<LoggedEvents> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: EventTile(
                label: '打鼾',
                icon: (color) =>
                    AppIcons.snore(size: 18, color: color, strokeWidth: 1.5),
                color: tokens.accentBlue,
                selected: events.snore,
                onTap: () => onChanged(events.copyWith(snore: !events.snore)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: EventTile(
                label: '说梦话',
                icon: (color) =>
                    AppIcons.bubble(size: 18, color: color, strokeWidth: 1.5),
                color: tokens.accentViolet,
                selected: events.talk,
                onTap: () => onChanged(events.copyWith(talk: !events.talk)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: EventTile(
                label: '辗转难眠',
                icon: (color) =>
                    AppIcons.sparkle(size: 18, color: color, strokeWidth: 1.5),
                color: tokens.caution,
                selected: events.restless,
                onTap: () =>
                    onChanged(events.copyWith(restless: !events.restless)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: EventTile(
                label: '噩梦',
                icon: (color) =>
                    AppIcons.moon(size: 18, color: color, strokeWidth: 1.5),
                color: tokens.danger,
                selected: events.nightmare,
                onTap: () =>
                    onChanged(events.copyWith(nightmare: !events.nightmare)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
