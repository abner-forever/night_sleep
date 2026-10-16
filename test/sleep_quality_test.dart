import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/features/sleep/domain/sleep_quality.dart';

/// 主观睡眠质量的档位、标签与即时反馈。
///
/// v3.34 起标签从「评价」换成「感受」（使用方要求星级改成状态选项），
/// 但**五个档位与它们的 1–5 底层值一个都没动**——`estimateScore` 有 35 分权重
/// 吃这个值，改档位数会让评分口径跟着变。这一组就是钉住这条边界。
void main() {
  test('仍是五档，底层值仍是 1–5', () {
    expect(SleepQuality.values.length, 5);
    expect([for (final q in SleepQuality.values) q.value], [1, 2, 3, 4, 5]);
  });

  test('标签换成感受，不再是评价', () {
    expect(
      [for (final q in SleepQuality.values) q.label],
      ['精疲力尽', '疲惫', '一般', '清醒', '精力充沛'],
    );
  });

  test('旧的四字评价词一个都不再出现', () {
    final labels = [for (final q in SleepQuality.values) q.label];
    for (final old in ['极差', '较差', '良好', '极好']) {
      expect(labels, isNot(contains(old)));
    }
  });

  test('每一档都有一句即时反馈，且各不相同', () {
    final feedbacks = [for (final q in SleepQuality.values) q.feedback];
    expect(feedbacks.where((f) => f.trim().isEmpty), isEmpty);
    expect(feedbacks.toSet().length, 5);
  });

  test('反馈与档位一一对应', () {
    expect(SleepQuality.veryPoor.feedback, '今晚早点休息');
    expect(SleepQuality.poor.feedback, '要留意一下节律');
    expect(SleepQuality.fair.feedback, '还算平稳');
    expect(SleepQuality.good.feedback, '状态不错');
    expect(SleepQuality.excellent.feedback, '休息得很好');
  });

  test('fromValue 取得到每一档', () {
    for (final q in SleepQuality.values) {
      expect(SleepQuality.fromValue(q.value), q);
    }
  });
}
