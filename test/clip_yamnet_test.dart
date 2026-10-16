// YAMNet 判定的单测——**整条判定规则就在这里被钉死**。
//
// 这里**不加载模型**（`flutter test` 里没有原生库，加载不了），喂进去的是
// 手写的分数。这正是 `clip_yamnet.dart` 不 import `tflite_flutter` 的原因：
// 「分数怎么变成结论」必须能在单测里逐条验证。
//
// **模型本身算得对不对，这里一条都不管**——那是真机上跑出来的数，记在
// `docs/verification-log.md`。这里只管一件事：**给定这些分数，代码有没有按写下的
// 规则下结论**。
//
// 括号里写「把哪个常量改成什么会让它变红」。阈值那两条尤其重要：它们是**拍的**，
// 所以必须有用例钉住「现在是这么多」，改了就红。

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/features/sleep/domain/clip_analysis.dart';
import 'package:night_sleep/features/sleep/domain/clip_yamnet.dart';

/// 一窗的采样点数：0.975 秒 × 16000。**这个数来自模型文件的输入张量形状。**
const int _window = kYamnetWindowSamples;

/// 造一份「每一窗都是同样的分」的 [ClipScores]，好让均分就是那个值。
ClipScores _flat({double snore = 0, double speech = 0, int windows = 1}) {
  return ClipScores(
    snore: List<double>.filled(windows, snore),
    speech: List<double>.filled(windows, speech),
  );
}

void main() {
  group('类别下标：错一个就是判错整个类', () {
    test('Snoring = 38、Speech = 0（按 mid /m/01d3sd、/m/09x0r 核过）', () {
      // 按 mid 查而不是按数字查：PANNs / AST / CED 用的是 527 类，同一个
      // `Snoring` 在它们那里是 43。把下标记错会让机器一直在判**别的类**，
      // 而那种错在界面上完全看不出来——它照样会给出一个带「疑似」的词。
      expect(kSnoringIndex, 38);
      expect(kSpeechIndex, 0);
      expect(kYamnetClassCount, 521);
    });

    test('窗口与步进：15600 点 / 7800 点，对应 0.975 秒与半个窗口', () {
      // 15600 是官方 README 那句 "you need at least 975 ms of input waveform"
      // 折算出来的采样点数，也是模型输入张量的 shape。改小它等于喂半截窗。
      expect(kYamnetWindowSamples, 15600);
      expect(kYamnetHopSamples, kYamnetWindowSamples ~/ 2);
      expect(kYamnetSampleRate, 16000);
    });
  });

  group('切窗：起点的位置与数量', () {
    test('空输入一个窗都没有——没有采样就没有可测的东西', () {
      expect(yamnetWindowStarts(0), isEmpty);
      expect(yamnetWindowStarts(-1), isEmpty);
    });

    test('比一个窗还短的只给一个起点 0（那一次由调用方补零补满）', () {
      expect(yamnetWindowStarts(1), [0]);
      expect(yamnetWindowStarts(8000), [0]);
    });

    test('刚好一个窗给一个起点', () {
      expect(yamnetWindowStarts(_window), [0]);
    });

    test('一个半窗**仍然只有一个**完整窗——补零凑第二个会让均分掺进静音', () {
      expect(yamnetWindowStarts(_window + kYamnetHopSamples - 1), [0]);
      expect(yamnetWindowStarts(_window + 1), [0]);
    });

    test('步进是半个窗，所以 N 个窗长的音频能放下 2N−1 个窗', () {
      // 重叠 50% 的直接后果：两个窗长的音频容得下三个窗（起于 0 / 半个 / 一个窗）。
      // 把 `kYamnetHopSamples` 改成整个窗会让下面这两条变成 [0, 7800] 与
      // [0, 7800, 15600]——重叠没了，均分也就跟着变。
      const hop = kYamnetHopSamples;
      expect(yamnetWindowStarts(2 * _window), [0, hop, 2 * hop]);
      expect(
          yamnetWindowStarts(3 * _window), [0, hop, 2 * hop, 3 * hop, 4 * hop]);
    });

    test('起点全都落得下整个窗，最后一个不会越界', () {
      const samples = 160000; // 10 秒
      final starts = yamnetWindowStarts(samples);
      expect(starts.length, 19);
      for (final start in starts) {
        expect(start + _window, lessThanOrEqualTo(samples));
      }
      expect(starts.first, 0);
    });
  });

  group('两个统计量', () {
    test('均分就是算术平均', () {
      expect(meanScore([0.2, 0.4, 0.6]), closeTo(0.4, 1e-12));
      expect(meanScore([1]), 1);
      expect(meanScore(const []), 0, reason: '空列表不许出 NaN');
    });

    test('最高分取最大，空列表同样是 0 而不是 NaN', () {
      expect(maxScore([0.2, 0.9, 0.4]), 0.9);
      expect(maxScore([0.5]), 0.5);
      expect(maxScore(const []), 0);
    });

    test('**均分与最高分不是一回事**——这正是两个都摆出来的理由', () {
      // 一段 8 秒的录音里只有一窗是鼾声：均分被摊薄到判定线以下，最高分却很高。
      final scores = ClipScores(
        snore: [0.95, 0, 0, 0, 0, 0, 0, 0],
        speech: List<double>.filled(8, 0),
      );
      expect(meanScore(scores.snore), closeTo(0.119, 1e-3));
      expect(maxScore(scores.snore), 0.95);
      expect(verdictFromScores(scores, dbfs: -30), isNull,
          reason: '判定用的是均分，所以它弃权——这是**已知且记在案**的盲区，'
              '不是可以靠偷偷改成最高分绕过去的');
    });
  });

  group('判定：鼾声', () {
    test('均分过线就是疑似打鼾', () {
      final verdict = verdictFromScores(_flat(snore: 0.85), dbfs: -30);
      expect(verdict, isNotNull);
      expect(verdict!.label, AutoLabel.snore);
    });

    test('判定线是**含**的：正好 0.40 算过线', () {
      // 把 `>=` 改成 `>` 会让这条红。
      expect(verdictFromScores(_flat(snore: 0.40), dbfs: -30)?.label,
          AutoLabel.snore);
      expect(verdictFromScores(_flat(snore: 0.399), dbfs: -30), isNull);
    });

    test('判定线默认 0.40（实测两组数据在 0.3–0.7 上都成立，取靠严的一头）', () {
      // 改 `YamnetParams.snoreThreshold` 的默认值会让这条红。
      expect(const YamnetParams().snoreThreshold, 0.40);
    });

    test('判出来的结论**不带区间**——模型是按整段给结论的', () {
      // 这是新判定与旧规则最大的形态差别。`durationMs` 一旦非零，详情页就会
      // 画出一对没量过的秒数（旧版的 `event` getter 正是这么漏的）。
      final verdict =
          verdictFromScores(_flat(snore: 0.9, windows: 8), dbfs: -30);
      expect(verdict!.startMs, 0);
      expect(verdict.durationMs, 0);
      expect(verdict.event, isNull, reason: '没有区间就没有事件可指');
    });
  });

  group('判定：疑似人声', () {
    test('鼾声没过线、人声过了线，就是疑似人声', () {
      final verdict = verdictFromScores(
        _flat(snore: 0.10, speech: 0.80),
        dbfs: -30,
      );
      expect(verdict?.label, AutoLabel.voice);
    });

    test('人声判定线默认 0.70——比鼾声那条严，因为证据弱得多', () {
      // 改 `YamnetParams.voiceThreshold` 的默认值会让这条红。
      expect(const YamnetParams().voiceThreshold, 0.70);
      expect(verdictFromScores(_flat(snore: 0.1, speech: 0.699), dbfs: -30),
          isNull);
      expect(
          verdictFromScores(_flat(snore: 0.1, speech: 0.70), dbfs: -30)?.label,
          AutoLabel.voice);
    });

    test('**两条同时过线时听鼾声的**——先后是定的，不随窗口顺序漂', () {
      final verdict =
          verdictFromScores(_flat(snore: 0.9, speech: 0.95), dbfs: -30);
      expect(verdict?.label, AutoLabel.snore,
          reason: '鼾声那一路的证据强得多（他自己的 3 段 0.708–0.850、'
              'ESC-50 36/40，两组负样本 0 误报）；人声那一路最好也只有 80/80');
    });
  });

  group('判不出来就弃权：机器永不拿「杂音」兜底', () {
    test('两条都没过线 → `null`', () {
      expect(verdictFromScores(_flat(snore: 0.30, speech: 0.50), dbfs: -30),
          isNull);
      expect(verdictFromScores(_flat(), dbfs: -30), isNull);
    });

    test('**任何**分数都不会产出 AutoLabel.noise', () {
      // 报「杂音」等于同时断言「不是鼾声」和「不是人声」两个否定结论，而模型给的
      // 是 521 类的排序、不是这两个否定。这条与 2026-10-15 拆掉杂音兜底同源
      // （偏差 #65），换模型也不许把它放回来。
      final rng = math.Random(11);
      for (var i = 0; i < 400; i++) {
        final scores = ClipScores(
          snore: List.generate(5, (_) => rng.nextDouble()),
          speech: List.generate(5, (_) => rng.nextDouble()),
        );
        final verdict = verdictFromScores(scores, dbfs: -30);
        expect(verdict?.label, isNot(AutoLabel.noise));
      }
    });

    test('一个窗口都没有 → 弃权，不是「什么都没有所以是杂音」', () {
      expect(
        verdictFromScores(ClipScores(snore: [], speech: []), dbfs: -30),
        isNull,
      );
    });

    test('数字静音不参与判定，哪怕分数高得离谱', () {
      // 平台静音时录到的是一串零（Android 上真发生过，验证记录 v3.19）。
      // 全零对 YAMNet 是**分布外**输入，它会对一串零说什么没有任何测量——
      // 所以不能让它说话。把 `verdictFromScores` 里那道闸删掉会让这条红。
      expect(
        verdictFromScores(_flat(snore: 0.99, speech: 0.99), dbfs: -160),
        isNull,
      );
      expect(
        verdictFromScores(_flat(snore: 0.99), dbfs: kSilenceDbfs - 0.1),
        isNull,
      );
      expect(
        verdictFromScores(_flat(snore: 0.99), dbfs: kSilenceDbfs)?.label,
        AutoLabel.snore,
        reason: '闸是**低于**才挡：正好 −60 不算静音',
      );
    });
  });

  group('依据串：摆的是测出来的数，不是把握', () {
    test('含赢的类的均分与最高分、窗口数、判定线，以及输的类的均分', () {
      final verdict = verdictFromScores(
        ClipScores(snore: [0.8, 0.9], speech: [0.02, 0.04]),
        dbfs: -30,
      );
      final basis = verdict!.basis;
      expect(basis, contains('YAMNet 鼾声分 0.85'));
      expect(basis, contains('最高 0.90'));
      expect(basis, contains('整段 2 个窗口均分'));
      expect(basis, contains('判定线 0.40'));
      expect(basis, contains('人声分 0.03'));
    });

    test('判人声时，赢的那个类换成「人声」、判定线也跟着换', () {
      final verdict = verdictFromScores(
        ClipScores(snore: [0.01], speech: [0.82]),
        dbfs: -30,
      );
      expect(verdict!.basis, contains('YAMNet 人声分 0.82'));
      expect(verdict.basis, contains('判定线 0.70'));
      expect(verdict.basis, contains('鼾声分 0.01'));
    });

    test('依据串里不出现任何「概率 / 把握 / 置信」字样', () {
      // 没有标注数据就估不出概率，摆一个百分比出来就是把编的数说成测量结果
      // （偏差 #59）。这条与旧规则的同一用例同源，换模型之后一个字没松。
      final basis = verdictFromScores(
        _flat(snore: 0.9, windows: 3),
        dbfs: -30,
      )!
          .basis;
      for (final word in ['概率', '把握', '置信', 'confidence']) {
        expect(basis, isNot(contains(word)));
      }
    });
  });

  group('不变量：结论永远自洽', () {
    test('余量恒在 0–1 之间，位置与时长恒为 0', () {
      final rng = math.Random(3);
      for (var i = 0; i < 200; i++) {
        final scores = ClipScores(
          snore: List.generate(4, (_) => rng.nextDouble()),
          speech: List.generate(4, (_) => rng.nextDouble()),
        );
        final verdict = verdictFromScores(scores, dbfs: -25);
        if (verdict == null) continue;
        expect(verdict.margin, inInclusiveRange(0, 1));
        expect(verdict.margin.isFinite, isTrue);
        expect(verdict.startMs, 0);
        expect(verdict.durationMs, 0);
        expect(verdict.basis, isNotEmpty);
      }
    });

    test('余量是「越过判定线多少」，阈值抬到 1.0 时贴近 0', () {
      final loose = verdictFromScores(_flat(snore: 0.5), dbfs: -30)!;
      final strict = verdictFromScores(
        _flat(snore: 0.5),
        dbfs: -30,
        params: const YamnetParams(snoreThreshold: 0.1),
      )!;
      expect(strict.margin, greaterThan(loose.margin));
    });

    test('阈值是可以整个换掉的——工具靠这个扫线', () {
      const wide = YamnetParams(snoreThreshold: 0.05, voiceThreshold: 0.05);
      expect(verdictFromScores(_flat(snore: 0.06), dbfs: -30)?.label,
          isNot(AutoLabel.snore));
      expect(
          verdictFromScores(_flat(snore: 0.06), dbfs: -30, params: wide)?.label,
          AutoLabel.snore);
    });
  });

  group('落库往返：依据串与判定一起活下来', () {
    test('判定编码再解码之后，依据串与标签都还在', () {
      final verdict = verdictFromScores(
        _flat(snore: 0.85, windows: 6),
        dbfs: -30,
      )!;
      final decoded = AutoAnalysis.decode(
        AutoAnalysis(
                verdict: verdict, analyzedAtUtc: DateTime.utc(2026, 10, 16))
            .encode(),
      );
      expect(decoded?.verdict?.label, AutoLabel.snore);
      expect(decoded?.verdict?.basis, verdict.basis);
      expect(decoded?.verdict?.durationMs, 0);
      // 旧记录带区间、新记录不带，两者都要能读回来——这是 `AutoVerdict.event`
      // 那个守卫要挡的：`durationMs == 0` 不许画成「第 0.0–0.0 秒」。
      expect(decoded?.verdict?.event, isNull);
    });
  });
}
