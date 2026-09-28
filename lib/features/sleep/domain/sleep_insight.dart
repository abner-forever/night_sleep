/// A model-generated observation about a record.
///
/// The spec requires that insights are only ever stored when a provider
/// actually produced them, and that failures never surface as valid
/// conclusions. So this type keeps provider/model provenance and a status, and
/// the UI shows nothing where [content] is null.
library;

enum InsightStatus {
  /// Requested and successfully generated.
  ok('ok'),

  /// The request failed or timed out; [Insight.content] should be ignored.
  failed('failed'),

  /// No provider is configured yet.
  unavailable('unavailable');

  const InsightStatus(this.id);

  final String id;

  static InsightStatus fromId(String id) {
    for (final status in InsightStatus.values) {
      if (status.id == id) return status;
    }
    return InsightStatus.unavailable;
  }
}

class Insight {
  const Insight({
    required this.id,
    this.recordId,
    this.kind = 'record_summary',
    this.content,
    this.provider,
    this.model,
    this.score,
    required this.generatedAtUtc,
    this.status = InsightStatus.unavailable,
  });

  final String id;
  final String? recordId;

  /// What the insight is about, e.g. `record_summary` or `clip_analysis`.
  final String kind;

  /// Model output. Null when generation failed or never ran.
  final String? content;

  final String? provider;
  final String? model;

  /// Model-supplied 0–100 score, when the provider returns one.
  final int? score;

  final DateTime generatedAtUtc;
  final InsightStatus status;

  bool get isUsable => status == InsightStatus.ok && content != null;
}
