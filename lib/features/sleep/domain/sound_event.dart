/// Night-time audio events.
///
/// A clip is only ever created from an actual recording — the app never
/// fabricates snore or sleep-talk events, and a transcript or analysis is
/// nullable because recognition may be unavailable or may have failed. The UI
/// must render the missing case rather than filling it in.
library;

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
  /// **Null for every real recording**, deliberately. A real envelope has to
  /// come from decoding the file, and painting a rhythm the audio may not have
  /// is exactly the fabrication the spec forbids — so a real clip without an
  /// analysed envelope draws neutral bars instead of a shape.
  ///
  /// The one populated case is a demo night: those rows are entirely synthetic
  /// (their transcripts and hypnograms are too), they are labelled as demo in
  /// the UI, and they can be cleared in one action. See
  /// [demoWaveformEnvelope].
  final List<double>? waveformEnvelope;

  bool get hasPlayableAudio => localUri != null;

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
