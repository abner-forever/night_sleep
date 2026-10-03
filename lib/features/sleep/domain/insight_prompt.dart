/// Builds the text sent to a model provider for one night.
///
/// Everything here is a **pure function of the record**: no defaults, no
/// placeholders, no "一般" standing in for a rating the user never gave. If a
/// field is absent the line is left out entirely, so the model cannot write
/// about something that was never measured — which is also why the user's free
/// text `notes` is **not** sent: it is the one field that can contain anything
/// the user typed, and sending it would widen the data scope without the user
/// having been shown what leaves the device. See 偏差 #47.
library;

import 'sleep_entry.dart';
import 'sleep_stage.dart';

class RecordInsightPrompt {
  const RecordInsightPrompt({required this.system, required this.user});

  final String system;
  final String user;
}

const String _system = '你是「夜深」App 的睡眠记录助手。'
    '只输出一个 json 对象，形如 {"score": 0 到 100 的整数, "summary": "中文总结"}，'
    '不要输出任何其他文字或代码块标记。'
    '总结不超过 120 字，语气平实。'
    '输入里没有给出的数据一律不要编造、也不要提及。'
    '不做医疗诊断，不给用药建议。';

RecordInsightPrompt buildRecordSummaryPrompt(SleepEntry entry) {
  final lines = <String>[
    '请根据下面这一晚的真实记录写一段中文总结，并给出 0-100 的睡眠评分。',
    '日期：${entry.dateLabel}',
    '入睡：${entry.bedtimeLabel}',
    '起床：${entry.wakeLabel}',
    '时长：${_duration(entry.durationMinutes)}',
    entry.quality == null
        // 未评分就说未评分。喂一个「良好」进去等于替用户说了一句他没说过的话。
        ? '主观质量：未评分（用户没有打分，不要替他打分，也不要假设他睡得好或不好）'
        : '主观质量：${entry.quality!.value}/5（用户自评）',
  ];

  if (entry.loggedEvents.any) {
    lines.add('用户标记的不适：${_events(entry)}');
  }
  if (entry.hasStages) {
    lines.add('睡眠阶段（设备测量，占比）：${_stages(entry)}');
  }
  if (entry.hasSoundEvents) {
    lines.add('声音事件（设备记录）：共 ${entry.soundClips.length} 条，${_clips(entry)}');
  }

  return RecordInsightPrompt(system: _system, user: lines.join('\n'));
}

String _duration(int minutes) {
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (hours == 0) return '$rest 分';
  if (rest == 0) return '$hours 小时';
  return '$hours 小时 $rest 分';
}

String _events(SleepEntry entry) {
  final events = entry.loggedEvents;
  return [
    if (events.snore) '打鼾',
    if (events.talk) '梦话',
    if (events.restless) '翻来覆去',
    if (events.nightmare) '噩梦',
  ].join('、');
}

String _stages(SleepEntry entry) => [
      for (final stage in SleepStageType.charted)
        '${stage.label} ${entry.stagePercent(stage)}%',
    ].join('、');

String _clips(SleepEntry entry) {
  final counts = <String, int>{};
  for (final clip in entry.soundClips) {
    counts.update(clip.kind.label, (value) => value + 1, ifAbsent: () => 1);
  }
  return [
    for (final counted in counts.entries) '${counted.key} ${counted.value}',
  ].join('、');
}
