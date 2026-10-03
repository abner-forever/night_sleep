import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/features/sleep/domain/clip_segmentation.dart';

const Duration _step = Duration(milliseconds: 100);

/// 从 [from] 到 [to]（不含）每隔 100ms 产生一格恒定 [dbfs] 的采样。
List<AmplitudeSample> _hold(Duration from, Duration to, double dbfs) {
  final out = <AmplitudeSample>[];
  for (var t = from; t < to; t += _step) {
    out.add(AmplitudeSample(offset: t, dbfs: dbfs));
  }
  return out;
}

void main() {
  // ---------------------------------------------------------------------------
  // 七个参数，每个至少一条：括号里写「把哪个参数改成什么会让它变红」。
  // ---------------------------------------------------------------------------

  test('触发阈值：持续低于 −38 dBFS 的底噪不产生片段', () {
    // 变异：把触发阈值改成 −50 dBFS，−40 的底噪会被触发成片段，本用例变红。
    final quiet = _hold(Duration.zero, const Duration(seconds: 3), -40);
    expect(segmentClips(quiet, const ClipParams()), isEmpty);

    // 正对照：−36 高于 −38，确实会开一段。
    final loud = _hold(Duration.zero, const Duration(seconds: 3), -36);
    expect(segmentClips(loud, const ClipParams()), hasLength(1));
  });

  test('结束阈值滞回：介于两个阈值之间的电平不会结束片段', () {
    // 变异：把结束阈值改成 −38 dBFS（与触发阈值相同、去掉滞回），
    // −42 的平台会被当成静音把片段切成两段，本用例变红。
    final samples = [
      ..._hold(Duration.zero, const Duration(milliseconds: 1500), -20),
      ..._hold(const Duration(milliseconds: 1500),
          const Duration(milliseconds: 4500), -42),
      ..._hold(
          const Duration(milliseconds: 4500), const Duration(seconds: 6), -20),
    ];
    final clips = segmentClips(samples, const ClipParams());
    expect(clips, hasLength(1));
    expect(clips.single.start, Duration.zero);
    expect(clips.single.end, const Duration(seconds: 6));
  });

  test('静音时长：短于阈值的安静间隔不断开片段', () {
    // 变异：把静音时长改成 1.0s，1.5s 的安静会结束上一段，段数变 2，本用例变红。
    const params = ClipParams(
      silenceDuration: Duration(seconds: 2),
      mergeGap: Duration.zero,
      prePadding: Duration.zero,
    );
    final samples = [
      ..._hold(Duration.zero, const Duration(seconds: 1), -20),
      ..._hold(
          const Duration(seconds: 1), const Duration(milliseconds: 2500), -60),
      ..._hold(const Duration(milliseconds: 2500),
          const Duration(milliseconds: 3500), -20),
    ];
    final clips = segmentClips(samples, params);
    expect(clips, hasLength(1));
    expect(clips.single.end, const Duration(milliseconds: 3500));
  });

  test('前置 padding：片段起点往前多留 0.5 秒，且不早于 0', () {
    // 变异：把前置 padding 改成 0 或 1.0s，起点断言变红。
    const params = ClipParams(
      prePadding: Duration(milliseconds: 500),
      silenceDuration: Duration(seconds: 2),
      mergeGap: Duration.zero,
      minDuration: Duration.zero,
    );
    final padded = segmentClips([
      ..._hold(Duration.zero, const Duration(seconds: 2), -60),
      ..._hold(const Duration(seconds: 2), const Duration(seconds: 4), -20),
    ], params);
    expect(padded, hasLength(1));
    expect(padded.single.start, const Duration(milliseconds: 1500));

    // 起音紧贴 0 时，padding 被夹到 0，不会得到负的时刻。
    final clamped = segmentClips([
      ..._hold(Duration.zero, const Duration(milliseconds: 200), -60),
      ..._hold(
          const Duration(milliseconds: 200), const Duration(seconds: 3), -20),
    ], params);
    expect(clamped.single.start, Duration.zero);
  });

  test('最短片段：短促脉冲被丢弃，够长的保留', () {
    // 变异：把最短片段改成 0.2s，0.5s 的脉冲会被保留，段数变 2，本用例变红。
    const params = ClipParams(
      minDuration: Duration(seconds: 1),
      silenceDuration: Duration(milliseconds: 300),
      mergeGap: Duration.zero,
      prePadding: Duration.zero,
    );
    final samples = [
      ..._hold(Duration.zero, const Duration(milliseconds: 500), -20),
      ..._hold(const Duration(milliseconds: 500),
          const Duration(milliseconds: 1200), -60),
      ..._hold(const Duration(milliseconds: 1200),
          const Duration(milliseconds: 3200), -20),
      ..._hold(
          const Duration(milliseconds: 3200), const Duration(seconds: 4), -60),
    ];
    final clips = segmentClips(samples, params);
    expect(clips, hasLength(1));
    expect(clips.single.start, const Duration(milliseconds: 1200));
    expect(clips.single.end, const Duration(milliseconds: 3200));
  });

  test('最短片段在合并之后判定：两段碎片合并够长就保留', () {
    // 变异：把最短片段改成 1.1s（或把丢弃挪到合并之前），合并后的 1.0s 会被丢掉，
    // 结果为空，本用例变红。
    const params = ClipParams(
      minDuration: Duration(seconds: 1),
      silenceDuration: Duration(milliseconds: 200),
      mergeGap: Duration(milliseconds: 1500),
      prePadding: Duration.zero,
    );
    final samples = [
      ..._hold(Duration.zero, const Duration(milliseconds: 400), -20),
      ..._hold(const Duration(milliseconds: 400),
          const Duration(milliseconds: 600), -60),
      ..._hold(
          const Duration(milliseconds: 600), const Duration(seconds: 1), -20),
      ..._hold(
          const Duration(seconds: 1), const Duration(milliseconds: 1200), -60),
    ];
    final clips = segmentClips(samples, params);
    expect(clips, hasLength(1));
    expect(clips.single.start, Duration.zero);
    expect(clips.single.end, const Duration(seconds: 1));
  });

  test('最长片段：超过 60 秒强制切分，每段都不超过上限', () {
    // 变异：把最长片段改成 300s，150s 不再切分，段数变 1，本用例变红。
    final samples = _hold(Duration.zero, const Duration(seconds: 150), -20);
    final clips = segmentClips(samples, const ClipParams());
    expect(clips, hasLength(3));
    expect(clips.first.start, Duration.zero);
    expect(clips.last.end, const Duration(seconds: 150));
    for (final clip in clips) {
      expect(clip.duration, lessThanOrEqualTo(const Duration(seconds: 60)));
    }
  });

  test('合并间隔：相邻片段间隔小于 1.5 秒就并成一段', () {
    // 变异：把合并间隔改成 0.5s，两段不再合并，段数变 2，本用例变红。
    const params = ClipParams(
      silenceDuration: Duration(milliseconds: 300),
      mergeGap: Duration(milliseconds: 1500),
      prePadding: Duration.zero,
      minDuration: Duration.zero,
    );
    final samples = [
      ..._hold(Duration.zero, const Duration(seconds: 1), -20),
      ..._hold(const Duration(seconds: 1), const Duration(seconds: 2), -60),
      ..._hold(const Duration(seconds: 2), const Duration(seconds: 3), -20),
    ];
    final clips = segmentClips(samples, params);
    expect(clips, hasLength(1));
    expect(clips.single.start, Duration.zero);
    expect(clips.single.end, const Duration(seconds: 3));
  });

  test('合并间隔：间隔不小于合并间隔时不合并', () {
    // 变异：把合并间隔改成 3.0s，两段会被并成一段，段数变 1，本用例变红。
    const params = ClipParams(
      silenceDuration: Duration(milliseconds: 300),
      mergeGap: Duration(milliseconds: 1500),
      prePadding: Duration.zero,
      minDuration: Duration.zero,
    );
    final samples = [
      ..._hold(Duration.zero, const Duration(seconds: 1), -20),
      ..._hold(const Duration(seconds: 1), const Duration(seconds: 3), -60),
      ..._hold(const Duration(seconds: 3), const Duration(seconds: 4), -20),
    ];
    expect(segmentClips(samples, params), hasLength(2));
  });

  // ---------------------------------------------------------------------------
  // 真实形态
  // ---------------------------------------------------------------------------

  test('合成鼾声：60 秒连续起伏（低谷 0.4 秒）切成一段，不被换气停顿切碎', () {
    // 变异：把静音时长改成 0.3s（短于 0.4s 的低谷），会被切成几十段、又因每段太短被
    // 丢弃，结果为空，本用例变红。
    final samples = [
      for (var i = 0; i < 600; i++)
        AmplitudeSample(
          offset: Duration(milliseconds: i * 100),
          dbfs: (i % 10) < 6 ? -20.0 : -55.0,
        ),
    ];
    final clips = segmentClips(samples, const ClipParams());
    expect(clips, hasLength(1));
    expect(clips.single.start, Duration.zero);
    expect(clips.single.end, const Duration(milliseconds: 59600));
  });

  test('真正的 5 秒安静间隔会把两段分开', () {
    // 变异：把静音时长改成 6.0s，5 秒的安静不足以结束片段，两段并成一段，本用例变红。
    final samples = [
      ..._hold(Duration.zero, const Duration(seconds: 2), -20),
      ..._hold(const Duration(seconds: 2), const Duration(seconds: 7), -60),
      ..._hold(const Duration(seconds: 7), const Duration(seconds: 9), -20),
    ];
    final clips = segmentClips(samples, const ClipParams());
    expect(clips, hasLength(2));
    expect(clips.first.start, Duration.zero);
    expect(clips.first.end, const Duration(seconds: 2));
    expect(clips.last.start, const Duration(milliseconds: 6500));
    expect(clips.last.end, const Duration(seconds: 9));
  });

  // ---------------------------------------------------------------------------
  // 边界输入
  // ---------------------------------------------------------------------------

  test('边界：空输入返回空', () {
    expect(segmentClips(const [], const ClipParams()), isEmpty);
  });

  test('边界：全静音返回空', () {
    final samples = _hold(Duration.zero, const Duration(seconds: 5), -70);
    expect(segmentClips(samples, const ClipParams()), isEmpty);
  });

  test('边界：一直高于阈值到序列结束时必须收尾成一段而不是丢掉', () {
    final samples = _hold(Duration.zero, const Duration(seconds: 5), -20);
    final clips = segmentClips(samples, const ClipParams());
    expect(clips, hasLength(1));
    expect(clips.single.start, Duration.zero);
    expect(clips.single.end, const Duration(seconds: 5));
  });

  test('边界：单个有声采样点短于最短片段而被丢弃', () {
    const single = [AmplitudeSample(offset: Duration.zero, dbfs: -20)];
    expect(segmentClips(single, const ClipParams()), isEmpty);
  });

  test('边界：单个静音采样点返回空', () {
    const single = [AmplitudeSample(offset: Duration.zero, dbfs: -70)];
    expect(segmentClips(single, const ClipParams()), isEmpty);
  });

  test('边界：单个有声采样点在最短片段为 0 时收尾成零长度片段', () {
    const single = [AmplitudeSample(offset: Duration.zero, dbfs: -20)];
    final clips =
        segmentClips(single, const ClipParams(minDuration: Duration.zero));
    expect(clips, hasLength(1));
    expect(clips.single.start, Duration.zero);
    expect(clips.single.end, Duration.zero);
  });

  // ---------------------------------------------------------------------------
  // 增量 / 批处理等价——防两条路径分叉的唯一保障
  // ---------------------------------------------------------------------------

  test('增量与批处理等价：逐点 add + flush 与 segmentClips 逐条相等', () {
    final samples = <AmplitudeSample>[
      ..._hold(Duration.zero, const Duration(seconds: 2), -20),
      ..._hold(const Duration(seconds: 2), const Duration(seconds: 3), -60),
      ..._hold(
          const Duration(seconds: 3), const Duration(milliseconds: 5600), -20),
      ..._hold(
          const Duration(milliseconds: 5600), const Duration(seconds: 7), -60),
      ..._hold(const Duration(seconds: 7), const Duration(seconds: 8), -42),
      ..._hold(const Duration(seconds: 8), const Duration(seconds: 9), -60),
    ];
    // 非默认参数，让合并 / 最短 / 最长三条规则都实际参与。
    const params = ClipParams(
      silenceDuration: Duration(milliseconds: 800),
      mergeGap: Duration(milliseconds: 900),
      prePadding: Duration(milliseconds: 300),
      minDuration: Duration(milliseconds: 500),
      maxDuration: Duration(seconds: 2),
    );

    final batch = segmentClips(samples, params);
    final segmenter = ClipSegmenter(params);
    final streamed = <ClipRange>[
      for (final sample in samples) ...segmenter.add(sample),
      ...segmenter.flush(),
    ];

    expect(streamed, hasLength(batch.length));
    for (var i = 0; i < batch.length; i++) {
      expect(streamed[i].start, batch[i].start);
      expect(streamed[i].end, batch[i].end);
    }
  });

  // ---------------------------------------------------------------------------
  // envelopeFor
  // ---------------------------------------------------------------------------

  const envelopeRange =
      ClipRange(start: Duration.zero, end: Duration(seconds: 2));

  test('包络：长度恒为 bars', () {
    final samples = _hold(Duration.zero, const Duration(seconds: 2), -30);
    for (final bars in [1, 5, 38, 100]) {
      expect(envelopeFor(samples, envelopeRange, bars: bars), hasLength(bars));
    }
    // 默认 38，对齐 SoundClip.waveformBarCount。
    expect(envelopeFor(samples, envelopeRange), hasLength(38));
  });

  test('包络：值域落在 0–1 且随电平单调', () {
    final samples = [
      for (var i = 0; i < 20; i++)
        AmplitudeSample(
          offset: Duration(milliseconds: i * 100),
          dbfs: -60 + i * 2.0,
        ),
    ];
    final bars = envelopeFor(samples, envelopeRange, bars: 20);
    expect(bars, hasLength(20));
    for (final value in bars) {
      expect(value, inInclusiveRange(0.0, 1.0));
    }
    for (var i = 1; i < bars.length; i++) {
      expect(bars[i], greaterThanOrEqualTo(bars[i - 1]));
    }
    expect(bars.first, 0.0);
    expect(bars.last, 1.0);
  });

  test('包络：全静音不产生 NaN，画成 0', () {
    final samples = _hold(Duration.zero, const Duration(seconds: 2), -70);
    final bars = envelopeFor(samples, envelopeRange, bars: 38);
    expect(bars, hasLength(38));
    for (final value in bars) {
      expect(value.isNaN, isFalse);
      expect(value, 0.0);
    }
  });

  test('包络：区间内没有采样点时返回全 0 而不是抛异常', () {
    final samples = _hold(Duration.zero, const Duration(seconds: 1), -30);
    const empty =
        ClipRange(start: Duration(seconds: 10), end: Duration(seconds: 12));
    final bars = envelopeFor(samples, empty, bars: 10);
    expect(bars, hasLength(10));
    for (final value in bars) {
      expect(value, 0.0);
    }
  });

  test('包络：只统计区间内的采样点', () {
    final samples = [
      ..._hold(Duration.zero, const Duration(seconds: 5), -10),
      ..._hold(const Duration(seconds: 5), const Duration(seconds: 7), -60),
      ..._hold(const Duration(seconds: 7), const Duration(seconds: 8), -20),
    ];
    const range =
        ClipRange(start: Duration(seconds: 5), end: Duration(seconds: 8));
    final bars = envelopeFor(samples, range, bars: 20);
    // 区间外的 −10 若被算进来，最大值就会变成 −10，末条不会是 1。
    expect(bars.first, 0.0);
    expect(bars.last, 1.0);
  });

  /// **出厂默认参数下，合并这条路必须真的走得通。**
  ///
  /// 它曾经走不通：`mergeGap` 默认 1.5 秒，而 `silenceDuration − prePadding`
  /// 恰好也是 1.5 秒，判据又是严格小于——合并窗口是空的，参数等于不存在。
  /// 后果不是「少一个功能」，而是鼾声那 2–3 秒的换气停顿会把一整段鼾声切成
  /// 几十个碎片，正是这条规则存在的理由。这条测试就是钉住那个窗口不为空。
  group('出厂默认参数', () {
    const params = ClipParams();

    test('2.5 秒的换气停顿被并成一段，不是两段', () {
      expect(
        params.mergeGap,
        greaterThan(params.silenceDuration - params.prePadding),
        reason: '合并窗口是空的，这条规则永远不会触发',
      );

      final samples = [
        ..._hold(Duration.zero, const Duration(seconds: 3), -10),
        // 2.5 秒的停顿：长于静音时长（2s，所以那一段已经关上、进了 pending），
        // 但短于合并上限（2.0 + 3.0 − 0.5 = 4.5s）。
        ..._hold(const Duration(seconds: 3),
            const Duration(seconds: 5, milliseconds: 500), -60),
        ..._hold(const Duration(seconds: 5, milliseconds: 500),
            const Duration(seconds: 8), -10),
      ];

      final clips = segmentClips(samples, params);

      // 变异验证：把 `mergeGap` 默认值改回 1.5 秒，这里会变成两段。
      expect(clips, hasLength(1), reason: '换气停顿不该把一段鼾声切碎');
    });

    test('真正长久的安静（10 秒）仍然把两段分开', () {
      final samples = [
        ..._hold(Duration.zero, const Duration(seconds: 3), -10),
        ..._hold(const Duration(seconds: 3), const Duration(seconds: 13), -60),
        ..._hold(const Duration(seconds: 13), const Duration(seconds: 16), -10),
      ];

      // 合并窗口没有被放得过大：真的安静下来还是要分成两段。
      expect(segmentClips(samples, params), hasLength(2));
    });
  });
}
