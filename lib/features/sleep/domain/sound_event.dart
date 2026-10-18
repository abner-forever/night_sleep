/// Night-time audio events.
///
/// A clip is only ever created from an actual recording — the app never
/// fabricates snore or sleep-talk events, and a transcript or analysis is
/// nullable because recognition may be unavailable or may have failed. The UI
/// must render the missing case rather than filling it in.
///
/// **2026-10-14 起多了一层：机器的判断（[SoundClip.autoAnalysis]）。** 它仍然
/// 不伪造任何东西——那是从**实测声学特征**算出来的启发式结果；没有可判定的声音
/// （数字静音 / 空输入）时不给结论。它与人的标注**分列存放**，理由见
/// [SoundClip.autoAnalysis] 的文档：混在一列里就再也分不清「用户听过说是打鼾」
/// 与「机器猜是打鼾」。
library;

import 'clip_analysis.dart';

enum SoundEventKind {
  snore('snore', '打鼾'),
  talk('talk', '梦话'),
  noise('noise', '杂音');

  const SoundEventKind(this.id, this.label);

  final String id;
  final String label;

  static SoundEventKind? fromId(String id) {
    for (final kind in SoundEventKind.values) {
      if (kind.id == id) return kind;
    }
    return null;
  }
}

/// How far along the analysis pipeline a clip is.
enum SoundAnalysisStatus {
  /// Recorded, not yet looked at. Playable, no transcript, no insight.
  pending('pending'),

  /// A transcript or classification exists.
  analysed('analysed'),

  /// Analysis was attempted and failed; the clip stays playable.
  failed('failed');

  const SoundAnalysisStatus(this.id);

  final String id;

  static SoundAnalysisStatus fromId(String id) {
    for (final status in SoundAnalysisStatus.values) {
      if (status.id == id) return status;
    }
    return SoundAnalysisStatus.pending;
  }
}

class SoundClip {
  const SoundClip({
    required this.id,
    required this.kind,
    required this.startedAtUtc,
    required this.durationMs,
    this.localUri,
    this.transcript,
    this.analysis,
    this.analysisStatus = SoundAnalysisStatus.pending,
    this.source = 'recording',
    this.waveformEnvelope,
    this.labeledAtUtc,
    this.autoAnalysis,
  });

  final String id;
  final SoundEventKind kind;
  final DateTime startedAtUtc;
  final int durationMs;

  /// Path inside the app's private directory. Null when the audio was pruned
  /// but the event record was kept.
  final String? localUri;

  /// Speech-to-text output for sleep talk. Null until a transcript exists.
  final String? transcript;

  /// Model-generated insight. Null unless a provider actually produced one.
  final String? analysis;

  final SoundAnalysisStatus analysisStatus;
  final String source;

  /// Normalised 0–1 amplitude per bar, [waveformBarCount] long.
  ///
  /// 两种来源：**真实录音**的包络是采集时实测的（切片时那段振幅序列归一化并
  /// 重采样），存在 `sound_clips.waveform_envelope` 列里；**演示数据**的包络是
  /// 合成的，见 [demoWaveformEnvelope]。
  ///
  /// 为 `null` 时界面画等高轨道，不给它编一个形状——「没有测量就不画」这条规则
  /// 一个字没改，变的只是「真实录音现在有测量了」。包络落库而不是读取时解码文件，
  /// 是因为片段被保留期限裁掉之后文件就没了，而形状仍然是真的。
  final List<double>? waveformEnvelope;

  /// 用户听过并标注过这一段的时刻；`null` = 还没标过。
  ///
  /// 少这一列就没法把「用户标成了杂音」与「还没标过」分开：两者在 [kind] 里
  /// 都是 [SoundEventKind.noise]。
  final DateTime? labeledAtUtc;

  /// 机器跑完声学分析之后的判断；`null` = 从没分析过。
  ///
  /// **它为什么不写进 [kind]**：`kind` 在库里是「人做的判断」，界面上的三态
  /// （人标过 / 机器判过 / 待标注）全靠它们是否为空来分。合成一列之后，
  /// 「用户听过说是打鼾」与「机器测出来像打鼾」就再也没法区分了——而那正是
  /// 这一整块最不能丢的区分。
  ///
  /// [AutoAnalysis.verdict] 为 `null` 表示机器**看过但没有结论**（数字静音 /
  /// 空输入），与本字段整体为 `null`（没分析过）不同。
  final AutoAnalysis? autoAnalysis;

  bool get hasPlayableAudio => localUri != null;

  bool get isLabeled => labeledAtUtc != null;

  /// 机器给出了判断（不是没有结论、也不是没分析过）。
  bool get hasAutoVerdict => autoAnalysis?.verdict != null;

  /// 卡片上显示的那个词。**优先级：人标的 > 机器判的 > 待标注。**
  ///
  /// 机器判出来的那个词**必须带「自动」**：读者要一眼看得出这是机器测出来的，
  /// 不是谁听过的。
  ///
  /// **「自动 · 杂音」与「待标注」是两件事，别合并。** 「自动 · 杂音」= 有声音、
  /// 但机器在整段上没测到够格的鼾声或人声；「待标注」= 机器没有给出结论（数字静音、
  /// 读不出来、或还没分析过）。前者是一个**测量过的兜底结论**，后者是**没有结论**
  /// ——`AutoLabel.noise` 的文档里写了它凭什么这么记。
  String get labelText {
    if (isLabeled) return kind.label;
    final verdict = autoAnalysis?.verdict;
    if (verdict != null) return '自动 · ${verdict.label.label}';
    return '待标注';
  }

  Duration get duration => Duration(milliseconds: durationMs);

  /// Local `HH:mm` label for the clip.
  String get timeLabel {
    final local = startedAtUtc.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  /// Clips shorter than a second still need a sensible label.
  String get durationLabel => '${(durationMs / 1000).round()}s';

  /// Bars the waveform track draws.
  static const int waveformBarCount = 38;

  /// A deterministic, plausible-looking envelope **for demo clips only**.
  ///
  /// Snoring reads as a slow repeating swell; sleep talk as irregular bursts.
  /// Seeded from the clip id so the same demo night always draws the same
  /// shape — a waveform that changed between rebuilds would be a bug, not a
  /// feature. This exists so the waveform track can be seen and checked at all;
  /// it is not a measurement and must never be attached to a real recording.
  static List<double> demoWaveformEnvelope(String id, SoundEventKind kind) {
    var seed = id.hashCode & 0x7fffffff;
    double next() {
      // xorshift keeps the sequence deterministic across runs, which
      // `Random(seed)` alone does not guarantee for a list build order.
      seed ^= (seed << 13) & 0x7fffffff;
      seed ^= seed >> 17;
      seed ^= (seed << 5) & 0x7fffffff;
      return (seed & 0xffff) / 0xffff;
    }

    return List<double>.generate(waveformBarCount, (i) {
      final jitter = 0.25 + next() * 0.3;
      if (kind == SoundEventKind.snore) {
        // ~8 bars per breath cycle, with the second half louder.
        final phase = (i % 8) / 8 * 3.14159 * 2;
        final swell = 0.45 + 0.35 * (phase / (3.14159 * 2));
        return (swell *
                (0.7 + 0.6 * (1 - (phase / 3.14159 - 1).abs())) *
                (0.8 + jitter * 0.4))
            .clamp(0.12, 1.0);
      }
      // Speech: bursts of 2–4 bars separated by quiet gaps.
      final inBurst = (i % 5) < 3;
      return (inBurst ? 0.55 + jitter * 0.6 : 0.10 + jitter * 0.12)
          .clamp(0.08, 1.0);
    });
  }
}
