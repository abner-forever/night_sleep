import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/platform/haptics.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/widgets/app_sheet.dart';
import '../../data/noise_player.dart';
import '../../data/noise_synth.dart';

/// Opens the sleep-sounds sheet.
Future<void> showNoiseSheet(BuildContext context) {
  return showAppSheet<void>(
    context: context,
    builder: (context) => const NoiseSheet(),
  );
}

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

/// The eight sounds from the prototype, in its order.
final List<NoiseOption> kNoiseOptions = [
  NoiseOption(
    id: 'white',
    label: '白噪音',
    icon: (size, color) =>
        AppIcons.wave(size: size, color: color, strokeWidth: 1.5),
    color: const Color(0xFF007AFF),
  ),
  NoiseOption(
    id: 'brown',
    label: '棕噪音',
    icon: (size, color) =>
        AppIcons.sparkle(size: size, color: color, strokeWidth: 1.5),
    color: const Color(0xFFB5A090),
  ),
  NoiseOption(
    id: 'rain',
    label: '雨声',
    icon: (size, color) =>
        AppIcons.rain(size: size, color: color, strokeWidth: 1.5),
    color: const Color(0xFF5AC8FA),
  ),
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
    id: 'fan',
    label: '风扇',
    icon: (size, color) =>
        AppIcons.fan(size: size, color: color, strokeWidth: 1.5),
    color: const Color(0xFFA0B8C4),
  ),
  NoiseOption(
    id: 'pink',
    label: '粉噪音',
    icon: (size, color) =>
        AppIcons.sparkle(size: size, color: color, strokeWidth: 1.5),
    color: const Color(0xFF5856D6),
  ),
];

/// Sleep sounds: pick a sound, set level, set a sleep timer.
///
/// The audio is **synthesised on device** — see [buildNoiseWav] — rather than
/// shipped as recordings, which is also what the prototype does with the Web
/// Audio API. Selecting a sound renders its loop once, off the main isolate, and
/// then plays it on repeat.
///
/// Playback failure is surfaced in the sheet instead of being swallowed: a sound
/// that cannot be produced must not leave the UI claiming it is playing.
class NoiseSheet extends StatefulWidget {
  const NoiseSheet({super.key, this.player});

  /// Test seam. The sheet always disposes the player it ends up holding, so an
  /// injected one must not be shared between tests.
  final NoisePlayer? player;

  @override
  State<NoiseSheet> createState() => _NoiseSheetState();
}

class _NoiseSheetState extends State<NoiseSheet>
    with SingleTickerProviderStateMixin {
  static const _timerChoices = <int?>[null, 15, 30, 45, 60, 90];

  late final AnimationController _pulse;
  late final NoisePlayer _player = widget.player ?? NoisePlayer();

  String? _activeId;
  double _volume = 0.5;
  int? _timerMinutes;
  int? _remainingSeconds;
  Timer? _countdown;

  /// Set when the platform refused to play, so the sheet can say so rather than
  /// showing a stop button for silence.
  String? _failure;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat();
  }

  @override
  void dispose() {
    _countdown?.cancel();
    _pulse.dispose();
    // The sheet owns the player: closing it must stop the sound.
    _player.dispose();
    super.dispose();
  }

  NoiseOption? get _active {
    if (_activeId == null) return null;
    for (final option in kNoiseOptions) {
      if (option.id == _activeId) return option;
    }
    return null;
  }

  void _countdownTick() {
    final remaining = _remainingSeconds;
    if (remaining == null) return;
    if (remaining <= 1) {
      _countdown?.cancel();
      _player.stop();
      setState(() {
        _remainingSeconds = null;
        _activeId = null;
      });
      return;
    }
    setState(() => _remainingSeconds = remaining - 1);
  }

  void _startTimer(int minutes) {
    _countdown?.cancel();
    _remainingSeconds = minutes * 60;
    _countdown =
        Timer.periodic(const Duration(seconds: 1), (_) => _countdownTick());
  }

  Future<void> _select(NoiseOption option) async {
    final wasActive = _activeId == option.id;
    AppHaptics.select();

    if (wasActive) {
      _countdown?.cancel();
      setState(() {
        _activeId = null;
        _remainingSeconds = null;
        _failure = null;
      });
      await _player.stop();
      return;
    }

    final kind = NoiseKind.fromId(option.id);
    if (kind == null) return;

    try {
      // Await before showing it as playing: the first selection of a sound also
      // renders it, and flipping the UI first would show a stop button for a
      // sound that has not started.
      await _player.play(kind, volume: _volume);
    } on NoisePlaybackFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _activeId = null;
        _failure = failure.message;
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _activeId = option.id;
      _failure = null;
      if (_timerMinutes != null) {
        _startTimer(_timerMinutes!);
      } else {
        _countdown?.cancel();
        _remainingSeconds = null;
      }
    });
  }

  void _selectTimer(int? minutes) {
    AppHaptics.select();
    _countdown?.cancel();
    setState(() {
      _timerMinutes = minutes;
      _remainingSeconds = null;
      if (minutes != null && _activeId != null) {
        _startTimer(minutes);
      }
    });
  }

  void _changeVolume(double value) {
    setState(() => _volume = value);
    // Fire and forget: dragging must stay responsive, and a volume call that
    // fails does not warrant interrupting the user mid-gesture.
    _player.setVolume(value);
  }

  String? get _remainingLabel {
    final remaining = _remainingSeconds;
    if (remaining == null) return null;
    final minutes = remaining ~/ 60;
    final seconds = remaining % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final active = _active;
    final remaining = _remainingLabel;
    final failure = _failure;

    return AppSheet(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetToolbar(
            title: '助眠音效',
            subtitle: active == null
                ? null
                : remaining != null
                    ? '$remaining 后停止'
                    : '播放中',
            onClose: () => Navigator.of(context).pop(),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              16,
              20,
              MediaQuery.of(context).padding.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (active != null) ...[
                  _WaveformIndicator(animation: _pulse, color: active.color),
                  const SizedBox(height: 20),
                ],
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final option in kNoiseOptions)
                      _NoiseTile(
                        option: option,
                        active: option.id == _activeId,
                        onTap: () => _select(option),
                        // Four per row: (width - 3 gaps) / 4.
                        width: (MediaQuery.sizeOf(context).width - 110) / 4,
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                _VolumeSlider(
                  value: _volume,
                  color: active?.color ?? tokens.accent,
                  onChanged: _changeVolume,
                ),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      AppIcons.timer(
                          size: 14, color: tokens.textMuted, strokeWidth: 1.8),
                      const SizedBox(width: 6),
                      Text(
                        '定时关闭',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.96,
                          color: tokens.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final minutes in _timerChoices)
                        _TimerChip(
                          label: minutes == null ? '不限' : '${minutes}m',
                          selected: _timerMinutes == minutes,
                          onTap: () => _selectTimer(minutes),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // Honest status. When a sound is playing, say where it comes
                // from; when the platform refused, say that instead of leaving
                // a stop button over silence.
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: tokens.bgMuted,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppIcons.volume(
                        size: 15,
                        color: tokens.textMuted,
                        strokeWidth: 1.6,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          failure ??
                              (active == null
                                  ? '声音由应用实时合成，不占用存储、不需要下载。选一个开始播放。'
                                  : '正在播放「${active.label}」，音频由应用实时合成，循环无缝。'),
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.45,
                            color: failure != null
                                ? tokens.danger
                                : tokens.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Twelve bars breathing with a staggered phase, mirroring the prototype's
/// `wave-bar` keyframes.
class _WaveformIndicator extends StatelessWidget {
  const _WaveformIndicator({required this.animation, required this.color});

  final Animation<double> animation;
  final Color color;

  static const _heights = [3, 5, 4, 7, 4, 6, 3, 5, 4, 6, 3, 5];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < _heights.length; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                Container(
                  width: 3,
                  height: 32 *
                      (_heights[i] / 7) *
                      (0.55 +
                          0.45 *
                              (0.5 +
                                  0.5 *
                                      math.sin(
                                        (animation.value * 2 * math.pi) +
                                            i * (2 * math.pi / 12),
                                      ))),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _NoiseTile extends StatelessWidget {
  const _NoiseTile({
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
      child: Container(
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
            Text(
              option.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `.slider-thumb` — 24px, matching the design.
const double _thumbSize = 24;

class _VolumeSlider extends StatelessWidget {
  const _VolumeSlider({
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

class _TimerChip extends StatelessWidget {
  const _TimerChip({
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
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? tokens.accent : tokens.bgMuted,
          borderRadius: BorderRadius.circular(AppRadii.panel),
        ),
        child: Text(
          label,
          style: AppTheme.num(
            context,
            size: 14,
            weight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? Colors.white : tokens.textSecondary,
          ),
        ),
      ),
    );
  }
}
