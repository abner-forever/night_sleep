import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/features/sleep/domain/insight_prompt.dart';
import 'package:night_sleep/features/sleep/domain/sleep_entry.dart';
import 'package:night_sleep/features/sleep/domain/sleep_quality.dart';
import 'package:night_sleep/features/sleep/domain/sleep_score.dart';
import 'package:night_sleep/features/sleep/domain/sleep_stage.dart';
import 'package:night_sleep/features/sleep/domain/sound_event.dart';

/// The prompt is the whole data-scope decision: whatever is written here is
/// what leaves the device. So the tests are mostly about what must **not**
/// appear — a placeholder rating, a stage breakdown for a night that was never
/// measured, or the user's free-text notes.
void main() {
  final bedtime = DateTime(2026, 9, 26, 23, 12);
  final wake = DateTime(2026, 9, 27, 7, 3);

  SleepEntry entry({
    SleepQuality? quality = SleepQuality.good,
    LoggedEvents events = LoggedEvents.none,
    List<SleepStageSegment> stages = const [],
    List<SoundClip> clips = const [],
    String notes = '',
  }) =>
      SleepEntry(
        id: 'e1',
        startAtUtc: bedtime.toUtc(),
        endAtUtc: wake.toUtc(),
        timeZoneId: 'UTC',
        quality: quality,
        notes: notes,
        loggedEvents: events,
        stages: stages,
        soundClips: clips,
        createdAtUtc: bedtime.toUtc(),
        updatedAtUtc: wake.toUtc(),
      );

  test('只带真实字段：日期、时刻、时长与自评', () {
    final prompt = buildRecordSummaryPrompt(entry());

    expect(prompt.user, contains('2026-09-27'));
    expect(prompt.user, contains('23:12'));
    expect(prompt.user, contains('07:03'));
    expect(prompt.user, contains('7 小时 51 分'));
    expect(prompt.user, contains('4/5'));
  });

  test('未评分就说未评分，绝不填一个占位档', () {
    final prompt = buildRecordSummaryPrompt(entry(quality: null));

    expect(prompt.user, contains('未评分'));
    // 既没有分数，也没有任何替用户下的判断。
    expect(prompt.user, isNot(contains('4/5')));
    expect(prompt.user, isNot(contains('良好')));
  });

  test('没有阶段数据时不出现阶段那一段', () {
    final prompt = buildRecordSummaryPrompt(entry(
      stages: [
        SleepStageSegment(
          stage: SleepStageType.deep,
          startAtUtc: bedtime.toUtc(),
          endAtUtc: bedtime.add(const Duration(hours: 2)).toUtc(),
        ),
      ],
    ));

    expect(prompt.user, contains('睡眠阶段'));
    expect(prompt.user, contains('深睡 100%'));

    final bare = buildRecordSummaryPrompt(entry());
    expect(bare.user, isNot(contains('睡眠阶段')));
  });

  test('没有声音事件时不出现声音那一段', () {
    final quiet = buildRecordSummaryPrompt(entry());
    expect(quiet.user, isNot(contains('声音事件')));

    final noisy = buildRecordSummaryPrompt(entry(clips: [
      SoundClip(
        id: 'c1',
        kind: SoundEventKind.snore,
        startedAtUtc: bedtime.toUtc(),
        durationMs: 4000,
      ),
      SoundClip(
        id: 'c2',
        kind: SoundEventKind.snore,
        startedAtUtc: bedtime.toUtc(),
        durationMs: 4000,
      ),
      SoundClip(
        id: 'c3',
        kind: SoundEventKind.talk,
        startedAtUtc: bedtime.toUtc(),
        durationMs: 4000,
      ),
    ]));
    expect(noisy.user, contains('共 3 条'));
    expect(noisy.user, contains('打鼾 2'));
    expect(noisy.user, contains('梦话 1'));
  });

  test('用户没有标记不适时，不写「无」这句', () {
    expect(buildRecordSummaryPrompt(entry()).user, isNot(contains('用户标记')));
    expect(
      buildRecordSummaryPrompt(entry(events: const LoggedEvents(snore: true)))
          .user,
      contains('打鼾'),
    );
  });

  test('备注不进提示词——它是唯一可能装着任意内容的字段', () {
    final prompt = buildRecordSummaryPrompt(entry(notes: '今天很累，家里的事很多'));
    expect(prompt.user, isNot(contains('家里的事')));
  });

  test('系统提示要求 JSON，且禁止编造与医疗结论', () {
    final prompt = buildRecordSummaryPrompt(entry());
    // JSON 模式要求提示词里出现 "json" 字样，这条是实测出来的。
    expect(prompt.system.toLowerCase(), contains('json'));
    expect(prompt.system, contains('不要编造'));
    expect(prompt.system, contains('不做医疗诊断'));
  });
}
