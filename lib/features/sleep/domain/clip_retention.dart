/// 录音片段的保留期限。
///
/// 规则只有一条：**留下最近 [keepNights] 个有录音的夜晚，其余的文件都清掉。**
/// 超期清理时删的是音频文件、`localUri` 置空，**`SoundClips` 行本身保留**——
/// 事件记录还在，详情页如实显示「这段录音未保留在本地」，而不是那个片段凭空消失。
library;

/// 一个片段属于哪一晚。
class ClipAge {
  const ClipAge({required this.clipId, required this.archiveDay});

  final String clipId;

  /// 这一晚归到哪一天，用**用户醒来**那天的本地日历日。
  ///
  /// 与 `SleepEntry.archiveDay` 同一口径——记录本来就是按醒来那天归档的，
  /// 保留期限另起一套算法只会让「记录列表里还在、录音却按另一个夜晚被清了」
  /// 这种自相矛盾有地方藏。
  final DateTime archiveDay;
}

/// 返回应该清理掉音频文件的片段 id。
///
/// **口径是「数据里最近的 [keepNights] 晚」，不是「距今天 [keepNights] 天」。**
/// 不用设备时钟有两个好处：一是这个函数的输出只由输入决定，测试不必伪造时间；
/// 二是它的目的本来就只是把磁盘占用压在一个固定的夜晚数以内，而不是给数据设
/// 一个会随时间流逝自动过期的保质期——用户停了两个月再回来，昨晚那段录音
/// 没有理由因为「过期了」而消失。
List<String> expiredClipIds(
  List<ClipAge> clips, {
  int keepNights = 7,
}) {
  if (keepNights <= 0) return [for (final clip in clips) clip.clipId];
  if (clips.isEmpty) return const [];

  final days = <DateTime>{
    for (final clip in clips) _dayOf(clip.archiveDay),
  }.toList()
    ..sort((a, b) => b.compareTo(a));

  if (days.length <= keepNights) return const [];
  final kept = days.take(keepNights).toSet();

  return [
    for (final clip in clips)
      if (!kept.contains(_dayOf(clip.archiveDay))) clip.clipId,
  ];
}

/// 只取日历日，把时分秒抹掉——否则同一晚的片段会因为时刻不同被当成不同的天。
DateTime _dayOf(DateTime value) => DateTime(value.year, value.month, value.day);
