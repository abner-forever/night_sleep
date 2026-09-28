import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/features/sleep/data/noise_synth.dart';

/// Waveform-level tests for the sleep-sound synthesis.
///
/// Nothing here listens to the output — that needs a device. What it does do is
/// check the properties that separate real synthesis from "it produced some
/// bytes": spectral slope, crest factor, seam continuity and determinism. A
/// generator that returned silence, or white noise for every kind, would pass a
/// naive length check and fail every test in this file.
void main() {
  /// Fraction of adjacent sample pairs that cross zero — a cheap brightness
  /// proxy. White ≈ 0.5; the more low-frequency energy, the lower it falls.
  double zeroCrossingRate(Float64List samples) {
    var crossings = 0;
    for (var i = 1; i < samples.length; i++) {
      if ((samples[i - 1] < 0) != (samples[i] < 0)) crossings++;
    }
    return crossings / (samples.length - 1);
  }

  double rms(Float64List samples) {
    var sum = 0.0;
    for (final value in samples) {
      sum += value * value;
    }
    return math.sqrt(sum / samples.length);
  }

  double peak(Float64List samples) {
    var maxAbs = 0.0;
    for (final value in samples) {
      final magnitude = value.abs();
      if (magnitude > maxAbs) maxAbs = magnitude;
    }
    return maxAbs;
  }

  double mean(Float64List samples) {
    var sum = 0.0;
    for (final value in samples) {
      sum += value;
    }
    return sum / samples.length;
  }

  group('波形', () {
    test('每种声音都是确定性的：同一种子出同一条波形', () {
      for (final kind in NoiseKind.values) {
        final first = buildNoiseWav(kind);
        final second = buildNoiseWav(kind);
        expect(first, equals(second), reason: '${kind.id} 两次生成不一致');
      }
    });

    test('八种声音互不相同', () {
      // Guards against a generator that silently falls through to the same bed
      // for several kinds — which is easy to do and hard to notice by ear when
      // the differences are meant to be subtle.
      final digests = <NoiseKind, int>{};
      for (final kind in NoiseKind.values) {
        final samples = buildNoiseLoop(kind);
        var hash = 17;
        for (var i = 0; i < samples.length; i += 97) {
          hash = (hash * 31 + (samples[i] * 10000).round()) & 0x7fffffff;
        }
        digests[kind] = hash;
      }
      expect(
        digests.values.toSet(),
        hasLength(NoiseKind.values.length),
        reason: '有声音的波形完全一样，说明生成器没有区分它们',
      );
    });

    test('不削波，且峰值落在设计的目标上', () {
      for (final kind in NoiseKind.values) {
        final samples = buildNoiseLoop(kind);
        expect(
          peak(samples),
          lessThanOrEqualTo(1.0),
          reason: '${kind.id} 超出 [-1,1]，编码时会被削平',
        );
        expect(
          peak(samples),
          closeTo(0.86, 0.001),
          reason: '${kind.id} 的峰值没有归一化到位',
        );
      }
    });

    test('没有直流偏置', () {
      for (final kind in NoiseKind.values) {
        expect(
          mean(buildNoiseLoop(kind)).abs(),
          lessThan(0.005),
          reason: '${kind.id} 有直流偏置，会吃掉动态余量',
        );
      }
    });

    test('循环接缝连续，重启时不会咔哒', () {
      for (final kind in NoiseKind.values) {
        final samples = buildNoiseLoop(kind);
        final seamStep = (samples.first - samples.last).abs();
        // Compare against how much the signal normally moves sample to sample:
        // the seam must not stand out from the ordinary waveform.
        var total = 0.0;
        for (var i = 1; i < samples.length; i++) {
          total += (samples[i] - samples[i - 1]).abs();
        }
        final meanStep = total / (samples.length - 1);
        expect(
          seamStep,
          lessThan(math.max(meanStep * 6, 0.05)),
          reason: '${kind.id} 的接缝跳变 $seamStep 远大于平均步进 $meanStep',
        );
      }
    });
  });

  group('频谱走向', () {
    test('白噪最亮、棕噪最暗，过零率依次递减', () {
      // The whole point of offering three noise colours is that they differ in
      // slope. If the filters were wrong, all three would land near white.
      final white = zeroCrossingRate(buildNoiseLoop(NoiseKind.white));
      final pink = zeroCrossingRate(buildNoiseLoop(NoiseKind.pink));
      final brown = zeroCrossingRate(buildNoiseLoop(NoiseKind.brown));

      expect(white, greaterThan(0.4), reason: '白噪应接近 0.5');
      expect(pink, lessThan(white), reason: '粉噪应比白噪暗');
      expect(brown, lessThan(pink), reason: '棕噪应比粉噪暗');
      expect(brown, lessThan(0.15), reason: '棕噪应以低频为主');
    });

    test('雨与篝火比纯噪声有更多瞬态', () {
      // Droplets and crackles are impulsive, which shows up as a higher
      // peak-to-RMS ratio than the noise bed alone.
      double crest(NoiseKind kind) {
        final samples = buildNoiseLoop(kind);
        return peak(samples) / rms(samples);
      }

      expect(crest(NoiseKind.rain), greaterThan(crest(NoiseKind.white)));
      expect(crest(NoiseKind.fire), greaterThan(crest(NoiseKind.brown)));
    });

    test('海浪有周期性起伏，噪声没有', () {
      //四段浪 across the loop; measure the spread of short-window RMS.
      double envelopeSpread(Float64List samples) {
        const window = kNoiseSampleRate ~/ 4;
        final levels = <double>[];
        for (var start = 0; start + window <= samples.length; start += window) {
          levels.add(rms(samples.sublist(start, start + window)));
        }
        final min = levels.reduce(math.min);
        final max = levels.reduce(math.max);
        return (max - min) / max;
      }

      final ocean = envelopeSpread(buildNoiseLoop(NoiseKind.ocean));
      final brown = envelopeSpread(buildNoiseLoop(NoiseKind.brown));

      expect(ocean, greaterThan(0.35), reason: '海浪应有明显的强弱起伏');
      expect(ocean, greaterThan(brown * 2), reason: '噪声床不该有这么强的起伏');
    });

    test('森林在粉噪底噪之外还有鸟鸣', () {
      // Bird notes are narrowband and loud, so they lift the peaks well above
      // what the wind bed alone reaches.
      final forest = buildNoiseLoop(NoiseKind.forest);
      final pink = buildNoiseLoop(NoiseKind.pink);
      expect(
        peak(forest) / rms(forest),
        greaterThan(peak(pink) / rms(pink)),
        reason: '森林缺少鸟鸣，听起来只会是风',
      );
    });
  });

  group('WAV 容器', () {
    Uint8List wav(NoiseKind kind) => buildNoiseWav(kind);

    String tag(Uint8List bytes, int offset) =>
        String.fromCharCodes(bytes.sublist(offset, offset + 4));

    int u32(Uint8List bytes, int offset) =>
        bytes.buffer.asByteData().getUint32(offset, Endian.little);

    int u16(Uint8List bytes, int offset) =>
        bytes.buffer.asByteData().getUint16(offset, Endian.little);

    test('头部字段正确', () {
      final bytes = wav(NoiseKind.white);

      expect(tag(bytes, 0), 'RIFF');
      expect(tag(bytes, 8), 'WAVE');
      expect(tag(bytes, 12), 'fmt ');
      expect(tag(bytes, 36), 'data');

      expect(u32(bytes, 16), 16, reason: 'PCM 块大小');
      expect(u16(bytes, 20), 1, reason: '必须是未压缩 PCM');
      expect(u16(bytes, 22), 1, reason: '单声道');
      expect(u32(bytes, 24), kNoiseSampleRate);
      expect(u16(bytes, 34), 16, reason: '16 位');
      expect(u32(bytes, 40), bytes.length - 44, reason: 'data 长度应与实际字节数一致');
      expect(u32(bytes, 4), bytes.length - 8, reason: 'RIFF 长度应为文件长度减 8');
    });

    test('采样数与时长相符', () {
      final bytes = wav(NoiseKind.brown);
      final samples = (bytes.length - 44) ~/ 2;
      expect(samples, kNoiseSampleRate * kNoiseLoopSeconds);
    });

    test('字节率与块对齐一致，播放器不会读出噪声', () {
      final bytes = wav(NoiseKind.pink);
      expect(u32(bytes, 28), kNoiseSampleRate * 2, reason: 'byte rate');
      expect(u16(bytes, 32), 2, reason: 'block align');
    });

    test('超出范围的值会被钳制而不是回绕', () {
      // A wrap-around here would turn a loud peak into a full-scale click.
      final clipped = encodeWav(
        Float64List.fromList([2.0, -2.0, 0.0]),
        sampleRate: kNoiseSampleRate,
      );
      final view = clipped.buffer.asByteData();
      expect(view.getInt16(44, Endian.little), 32767);
      expect(view.getInt16(46, Endian.little), -32767);
      expect(view.getInt16(48, Endian.little), 0);
    });
  });

  group('枚举', () {
    test('八个 id 与助眠音效面板一致', () {
      expect(
        NoiseKind.values.map((kind) => kind.id).toList(),
        ['white', 'brown', 'pink', 'rain', 'ocean', 'fire', 'forest', 'fan'],
      );
    });

    test('未知 id 返回 null 而不是崩溃', () {
      expect(NoiseKind.fromId('thunder'), isNull);
      expect(NoiseKind.fromId('rain'), NoiseKind.rain);
    });
  });
}
