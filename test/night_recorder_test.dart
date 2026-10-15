import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/core/platform/night_audio_service.dart';
import 'package:night_sleep/features/sleep/data/clip_store.dart';
import 'package:night_sleep/features/sleep/data/night_recorder.dart';
import 'package:night_sleep/features/sleep/domain/clip_journal.dart';
import 'package:path/path.dart' as p;

/// 造一段恒定振幅的 PCM16 单声道。`amplitude` 直接决定 dBFS：
/// 8000 ≈ −12 dBFS（远高于触发阈值 −38），1 ≈ −90 dBFS（远低于结束阈值 −45）。
Uint8List _pcm({required int milliseconds, required int amplitude}) {
  final samples = kRecordSampleRate * milliseconds ~/ 1000;
  final bytes = Uint8List(samples * 2);
  final view = ByteData.view(bytes.buffer);
  for (var i = 0; i < samples; i++) {
    view.setInt16(i * 2, amplitude, Endian.little);
  }
  return bytes;
}

/// 假采集端：测试自己往里推 PCM，不碰任何平台通道。
class _FakePcmInput implements PcmInput {
  _FakePcmInput({List<String>? log}) : log = log ?? [];

  /// 与假前台服务共用一条流水，用来断言**谁先谁后**。
  final List<String> log;

  final _pcm = StreamController<Uint8List>.broadcast();
  final _interruptions = StreamController<String>.broadcast();

  bool permission = true;
  bool started = false;
  int stopCount = 0;

  /// 设成非 null 就让 [startStream] 抛这个错，用来测「起不来」那条路。
  Object? startError;

  void push(Uint8List chunk) => _pcm.add(chunk);
  void interrupt(String reason) => _interruptions.add(reason);

  @override
  Future<bool> ensurePermission() async => permission;

  @override
  Future<Stream<Uint8List>> startStream() async {
    log.add('pcm.startStream');
    if (startError case final error?) throw error;
    started = true;
    return _pcm.stream;
  }

  @override
  Future<void> stop() async {
    log.add('pcm.stop');
    stopCount++;
  }

  @override
  Future<void> dispose() async {
    await _pcm.close();
    await _interruptions.close();
  }

  @override
  Stream<String> get interruptions => _interruptions.stream;
}

/// 假前台服务：**只记流水、只回一个预先设定的结果**，一次平台通道都不碰。
class _FakeNightAudioService implements NightAudioService {
  _FakeNightAudioService({List<String>? log}) : log = log ?? [];

  final List<String> log;

  /// 下一次 [start] 要回的结果码。默认 `started`——Android 上正常的那一条。
  NightAudioServiceResult result = NightAudioServiceResult.started;

  int startCount = 0;
  int stopCount = 0;

  @override
  Future<NightAudioServiceResult> start() async {
    log.add('service.start');
    startCount++;
    return result;
  }

  @override
  Future<void> stop() async {
    log.add('service.stop');
    stopCount++;
  }
}

void main() {
  late Directory tempDir;
  late _FakePcmInput input;
  late _FakeNightAudioService service;
  late List<String> log;
  late ClipFileStore files;
  late RecordNightRecorder recorder;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('night_recorder');
    // 采集端与前台服务共用一条流水，断言「谁先谁后」时读的只有这一条。
    log = <String>[];
    input = _FakePcmInput(log: log);
    service = _FakeNightAudioService(log: log);
    files = ClipFileStore(baseDirectory: () async => tempDir);
    recorder = RecordNightRecorder(
      files: files,
      input: input,
      audioService: service,
      // 固定时钟：片段的墙上时刻要能对得上，不然断言只能写成「约等于现在」。
      clock: () => DateTime.utc(2026, 10, 3, 23),
    );
  });

  tearDown(() async {
    await recorder.dispose();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  /// 让事件循环跑一拍。
  ///
  /// PCM 走的是**异步**广播流：`push()` 只是把字节投出去，采集端要等到下一次
  /// 微任务才处理它们。紧接着调 `stop()` 的话，`_flush()` 看到的是一个空窗口，
  /// 于是一条片段都不会产生——那不是被测代码的毛病，是测试自己抢跑了。
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 20));

  /// 等一条片段，超时就抛——比 `expectLater(stream, emits(...))` 好读，
  /// 而且能拿到那条片段本身去做断言。
  ///
  /// **必须在片段发出之前订阅**：`closedClips` 是广播流，错过就是错过。
  Future<ClipDraft> nextClip({Duration timeout = const Duration(seconds: 5)}) {
    return recorder.closedClips.first.timeout(timeout);
  }

  List<File> clipFiles() {
    final dir = Directory(p.join(tempDir.path, 'clips'));
    if (!dir.existsSync()) return const [];
    return dir.listSync().whereType<File>().toList();
  }

  group('采集与切片', () {
    test('一段持续的有声输入收尾时落成一条片段，文件是合法 WAV', () async {
      await recorder.start();
      input.push(_pcm(milliseconds: 3000, amplitude: 8000));
      await settle();

      // 一直有声，切片定不了案（要等静音），所以由 stop() 收尾。
      final pending = nextClip();
      await recorder.stop();
      final clip = await pending;

      expect(clip.durationMs, greaterThan(2500));
      expect(clip.durationMs, lessThanOrEqualTo(3500));
      expect(clip.localUri, isNotNull);
      // 片段起始时刻 = 会话开始 + 采样偏移（这一段从 0 起，所以就是那一刻）。
      expect(clip.startedAtUtc, DateTime.utc(2026, 10, 3, 23));

      final bytes = File(clip.localUri!).readAsBytesSync();
      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
      expect(bytes.length, greaterThan(44), reason: '只有头没有音频');
      // WAV 头里的 data 长度必须和实际音频对得上，否则播放器读出来的时长是错的。
      final dataBytes =
          ByteData.view(bytes.buffer).getUint32(40, Endian.little);
      expect(dataBytes, bytes.length - 44);
    });

    test('静音持续足够久时片段在流中就被定案，不必等到结束', () async {
      await recorder.start();
      final pending = nextClip();
      input.push(_pcm(milliseconds: 3000, amplitude: 8000));
      // 静音 4 秒 > 静音时长 2 秒 + 合并间隔 1.5 秒，这一段落该定案了。
      input.push(_pcm(milliseconds: 4000, amplitude: 1));

      final clip = await pending;
      expect(clip.durationMs, greaterThan(2500));
      // 这里**没有**调 stop()——它是在流里跑出来的。
      expect(recorder.status.value.isRecording, isTrue);
    });

    test('整夜安静：一条片段都不产生，也一个文件都不建', () async {
      await recorder.start();
      var emitted = 0;
      final sub = recorder.closedClips.listen((_) => emitted++);
      input.push(_pcm(milliseconds: 10000, amplitude: 1));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await recorder.stop();
      await sub.cancel();

      expect(emitted, 0);
      expect(clipFiles(), isEmpty, reason: '没有事件就不该有文件');
    });

    test('stop() 返回时最后一段已经送达订阅方', () async {
      await recorder.start();
      final received = <ClipDraft>[];
      recorder.closedClips.listen(received.add);
      input.push(_pcm(milliseconds: 3000, amplitude: 8000));
      await settle();

      await recorder.stop();

      // **不许再加任何等待**：`finish()` 就排在 `stopForSessionEnd()` 的下一行，
      // 它在同一个事务里读会话行的片段清单。这里少一条，那一晚就少一条——
      // 而一次会话只有一段时，少的那条就是全部。
      //
      // 变异验证：把 `_flush()` 末尾的 `await _drainWrites()` 去掉，这条立刻变红。
      expect(received, hasLength(1));
    });

    test('包络是实测的，长度等于波形轨道的柱数', () async {
      await recorder.start();
      input.push(_pcm(milliseconds: 3000, amplitude: 8000));
      await settle();
      final pending = nextClip();
      await recorder.stop();
      final clip = await pending;

      expect(clip.envelope, isNotNull);
      expect(clip.envelope, hasLength(38));
    });
  });

  group('失败与中断', () {
    test('起不来时不进入录音态，并带上原因', () async {
      input.startError = StateError('麦克风被占用');

      await expectLater(recorder.start(), throwsA(isA<StateError>()));

      expect(recorder.status.value.isRecording, isFalse);
      expect(recorder.status.value.state, NightRecordingState.stopped);
      expect(recorder.status.value.reason, contains('麦克风被占用'));
    });

    test('被抢占时停止并说明原因，已经录到的片段不丢', () async {
      await recorder.start();
      final pending = nextClip();
      input.push(_pcm(milliseconds: 3000, amplitude: 8000));
      input.interrupt('录音被系统中断，已暂停');

      final clip = await pending;
      expect(clip.localUri, isNotNull, reason: '中断不该把已录到的片段连累掉');

      // 状态流转是异步的，给它一拍。
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(recorder.status.value.state, NightRecordingState.stopped);
      expect(recorder.status.value.reason, contains('中断'));
    });

    test('停止之后不再接收新的 PCM', () async {
      await recorder.start();
      input.push(_pcm(milliseconds: 3000, amplitude: 8000));
      await recorder.stop();

      var emitted = 0;
      final sub = recorder.closedClips.listen((_) => emitted++);
      input.push(_pcm(milliseconds: 3000, amplitude: 8000));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();

      expect(emitted, 0);
    });
  });

  /// 平台静音：应用离开前台之后，Android 会静音录音端口并**持续交付零样本**，
  /// 而 `record` 插件不报任何中断。没有这段逻辑的话，界面会整夜写着「录音中」。
  /// 真机实测与判据见 `docs/verification-log.md` v3.19。
  group('平台静音', () {
    /// 一整段逐样本全零的 PCM——平台静音时交上来的就是这种东西。
    ///
    /// **不能拿 `amplitude: 1` 冒充**：那是一个真实的 1 LSB 底噪（约 −90 dBFS），
    /// 安静，但不是全零，两者必须分得开。
    Uint8List digitalSilence(int milliseconds) =>
        _pcm(milliseconds: milliseconds, amplitude: 0);

    test('全零攒够 kSilentMicRun 之前不翻状态，越过之后转成 silenced', () async {
      await recorder.start();
      expect(recorder.status.value.state, NightRecordingState.recording);

      input.push(digitalSilence(kSilentMicRun.inMilliseconds - 100));
      await settle();
      expect(recorder.status.value.state, NightRecordingState.recording,
          reason: '差一格就是还没到，提前翻状态等于冤枉一个好麦克风');

      input.push(digitalSilence(200));
      await settle();
      expect(recorder.status.value.state, NightRecordingState.silenced);
      expect(recorder.status.value.reason, isNotNull);
      // **不是"停了"**：流还活着，采样还在来，只是每个都是 0。
      expect(recorder.status.value.isRecording, isFalse);
    });

    test('声音一回来就回到 recording', () async {
      await recorder.start();
      input.push(digitalSilence(kSilentMicRun.inMilliseconds + 1000));
      await settle();
      expect(recorder.status.value.state, NightRecordingState.silenced);

      input.push(_pcm(milliseconds: 500, amplitude: 8000));
      await settle();
      expect(recorder.status.value.state, NightRecordingState.recording);
      expect(recorder.status.value.reason, isNull);
    });

    test('安静但有底噪不算平台静音——判据是逐样本全零，不是"很安静"', () async {
      await recorder.start();
      // 1 LSB 的底噪：约 −90 dBFS，比任何切片阈值都低，但它不是 0。
      input.push(_pcm(
          milliseconds: kSilentMicRun.inMilliseconds + 5000, amplitude: 1));
      await settle();
      expect(recorder.status.value.state, NightRecordingState.recording);
    });

    test('全零必须连续：中间夹一格真声音就重新起算', () async {
      await recorder.start();
      final half = kSilentMicRun.inMilliseconds ~/ 2;
      input.push(digitalSilence(half));
      input.push(_pcm(milliseconds: 100, amplitude: 1));
      input.push(digitalSilence(half));
      await settle();
      expect(recorder.status.value.state, NightRecordingState.recording,
          reason: '两段各半、中间被打断，加起来够阈值也不算数');
    });

    test('主动停录之后不再停留在 silenced', () async {
      await recorder.start();
      input.push(digitalSilence(kSilentMicRun.inMilliseconds + 1000));
      await settle();
      expect(recorder.status.value.state, NightRecordingState.silenced);

      await recorder.stop();
      expect(recorder.status.value.state, NightRecordingState.idle,
          reason: '会话都结束了还说"麦克风被静音"，是在说一件已经不成立的事');
    });
  });

  /// 前台服务（Android 上「退到后台 / 锁屏后还能不能录」的唯一凭据）。
  ///
  /// **接线顺序是硬约束**，两个方向都有各自的失败形态：起的时候反了会漏一段真实的
  /// 空窗（收到的是数字静音、不报错），停的时候反了会把完好的尾巴抹黑成 `silenced`。
  /// 这里的用例就是钉住这两条顺序，以及三个结果码各自的处置。
  group('前台服务', () {
    test('start() 里服务先于开流', () async {
      await recorder.start();

      expect(log, ['service.start', 'pcm.startStream'],
          reason: '反了的话，麦克风已经在采而这半秒里没人保着它——收上来的是一格全零');
      expect(service.startCount, 1);
    });

    test('stop() 里先停流、后撤服务', () async {
      await recorder.start();
      log.clear();

      await recorder.stop();

      expect(log, ['pcm.stop', 'service.stop'],
          reason: '反了的话，撤服务到真的停流之间那半秒会被记成一格全零');
    });

    test('notForeground：不开流，状态是 stopped 并带上那句说明', () async {
      service.result = NightAudioServiceResult.notForeground;

      await expectLater(recorder.start(), throwsA(isA<StateError>()));

      expect(input.started, isFalse, reason: '不去开一个注定收到静音的麦克风');
      expect(log, ['service.start'], reason: '连流都没碰过');
      expect(recorder.status.value.state, NightRecordingState.stopped);
      expect(recorder.status.value.reason, kNotForegroundReason);
      expect(recorder.status.value.isRecording, isFalse);
    });

    test('missingPermission：同样不开流，但说的是另一句', () async {
      service.result = NightAudioServiceResult.missingPermission;

      await expectLater(recorder.start(), throwsA(isA<StateError>()));

      expect(input.started, isFalse);
      expect(recorder.status.value.state, NightRecordingState.stopped);
      expect(recorder.status.value.reason, kMissingForegroundPermissionReason);
      // 两句必须分得开：一句是「此刻不行，回到前台再说」，另一句是「这个包不行，
      // 去更新」。合成一句，用户就分不清该等还是该升级。
      expect(kMissingForegroundPermissionReason, isNot(kNotForegroundReason));
    });

    test('unsupported / failed：照旧开流', () async {
      // iOS 根本没有这条通道；平台侧偶发失败时应用也还在前台。两种都不许把录音拦下来。
      for (final result in const [
        NightAudioServiceResult.unsupported,
        NightAudioServiceResult.failed,
      ]) {
        service.result = result;
        await recorder.start();

        expect(input.started, isTrue, reason: '$result 不该拦住开流');
        expect(recorder.status.value.state, NightRecordingState.recording);

        await recorder.stop();
      }
    });

    test('服务起来了、流却没起来时，把服务撤掉再抛', () async {
      input.startError = StateError('麦克风被占用');

      await expectLater(recorder.start(), throwsA(isA<StateError>()));

      expect(log, ['service.start', 'pcm.startStream', 'service.stop'],
          reason: '留着服务就是通知栏上一条「正在录制」，而一个采样都没采');
      expect(recorder.status.value.state, NightRecordingState.stopped);
      expect(recorder.status.value.reason, contains('麦克风被占用'));
    });

    test('服务没起来时什么也不用撤', () async {
      service.result = NightAudioServiceResult.notForeground;

      await expectLater(recorder.start(), throwsA(isA<StateError>()));

      expect(service.stopCount, 0);
    });
  });
}
