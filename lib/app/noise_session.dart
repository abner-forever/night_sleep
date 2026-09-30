import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/platform/haptics.dart';
import '../features/sleep/data/noise_player.dart';
import '../features/sleep/data/noise_synth.dart';
import '../features/sleep/data/session_repository.dart';
import '../features/sleep/presentation/widgets/noise_controls.dart';

/// 会话里的助眠音效播放控制。
///
/// **它的生命周期必须比会话页长。** 使用方裁定：白噪音在收起设定抽屉、乃至 pop 掉
/// 整个会话页之后都要继续响——抽屉里的定时上限 60 分钟本意就是「让声音陪你入睡」，
/// 收起面板不该静音（规格 §四 也说收起会话页时「会话继续跑」）。所以播放器与倒计时
/// 住在这里，由 app 级的 [noiseSessionControllerProvider] 持有，而不是某个 widget 的
/// `State`。藏在面板里、面板一关就 `dispose()` 的写法会造出「库里写着在播、实际没声」
/// 的假值。
///
/// 谁创建、谁释放：
/// - 播放器由 [noisePlayerProvider] 创建并释放（测试用 `overrideWithValue` 换成假实现）。
/// - 控制器由 [noiseSessionControllerProvider]（`ChangeNotifierProvider`）创建，并在该
///     provider 释放时 `dispose()`；它只取消自己的倒计时，**不**释放播放器。
///
/// 因为比页面长命，[stop] 是公开的：「倒计时到点」「用户取消选择」，以及
/// **会话结束/丢弃**（Task 7）都要调它——结束了一个会话还响着白噪音不通。
class NoiseSessionController extends ChangeNotifier {
  NoiseSessionController({
    required SessionRepository repository,
    required NoisePlayer player,
  })  : _repository = repository,
        _player = player {
    _ready = _load();
  }

  /// 会话里的白噪音**必须有上限**，所以这里没有 `null`。
  ///
  /// 独立的助眠音效弹层保留「不限」与 90m——它是一个「醒着听」的入口，与夜间录音
  /// 没有交互。同一个功能两个上限，两处界面都要写清。
  static const timerChoices = <int>[15, 30, 45, 60];

  static const defaultTimerMinutes = 30;

  final SessionRepository _repository;
  final NoisePlayer _player;

  /// 冷启动对账跑完没。选择与调音量都排在它后面，免得对账把刚写的值又抹掉。
  late final Future<void> _ready;

  bool _disposed = false;

  int _timerMinutes = defaultTimerMinutes;
  int? _remainingSeconds;
  Timer? _countdown;

  /// 正在播放的音效 id，`null` 表示没在放。
  ///
  /// **不从会话里恢复**：恢复了高亮却没有真的出声，就是在宣称一件没发生的事。
  String? _activeId;

  double _volume = 0.5;

  /// 上次落库的音量百分点，避免拖动时每一帧都写一次库。
  int _persistedPercent = 50;

  String? _failure;

  String? get activeId => _activeId;
  double get volume => _volume;
  int get timerMinutes => _timerMinutes;
  int? get remainingSeconds => _remainingSeconds;
  String? get failure => _failure;
  bool get isPlaying => _activeId != null;

  NoiseOption? get activeOption {
    final id = _activeId;
    if (id == null) return null;
    for (final option in kNoiseOptions) {
      if (option.id == id) return option;
    }
    return null;
  }

  /// `12:34` 形式的剩余时长，没在倒计时时为 `null`。
  String? get remainingLabel {
    final remaining = _remainingSeconds;
    if (remaining == null) return null;
    final minutes = remaining ~/ 60;
    final seconds = remaining % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  /// 冷启动对账 + 读回上次的音量。
  ///
  /// 进程被系统杀掉时播放器早就没了，库里若还写着「在播」（`noiseId` 非空）就是一个
  /// 假值——这一列的定义是「选中**并正在播放**」。这里把它清掉，并取回会话记住的音量。
  Future<void> _load() async {
    final session = await _repository.load();
    if (session != null && session.noiseId != null) {
      await _repository.update(noiseId: null);
    }
    _volume = session?.noiseVolume ?? 0.5;
    _persistedPercent = (_volume * 100).round();
    _notify();
  }

  Future<void> select(NoiseOption option) async {
    await _ready;
    AppHaptics.select();

    if (_activeId == option.id) {
      await stop();
      return;
    }

    final kind = NoiseKind.fromId(option.id);
    if (kind == null) return;

    try {
      // 先 await 再显示为播放中：第一次选一个音还要现场合成，先翻界面会留下一个
      // 对着静音的停止按钮。
      await _player.play(kind, volume: _volume);
    } on NoisePlaybackFailure catch (failure) {
      _activeId = null;
      _failure = failure.message;
      _notify();
      return;
    }

    await _repository.update(noiseId: option.id);
    if (_disposed) return;
    _activeId = option.id;
    _failure = null;
    // 没有「不限」：选中即起倒计时，白噪音不会整晚占着录音通道。
    _startTimer(_timerMinutes);
    _notify();
  }

  /// 停掉播放，并清空会话里的选中值。
  ///
  /// 倒计时到点、用户取消选择、以及**会话结束/丢弃**（Task 7）都走它。
  Future<void> stop() async {
    _countdown?.cancel();
    _countdown = null;
    _activeId = null;
    _remainingSeconds = null;
    _failure = null;
    await _player.stop();
    await _repository.update(noiseId: null);
    _notify();
  }

  void selectTimer(int minutes) {
    AppHaptics.select();
    _countdown?.cancel();
    _countdown = null;
    _timerMinutes = minutes;
    _remainingSeconds = null;
    if (_activeId != null) {
      _startTimer(minutes);
    }
    _notify();
  }

  void changeVolume(double value) {
    _volume = value;
    // 拖动要保持跟手：播放器调用与落库都不阻塞手势。
    _player.setVolume(value);
    final percent = (value * 100).round();
    if (percent != _persistedPercent) {
      _persistedPercent = percent;
      unawaited(_repository.update(noiseVolume: value));
    }
    _notify();
  }

  void _startTimer(int minutes) {
    _countdown?.cancel();
    _remainingSeconds = minutes * 60;
    _countdown = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final remaining = _remainingSeconds;
    if (remaining == null) return;
    if (remaining <= 1) {
      unawaited(stop());
      return;
    }
    _remainingSeconds = remaining - 1;
    _notify();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _countdown?.cancel();
    _countdown = null;
    // 播放器不归它释放——那是 `noisePlayerProvider` 的事。
    super.dispose();
  }
}

/// 播放器的注入口，也是它的**所有者**。
///
/// 测试用 `overrideWithValue` 换成假实现（与 `NoiseSheet` 的 `player` 接缝同款）；
/// 被注入的那个不归它释放——测试自备，别在用例之间共享。
final noisePlayerProvider = Provider<NoisePlayer>((ref) {
  final player = NoisePlayer();
  ref.onDispose(() => unawaited(player.dispose()));
  return player;
});

/// app 级的白噪音控制器：比任何一页都长命，所以收起抽屉、pop 会话页都不会打断它。
final noiseSessionControllerProvider =
    ChangeNotifierProvider<NoiseSessionController>((ref) {
  return NoiseSessionController(
    repository: ref.watch(sessionRepositoryProvider),
    player: ref.watch(noisePlayerProvider),
  );
});
