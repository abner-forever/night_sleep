// 夜间录音片段的声学特征与启发式判定——整条分析链路里唯一能被完整单测的纯函数层。
//
// 这个文件故意不 import `dart:io`、不碰任何插件、不碰平台通道：读 WAV、写数据库都要
// 真机或集成测试才能验证，而「一段声音有哪些可测量的特征、够不够格下一个判断」必须
// 全部靠单测钉死。把判定规则挪出这个文件，整条链路就再没有可被完整验证的部分了。
//
// **这里没有模型，也不声称有。** 输出全部来自**实测特征**加一组写死在
// [ClipAnalysisParams] 里的阈值。
//
// ## 判定是「找事件」，不是「给整段平均打一个分」
//
// 早先的版本把整段几十秒平均成一个特征向量再判一次，两个后果都在真机上撞到了：
//
//  * **一段里混着鼾声与杂音时，平均完谁都不像。** 实测：一段 11.8 秒的录音，
//    前 3.5 秒是教科书式的鼾声（低频 66–84%、质心 331–502 Hz、平坦度 0.00），
//    后 8 秒是别的声音；整段平均出来是「低频 50%、质心 704 Hz」，两条规则都不满足，
//    于是弃权——**明明有 3.5 秒的鼾声，机器却说判不了**。
//  * **时长完全没被用上。** 实测：一段 1.1 秒的拖椅子声，低频 75%、质心 350 Hz、
//    平坦度 0.02，是全部样本里最像鼾声的一段，机器给了最高余量。它错在只有 1.1 秒
//    ——**鼾声不可能只有一秒**，而整段平均的模型里根本没有「时长」这个概念。
//
// 所以现在改成：滑动窗逐窗判，把连续同向的窗口并成**事件**，只有持续够长的事件才算数。
// 这同时解决了上面两条，而且是同一个改动的两面：**一段混音里只有真正持续的那部分
// 才配得上一个标签。**
//
// 四件刻意不做的事，别当遗漏：
//  * **不做语音转写**：`SoundClips.transcript` 永远不由这里写。
//  * **不声称「梦话」**：那要分清梦话、清醒说话与电视声，光靠声学特征做不到，
//    所以只说 [AutoLabel.voice]（疑似人声）。
//  * **不给概率**：[AutoVerdict.margin] 是「越过阈值多少」，**不是**「有多大概率
//    是鼾声」。没有标注数据就估不出概率，编一个百分比出来正是本仓最要挡的那种假话。
//  * **判不出来就弃权，不拿「杂音」兜底**：见 [AutoLabel.noise] 的文档。

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// 一个片段的标注。
///
/// **前两个是机器能给的，第三个不是。** [AutoLabel.snore] 与 [AutoLabel.voice] 是
/// 机器的**正向证据**：测到了持续的低频周期性 / 持续的语音带周期性。
///
/// **[AutoLabel.noise] 只能由人来给。** 2026-10-15 之前机器拿它兜底——「按窗口扫过
/// 整段，没找到够格的鼾声或人声事件」就报杂音。**这条兜底已拆掉**，因为它的前提
/// 不成立：说「杂音」等于同时说了「不是鼾声」和「不是人声」两个否定结论，而机器
/// **根本认不出鼾声**（在 19 段已标注真机片段上召回 0%，见 `docs/verification-log.md`），
/// 它没有任何资格下这个否定结论。现在扫完没找到事件一律弃权，界面上留「待标注」。
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

  /// 人在界面上能核对的依据串。**显示实测数，不显示任何「把握」**。
  ///
  /// 三条判据一条一个数，顺序与 [ClipAnalysisParams] 里鼾声规则的顺序一致——
  /// 读者拿这三个数就能自己复核机器为什么这么判。
  String get basis {
    String pct(double v) => '${(v * 100).round()}%';
    return '低频能量 ${pct(lowRatio)} · 谱质心 ${spectralCentroid.round()} Hz '
        '· 周期性 ${pitchStrength.toStringAsFixed(2)} '
        '· 最强单音占比 ${pct(spectralPeakShare)}';
  }
}

/// 机器在片段里找到（或否定）的一个事件。
///
/// [startMs] / [durationMs] 是**实测的**：它们就是那串连续同向窗口的实际跨度。
/// 旧版本没有这两个数，于是「1.1 秒的拖椅子声」和「10 秒的鼾声」在结果里长得一模一样。
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

  /// 判定所依据的实测特征，直接来自 [AudioFeatures.basis]。
  final String basis;

  /// 判出来的那个事件在片段里的位置与时长（毫秒）。见 [ClipEvent]。
  final int startMs;
  final int durationMs;

  /// 判出来的事件。
  ///
  /// [AutoLabel.noise] 没有事件可给——它指的是「扫过一遍没找到事件」，不是某个段落。
  /// 现在的判定路径**永远不会产出** noise（见 [AutoLabel] 的文档），但旧记录里存着，
  /// [AutoAnalysis.decode] 会把它们读回来，所以这一支仍然要留着。
  ClipEvent? get event => label == AutoLabel.noise
      ? null
      : ClipEvent(
          label: label,
          startMs: startMs,
          durationMs: durationMs,
          margin: margin,
        );
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

/// 判定参数。**全部是拍的，必须在真实样本上验过再定稿**。
///
/// 现状（2026-10-15）：这组值在**使用方手机上 12 段真实录音**上跑过，但**没有定稿**
/// ——那 12 段的标注自相矛盾（见 `docs/verification-log.md` 本轮条目），拿它标定等于
/// 往错的答案上拟合。**未验证项原样留在验证日志里。**
class ClipAnalysisParams {
  const ClipAnalysisParams({
    this.frameLength = 1024,
    this.hopLength = 512,
    this.lowBandBottom = 20,
    this.lowBandTop = 300,
    this.speechBandTop = 3400,
    this.pitchBandBottom = 40,
    this.pitchBandTop = 320,
    this.windowMs = 1200,
    this.windowHopMs = 300,
    this.mergeGapMs = 1500,
    this.minEventMs = 2500,
    this.snoreLowRatio = 0.45,
    this.snoreCentroid = 800,
    this.snorePitchStrength = 0.50,
    this.snoreMaxPeakShare = 0.30,
    this.voiceSpeechRatio = 0.50,
    this.voiceCentroid = 700,
    this.voicePitchStrength = 0.50,
    this.voiceLowRatioMax = 0.45,
    this.noiseMinDbfs = -60,
    this.minMargin = 0.20,
  })  : assert(frameLength > 0),
        assert(hopLength > 0),
        assert(lowBandBottom >= 0),
        assert(lowBandTop > lowBandBottom),
        assert(speechBandTop > lowBandTop),
        assert(pitchBandTop > pitchBandBottom),
        assert(windowMs > 0),
        assert(windowHopMs > 0),
        assert(mergeGapMs >= 0),
        assert(minEventMs > 0);

  /// 一帧的采样点数（FFT 长度），必须是 2 的幂。
  final int frameLength;

  /// 帧间步进。小于 [frameLength] 才有重叠，特征才稳。
  final int hopLength;

  /// 低频带的左边界（Hz）。
  ///
  /// **不是 0，是刻意的。** 麦克风有直流偏置是常事，而直流与次声不是「声音」——把它
  /// 算进低频带会让任何一段录音都显得低频很足。实测过：同一段片段，把直流算进来时
  /// 低频占比 0.62，排除之后是 0.36，足以让一段翻身摩擦被误判成鼾声。
  final double lowBandBottom;

  /// 低频带的右边界（Hz）。
  final double lowBandTop;

  /// 语音带的右边界（Hz）。再往上到奈奎斯特即高频带。
  final double speechBandTop;

  /// 周期性搜索的下限（Hz）。见 [AudioFeatures.pitchStrength]。
  final double pitchBandBottom;

  /// 周期性搜索的上限（Hz）。
  final double pitchBandTop;

  /// 滑动窗长度（毫秒）。判定在这个尺度上进行，不再对整段求平均。
  final int windowMs;

  /// 窗口步进（毫秒）。小于 [windowMs] 才有重叠，事件的起止才定得准。
  final int windowHopMs;

  /// 相邻两个同向事件相隔不超过它，就并成一个。
  ///
  /// **这是为「鼾声是一串」准备的**：一次吸气一两秒，两次之间本来就有停顿。不合并的话
  /// 每一段单独的鼾声都够不着 [minEventMs]，整夜会一条都判不出来。
  final int mergeGapMs;

  /// 事件要成立所需的最短持续时长（毫秒）。
  ///
  /// **这是本文件里最重要的一条阈值**，也是使用方直接指出来的：实测那段误报是
  /// 1.1 秒的拖椅子声，频率上像极了鼾声，机器给了全部样本里最高的余量——它唯一的
  /// 破绽就是**太短**。鼾声是一次吸气，不可能只有一秒；把它定在 2.5 秒，
  /// 1.1 秒的瞬态再怎么像也拿不到标签。
  final int minEventMs;

  /// 打鼾：低频占比不低于它。
  final double snoreLowRatio;

  /// 打鼾：谱质心必须**低于**它。
  final double snoreCentroid;

  /// 打鼾：周期性强度必须**不低于**它。
  ///
  /// 取 0.50 而不是 0.45，是为了**留出余量**而不是为了那 5 个百分点：真机上那段误报
  /// 的拖椅子声量出来是 0.44，0.45 只比它高 0.01——那样这条判据随时会因为一点点
  /// 录音差异而失守。0.50 落在实测两簇（≤0.44 与 ≥0.63）的中间空档里。
  final double snorePitchStrength;

  /// 打鼾：最强谱峰占比必须**低于**它——**鼾声不是乐音**。
  ///
  /// 这条是使用方那句「我前面一段在哼歌」逼出来的。哼歌与鼾声在「低频 + 周期」上
  /// 几乎无法区分（哼歌也是准周期的低频浊音），实测那段哼歌因此被判成疑似打鼾。
  /// 分开两者的是**有调性**：哼歌是乐音（单一音高，实测最强峰占 43.3%、峰间距只有
  /// 12 Hz 的颤音），鼾声是软腭振动发出的**粗糙**声，能量摊在众多谐波与谐波间噪声上
  /// （实测拖椅子 9.8%、床品 8.0%、翻身吱呀 3.0%、假装鼾声 2.5%）。
  ///
  /// 取 0.30 是**在两簇之间的空档里取中**：实测哼歌 37.2% / 44.3% / 48.9%，
  /// 其余全部 ≤24.9%。0.30 离两边各约 1.2 倍。
  ///
  /// **仍然不知道真实鼾声落在这条线的哪一侧**——见规格 §七 未验证。这是本组阈值里
  /// 唯一一条**完全没有正样本**的判据，它的依据是「鼾声不是乐音」这条声学常识，
  /// 不是任何一段被确认过的鼾声。
  final double snoreMaxPeakShare;

  /// 疑似人声：语音带占比不低于它。
  final double voiceSpeechRatio;

  /// 疑似人声：谱质心必须**高于**它（人声不会像鼾声那么闷）。
  final double voiceCentroid;

  /// 疑似人声：周期性强度必须**不低于**它。取值理由同 [snorePitchStrength]。
  final double voicePitchStrength;

  /// 疑似人声：低频占比必须**低于**它——否则同一段东西会被两条规则同时认领。
  final double voiceLowRatioMax;

  /// 低于这个响度就不下任何结论（dBFS）。
  ///
  /// **数字静音不是「杂音」，也不是任何别的东西。** 平台静音时录到的是一串零，给它
  /// 安一个标签等于把「什么都没录到」说成一个判断。
  ///
  /// 这道闸**在三条判定通路的更上游**，所以它挡的不只是「杂音」：极轻的抖动噪声上
  /// 算出来的谱特征本来就是垃圾，任何一条规则都可能被它蒙对。样本全零时
  /// [AudioFeatures.dbfs] 是 −160，天然被挡在外面。
  final double noiseMinDbfs;

  /// 自动标注的**最低余量**，低于它一律弃权。
  ///
  /// 这是「有把握才自动写」这句承诺在代码里的落点。三条阈值**擦边**满足的片段，
  /// 特征上确实像，但擦边本身就说明它离另一类不远——那种片段该留给用户听，
  /// 而不是让机器抢答。余量是相对量（超出阈值的比例），所以它不随片段的绝对响度漂移。
  final double minMargin;
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
    dbfs: _dbfs(samples),
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

/// 一个窗口给出的判断（还没有并成事件）。
typedef _WindowVerdict = ({int startMs, AutoLabel label, double margin});

/// 在片段里找出够格的事件。
///
/// 三步：**逐窗判 → 连续同向的并成一段 → 太短的丢掉**。第三步是这件事的关键，
/// 理由见 [ClipAnalysisParams.minEventMs]。
List<ClipEvent> detectEvents(
  Float64List samples, {
  required int sampleRate,
  ClipAnalysisParams params = const ClipAnalysisParams(),
}) =>
    _detect(samples, sampleRate: sampleRate, params: params);

/// 找出够格的事件。**擦边的窗口不算事件，也不另行上报。**
///
/// 2026-10-15 之前这里还数了「过了三条特征阈值、但没过余量门槛」的窗口个数，好让
/// [classifyClip] 把「有东西但不够格」与「什么都没找到」分开——前者弃权、后者报杂音。
/// 杂音兜底拆掉之后两者都归弃权，那个计数就没有用处了，于是删掉。
List<ClipEvent> _detect(
  Float64List samples, {
  required int sampleRate,
  required ClipAnalysisParams params,
}) {
  if (samples.isEmpty) return const <ClipEvent>[];

  final windowSamples = sampleRate * params.windowMs ~/ 1000;
  final hopSamples = math.max(1, sampleRate * params.windowHopMs ~/ 1000);

  // 窗口起点。片段比一个窗还短时只取一段（整段），它的时长天生够不着
  // [ClipAnalysisParams.minEventMs]，于是自然什么都判不出来——这正是应有之义。
  final starts = <int>[];
  if (samples.length <= windowSamples) {
    starts.add(0);
  } else {
    for (var s = 0; s + windowSamples <= samples.length; s += hopSamples) {
      starts.add(s);
    }
  }

  final windows = <_WindowVerdict>[];
  for (final start in starts) {
    final end = math.min(start + windowSamples, samples.length);
    final slice = samples.sublist(start, end);
    final features = measureClip(slice, sampleRate: sampleRate, params: params);
    final verdict = _strongestRule(features, params);
    if (verdict == null) continue;
    // 三条阈值都过、只是余量不够的窗口**不算事件**——见 [ClipAnalysisParams.minMargin]。
    if (verdict.$2 < params.minMargin) continue;
    windows.add((
      startMs: start * 1000 ~/ sampleRate,
      label: verdict.$1,
      margin: verdict.$2,
    ));
  }
  if (windows.isEmpty) return const <ClipEvent>[];

  final effectiveWindowMs =
      math.min(windowSamples, samples.length) * 1000 ~/ sampleRate;
  return _mergeWindows(windows, effectiveWindowMs, params);
}

/// 把逐窗结果并成事件：连续同标签的成一段，间隔小于 [ClipAnalysisParams.mergeGapMs]
/// 的同标签段再并起来（鼾声是一串，中间本来就有停顿）。
List<ClipEvent> _mergeWindows(
  List<_WindowVerdict> windows,
  int windowMs,
  ClipAnalysisParams params,
) {
  final events = <ClipEvent>[];
  var i = 0;
  while (i < windows.length) {
    final label = windows[i].label;
    var lastStart = windows[i].startMs;
    var best = windows[i].margin;
    var j = i + 1;
    while (j < windows.length) {
      final gap = windows[j].startMs - (lastStart + windowMs);
      if (windows[j].label != label || gap > params.mergeGapMs) break;
      lastStart = windows[j].startMs;
      if (windows[j].margin > best) best = windows[j].margin;
      j++;
    }

    final startMs = windows[i].startMs;
    final durationMs = lastStart + windowMs - startMs;
    if (durationMs >= params.minEventMs) {
      events.add(ClipEvent(
        label: label,
        startMs: startMs,
        durationMs: durationMs,
        margin: best,
      ));
    }
    i = j;
  }
  return events;
}

/// 一个窗口最够格的那条规则；三条特征阈值都不满足时返回 `null`。
///
/// **这里不判余量**，余量由调用方在 [detectEvents] 里单独过一道。分成两道是有后果的：
/// 「三条阈值都不过」与「三条都过、只是擦边」是两件事——前者是**什么都没测到**，
/// 后者是**测到了但没把握**。合成一道（把擦边的也收进事件表）就等于让一段勉强够格的
/// 鼾声拿到标签，而这正是 [ClipAnalysisParams.minMargin] 要挡的。
///
/// 两条规则互斥（人声那条要求低频占比低于 [ClipAnalysisParams.voiceLowRatioMax]），
/// 所以这里不会出现「同一样东西被两条规则同时认领」。真出现（阈值被改到一起去了）
/// 就取余量高的那条，并且**在测试里钉住互斥性**。
(AutoLabel, double)? _strongestRule(
  AudioFeatures f,
  ClipAnalysisParams p,
) {
  final snore = _snoreMargin(f, p);
  final voice = _voiceMargin(f, p);
  if (snore == null) return voice == null ? null : (AutoLabel.voice, voice);
  if (voice == null) return (AutoLabel.snore, snore);
  return snore >= voice ? (AutoLabel.snore, snore) : (AutoLabel.voice, voice);
}

/// 判定一段片段。**认不出来返回 `null`**，调用方据此保持「待标注」。
///
/// 只有一条通路：**逐窗事件**（频谱判据）。有事件就取**最长**的，同样长取余量高的；
/// 没有事件就弃权。
///
/// ## 两条被拆掉的通路，别当遗漏
///
///  * **呼吸带通路**（整段包络的 0.15–0.6 Hz 能量），2026-10-15 当晚拆掉。见
///    [AudioFeatures.breathBandRatio]：它判不出鼾声，因为它判的其实是「有东西在按
///    呼吸的节律起伏」，而那个描述同时成立的对象太多——实测纯风扇 34–40%、
///    风扇+敲桌 45%，比真鼾声那两段（6% / 10%）还高。
///  * **「没找到事件 = 杂音」的兜底**，2026-10-15 拆掉。见 [AutoLabel.noise]：报杂音
///    等于同时断言「不是鼾声」「不是人声」，而机器认不出鼾声，没资格下这个否定结论。
///    使用方当天的原话是「判不出来就留待标注」。
///
/// 所以现在的机器**要么给出一个带「疑似」的正向判断，要么什么都不说**。
/// 代价是覆盖率极低，这是如实的结果，不是可以靠调阈值绕过去的问题。
AutoVerdict? classifyClip(
  Float64List samples, {
  required int sampleRate,
  ClipAnalysisParams params = const ClipAnalysisParams(),
}) {
  final features = measureClip(samples, sampleRate: sampleRate, params: params);

  // 数字静音不参与判定。见 [ClipAnalysisParams.noiseMinDbfs]。
  if (features.dbfs < params.noiseMinDbfs) return null;

  final events = _detect(samples, sampleRate: sampleRate, params: params);
  if (events.isEmpty) return null;

  var best = events.first;
  for (final event in events.skip(1)) {
    if (event.durationMs > best.durationMs ||
        (event.durationMs == best.durationMs && event.margin > best.margin)) {
      best = event;
    }
  }

  return AutoVerdict(
    label: best.label,
    margin: best.margin.clamp(0.0, 1.0),
    basis: features.basis,
    startMs: best.startMs,
    durationMs: best.durationMs,
  );
}

/// 打鼾的余量；不满足返回 `null`。四条必须**同时**成立，取最小余量当结果——
/// 用最小值而不是平均值，是因为四条里只要有一条只是勉强擦过，这个判断就不该自信。
double? _snoreMargin(AudioFeatures f, ClipAnalysisParams p) {
  if (f.lowRatio < p.snoreLowRatio) return null;
  if (f.spectralCentroid >= p.snoreCentroid) return null;
  if (f.pitchStrength < p.snorePitchStrength) return null;
  if (f.spectralPeakShare >= p.snoreMaxPeakShare) return null;
  return math.min(
    (f.lowRatio - p.snoreLowRatio) / p.snoreLowRatio,
    math.min(
      (p.snoreCentroid - f.spectralCentroid) / p.snoreCentroid,
      math.min(
        (f.pitchStrength - p.snorePitchStrength) / p.snorePitchStrength,
        (p.snoreMaxPeakShare - f.spectralPeakShare) / p.snoreMaxPeakShare,
      ),
    ),
  );
}

/// 疑似人声的余量；不满足返回 `null`。
double? _voiceMargin(AudioFeatures f, ClipAnalysisParams p) {
  if (f.speechRatio < p.voiceSpeechRatio) return null;
  if (f.spectralCentroid <= p.voiceCentroid) return null;
  if (f.pitchStrength < p.voicePitchStrength) return null;
  if (f.lowRatio >= p.voiceLowRatioMax) return null;
  return math.min(
    (f.speechRatio - p.voiceSpeechRatio) / p.voiceSpeechRatio,
    math.min(
      (f.spectralCentroid - p.voiceCentroid) / p.voiceCentroid,
      (f.pitchStrength - p.voicePitchStrength) / p.voicePitchStrength,
    ),
  );
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

double _dbfs(Float64List samples) {
  if (samples.isEmpty) return -160;
  var sum = 0.0;
  for (final v in samples) {
    sum += v * v;
  }
  final rms = math.sqrt(sum / samples.length);
  if (rms <= 0) return -160;
  return 20 * (math.log(rms) / math.ln10);
}
