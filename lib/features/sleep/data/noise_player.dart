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
      await _audio.play();
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
