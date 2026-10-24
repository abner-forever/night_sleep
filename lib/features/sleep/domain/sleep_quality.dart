/// Subjective sleep quality, rated 1–5 by the user.
///
/// 标签按最新设计稿的五星质量档位展示。五个档位与它们的 1–5 底层值**一个都没动**
/// ——`estimateScore` 有 35 分权重吃这个值，改档位数会让评分口径跟着变。
enum SleepQuality {
  veryPoor(1, '极差', '今晚早点休息'),
  poor(2, '较差', '要留意一下节律'),
  fair(3, '一般', '还算平稳'),
  good(4, '良好', '状态不错'),
  excellent(5, '极好', '休息得很好');

  const SleepQuality(this.value, this.label, this.feedback);

  final int value;

  /// 选项上的文字。
  final String label;

  /// 选中之后就地在同一行给出的一句反馈。
  ///
  /// **它与 [value] 一一对应，不另立一套判断**——反馈说的是这一档本身，
  /// 不是对整晚睡眠下的结论（那种结论这一页没有资格给）。
  final String feedback;

  static SleepQuality fromValue(int value) {
    return SleepQuality.values.firstWhere(
      (quality) => quality.value == value,
      orElse: () => SleepQuality.fair,
    );
  }
}
