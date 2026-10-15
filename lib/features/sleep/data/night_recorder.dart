import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';

import '../../../core/platform/night_audio_service.dart';
import '../domain/clip_journal.dart';
import '../domain/clip_segmentation.dart';
import 'clip_store.dart';
import 'pcm_ring.dart';
import 'wav_file.dart';

/// 录音服务此刻在做什么。
///
/// **这四个值都必须是实际状态，不是偏好值。** 一个整夜开着麦克风的功能，
/// 界面上的「录音中」不能只是把设置里的那个开关回显一遍——那正是偏差 #7 当初
/// 挡的事：让控件声称一个它并不具备的状态。
enum NightRecordingState {
  /// 没在录：开关关着，或会话还没开始。
  idle,

  /// 白噪音在播，等它停下来。**这段空档是真的不录**，界面必须写出来。
  waitingForNoise,

  /// 正在录。
  recording,

  /// **在录，但平台交上来的是静音**——连续收了一段时间的逐样本全零。
  ///
  /// 与 [stopped] 分开是必须的：流还活着、采样还在源源不断地来，只是每一个都是 0。
  /// 麦克风可能在下一秒就回来（实测 Android 上应用一回到前台就恢复），所以这时候说
  /// 「已停止」是假的，说「录音中」也是假的——它既不响，也没停。
  silenced,

  /// 录过，但已经停了（来电抢占、出错、被系统中断）。
  stopped,
}

@immutable
class NightRecordingStatus {
  const NightRecordingStatus(this.state, {this.reason});

  const NightRecordingStatus.idle() : this(NightRecordingState.idle);

  final NightRecordingState state;

  /// 为什么停的。只对 [NightRecordingState.stopped] 有意义，是给用户看的一句话。
  final String? reason;

  bool get isRecording => state == NightRecordingState.recording;

  @override
  bool operator ==(Object other) =>
      other is NightRecordingStatus &&
      other.state == state &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(state, reason);
}

/// 采集格式。规格 §二 定死的三个值，写在一处免得实现里各写各的。
///
/// **16kHz 单声道**：鼾声与梦话的能量都在 8kHz 以内，再高只是白写盘。
/// `autoGain` / `echoCancel` / `noiseSuppress` 三个开关全部关掉——它们都会改变信号，
/// 开着就等于让实测包络变成对处理链的测量，而不是对房间的测量。
const kRecordSampleRate = 16000;
const kRecordChannels = 1;
const kRecordBytesPerSample = 2;

/// 振幅聚合窗口。固定 100ms，与插件吐出来的分片大小无关——否则同一段音频在
/// 不同设备上会切出不同的片段。
const kAmplitudeWindow = Duration(milliseconds: 100);

/// **采集源试过 `UNPROCESSED`，2026-10-15 当晚就回退了——记在这里免得有人再试一遍。**
///
/// 想法本来是对的：`record` 插件在 Android 上默认走
/// `MediaRecorder.AudioSource.DEFAULT`，厂商（MIUI 尤其）会在这条路上叠自己的处理
/// （高通、降噪、AGC），正是上面那段注释要挡的东西；而 `autoGain: false` 这类开关
/// **只是不去主动打开**处理，保证不了厂商的处理不在。Android 也确实为「我要未经处理
/// 的音频」提供了 `UNPROCESSED`。
///
/// **但它在这台 MI 9（MIUI 12.5.6 / API 30）上会静默地录不到东西。** 判据是
/// `logcat` 里这一行：
///
/// ```
/// AudioRecord: set(): inputSource 9, sampleRate 16000, ... com.example.night_sleep
/// ```
///
/// `inputSource 9` 就是 `UNPROCESSED`——**源打开成功了**（没抛异常，所以「打不开就
/// 退回默认源」那条路根本不会触发），然后以它录了 66 秒，**一个片段都没产生**。
///
/// **教训不是「别换源」，是「只在异常上做回退不够」。** 设备的失败模式有两种：
/// 打不开（抛异常）与**打开了、不报错、但交静音**。后者要靠
/// [kSilentMicRun] 那种「收了一段时间逐样本全零」的实测判据才认得出，而那时人已经
/// 醒了一夜。所以这里**刻意不指定采集源**，就用插件的默认值。
/// 完整经过见 [验证记录](../../../../docs/verification-log.md) v3.28。

/// 连续这么多**逐样本全零**的振幅格之后，认定麦克风没有在收音。
///
/// **与切片那七个参数一样是拍的**，待真机标定。判据取「每一个采样都正好是 0」而不是
/// 「很安静」，因为这两件事完全不同：真实麦克风永远有本底噪声（实测这台机器上这间房
/// 约 −55 dBFS），一整格 1600 个采样全是 0 只可能是**平台没有把麦克风的声音交给应用**。
/// 所以这是一次测量，不是一次猜测。
///
/// 60 秒给得很宽：起录瞬间的空缓冲、以及任何真实的安静房间都够不到它。实测 Android 上
/// （MI 9 / Android 11）灭屏之后平台会静音录音端口、并持续交付零样本，触发时延是秒级。
const kSilentMicRun = Duration(seconds: 60);

/// 判定「麦克风被静音」时给用户看的那句话。
///
/// 「系统静音」这一半在 Android 上是实测过的（`AudioFlinger: setRecordSilenced(…),
/// portId:<本应用的录音端口>, silenced 1`，见 `docs/verification-log.md` v3.19）；
/// 在其他平台上，同样的「逐样本全零」只说明输入设备没有在收音，措辞仍然成立。
const kSilencedMicReason = '麦克风被系统静音 · 现在录不到声音';

/// 应用不在前台、起不了前台服务时给用户看的那句话。
///
/// 这条路的典型来法是**白噪音倒计时到点，而那时应用已经在后台 / 锁屏**：Dart 的
/// `Timer.periodic` 只要进程还活着就照常到点，醒来就去起前台服务，而 Android 12+
/// 后台起前台服务直接抛异常、API 30 上不抛但麦克风照样是静音的。
///
/// 所以**不进入录音态、也不去开一个注定收到静音的麦克风**——界面如实写这一句，
/// 而不是先写「录音中」再等 60 秒翻成「麦克风被系统静音」。
const kNotForegroundReason = '应用不在前台 · 暂时无法开始录音';

/// 应用缺少后台录音所需权限时给用户看的那句话。
///
/// **措辞刻意指向应用，不是指向设备。** 走到这里说明「装着的这个包」与「这段代码」
/// 对不上（清单里少声明，或麦克风权限此刻不在手里），而**不是**这台机器不行——
/// 与 `compass.dart` 那条「平台未实现 ≠ 设备不行」的红线同一口径。
const kMissingForegroundPermissionReason = '当前版本缺少后台录音权限 · 请更新应用';

/// 采集端的缝。
///
/// 把 `record` 插件挡在这个接口后面，单元测试才能喂一段合成的 PCM 而不是去开真
/// 麦克风（`Provider.overrideWithValue` 是这个项目的既有做法）。
abstract class PcmInput {
  Future<bool> ensurePermission();

  /// 开始采集，返回裸小端 PCM16 的字节流。
  Future<Stream<Uint8List>> startStream();

  Future<void> stop();

  Future<void> dispose();

  /// 被外部打断（来电、别的应用抢麦克风）时发一个事件，参数是给用户看的原因。
  Stream<String> get interruptions;
}

/// 夜间录音的采集端。
///
/// 抽成接口是为了让 widget / 单元测试注入假实现——**这条链路一个测试都不该碰
/// 真实的麦克风**。
abstract class NightRecorder {
  /// 当前状态。界面订阅它来显示「录音中」/「白噪音播放中 · 暂不录音」/ 停止原因。
  ValueListenable<NightRecordingStatus> get status;

  /// 每录完一段就吐一条。**上层拿到就要立刻写进会话行的片段清单**，
  /// 攒着的话 App 被杀就等于整晚录音全丢。
  Stream<ClipDraft> get closedClips;

  /// 申请麦克风权限，已经给了就返回 true。用户打开开关时调。
  Future<bool> ensurePermission();

  /// 开始采集。失败时**不进入录音态**，抛出说明原因的错误。
  Future<void> start();

  /// 停止采集并收尾正在录的那一段。已经在录的片段不丢。
  Future<void> stop();

  Future<void> dispose();
}

/// 真实实现：`record` 插件的 PCM16 流 → 振幅序列 → 切片 → 一段一个 WAV 文件。
///
/// **不边录边开文件。** 采集到的 PCM 一直写进一个有界的环形缓冲（覆盖最近
/// [kCaptureWindow]），等切片状态机判定某一段成立时，再按字节偏移把那段从缓冲里
/// 切出来落盘。这样做的理由有三个：
///
/// 1. **切片规则只有一份**。什么时候算一段、两段要不要合并，全部由
///    [ClipSegmenter] 说了算；如果改成「一越阈值就开文件、静音就收尾」，那套规则
///    就得在采集端再写一遍，两份迟早会分叉。
/// 2. **合并与丢弃都能事后修正**。一段声响刚开始时还说不准它是不是只有 0.3 秒
///    （该丢）、后面 1 秒内会不会再来一段（该并）——先落盘再回头删文件既费事又
///    容易留下垃圾。
/// 3. **峰值内存有界**。窗口固定 75 秒 ≈ 2.4 MB，与录多久无关。
///
/// 代价如实记下：进程在片段定案之前被杀，那一段最多 75 秒的音频会丢。这与
/// 「重启后以数据库里真实的片段为准」是同一条口径——库里没有的，不假装有。
class RecordNightRecorder implements NightRecorder {
  RecordNightRecorder({
    required ClipFileStore files,
    required PcmInput input,
    NightAudioService audioService = const NoopNightAudioService(),
    ClipParams params = const ClipParams(),
    DateTime Function() clock = DateTime.now,
  })  : _files = files,
        _input = input,
        _audioService = audioService,
        _params = params,
        _clock = clock;

  /// 覆盖「最长片段 + 合并间隔 + 静音时长 + 前置 padding」再留点余量。
  /// 一个片段从起音到定案，时间跨度不会超过这个窗口。
  static const kCaptureWindow = Duration(seconds: 75);

  static const _bytesPerSecond =
      kRecordSampleRate * kRecordChannels * kRecordBytesPerSample;

  final ClipFileStore _files;
  final PcmInput _input;

  /// 前台服务开关，见 `lib/core/platform/night_audio_service.dart`。
  ///
  /// **默认值是空实现**（返回 `unsupported`，一切照旧）：`test/night_recorder_test.dart`
  /// 里那些直接 `new` 本类的用例一行都不用改，也不会因此碰真平台通道。
  /// 真实接线在 [nightRecorderProvider]，那里注入 `MethodChannelNightAudioService`。
  final NightAudioService _audioService;

  final ClipParams _params;
  final DateTime Function() _clock;

  final ValueNotifier<NightRecordingStatus> _status =
      ValueNotifier(const NightRecordingStatus.idle());

  /// **同步投递**：`stop()` 收尾最后一段时，订阅方必须在那次 `await` 返回之前
  /// 就拿到这一条。换成异步投递的话，`finish()` 会赶在「最后一段已经写进清单」
  /// 之前去读那一行会话，最后一段就赶不上这趟车——而它恰恰是最容易被漏掉的一段
  /// （一次会话只有一段时，漏掉的就是全部）。
  final StreamController<ClipDraft> _clips =
      StreamController<ClipDraft>.broadcast(sync: true);

  StreamSubscription<Uint8List>? _pcmSub;
  StreamSubscription<String>? _interruptionSub;

  PcmRing? _ring;
  ClipSegmenter? _segmenter;

  /// 振幅窗口的累积器：攒够 [kAmplitudeWindow] 那么多字节就算一格。
  final BytesBuilder _windowBytes = BytesBuilder();

  /// 采集以来一共写进来多少字节。绝对偏移全靠它——环形缓冲只给「最近 N 字节」，
  /// 得自己换算成绝对位置才知道某一段在哪。
  int _totalBytes = 0;

  /// 当前窗口已经攒到的字节数。
  int _windowFill = 0;

  int _windowIndex = 0;

  /// 连续收到了多少格逐样本全零。任何一格不是全零就归零——它要的是"连续"，
  /// 不是"累计"。
  int _zeroRun = 0;

  /// 还在窗口内的振幅采样点，供 [envelopeFor] 算包络。与 PCM 缓冲同一时间跨度。
  final List<AmplitudeSample> _samples = [];

  /// 正在写的片段文件。
  ///
  /// **不是可有可无的记账。** 切片在流里定案时是在一个同步回调里，写文件却是异步的；
  /// 不把它们收起来，`stop()` 就会在最后一个片段还没落盘、还没通过 `closedClips`
  /// 送达上层时返回——而 `finish()` 紧接着就去读会话行里的片段清单了。一次会话只有
  /// 一段的时候（比如整夜就响了一声），漏掉的就是全部。
  final List<Future<void>> _writes = [];

  /// 会话开始时的那一刻。片段的墙上时刻 = 它 + 采样偏移。
  DateTime? _sessionStartUtc;

  bool _running = false;

  @override
  ValueListenable<NightRecordingStatus> get status => _status;

  @override
  Stream<ClipDraft> get closedClips => _clips.stream;

  @override
  Future<bool> ensurePermission() => _input.ensurePermission();

  @override
  Future<void> start() async {
    if (_running) return;
    _reset();

    // **先起前台服务、后开流。** 顺序反了会有一段真实的空窗：`startStream()` 已经
    // 返回、麦克风已经在采，但前台服务还没起——这半秒里平台按「应用不在前台」的规则
    // 静音录音端口，交上来的是一格全零（**不报错**），它会跟着流一路记进状态里。
    final service = await _audioService.start();
    switch (service) {
      case NightAudioServiceResult.started:
      case NightAudioServiceResult.unsupported:
      case NightAudioServiceResult.failed:
        // 后两种照旧往下走：iOS 根本没有这条通道，平台侧偶发失败时应用也还在前台，
        // 录音本来就能录。**不能因为拿不到前台服务就把流拦下来。**
        break;
      case NightAudioServiceResult.notForeground:
        // 应用此刻不可见：系统不许这么起服务，就算硬起，麦克风也是静音的。
        // **不进入录音态、不开流**，如实说出原因。
        _status.value = const NightRecordingStatus(
          NightRecordingState.stopped,
          reason: kNotForegroundReason,
        );
        throw StateError(kNotForegroundReason);
      case NightAudioServiceResult.missingPermission:
        _status.value = const NightRecordingStatus(
          NightRecordingState.stopped,
          reason: kMissingForegroundPermissionReason,
        );
        throw StateError(kMissingForegroundPermissionReason);
    }

    final Stream<Uint8List> stream;
    try {
      stream = await _input.startStream();
    } catch (error) {
      // 服务已经起来了、流却没起来：**把服务撤掉再抛**。留着的话通知栏会挂一条
      // 「正在录制」，而实际上一个采样都不采——一个控件声称它并不具备的状态。
      if (service == NightAudioServiceResult.started) {
        await _stopServiceQuietly();
      }
      _status.value = NightRecordingStatus(
        NightRecordingState.stopped,
        reason: '无法开始录音：$error',
      );
      rethrow;
    }

    _running = true;
    _pcmSub = stream.listen(
      _onPcm,
      onError: (Object error) => _stopWithReason('录音中断：$error'),
      cancelOnError: false,
    );
    _interruptionSub = _input.interruptions.listen(
      (reason) => _stopWithReason(reason),
    );
    _status.value = const NightRecordingStatus(NightRecordingState.recording);
  }

  @override
  Future<void> stop() async {
    if (!_running) return;
    _running = false;

    await _pcmSub?.cancel();
    _pcmSub = null;
    await _interruptionSub?.cancel();
    _interruptionSub = null;
    try {
      await _input.stop();
    } catch (error) {
      // 停不下来不该把已经录到的片段连累掉——下面照样把尾巴收尾、照样落盘。
      debugPrint('停止录音时出错：$error');
    }
    // **先停流、后撤服务。** 反了的话，从撤服务到真的停流之间麦克风已经不被保着，
    // 收尾那半秒会被记成一格全零——而 `_flush()` 就排在下面，它可能在把尾巴定案
    // 之前先把状态翻成 `silenced`，一段原本完好的录音被自己抹黑。
    await _stopServiceQuietly();

    await _flush();
    // `silenced` 也要落回 idle：它是"在录但收不到声音"，主动停下来之后那个状态
    // 就不再成立，留着会让界面在会话已经结束之后继续说"麦克风被静音"。
    switch (_status.value.state) {
      case NightRecordingState.recording:
      case NightRecordingState.silenced:
        _status.value = const NightRecordingStatus.idle();
      case NightRecordingState.idle:
      case NightRecordingState.waitingForNoise:
      case NightRecordingState.stopped:
        break;
    }
  }

  Future<void> _stopWithReason(String reason) async {
    if (!_running) return;
    _running = false;
    await _pcmSub?.cancel();
    _pcmSub = null;
    await _interruptionSub?.cancel();
    _interruptionSub = null;
    try {
      await _input.stop();
    } catch (_) {
      // 已经被抢走了，停不掉是正常的。
    }
    // 与 `stop()` 同一顺序：先停流、后撤服务。
    await _stopServiceQuietly();
    await _flush();
    // **已经录到的片段不丢**，只是不再往下录了。
    _status.value = NightRecordingStatus(
      NightRecordingState.stopped,
      reason: reason,
    );
  }

  /// 撤掉前台服务，**永不抛**。
  ///
  /// 收尾这一段（停流 → 撤服务 → `_flush()`）绝不能因为平台侧的失败而中断：
  /// `_flush()` 决定的是「已经录到的片段还在不在」，那是整晚录音里最不能丢的东西。
  Future<void> _stopServiceQuietly() async {
    try {
      await _audioService.stop();
    } catch (error) {
      debugPrint('撤前台服务时出错：$error');
    }
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _clips.close();
    await _input.dispose();
    _status.dispose();
  }

  void _reset() {
    _ring = PcmRing.forDuration(
      kCaptureWindow,
      sampleRate: kRecordSampleRate,
      channels: kRecordChannels,
    );
    _segmenter = ClipSegmenter(_params);
    _windowBytes.clear();
    _totalBytes = 0;
    _windowFill = 0;
    _windowIndex = 0;
    _zeroRun = 0;
    _samples.clear();
    _writes.clear();
    _sessionStartUtc = _clock().toUtc();
  }

  void _onPcm(Uint8List chunk) {
    if (!_running || chunk.isEmpty) return;

    _ring!.write(chunk);
    _totalBytes += chunk.length;

    // 按字节攒窗口，而不是假设每一个分片正好是整数个窗口——上游不保证对齐。
    var consumed = 0;
    final windowBytes = _bytesPerWindow;
    while (consumed < chunk.length) {
      final take = math.min(windowBytes - _windowFill, chunk.length - consumed);
      _windowBytes.add(Uint8List.sublistView(chunk, consumed, consumed + take));
      consumed += take;
      _windowFill += take;
      if (_windowFill == windowBytes) {
        _closeWindow();
      }
    }
  }

  void _closeWindow() {
    final bytes = _windowBytes.takeBytes();
    _windowBytes.clear();
    _windowFill = 0;

    final analysed = _analyseWindow(bytes);
    final sample = AmplitudeSample(
      offset: Duration(microseconds: _windowIndex * 100000),
      dbfs: analysed.dbfs,
    );
    _windowIndex++;

    _trackSilence(analysed.allZero);

    _samples.add(sample);
    _trimWindow();

    final segmenter = _segmenter;
    if (segmenter == null) return;
    for (final range in segmenter.add(sample)) {
      _writes.add(_writeClip(range));
    }
  }

  /// 序列结束（停止录音）时，把还挂着的那一段收尾。
  ///
  /// 尾巴上不足一个窗口的字节也要算一格——不然一整夜的最后半秒会凭空消失。
  Future<void> _flush() async {
    if (_windowFill > 0) _closeWindow();

    final segmenter = _segmenter;
    if (segmenter != null) {
      for (final range in segmenter.flush()) {
        _writes.add(_writeClip(range));
      }
    }
    _segmenter = null;

    // **等全部写完再返回。** 上层（`stopForSessionEnd`）就是靠这个 `await` 才敢说
    // 「最后一段已经在清单里了」，`finish()` 也才敢去读那一行会话。
    await _drainWrites();
  }

  /// 把正在写的片段全部等完。
  ///
  /// 用循环而不是一次 `Future.wait`：写文件的那几步里还会再定案出新的片段
  /// （`_writeClip` 本身不改列表，但它的 `closedClips` 订阅方可能会），循环到
  /// 列表真的空为止才叫排空。
  Future<void> _drainWrites() async {
    while (_writes.isNotEmpty) {
      final pending = List<Future<void>>.of(_writes);
      _writes.clear();
      await Future.wait(pending);
    }
  }

  /// 把落在 [range] 里的 PCM 从环形缓冲里切出来写成一个 WAV 文件。
  Future<ClipDraft> _writeClip(ClipRange range) async {
    final start = _sessionStartUtc;
    final ring = _ring;
    final startedAtUtc = (start ?? _clock().toUtc()).add(range.start);
    final durationMs = range.end.inMilliseconds - range.start.inMilliseconds;
    // id 由片段起始时刻生成，天然有序。
    final id = 'clip-${startedAtUtc.microsecondsSinceEpoch}';

    final draft = ClipDraft(
      id: id,
      startedAtUtc: startedAtUtc,
      durationMs: durationMs,
      localUri: null,
      envelope: envelopeFor(_samples, range),
    );

    if (ring == null || !_withinWindow(range)) {
      // 缓冲区已经滚过了这一段——只在极端情况下发生（事件跨度比窗口还长）。
      // 没有音频就不写文件，但事件行还是要留：**有过一段声响**这件事是真的。
      final withoutAudio = ClipDraft(
        id: draft.id,
        startedAtUtc: draft.startedAtUtc,
        durationMs: draft.durationMs,
        localUri: null,
        envelope: draft.envelope,
      );
      _clips.add(withoutAudio);
      return withoutAudio;
    }

    final ringStart = _totalBytes - ring.length;
    // 夹住两端：环形缓冲里没有的部分宁可少写一点，也不让下标越界——那会把一整段
    // 音频连事件行一起弄丢。`slice` 自己也会夹一次，这里是让两端的意图写在明处。
    final from = (_byteOffset(range.start) - ringStart).clamp(0, ring.length);
    final to = (_byteOffset(range.end) - ringStart).clamp(from, ring.length);
    // **只切要的那一段**，不把整块 2.4MB 环形缓冲读出来再丢掉大半。
    final audio = ring.slice(from, to);

    String? path;
    try {
      path = await _files.pathFor(id);
      final writer = WavWriter(
        sampleRate: kRecordSampleRate,
        channels: kRecordChannels,
      );
      await writer.open(path);
      await writer.append(audio);
      await writer.close();
    } catch (error) {
      // 写文件失败**不影响事件本身**：行照样入库，`localUri` 留空，
      // 详情页如实显示「这段录音未保留在本地」。
      debugPrint('写片段文件失败：$error');
      path = null;
    }

    final written = ClipDraft(
      id: draft.id,
      startedAtUtc: draft.startedAtUtc,
      durationMs: draft.durationMs,
      localUri: path,
      envelope: draft.envelope,
    );
    _clips.add(written);
    return written;
  }

  /// 这一段是不是还在缓冲覆盖的时间范围内。
  bool _withinWindow(ClipRange range) {
    final ring = _ring;
    if (ring == null) return false;
    return _byteOffset(range.start) >= _totalBytes - ring.capacityBytes;
  }

  /// 把时间偏移换算成采集以来的绝对字节偏移。采样率固定，所以这是一次乘法。
  int _byteOffset(Duration offset) =>
      offset.inMicroseconds * _bytesPerSecond ~/ 1000000;

  int get _bytesPerWindow =>
      kAmplitudeWindow.inMicroseconds * _bytesPerSecond ~/ 1000000;

  /// 把窗口外的振幅采样点丢掉，只留环形缓冲覆盖的那一段。
  void _trimWindow() {
    final oldest = _totalBytes - (_ring?.capacityBytes ?? 0);
    if (oldest <= 0) return;
    final cutoff = Duration(
      microseconds: _byteOffsetInverse(oldest),
    );
    _samples.removeWhere((sample) => sample.offset < cutoff);
  }

  int _byteOffsetInverse(int bytes) => bytes * 1000000 ~/ _bytesPerSecond;

  /// 一个窗口的 RMS（换算成 dBFS），外加**这一格是不是逐样本全零**。
  ///
  /// 全静音时封底在 −160，不产生 `-Infinity`——那个值传进切片函数会把阈值比较变成
  /// 一片混乱。
  ///
  /// 两件事一起算是因为它们共用同一次求和：`sum == 0` 且只有它，才说明 1600 个采样
  /// 无一例外都是 0。**不能拿「dBFS 等于 −160」当同一件事**——那是个有下限的近似值，
  /// 稍高于它的安静房间也会被压到同一个读数上，两者必须分开。
  ({double dbfs, bool allZero}) _analyseWindow(Uint8List bytes) {
    if (bytes.length < 2) return (dbfs: -160.0, allZero: false);
    final samples = bytes.length ~/ 2;
    var sum = 0.0;
    final view = ByteData.view(bytes.buffer, bytes.offsetInBytes, samples * 2);
    for (var i = 0; i < samples; i++) {
      final value = view.getInt16(i * 2, Endian.little);
      sum += value * value;
    }
    if (sum == 0) return (dbfs: -160.0, allZero: true);
    final rms = math.sqrt(sum / samples);
    if (rms < 1) return (dbfs: -160.0, allZero: false);
    return (
      dbfs: (20 * (math.log(rms / 32768) / math.ln10)).clamp(-160.0, 0.0),
      allZero: false,
    );
  }

  /// 记账「平台是不是正在交静音」，并在跨过 [kSilentMicRun] 时把状态翻过去。
  ///
  /// 两个方向都要走：全零攒够了 → `silenced`；一旦真声音回来 → 立刻回到 `recording`
  /// （实测里这一步是自动的，应用一回到前台平台就解除静音）。**不在这条路上停录**：
  /// 流还活着，停下来才是真的把后面可能回来的声音丢掉。
  void _trackSilence(bool allZero) {
    if (!_running) return;

    if (!allZero) {
      _zeroRun = 0;
      if (_status.value.state == NightRecordingState.silenced) {
        _status.value =
            const NightRecordingStatus(NightRecordingState.recording);
      }
      return;
    }

    _zeroRun++;
    if (_status.value.state != NightRecordingState.recording) return;
    if (kAmplitudeWindow * _zeroRun < kSilentMicRun) return;
    _status.value = const NightRecordingStatus(
      NightRecordingState.silenced,
      reason: kSilencedMicReason,
    );
  }
}

/// 真实采集端：包 `record` 插件。
class RecordPcmInput implements PcmInput {
  RecordPcmInput({AudioRecorder? recorder}) : _injected = recorder;

  /// **`AudioRecorder` 推迟到第一次真正用到时才创建。** 它一构造就会去
  /// `_platform.create(...)`，而那条平台通道在 widget / 单元测试里并不存在——
  /// 急着在这里 `?? AudioRecorder()` 会让所有用到录音 provider 的测试一挂到底，
  /// 哪怕它们根本不录音。与 `NoisePlayer` 推迟创建 `AudioPlayer` 是同一条理由。
  final AudioRecorder? _injected;
  AudioRecorder? _created;

  AudioRecorder get _recorder => _injected ?? (_created ??= AudioRecorder());

  final StreamController<String> _interruptions =
      StreamController<String>.broadcast();

  /// 插件状态流的订阅。**必须留住并在下次起录前取消**：一次会话里起停好几次是常态
  /// （白噪音停了起一次、被抢占后又起一次），每起一次就多挂一个监听，同一个中断事件
  /// 会被投递 N 遍。`_running` 那道守卫挡得住重复的「已停止」，挡不住订阅本身泄漏。
  StreamSubscription<RecordState>? _stateSub;

  @override
  Future<bool> ensurePermission() => _recorder.hasPermission();

  @override
  Future<Stream<Uint8List>> startStream() async {
    await _listenForInterruptions();
    // **不要在这里指定 `androidConfig.audioSource`。** 试过 `UNPROCESSED`，
    // 这台机器上它会静默地什么也不录——理由见上面那段注释。
    return _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: kRecordSampleRate,
        numChannels: kRecordChannels,
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
      ),
    );
  }

  /// 被暂停 / 停止都由插件从状态流推过来。
  Future<void> _listenForInterruptions() async {
    await _stateSub?.cancel();
    _stateSub = _recorder.onStateChanged().listen((state) {
      if (_interruptions.isClosed) return;
      switch (state) {
        case RecordState.pause:
          _interruptions.add('录音被系统中断，已暂停');
        case RecordState.stop:
          _interruptions.add('录音已停止');
        case RecordState.record:
          break;
      }
    });
  }

  @override
  Future<void> stop() => _recorder.stop();

  @override
  Future<void> dispose() async {
    await _stateSub?.cancel();
    _stateSub = null;
    await _interruptions.close();
    // 从没被用过就没什么可释放的——顺手也把那条平台通道挡在测试之外。
    await _created?.dispose();
    _created = null;
  }

  @override
  Stream<String> get interruptions => _interruptions.stream;
}

final pcmInputProvider = Provider<PcmInput>((ref) {
  final input = RecordPcmInput();
  ref.onDispose(() => unawaited(input.dispose()));
  return input;
});

final nightRecorderProvider = Provider<NightRecorder>((ref) {
  final recorder = RecordNightRecorder(
    files: ref.watch(clipFileStoreProvider),
    input: ref.watch(pcmInputProvider),
    audioService: ref.watch(nightAudioServiceProvider),
  );
  ref.onDispose(() => unawaited(recorder.dispose()));
  return recorder;
});
