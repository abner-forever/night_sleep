import 'package:flutter/cupertino.dart';
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
    this.photo = false,
  });

  final NoiseOption option;
  final bool active;
  final VoidCallback onTap;
  final double width;
  final bool photo;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final color = active ? option.color : tokens.textMuted;

    if (photo) {
      final cover = switch (option.id) {
        'ocean' => 'ocean',
        'fire' => 'fire',
        'stream' => 'waterfall',
        _ => 'forest',
      };
      return Semantics(
        button: true,
        selected: active,
        label: '${option.label}，${active ? '停止播放' : '播放'}',
        excludeSemantics: true,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: width,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                  color: active ? tokens.accent : Colors.transparent, width: 2),
            ),
            child: AspectRatio(
              aspectRatio: 1.06,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset('assets/images/$cover.jpg', fit: BoxFit.cover),
                    const DecoratedBox(
                        decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x1A061B36), Color(0xB3061B36)],
                        stops: [.2, 1],
                      ),
                    )),
                    Positioned(
                        top: 10,
                        left: 11,
                        child: option.icon(20, const Color(0xFFD2E4F7))),
                    Positioned(
                      left: 12,
                      right: 42,
                      bottom: 12,
                      child: Text(option.label,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600)),
                    ),
                    Positioned(
                      right: 11,
                      bottom: 12,
                      child: Container(
                        width: 25,
                        height: 25,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                            color: Colors.white, shape: BoxShape.circle),
                        child: active
                            ? AppIcons.stop(
                                size: 12, color: const Color(0xFF24476C))
                            : AppIcons.play(
                                size: 12, color: const Color(0xFF24476C)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

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
          child: Semantics(
            label: '音量',
            child: SizedBox(
              height: 44,
              child: CupertinoSlider(
                value: value,
                activeColor: color,
                onChanged: onChanged,
              ),
            ),
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
