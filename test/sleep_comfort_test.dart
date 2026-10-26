import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/features/home/domain/sleep_comfort.dart';

/// 「今晚怎么睡」的判据表在 `docs/sleep-comfort-plan.md` §3.2，这些用例逐档钉住它：
/// 阈值挪一格就会有一条挂掉，而不是等用户发现「30 度让我盖厚被」。
void main() {
  /// 默认让此刻温度等于预报最低温：多数用例只关心一档温度，不必两处都写。
  /// 需要「此刻比预报更低」时显式传 [temperature]。
  SleepComfortAdvice advice({
    double? temperature,
    double temperatureMin = 20,
    double? humidity = 55,
    double windSpeed = 8,
    int weatherCode = 0,
    double? precipitation,
  }) =>
      buildSleepComfort(
        temperature: temperature ?? temperatureMin,
        temperatureMin: temperatureMin,
        humidity: humidity,
        windSpeed: windSpeed,
        weatherCode: weatherCode,
        precipitation: precipitation,
      );

  ComfortTip tipOf(SleepComfortAdvice value, ComfortTopic topic) =>
      value.tips.firstWhere((tip) => tip.topic == topic);

  group('被子按今夜最低温分档', () {
    test('27° 以上只搭一角', () {
      final result = advice(temperatureMin: 28);
      expect(tipOf(result, ComfortTopic.bedding).action, '只搭一角');
    });

    test('24–27° 夏凉被单层', () {
      final result = advice(temperatureMin: 25);
      expect(tipOf(result, ComfortTopic.bedding).action, '夏凉被，单层');
    });

    test('21–24° 薄被', () {
      final result = advice(temperatureMin: 22);
      expect(tipOf(result, ComfortTopic.bedding).action, '薄被，2–3 斤');
    });

    test('17–21° 中等厚度', () {
      final result = advice(temperatureMin: 18);
      expect(tipOf(result, ComfortTopic.bedding).action, '中等厚度，4–5 斤');
    });

    test('12–17° 厚被', () {
      final result = advice(temperatureMin: 14);
      expect(tipOf(result, ComfortTopic.bedding).action, '厚被，6 斤以上');
    });

    test('12° 以下厚被加毛毯', () {
      final result = advice(temperatureMin: 5);
      expect(tipOf(result, ComfortTopic.bedding).action, '厚被加毛毯');
    });
  });

  group('空调同时看温度与湿度', () {
    test('27° 以上制冷 26–27°', () {
      final result = advice(temperatureMin: 28, humidity: 50);
      expect(tipOf(result, ComfortTopic.airConditioner).action, '制冷 26–27°');
      expect(result.headline, contains('开空调 26°'));
    });

    test('24–27° 且湿度 75% 以上走除湿', () {
      final result = advice(temperatureMin: 25, humidity: 82);
      expect(tipOf(result, ComfortTopic.airConditioner).action, '除湿 26°');
    });

    test('24–27° 但湿度不高时只用风扇', () {
      final result = advice(temperatureMin: 25, humidity: 60);
      expect(tipOf(result, ComfortTopic.airConditioner).action, '风扇低档就够');
    });

    test('17–24° 不用开空调', () {
      final result = advice(temperatureMin: 20, humidity: 50);
      expect(tipOf(result, ComfortTopic.airConditioner).action, '不用开');
    });

    test('12–17° 给「怕冷再开」而不是直接制热', () {
      final result = advice(temperatureMin: 15, humidity: 50);
      expect(
        tipOf(result, ComfortTopic.airConditioner).action,
        '制热 18–20°（怕冷再开）',
      );
    });

    test('12° 以下制热且提醒不要超过 22°', () {
      final result = advice(temperatureMin: 4, humidity: 40);
      final ac = tipOf(result, ComfortTopic.airConditioner);
      expect(ac.action, '制热 18–20°');
      expect(ac.reason, contains('别超过 22°'));
    });

    test('阈值按原值判断，25.9° 仍属 24–27° 档', () {
      final result = advice(temperatureMin: 25.9, humidity: 55);
      expect(tipOf(result, ComfortTopic.airConditioner).action, '风扇低档就够');
    });
  });

  group('空气按湿度', () {
    test('75% 以上除湿到 55%', () {
      final result = advice(humidity: 80);
      expect(tipOf(result, ComfortTopic.air).action, '除湿到 55%');
    });

    test('65–75% 睡前除湿一小时', () {
      final result = advice(humidity: 68);
      expect(tipOf(result, ComfortTopic.air).action, '睡前除湿 1 小时');
    });

    test('40–65% 不用处理', () {
      final result = advice(humidity: 52);
      expect(tipOf(result, ComfortTopic.air).action, '湿度刚好');
    });

    test('30–40% 加湿到 45%', () {
      final result = advice(humidity: 35);
      expect(tipOf(result, ComfortTopic.air).action, '加湿到 45%');
    });

    test('30% 以下加强加湿', () {
      final result = advice(humidity: 22);
      expect(tipOf(result, ComfortTopic.air).action, '加湿，放盆水');
    });
  });

  group('湿度缺失时如实缩水', () {
    final result = advice(humidity: null);

    test('只剩被子与空调两条', () {
      expect(result.tips.map((tip) => tip.topic), [
        ComfortTopic.bedding,
        ComfortTopic.airConditioner,
      ]);
      expect(result.humidityKnown, isFalse);
    });

    test('判据行里不出现湿度，也不拿默认值顶上', () {
      expect(result.basis, isNot(contains('湿度')));
      expect(result.basis, isNot(contains('%')));
    });
  });

  group('通风并进空调那条，避免与开窗互相打架', () {
    test('有雨时整夜关窗', () {
      final result = advice(weatherCode: 61);
      expect(
        tipOf(result, ComfortTopic.airConditioner).reason,
        contains('外面有雨雪，整夜把窗关好'),
      );
    });

    test('有降水量同样算湿', () {
      final result = advice(precipitation: 0.4);
      expect(
        tipOf(result, ComfortTopic.airConditioner).reason,
        contains('整夜把窗关好'),
      );
    });

    test('风大时只留一条缝', () {
      final result = advice(windSpeed: 26);
      expect(
        tipOf(result, ComfortTopic.airConditioner).reason,
        contains('窗最多留一条缝'),
      );
    });

    test('无风无雨且不用开空调时给睡前开窗', () {
      final result = advice(temperatureMin: 20);
      expect(
        tipOf(result, ComfortTopic.airConditioner).reason,
        contains('开窗'),
      );
    });
  });

  test('预报最低温高于此刻时，取此刻作为今夜最低', () {
    final result = advice(temperature: 18, temperatureMin: 24);
    expect(result.nightLow, 18);
    expect(result.basis, contains('夜里最低 18°'));
  });

  test('结论由空调动作与被子动作拼成，读得通', () {
    final result = advice(temperatureMin: 19, humidity: 50);
    expect(result.headline, '不用开空调，盖中等厚度的被子');
  });

  test('文案不下绝对化承诺', () {
    for (final min in [30.0, 25.0, 22.0, 18.0, 14.0, 3.0, -15.0]) {
      final result = advice(temperatureMin: min, humidity: 70);
      final text = [
        result.headline,
        result.basis,
        for (final tip in result.tips) '${tip.action}${tip.reason}',
      ].join();
      for (final banned in ['一定', '保证', '必须', '绝对', '包你']) {
        expect(text, isNot(contains(banned)), reason: '「$banned」不该出现在建议里');
      }
    }
  });
}
