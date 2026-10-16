// 夜间录音片段的**实测声学特征**，以及机器判定的落地格式。
//
// 这个文件故意不 import `dart:io`、不碰任何插件、不碰平台通道：读 WAV、写数据库都要
// 真机或集成测试才能验证，而「一段声音有哪些可测量的特征」必须靠单测钉死。
//
// ## 判定已经不在这个文件里了
//
// **2026-10-16 起，机器判定由 YAMNet 给出，规则在 [`clip_yamnet.dart`](clip_yamnet.dart)。**
// 这里原来那套写死的声学阈值（低频占比 + 谱质心 + 周期性 + 最强单音 + 滑动窗找事件）
// **已被证伪、已删除**：在使用方 47 段真实录音上覆盖 2% / 准确 0% / 鼾声召回 0%，
// 把时长门槛从 2500 ms 一路扫到 500 ms 也救不回来——不是阈值没调对，是那组特征
// 不承载「鼾声 vs 划桌子 + 拍手」这个区分。逐条读数见
// `docs/superpowers/specs/2026-10-14-night-clip-auto-analysis-design.md` §五·补。
//
// **[measureClip] / [AudioFeatures] 留着**，而且不是死代码：它们是**真测量**，
// `tool/analyse_clips.dart` 仍然把它们逐段打出来给人肉眼核对。**但它们已经不参与判定了**
// ——摆一份「实测特征」在「自动判断依据」旁边会让人以为机器是照这些数判的，而模型
// 一个都不用。所以界面上那行依据摆的是模型分，见 [AutoVerdict.basis]。
//
// ## 三件刻意不做的事，别当遗漏
//
//  * **不做语音转写**：`SoundClips.transcript` 永远不由这里写。
//  * **不声称「梦话」**：那要分清梦话、清醒说话与电视声，所以只说 [AutoLabel.voice]
//    （疑似人声）。换了模型也不改这一条——YAMNet 的 `Speech` 类同样分不出这几个。
//  * **不给概率**：[AutoVerdict.margin] 是「越过判定线多少」，**不是**「有多大概率
//    是鼾声」。没有标注数据就估不出概率，编一个百分比出来正是本仓最要挡的那种假话。

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// 一个片段的标注。
///
/// **前两个是机器能给的，第三个不是。** [AutoLabel.snore] 与 [AutoLabel.voice] 是
/// 机器的**正向证据**：测到了持续的低频周期性 / 持续的语音带周期性。
///
/// **[AutoLabel.noise] 只能由人来给。** 2026-10-15 之前机器拿它兜底——「扫过整段，
/// 没找到够格的鼾声或人声事件」就报杂音。**这条兜底已拆掉，而且换了模型也没有回来**：
/// 说「杂音」等于同时说了「不是鼾声」和「不是人声」两个否定结论，而 YAMNet 给出的是
/// 521 类的排序、不是这两个否定——某一段在 `Snoring` 上没到判定线，与「它不是鼾声」
/// 是两回事。现在没过判定线一律弃权，界面上留「待标注」。
///
/// 这个值仍然必须留着两处用它：**人标的取值**，以及**旧记录里已经写下的
/// `auto_analysis`**——删掉它等于让那些记录读不回来。
enum AutoLabel {
  snore('snore', '疑似打鼾'),
  voice('voice', '疑似人声'),
  noise('noise', '杂音');

  const AutoLabel(this.id, this.label);

  /// 落库用的稳定标识；改它等于让已经写进库的旧数据读不回来。
  final String id;

  /// 界面上的说法。鼾声与人声**必须带「疑似」**：机器没听过，只是测出来像。
  final String label;

  static AutoLabel? fromId(String? id) {
    if (id == null) return null;
    for (final value in AutoLabel.values) {
      if (value.id == id) return value;
    }
    return null;
  }
}

/// 一段片段的实测声学特征。每一个数都是**测出来的**，不是推断出来的。
class AudioFeatures {
  const AudioFeatures({
    required this.dbfs,
    required this.lowRatio,
    required this.speechRatio,
    required this.highRatio,
    required this.spectralCentroid,
    required this.spectralFlatness,
    required this.pitchStrength,
    required this.spectralPeakShare,
    required this.zeroCrossingRate,
    required this.breathBandRatio,
    required this.syllableBandRatio,
  });

  /// 整段的 RMS 响度（dBFS）。
  final double dbfs;

  /// 20–300 Hz 的能量占比。鼾声的能量集中在这一带。
  final double lowRatio;

  /// 300–3400 Hz 的能量占比。人声的基频与共振峰在这一带。
  final double speechRatio;

  /// 3400 Hz 以上的能量占比。越高越像摩擦声、沙沙声。
  final double highRatio;

  /// 谱质心（Hz）。越低越「闷」，越高越「亮」。
  final double spectralCentroid;

  /// 谱平坦度：噪声趋近 1，纯谐音趋近 0。
  ///
  /// **它已经不参与判定了**（曾经是鼾声规则的一条，阈值 0.05）。撤掉的理由是实测：
  /// 它和 [pitchStrength] 量的是同一件事（「有调 vs 无调」），而后者更利——真机上
  /// 好几段真实音频的平坦度落在 0.05–0.08，恰好骑在旧阈值上，把判据变成了掷硬币。
  /// 仍然测、仍然显示，是因为它对读依据的人有用；但它不再是门槛。
  final double spectralFlatness;

  /// **周期性强度（0–1）**：40–320 Hz 上归一化自相关的峰值。
  ///
  /// 这是替掉旧「音节带包络能量」那条判据的量。旧判据被实测证伪了：它对**完全没有
  /// 调制的白噪声**也给出 16%–30%，而阈值是 25%——等于掷硬币。周期性的道理直白得多：
  /// 鼾声是软腭周期性振动发出的，人声（浊音）是声带周期性振动发出的，两者都**真的
  /// 周期**；而摩擦声、床品窸窣、拖动家具都不是。真机上它把 12 段干净地分成了两簇
  /// （0.06–0.40 与 0.51–0.88），而旧判据什么也没分开。
  ///
  /// 搜索下限取 40 Hz 而不是 60 Hz：有些鼾声基频很低，下限太高会把它们误判成非周期。
  final double pitchStrength;

  /// **最强谱峰占总能量的比例（0–1）**。纯音趋近 1，噪声趋近 0。
  ///
  /// 它与 [pitchStrength] 是两件事，缺一不可：周期性问的是「有没有重复」，
  /// 这一条问的是「**是不是一个乐音**」。真实样本上两者确实分得开——
  /// 使用方哼歌那一段是**近乎纯音**（单一谱峰占 43.3%，峰间距只有 12 Hz 的颤音），
  /// 而拖椅子 9.8%、床品 8.0%、翻身吱呀 3.0%、假装鼾声 2.5%。
  ///
  /// **为什么不用 [spectralFlatness] 代替它**：平坦度是**全部** bin 的几何均/算术均，
  /// 被大量近零 bin 主导，在真实音频上老是落在 0.00–0.02 这个分不开的区间里
  /// （实测：哼歌 0.00、拖椅子 0.02）。最大峰占比是一个尖得多的量。
  final double spectralPeakShare;

  /// 过零率（0–1）。宽带噪声高，低频谐音低。
  final double zeroCrossingRate;

  /// RMS 包络在 0.15–0.6 Hz 的能量占比——呼吸周期的量级。
  ///
  /// **不参与判定。2026-10-15 试过让它参与，当晚就拆了——它判不出鼾声。**
  ///
  /// 想法本来是顺理成章的：鼾声的定义就是「跟着呼吸走」，而那是时间结构、不是频谱。
  /// 触发它的是使用方新录的一段 21.6 秒录音：**四条频谱判据一条都不过**，可它的
  /// 包络是清清楚楚的一响一停（主周期 2.60 秒），这条量出来 43%，是当时 15 段里最高的。
  ///
  /// **但它不特异，因为「按呼吸的节律起伏」这个描述同时成立的对象太多。** 当晚在设备上
  /// 实跑一次 2 分钟会话，三段全部误报，判据都在这一条上：
  ///
  /// | 实际是什么 | 呼吸带 | 机器判成 |
  /// | --- | --- | --- |
  /// | **风扇** | **45%** | 疑似打鼾 |
  /// | **唱歌 + 说话** | 31% | 疑似打鼾 |
  /// | 风扇 + 敲桌子 | 14% | 杂音（对） |
  ///
  /// 两条各有各的道理，合起来是致命的：
  ///  * **风扇**那种「持续 + 低频 + 缓慢起伏」的环境声，能量照样落进这个带——
  ///    实测 45%，**比那段被当作鼾声的录音（43%）还高**。任何夹在两者之间的阈值都不存在。
  ///  * **任何由会呼吸的人发出的声音都有呼吸节律**——说话、唱歌都有换气停顿。
  ///
  /// 试过用「包络的节律性」（把包络当信号看它有没有一个清晰的峰）去分开，**分不开**：
  /// 被当作鼾声的那段 0.47，风扇 0.37，而翻身杂音是 0.69。调制深度、峰值频率同样分不开。
  ///
  /// **所以它退回到「只测不判」。** 留着这个数是因为它对读依据的人仍有信息量，
  /// 也因为**将来若有更好的判据，得从这条被证伪的记录上接着走，而不是从头再想一遍**。
  final double breathBandRatio;

  /// RMS 包络在 2–8 Hz 的能量占比——音节速率的量级。
  ///
  /// **不参与判定**，理由见 [pitchStrength]（实测处在随机水平）。保留同
  /// [spectralFlatness]。
  final double syllableBandRatio;

  /// 把四个特征拼成一行，给**人**读的一串实测数。
  ///
  /// **它不再是判定依据**——判定由 YAMNet 给出，界面上那行依据摆的是模型分
  /// （[AutoVerdict.basis]）。这一串只出现在 `tool/analyse_clips.dart` 的表里，
  /// 用途是让人拿它逐段核对声学特征本身对不对。
  String get basis {
    String pct(double v) => '${(v * 100).round()}%';
    return '低频能量 ${pct(lowRatio)} · 谱质心 ${spectralCentroid.round()} Hz '
        '· 周期性 ${pitchStrength.toStringAsFixed(2)} '
        '· 最强单音占比 ${pct(spectralPeakShare)}';
  }
}

/// 机器在片段里找到（或否定）的一个事件。
///
/// **新的判定不再产出它。** YAMNet 给的是**整段**的分数，拿它画一个「第几秒到第几秒」
/// 就是把没量过的东西画出来（片级标签训出来的模型定位能力差是公认的，见
/// `2026-10-16-snore-detection-approaches-design.md` §4.3）。
///
/// 这个类留着只有一个理由：**旧记录里存着区间**。2026-10-16 之前那套判定确实产出过
/// 起止位置，`AutoAnalysis.decode` 会把它们读回来，界面也还在显示——删掉这个类等于
/// 让那些记录读不回来，同 [AutoLabel.noise] 是同一条理由。
///
/// [startMs] / [durationMs] 是**实测的**：它们就是那串连续同向窗口的实际跨度。
class ClipEvent {
  const ClipEvent({
    required this.label,
    required this.startMs,
    required this.durationMs,
    required this.margin,
  });

  final AutoLabel label;

  /// 事件相对片段起点的位置（毫秒）。
  final int startMs;

  /// 事件持续时长（毫秒）。**这个数就是判定的门槛之一**。
  final int durationMs;

  /// 组成这个事件的全部窗口里最高的那个余量。
  final double margin;

  /// 「第 0.3–6.6 秒」。界面用它说明机器**在哪一段**上判的。
  ///
  /// 写成区间而不是「持续 N 秒」是有意的：鼾声是一串，中间本来就有停顿，而
  /// [ClipAnalysisParams.mergeGapMs] 会把小于它的停顿跨过去。所以这一对数说的是
  /// **这一段的起止**，不是「从头到尾一秒没停」——用「持续」会把跨过去的那几秒
  /// 说成也在响，那是不该说的话。
  String get spanLabel {
    String s(int ms) => (ms / 1000).toStringAsFixed(1);
    return '第 ${s(startMs)}–${s(startMs + durationMs)} 秒';
  }
}

/// 机器对一段片段的判断结果。
class AutoVerdict {
  const AutoVerdict({
    required this.label,
    required this.margin,
    required this.basis,
    this.startMs = 0,
    this.durationMs = 0,
  });

  final AutoLabel label;

  /// **越过阈值的余量，不是概率。** 只在 0–1 之间用于排序与诊断，**界面不显示它**。
  /// 详见文件头最后一条。
  final double margin;

  /// 判定所依据的**实测数**——现在是 YAMNet 的分与判定线，由
  /// `clip_yamnet.dart` 的 `verdictFromScores` 拼出来。
  ///
  /// 它不再是 [AudioFeatures.basis] 那一组声学特征：模型一个都不用那些数，
  /// 摆在「自动判断依据」里就是让人以为机器是照它们判的。
  final String basis;

  /// 判出来的那个事件在片段里的位置与时长（毫秒）。见 [ClipEvent]。
  ///
  /// **新判定恒为 0**（按整段给结论，不定位）。有值的一定是 2026-10-16 之前的旧记录。
  final int startMs;
  final int durationMs;

  /// 判出来的事件。
  ///
  /// 三种情形返回 `null`：**没有时长**（新判定的常态，见 [ClipEvent]）、
  /// [AutoLabel.noise]（它指的是「扫过一遍没找到事件」，不是某个段落）。
  ///
  /// 守卫写在这里而不是界面里：「这一段没有区间」是关于结论本身的事实，
  /// 不该由每个读它的地方各自判断一遍——漏掉一处就会画出「第 0.0–0.0 秒」。
  ClipEvent? get event {
    if (label == AutoLabel.noise) return null;
    if (durationMs <= 0) return null;
    return ClipEvent(
      label: label,
      startMs: startMs,
      durationMs: durationMs,
      margin: margin,
    );
  }
}

/// 一次机器分析的落地记录，存进 `sound_clips.auto_analysis` 那一列。
///
/// **[verdict] 为 `null` 是有意义的状态，不是缺失**：它表示机器看过这一段但没把握
/// （弃权）。整列为 `null`（这一列没有值）才是「从没分析过」。两者必须分得开——
/// 同 `labeledAtUtc` 存在的理由。
class AutoAnalysis {
  const AutoAnalysis({required this.verdict, required this.analyzedAtUtc});

  /// `null` = 弃权。见类文档。
  final AutoVerdict? verdict;

  /// 这次分析发生的时刻。重跑之后它会被刷新。
  final DateTime analyzedAtUtc;

  String encode() {
    return jsonEncode({
      'kind': verdict?.label.id,
      'margin': verdict?.margin,
      'basis': verdict?.basis,
      'startMs': verdict?.startMs,
      'durationMs': verdict?.durationMs,
      'atUtc': analyzedAtUtc.toUtc().toIso8601String(),
    });
  }

  /// 解析一列的原始文本。**坏数据返回 `null`（当作没有记录），不抛异常**——
  /// 与 `sleep_repository.dart` 的 `_decodeEnvelope` 同一条口径：宁可如实说读不到，
  /// 也不要猜一个形状出来。
  ///
  /// `startMs` / `durationMs` 是后加的键，旧记录没有，读出来是 0——**不当作坏数据**，
  /// 因为「没有这两个数」正是旧版本的真实情况，不是损坏。
  static AutoAnalysis? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final Object? parsed;
    try {
      parsed = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (parsed is! Map) return null;

    final atUtc = DateTime.tryParse('${parsed['atUtc']}');
    if (atUtc == null) return null;

    final label = AutoLabel.fromId(parsed['kind'] as String?);
    // kind 有值却没解析出来（拼错的字符串、或将来撤掉的标签）——那是一条我们不认识
    // 的记录，宁可当作没有，也不要把它当成「弃权」展示出去。
    if (parsed['kind'] != null && label == null) return null;
    if (label == null) {
      return AutoAnalysis(verdict: null, analyzedAtUtc: atUtc.toUtc());
    }

    final margin = parsed['margin'];
    final basis = parsed['basis'];
    final startMs = parsed['startMs'];
    final durationMs = parsed['durationMs'];
    return AutoAnalysis(
      verdict: AutoVerdict(
        label: label,
        margin: margin is num ? margin.toDouble().clamp(0.0, 1.0) : 0,
        basis: basis is String ? basis : '',
        startMs: startMs is num ? math.max(0, startMs.round()) : 0,
        durationMs: durationMs is num ? math.max(0, durationMs.round()) : 0,
      ),
      analyzedAtUtc: atUtc.toUtc(),
    );
  }
}

/// 特征测量的参数。**只剩「怎么量」，没有「怎么判」了。**
///
/// 判定那些阈值（低频占比 / 谱质心 / 周期性 / 最强单音、时长门槛、余量门槛）连同
/// 它们的理由一起删掉了，去向见文件头：那套规则已被证伪，换成 `clip_yamnet.dart`
/// 里的模型分判定。**理由没有丢**——它们逐条写在
/// `docs/superpowers/specs/2026-10-14-night-clip-auto-analysis-design.md` §三 与
/// §七，以及 git 历史里。将来若要回到声学特征这条路，从那里接着走，不要从头再想。
class ClipAnalysisParams {
  const ClipAnalysisParams({
    this.frameLength = 1024,
    this.hopLength = 512,
    this.lowBandBottom = 20,
    this.lowBandTop = 300,
    this.speechBandTop = 3400,
    this.pitchBandBottom = 40,
    this.pitchBandTop = 320,
  })  : assert(frameLength > 0),
        assert(hopLength > 0),
        assert(lowBandBottom >= 0),
        assert(lowBandTop > lowBandBottom),
        assert(speechBandTop > lowBandTop),
        assert(pitchBandTop > pitchBandBottom);

  /// 一帧的采样点数（FFT 长度），必须是 2 的幂。
  final int frameLength;

  /// 帧间步进。小于 [frameLength] 才有重叠，特征才稳。
  final int hopLength;

  /// 低频带的左边界（Hz）。
  ///
  /// **不是 0，是刻意的。** 麦克风有直流偏置是常事，而直流与次声不是「声音」——把它
  /// 算进低频带会让任何一段录音都显得低频很足。实测过：同一段片段，把直流算进来时
  /// 低频占比 0.62，排除之后是 0.36，足以让一段翻身摩擦看起来低频很足。
  final double lowBandBottom;

  /// 低频带的右边界（Hz）。
  final double lowBandTop;

  /// 语音带的右边界（Hz）。再往上到奈奎斯特即高频带。
  final double speechBandTop;

  /// 周期性搜索的下限（Hz）。见 [AudioFeatures.pitchStrength]。
  final double pitchBandBottom;

  /// 周期性搜索的上限（Hz）。
  final double pitchBandTop;
}

/// 包络分析的帧率（Hz）。50 意味着每 20 ms 一格。
const int kEnvelopeFrameRate = 50;

/// 跑一遍全部特征。样本为 `[−1, 1]` 的归一化浮点。
///
/// 比一帧还短的输入会补零到一帧再算——不是因为它有内容，而是为了让调用方不必
/// 为「1 秒的片段」和「0.01 秒的片段」写两条路径。
AudioFeatures measureClip(
  Float64List samples, {
  required int sampleRate,
  ClipAnalysisParams params = const ClipAnalysisParams(),
}) {
  assert(sampleRate > 0, '采样率必须为正');
  if (samples.isEmpty) {
    return const AudioFeatures(
      dbfs: -160,
      lowRatio: 0,
      speechRatio: 0,
      highRatio: 0,
      spectralCentroid: 0,
      spectralFlatness: 0,
      pitchStrength: 0,
      spectralPeakShare: 0,
      zeroCrossingRate: 0,
      breathBandRatio: 0,
      syllableBandRatio: 0,
    );
  }

  final stats = _spectralStats(samples, sampleRate, params);
  final envelope = _envelopeBands(samples, sampleRate);

  return AudioFeatures(
    dbfs: rmsDbfs(samples),
    lowRatio: stats.lowRatio,
    speechRatio: stats.speechRatio,
    highRatio: stats.highRatio,
    spectralCentroid: stats.centroid,
    spectralFlatness: stats.flatness,
    pitchStrength: stats.pitchStrength,
    spectralPeakShare: stats.peakShare,
    zeroCrossingRate: _zeroCrossingRate(samples),
    breathBandRatio: envelope.breath,
    syllableBandRatio: envelope.syllable,
  );
}

/// 逐帧统计再取平均的结果。
typedef _SpectralStats = ({
  double lowRatio,
  double speechRatio,
  double highRatio,
  double centroid,
  double flatness,
  double pitchStrength,
  double peakShare,
});

/// 逐帧算频带占比 / 质心 / 平坦度 / 周期性，**再对帧取平均**。
///
/// **口径是「先算每帧的比值，再平均帧」，不是「先平均频谱，再算比值」。** 两者对
/// 大部分片段给出接近的数，但混着内容的片段会差很远：后者被**响的**那些帧主导，
/// 一段安静的鼾声里插进半秒翻身摩擦，整段的低频占比就会被那半秒拽下去。
///
/// 只统计**有能量**的帧：全零帧（平台静音、或片段开头的空缓冲）没有频谱特征可言，
/// 让它们参与平均等于把每一段的特征都往 0 拽——那不是测量，是稀释。
_SpectralStats _spectralStats(
  Float64List samples,
  int sampleRate,
  ClipAnalysisParams params,
) {
  const empty = (
    lowRatio: 0.0,
    speechRatio: 0.0,
    highRatio: 0.0,
    centroid: 0.0,
    flatness: 0.0,
    pitchStrength: 0.0,
    peakShare: 0.0,
  );

  final n = params.frameLength;
  final bins = n ~/ 2 + 1;
  final window = Float64List(n);
  for (var i = 0; i < n; i++) {
    window[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / n);
  }
  final twiddle = _twiddles(n);
  final re = Float64List(n);
  final im = Float64List(n);
  // 周期性用「功率谱的逆变换」算自相关（维纳–辛钦），复用同一个 _fft。
  final powerFull = Float64List(n);
  final imScratch = Float64List(n);

  // 周期性的搜索范围换算成延迟（采样点数）。
  final kMin = (sampleRate / params.pitchBandTop).round();
  final kMax = (sampleRate / params.pitchBandBottom).round();
  final subAudibleBin = (params.lowBandBottom * n / sampleRate).round();

  var frames = 0;
  var lowSum = 0.0;
  var speechSum = 0.0;
  var highSum = 0.0;
  var centroidSum = 0.0;
  var flatnessSum = 0.0;
  var pitchSum = 0.0;
  var peakSum = 0.0;

  // 比一帧还短的输入补零算一次——不是因为它有内容，而是为了不让调用方为超短片段
  // 另写一条路径。
  final shortInput = samples.length < n;
  final starts = <int>[];
  if (shortInput) {
    starts.add(0);
  } else {
    for (var s = 0; s + n <= samples.length; s += params.hopLength) {
      starts.add(s);
    }
  }

  for (final start in starts) {
    // 先去掉这一帧的直流再开窗：有偏置的话 bin 0 会是个尖峰，既污染低频带，
    // 也把谱平坦度那个「几何均 / 算术均」的分母抬起来。见 [ClipAnalysisParams.lowBandBottom]。
    var mean = 0.0;
    for (var i = 0; i < n; i++) {
      final index = start + i;
      if (index < samples.length) mean += samples[index];
    }
    mean /= n;

    for (var i = 0; i < n; i++) {
      final index = start + i;
      re[i] = index < samples.length ? (samples[index] - mean) * window[i] : 0;
      im[i] = 0;
    }
    _fft(re, im, twiddle);

    var total = 0.0;
    var low = 0.0;
    var speech = 0.0;
    var high = 0.0;
    var weighted = 0.0;
    var logSum = 0.0;
    var peak = 0.0;
    for (var i = 0; i < bins; i++) {
      final power = re[i] * re[i] + im[i] * im[i];
      final hz = i * sampleRate / n;
      total += power;
      weighted += power * hz;
      logSum += math.log(power + 1e-20);
      powerFull[i] = power;
      if (i > 0 && i < bins - 1) powerFull[n - i] = power; // 补成共轭对称的全谱
      if (hz < params.lowBandBottom) {
        // 直流与次声：不计入任何频带。它们仍然留在 total 里（那才是真正的总能量），
        // 只是三个占比加起来不再恰好等于 1——这是对的，不该为凑整把它们算成声音。
        continue;
      } else if (power > peak) {
        // 最强峰只在可听带里找：直流与次声不是声音，不该去竞争「最强的那个峰」。
        peak = power;
      }
      if (hz < params.lowBandTop) {
        low += power;
      } else if (hz < params.speechBandTop) {
        speech += power;
      } else {
        high += power;
      }
    }
    // 全零帧（或近乎全零）跳过，理由见函数头。
    if (total <= 1e-18) continue;

    frames++;
    lowSum += low / total;
    speechSum += speech / total;
    highSum += high / total;
    centroidSum += weighted / total;
    // 几何均 / 算术均：噪声趋近 1，谐音趋近 0。
    flatnessSum += (math.exp(logSum / bins) / (total / bins)).clamp(0.0, 1.0);
    pitchSum += _pitchStrength(
      powerFull,
      imScratch,
      twiddle,
      n,
      kMin,
      kMax,
      subAudibleBin,
    );
    peakSum += (peak / total).clamp(0.0, 1.0);
  }

  if (frames == 0) return empty;
  return (
    lowRatio: lowSum / frames,
    speechRatio: speechSum / frames,
    highRatio: highSum / frames,
    centroid: centroidSum / frames,
    flatness: flatnessSum / frames,
    pitchStrength: pitchSum / frames,
    peakShare: peakSum / frames,
  );
}

/// 由**功率谱的逆变换**得到自相关，取搜索范围内归一化峰值——即周期性强度。
///
/// 维纳–辛钦定理：功率谱的逆变换就是自相关。这里已经为每一帧算过功率谱了，所以
/// 代价只是**再一次同样长度的 FFT**，比为周期性单开一套抽稀+自相关的代码省得多。
///
/// [powerFull] **会被就地改写**（变成自相关），调用方每帧必须重新填。
/// [subAudibleBin] 以下的 bin 先清零：直流与次声在自相关里是一个**与延迟无关的常数
/// 偏置**，不清掉的话所有延迟上的值会被一起抬高，周期性就再也分不出来了。
double _pitchStrength(
  Float64List powerFull,
  Float64List imScratch,
  Float64List twiddle,
  int n,
  int kMin,
  int kMax,
  int subAudibleBin,
) {
  for (var i = 0; i < subAudibleBin; i++) {
    powerFull[i] = 0;
    if (i > 0) powerFull[n - i] = 0;
  }
  imScratch.fillRange(0, n, 0);
  _fft(powerFull, imScratch, twiddle);

  final r0 = powerFull[0] / n;
  if (r0 <= 0) return 0;

  var best = 0.0;
  final last = kMax < n ? kMax : n - 1;
  for (var k = kMin; k <= last; k++) {
    final v = powerFull[k] / n / r0;
    if (v > best) best = v;
  }
  return best.clamp(0.0, 1.0);
}

/// 原地 radix-2 迭代 FFT。`re` / `im` 长度必须相等且是 2 的幂。
///
/// 自己写而不是引 `fftea` / `scidart`：这里只需要一个固定长度的实数 FFT，
/// 六十行能单测的代码比一个要长期跟版本的依赖更可控。
/// [twiddles] 是 `n/2` 个旋转因子（`_twiddles(n)` 算出来的），避免逐帧重算三角函数。
void _fft(Float64List re, Float64List im, Float64List twiddles) {
  final n = re.length;
  assert(im.length == n, '实部虚部长度必须一致');

  // 位反转置换。
  for (var i = 1, j = 0; i < n; i++) {
    var bit = n >> 1;
    while (j & bit != 0) {
      j ^= bit;
      bit >>= 1;
    }
    j |= bit;
    if (i < j) {
      final tr = re[i];
      re[i] = re[j];
      re[j] = tr;
      final ti = im[i];
      im[i] = im[j];
      im[j] = ti;
    }
  }

  for (var len = 2; len <= n; len <<= 1) {
    final half = len >> 1;
    // 这一层每跨 half 个 bin 取一次旋转因子，步长是 n / len。
    final step = n ~/ len;
    for (var i = 0; i < n; i += len) {
      for (var k = 0; k < half; k++) {
        final wr = twiddles[k * step];
        final wi = -twiddles[k * step + n ~/ 2];
        final a = i + k;
        final b = a + half;
        final vr = re[b] * wr - im[b] * wi;
        final vi = re[b] * wi + im[b] * wr;
        re[b] = re[a] - vr;
        im[b] = im[a] - vi;
        re[a] += vr;
        im[a] += vi;
      }
    }
  }
}

/// 长度 `n` 的旋转因子表：前 `n/2` 个是余弦，后 `n/2` 个是正弦（同角度）。
///
/// 用一个表装两种函数是为了让 [\_fft] 只收一个参数；这一点点小聪明换来的是一处
/// 约定（正弦在下半段）必须写清楚，否则下标一错就是无声的错答案。
Float64List _twiddles(int n) {
  final half = n ~/ 2;
  final table = Float64List(n);
  for (var i = 0; i < half; i++) {
    final angle = -2 * math.pi * i / n;
    table[i] = math.cos(angle);
    table[half + i] = -math.sin(angle);
  }
  return table;
}

/// RMS 包络在呼吸带与音节带上的能量占比。
///
/// **两个数现在都不参与判定**（理由见 [AudioFeatures.breathBandRatio] /
/// [AudioFeatures.syllableBandRatio]），保留是因为它们仍然是对整段的真实测量，
/// 而且周期性的替代方案 [AudioFeatures.pitchStrength] 走的正是同一条「包络/频谱的
/// 周期性」思路——将来若要再加一条呼吸速率判据，从这里接着走。
({double breath, double syllable}) _envelopeBands(
  Float64List samples,
  int sampleRate,
) {
  final hop = sampleRate ~/ kEnvelopeFrameRate;
  if (hop < 1) return (breath: 0.0, syllable: 0.0);

  final count = samples.length ~/ hop;
  if (count < 4) return (breath: 0.0, syllable: 0.0);

  // 每 hop 个采样的 RMS 就是一格包络。
  final envelope = Float64List(count);
  var mean = 0.0;
  for (var i = 0; i < count; i++) {
    var sum = 0.0;
    final base = i * hop;
    for (var j = 0; j < hop; j++) {
      final v = samples[base + j];
      sum += v * v;
    }
    envelope[i] = math.sqrt(sum / hop);
    mean += envelope[i];
  }
  mean /= count;
  for (var i = 0; i < count; i++) {
    envelope[i] -= mean; // 去掉直流，否则低频端全是它的泄漏
  }

  // 补零到 2 的幂再做 FFT（同一份 _fft，不再写第二套变换）。
  var n = 1;
  while (n < count) {
    n <<= 1;
  }
  final re = Float64List(n);
  final im = Float64List(n);
  final window = Float64List(count);
  for (var i = 0; i < count; i++) {
    window[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / count);
    re[i] = envelope[i] * window[i];
  }
  _fft(re, im, _twiddles(n));

  var breath = 0.0;
  var syllable = 0.0;
  var total = 0.0;
  final bins = n ~/ 2 + 1;
  for (var i = 1; i < bins; i++) {
    final hz = i * kEnvelopeFrameRate / n;
    final power = re[i] * re[i] + im[i] * im[i];
    total += power;
    if (hz >= 0.15 && hz <= 0.6) breath += power;
    if (hz >= 2 && hz <= 8) syllable += power;
  }
  if (total <= 0) return (breath: 0.0, syllable: 0.0);
  return (breath: breath / total, syllable: syllable / total);
}

double _zeroCrossingRate(Float64List samples) {
  if (samples.length < 2) return 0;
  var crossings = 0;
  for (var i = 1; i < samples.length; i++) {
    final a = samples[i - 1];
    final b = samples[i];
    // 严格异号才算过零；0 不计，避免静音段被算成高频。
    if ((a < 0 && b > 0) || (a > 0 && b < 0)) crossings++;
  }
  return crossings / (samples.length - 1);
}

/// 整段的 RMS 响度（dBFS）。空输入与全零返 −160。
///
/// 单独曝出来是因为判定那一边要用它做一道闸：数字静音不能拿到任何标签
/// ——见 `clip_yamnet.dart` 的 `kSilenceDbfs`。而它比 `measureClip` 便宜得多：
/// 后者要跑一遍 FFT，而这一条只是一遍求和。
double rmsDbfs(Float64List samples) {
  if (samples.isEmpty) return -160;
  var sum = 0.0;
  for (final v in samples) {
    sum += v * v;
  }
  final rms = math.sqrt(sum / samples.length);
  if (rms <= 0) return -160;
  return 20 * (math.log(rms) / math.ln10);
}
