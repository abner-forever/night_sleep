import 'package:flutter/material.dart';

import '../../../../core/platform/haptics.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../domain/sound_event.dart';
import '../widgets/stage_style.dart';

/// One recorded sound event, expandable to reveal its transcript and insight.
///
/// Two things are kept apart on purpose, because conflating them is how a UI
/// starts lying:
///
///  * **shape** — bar heights come from [SoundClip.waveformEnvelope], which only
///    a decoded file (or a demo row) can supply. Without one the track is drawn
///    flat rather than given the design's fixed 38-bar rhythm.
///  * **playability** — needs an actual file. When [SoundClip.localUri] is null
///    the card says the audio was pruned and the transport stays inert, instead
///    of showing a play state that produces no sound.
///
/// So a clip can legitimately show a waveform and still refuse to play — that is
/// what a night whose audio has been pruned really looks like.
class SoundCard extends StatefulWidget {
  const SoundCard({
    super.key,
    required this.clip,
    required this.expanded,
    required this.onToggle,
  });

  final SoundClip clip;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  State<SoundCard> createState() => _SoundCardState();
}

class _SoundCardState extends State<SoundCard> {
  bool _playing = false;
  double _progress = 0;

  bool get _playable => widget.clip.hasPlayableAudio;

  void _togglePlayback() {
    if (!_playable) return;
    AppHaptics.select();
    setState(() {
      if (_playing) {
        _playing = false;
      } else {
        _playing = true;
        _progress = _progress >= 1 ? 0 : _progress;
      }
    });
  }

  void _seek(double fraction) {
    if (!_playable) return;
    setState(() => _progress = fraction.clamp(0.0, 1.0));
  }

  String _formatTime(double ratio) {
    final seconds = (widget.clip.durationMs / 1000 * ratio).round();
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final clip = widget.clip;
    final color = soundEventColor(tokens, clip.kind);

    return Container(
      decoration: BoxDecoration(
        color: tokens.bgRaised,
        borderRadius: BorderRadius.circular(AppRadii.panel),
        border: Border.all(
          color:
              widget.expanded ? color.withValues(alpha: 0.27) : tokens.border,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              AppHaptics.select();
              widget.onToggle();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.09),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: clip.kind == SoundEventKind.snore
                        ? AppIcons.snore(size: 18, color: color)
                        : AppIcons.bubble(size: 18, color: color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Text(
                              clip.kind.label,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: tokens.textPrimary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.09),
                                borderRadius:
                                    BorderRadius.circular(AppRadii.pill),
                              ),
                              child: Text(
                                clip.durationLabel,
                                style: AppTheme.num(
                                  context,
                                  size: 12,
                                  color: color,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          clip.timeLabel,
                          style: AppTheme.num(
                            context,
                            size: 12,
                            color: tokens.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _PlayButton(
                    playing: _playing,
                    enabled: _playable,
                    color: color,
                    onTap: _togglePlayback,
                  ),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: widget.expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 220),
                    child: AppIcons.chevronDown(
                      size: 20,
                      color: tokens.textMuted,
                      strokeWidth: 2,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The track is drawn even without audio. Keeping it on screen
                // means the clip's shape is visible — from the file when it has
                // been analysed, neutral bars when it has not — while the note
                // below is what states the audio is gone.
                _WaveformTrack(
                  progress: _playable ? _progress : 0,
                  color: color,
                  envelope: clip.waveformEnvelope,
                  label: _playable
                      ? '${_formatTime(_progress)} / ${_formatTime(1)}'
                      : clip.durationLabel,
                  onSeek: _playable ? _seek : null,
                ),
                if (!_playable) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      AppIcons.volume(
                        size: 14,
                        color: tokens.textMuted,
                        strokeWidth: 1.6,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          '这段录音未保留在本地，无法回放',
                          style:
                              TextStyle(fontSize: 12, color: tokens.textMuted),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (widget.expanded)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: tokens.border)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (clip.transcript != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: tokens.bgMuted,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '语音转录',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.96,
                              color: tokens.textMuted,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            clip.transcript!,
                            style: TextStyle(
                              fontSize: 14,
                              fontStyle: FontStyle.italic,
                              height: 1.5,
                              color: tokens.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (clip.analysis != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: tokens.accentSoft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              AppIcons.ai(
                                  size: 13,
                                  color: tokens.accent,
                                  strokeWidth: 1.8),
                              const SizedBox(width: 6),
                              Text(
                                '睡眠洞察',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.72,
                                  color: tokens.accent,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            clip.analysis!,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.5,
                              color: tokens.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (clip.transcript == null &&
                      clip.analysis == null &&
                      clip.analysisStatus == SoundAnalysisStatus.pending)
                    Row(
                      children: [
                        AppIcons.sparkle(
                          size: 14,
                          color: tokens.textMuted,
                          strokeWidth: 1.8,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            '尚未分析这段录音，因此没有转录或洞察。',
                            style: TextStyle(
                                fontSize: 12, color: tokens.textMuted),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.playing,
    required this.enabled,
    required this.color,
    required this.onTap,
  });

  final bool playing;
  final bool enabled;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final effective = enabled ? color : color.withValues(alpha: 0.4);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Opacity(
        opacity: enabled ? 1 : 0.55,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: playing ? effective : effective.withValues(alpha: 0.09),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: playing
              ? AppIcons.stop(size: 13, color: Colors.white, strokeWidth: 2)
              : AppIcons.play(size: 13, color: effective, strokeWidth: 2),
        ),
      ),
    );
  }
}

/// Progress track.
///
/// Bar heights come from [envelope] when the clip has one. Without an envelope
/// every bar is the same height and the track only communicates position — the
/// design's fixed 38-bar shape is *not* reproduced, because drawing a rhythm
/// for audio that has not been analysed is presenting a measurement that was
/// never taken. See [SoundClip.waveformEnvelope].
class _WaveformTrack extends StatelessWidget {
  const _WaveformTrack({
    required this.progress,
    required this.color,
    required this.label,
    required this.onSeek,
    this.envelope,
  });

  final double progress;
  final Color color;
  final String label;

  /// Null when there is nothing to seek to as well as nothing to draw.
  final ValueChanged<double>? onSeek;

  final List<double>? envelope;

  static const double _maxBarHeight = 26;
  static const double _neutralBarHeight = 8;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    return Row(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              void seekTo(double dx) {
                if (constraints.maxWidth <= 0) return;
                onSeek?.call(dx / constraints.maxWidth);
              }

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown:
                    onSeek == null ? null : (d) => seekTo(d.localPosition.dx),
                onHorizontalDragUpdate:
                    onSeek == null ? null : (d) => seekTo(d.localPosition.dx),
                child: SizedBox(
                  height: 28,
                  child: Row(
                    children: [
                      for (var i = 0; i < SoundClip.waveformBarCount; i++) ...[
                        if (i > 0) const SizedBox(width: 1),
                        Expanded(
                          child: Align(
                            alignment: Alignment.center,
                            child: AnimatedContainer(
                              duration: AppDurations.springy,
                              curve: AppMotion.standardCurve,
                              height: _heightAt(i),
                              decoration: BoxDecoration(
                                color: (i + 0.5) / SoundClip.waveformBarCount <=
                                        progress
                                    ? color
                                    : tokens.borderStrong
                                        .withValues(alpha: 0.48),
                                borderRadius:
                                    BorderRadius.circular(AppRadii.pill),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: AppTheme.num(
            context,
            size: 11,
            color: tokens.textMuted,
          ),
        ),
      ],
    );
  }

  /// A missing envelope falls back to a flat, evenly-spaced row: it shows how
  /// far along the clip is without asserting a shape.
  double _heightAt(int index) {
    final bars = envelope;
    if (bars == null || index >= bars.length) return _neutralBarHeight;
    final amplitude = bars[index].clamp(0.0, 1.0);
    // A floor keeps the quietest bar visible rather than collapsing to a dot.
    return (_neutralBarHeight * 0.45 + _maxBarHeight * amplitude * 0.72)
        .clamp(4.0, _maxBarHeight);
  }
}
