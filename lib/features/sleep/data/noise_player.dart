import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'noise_asset.dart';

/// Raised when the sound could not be produced. Carries a message meant for the
/// user, not a stack trace.
class NoisePlaybackFailure implements Exception {
  const NoisePlaybackFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Plays the sleep sounds bundled in `assets/noise/`.
///
/// 素材是**打包资源**，不是运行时合成、也不落临时目录——所以这个类不再有渲染、
/// 写盘与缓存清理三段。换成实景录音的经过见 [NoiseKind] 的文件注释。
///
/// Playback failures are surfaced rather than swallowed: a sound that cannot be
/// loaded must not leave the UI claiming it is playing.
class NoisePlayer {
  NoisePlayer();

  /// Created on first use rather than in the constructor.
  ///
  /// Constructing an [AudioPlayer] opens a platform channel, which does not
  /// exist in a unit test — so creating it eagerly would make this class
  /// impossible to subclass for a test double.
  AudioPlayer? _player;

  AudioPlayer get _audio => _player ??= AudioPlayer();

  NoiseKind? _current;

  /// The sound currently playing, or null.
  NoiseKind? get current => _current;

  Stream<PlayerState> get stateStream => _audio.playerStateStream;

  Future<void> play(NoiseKind kind, {required double volume}) async {
    try {
      await _audio.setAsset(kind.assetPath);
      // Loop the single item rather than queueing copies: the seam is already
      // crossfaded into the asset, so repeats do not click. darwin 侧这一支走
      // AVQueuePlayer 的「预排下一个 item」路径，是平台的无缝衔接实现。
      await _audio.setLoopMode(LoopMode.one);
      await _audio.setVolume(volume.clamp(0.0, 1.0));
      // **起播不能 `await`。** `AudioPlayer.play()` 的 Future 要等「播放结束或被
      // 暂停 / 停止」才完成（`just_audio` 的公开契约；darwin 侧由 `pause:` 与
      // `complete` 两个回调兑现，见 just_audio 的 `AudioPlayer.m`），而这里循环的是
      // 一段 44–75 秒的素材，永远不会结束——await 它就是死等。2026-10-03 在 macOS 上实测：
      // await 之后 6 秒仍不返回（`playing=true`、`ProcessingState.ready`，声音早就
      // 出来了），一直等到有人调 `stop()` 才放行。
      //
      // 死等的代价不只是慢：`_current` 永远赋不上，界面停在「没选中」；而等用户点了
      // 「关闭」把这个 await 放行时，它反倒接着往下走，把状态翻成「正在播放」——
      // 一条彻头彻尾的假状态。
      //
      // 起播请求本身被平台拒绝（播放器已释放、音频会话激活不了）时它会抛错，而这个
      // Future 已经没人 await 了：接住它，别让它变成「未处理的异步错误」打到控制台。
      // **能报给用户的失败在前面三步（`setAsset` 打不开资源）就已经抛出去了**；
      // 剩下的这一种 `just_audio` 自己会吞掉（它还同时让这个 Future 永不完成），
      // 这里也就无从知道，如实记在这里，不假装能看见。
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
}
