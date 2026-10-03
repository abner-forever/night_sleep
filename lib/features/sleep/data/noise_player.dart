import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'noise_synth.dart';

/// Renders one loop off the main isolate.
///
/// Top-level because [compute] needs a function it can send to another isolate,
/// and taking a plain `String` keeps the message trivially sendable.
Uint8List _generateLoop(String kindId) {
  final kind = NoiseKind.fromId(kindId);
  if (kind == null) {
    throw ArgumentError('unknown noise id: $kindId');
  }
  return buildNoiseWav(kind);
}

/// Raised when the sound could not be produced. Carries a message meant for the
/// user, not a stack trace.
class NoisePlaybackFailure implements Exception {
  const NoisePlaybackFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Plays the synthesised sleep sounds.
///
/// The audio is generated on device rather than shipped (see [buildNoiseWav]);
/// this class owns everything that touches the platform — rendering each loop
/// once into the cache directory, then handing that file to the player on
/// repeat.
///
/// Playback failures are surfaced rather than swallowed: a sound that cannot be
/// produced must not leave the UI claiming it is playing.
class NoisePlayer {
  NoisePlayer();

  /// Created on first use rather than in the constructor.
  ///
  /// Constructing an [AudioPlayer] opens a platform channel, which does not
  /// exist in a unit test — so creating it eagerly would make this class
  /// impossible to subclass for a test double.
  AudioPlayer? _player;

  AudioPlayer get _audio => _player ??= AudioPlayer();
  final Map<NoiseKind, String> _files = {};

  NoiseKind? _current;

  /// The sound currently playing, or null.
  NoiseKind? get current => _current;

  Stream<PlayerState> get stateStream => _audio.playerStateStream;

  Future<void> play(NoiseKind kind, {required double volume}) async {
    try {
      final path = await _ensureFile(kind);
      await _audio.setFilePath(path);
      // Loop the single 20-second item rather than queueing copies: the seam is
      // already crossfaded, so repeats do not click.
      await _audio.setLoopMode(LoopMode.one);
      await _audio.setVolume(volume.clamp(0.0, 1.0));
      // **起播不能 `await`。** `AudioPlayer.play()` 的 Future 要等「播放结束或被
      // 暂停 / 停止」才完成（`just_audio` 的公开契约；darwin 侧由 `pause:` 与
      // `complete` 两个回调兑现，见 just_audio 的 `AudioPlayer.m`），而这里循环的是
      // 一个 20 秒的源，永远不会结束——await 它就是死等。2026-10-03 在 macOS 上实测：
      // await 之后 6 秒仍不返回（`playing=true`、`ProcessingState.ready`，声音早就
      // 出来了），一直等到有人调 `stop()` 才放行。
      //
      // 死等的代价不只是慢：`_current` 永远赋不上，界面停在「没选中」；而等用户点了
      // 「关闭」把这个 await 放行时，它反倒接着往下走，把状态翻成「正在播放」——
      // 一条彻头彻尾的假状态。
      //
      // 起播请求本身被平台拒绝（播放器已释放、解码器打不开）时它会抛错，而这个 Future
      // 已经没人 await 了：接住它，别让它变成「未处理的异步错误」打到控制台。**能报给
      // 用户的失败在 `_ensureFile` 与 `setFilePath` 那两步就已经抛出去了**；剩下的
      // 一种失败——音频会话激活不了——`just_audio` 自己会吞掉（它还同时让这个 Future
      // 永不完成），这里也就无从知道，如实记在这里，不假装能看见。
      unawaited(_audio.play().catchError((Object error) {
        debugPrint('助眠音起播请求失败：$error');
      }));
      _current = kind;
    } on NoisePlaybackFailure {
      rethrow;
    } catch (error) {
      _current = null;
      throw NoisePlaybackFailure('无法播放：$error');
    }
  }

  Future<void> setVolume(double volume) =>
      _audio.setVolume(volume.clamp(0.0, 1.0));

  Future<void> stop() async {
    _current = null;
    try {
      await _audio.stop();
    } catch (_) {
      // Stopping a player that never started is not worth reporting.
    }
  }

  Future<void> dispose() async {
    _current = null;
    await _player?.dispose();
  }

  /// Renders [kind] to a cache file once, and remembers where.
  Future<String> _ensureFile(NoiseKind kind) async {
    final cached = _files[kind];
    if (cached != null && File(cached).existsSync()) return cached;

    final directory = await getTemporaryDirectory();
    final file = File(p.join(directory.path, 'noise-${kind.id}.wav'));
    if (!file.existsSync()) {
      try {
        // **先建目录**：macOS 上 `getTemporaryDirectory()` 返回的是
        // `~/Library/Caches/<bundle id>`，而 `path_provider_foundation` 只保证
        // `getApplicationSupportDirectory()` 与 `getApplicationCacheDirectory()`
        // 会顺手建目录，**temp 这一支不建**。全新安装上那个目录并不存在，
        // 直接往里写就是 `PathNotFoundException (errno = 2)`——渲染得再对，
        // 声音也出不来（`export_sharer.dart` 里那次临时目录写入就带着这一行，
        // 所以它一直没事）。目录已存在时是空操作，不额外付代价。
        await directory.create(recursive: true);
        // 50–130ms of DSP and ~860 KB: off the main isolate, so picking a sound
        // does not drop frames, and it is only paid once per sound per install.
        final bytes = await compute(_generateLoop, kind.id);
        await file.writeAsBytes(bytes, flush: true);
      } catch (error) {
        throw NoisePlaybackFailure('无法生成音频：$error');
      }
    }
    _files[kind] = file.path;
    return file.path;
  }

  /// Removes the rendered loops. Called when the user clears local data.
  Future<void> clearCache() async {
    for (final path in _files.values) {
      final file = File(path);
      if (file.existsSync()) {
        try {
          await file.delete();
        } catch (_) {
          // A locked or already-removed cache file is not an error worth
          // surfacing.
        }
      }
    }
    _files.clear();
  }
}
