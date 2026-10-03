import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/features/sleep/domain/clip_retention.dart';

/// 造某一天的一批片段。`hour` 用来确认同一晚的片段不会被时刻拆成不同的天。
List<ClipAge> _night(int year, int month, int day, int clipCount,
    {int hour = 2}) {
  return [
    for (var i = 0; i < clipCount; i++)
      ClipAge(
        clipId: '$year-$month-$day-$i',
        archiveDay: DateTime(year, month, day, hour, 30 + i),
      ),
  ];
}

void main() {
  group('保留最近 N 晚', () {
    test('恰好 7 晚时一个都不清', () {
      final clips = [
        for (var day = 1; day <= 7; day++) ..._night(2026, 9, day, 2),
      ];

      expect(expiredClipIds(clips), isEmpty);
    });

    test('第 8 晚出现时，最旧那一晚的片段全部过期', () {
      final clips = [
        for (var day = 1; day <= 8; day++) ..._night(2026, 9, day, 2),
      ];

      final expired = expiredClipIds(clips);

      // 变异验证：把 keepNights 默认值改成 8，这里会变成空集，断言立刻变红。
      expect(expired, hasLength(2));
      expect(expired, containsAll(['2026-9-1-0', '2026-9-1-1']));
    });

    test('同一晚的多个片段一起保留、一起清理，不被时刻拆开', () {
      final clips = [
        // 同一晚的两个片段，时刻差了将近一整天（一个凌晨、一个深夜）——按日历日
        // 归档时它们必须算作同一晚，一起保留或一起清理。
        ClipAge(clipId: 'a', archiveDay: DateTime(2026, 9, 1, 0, 1)),
        ClipAge(clipId: 'b', archiveDay: DateTime(2026, 9, 1, 23, 59)),
        for (var day = 2; day <= 8; day++) ..._night(2026, 9, day, 1),
      ];

      final expired = expiredClipIds(clips);

      expect(expired, containsAll(['a', 'b']));
      expect(expired, hasLength(2));
    });

    test('输入顺序不影响结果', () {
      final clips = [
        for (var day = 1; day <= 9; day++) ..._night(2026, 9, day, 1),
      ];

      final forward = expiredClipIds(clips);
      final backward = expiredClipIds(clips.reversed.toList());

      expect(forward.toSet(), backward.toSet());
      expect(forward, hasLength(2), reason: '9 晚留 7 晚，该清掉最早的两晚');
    });

    test('不足 7 晚时一个都不清', () {
      final clips = [..._night(2026, 9, 1, 3), ..._night(2026, 9, 2, 1)];

      expect(expiredClipIds(clips), isEmpty);
    });

    test('空输入得到空结果', () {
      expect(expiredClipIds(const []), isEmpty);
    });

    test('keepNights 可调，传 1 就只留最近一晚', () {
      final clips = [
        for (var day = 1; day <= 3; day++) ..._night(2026, 9, day, 1),
      ];

      final expired = expiredClipIds(clips, keepNights: 1);

      expect(expired, containsAll(['2026-9-1-0', '2026-9-2-0']));
      expect(expired, hasLength(2));
    });

    test('夜晚之间的间隔多大都不影响——口径是「最近 N 晚」不是「最近 N 天」', () {
      // 2026-01-01 与 2026-09-01 之间隔了大半年，但只有两晚，都该留着。
      final clips = [
        ..._night(2026, 1, 1, 2),
        ..._night(2026, 9, 1, 2),
      ];

      // 变异验证：把实现改成「按距今天数」筛（比如 now.difference(day) > N 天），
      // 这条会立刻变红——而那正是这个函数不该依赖设备时钟的理由。
      expect(expiredClipIds(clips), isEmpty);
    });
  });
}
