/// 首页眉题那句问候与 hero 卡里那条结论。
///
/// **纯函数**：没有时钟、没有数据库。时间由调用方从 `homeNowProvider` 取
/// （测试靠它冻结「现在」），记录由调用方从 `sleepEntriesProvider` 取。
///
/// 结论条这一条是超出原型的产品决定（原型末层有这个元素，但使用方第 3 条
/// 把它的地位提上来了），见总规格 §8 偏差 #70 与
/// [静谧夜色 + 柔和晨光](../../../../docs/superpowers/specs/2026-10-16-quiet-night-visual-language.md) §4.1.1。
library;

/// 首页那行问候。时段分界见规格 §3.1。
///
/// 23:00–04:59 是「夜深了」而不是「晚安」：这一档覆盖的是**还没睡**的人，
/// 说「晚安」等于替用户宣布他要去睡了。
String greetingFor(DateTime now) {
  final hour = now.hour;
  if (hour >= 5 && hour < 12) return '早安';
  if (hour >= 12 && hour < 18) return '午安';
  if (hour >= 18 && hour < 23) return '晚上好';
  return '夜深了';
}

/// 昨夜时长相对**前七晚**平均的差值，单位分钟。没有可比的前几晚时为 `null`。
///
/// [recentHoursNewestFirst] 是各晚时长（小时），**最新在前**。原型取
/// `records.slice(1, 8)`——下标 1 到 7，也就是**前七晚**（不是六晚），
/// 分母是实际取到的条数：只有两晚记录时就用那一晚，不拿 0 去补。
int? durationDelta(List<double> recentHoursNewestFirst) {
  if (recentHoursNewestFirst.isEmpty) return null;
  final previous = recentHoursNewestFirst.skip(1).take(7).toList();
  if (previous.isEmpty) return null;
  final average = previous.reduce((a, b) => a + b) / previous.length;
  return ((recentHoursNewestFirst.first - average) * 60).round();
}

/// 结论条第一行：昨夜与前七晚平均比出来的那句话。
///
/// **它只说时长。** 不说「深睡表现不错」这类话——本应用没有可靠的阶段结论，
/// 而 `notes` 与事件都是用户自己填的。差值不足 10 分钟按「基本持平」算：
/// 那一档的误差本来就在四舍五入的量级上，报一个「多睡了 3 分钟」是假精确。
String durationInsightSentence(int? delta) {
  if (delta == null) return '继续记录几晚，就能看到你的睡眠变化';
  if (delta.abs() < 10) return '与近 7 日平均基本持平，节律很稳定';
  return delta > 0 ? '比近 7 日平均多睡了 $delta 分钟' : '比近 7 日平均少睡了 ${delta.abs()} 分钟';
}

/// 结论条第二行：一句当晚就能做的事。
String durationAdviceSentence(double lastNightHours) =>
    lastNightHours >= 7 ? '时长已达到建议目标，保持现在的睡眠节律' : '今晚可以尝试提前半小时放下手机';
