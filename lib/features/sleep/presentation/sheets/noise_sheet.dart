import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/platform/haptics.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/widgets/app_sheet.dart';
import '../../data/noise_asset.dart';
import '../../data/noise_player.dart';
import '../widgets/noise_controls.dart';

/// Opens the sleep-sounds sheet.
Future<void> showNoiseSheet(BuildContext context) {
  return showAppSheet<void>(
    context: context,
    expanded: true,
    builder: (context) => const NoiseSheet(),
  );
}

/// Sleep sounds: pick a sound, set level, set a sleep timer.
///
/// 素材是**打包在应用里的实景录音**（`assets/noise/`），选中即播、循环播放；
/// 不再是运行时合成（那套已随 `noise_synth.dart` 一起删掉，经过见 [NoiseKind]）。
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
      expanded: true,
      showHandle: false,
      // 内容比视口高时（iPhone 横屏、iPad 分屏）允许滚动：面板高度上限是屏高的
      // 92%，装不下的部分会被 `ClipRRect` 裁掉，音量条与定时 chips 就再也够不着。
      // 安全区下边距交给这里的滚动视图留（下面的 `Padding` 不再重复计一遍）。
      scrollable: true,
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
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: LayoutBuilder(
              builder: (context, constraints) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (active != null) ...[
                    _WaveformIndicator(animation: _pulse, color: active.color),
                    const SizedBox(height: 20),
                  ],
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final option in kNoiseOptions)
                        NoiseTile(
                          option: option,
                          active: option.id == _activeId,
                          onTap: () => _select(option),
                          photo: true,
                          width: (constraints.maxWidth - 12) / 2,
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  VolumeSlider(
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
                            size: 14,
                            color: tokens.textMuted,
                            strokeWidth: 1.8),
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
                          TimerChip(
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
                                    ? '声音是打包在应用里的实景录音，不需要下载。选一个开始播放。'
                                    : '正在播放「${active.label}」，实景录音循环播放，接缝已做淡化。'),
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
