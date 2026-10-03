import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/database/app_database.dart' as db;
import '../features/sleep/data/clip_store.dart';
import '../features/sleep/data/night_recorder.dart';
import '../features/sleep/data/session_repository.dart';
import '../features/sleep/domain/clip_journal.dart';
import 'noise_session.dart';

/// 把「录音开关 / 白噪音 / 会话」三件事撮合到一起。
///
/// **它比会话页长命**，与 [NoiseSessionController] 同一手法：用户在会话进行中
/// 收起页面，录音要继续跑。藏在页面 `State` 里的写法会造出「库里写着录了一晚、
/// 实际早就停了」的假状态。
///
/// 撮合规则（会话规格 §六 的裁定）：
/// - 开关关着 → 不录。
/// - **白噪音在播 → 不录，等它停下来**。两者不重叠，而且是白噪音优先：白噪音
///   的任务是在你还醒着的时候把你送睡着，录音是睡着之后的事；而且白噪音在房间里
///   长期高于触发阈值，录进去会让每一段都被判成「有声响」，切片彻底失去意义。
/// - 白噪音停了（倒计时到点，或用户手动停）→ 开关为开就开始录。
class NightRecordingController extends ChangeNotifier {
  NightRecordingController({
    required SessionRepository repository,
    required NightRecorder recorder,
    required ClipFileStore files,
    required ValueListenable<bool> noisePlaying,
    required Future<bool> Function() recordingEnabled,
  })  : _repository = repository,
        _recorder = recorder,
        _files = files,
        _noisePlaying = noisePlaying,
        _recordingEnabled = recordingEnabled {
    _recorderStatus = _recorder.status;
    _recorderStatus.addListener(_onRecorderStatus);
    _noisePlaying.addListener(_onNoiseChanged);
    _clipSub = _recorder.closedClips.listen(_onClipClosed);
  }

  final SessionRepository _repository;
  final NightRecorder _recorder;
  final ClipFileStore _files;
  final ValueListenable<bool> _noisePlaying;
  final Future<bool> Function() _recordingEnabled;

  late final ValueListenable<NightRecordingStatus> _recorderStatus;
  StreamSubscription<ClipDraft>? _clipSub;

  /// 这一晚已经录到的片段。**与数据库里那份清单保持同步**，不是它的缓存副本——
  /// 每次变动都整份写回去，读回来的永远是唯一的真相。
  List<ClipDraft> _journal = const [];

  /// 清单写库的串行链。`stopForSessionEnd` 要等它排空——会话结束那一刻写进去的
  /// 最后一条，正是最容易被漏掉的那一条。
  Future<void> _pendingWrite = Future<void>.value();

  bool _disposed = false;
  bool _sessionActive = false;

  NightRecordingStatus get status {
    if (!_sessionActive) return const NightRecordingStatus.idle();
    if (_noisePlaying.value && !_recorderStatus.value.isRecording) {
      return const NightRecordingStatus(NightRecordingState.waitingForNoise);
    }
    return _recorderStatus.value;
  }

  /// 这一晚录到的片段条数，供会话页显示。
  int get clipCount => _journal.length;

  /// 会话开始时调。**只负责把状态对齐**：到底录不录由开关与白噪音决定，
  /// 调用它不等于开始录。
  Future<void> syncWithSession() async {
    final session = await _repository.load();
    if (_disposed) return;

    _sessionActive = session != null;
    // 清单从库里读回来：进程被杀过一次再重启，之前录到的片段还在这一行里。
    _journal = session?.clipJournal ?? const [];
    _notify();

    await _reconcile();
  }

  /// 「删除全部录音」之后调它：把当前会话清单里的文件指针一并清空。
  ///
  /// **不清的话，那一晚会带着一串指向已删文件的 `localUri` 结束。** 片段行本身
  /// 要留着（声响确实发生过，事件记录不该凭空消失），但它不能再宣称音频还在——
  /// 详情页据此判定「可回放」，用户点下去才发现文件早没了。
  ///
  /// 只动指针，不删清单里的条目。
  Future<void> forgetRecordings() async {
    final session = await _repository.load();
    if (session == null || session.clipJournal.isEmpty) return;

    final cleared = [
      for (final draft in session.clipJournal)
        ClipDraft(
          id: draft.id,
          startedAtUtc: draft.startedAtUtc,
          durationMs: draft.durationMs,
          // 指针清空，条目保留——事件记录还在，只是音频没了。
          localUri: null,
          envelope: draft.envelope,
        ),
    ];
    _journal = cleared;
    await _repository.update(clipJournal: cleared);
    _notify();
  }

  /// 偏好刚被改过时调它，把录音的实际状态重新对齐一次。
  ///
  /// 会话页那个开关写的就是 `AppSettings.soundRecordingEnabled`；不去叫它一声的话，
  /// 用户关掉开关之后录音会一直录到这一晚结束——一个「已经关掉却还在录」的麦克风，
  /// 是这一整块最不能有的状态。
  Future<void> refresh() => _reconcile();

  /// 会话结束 / 丢弃之前必须调它。
  ///
  /// **顺序不能反**：`finish()` 要在同一个事务里读这一行会话的片段清单来落片段行，
  /// 如果这时候还在录，那一段就赶不上这趟车。所以这里先把录音收尾，**并且等最后
  /// 一次清单落完库**，再把控制权交回调用方。
  Future<void> stopForSessionEnd() async {
    await _recorder.stop();
    // 收尾吐出来的那一条是**同步**投递的，`_journal` 此刻已经带上它；但写库还是
    // 异步的，不等这一步的话 `finish()` 读到的会是少一条的旧清单。
    await _pendingWrite;
    _sessionActive = false;
    _notify();
  }

  /// 丢弃这一晚：先把录音停掉，再把这一晚已经录到的文件删掉。
  ///
  /// **必须在 `discard()` 之前调**（会话行还在的时候），否则收尾那一段的清单
  /// 没有地方可写，它的文件就成了孤儿——启动时的孤儿清理确实会删掉它，但那要等
  /// 到下一次启动，中间它一直在占着空间。
  ///
  /// 用户丢掉这一晚，音频没有理由留着。
  Future<void> discardRecordings() async {
    // **先停、再读清单。** 顺序反过来的话：还在录的那一段会在 `stop()` 里被收尾、
    // 落盘、通过 `closedClips` 同步进 `_journal`——而它不在先前那份快照里，
    // 于是它的文件永远不会被删，变成一个要等到下次启动才被扫掉的孤儿。
    // 这恰恰是「用户丢掉这一晚，音频没有理由留着」要挡住的东西。
    await stopForSessionEnd();

    // 停完之后才读库：`stopForSessionEnd` 已经等过最后一次写，所以库里这份是**完整**
    // 的。它同时兜住了「控制器从没对账过、内存清单还是空的」那种情形——只信内存
    // 的话，那种情况下一个文件都删不掉。
    final session = await _repository.load();
    final drafts = session?.clipJournal ?? _journal;

    for (final draft in drafts) {
      await _files.deleteClip(draft.localUri);
    }
    _journal = const [];
    _notify();
  }

  Future<void> _reconcile() async {
    if (_disposed) return;

    // **每次都重新读一次会话，而不是信 `_sessionActive` 这个内存标记。**
    // 会话可能是从别处消失的（设置页的「删除全部本地数据」、另一个页面里的丢弃），
    // 而 `_onNoiseChanged` 恰恰会在那些路径里被叫醒——`teardownSession` 会停白噪音。
    // 信旧标记的话，删完全部数据、白噪音一停，录音反而被启起来。
    final session = await _repository.load();
    if (_disposed) return;

    if (session == null) {
      _sessionActive = false;
      await _recorder.stop();
      _notify();
      return;
    }

    _sessionActive = true;
    _journal = session.clipJournal;

    if (!await _recordingEnabled()) {
      await _recorder.stop();
      _notify();
      return;
    }
    // 白噪音在播就先等它——`_onNoiseChanged` 会在它停下时把我们叫回来。
    if (_noisePlaying.value) {
      _notify();
      return;
    }

    if (_disposed) return;

    // **权限闸口放在这里，而不是每个开关各写一遍。** 会话页、设置页、入睡前态那三
    // 处开关，加上冷启动恢复，走到的都是这一个方法。少了它，一个从没给过权限的用户
    // 打开开关时看到的会是平台抛回来的原始报错，而不是一句「没有麦克风权限」。
    //
    // 被拒时**不去开一个注定失败的麦克风**，也不改状态：界面读到的仍是
    // `idle`，于是如实显示「已开启，但现在没有在录」——它确实没在录。
    if (!await _recorder.ensurePermission()) {
      debugPrint('没有麦克风权限，夜间录音未开始。');
      _notify();
      return;
    }
    if (_disposed) return;

    try {
      await _recorder.start();
    } catch (error) {
      // 录不了就如实说录不了，**绝不留下一个写着「录音中」的假状态**。
      // 状态由 `_recorder` 自己转成 `stopped` 并带上原因，这里只负责不吞掉它。
      debugPrint('夜间录音起不来：$error');
    }
    _notify();
  }

  void _onNoiseChanged() {
    // 白噪音停了 → 该开始了。白噪音起播 → 录音那边由 `_reconcile` 的等待分支挡住，
    // 这里不需要做别的（会话期间白噪音只会被停掉，不会被起播）。
    if (!_noisePlaying.value) unawaited(_reconcile());
    _notify();
  }

  void _onRecorderStatus() => _notify();

  void _onClipClosed(ClipDraft draft) {
    if (_disposed) return;
    _journal = [..._journal, draft];
    // 立刻落库，不攒着。这一行就是「App 被杀之后还能不能保住整晚录音」的全部依据。
    // 用链式 Future 而不是 `await`：这个回调是**同步**的（`closedClips` 是同步流），
    // 而写库要排到 `stopForSessionEnd` 里去等。
    final snapshot = _journal;
    _pendingWrite = _pendingWrite.then(
      (_) => _repository.update(clipJournal: snapshot),
      onError: (Object error) {
        // 一次写失败不该让链断掉——链上任何一环抛出去，后面每一次写都会跟着失败，
        // 而那时候用户看到的会是「录了一晚、片段时间轴停在半夜」。
        debugPrint('写入片段清单失败：$error');
      },
    );
    _notify();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _recorderStatus.removeListener(_onRecorderStatus);
    _noisePlaying.removeListener(_onNoiseChanged);
    unawaited(_clipSub?.cancel());
    _clipSub = null;
    // 录音器与播放器都不归它释放——那是各自 provider 的事。
    super.dispose();
  }
}

final nightRecordingControllerProvider =
    ChangeNotifierProvider<NightRecordingController>((ref) {
  final recorder = ref.watch(nightRecorderProvider);
  final noise = ref.watch(noiseSessionControllerProvider);
  final database = ref.watch(db.databaseProvider);

  // `NoiseSessionController` 是 `ChangeNotifier`，`isPlaying` 是它的一个属性；
  // 这里要的是一个**只暴露那个布尔**的 `ValueListenable`，所以套一层。
  // 它由 provider 创建，也就得由 provider 释放。
  final noisePlaying = _NoisePlayingNotifier(noise);
  ref.onDispose(noisePlaying.dispose);

  return NightRecordingController(
    repository: ref.watch(sessionRepositoryProvider),
    recorder: recorder,
    files: ref.watch(clipFileStoreProvider),
    noisePlaying: noisePlaying,
    recordingEnabled: () async {
      final settings = await database.getSettings();
      return settings.soundRecordingEnabled;
    },
  );
});

/// 把 `NoiseSessionController.isPlaying` 投影成一个 `ValueListenable<bool>`。
///
/// 直接监听整个控制器也行，但那样音量拖动（每帧一次 `notifyListeners`）会连带
/// 把录音控制器叫醒；只投影这一个布尔，唤醒次数就只跟真正相关的变化走。
class _NoisePlayingNotifier extends ValueNotifier<bool> {
  _NoisePlayingNotifier(this._source) : super(_source.isPlaying) {
    _source.addListener(_sync);
  }

  final NoiseSessionController _source;

  void _sync() => value = _source.isPlaying;

  @override
  void dispose() {
    _source.removeListener(_sync);
    super.dispose();
  }
}
