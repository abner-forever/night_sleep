// **声学特征测量的单测。判定已经不在这里了。**
//
// 2026-10-16 起机器判定由 YAMNet 给出，规则在 `clip_yamnet.dart`、单测在
// `clip_yamnet_test.dart`。这个文件只剩 `measureClip` / `AudioFeatures` /
// `rmsDbfs`——那些**仍然是真测量**（`tool/analyse_clips.dart` 还拿它们给人核对），
// 只是**不再参与任何判定**。原来那批判定用例连同它们钉的阈值一起删了，理由见
// `clip_analysis.dart` 的文件头。
//
// **信号一律在这里合成，不提交 .wav fixture**（与本仓其余音频测试一致，见
// `night_recorder_test.dart` 的 `_pcm`）。合成的信号不能证明「特征在真实录音上
// 算得对」——那件事只有真人录音能答；这里钉的是**代码有没有按写下的公式算**。
//
// 每个可调常量至少一条用例，括号里写「把哪个常量改成什么会让它变红」。
//
// 真实录音上的账在别处：`tool/eval_clips.dart` 拿人工标注算模型的正确率，
// `tool/analyse_clips.dart` 逐段打特征表给人耳听。这里合成信号做得再全，
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

/// 60 Hz 基频的**多谐波**音——低频、暗、准周期的信号。
///
/// **它不再代表「鼾声」了。** 名字是历史：这套振幅（[1.0, 1.0, 0.9, …, 0.15]）
/// 当初是照着「鼾声是软腭振动的粗糙声、能量摊在众多谐波上」铺的，好让旧的四条
/// 阈值都过得去。**那四条阈值已被证伪并删除**，YAMNet 对这段合成音会说什么
/// 完全未知——所以现在它只是一个「低频 + 周期 + 不刺耳」的测试信号，
/// 用来量特征、用来跑响度那道闸，**不能拿它推断判定**。
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

    test('RMS 响度也是有限值，空输入与全零都是 −160 而不是 NaN', () {
      // 这道量现在多了一个身份：判定那一边拿它当「是不是数字静音」的闸
      // （`clip_yamnet.dart` 的 `kSilenceDbfs`）。所以它不能再出 NaN——
      // `-160 < -60` 是 true，而 `NaN < -60` 是 false，后者会让一段数字静音
      // 悄悄滑过那道闸。
      expect(rmsDbfs(Float64List(0)), -160);
      expect(rmsDbfs(Float64List(1000)), -160);
      for (final input in <Float64List>[
        _whiteNoise(ms: 500),
        _tone(const [60], ms: 500),
        _snoreTone(ms: 3000),
      ]) {
        final dbfs = rmsDbfs(input);
        expect(dbfs.isFinite, isTrue);
        expect(dbfs, greaterThan(-160));
        expect(dbfs, lessThanOrEqualTo(0));
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
