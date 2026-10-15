// 声学特征与判定的单测。
//
// **信号一律在这里合成，不提交 .wav fixture**（与本仓其余音频测试一致，见
// `night_recorder_test.dart` 的 `_pcm`）。合成的信号不能证明「阈值在真实鼾声上
// 是对的」——那件事只有人耳能答；这里钉的是**代码有没有按写下的规则算**。
//
// 每个可调常量至少一条用例，括号里写「把哪个常量改成什么会让它变红」。
//
// 真机复核的入口是 `tool/eval_clips.dart`（拿真实标注算正确率）与
// `tool/analyse_clips.dart`（逐段打特征表给人耳听）。这里合成信号做得再全，
// 也替代不了那两个。

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/features/sleep/domain/clip_analysis.dart';

const int _rate = 16000;

/// 若干等幅正弦的叠加。用来合成「窄带、低频、**周期**」——也就是鼾声在特征上的样子。
Float64List _tone(List<double> partials, {required int ms, double amp = 0.4}) {
  final n = _rate * ms ~/ 1000;
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    final t = i / _rate;
    var sum = 0.0;
    for (final hz in partials) {
      sum += math.sin(2 * math.pi * hz * t);
    }
    out[i] = amp * sum / partials.length;
  }
  return out;
}

/// 60 Hz 基频的**多谐波**音——鼾声在频率上的样子。
///
/// **为什么谐波要这么多、振幅要这样铺**：鼾声是软腭振动的**粗糙**声，能量摊在
/// 众多谐波上；如果只取两三个等幅谐波，合成出来的东西其实更接近**乐音**，
/// 会被 `snoreMaxPeakShare` 判掉——那正是哼歌的特征，不是鼾声的。
/// 振幅取 [1.0, 1.0, 0.9, …, 0.15]：低频占比约 70%、谱质心约 216 Hz、
/// 最强单音占比约 12%，四条判据都过得去。
const _snoreWeights = [
  1.0,
  1.0,
  0.9,
  0.8,
  0.7,
  0.6,
  0.5,
  0.4,
  0.3,
  0.25,
  0.2,
  0.15
];

Float64List _snoreTone({required int ms}) {
  final n = _rate * ms ~/ 1000;
  final out = Float64List(n);
  var norm = 0.0;
  for (final w in _snoreWeights) {
    norm += w;
  }
  for (var i = 0; i < n; i++) {
    final t = i / _rate;
    var sum = 0.0;
    for (var k = 0; k < _snoreWeights.length; k++) {
      sum += _snoreWeights[k] * math.sin(2 * math.pi * 60 * (k + 1) * t);
    }
    out[i] = 0.5 * sum / norm;
  }
  return out;
}

/// 一个**近乎纯音**的持续低频音——哼歌在特征上的样子。真机上使用方哼歌那一段：
/// 最强谱峰占 **43.3%**、峰间距只有 12 Hz 的颤音、低频 60–83%、周期性 0.81–0.96。
Float64List _humTone({required int ms}) {
  final n = _rate * ms ~/ 1000;
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    out[i] = 0.45 * math.sin(2 * math.pi * 250 * i / _rate);
  }
  return out;
}

/// 浊音：**有基频的谐波列**，能量落在语音带。
///
/// 必须真的是周期的——早先这里合成的是「语音带内一堆随机频率求和」，那种信号在
/// 周期性上和白噪声没区别，换掉旧判据之后它会立刻判不出来。真实浊音本来就是
/// 声带周期振动的谐波列，所以这个合成方式既更简单也更接近事实。
Float64List _voicedTone({
  required int ms,
  double f0 = 150,
  int harmonics = 22,
  double amp = 0.4,
}) {
  final n = _rate * ms ~/ 1000;
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    final t = i / _rate;
    var sum = 0.0;
    for (var k = 1; k <= harmonics; k++) {
      sum += math.sin(2 * math.pi * f0 * k * t);
    }
    out[i] = amp * sum / harmonics;
  }
  return out;
}

/// 白噪声。定种子，保证每次跑出来一模一样。
Float64List _whiteNoise({required int ms, double amp = 0.3, int seed = 7}) {
  final rng = math.Random(seed);
  final n = _rate * ms ~/ 1000;
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    out[i] = amp * (rng.nextDouble() * 2 - 1);
  }
  return out;
}

/// 把几段信号首尾接起来——「一段录音里先后有几种声音」就是这么来的。
Float64List _concat(List<Float64List> parts) {
  final total = parts.fold<int>(0, (sum, p) => sum + p.length);
  final out = Float64List(total);
  var at = 0;
  for (final part in parts) {
    out.setRange(at, at + part.length, part);
    at += part.length;
  }
  return out;
}

void main() {
  group('谱质心 = 纯音的频率（这一条同时钉住整条 FFT）', () {
    test('440 Hz 的谱质心就是 440 Hz 左右', () {
      // 变异：把 `_fft` 里的**位反转置换**删掉，本用例立刻变红——质心跑到 2437 Hz
      // （实测读数），整条谱被打乱。
      //
      // **反过来，把旋转因子的虚部符号写反是不会变红的**（也实测过）：对实数输入
      // 那只是取共轭，`|X[N−k]| = |X[k]|`，功率谱一个数都不变。所以任何基于幅度谱
      // 的特征都测不出它——**它不是 bug，是一条测不到的等价变换**。写在这里免得
      // 以后有人看到那句「符号写反了」的直觉去改一个本来对的地方。
      final features = measureClip(
        _tone(const [440], ms: 500),
        sampleRate: _rate,
      );
      expect(features.spectralCentroid, closeTo(440, 40),
          reason: 'FFT 算对了，纯音的谱质心才会落回它自己的频率上');
    });

    test('220 Hz 的谱质心低于 440 Hz 的——频带归属不是常数', () {
      final low = measureClip(_tone(const [220], ms: 500), sampleRate: _rate);
      final high = measureClip(_tone(const [440], ms: 500), sampleRate: _rate);
      expect(low.spectralCentroid, lessThan(high.spectralCentroid));
    });
  });

  group('周期性：替掉旧「音节带包络能量」的那条判据', () {
    test('周期信号高、白噪声低——这是它能当判据的根据', () {
      final periodic =
          measureClip(_snoreTone(ms: 2000), sampleRate: _rate).pitchStrength;
      final noisy =
          measureClip(_whiteNoise(ms: 2000), sampleRate: _rate).pitchStrength;
      expect(periodic, greaterThan(0.6), reason: '60 Hz 的谐波列当然应该是周期的');
      expect(noisy, lessThan(0.35),
          reason: '白噪声没有周期可言。旧判据正是在这一步失守的：'
              '它对无调制的白噪声也给 16%–30%，而阈值是 25%');
      expect(periodic, greaterThan(noisy + 0.3), reason: '两者必须拉得开');
    });

    test('搜索范围的下限真的卡在 `pitchBandBottom` 上', () {
      // 变异：把 `pitchBandBottom` 从 40 提到 200，本用例变红——100 Hz 的周期信号
      // 会被整个排除在搜索范围之外，周期性塌到噪声水平。
      final low = _tone(const [100], ms: 2000);
      final wide = measureClip(low, sampleRate: _rate);
      final narrow = measureClip(
        low,
        sampleRate: _rate,
        params: const ClipAnalysisParams(pitchBandBottom: 200),
      );
      expect(wide.pitchStrength, greaterThan(0.6));
      expect(narrow.pitchStrength, lessThan(0.35),
          reason: '基频落在搜索范围之外，就不该再被认成周期的');
    });

    test('次声与直流不会把周期性抬起来', () {
      // 自相关里直流是一个**与延迟无关的常数偏置**，不清掉的话所有延迟上的值
      // 会被一起抬高，周期性再也分不出来。变异：把 `_pitchStrength` 里那段
      // 清零次声 bin 的循环删掉，本用例变红。
      final noisy = _whiteNoise(ms: 2000, seed: 3);
      final biased = Float64List(noisy.length);
      for (var i = 0; i < noisy.length; i++) {
        biased[i] = noisy[i] + 0.5; // 麦克风直流偏置
      }
      expect(
        measureClip(biased, sampleRate: _rate).pitchStrength,
        closeTo(measureClip(noisy, sampleRate: _rate).pitchStrength, 0.1),
      );
    });
  });

  group('低频带：直流不算声音', () {
    test('叠加直流偏置不改变任何特征', () {
      // 变异：把 `_spectralStats` 里的逐帧去直流删掉，本用例变红——直流是 bin 0
      // 上一个压倒性的尖峰，会把**质心从 1000 Hz 拽到 90 Hz**（实测读数）。
      //
      // **初版这条注释是假的，写下来免得再犯**：那时它只断言 lowRatio，而低频带的
      // 下界（`lowBandBottom`）单独就把直流挡在外面了，所以去掉去直流它照样绿。
      // 直流与次声是两回事，两条机制各挡一个——次声那条见下面一个用例。
      final clean = _tone(const [800, 1200], ms: 500);
      final biased = Float64List(clean.length);
      for (var i = 0; i < clean.length; i++) {
        biased[i] = clean[i] + 0.5;
      }
      final a = measureClip(clean, sampleRate: _rate);
      final b = measureClip(biased, sampleRate: _rate);

      expect(b.lowRatio, closeTo(a.lowRatio, 0.05),
          reason: '直流是采集 artifact，不是低频声音；它不该左右判断');
      expect(b.spectralCentroid, closeTo(a.spectralCentroid, 20),
          reason: '不去直流的话，bin 0 那个尖峰会把这个数拽到接近 0');
      expect(b.spectralFlatness, closeTo(a.spectralFlatness, 0.02),
          reason: '不去直流的话，bin 0 会抬高算术均、压低平坦度');
    });

    test('20 Hz 以下的成分不算进低频带', () {
      // 去直流挡的是**恒定**偏置；这一条挡的是**次声**（真的在动，只是低到听不见）。
      // 两者是不同的东西，所以是两条机制。
      // 变异：把 `lowBandBottom` 改回 0，本用例变红——10 Hz 会整个落进低频带。
      final infrasonic = Float64List(_rate * 2);
      for (var i = 0; i < infrasonic.length; i++) {
        final t = i / _rate;
        infrasonic[i] = 0.5 * math.sin(2 * math.pi * 10 * t) +
            0.02 * math.sin(2 * math.pi * 800 * t);
      }
      final features = measureClip(infrasonic, sampleRate: _rate);
      expect(features.lowRatio, lessThan(0.5),
          reason: '10 Hz 听不见也不是鼾声的能量区，不该被算成「低频很足」');
    });
  });

  group('判定：打鼾', () {
    test('持续的低频周期音判为疑似打鼾', () {
      final verdict = classifyClip(_snoreTone(ms: 3000), sampleRate: _rate);
      expect(verdict, isNotNull, reason: '低频 + 暗 + 周期三条都满足，不该弃权');
      expect(verdict!.label, AutoLabel.snore);
    });

    test('判出来的事件带着起止位置', () {
      // 一段里混着几种声音时，「在哪几秒」和「是什么」一样重要。
      final verdict = classifyClip(_snoreTone(ms: 3000), sampleRate: _rate);
      expect(verdict!.startMs, lessThan(400));
      expect(verdict.durationMs, greaterThanOrEqualTo(2500));
    });

    test('疑似的说法里带「疑似」二字', () {
      // 界面上的措辞也是契约的一部分：机器没听过，只能说「疑似」。
      expect(AutoLabel.snore.label, contains('疑似'));
      expect(AutoLabel.voice.label, contains('疑似'));
    });

    test('**近乎纯音**的持续低频音不判打鼾——那是哼歌', () {
      // 使用方 2026-10-15 澄清：那段被判「疑似打鼾」的录音，**前面一段是他自己在哼歌**。
      // 哼歌与鼾声在「低频 + 周期」上几乎无法区分（哼歌也是准周期的低频浊音），
      // 分开两者的是**有调性**：哼歌是乐音，鼾声是粗糙声。
      //
      // 变异：把 `snoreMaxPeakShare` 抬到 1.0（等于取消这条判据），本用例变红——
      // 使用方手机上的哼歌会被判成疑似打鼾，那正是这一轮要修的误报。
      final hum = _humTone(ms: 3000);
      final f = measureClip(hum, sampleRate: _rate);
      expect(f.spectralPeakShare, greaterThan(0.35),
          reason: '哼歌是近乎纯音，最强单音应当占掉很大一块能量');
      expect(f.lowRatio, greaterThan(0.45), reason: '哼的是低音，低频占比确实高');
      expect(f.pitchStrength, greaterThan(0.5),
          reason: '它确实是周期的——'
              '正因如此，光靠周期性分不开哼歌与鼾声');
      expect(
        classifyClip(hum, sampleRate: _rate)?.label,
        isNot(AutoLabel.snore),
        reason: '低频、周期都满足，唯独它是乐音——鼾声不是乐音',
      );
    });
  });

  group('时长门槛：这是整轮改动里最重要的一条', () {
    test('1.1 秒的低频周期瞬态**不**判打鼾', () {
      // 这是使用方在真机上抓到的那次误报：一段 1.1 秒的拖椅子声，低频 75%、
      // 质心 350 Hz、平坦度 0.02，是全部样本里最像鼾声的一段。使用方的话是
      // **「鼾声不可能只有一秒钟」**。
      //
      // 变异：把 `minEventMs` 降到 1000，本用例变红。
      final brief = _snoreTone(ms: 1100);
      final verdict = classifyClip(brief, sampleRate: _rate);
      expect(verdict?.label, isNot(AutoLabel.snore),
          reason: '频率上再像，只有 1.1 秒就不是鼾声');
    });

    test('同一段信号拉长到 3 秒就判得出来了——差别只在时长', () {
      // 与上一条配对：把这条断言删掉，上一条就可能被「阈值调高到什么都不判」
      // 这种改动蒙混过去。两条一起才说明**时长**是那个变量。
      expect(
        classifyClip(_snoreTone(ms: 3000), sampleRate: _rate)?.label,
        AutoLabel.snore,
      );
      expect(
        classifyClip(_snoreTone(ms: 1100), sampleRate: _rate)?.label,
        isNot(AutoLabel.snore),
      );
    });

    test('够长但中间断开的，合并之后仍然算一段', () {
      // 鼾声是一串：一次吸气一两秒，两次之间本来就有停顿。不合并的话每一段单独的
      // 鼾声都够不着门槛，整夜会一条都判不出来。
      // 变异：把 `mergeGapMs` 降到 0，本用例变红。
      final train = _concat([
        _snoreTone(ms: 1600),
        Float64List(_rate), // 1 秒停顿
        _snoreTone(ms: 1600),
      ]);
      final verdict = classifyClip(train, sampleRate: _rate);
      expect(verdict?.label, AutoLabel.snore,
          reason: '两段 1.6 秒的鼾声中间隔 1 秒，合起来是一串鼾声');
    });

    test('有够格的窗口却连不成一段时**弃权**', () {
      // 1.1 秒的鼾声在频谱上够格，只是太短（见 `minEventMs`）。这正是使用方那台
      // 机器上「拖椅子」那一段的形状：机器看见了像鼾声的东西，但拿不准。
      // 变异：把 `minEventMs` 降到 500，本用例变红——这段会拿到「疑似打鼾」。
      final brief = _snoreTone(ms: 1100);
      expect(classifyClip(brief, sampleRate: _rate), isNull);
      expect(detectEvents(brief, sampleRate: _rate), isEmpty);
    });
  });

  group('判定：疑似人声', () {
    test('语音带的周期音判为疑似人声', () {
      final verdict = classifyClip(_voicedTone(ms: 3000), sampleRate: _rate);
      expect(verdict, isNotNull);
      expect(verdict!.label, AutoLabel.voice);
    });

    test('同样的频带，去掉周期性就判不出来', () {
      // 变异：把 `voicePitchStrength` 降到 0，本用例变红。
      // 频带内的白噪声：能量确实在语音带，但完全不周期——真实世界里对应的就是
      // 床品窸窣、翻身的摩擦，它们同样落在语音带里，这正是旧判据分不开的那一批。
      const n = _rate * 3;
      final rng = math.Random(5);
      final noise = Float64List(n);
      for (var i = 0; i < n; i++) {
        noise[i] = 0.3 * (rng.nextDouble() * 2 - 1);
      }
      final features = measureClip(noise, sampleRate: _rate);
      expect(features.pitchStrength, lessThan(0.4));
      expect(
        classifyClip(noise, sampleRate: _rate)?.label,
        isNot(AutoLabel.voice),
        reason: '光有语音带能量、没有周期性，不足以说是人声',
      );
    });

    test('低频主导的东西不会被两条规则同时认领', () {
      // 互斥是靠 `voiceLowRatioMax` 保证的。变异：把它抬到 1.0，本用例变红——
      // 一段低频周期音会同时满足两条规则。
      final f = measureClip(_snoreTone(ms: 3000), sampleRate: _rate);
      expect(f.lowRatio, greaterThan(0.45));
      expect(
        classifyClip(_snoreTone(ms: 3000), sampleRate: _rate)?.label,
        AutoLabel.snore,
      );
    });
  });

  group('判不出来就弃权：机器不拿「杂音」兜底', () {
    test('扫过一遍没找到事件 → 弃权，**不再说杂音**', () {
      // 使用方 2026-10-15 的原话是「判不出来就留待标注」。这条兜底拆掉的直接理由：
      // 报杂音等于同时断言「不是鼾声」和「不是人声」，而机器**认不出鼾声**
      // （19 段已标注真机片段上召回 0%），没有资格下这个否定结论。
      // 变异：把 `classifyClip` 里 `if (events.isEmpty) return null;` 改回返回
      // `AutoLabel.noise`，本用例变红。
      final verdict = classifyClip(_whiteNoise(ms: 3000), sampleRate: _rate);
      expect(verdict, isNull, reason: '宽带白噪机器确实判不出来——判不出来就该什么都不说');
    });

    test('**任何**输入都不会产出 AutoLabel.noise', () {
      // 这条钉的是「杂音只能由人来给」这个不变量本身，不是某一个例子。
      final inputs = <Float64List>[
        _whiteNoise(ms: 3000),
        _snoreTone(ms: 3000),
        _voicedTone(ms: 3000),
        _snoreTone(ms: 1100),
        Float64List(_rate * 3),
        Float64List(0),
      ];
      for (final input in inputs) {
        expect(classifyClip(input, sampleRate: _rate)?.label,
            isNot(AutoLabel.noise));
      }
    });

    test('响度不够的片段不参与判定，哪怕特征上像极了鼾声', () {
      // 平台静音录到的是一串零；比它响一点、但仍然近乎无声的片段同样不该拿到标签
      // ——太轻的信号算出来的谱特征本来就不作数。
      // **这条信号是刻意挑的**：把它放大 1000 倍就是本文件里判得最稳的那段鼾声，
      // 所以这里挡住它的**只可能是**响度闸，不可能是别的原因。
      // 变异：把 `noiseMinDbfs` 降到 -200，本用例变红（这段会拿到「疑似打鼾」）。
      final faint = _snoreTone(ms: 3000).map((v) => v * 0.001).toList();
      final samples = Float64List.fromList(faint);
      expect(measureClip(samples, sampleRate: _rate).dbfs, lessThan(-60));
      expect(classifyClip(samples, sampleRate: _rate), isNull);
    });

    test('数字静音不参与判定，是弃权', () {
      expect(classifyClip(Float64List(_rate * 3), sampleRate: _rate), isNull);
    });

    test('太短、太轻的片段不下结论', () {
      expect(classifyClip(Float64List(10), sampleRate: _rate), isNull);
      expect(classifyClip(Float64List(0), sampleRate: _rate), isNull);
      expect(measureClip(Float64List(0), sampleRate: _rate).lowRatio, 0);
    });
  });

  group('一段里先后混着两种声音', () {
    test('前 3 秒鼾声、后 6 秒杂音 → 判鼾声，且指出是前几秒', () {
      // 这正是使用方提出来的情形：「这一段里面可以有鼾声跟杂音是一起的，
      // 你把鼾声标记出来即可」。旧版把整段平均成一个向量，平均完谁都不像，
      // 只能弃权——**明明有 3 秒鼾声**。
      final mixed = _concat([
        _snoreTone(ms: 3000),
        _whiteNoise(ms: 6000, amp: 0.25),
      ]);
      final verdict = classifyClip(mixed, sampleRate: _rate);
      expect(verdict?.label, AutoLabel.snore);
      expect(verdict!.startMs, lessThan(500), reason: '鼾声在开头');
      expect(verdict.durationMs, greaterThanOrEqualTo(2500));
      expect(verdict.durationMs, lessThan(5000), reason: '不该把后面那 6 秒杂音也算进鼾声里');
    });

    test('前 6 秒杂音、后 3 秒鼾声 → 判鼾声，起点在后面', () {
      final mixed = _concat([
        _whiteNoise(ms: 6000, amp: 0.25),
        _snoreTone(ms: 3000),
      ]);
      final verdict = classifyClip(mixed, sampleRate: _rate);
      expect(verdict?.label, AutoLabel.snore);
      expect(verdict!.startMs, greaterThan(4000), reason: '鼾声在后面');
    });
  });

  group('最低余量：擦边不算数（「有把握才自动写」的落点）', () {
    test('余量门槛抬高之后就不再下结论', () {
      // 变异：把 `minMargin` 的默认值改成 0，本用例变红。
      final signal = _snoreTone(ms: 3000);
      const strict = ClipAnalysisParams(minMargin: 0.99);
      expect(classifyClip(signal, sampleRate: _rate)?.label, AutoLabel.snore);
      expect(classifyClip(signal, sampleRate: _rate, params: strict), isNull,
          reason: '门槛抬高之后，同样的声音不再够格被自动标注——'
              '而且必须是**弃权**，不能退化成「杂音」');
    });
  });

  group('不变量：特征永远是有限值且在值域内', () {
    test('各种输入下都不出 NaN / 越界', () {
      final inputs = <Float64List>[
        Float64List(0),
        Float64List(5),
        Float64List(_rate),
        _whiteNoise(ms: 500),
        _tone(const [60], ms: 500),
        _tone(const [7000], ms: 500),
        _voicedTone(ms: 500),
      ];
      for (final input in inputs) {
        final f = measureClip(input, sampleRate: _rate);
        for (final value in [
          f.dbfs,
          f.lowRatio,
          f.speechRatio,
          f.highRatio,
          f.spectralCentroid,
          f.spectralFlatness,
          f.pitchStrength,
          f.spectralPeakShare,
          f.zeroCrossingRate,
          f.breathBandRatio,
          f.syllableBandRatio,
        ]) {
          expect(value.isFinite, isTrue, reason: '特征值不许是 NaN / 无穷');
        }
        expect(f.lowRatio, inInclusiveRange(0, 1));
        expect(f.speechRatio, inInclusiveRange(0, 1));
        expect(f.highRatio, inInclusiveRange(0, 1));
        expect(f.spectralFlatness, inInclusiveRange(0, 1));
        expect(f.pitchStrength, inInclusiveRange(0, 1));
        expect(f.spectralPeakShare, inInclusiveRange(0, 1));
        expect(f.zeroCrossingRate, inInclusiveRange(0, 1));
        expect(f.breathBandRatio, inInclusiveRange(0, 1));
        expect(f.syllableBandRatio, inInclusiveRange(0, 1));
        expect(f.spectralCentroid, greaterThanOrEqualTo(0));
      }
    });

    test('余量恒在 0–1 之间，事件时长恒非负', () {
      for (final ms in [1100, 3000, 6000]) {
        final v = classifyClip(_snoreTone(ms: ms), sampleRate: _rate);
        if (v != null) {
          expect(v.margin, inInclusiveRange(0, 1));
          expect(v.durationMs, greaterThanOrEqualTo(0));
          expect(v.startMs, greaterThanOrEqualTo(0));
        }
      }
    });
  });

  group('依据串：给的是实测数，不是把握', () {
    test('依据里含低频占比、谱质心、周期性、最强单音占比', () {
      final f =
          measureClip(_tone(const [60, 120], ms: 1000), sampleRate: _rate);
      expect(f.basis, contains('低频能量'));
      expect(f.basis, contains('谱质心'));
      expect(f.basis, contains('周期性'));
      expect(f.basis, contains('最强单音占比'));
    });

    test('依据串里不出现任何「概率 / 把握 / 置信」字样', () {
      // 界面上不许把一个测出来的比例说成「有 66% 的把握是鼾声」——
      // 没有标注数据就估不出概率，那是编的。见 `clip_analysis.dart` 文件头。
      final f =
          measureClip(_tone(const [60, 120], ms: 1000), sampleRate: _rate);
      for (final word in ['把握', '概率', '置信']) {
        expect(f.basis.contains(word), isFalse);
      }
    });
  });

  group('落库：标签与判断的往返', () {
    test('AutoLabel 的 id 稳定，且能被读回来', () {
      // 变异：改 `AutoLabel.snore` 的 id 字符串，本用例变红，
      // 且已经写进库的旧行读不回来。
      expect(AutoLabel.snore.id, 'snore');
      expect(AutoLabel.voice.id, 'voice');
      expect(AutoLabel.noise.id, 'noise');
      expect(AutoLabel.fromId('snore'), AutoLabel.snore);
      expect(AutoLabel.fromId('voice'), AutoLabel.voice);
      expect(AutoLabel.fromId('noise'), AutoLabel.noise);
      expect(AutoLabel.fromId(null), isNull);
      expect(AutoLabel.fromId('乱写的'), isNull);
    });

    test('判断编码再解码之后，位置与时长都还在', () {
      final at = DateTime.utc(2026, 10, 15, 20, 40);
      final original = AutoAnalysis(
        verdict: const AutoVerdict(
          label: AutoLabel.snore,
          margin: 0.62,
          basis: '低频能量 70% · 谱质心 344 Hz · 周期性 0.95',
          startMs: 300,
          durationMs: 4500,
        ),
        analyzedAtUtc: at,
      );
      final decoded = AutoAnalysis.decode(original.encode());
      expect(decoded, isNotNull);
      expect(decoded!.verdict!.label, AutoLabel.snore);
      expect(decoded.verdict!.startMs, 300);
      expect(decoded.verdict!.durationMs, 4500);
      expect(decoded.analyzedAtUtc, at);
    });

    test('弃权能编码，也能读回来——它和「没分析过」不是一回事', () {
      final at = DateTime.utc(2026, 10, 15);
      final decoded = AutoAnalysis.decode(
          AutoAnalysis(verdict: null, analyzedAtUtc: at).encode());
      expect(decoded, isNotNull);
      expect(decoded!.verdict, isNull);
      expect(AutoAnalysis.decode(null), isNull);
      expect(AutoAnalysis.decode('{不是 json'), isNull);
    });

    test('旧记录没有 startMs / durationMs，读出来当 0，不当坏数据', () {
      // 这两个键是后加的。旧行本来就没有它们，那是真实情况，不是损坏——
      // 当作坏数据会让升级之后所有历史判断凭空消失。
      const legacy = '{"kind":"snore","margin":0.5,"basis":"低频能量 66%",'
          '"atUtc":"2026-10-14T00:34:00.000Z"}';
      final decoded = AutoAnalysis.decode(legacy);
      expect(decoded, isNotNull);
      expect(decoded!.verdict!.label, AutoLabel.snore);
      expect(decoded.verdict!.startMs, 0);
      expect(decoded.verdict!.durationMs, 0);
    });
  });
}
