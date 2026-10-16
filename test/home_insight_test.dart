import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/features/home/domain/home_insight.dart';

/// 首页眉题问候与 hero 卡里那条结论的单元测试。
///
/// 两条都是纯函数：没有时钟、没有数据库。结论条只说**时长**这一件真的测过的事
/// ——它不该、也不会提到阶段或声音。
void main() {
  group('问候', () {
    // 四个时段的分界逐个钉住。分界本身是产品裁定（规格 §3.1），
    // 23:00–04:59 说「夜深了」而不是「晚安」——那一档覆盖的是还没睡的人。
    const cases = <(int, int, String)>[
      (4, 59, '夜深了'),
      (5, 0, '早安'),
      (11, 59, '早安'),
      (12, 0, '午安'),
      (17, 59, '午安'),
      (18, 0, '晚上好'),
      (22, 59, '晚上好'),
      (23, 0, '夜深了'),
      (0, 0, '夜深了'),
    ];

    for (final (hour, minute, expected) in cases) {
      test(
          '${hour.toString().padLeft(2, '0')}:'
          '${minute.toString().padLeft(2, '0')} → $expected', () {
        expect(greetingFor(DateTime(2026, 10, 16, hour, minute)), expected);
      });
    }
  });

  group('昨夜与前七晚的差', () {
    /// 把分钟数换成小时，避免在夹具里手写 8.1666…。
    double hours(int minutes) => minutes / 60;

    test('一条记录都没有时为 null', () {
      expect(durationDelta(const []), isNull);
    });

    test('只有昨晚一条、没有可比的前几晚时为 null', () {
      expect(durationDelta([hours(480)]), isNull);
    });

    test('与前几晚持平时报 0', () {
      expect(durationDelta([hours(480), hours(480), hours(480)]), 0);
    });

    test('分母是实际取到的前几晚条数，不拿 0 去补', () {
      // 一共三晚：昨晚 8h，前两晚 6h 与 7h → 平均 6.5h → 多睡 90 分钟。
      expect(durationDelta([hours(480), hours(360), hours(420)]), 90);
    });

    test('只看前七晚，更早的不参与', () {
      final nights = [
        hours(600), // 昨晚 10h
        for (var i = 0; i < 9; i++) hours(480), // 前九晚都是 8h
      ];
      // 前七晚全是 8h，第 8、9 晚（也是 8h）本就不该被算进来——这里靠
      // 「取七条」而不是「取全部」来钉：把 take(7) 改成 take(9) 结果不变，
      // 所以另用一组前七晚与更早几晚不同的数据来钉住边界。
      expect(durationDelta(nights), 120);

      final mixed = [
        hours(600),
        for (var i = 0; i < 7; i++) hours(480), // 前七晚 8h
        for (var i = 0; i < 3; i++) hours(300), // 更早三晚 5h
      ];
      expect(durationDelta(mixed), 120);
    });
  });

  group('结论条第一行', () {
    test('没有可比的前几晚时不报数字，只说继续记录', () {
      expect(durationInsightSentence(null), '继续记录几晚，就能看到你的睡眠变化');
    });

    test('不足 10 分钟按「基本持平」算——那一档报数字是假精确', () {
      expect(durationInsightSentence(0), '与近 7 日平均基本持平，节律很稳定');
      expect(durationInsightSentence(9), '与近 7 日平均基本持平，节律很稳定');
      expect(durationInsightSentence(-9), '与近 7 日平均基本持平，节律很稳定');
    });

    test('差 10 分钟开始报数字', () {
      expect(durationInsightSentence(10), '比近 7 日平均多睡了 10 分钟');
      expect(durationInsightSentence(42), '比近 7 日平均多睡了 42 分钟');
    });

    test('少睡时写绝对值，不写负号', () {
      expect(durationInsightSentence(-10), '比近 7 日平均少睡了 10 分钟');
      expect(durationInsightSentence(-95), '比近 7 日平均少睡了 95 分钟');
    });
  });

  group('结论条第二行', () {
    test('达到 7 小时给「保持节律」', () {
      expect(durationAdviceSentence(7), '时长已达到建议目标，保持现在的睡眠节律');
      expect(durationAdviceSentence(8.5), '时长已达到建议目标，保持现在的睡眠节律');
    });

    test('不足 7 小时给一句当晚就能做的事', () {
      expect(durationAdviceSentence(6.9), '今晚可以尝试提前半小时放下手机');
    });
  });
}
