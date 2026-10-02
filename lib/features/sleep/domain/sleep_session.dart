/// 一次正在进行（或刚刚结束）的睡眠会话。
///
/// **它不测量任何东西。** 两个时刻都来自用户自己按下的按钮，起床时间来自用户
/// 自己的设定。圆环画的是「已过时长 ÷ 计划时长」，两个数都是推导出来的，
/// 不是推断出来的。
library;

class SleepSession {
  const SleepSession({
    required this.startAtUtc,
    required this.timeZoneId,
    required this.wakeMinutes,
    required this.alarmEnabled,
    this.noiseId,
    this.noiseVolume = 0.5,
    required this.createdAtUtc,
  });

  /// 点「开始睡眠」的真实时刻。
  final DateTime startAtUtc;

  final String timeZoneId;

  /// 设定的起床时间，距本地午夜的分钟数。**起床时间就是闹钟时间**。
  final int wakeMinutes;

  /// 到点响不响。只影响通知，不影响圆环的目标。
  final bool alarmEnabled;

  /// 正在播放的助眠音效 id，`null` 表示没选。
  final String? noiseId;
  final double noiseVolume;

  final DateTime createdAtUtc;

  /// 起床时刻：从会话开始起，下一个落在 [wakeMinutes] 的**本地墙上时刻**。
  ///
  /// 用 `DateTime(y, m, d, h, min)` 构造而不是加时长，因此跨夏令时切换日时
  /// 仍落在同一个钟点上——与 `ReminderScheduler.nextOccurrence` 是同一条规则。
  /// 严格比较：正好等于开始时刻的那一秒已经过去，归到次日（否则计划时长会是
  /// 零，进度除零）。
  DateTime get _wakeAt {
    final start = startAtUtc.toLocal();
    final hour = wakeMinutes ~/ 60;
    final minute = wakeMinutes % 60;
    final sameDay = DateTime(start.year, start.month, start.day, hour, minute);
    if (sameDay.isAfter(start)) return sameDay;
    return DateTime(start.year, start.month, start.day + 1, hour, minute);
  }

  /// 计划睡多久：起床时刻 − 开始时刻。恒为正。
  Duration get plannedDuration => _wakeAt.difference(startAtUtc.toLocal());

  Duration elapsedAt(DateTime now) => now.toUtc().difference(startAtUtc);

  /// 圆环画的那条弧。超过起床时间后封顶在 1，不溢出也不回绕。
  double progressAt(DateTime now) {
    final planned = plannedDuration.inSeconds;
    if (planned <= 0) return 1;
    return (elapsedAt(now).inSeconds / planned).clamp(0.0, 1.0);
  }

  /// 是否已经过了设定的起床时间。
  bool overdueAt(DateTime now) => elapsedAt(now) > plannedDuration;

  /// 已睡时长的整分读法，供界面显示。
  String elapsedLabelAt(DateTime now) {
    final total = elapsedAt(now).inMinutes;
    if (total < 0) return '0h 0m';
    return '${total ~/ 60}h ${total % 60}m';
  }

  /// 超出起床时间多久，用于「已超过起床时间 42m」。
  String overdueLabelAt(DateTime now) {
    final over = elapsedAt(now) - plannedDuration;
    final minutes = over.inMinutes < 0 ? 0 : over.inMinutes;
    if (minutes < 60) return '${minutes}m';
    return '${minutes ~/ 60}h${minutes % 60}m';
  }

  /// 距起床时刻的剩余读法，用于「起床闹钟已开 · 还有 4h 4m」。
  ///
  /// **已过起床时间时为 `null`。** 剩余/已过的口径只留模型这一份：`_AlarmChip`
  /// 先前自己重算一遍并把分钟夹到 0，于是同一屏上方日晷写着「已超过起床时间 42m」、
  /// 下方写着「还有 0h 0m」——两句互相打脸，而这正是用户睡过头睁眼看手机的那一刻。
  String? remainingLabelAt(DateTime now) {
    if (overdueAt(now)) return null;
    final minutes = (plannedDuration - elapsedAt(now)).inMinutes;
    return '${minutes ~/ 60}h ${minutes % 60}m';
  }
}

/// 结束会话时时长的合法性判定。
enum SessionFinishRejection {
  none,

  /// 时长为零或负——点了开始就立刻点结束。
  tooShort,

  /// 超过 24 小时——点了开始忘了结束。
  tooLong,
}

/// 与 `SleepWindow.isPlausible` 同一口径：`0 < 时长 ≤ 24h`。
///
/// 越界时**不落库**：两种情形都不该静默变成一条睡眠记录。
SessionFinishRejection validateSessionDuration(Duration duration) {
  if (duration <= Duration.zero) return SessionFinishRejection.tooShort;
  if (duration > const Duration(hours: 24)) {
    return SessionFinishRejection.tooLong;
  }
  return SessionFinishRejection.none;
}
