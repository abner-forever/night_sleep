import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
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
    if (startError case final error?) throw error;
    started = true;
    return _pcm.stream;
  }

  @override
  Future<void> stop() async {
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

void main() {
  late Directory tempDir;
  late _FakePcmInput input;
  late ClipFileStore files;
  late RecordNightRecorder recorder;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('night_recorder');
    input = _FakePcmInput();
    files = ClipFileStore(baseDirectory: () async => tempDir);
    recorder = RecordNightRecorder(
      files: files,
      input: input,
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
}
