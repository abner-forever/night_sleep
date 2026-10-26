/// 把一晚的城市级天气翻译成「盖什么被子、开不开空调、空气怎么处理」。
///
/// **纯函数**：无时钟、无 I/O、无 widgets。输入全部来自首页那一次天气请求，
/// 没有额外网络调用，也不读数据库。
///
/// 判据是**今夜最低温**而不是此刻温度：睡眠发生在夜里，此刻 30°、凌晨 18° 的
/// 那种天气，按此刻定被子就会给出相反的结论。此刻温度只用于写「现在几度」。
library;

import 'package:flutter/foundation.dart';

/// 一条建议属于哪个话题。顺序即界面顺序：被子 → 空调 → 空气。
enum ComfortTopic { bedding, airConditioner, air }

/// 一条可执行的建议。
///
/// [action] 是卡片上那一列短结论（「薄被，2–3 斤」），[reason] 是详情里的依据
/// 与做法——两者分开，是因为首页那三行放不下解释，而解释恰恰是「凭什么」。
@immutable
class ComfortTip {
  const ComfortTip({
    required this.topic,
    required this.action,
    required this.reason,
  });

  final ComfortTopic topic;
  final String action;
  final String reason;
}

/// 今晚的结论。
@immutable
class SleepComfortAdvice {
  const SleepComfortAdvice({
    required this.headline,
    required this.basis,
    required this.tips,
    required this.nightLow,
    required this.nowTemperature,
    required this.humidity,
    required this.humidityKnown,
  });

  /// 一句话结论，例如「开空调 26°，被子搭一角」。
  final String headline;

  /// 判据行，例如「现在 24°，夜里最低 18°，湿度 68%」。
  final String basis;

  /// 被子、空调、空气（湿度缺失时没有这一条）。
  final List<ComfortTip> tips;

  /// 今夜最低温（取今天最低温与此刻温度的较小值），已四舍五入。
  final int nightLow;

  /// 此刻温度，已四舍五入。
  final int nowTemperature;

  final double? humidity;

  /// 这次天气是否带了湿度。为 false 时 [tips] 只有两条，界面要说明原因，
  /// 不能拿 50% 之类的默认值顶上。
  final bool humidityKnown;

  /// 睡眠最适的室温与湿度区间，详情里作为「调到多少」的参照。
  static const target = '目标室温 20–22°，湿度 45–55%';
}

/// 城市级天气 → 今晚的睡眠建议。
///
/// [temperature] 是此刻温度，[temperatureMin] 是今天的最低气温（和风 `tempMin`，
/// 通常落在凌晨）。两者都可能是小数，分档用原值判断，展示时取整。
SleepComfortAdvice buildSleepComfort({
  required double temperature,
  required double temperatureMin,
  required double windSpeed,
  required int weatherCode,
  double? humidity,
  double? precipitation,
}) {
  // 夜里到明晨的最低：预报的最低气温偶尔会高于此刻（凌晨读数更新、或跨日边界），
  // 取较小值才不会给出「夜里最低 26°」而此刻 24° 这种自相矛盾的判据。
  final nightLow = temperatureMin < temperature ? temperatureMin : temperature;
  final low = nightLow.round();
  final now = temperature.round();

  final bedding = _bedding(low);
  final air = _airConditioner(
    low: low,
    now: now,
    humidity: humidity,
    windSpeed: windSpeed,
    weatherCode: weatherCode,
    precipitation: precipitation,
  );
  final airTip = _humidityTip(humidity);

  return SleepComfortAdvice(
    headline: '${air.headline}，${bedding.headline}',
    basis: humidity == null
        ? '现在 $now°，夜里最低 $low°'
        : '现在 $now°，夜里最低 $low°，湿度 ${humidity.round()}%',
    tips: [
      ComfortTip(
        topic: ComfortTopic.bedding,
        action: bedding.action,
        reason: bedding.reason,
      ),
      ComfortTip(
        topic: ComfortTopic.airConditioner,
        action: air.action,
        reason: air.reason,
      ),
      if (airTip != null) airTip,
    ],
    nightLow: low,
    nowTemperature: now,
    humidity: humidity,
    humidityKnown: humidity != null,
  );
}

/// 卡片上那一列短结论的写法，与 [headline] 里的短句分开：
/// 「薄被，2–3 斤」当动作条目读，「薄被就够」当半句话读。
typedef _Bedding = ({
  String action,
  String reason,
  String headline,
});

_Bedding _bedding(int low) {
  if (low >= 27) {
    return (
      action: '只搭一角',
      headline: '被子搭一角',
      reason: '夜里最低 $low°，不盖或只用薄巾盖住腹部就够；被套换成纯棉的，贴皮肤更凉。',
    );
  }
  if (low >= 24) {
    return (
      action: '夏凉被，单层',
      headline: '夏凉被单层',
      reason: '夜里最低 $low°，一层夏凉被刚好；热了可以只盖到腰，别整夜裹住。',
    );
  }
  if (low >= 21) {
    return (
      action: '薄被，2–3 斤',
      headline: '薄被就够',
      reason: '夜里最低 $low°，2–3 斤的薄被正合适；后半夜转凉，被子别只搭在腰上。',
    );
  }
  if (low >= 17) {
    return (
      action: '中等厚度，4–5 斤',
      headline: '盖中等厚度的被子',
      reason: '夜里最低 $low°，4–5 斤的中等厚度被子刚好；嫌热可以把脚露出来。',
    );
  }
  if (low >= 12) {
    return (
      action: '厚被，6 斤以上',
      headline: '换厚被',
      reason: '夜里最低 $low°，6 斤以上的厚被，再加一条薄毯压住脚，别让肩颈漏风。',
    );
  }
  return (
    action: '厚被加毛毯',
    headline: '厚被加毛毯',
    reason: '夜里最低 $low°，厚被之外再加一层毛毯；被窝可以先暖热再进去，脚冷最难睡着。',
  );
}

/// 空调结论。返回值里的 [headline] 是拼进主结论的半句话。
typedef _Air = ({String action, String reason, String headline});

_Air _airConditioner({
  required int low,
  required int now,
  required double? humidity,
  required double windSpeed,
  required int weatherCode,
  required double? precipitation,
}) {
  final wet = _isWet(weatherCode, precipitation);
  final windy = windSpeed >= 20;

  // 开窗 / 关窗的说明只出现在空调那条里：单独列一条会和「开空调」互相打架，
  // 用户看不出到底该开窗还是关窗。
  String vent(String whenCalm) {
    if (wet) return '外面有雨雪，整夜把窗关好。';
    if (windy) return '风有 ${windSpeed.round()} km/h，窗最多留一条缝。';
    return whenCalm;
  }

  if (low >= 27) {
    return (
      action: '制冷 26–27°',
      headline: '开空调 26°',
      reason: '睡前 1 小时开到 26°，睡着后切睡眠模式或定时 3 小时；风向朝上，别对着床。'
          '${vent('空调房把窗关好，门留一条缝换气。')}',
    );
  }
  if (low >= 24 && humidity != null && humidity >= 75) {
    return (
      action: '除湿 26°',
      headline: '空调除湿 26°',
      reason: '湿度 ${humidity.round()}% 偏高，这种天气除湿比降温管用；'
          '降到 55% 左右就可以关，别整夜开着。'
          '${vent('除湿时把窗关好，否则外面湿气一直进来。')}',
    );
  }
  if (low >= 24) {
    return (
      action: '风扇低档就够',
      headline: '开风扇就够',
      reason: '夜里最低 $low°，不用开空调；风扇摇头低档，别直吹头颈。'
          '${vent('睡前开窗换气 20 分钟，睡下时留一条缝。')}',
    );
  }
  if (low >= 17) {
    return (
      action: '不用开',
      headline: '不用开空调',
      reason: '夜里最低 $low°，室温正好；现在 $now°，睡前开窗 20 分钟把白天的积热放掉。'
          '${vent('睡下时窗留一条缝，比闷着更舒服。')}',
    );
  }
  if (low >= 12) {
    return (
      action: '制热 18–20°（怕冷再开）',
      headline: '怕冷再开暖气',
      reason: '夜里最低 $low°，怕冷可以制热 18–20°，睡前预热、睡着后关掉。'
          '${vent('睡前开窗 10 分钟换气，睡下后关好。')}',
    );
  }
  return (
    action: '制热 18–20°',
    headline: '暖气 18–20°',
    reason: '夜里最低 $low°，制热 18–20° 就够，别超过 22°：'
        '室内外温差太大，起床更难受。${vent('窗关好，白天再通风。')}',
  );
}

ComfortTip? _humidityTip(double? humidity) {
  if (humidity == null) return null;
  final value = humidity.round();

  if (humidity >= 75) {
    return ComfortTip(
      topic: ComfortTopic.air,
      action: '除湿到 55%',
      reason: '湿度 $value%，被子选棉麻这类透气的；空调除湿或除湿机都行，'
          '降到 55% 左右就停，太干反而容易鼻塞。',
    );
  }
  if (humidity >= 65) {
    return ComfortTip(
      topic: ComfortTopic.air,
      action: '睡前除湿 1 小时',
      reason: '湿度 $value%，有点潮；睡前除湿 1 小时到 60% 以下，或者开窗对流一会儿。',
    );
  }
  if (humidity >= 40) {
    return ComfortTip(
      topic: ComfortTopic.air,
      action: '湿度刚好',
      reason: '湿度 $value%，在舒适区间，不用特别处理。',
    );
  }
  if (humidity >= 30) {
    return ComfortTip(
      topic: ComfortTopic.air,
      action: '加湿到 45%',
      reason: '湿度 $value% 偏干，加湿器定到 45–55%；没有加湿器可以床头放一盆水。',
    );
  }
  return ComfortTip(
    topic: ComfortTopic.air,
    action: '加湿，放盆水',
    reason: '湿度 $value% 很干，加湿器整夜低档；早起嗓子干、鼻子不舒服，多半就是这一条。',
  );
}

/// 雨、雪、雷暴，或者有降水量——都算「外面是湿的」。
bool _isWet(int code, double? precipitation) {
  if (precipitation != null && precipitation > 0) return true;
  if (code >= 51 && code <= 67) return true; // 毛毛雨 / 雨
  if (code >= 71 && code <= 77) return true; // 雪
  if (code >= 80 && code <= 82) return true; // 阵雨
  if (code >= 85 && code <= 86) return true; // 阵雪
  if (code >= 95) return true; // 雷暴
  return false;
}
