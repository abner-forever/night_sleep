import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/platform/haptics.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/app_basics.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/widgets/app_sheet.dart';
import '../../../../core/widgets/quiet_surface.dart';
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

/// 助眠音效：分类照片墙、定时关闭、音量与当前播放器。
///
/// 目录只包含实际打包在应用里的五条实景录音。设计稿的「白噪音」分类没有对应
/// 素材时显示空状态，不把风声或自然声冒充成白噪音。
class NoiseSheet extends StatefulWidget {
  const NoiseSheet({super.key, this.player});

  /// Test seam. This sheet owns and disposes the player it receives.
  final NoisePlayer? player;

  @override
  State<NoiseSheet> createState() => _NoiseSheetState();
}

class _NoiseSheetState extends State<NoiseSheet> {
  static const _tabs = ['推荐', '自然', '白噪音'];
  static const _timerChoices = <int?>[null, 15, 30, 60];

  late final NoisePlayer _player = widget.player ?? NoisePlayer();

  String _category = '推荐';
  String? _activeId;
  double _volume = 0.5;
  int? _timerMinutes;
  int? _remainingSeconds;
  Timer? _countdown;
  String? _failure;

  @override
  void dispose() {
    _countdown?.cancel();
    _player.dispose();
    super.dispose();
  }

  NoiseOption? get _active {
    for (final option in kNoiseOptions) {
      if (option.id == _activeId) return option;
    }
    return null;
  }

  List<NoiseOption> get _visibleOptions {
    return switch (_category) {
      // 当前目录全是实景自然声。推荐与自然都展示全部真实素材。
      '推荐' || '自然' => kNoiseOptions,
      // 没有白/棕/粉噪音录音，不能拿自然声冒充。
      _ => const [],
    };
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
    final options = _visibleOptions;

    return AppSheet(
      expanded: true,
      showHandle: false,
      scrollable: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _NoiseHeader(
            activeLabel: active?.label,
            onClose: () => Navigator.of(context).pop(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _CategoryTabs(
                  values: _tabs,
                  selected: _category,
                  onChanged: (value) {
                    AppHaptics.select();
                    setState(() => _category = value);
                  },
                ),
                const SizedBox(height: 10),
                if (options.isEmpty)
                  QuietSurface(
                    borderRadius: BorderRadius.circular(18),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 24,
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: tokens.bgMuted,
                            shape: BoxShape.circle,
                          ),
                          child: AppIcons.volume(
                            size: 22,
                            color: tokens.textMuted,
                            strokeWidth: 1.6,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '暂无白噪音录音',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: tokens.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '当前只打包了经过确认的五条实景自然声。',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.5,
                            color: tokens.textMuted,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 560 ? 3 : 2;
                      final gap = columns == 3 ? 12.0 : 10.0;
                      final width =
                          (constraints.maxWidth - gap * (columns - 1)) /
                              columns;
                      return Wrap(
                        spacing: gap,
                        runSpacing: 8,
                        children: [
                          for (final option in options)
                            NoiseTile(
                              option: option,
                              active: option.id == _activeId,
                              onTap: () => _select(option),
                              photo: true,
                              width: width,
                              photoAspectRatio: columns == 2 ? 1.13 : 1.06,
                            ),
                        ],
                      );
                    },
                  ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    AppIcons.timer(
                      size: 16,
                      color: tokens.textSecondary,
                      strokeWidth: 1.6,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      '定时关闭',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: tokens.textSecondary,
                      ),
                    ),
                    const Spacer(),
                    for (final minutes in _timerChoices) ...[
                      if (minutes != _timerChoices.first)
                        const SizedBox(width: 4),
                      _TimerChoice(
                        label: minutes == null ? '不限' : '$minutes分',
                        selected: _timerMinutes == minutes,
                        onTap: () => _selectTimer(minutes),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: VolumeSlider(
                        value: _volume,
                        color: active?.color ?? tokens.accent,
                        onChanged: _changeVolume,
                        showPercentage: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _PlayerBar(
                  active: active,
                  remaining: remaining,
                  timerMinutes: _timerMinutes,
                  failure: _failure,
                  onToggle: active == null ? null : () => _select(active),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NoiseHeader extends StatelessWidget {
  const _NoiseHeader({
    required this.activeLabel,
    required this.onClose,
  });

  final String? activeLabel;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: '关闭助眠音效',
            child: Pressable(
              haptic: false,
              onTap: onClose,
              child: SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: Transform.rotate(
                    angle: 3.1415926535897932,
                    child: AppIcons.chevronRight(
                      size: 21,
                      color: tokens.textPrimary,
                      strokeWidth: 1.9,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  '助眠音效',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: tokens.textPrimary,
                  ),
                ),
                if (activeLabel != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '正在播放 ${activeLabel!.trim()}',
                      style: TextStyle(
                        fontSize: 10,
                        color: tokens.textMuted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 44),
        ],
      ),
    );
  }
}

class _CategoryTabs extends StatelessWidget {
  const _CategoryTabs({
    required this.values,
    required this.selected,
    required this.onChanged,
  });

  final List<String> values;
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Row(
      children: [
        for (final value in values)
          Expanded(
            child: Semantics(
              button: true,
              selected: value == selected,
              label: value,
              child: Pressable(
                haptic: false,
                onTap: () => onChanged(value),
                child: AnimatedContainer(
                  duration: AppDurations.control,
                  alignment: Alignment.center,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    color: value == selected
                        ? tokens.accentSoft
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          value == selected ? FontWeight.w600 : FontWeight.w500,
                      color:
                          value == selected ? tokens.accent : tokens.textMuted,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _TimerChoice extends StatelessWidget {
  const _TimerChoice({
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
    return Semantics(
      button: true,
      selected: selected,
      label: '定时 $label',
      child: Pressable(
        haptic: false,
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppDurations.control,
          constraints: const BoxConstraints(minWidth: 40),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? tokens.accentSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? tokens.accent : tokens.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayerBar extends StatelessWidget {
  const _PlayerBar({
    required this.active,
    required this.remaining,
    required this.timerMinutes,
    required this.failure,
    required this.onToggle,
  });

  final NoiseOption? active;
  final String? remaining;
  final int? timerMinutes;
  final String? failure;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final subtitle = failure ??
        (active == null
            ? '让自然的声音，陪你慢慢入睡'
            : remaining != null
                ? '$remaining 后停止'
                : timerMinutes != null
                    ? '正在播放 · ${timerMinutes!} 分钟后停止'
                    : '正在播放 · 实景录音循环');
    return Container(
      constraints: const BoxConstraints(minHeight: 58),
      padding: const EdgeInsets.fromLTRB(11, 8, 9, 8),
      decoration: BoxDecoration(
        color: tokens.bgCardSolid.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tokens.border),
        boxShadow: [
          BoxShadow(
            color: tokens.textPrimary.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: (active?.color ?? tokens.accent).withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: active?.icon(23, active!.color) ??
                AppIcons.wave(
                  size: 23,
                  color: tokens.accent,
                  strokeWidth: 1.6,
                ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  active?.label.trim() ?? '选择喜欢的声音',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: failure == null ? tokens.textPrimary : tokens.danger,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9,
                    height: 1.35,
                    color: failure == null ? tokens.textMuted : tokens.danger,
                  ),
                ),
              ],
            ),
          ),
          if (active != null)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Semantics(
                button: true,
                label: '暂停播放',
                child: Pressable(
                  haptic: false,
                  onTap: onToggle,
                  child: Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: tokens.bgMuted,
                      shape: BoxShape.circle,
                    ),
                    child: AppIcons.stop(
                      size: 12,
                      color: tokens.textSecondary,
                      strokeWidth: 1.8,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
