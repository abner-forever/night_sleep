import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/app_icons.dart';

/// A sleep sound offered by the sheet.
class NoiseOption {
  const NoiseOption({
    required this.id,
    required this.label,
    required this.icon,
    required this.color,
  });

  final String id;
  final String label;
  final IconBuilder icon;

  /// Fixed brand colour, taken from the prototype's `NOISES` table.
  final Color color;
}

typedef IconBuilder = Widget Function(double size, Color color);

/// 五条助眠音效。**不再是一份等长的原型清单**：原型的八条里，白/棕/粉噪音与雨声、
/// 风扇都没有对应的实景录音，硬套会让标签与内容不符（规格偏差 #3/#7/#33），所以只保留
/// 素材真正覆盖的五类。次序沿用原型中仍然存在者的原有先后，新的两条追加在后。
///
/// 颜色全部取自原型既有调色板：`stream` 沿用原「雨声」的蓝、`wind` 沿用原「风扇」的灰蓝。
///
/// [id] 必须与 `NoiseKind` 一一对应——`test/noise_asset_test.dart` 钉着这条。
final List<NoiseOption> kNoiseOptions = [
  NoiseOption(
    id: 'ocean',
    label: '海浪',
    icon: (size, color) =>
        AppIcons.ocean(size: size, color: color, strokeWidth: 1.5),
    color: const Color(0xFF7AB8C4),
  ),
  NoiseOption(
    id: 'fire',
    label: '篝火',
    icon: (size, color) =>
        AppIcons.fire(size: size, color: color, strokeWidth: 1.5),
    color: const Color(0xFFD4A060),
  ),
  NoiseOption(
    id: 'forest',
    label: '森林',
    icon: (size, color) =>
        AppIcons.forest(size: size, color: color, strokeWidth: 1.5),
    color: const Color(0xFF90B890),
  ),
  NoiseOption(
    id: 'stream',
    label: '溪流',
    icon: (size, color) =>
        AppIcons.stream(size: size, color: color, strokeWidth: 1.5),
    color: const Color(0xFF5AC8FA),
  ),
  NoiseOption(
    id: 'wind',
    label: '风',
    icon: (size, color) =>
        AppIcons.wind(size: size, color: color, strokeWidth: 1.5),
    color: const Color(0xFFA0B8C4),
  ),
];

/// One sound in the picker grid.
///
/// 从 `noise_sheet.dart` 提出来成公开组件，供会话页的设定抽屉共用——
/// 复制一份私有副本会让两处的选中态样式慢慢分叉。
class NoiseTile extends StatelessWidget {
  const NoiseTile({
    super.key,
    required this.option,
    required this.active,
    required this.onTap,
    required this.width,
  });

  final NoiseOption option;
  final bool active;
  final VoidCallback onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final color = active ? option.color : tokens.textMuted;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppDurations.control,
        curve: AppMotion.standardCurve,
        width: width,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: active ? option.color.withValues(alpha: 0.13) : tokens.bgMuted,
          borderRadius: BorderRadius.circular(AppRadii.panel),
          border: Border.all(
            width: 1.5,
            color: active
                ? option.color.withValues(alpha: 0.44)
                : Colors.transparent,
          ),
        ),
        child: Column(
          children: [
            option.icon(22, color),
            const SizedBox(height: 8),
            AnimatedDefaultTextStyle(
              duration: AppDurations.control,
              curve: AppMotion.standardCurve,
              style: TextStyle(
                fontSize: 11,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                color: color,
              ),
              child: Text(option.label),
            ),
          ],
        ),
      ),
    );
  }
}

/// `.slider-thumb` — 24px, matching the design.
const double _thumbSize = 24;

/// Volume slider shared by the sleep-sounds sheet and the session drawer.
class VolumeSlider extends StatelessWidget {
  const VolumeSlider({
    super.key,
    required this.value,
    required this.color,
    required this.onChanged,
  });

  final double value;
  final Color color;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    return Row(
      children: [
        AppIcons.volume(size: 18, color: tokens.textMuted, strokeWidth: 1.5),
        const SizedBox(width: 12),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              void update(double dx) {
                if (constraints.maxWidth <= 0) return;
                onChanged((dx / constraints.maxWidth).clamp(0.0, 1.0));
              }

              // The design positions the thumb with `left: <value>%` plus
              // `translateX(-50%)`, i.e. centred on the value, and lets it
              // overhang the track ends. Here it is centred but clamped inside
              // the track, so it never gets clipped at 0% or 100%.
              final trackWidth = constraints.maxWidth;
              final thumbLeft = (value * trackWidth - _thumbSize / 2).clamp(
                  0.0, (trackWidth - _thumbSize).clamp(0.0, double.infinity));

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) => update(details.localPosition.dx),
                onHorizontalDragStart: (details) =>
                    update(details.localPosition.dx),
                onHorizontalDragUpdate: (details) =>
                    update(details.localPosition.dx),
                child: SizedBox(
                  height: 28,
                  child: Stack(
                    children: [
                      Positioned(
                        left: 0,
                        right: 0,
                        top: (28 - 5) / 2,
                        height: 5,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: tokens.borderStrong,
                            borderRadius: BorderRadius.circular(AppRadii.pill),
                          ),
                        ),
                      ),
                      // `left: 0` — the fill grows from the left edge, never
                      // from the middle.
                      Positioned(
                        left: 0,
                        top: (28 - 5) / 2,
                        width: value * trackWidth,
                        height: 5,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(AppRadii.pill),
                          ),
                        ),
                      ),
                      Positioned(
                        left: thumbLeft,
                        top: (28 - _thumbSize) / 2,
                        child: Container(
                          width: _thumbSize,
                          height: _thumbSize,
                          decoration: BoxDecoration(
                            color: tokens.bgCardSolid,
                            shape: BoxShape.circle,
                            border: Border.all(color: color, width: 2.5),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.22),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 12),
        AppIcons.volume(size: 22, color: tokens.textMuted, strokeWidth: 1.5),
      ],
    );
  }
}

/// 一颗时长 chip（「不限」/「15m」/…）。
///
/// 助眠音效弹层与会话页抽屉共用同一份：两处只是给的选项不同——弹层有「不限」与
/// 90m，会话里最长 60m 且没有「不限」——样式本身不该有第二份。
class TimerChip extends StatelessWidget {
  const TimerChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppDurations.control,
        curve: AppMotion.standardCurve,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? tokens.accent : tokens.bgMuted,
          borderRadius: BorderRadius.circular(AppRadii.panel),
        ),
        child: AnimatedDefaultTextStyle(
          duration: AppDurations.control,
          curve: AppMotion.standardCurve,
          style: AppTheme.num(
            context,
            size: 14,
            weight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? Colors.white : tokens.textSecondary,
          ),
          child: Text(label),
        ),
      ),
    );
  }
}
