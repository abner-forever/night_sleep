// 夜间录音的切片与包络——整条录音链路里唯一能被完整单测的纯函数层。
//
// 这个文件故意不 import `dart:io`、不碰任何插件、不碰平台通道：PCM 采集、RMS 聚合、
// 写 WAV 文件都要真机才能验证，而「哪一段算有声响、片段从哪到哪、包络长什么样」必须
// 全部靠单测钉死。把切片规则挪出这个文件，整条链路就再没有可被完整验证的部分了。
//
// 切片走**增量状态机**：录音是实时的，不能等整夜的序列算完再切，所以必须在一个一个
// 采样点到的当下就决定「什么时候开一个片段、什么时候收尾」。`segmentClips` 只是把这台
// 状态机整段跑一遍的薄包装——批量与流式两条路径共用同一份实现，因此永远不会分叉。
//
// 采样点假定按 `offset` 升序到达（采集端就是按时间顺序产出的）。

/// 一格振幅采样：某个时刻的响度（dBFS，0 为满刻度，越负越安静）。
class AmplitudeSample {
  const AmplitudeSample({required this.offset, required this.dbfs});

  /// 相对于录音起点的时刻。
  final Duration offset;

  /// 这一格的 RMS 响度，单位 dBFS。
  final double dbfs;
}

/// 一段「有声响的片段」的时间区间，左闭右开语义（起点包含，终点为其后一格的边界）。
class ClipRange {
  const ClipRange({required this.start, required this.end});

  final Duration start;
  final Duration end;

  Duration get duration => end - start;
}

/// 切片参数。规格 §三 的七个默认值全部是拍的，必须真机实测后再调，不能当结论。
///
/// 阈值不是分类器：超过 [triggerThreshold] 只说明「有声响」，不说明「这是鼾声」。
class ClipParams {
  const ClipParams({
    this.triggerThreshold = -38,
    this.endThreshold = -45,
    this.silenceDuration = const Duration(seconds: 2),
    this.prePadding = const Duration(milliseconds: 500),
    this.minDuration = const Duration(seconds: 1),
    this.maxDuration = const Duration(seconds: 60),
    this.mergeGap = const Duration(seconds: 3),
  });

  /// 触发阈值：采样点**严格高于**它算「开始有声响」。
  final double triggerThreshold;

  /// 结束阈值（滞回）：已经进入片段之后，要**严格低于**它才计入静音。
  /// 与 [triggerThreshold] 拉开一段距离，音量在阈值附近抖动时才不会把一段切成几十片。
  final double endThreshold;

  /// 静音时长：连续低于 [endThreshold] 达到这么久，才结束片段。
  /// 鼾声的换气停顿比它短，所以一段鼾声不会被停顿切碎。
  final Duration silenceDuration;

  /// 前置 padding：片段起点往前多留这么多，起音不会被切掉。
  final Duration prePadding;

  /// 最短片段：短于它丢弃。丢弃发生在合并之后（见 [ClipSegmenter]）。
  final Duration minDuration;

  /// 最长片段：超过它强制切分，切出来的每段都不超过上限。
  final Duration maxDuration;

  /// 合并间隔：相邻两段（加上 padding 之后）间隔**严格小于**它，就并成一段。
  ///
  /// **它必须大于 `silenceDuration - prePadding`，否则这条规则永远触发不了。**
  /// 短于 [silenceDuration] 的停顿本来就不会关掉那一段（状态机还停在 `_active` 上），
  /// 所以「合并」只对
  /// `[silenceDuration, silenceDuration + mergeGap - prePadding]`
  /// 这个窗口里的停顿有意义。出厂默认值曾经是 1.5 秒，而 `2.0 − 0.5` 恰好也是 1.5，
  /// 比较又是严格小于——窗口是空的，参数等于不存在，鼾声那 2–3 秒的换气停顿会被
  /// 切成几十个碎片，正是这条规则要挡的事。
  ///
  /// 回归：`test/clip_segmentation_test.dart` 的「用出厂默认参数也能把换气停顿并起来」。
  final Duration mergeGap;
}

/// 增量切片状态机。喂采样点，逐点定案片段。
///
/// 一台状态机同时只持有一段「暂时还不能定案」的片段：它可能还会被后面的声响合并、
/// 可能因为太短被丢弃、也可能因为太长被切分。定案（返回）只发生在确定它不会再变的时候：
///
/// 1. 新采样点触发了一段新声响，而它与暂挂片段之间的间隔已经不小于 [ClipParams.mergeGap]
///    （或已被 padding 夹到上一段末尾之外）——上一段不会再被合并，可以定案；
/// 2. 当前采样点之后，任何未来声响到暂挂片段末尾的距离都已经不小于
///    `mergeGap + prePadding`，于是上一段同样不可能再被合并；
/// 3. [flush]：序列结束，把最后挂着的一段收尾。
class ClipSegmenter {
  ClipSegmenter(this.params);

  final ClipParams params;

  /// 是否正在累积一段高于结束阈值的声响。
  bool _active = false;

  /// 当前这段声响关闭时，是否直接延长暂挂片段（而不是新起一段）。
  bool _activeMerges = false;

  /// 当前这段声响若是新起一段，它加上 padding 之后的起点。
  Duration _activePaddedStart = Duration.zero;

  /// 当前这段声响里最后一个「非静音」采样点的窗口末端。
  Duration _lastSoundEnd = Duration.zero;

  /// 当前这段声响里连续静音累计的时长。
  Duration _silence = Duration.zero;

  /// 已关闭、但还可能被后续声响合并、因而尚未定案的片段。
  ClipRange? _pending;

  bool _hasLast = false;
  Duration _lastOffset = Duration.zero;

  /// 喂一个新的采样点，返回**因为这一个采样点而变得可以定案的**片段区间。
  ///
  /// 一次最多只能定案一段（状态机同时只暂挂一段）。
  List<ClipRange> add(AmplitudeSample sample) {
    var step = _hasLast ? sample.offset - _lastOffset : Duration.zero;
    if (step < Duration.zero) step = Duration.zero;
    _hasLast = true;
    _lastOffset = sample.offset;

    if (_active) {
      if (sample.dbfs < params.endThreshold) {
        _silence += step;
        if (_silence >= params.silenceDuration) {
          _closeActive();
        }
      } else {
        _silence = Duration.zero;
        final end = sample.offset + step;
        if (end > _lastSoundEnd) _lastSoundEnd = end;
      }
    }

    if (_active) return const [];

    if (sample.dbfs > params.triggerThreshold) {
      return _beginActive(sample.offset, step);
    }

    final pending = _pending;
    if (pending != null && _canFinalize(sample.offset)) {
      _pending = null;
      return _emit(pending);
    }
    return const [];
  }

  /// 序列结束（会话结束 / 停止录音）时收尾，把还没定案的片段吐出来。
  ///
  /// 不管此刻是停在高电平上、还是停在静音的尾巴上：后者会以最后一个非静音采样点
  /// 的窗口末端作为片段终点，静音尾巴不算进片段。
  List<ClipRange> flush() {
    if (_active) _closeActive();
    final pending = _pending;
    if (pending == null) return const [];
    _pending = null;
    _activeMerges = false;
    return _emit(pending);
  }

  /// 从现在起，未来任何声响都到不了会与暂挂片段合并的距离。
  bool _canFinalize(Duration now) {
    final pending = _pending;
    if (pending == null) return false;
    return now - params.prePadding - pending.end >= params.mergeGap;
  }

  /// 开始一段新声响。可能顺手把上一段定案（间隔太大、合并不了时）。
  List<ClipRange> _beginActive(Duration offset, Duration step) {
    _active = true;
    _silence = Duration.zero;
    _lastSoundEnd = offset + step;

    var padded = offset - params.prePadding;
    if (padded < Duration.zero) padded = Duration.zero;

    final pending = _pending;
    if (pending != null) {
      // 起点不得早于上一段的结束。
      if (padded < pending.end) padded = pending.end;
      if (padded - pending.end < params.mergeGap) {
        // 并进上一段：起点沿用上一段，终点等这段关闭时再延长。
        _activeMerges = true;
        return const [];
      }
      _pending = null;
      _activeMerges = false;
      _activePaddedStart = padded;
      return _emit(pending);
    }

    _activeMerges = false;
    _activePaddedStart = padded;
    return const [];
  }

  void _closeActive() {
    _active = false;
    _silence = Duration.zero;
    final end = _lastSoundEnd;
    final pending = _pending;
    if (_activeMerges && pending != null) {
      _pending = ClipRange(start: pending.start, end: end);
    } else {
      _pending = ClipRange(start: _activePaddedStart, end: end);
    }
    _activeMerges = false;
  }

  /// 最短片段丢弃、最长片段切分——都发生在合并之后、片段定案的那一刻。
  List<ClipRange> _emit(ClipRange clip) {
    final span = clip.end - clip.start;
    if (span < params.minDuration) return const [];
    if (params.maxDuration <= Duration.zero || span <= params.maxDuration) {
      return [clip];
    }
    final total = span.inMicroseconds;
    final maxUs = params.maxDuration.inMicroseconds;
    final pieces = (total + maxUs - 1) ~/ maxUs;
    final out = <ClipRange>[];
    var prevUs = 0;
    for (var k = 1; k <= pieces; k++) {
      final endUs = (k * total) ~/ pieces;
      out.add(ClipRange(
        start: clip.start + Duration(microseconds: prevUs),
        end: clip.start + Duration(microseconds: endUs),
      ));
      prevUs = endUs;
    }
    return out;
  }
}

/// 批处理 = 增量状态机整段跑一遍，因此仍然是纯函数。
///
/// 边界输入：
/// * 空输入 → 空清单；
/// * 全静音 → 空清单；
/// * 一直高于触发阈值直到序列结束 → [ClipSegmenter.flush] 会把它收尾成一段，**不会丢**；
/// * 单个采样点 → 会被当作一段零长度区间，因短于 [ClipParams.minDuration] 而丢弃
///   （`minDuration` 为 0 时则得到一段 `[t, t]` 的零长度片段）；
/// * `offset` 未按升序排列时结果未定义。
List<ClipRange> segmentClips(List<AmplitudeSample> samples, ClipParams params) {
  final segmenter = ClipSegmenter(params);
  return [
    for (final sample in samples) ...segmenter.add(sample),
    ...segmenter.flush(),
  ];
}

/// 把 [range] 区间内的采样归一化并重采样成 [bars] 条实测包络。
///
/// * 结果长度恒为 [bars]，元素在 0–1；
/// * 归一化用区间内的最小值与最大值做线性映射（最小值 → 0，最大值 → 1），
///   因此是单调的；
/// * 每一格取该格中心时刻**最近**的采样点（最近邻重采样）；采样点比格子少时会有
///   重复值，比格子多时取代表值，不做平均；
/// * 区间内没有任何采样点时返回全 0；
/// * 区间内所有采样点相等（含全静音）时没有可归一化的动态范围，也返回全 0——
///   重点是**不得产生 NaN**；
/// * [bars] 非正数时返回空清单。
List<double> envelopeFor(
  List<AmplitudeSample> samples,
  ClipRange range, {
  int bars = 38,
}) {
  if (bars <= 0) return const <double>[];

  final inRange = <AmplitudeSample>[
    for (final sample in samples)
      if (sample.offset >= range.start && sample.offset <= range.end) sample,
  ];
  if (inRange.isEmpty) return List<double>.filled(bars, 0);

  var minDb = inRange.first.dbfs;
  var maxDb = inRange.first.dbfs;
  for (final sample in inRange) {
    if (sample.dbfs < minDb) minDb = sample.dbfs;
    if (sample.dbfs > maxDb) maxDb = sample.dbfs;
  }
  // 全静音（或电平恒定）时没有动态范围：画成静音高度，绝不出 NaN。
  if (!(maxDb > minDb)) return List<double>.filled(bars, 0);
  final span = maxDb - minDb;

  final totalUs = (range.end - range.start).inMicroseconds;
  final result = List<double>.filled(bars, 0);
  for (var i = 0; i < bars; i++) {
    final centerUs = ((2 * i + 1) * totalUs) ~/ (2 * bars);
    final center = range.start + Duration(microseconds: centerUs);
    var best = inRange.first;
    var bestDiff = (best.offset - center).abs();
    for (final sample in inRange) {
      final diff = (sample.offset - center).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = sample;
      }
    }
    result[i] = ((best.dbfs - minDb) / span).clamp(0.0, 1.0).toDouble();
  }
  return result;
}
