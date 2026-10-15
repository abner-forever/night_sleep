import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/features/sleep/data/pcm_ring.dart';
import 'package:night_sleep/features/sleep/data/wav_file.dart';
import 'package:path/path.dart' as p;

/// WAV 头与流式写入的字节级验收。
///
/// 头的部分**不落盘**：直接对 [pcm16WavHeader] 逐字节断言。`WavWriter` 那部分必须
/// 写真实文件才测得到「回填两处长度」这件事，所以用系统临时目录，跑完删掉。
void main() {
  group('pcm16WavHeader', () {
    test('16000Hz 单声道：44 字节逐字节对齐（含四段标识与小端字段）', () {
      final header =
          pcm16WavHeader(sampleRate: 16000, channels: 1, dataBytes: 1234);

      expect(header.length, 44);
      expect(header, <int>[
        0x52, 0x49, 0x46, 0x46, // 'RIFF'
        0xF6, 0x04, 0x00, 0x00, // 文件总长 − 8 = 36 + 1234 = 1270（小端）
        0x57, 0x41, 0x56, 0x45, // 'WAVE'
        0x66, 0x6D, 0x74, 0x20, // 'fmt '
        0x10, 0x00, 0x00, 0x00, // fmt 子块长度 = 16
        0x01, 0x00, // 格式 = 1（PCM）
        0x01, 0x00, // 声道数 = 1
        0x80, 0x3E, 0x00, 0x00, // 采样率 = 16000
        0x00, 0x7D, 0x00, 0x00, // byteRate = 16000 × 1 × 2 = 32000
        0x02, 0x00, // blockAlign = 1 × 2 = 2
        0x10, 0x00, // 位深 = 16
        0x64, 0x61, 0x74, 0x61, // 'data'
        0xD2, 0x04, 0x00, 0x00, // data 段字节数 = 1234
      ]);
    });

    test('双声道时 byteRate 与 blockAlign 跟着翻倍', () {
      final header =
          pcm16WavHeader(sampleRate: 44100, channels: 2, dataBytes: 0);

      expect(_u32(header, 28), 44100 * 2 * 2, reason: 'byteRate');
      expect(_u16(header, 32), 4, reason: 'blockAlign = 声道数 × 2');
      expect(_u16(header, 22), 2, reason: '声道数');
      expect(_u32(header, 40), 0, reason: '空文件时 data 长为 0');
      expect(_u32(header, 4), 36, reason: '空文件时 RIFF 长 = 44 − 8');
    });

    test('四个标识段固定不变', () {
      final header =
          pcm16WavHeader(sampleRate: 8000, channels: 1, dataBytes: 2);
      expect(_ascii(header, 0, 4), 'RIFF');
      expect(_ascii(header, 8, 4), 'WAVE');
      expect(_ascii(header, 12, 4), 'fmt ');
      expect(_ascii(header, 36, 4), 'data');
    });
  });

  group('WavWriter', () {
    late Directory root;
    late String path;

    setUp(() {
      root = Directory.systemTemp.createTempSync('wav-writer-test');
      path = p.join(root.path, 'clip.wav');
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    test('分多次 append，data 长等于累计字节数，RIFF 长等于文件总长 − 8', () async {
      final writer = WavWriter();
      await writer.open(path);
      await writer.append(Uint8List.fromList([1, 2, 3]));
      await writer.append(Uint8List.fromList([4, 5, 6, 7]));
      await writer.append(Uint8List.fromList(const [])); // 空片不该改变任何东西
      await writer.close();

      final bytes = File(path).readAsBytesSync();
      expect(writer.dataBytes, 7);
      expect(bytes.length, 44 + 7);
      expect(_u32(bytes, 40), 7, reason: 'data 长 = 实际写入的字节数');
      expect(_u32(bytes, 4), bytes.length - 8, reason: 'RIFF 长 = 文件总长 − 8');
      // 头之后就是裸 PCM，没有被改写。
      expect(bytes.sublist(44), <int>[1, 2, 3, 4, 5, 6, 7]);
      // 回填之后头本身也应当等于「按最终 dataBytes 算出来的头」。
      expect(
        bytes.sublist(0, 44),
        pcm16WavHeader(sampleRate: 16000, channels: 1, dataBytes: 7),
      );
    });

    test('close 之前文件已经可读，头里是占位长度 0 而不是垃圾', () async {
      final writer = WavWriter();
      await writer.open(path);
      await writer.append(Uint8List.fromList(List<int>.filled(10, 0xAB)));

      // 故意不 close：模拟中途被杀 / 边写边读。
      final bytes = File(path).readAsBytesSync();
      expect(bytes.length, 44 + 10);
      expect(_u32(bytes, 40), 0, reason: 'data 长是占位值 0');
      expect(_u32(bytes, 4), 36, reason: 'RIFF 长是占位值 36（= 44 − 8）');
      expect(bytes.sublist(44), List<int>.filled(10, 0xAB));

      await writer.close(); // 收尾，避免留下随机文件
    });

    test('没写任何 PCM 也能关闭，得到一个合法的 0 字节 WAV', () async {
      final writer = WavWriter();
      await writer.open(path);
      await writer.close();

      final bytes = File(path).readAsBytesSync();
      expect(bytes.length, 44);
      expect(_u32(bytes, 40), 0);
      expect(_u32(bytes, 4), 36);
    });

    test('open 之前 append / close 都抛 StateError，不静默丢数据', () async {
      final writer = WavWriter();
      await expectLater(
        writer.append(Uint8List.fromList([1])),
        throwsStateError,
      );
      await expectLater(writer.close(), throwsStateError);
    });

    test('close 之后 append 抛 StateError，重复 open 也抛', () async {
      final writer = WavWriter();
      await writer.open(path);
      await writer.close();

      await expectLater(
        writer.append(Uint8List.fromList([1])),
        throwsStateError,
      );
      await writer.open(path); // close 之后允许再 open（新文件截断重建）
      await expectLater(writer.open(path), throwsStateError);
      await writer.close();
    });

    test('构造参数决定头里的采样率与声道数', () async {
      final writer = WavWriter(sampleRate: 48000, channels: 2);
      await writer.open(path);
      await writer.append(Uint8List.fromList([0, 0, 0, 0]));
      await writer.close();

      final bytes = File(path).readAsBytesSync();
      expect(_u32(bytes, 24), 48000);
      expect(_u16(bytes, 22), 2);
      expect(_u32(bytes, 28), 48000 * 2 * 2);
    });
  });

  group('PcmRing', () {
    test('没写满时取出的就是全部，顺序不变', () {
      final ring = PcmRing(8);
      ring.write(Uint8List.fromList([1, 2, 3]));
      expect(ring.length, 3);
      expect(ring.isEmpty, isFalse);
      expect(ring.read(), <int>[1, 2, 3]);

      ring.write(Uint8List.fromList([4, 5]));
      expect(ring.read(), <int>[1, 2, 3, 4, 5]);
    });

    test('写超容量后取出的正好是最后 N 字节，顺序正确', () {
      final ring = PcmRing(5);
      ring.write(Uint8List.fromList([1, 2, 3]));
      ring.write(Uint8List.fromList([4, 5, 6])); // 总 6，只留最后 5
      expect(ring.read(), <int>[2, 3, 4, 5, 6]);

      ring.write(Uint8List.fromList([7, 8]));
      expect(ring.read(), <int>[4, 5, 6, 7, 8]);
      expect(ring.length, 5);
    });

    test('单片就超过容量时，留下的是这一片的尾部', () {
      final ring = PcmRing(4);
      ring.write(Uint8List.fromList(List<int>.generate(10, (i) => i)));
      expect(ring.read(), <int>[6, 7, 8, 9]);
    });

    test('容量为奇数个字节也不出错', () {
      final ring = PcmRing(7);
      ring.write(Uint8List.fromList([1, 2, 3]));
      ring.write(Uint8List.fromList([4, 5, 6]));
      ring.write(Uint8List.fromList([7, 8]));
      // 三次共写 8 字节，留最后 7 个。
      expect(ring.read(), <int>[2, 3, 4, 5, 6, 7, 8]);
    });

    test('任意分片下都与「朴素保留最后 N 字节」一致', () {
      const capacity = 13; // 刻意取奇数
      final ring = PcmRing(capacity);
      final written = <int>[];

      for (var chunk = 1; chunk <= 40; chunk++) {
        final piece = Uint8List.fromList(
            List<int>.generate(chunk, (i) => written.length + i));
        written.addAll(piece);
        ring.write(piece);
      }

      final expected = Uint8List.fromList(
        written.sublist(written.length - capacity),
      );
      expect(ring.read(), expected, reason: '顺序必须与写入一致，不能逆序');
    });

    test('read 不清空；clear 之后才为空', () {
      final ring = PcmRing(4);
      ring.write(Uint8List.fromList([1, 2, 3]));
      expect(ring.read(), <int>[1, 2, 3]);
      expect(ring.read(), <int>[1, 2, 3], reason: '重复读结果相同');

      ring.clear();
      expect(ring.isEmpty, isTrue);
      expect(ring.read(), isEmpty);
    });

    test('空写入与零容量都是明确的无操作', () {
      final ring = PcmRing(4);
      ring.write(Uint8List(0));
      expect(ring.isEmpty, isTrue);

      final none = PcmRing(0);
      none.write(Uint8List.fromList([1, 2, 3]));
      expect(none.isEmpty, isTrue);
      expect(none.read(), isEmpty);
    });

    test('forDuration 按采样参数算出容量并向上取整', () {
      // 16000 Hz 单声道 16-bit、0.5 秒 = 16000 字节。
      expect(
        PcmRing.forDuration(
          const Duration(milliseconds: 500),
          sampleRate: 16000,
          channels: 1,
        ).capacityBytes,
        16000,
      );

      // 除不尽时向上取整，宁可多一个字节也不差一点点。
      expect(
        PcmRing.forDuration(
          const Duration(microseconds: 1),
          sampleRate: 1,
          channels: 1,
          bytesPerSample: 1,
        ).capacityBytes,
        1,
      );
    });

    test('forDuration 建的缓冲能装下正好那段时长', () {
      final ring = PcmRing.forDuration(
        const Duration(milliseconds: 100),
        sampleRate: 16000,
        channels: 1,
      );
      // 100ms 的 PCM 是 3200 字节，正好装满，不应被截掉。
      final pcm = Uint8List.fromList(
        List<int>.generate(3200, (i) => i % 256),
      );
      ring.write(pcm);
      expect(ring.length, 3200);
      expect(ring.read(), pcm);
    });
  });

  /// [PcmRing.slice] 是采集端真正用的那一个：每个片段只切自己那一小段，
  /// 不把整块容量读出来再丢掉大半。它的结果必须与「读全部再取子区间」完全一致。
  group('PcmRing.slice', () {
    test('未写满时与「先 read 再取子区间」逐字节一致', () {
      final ring = PcmRing(16);
      ring.write(Uint8List.fromList(List.generate(10, (i) => i)));

      expect(ring.slice(2, 6), Uint8List.fromList([2, 3, 4, 5]));
      expect(ring.slice(0, 10), ring.read());
    });

    test('写满并回绕之后仍然一致——这是切片真正会遇到的形态', () {
      final ring = PcmRing(16);
      ring.write(Uint8List.fromList(List.generate(16, (i) => i)));
      // 再写 7 个，最老的 7 个被挤掉，内部指针已经绕过物理末尾。
      ring.write(Uint8List.fromList(List.generate(7, (i) => 100 + i)));

      final all = ring.read();
      for (var from = 0; from <= ring.length; from += 3) {
        for (var to = from; to <= ring.length; to += 5) {
          expect(
            ring.slice(from, to),
            Uint8List.sublistView(all, from, to),
            reason: 'slice($from, $to) 与整段读出来的子区间不一致',
          );
        }
      }
    });

    test('越界的下标被夹住，不抛异常', () {
      final ring = PcmRing(8);
      ring.write(Uint8List.fromList([1, 2, 3, 4]));

      expect(ring.slice(-5, 100), Uint8List.fromList([1, 2, 3, 4]));
      // 起点越界时夹到末尾，得到的是空而不是反向的一段。
      expect(ring.slice(50, 100), isEmpty);
      expect(ring.slice(3, 1), isEmpty);
    });

    test('空缓冲上是空，不是崩', () {
      final ring = PcmRing(8);
      expect(ring.slice(0, 4), isEmpty);
    });
  });

  group('parsePcm16Wav', () {
    /// 按采集端的格式（16 kHz 单声道 PCM16）拼一个完整 WAV。
    Uint8List wavOf(List<int> samples, {int rate = 16000}) {
      final data = Uint8List(samples.length * 2);
      final view = ByteData.view(data.buffer);
      for (var i = 0; i < samples.length; i++) {
        view.setInt16(i * 2, samples[i], Endian.little);
      }
      return Uint8List.fromList([
        ...pcm16WavHeader(
          sampleRate: rate,
          channels: 1,
          dataBytes: data.length,
        ),
        ...data,
      ]);
    }

    test('写出去再读回来，采样一个不差、采样率来自文件头', () {
      // 变异：把 `parsePcm16Wav` 里的偏移 44 改成 43，本用例变红。
      final audio = parsePcm16Wav(wavOf([0, 1000, -1000, 32767, -32768]))!;
      expect(audio.sampleRate, 16000);
      expect(audio.samples, hasLength(5));
      expect(audio.samples[1], closeTo(1000 / 32768, 1e-9));
      expect(audio.samples[3], closeTo(32767 / 32768, 1e-9));
      expect(audio.samples[4], closeTo(-1.0, 1e-9));
    });

    test('采样率是读出来的，不是写死的 16000', () {
      final audio = parsePcm16Wav(wavOf([0, 0], rate: 48000))!;
      expect(audio.sampleRate, 48000, reason: '写死 16000 的话，换个采样率就会把频率全部算错一倍');
    });

    test('时长由采样数与采样率算出来', () {
      final audio = parsePcm16Wav(wavOf(List.filled(16000, 0)))!;
      expect(audio.duration, const Duration(seconds: 1));
    });

    test('不是 WAV 的字节返回 null，不抛', () {
      // 变异：把 `_hasAscii(view, 0, 'RIFF')` 那道判断删掉，本用例变红。
      expect(parsePcm16Wav(Uint8List.fromList(List.filled(200, 7))), isNull);
    });

    test('太短的输入返回 null', () {
      expect(parsePcm16Wav(Uint8List(10)), isNull);
    });

    test('头声明比实际长时按实际算——写到一半被杀的文件不该读出垃圾', () {
      final full = wavOf(List.filled(100, 5));
      final truncated = Uint8List.sublistView(full, 0, 44 + 40);
      final audio = parsePcm16Wav(truncated)!;
      expect(audio.samples, hasLength(20));
    });

    test('占位长度 0 的文件读成空，不读成垃圾', () {
      // `WavWriter.open` 先写 `dataBytes: 0` 占位。中途被杀留下的就是这种文件，
      // 它按设计是一个**合法的空 WAV**。
      final audio = parsePcm16Wav(wavOf(const []))!;
      expect(audio.isEmpty, isTrue);
    });
  });
}

/// 从 [bytes] 的 [offset] 读一个小端 uint32（测试用，故意不共用实现）。
int _u32(Uint8List bytes, int offset) =>
    bytes[offset] |
    (bytes[offset + 1] << 8) |
    (bytes[offset + 2] << 16) |
    (bytes[offset + 3] << 24);

/// 从 [bytes] 的 [offset] 读一个小端 uint16。
int _u16(Uint8List bytes, int offset) =>
    bytes[offset] | (bytes[offset + 1] << 8);

/// 从 [bytes] 的 [offset] 起读 [length] 个 ASCII 字符。
String _ascii(Uint8List bytes, int offset, int length) =>
    String.fromCharCodes(bytes.sublist(offset, offset + length));
