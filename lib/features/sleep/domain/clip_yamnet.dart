// 夜间片段的判定规则——「每一窗的模型分」进，「一个结论或弃权」出。
//
// 这个文件故意不 import `tflite_flutter`、不碰 `dart:io`：**模型在 `flutter test`
// 里根本加载不了**（它要一个平台上的原生库）。把「分数怎么变成结论」留在这里，
// 判定规则才有一条能被完整单测钉死的路；跑模型那一半在
// `data/yamnet_scorer.dart`。
//
// ## 为什么是 YAMNet，以及原来那套去哪儿了
//
// 2026-10-14 起这里原本是一组写死的声学阈值（低频占比 + 谱质心 + 周期性 + 最强单音），
// 用滑动窗找事件。**它已被证伪**：在使用方 47 段真实录音上覆盖 2% / 准确 0% /
// 鼾声召回 0%，把时长门槛从 2500 ms 一路扫到 500 ms 也救不回来——不是阈值没调对，
// 是那组特征不承载「鼾声 vs 划桌子 + 拍手」这个区分。
//
// 换成的东西是 **YAMNet**（AudioSet 训练，521 类）。它在同一批数据上零样本就分开了：
// 使用方本人 3 段鼾声的 `Snoring` 均分 0.708–0.850，44 段其余最高 0.305；
// 换到 ESC-50 别人录的 40 段鼾声 / 200 段易混类，阈值 0.3–0.4 上仍是
// 「36 或 33 条命中、200 条一条不过」。逐条依据见
// `docs/superpowers/specs/2026-10-16-snore-detection-approaches-design.md`。
//
// ## 三件刻意不做的事，别当遗漏
//
//  * **只给整段一个结论，不给「第几秒到第几秒」。** 文档 §4.3 记着：拿片级标签训出来的
//    模型定位能力差是 2025 年仍在攻的活跃问题。`Snoring` 分数是**片级**的，拿它去画一个
//    事件区间就是把没量过的东西画出来。`AutoVerdict.startMs` / `durationMs` 因此恒为 0，
//    那一对字段留着是为了读**旧记录**（旧规则确实产出过区间）。
//  * **统计量只用整段均分。** 那正是上面那些数字被量出来的口径。取最大、取分位数都要
//    另一轮实测才作数。
//  * **不给概率、不拿「杂音」兜底。** 两条都没有变：`margin` 是「越过判定线多少」，
//    不是「有多大概率」；认不出来就弃权，见 [AutoLabel.noise] 的文档。
//
// ## 短于一个窗口的片段
//
// YAMNet 一窗要吃满 15600 点（0.975 秒）。比这短的片段**补零喂一整窗**——
// 与 2026-10-16 那次端侧探针逐字一致，好让两边的数能直接比。**这个行为本身没有测量过**
// （那 47 段里最短的是 1.00 秒，从来没走到这一支），照样记在未验证里。

import 'clip_analysis.dart';

/// 模型的采样率。**不是本项目选的**：YAMNet 只吃 16 kHz 单声道。
/// 采集格式恰好也是 16 kHz（规格 §二），所以两端对得上，不需要重采样。
const int kYamnetSampleRate = 16000;

/// 一窗的采样点数——0.975 秒。官方 README 的原话是
/// **"you need at least 975 ms of input waveform to get the first frame of output scores"**，
/// 这也是模型文件里输入张量 `waveform_binary` 的 shape。
const int kYamnetWindowSamples = 15600;

/// 窗口步进，取半个窗口。判定要的是「整段均分」，步进大小不影响这个量；
/// 取一半是为了在片段稍长于一个窗口时也能多拿到几窗，均分不至于被一窗定死。
const int kYamnetHopSamples = 7800;

/// `Snoring` 在 YAMNet 521 类 output 里的下标。
///
/// **AudioSet 本体里的 mid 是 `/m/01d3sd`**，按 mid 查而不是按下标查——
/// PANNs / AST / CED 用的是 527 类，同一个 `Snoring` 在它们那里是 43。
const int kSnoringIndex = 38;

/// `Speech` 的下标（`/m/09x0r`）。机器只说「疑似人声」，**不说「梦话」**：
/// 分清梦话、清醒说话与电视声，光靠这一类的分数做不到。
const int kSpeechIndex = 0;

/// 输出向量的长度。`Interpreter.run` 要求调用方按这个形状把容器准备好。
const int kYamnetClassCount = 521;

/// 低于这个响度就不下任何结论（dBFS）。
///
/// **数字静音不是「杂音」，也不是任何别的东西。** 平台静音时录到的是一串零
/// （Android 上真发生过，见验证记录 v3.19），给它安一个标签等于把「什么都没录到」
/// 说成一个判断。极轻的抖动噪声同理：那上面算出来的任何东西都是垃圾。
///
/// 这道闸**在模型之前**，理由不只是「不该给它标签」：全零输入对 YAMNet 是**分布外**
/// 的——它的输入本来是真实录音的波形。模型对一串零会说什么，**没有任何测量**，
/// 所以不能让它说话。
const double kSilenceDbfs = -60;

/// 判定参数。**两个阈值都是拍的，理由写在字段上，未验证项在验证记录里。**
class YamnetParams {
  const YamnetParams({
    this.snoreThreshold = 0.40,
    this.voiceThreshold = 0.70,
  })  : assert(snoreThreshold >= 0 && snoreThreshold <= 1),
        assert(voiceThreshold >= 0 && voiceThreshold <= 1);

  /// 鼾声的判定线：整段 `Snoring` 均分不低于它就算「疑似打鼾」。
  ///
  /// **取 0.40 的直接依据是两组实测在同一个区间上给出同一个结论**：
  /// 使用方自己那 3 段是 0.708–0.850、他自己 44 段负样本最高 0.305；ESC-50 那 240 段上
  /// 阈值 0.4 是「33 / 40 命中、200 条 0 误报」。0.3–0.7 之间随便取都成立，
  /// 取靠中间偏严的 0.4 是为了**宁可漏也不误报**。
  ///
  /// **但它不是定稿**：两组加起来只有 43 条正样本。说得出「这条路成立」，
  /// 说不出「0.40 是对的」——本仓的规矩是样本不足不调参。
  final double snoreThreshold;

  /// 人声的判定线。**比鼾声那条严得多，因为它这条路的证据弱得多。**
  ///
  /// 实测（使用方 10 段人标梦话 / 37 段其余）：阈值 0.3 → 召回 90% / 精确 69%，
  /// 0.4 → 90% / 75%，0.5 → 80% / 80%。**0.70 这一档没有量过**——它是使用方
  /// 明确要求「收得更紧」之后取的，标准是「宁可漏也不误报」。
  /// 什么时候能把它调回来，取决于攒到多少段人标梦话，见验证记录 v3.37。
  final double voiceThreshold;
}

/// 一段片段里每一窗的模型分。两个列表与窗口一一对应，长度必须相等。
class ClipScores {
  /// **不是 `const` 构造**：那条「两类窗口数一致」的断言在常量求值里读不了
  /// `.length`，写成 `const` 会让 `const ClipScores(snore: [], ...)` 编译不过。
  ClipScores({required this.snore, required this.speech})
      : assert(snore.length == speech.length, '两类的窗口数必须一致');

  /// 每一窗的 `Snoring` 分数。
  final List<double> snore;

  /// 每一窗的 `Speech` 分数。
  final List<double> speech;

  int get windowCount => snore.length;

  bool get isEmpty => snore.isEmpty;
}

/// 哪些采样点是窗口起点。**这就是 `Interpreter.run` 要喂的第几个窗口。**
///
/// 片段比一个窗还短时只给一个起点 0——那一次的输入由调用方补零补满
/// （见文件头最后一段）。比一个窗稍长的片段只有一个完整窗，也就只跑一次：
/// 补零凑第二个窗会让均值里掺进半截静音，那不是测量。
List<int> yamnetWindowStarts(int sampleCount) {
  if (sampleCount <= 0) return const <int>[];
  if (sampleCount <= kYamnetWindowSamples) return const <int>[0];
  final starts = <int>[];
  for (var start = 0;
      start + kYamnetWindowSamples <= sampleCount;
      start += kYamnetHopSamples) {
    starts.add(start);
  }
  return starts;
}

/// 整段的均分——**判定唯一用到的那个统计量**。
///
/// 单独拎出来是为了让它可测：`basis` 里要摆这个数，测试要能直接钉住它。
double meanScore(List<double> windowScores) {
  if (windowScores.isEmpty) return 0;
  var sum = 0.0;
  for (final score in windowScores) {
    sum += score;
  }
  return sum / windowScores.length;
}

/// 所有窗口里最高的那一窗。**不参与判定，只摆在依据里给人看。**
///
/// 为什么要摆一个不参与的数：**均分有一个已知的盲区**。一段 11.8 秒的录音里
/// 只有前 3.5 秒是鼾声，剩下的在翻身——鼾声那几窗能到 0.9，均分却被摊到 0.3 上下，
/// 于是弃权。这个盲区**不是新引入的**：上面那些把阈值定到 0.40 的数字
/// （他自己 3 段 0.708–0.850、ESC-50 36/40）**全都是拿均分量出来的**，换成最高分
/// 就等于换一个没有量过的统计量，本仓不许这么干。
///
/// 所以摆出来让人**看得见**它：`均分 0.31、最高 0.91` 一眼就是「这段里有一截很像」，
/// 而 `均分 0.05、最高 0.09` 是「整段都不像」。什么时候把判定改成按最高分或
/// 按「连续够长的窗口」，取决于重新量过一次。见验证记录 v3.37 的未验证那一半。
double maxScore(List<double> windowScores) {
  if (windowScores.isEmpty) return 0;
  var best = windowScores.first;
  for (final score in windowScores.skip(1)) {
    if (score > best) best = score;
  }
  return best;
}

/// 一段片段的判定结果；**认不出来返回 `null`**（弃权）。
///
/// 顺序是刻意的：先看鼾声，再看人声。鼾声那一路的证据强得多，两边同时过线时
/// 该听它的。**两条同时成立本身是异常**——`Snoring` 是「呼吸受阻的声音」、
/// `Speech` 是「说话」，真实的片段极少同时像这两个；但阈值摆在那里就可能发生，
/// 所以要有确定的先后，而不是让它随窗口顺序漂。
///
/// **永远不会返回 [AutoLabel.noise]**：说「杂音」等于同时断言「不是鼾声」和
/// 「不是人声」两个否定结论，而模型给的是 521 类的排序，不是这两个否定。这条
/// 与 2026-10-15 拆掉杂音兜底是同一件事（偏差 #65）。
AutoVerdict? verdictFromScores(
  ClipScores scores, {
  required double dbfs,
  YamnetParams params = const YamnetParams(),
}) {
  if (scores.isEmpty) return null;
  if (dbfs < kSilenceDbfs) return null;

  final snoreMean = meanScore(scores.snore);
  final speechMean = meanScore(scores.speech);

  if (snoreMean >= params.snoreThreshold) {
    return AutoVerdict(
      label: AutoLabel.snore,
      margin: _margin(snoreMean, params.snoreThreshold),
      basis: _basis(
        scores: scores,
        winner: AutoLabel.snore,
        winnerMean: snoreMean,
        loserMean: speechMean,
        threshold: params.snoreThreshold,
      ),
    );
  }

  if (speechMean >= params.voiceThreshold) {
    return AutoVerdict(
      label: AutoLabel.voice,
      margin: _margin(speechMean, params.voiceThreshold),
      basis: _basis(
        scores: scores,
        winner: AutoLabel.voice,
        winnerMean: speechMean,
        loserMean: snoreMean,
        threshold: params.voiceThreshold,
      ),
    );
  }

  return null;
}

/// 越过判定线的**相对**余量，不是概率。
///
/// 用相对量而不是绝对差，是为了让两个阈值差一倍多的类能放在一起排序。
/// 夹到 1.0 是照 `AutoAnalysis.decode` 的既有口径（它读回来会 clamp）。
double _margin(double mean, double threshold) {
  if (threshold <= 0) return 1;
  return ((mean - threshold) / threshold).clamp(0.0, 1.0);
}

/// 界面上摆出来的依据串。
///
/// 摆五样东西，每一样都是**测出来的**：赢的那个类的均分、它的最高分、整段跑了几个
/// 窗口、生效的判定线、以及输的那个类的均分。五个都摆是有用的——
///
///  * 两个类的分都摆，读者能看出机器是在「像鼾声」和「像人声」之间怎么选的；
///  * **最高分摆出来是为了让均分的盲区可见**（见 [maxScore]）：`均分 0.31、最高 0.91`
///    与 `均分 0.31、最高 0.34` 是完全不同的两段东西，前者一眼看得出「里面有一截很像」；
///  * 窗口数与判定线摆出来，这串数才是可复核的——不然读者不知道 0.85 是拿几个数
///    平均出来的、也不知道它离判定线多远。
///
/// **摆的是分与判定线，不是「把握」或概率**——那两样都要标注数据才估得出来，
/// 编一个百分比出来正是本仓最要挡的那种假话（偏差 #59）。
String _basis({
  required ClipScores scores,
  required AutoLabel winner,
  required double winnerMean,
  required double loserMean,
  required double threshold,
}) {
  final windows = scores.windowCount;
  final winnerMax =
      maxScore(winner == AutoLabel.snore ? scores.snore : scores.speech);
  final winnerName = winner == AutoLabel.snore ? '鼾声' : '人声';
  final loserName = winner == AutoLabel.snore ? '人声' : '鼾声';
  return 'YAMNet $winnerName分 ${winnerMean.toStringAsFixed(2)}'
      '（整段 $windows 个窗口均分、最高 ${winnerMax.toStringAsFixed(2)}，'
      '判定线 ${threshold.toStringAsFixed(2)}）'
      '· $loserName分 ${loserMean.toStringAsFixed(2)}';
}
