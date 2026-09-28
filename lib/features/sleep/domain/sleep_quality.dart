/// Subjective sleep quality, rated 1–5 by the user.
///
/// Labels follow the prototype (`Q_LBL`): the full five-step scale is always
/// available because the user is the source of this value — unlike the model
/// insights, nothing here is inferred.
enum SleepQuality {
  veryPoor(1, '极差'),
  poor(2, '较差'),
  fair(3, '一般'),
  good(4, '良好'),
  excellent(5, '极好');

  const SleepQuality(this.value, this.label);

  final int value;
  final String label;

  static SleepQuality fromValue(int value) {
    return SleepQuality.values.firstWhere(
      (quality) => quality.value == value,
      orElse: () => SleepQuality.fair,
    );
  }
}
