/// 把裸 PCM16 流写成标准 WAV 文件。
///
/// 采集端拿到的字节有一个必须记住的事实：`record` 7.1.1 在 iOS / macOS 上的
/// **流式**输出是**裸小端 PCM16，没有容器头**（`record_ios` 的 `Pcm16BitsEncoder`
/// 逐帧拼字节，不写 WAV 头）。所以 WAV 头必须由我们自己写：固定 44 字节，
/// 见 [pcm16WavHeader]。
///
/// 采集格式固定为 **16000 Hz、单声道、16-bit**（规格 §二），这些值由 [WavWriter]
/// 的构造参数传入，不在本文件里写死，便于单测覆盖其他组合。
library;

import 'dart:io';
import 'dart:typed_data';

/// WAV 头的固定字节数（标准 PCM 头：4+4+4 + 4+4+2+2+4+4+2+2 + 4+4）。
const int kWavHeaderBytes = 44;

/// 构造一个 44 字节的标准 WAV（PCM）头。
///
/// 字段与偏移（全部小端）：
///
/// | 偏移 | 内容 |
/// | --- | --- |
/// | 0  | `RIFF` |
/// | 4  | 文件总长 − 8（uint32） |
/// | 8  | `WAVE` |
/// | 12 | `fmt ` |
/// | 16 | 子块长度 16（uint32） |
/// | 20 | 音频格式 1 = PCM（uint16） |
/// | 22 | 声道数（uint16） |
/// | 24 | 采样率（uint32） |
/// | 28 | byteRate = 采样率 × 声道数 × 2（uint32） |
/// | 32 | blockAlign = 声道数 × 2（uint16） |
/// | 34 | 位深 16（uint16） |
/// | 36 | `data` |
/// | 40 | data 段字节数（uint32） |
///
/// 采样位深固定 16-bit，因为本文件的用途就是 PCM16；需要别的位深时另开函数，
/// 不要在这里加参数然后让调用方猜。
Uint8List pcm16WavHeader({
  required int sampleRate,
  required int channels,
  required int dataBytes,
}) {
  assert(sampleRate > 0, '采样率必须为正');
  assert(channels > 0, '声道数必须为正');
  assert(dataBytes >= 0, 'data 字节数不能为负');

  final bytes = Uint8List(kWavHeaderBytes);
  final view = ByteData.view(bytes.buffer);

  _writeAscii(view, 0, 'RIFF');
  // 文件总长 = 44 字节头 + data 段；再减去「RIFF」与长度字段这 8 个字节。
  view.setUint32(4, kWavHeaderBytes - 8 + dataBytes, Endian.little);
  _writeAscii(view, 8, 'WAVE');

  _writeAscii(view, 12, 'fmt ');
  view.setUint32(16, 16, Endian.little); // fmt 子块长度
  view.setUint16(20, 1, Endian.little); // 1 = PCM
  view.setUint16(22, channels, Endian.little);
  view.setUint32(24, sampleRate, Endian.little);
  view.setUint32(28, sampleRate * channels * 2, Endian.little); // byteRate
  view.setUint16(32, channels * 2, Endian.little); // blockAlign
  view.setUint16(34, 16, Endian.little); // 位深

  _writeAscii(view, 36, 'data');
  view.setUint32(40, dataBytes, Endian.little);

  return bytes;
}

/// 往 [view] 的 [offset] 处写入 ASCII 字符串的字节。
void _writeAscii(ByteData view, int offset, String value) {
  for (var i = 0; i < value.length; i++) {
    view.setUint8(offset + i, value.codeUnitAt(i));
  }
}

/// 把 [value] 编成小端 uint32 的 4 字节。
Uint8List _uint32Le(int value) {
  final bytes = Uint8List(4);
  ByteData.view(bytes.buffer).setUint32(0, value, Endian.little);
  return bytes;
}

/// 流式写一个 WAV 文件：先写占位头，边收 PCM 边追加，关闭时回填长度。
///
/// 用法固定为 [open] → 若干次 [append] → [close]。同一时刻一个实例只能写一个文件；
/// [close] 之后可以再次 [open] 复用（新文件会截断重建）。长度在 [open] 时不可能知道，
/// 所以头里的两处长度（偏移 4 与 40）先写占位值 0；[close] 时用
/// [RandomAccessFile.setPosition] 回填。
///
/// 占位值取 0 而不是「未写」是为了让**中途被杀留下的文件仍然是一个合法的空 WAV**：
/// 解码器会把它读成 0 字节音频，而不是一个损坏的文件。
class WavWriter {
  /// 采样率与声道数是文件头的一部分，必须在 [open] 前定下。
  /// 默认值就是规格 §二 的采集格式（16000 Hz 单声道）。
  WavWriter({this.sampleRate = 16000, this.channels = 1}) {
    assert(sampleRate > 0, '采样率必须为正');
    assert(channels > 0, '声道数必须为正');
  }

  /// 采样率（Hz），写进 WAV 头。
  final int sampleRate;

  /// 声道数，写进 WAV 头。
  final int channels;

  RandomAccessFile? _file;
  int _dataBytes = 0;

  /// 当前累计写入的 PCM 字节数（不含 44 字节头）。调用方用它算片段时长。
  int get dataBytes => _dataBytes;

  /// 打开 [path] 准备写入，并先落一个占位头。
  ///
  /// 文件会被截断重建；父目录必须已存在。
  Future<void> open(String path) async {
    if (_file != null) {
      throw StateError('WavWriter 已经打开，不能重复 open；请先 close()');
    }
    final file = await File(path).open(mode: FileMode.write);
    _file = file;
    _dataBytes = 0;
    // dataBytes 未知，先写 0 占位。
    await file.writeFrom(pcm16WavHeader(
      sampleRate: sampleRate,
      channels: channels,
      dataBytes: 0,
    ));
  }

  /// 追加一段裸 PCM16 小端字节。
  ///
  /// 在 [open] 之前（或 [close] 之后）调用会抛 [StateError]——这里宁可炸掉，
  /// 也不静默把这批音频丢掉：丢一段 PCM 意味着片段中间凭空少一截，用户听不出来是
  /// 哪个环节的错。
  Future<void> append(Uint8List pcm) async {
    final file = _file;
    if (file == null) {
      throw StateError('WavWriter 尚未 open（或已 close），不能 append');
    }
    if (pcm.isEmpty) return;
    await file.writeFrom(pcm);
    _dataBytes += pcm.length;
  }

  /// 回填两处长度并关闭文件。
  ///
  /// 未打开（或已关闭）时调用会抛 [StateError]。
  Future<void> close() async {
    final file = _file;
    if (file == null) {
      throw StateError('WavWriter 尚未 open（或已 close），不能 close');
    }
    try {
      // 两处长度：偏移 4 的 RIFF 文件长、偏移 40 的 data 段长。
      await file.setPosition(4);
      await file.writeFrom(_uint32Le(kWavHeaderBytes - 8 + _dataBytes));
      await file.setPosition(40);
      await file.writeFrom(_uint32Le(_dataBytes));
      await file.flush();
    } finally {
      await file.close();
      _file = null;
    }
  }
}

/// 一段解出来的 PCM16 音频。
class Pcm16Audio {
  const Pcm16Audio({required this.samples, required this.sampleRate});

  /// 归一化到 `[−1, 1]` 的采样点。
  final Float64List samples;

  /// 采样率（Hz），来自文件头——**不是**假定 16000，否则将来换采样率会静默算错频率。
  final int sampleRate;

  bool get isEmpty => samples.isEmpty;

  Duration get duration =>
      Duration(microseconds: samples.length * 1000000 ~/ sampleRate);
}

/// 解一个 PCM16 的 WAV——也就是 [WavWriter] / [pcm16WavHeader] 写出来的那种。
///
/// **读不出来的返回 `null`，不抛异常。** 调用方（片段分析）面对的是一个可能被中途
/// 杀掉、被裁剪、或者干脆不是 WAV 的文件目录，一段坏文件不该让整晚的分析全军覆没。
/// 这与 `sleep_repository.dart` 里 `_decodeEnvelope` 的口径一致：**宁可如实说读不到，
/// 也不要猜一个形状**。
///
/// 只接受 [pcm16WavHeader] 写出的那种头（PCM、16-bit）。别的位深不在这里兼容：
/// 本应用**只**产出这一种格式，为读得懂别人家的文件而写的分支没有被任何真实数据
/// 走过，正是本仓最不想要的那种代码。
Pcm16Audio? parsePcm16Wav(Uint8List bytes) {
  if (bytes.length < kWavHeaderBytes) return null;

  final view = ByteData.view(bytes.buffer, bytes.offsetInBytes);
  if (!_hasAscii(view, 0, 'RIFF') || !_hasAscii(view, 8, 'WAVE')) return null;
  if (!_hasAscii(view, 12, 'fmt ') || !_hasAscii(view, 36, 'data')) return null;

  final audioFormat = view.getUint16(20, Endian.little);
  final channels = view.getUint16(22, Endian.little);
  final sampleRate = view.getUint32(24, Endian.little);
  final bitsPerSample = view.getUint16(34, Endian.little);
  if (audioFormat != 1 || bitsPerSample != 16) return null;
  if (channels < 1 || sampleRate < 1) return null;

  // 头里声明的长度**可能大于**文件实际长度（写到一半被杀），也可能故意是 0 占位
  // （见 `WavWriter.open`）。两头都夹一次，取真正存在的那些字节。
  final declared = view.getUint32(40, Endian.little);
  final available = bytes.length - kWavHeaderBytes;
  final dataBytes = declared < available ? declared : available;
  if (dataBytes <= 0) {
    return Pcm16Audio(samples: Float64List(0), sampleRate: sampleRate);
  }

  final frameCount = dataBytes ~/ (2 * channels);
  final samples = Float64List(frameCount);
  var offset = kWavHeaderBytes;
  for (var i = 0; i < frameCount; i++) {
    // 多声道只取第一声道：采集端固定单声道，这里不为一条从没走过的路径编混音。
    samples[i] = view.getInt16(offset, Endian.little) / 32768.0;
    offset += 2 * channels;
  }
  return Pcm16Audio(samples: samples, sampleRate: sampleRate);
}

/// 读并解一个 WAV 文件。文件不存在 / 读不动 / 不是 WAV 一律返回 `null`。
Future<Pcm16Audio?> readWavFile(String path) async {
  try {
    final bytes = await File(path).readAsBytes();
    return parsePcm16Wav(bytes);
  } on FileSystemException {
    return null;
  }
}

/// [view] 从 [offset] 起是否正好是 ASCII [value]。
bool _hasAscii(ByteData view, int offset, String value) {
  if (view.lengthInBytes < offset + value.length) return false;
  for (var i = 0; i < value.length; i++) {
    if (view.getUint8(offset + i) != value.codeUnitAt(i)) return false;
  }
  return true;
}
