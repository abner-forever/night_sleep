import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../../../core/database/app_database.dart' show databaseProvider;
import '../../../../core/platform/haptics.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../data/sleep_repository.dart' show sleepEntriesProvider;
import '../../domain/sound_event.dart';
import '../widgets/stage_style.dart';

/// 单段录音回放的最小接口。
///
/// 生产实现 [JustAudioClipPlayer] 包 `just_audio`；测试注入假实现，
/// 免得 widget 测试去碰真实平台通道（理由与 `NoisePlayer` 同一套）。
abstract class ClipAudioPlayer {
  /// 载入本地文件。打不开 / 解不了码时**抛错**（由调用方接住并如实说明）。
  Future<Duration?> setFilePath(String path);

  /// 起播。**调用方不得 `await`**：`just_audio` 的 `play()` 要等播放结束或
  /// 被停止才完成——实测记录见 `noise_player.dart` 里那段长注释。
  Future<void> play();

  Future<void> stop();

  Future<void> seek(Duration position);

  /// 播放位置。只在有片段播放时有事件。
  Stream<Duration> get positionStream;

  Future<void> dispose();
}

/// [ClipAudioPlayer] 的 `just_audio` 实现。
///
/// [AudioPlayer] **首次真正用到时才创建**：它的构造函数会打开平台通道，
/// 在单元测试里并不存在（与 `NoisePlayer` 同一个理由）。
class JustAudioClipPlayer implements ClipAudioPlayer {
  AudioPlayer? _player;

  AudioPlayer get _audio => _player ??= AudioPlayer();

  @override
  Future<Duration?> setFilePath(String path) => _audio.setFilePath(path);

  @override
  Future<void> play() => _audio.play();

  @override
  Future<void> stop() => _audio.stop();

  @override
  Future<void> seek(Duration position) => _audio.seek(position);

  @override
  Stream<Duration> get positionStream => _audio.positionStream;

  @override
  Future<void> dispose() async {
    await _player?.dispose();
  }
}

/// 播放器的注入口，也是它的所有者；测试用 `overrideWithValue` 换成假实现。
final clipAudioPlayerProvider = Provider<ClipAudioPlayer>((ref) {
  final player = JustAudioClipPlayer();
  ref.onDispose(() => unawaited(player.dispose()));
  return player;
});

/// 谁在播，由它唯一裁决。
///
/// 每张卡各自持一个播放器是不行的：换一张卡起播时，上一张卡仍停在
/// 「正在播」——一句对着静音的假状态。控制器把「正在播哪个片段」集中起来，
/// 换片段时先停掉上一个，卡片只是订阅它。播放器与进度订阅都由 provider
/// 持有、随 provider 释放（见 [clipPlaybackProvider]）。
class ClipPlaybackController extends ChangeNotifier {
  ClipPlaybackController(this._player);

  final ClipAudioPlayer _player;

  /// 首次起播时才订阅，好让 [JustAudioClipPlayer] 的 `AudioPlayer` 跟着推迟
  /// 到第一次需要播放时才构造。
  StreamSubscription<Duration>? _positions;

  String? _clipId;
  Duration _position = Duration.zero;
  String? _failedClipId;
  bool _disposed = false;

  /// 正在播放的片段 id；`null` = 没有片段在播。
  String? get playingClipId => _clipId;

  /// 当前片段方位（只对 [playingClipId] 那张卡有意义）。
  Duration get position => _position;

  bool isPlaying(String clipId) => _clipId == clipId;

  /// 这个片段起播 / 载入失败了吗——卡片据此显示一行小字。
  bool failed(String clipId) => _failedClipId == clipId;

  /// 点播放键：本卡在播就停，否则换成它播（先停掉上一个）。
  ///
  /// `localUri` 为空直接返回——没有文件就不该有任何声音，也不该切到播放态。
  Future<void> toggle(SoundClip clip) async {
    if (_clipId == clip.id) {
      await stop();
      return;
    }
    final uri = clip.localUri;
    if (uri == null) return;

    // 同一时刻只允许一个片段出声：先把上一个停掉。
    await stop();
    _failedClipId = null;

    try {
      await _player.setFilePath(uri);
    } catch (_) {
      // 文件不存在 / 解码失败：不抛到用户脸上，只回一句卡片内的说明。
      _failedClipId = clip.id;
      _notify();
      return;
    }

    _positions ??= _player.positionStream.listen(_onPosition);
    _clipId = clip.id;
    _position = Duration.zero;
    _notify();

    // 起播**不能 await**：这个 Future 要等播放结束才完成。自然放完或用户停掉
    // 时它才 resolve，届时把播放态收回；平台拒绝起播时会抛错，同样收回并说明。
    unawaited(
      _player.play().then((_) => _finished(clip.id)).catchError((Object error) {
        debugPrint('录音片段起播失败：$error');
        _failed(clip.id);
      }),
    );
  }

  Future<void> seek(SoundClip clip, Duration position) async {
    if (_clipId != clip.id) return;
    _position = position;
    _notify();
    try {
      await _player.seek(position);
    } catch (_) {
      // 跳转失败不打断界面；下一次进度回报会纠正位置。
    }
  }

  Future<void> stop() async {
    _clipId = null;
    _position = Duration.zero;
    _notify();
    try {
      await _player.stop();
    } catch (_) {
      // 停一个从未起播的播放器不算错误。
    }
  }

  /// 承载它的卡片正在拆解时调用：停掉声音，但**不通知**监听者——它们也在
  /// 拆解，`notifyListeners` 会去 `markNeedsBuild` 已卸载的元素。
  void detach(String clipId) {
    if (_clipId != clipId) return;
    _clipId = null;
    _position = Duration.zero;
    unawaited(_player.stop().catchError((Object _) {}));
  }

  /// 播放自然结束（或被停止）——回到未播放态，别让停止按钮继续挂着。
  void _finished(String clipId) {
    if (_disposed || _clipId != clipId) return;
    _clipId = null;
    _position = Duration.zero;
    _notify();
  }

  void _failed(String clipId) {
    if (_disposed || _clipId != clipId) return;
    _clipId = null;
    _position = Duration.zero;
    _failedClipId = clipId;
    _notify();
  }

  void _onPosition(Duration position) {
    if (_clipId == null) return;
    _position = position;
    _notify();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _positions?.cancel();
    super.dispose();
  }
}

/// 播放控制器：app 级单例，任意时刻只有一个片段在播。
///
/// `ChangeNotifierProvider` 自己会在 provider 释放时 `dispose()` 这个 notifier，
/// 不要再挂一个 `ref.onDispose(controller.dispose)`——那会二次 dispose 直接抛错。
final clipPlaybackProvider =
    ChangeNotifierProvider<ClipPlaybackController>((ref) {
  return ClipPlaybackController(ref.watch(clipAudioPlayerProvider));
});

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
///
/// 回放是真的（`just_audio`），标注写回 `sound_clips` 的 `kind` 与
/// `labeledAtUtc`；未标注的片段标题显示「待标注」，绝不显示那个中性的占位 kind。
class SoundCard extends ConsumerStatefulWidget {
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
  ConsumerState<SoundCard> createState() => _SoundCardState();
}

class _SoundCardState extends ConsumerState<SoundCard> {
  /// 标注写回库之后，卡片自己记住新的 kind。
  ///
  /// 详情页拿到的是一条**值**（`SleepEntry`），不是流：`sleepEntriesProvider`
  /// 失效后首页会重读，但已经打开的这张表不会。少了这一格，用户点完标注看到的
  /// 还是「待标注」，会以为没生效。
  SoundEventKind? _labeledKind;

  /// 播放在 [clipPlaybackProvider] 里，卡片只订阅它。这里抓住引用，好在
  /// `dispose` 时收尾——`dispose` 里再 `ref.read` 有生命周期风险。
  late final ClipPlaybackController _playback;

  @override
  void initState() {
    super.initState();
    _playback = ref.read(clipPlaybackProvider);
  }

  @override
  void dispose() {
    // 详情页关掉时，如果正是这段在播，停掉它——页面关了不该还有声音。
    // 用 `detach`：此刻别的卡片也在拆解，不能再通知它们重建。
    _playback.detach(widget.clip.id);
    super.dispose();
  }

  SoundClip get _clip => widget.clip;

  bool get _playable => _clip.hasPlayableAudio;

  /// 已标注用写回的 kind（或库里读到的），未标注只是一个中性占位。
  SoundEventKind get _kind => _labeledKind ?? _clip.kind;

  bool get _isLabeled => _labeledKind != null || _clip.isLabeled;

  /// 卡片标题。未标注一律「待标注」——不把中性的占位 kind 说成一个做过的判断。
  String get _labelText => _isLabeled ? _kind.label : '待标注';

  void _togglePlayback() {
    if (!_playable) return;
    AppHaptics.select();
    unawaited(ref.read(clipPlaybackProvider).toggle(_clip));
  }

  void _seek(double fraction) {
    final controller = ref.read(clipPlaybackProvider);
    if (!controller.isPlaying(_clip.id)) return;
    final ms = (_clip.durationMs * fraction.clamp(0.0, 1.0)).round();
    unawaited(controller.seek(_clip, Duration(milliseconds: ms)));
  }

  /// 用户听完之后标注。`kind` 与 `labeledAtUtc` 必须一起写：只改 kind 会让
  /// 「标成了杂音」与「还没标过」再也分不开。
  Future<void> _label(SoundEventKind kind) async {
    AppHaptics.select();
    try {
      await ref.read(databaseProvider).updateClipLabel(
            _clip.id,
            kind: kind.id,
            labeledAtUtc: DateTime.now().toUtc(),
          );
    } catch (_) {
      // 写库失败就不改界面：显示一个没落库的标注等于宣称一件没发生的事。
      return;
    }
    if (!mounted) return;
    setState(() => _labeledKind = kind);
    // 这条 provider 只 watch 记录表，写完片段不会自动重读。
    ref.invalidate(sleepEntriesProvider);
  }

  String _formatTime(double ratio) {
    final seconds = (_clip.durationMs / 1000 * ratio).round();
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final clip = _clip;
    final color = soundEventColor(tokens, _kind);

    // 谁在播由控制器裁决；进度也从它回传，波形轨道与时间标签都靠这个。
    final playback = ref.watch(clipPlaybackProvider);
    final playing = playback.isPlaying(clip.id);
    final progress = playing && clip.durationMs > 0
        ? (playback.position.inMilliseconds / clip.durationMs).clamp(0.0, 1.0)
        : 0.0;
    final failed = playback.failed(clip.id);

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
                    // 未标注用一个中性的声音图标，不借任何一种已标注的图标——
                    // 那会让人以为这段已经被判断过了。
                    child: !_isLabeled
                        ? AppIcons.wave(size: 18, color: color)
                        : _kind == SoundEventKind.snore
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
                              _labelText,
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
                    key: ValueKey('clip-play-${clip.id}'),
                    playing: playing,
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
                  progress: _playable ? progress : 0,
                  color: color,
                  envelope: clip.waveformEnvelope,
                  label: _playable
                      ? '${_formatTime(progress)} / ${_formatTime(1)}'
                      : clip.durationLabel,
                  // 只有这个片段真的在播时才可拖动跳转：控制器一次只载一个文件。
                  onSeek: _playable && playing ? _seek : null,
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
                // 有文件却放不出来（被删 / 损坏）：如实说一行，且不留在播放态。
                if (failed) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      AppIcons.volume(
                        size: 14,
                        color: tokens.danger,
                        strokeWidth: 1.6,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          '这段录音无法播放，文件可能已损坏或不可读。',
                          style: TextStyle(fontSize: 12, color: tokens.danger),
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
                  _LabelChooser(
                    selected: _isLabeled ? _kind : null,
                    onSelect: _label,
                  ),
                  const SizedBox(height: 14),
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
    super.key,
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

/// 三选一标注。**未标注时三项都不选中**——把「还没标过」画成「已经是杂音」
/// 正是 `labeledAtUtc` 这一列存在的理由。
class _LabelChooser extends StatelessWidget {
  const _LabelChooser({required this.selected, required this.onSelect});

  /// 已标注的 kind；`null` = 还没标过。
  final SoundEventKind? selected;

  final ValueChanged<SoundEventKind> onSelect;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '标记这个声音',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.72,
            color: tokens.textMuted,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final kind in SoundEventKind.values)
              _LabelChoice(
                key: ValueKey('clip-label-${kind.id}'),
                kind: kind,
                selected: selected == kind,
                onTap: () => onSelect(kind),
              ),
          ],
        ),
      ],
    );
  }
}

class _LabelChoice extends StatelessWidget {
  const _LabelChoice({
    super.key,
    required this.kind,
    required this.selected,
    required this.onTap,
  });

  final SoundEventKind kind;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final color = soundEventColor(tokens, kind);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.14) : tokens.bgMuted,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          border: Border.all(
            color: selected ? color.withValues(alpha: 0.55) : tokens.border,
          ),
        ),
        child: Text(
          kind.label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? color : tokens.textSecondary,
          ),
        ),
      ),
    );
  }
}
