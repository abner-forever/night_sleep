/// 定长 PCM 字节环形缓冲，用于片段的前置 padding。
///
/// 切片时事件是「事后」才知道的：等到振幅越过阈值，起音已经过去了。所以采集端要
/// 一直把最近一小段 PCM 留在缓冲里，触发时先把这段历史写进片段，片段才不会从中间
/// 开始（规格 §四、§三的「前置 padding」）。
///
/// **按字节记账，不按样本数。** 上游 `record` 吐出的分片边界不保证按样本对齐——
/// 一片可能是奇数个字节。如果按样本数设计容量、再假设每片是整数个样本，遇到奇数字节
/// 就得丢半字节或猜，最终表现为波形里随机的「咔」声。这里只认字节，调用方要拼回
/// 样本时自己按 `sampleRate * channels * 2` 对齐。
library;

import 'dart:typed_data';

/// 固定容量的字节环形缓冲：写满之后继续写，会自动丢掉最老的字节，
/// [read] 永远返回**最近**写入的至多 [capacityBytes] 个字节，且保持写入顺序。
class PcmRing {
  /// 建一个能存 [capacityBytes] 字节的缓冲。容量必须非负；0 表示「什么都不留」。
  PcmRing(this.capacityBytes)
      : assert(capacityBytes >= 0, '容量不能为负'),
        _buffer = Uint8List(capacityBytes);

  /// 按**时长**构造，这是调用方通常想要的写法。
  ///
  /// 容量按下面这条算出来，向上取整：
  ///
  /// ```
  /// capacityBytes = ceil(sampleRate × channels × bytesPerSample × duration / 1s)
  /// ```
  ///
  /// 例如 16000 Hz、单声道、16-bit（每样本 2 字节）、0.5 秒：
  /// `16000 × 1 × 2 × 0.5 = 16000` 字节。向上取整是为了保证**至少**能装下这段
  /// 时长，宁可多一个字节，也不要因为整除截断而差一点点。
  ///
  /// [bytesPerSample] 默认 2，对应 16-bit。
  factory PcmRing.forDuration(
    Duration duration, {
    required int sampleRate,
    required int channels,
    int bytesPerSample = 2,
  }) {
    assert(sampleRate > 0, '采样率必须为正');
    assert(channels > 0, '声道数必须为正');
    assert(bytesPerSample > 0, '每样本字节数必须为正');
    final micros = duration.inMicroseconds;
    final numerator = sampleRate * channels * bytesPerSample * micros;
    final capacity = (numerator + Duration.microsecondsPerSecond - 1) ~/
        Duration.microsecondsPerSecond;
    return PcmRing(capacity);
  }

  /// 容量（字节），构造后不变。
  final int capacityBytes;

  final Uint8List _buffer;
  int _start = 0; // 最老字节的位置
  int _length = 0; // 当前存了多少字节

  /// 当前缓冲里有多少字节。
  int get length => _length;

  /// 当前是否为空。
  bool get isEmpty => _length == 0;

  /// 追加一段字节。超过容量的部分是所写数据的**头部**（最老的），会被丢掉。
  void write(Uint8List pcm) {
    if (pcm.isEmpty || capacityBytes == 0) return;

    if (pcm.length >= capacityBytes) {
      // 这一片本身就装不下：只有它的最后 capacityBytes 字节有意义。
      _buffer.setRange(0, capacityBytes,
          Uint8List.sublistView(pcm, pcm.length - capacityBytes));
      _start = 0;
      _length = capacityBytes;
      return;
    }

    final excess = _length + pcm.length - capacityBytes;
    if (excess > 0) {
      _start = (_start + excess) % capacityBytes;
      _length -= excess;
    }

    final writeAt = (_start + _length) % capacityBytes;
    final tailRoom = capacityBytes - writeAt; // 写到物理末尾还剩多少
    if (pcm.length <= tailRoom) {
      _buffer.setRange(writeAt, writeAt + pcm.length, pcm);
    } else {
      _buffer.setRange(writeAt, capacityBytes, pcm, 0);
      _buffer.setRange(0, pcm.length - tailRoom, pcm, tailRoom);
    }
    _length += pcm.length;
  }

  /// 取出当前缓冲里的全部字节，按写入顺序（最老的在前）。**不清空缓冲**：
  /// 连续 [read] 两次结果一样；要重置用 [clear]。
  Uint8List read() {
    final out = Uint8List(_length);
    if (_length == 0) return out;
    final tailRoom = capacityBytes - _start;
    if (_length <= tailRoom) {
      out.setRange(0, _length, _buffer, _start);
    } else {
      out.setRange(0, tailRoom, _buffer, _start);
      out.setRange(tailRoom, _length, _buffer, 0);
    }
    return out;
  }

  /// 取最近写入字节里 `[start, end)` 这一段，**只复制这一段**。
  ///
  /// 下标与 [read] 返回的那个视图同一口径：0 是最老的那一字节。
  ///
  /// 为什么要单开一个方法：[read] 每次都要把整块容量拼成一段连续内存。一个整夜
  /// 几百个片段的场景下，那就是几百次「分配 2.4MB 再拷贝 2.4MB」，而每个片段真正
  /// 要的往往只有几秒音频（几十 KB）。这里按需只拷那一段。
  ///
  /// 越界的下标会夹到有效范围内，不抛异常——采集端算出来的偏移来自墙上时间，
  /// 环形缓冲一旦滚过它，少写几个字节远好过把一整段音频连事件行一起弄丢。
  Uint8List slice(int start, int end) {
    final from = start.clamp(0, _length);
    final to = end.clamp(from, _length);
    final count = to - from;
    final out = Uint8List(count);
    if (count == 0) return out;

    final physical = (_start + from) % capacityBytes;
    final tailRoom = capacityBytes - physical;
    if (count <= tailRoom) {
      out.setRange(0, count, _buffer, physical);
    } else {
      out.setRange(0, tailRoom, _buffer, physical);
      out.setRange(tailRoom, count, _buffer, 0);
    }
    return out;
  }

  /// 清空缓冲，容量不变。
  void clear() {
    _start = 0;
    _length = 0;
  }
}
