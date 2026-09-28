import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/core/config/app_config.dart';
// Only the database handle is needed here; drift's generated row classes share
// names with the domain models, so the rest is deliberately not imported.
import 'package:night_sleep/core/database/app_database.dart' show AppDatabase;
import 'package:night_sleep/features/sleep/data/demo_seed.dart';
import 'package:night_sleep/features/sleep/data/sleep_repository.dart';
import 'package:night_sleep/features/sleep/domain/sleep_entry.dart';
import 'package:night_sleep/features/sleep/domain/sleep_quality.dart';
import 'package:night_sleep/features/sleep/domain/sleep_score.dart';
import 'package:night_sleep/features/sleep/domain/sleep_stage.dart';
import 'package:night_sleep/features/sleep/domain/sleep_window.dart';

void main() {
  late AppDatabase database;
  late SleepRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = SleepRepository(database);
  });

  tearDown(() => database.close());

  group('演示数据', () {
    // A fixed reference date keeps the seeded nights deterministic.
    final reference = DateTime(2026, 9, 27, 12);

    test('安装 5 条演示记录，全部标记为 demo', () async {
      await DemoSeed.install(database, now: reference);

      final entries = await repository.loadAll();
      expect(entries, hasLength(5));
      expect(
        entries.every((entry) => entry.source == AppConfig.demoSource),
        isTrue,
        reason: '演示行必须可被 deleteDemoData 识别',
      );
    });

    test('每条演示记录的阶段总和等于睡眠时长', () async {
      await DemoSeed.install(database, now: reference);

      for (final entry in await repository.loadAll()) {
        final stageMinutes =
            entry.stages.fold<int>(0, (sum, segment) => sum + segment.minutes);
        expect(
          stageMinutes,
          entry.durationMinutes,
          reason: '$entry.id 的阶段与时长不一致，柱状图会与总时长矛盾',
        );
      }
    });

    test('阶段段连续无缝，从入睡贯穿到起床', () async {
      await DemoSeed.install(database, now: reference);

      for (final entry in await repository.loadAll()) {
        final ordered = [...entry.stages]
          ..sort((a, b) => a.startAtUtc.compareTo(b.startAtUtc));
        expect(ordered.first.startAtUtc, entry.startAtUtc);
        expect(ordered.last.endAtUtc, entry.endAtUtc);
        for (var i = 1; i < ordered.length; i++) {
          expect(
            ordered[i].startAtUtc,
            ordered[i - 1].endAtUtc,
            reason: '阶段 $i 与前一段之间存在空隙或重叠',
          );
        }
      }
    });

    test('声音片段与洞察带来源，且不凭空生成', () async {
      await DemoSeed.install(database, now: reference);

      final entries = await repository.loadAll();
      final withClips = entries.where((entry) => entry.hasSoundEvents).toList();
      expect(withClips, hasLength(3), reason: '原型中 1/2/4 号有声音事件');

      final snoreClips = entries
          .expand((entry) => entry.soundClips)
          .where((clip) => clip.kind.name == 'snore')
          .toList();
      expect(snoreClips, isNotEmpty);

      // Every seeded night carries an insight, and it is attributed to demo
      // rather than to a model provider that never ran.
      for (final entry in entries) {
        expect(entry.insight, isNotNull);
        expect(entry.insight!.provider, AppConfig.demoSource);
        expect(entry.scoreSource, ScoreSource.modelInsight);
      }
    });

    test('清除演示数据只删除 demo 行', () async {
      await DemoSeed.install(database, now: reference);
      final window = buildSleepWindow(
        wakeDate: reference,
        bedtime: '23:00',
        wakeTime: '07:00',
      );
      await repository.save(
        id: 'real-1',
        startAtUtc: window.startAtUtc,
        endAtUtc: window.endAtUtc,
        timeZoneId: window.timeZoneId,
        quality: SleepQuality.good,
        notes: '真实记录',
        events: LoggedEvents.none,
      );

      await repository.deleteDemoData();

      final remaining = await repository.loadAll();
      expect(remaining, hasLength(1));
      expect(remaining.single.id, 'real-1');
    });
  });

  group('记录读写', () {
    Future<String> saveNight({
      String id = 'night-1',
      String bedtime = '23:15',
      String wakeTime = '07:20',
      SleepQuality quality = SleepQuality.good,
      LoggedEvents events = LoggedEvents.none,
      String notes = '',
    }) async {
      final window = buildSleepWindow(
        wakeDate: DateTime(2026, 9, 27),
        bedtime: bedtime,
        wakeTime: wakeTime,
      );
      await repository.save(
        id: id,
        startAtUtc: window.startAtUtc,
        endAtUtc: window.endAtUtc,
        timeZoneId: window.timeZoneId,
        quality: quality,
        notes: notes,
        events: events,
      );
      return id;
    }

    test('保存后可读回，时长由时间戳派生', () async {
      await saveNight(notes: '测试备注');

      final entry = (await repository.loadAll()).single;
      expect(entry.durationHours, closeTo(8.083, 0.001));
      expect(entry.bedtimeLabel, '23:15');
      expect(entry.wakeLabel, '07:20');
      expect(entry.notes, '测试备注');
      expect(entry.quality, SleepQuality.good);
    });

    test('醒来日归档：跨午夜记录归属次日', () async {
      await saveNight();
      final entry = (await repository.loadAll()).single;
      expect(entry.dateLabel, '2026-09-27');
      expect(entry.archiveDay, DateTime(2026, 9, 27));
    });

    test('事件标记被持久化并能驱动本地估算', () async {
      await saveNight(events: const LoggedEvents(snore: true, restless: true));

      final entry = (await repository.loadAll()).single;
      expect(entry.loggedEvents.snore, isTrue);
      expect(entry.loggedEvents.restless, isTrue);
      expect(entry.loggedEvents.talk, isFalse);
    });

    test('同 id 再次保存为更新，不产生重复行', () async {
      await saveNight(notes: '第一版');
      await saveNight(notes: '第二版');

      final entries = await repository.loadAll();
      expect(entries, hasLength(1));
      expect(entries.single.notes, '第二版');
    });
  });

  group('无测量数据时不伪造内容', () {
    test('纯手动记录：无阶段、无声音，评分标记为本地估算', () async {
      final window = buildSleepWindow(
        wakeDate: DateTime(2026, 9, 27),
        bedtime: '23:00',
        wakeTime: '07:00',
      );
      await repository.save(
        id: 'manual-1',
        startAtUtc: window.startAtUtc,
        endAtUtc: window.endAtUtc,
        timeZoneId: window.timeZoneId,
        quality: SleepQuality.fair,
        notes: '',
        events: LoggedEvents.none,
      );

      final entry = (await repository.loadAll()).single;
      expect(entry.hasStages, isFalse);
      expect(entry.hasSoundEvents, isFalse);
      expect(entry.totalStageMinutes, 0);
      expect(entry.scoreSource, ScoreSource.onDeviceEstimate);
      expect(entry.isEstimated, isTrue);
      // 8h + fair quality + no events → 45 + 17.5 + 20 = 82.5 → 83.
      expect(entry.score, 83);
      expect(entry.insightText, isNull, reason: '没有模型结果就不应有洞察文案');
      expect(entry.estimatedSummary, isNotNull);
    });

    test('阶段写入后按阶段计分，不再回退到估算', () async {
      final window = buildSleepWindow(
        wakeDate: DateTime(2026, 9, 27),
        bedtime: '23:00',
        wakeTime: '07:00',
      );
      await repository.save(
        id: 'imported-1',
        startAtUtc: window.startAtUtc,
        endAtUtc: window.endAtUtc,
        timeZoneId: window.timeZoneId,
        quality: SleepQuality.good,
        notes: '',
        events: LoggedEvents.none,
        source: 'import',
        stages: [
          SleepStageSegment(
            stage: SleepStageType.light,
            startAtUtc: window.startAtUtc,
            endAtUtc: window.startAtUtc.add(const Duration(hours: 2)),
          ),
          SleepStageSegment(
            stage: SleepStageType.deep,
            startAtUtc: window.startAtUtc.add(const Duration(hours: 2)),
            endAtUtc: window.endAtUtc,
          ),
        ],
      );

      final entry = (await repository.loadAll()).single;
      expect(entry.hasStages, isTrue);
      expect(entry.totalStageMinutes, 480);
      expect(entry.minutesFor(SleepStageType.deep), 360);
      expect(entry.stagePercent(SleepStageType.deep), 75);
      // Measured data with no model insight → no score at all, rather than a
      // rule-based estimate standing in for a measurement.
      expect(entry.scoreSource, ScoreSource.none);
      expect(entry.score, isNull);
    });
  });

  group('删除', () {
    test('删除记录连带清理阶段与声音片段', () async {
      final window = buildSleepWindow(
        wakeDate: DateTime(2026, 9, 27),
        bedtime: '23:00',
        wakeTime: '07:00',
      );
      await repository.save(
        id: 'cascade-1',
        startAtUtc: window.startAtUtc,
        endAtUtc: window.endAtUtc,
        timeZoneId: window.timeZoneId,
        quality: SleepQuality.good,
        notes: '',
        events: LoggedEvents.none,
        stages: [
          SleepStageSegment(
            stage: SleepStageType.deep,
            startAtUtc: window.startAtUtc,
            endAtUtc: window.endAtUtc,
          ),
        ],
      );
      expect(await database.stagesFor('cascade-1'), hasLength(1));

      await repository.delete('cascade-1');

      expect(await database.stagesFor('cascade-1'), isEmpty);
      expect(await repository.loadAll(), isEmpty);
    });

    test('删除全部本地数据清空记录与洞察', () async {
      await DemoSeed.install(database, now: DateTime(2026, 9, 27, 12));
      await repository.deleteAllUserData();

      expect(await repository.loadAll(), isEmpty);
      expect(await database.allInsightsByRecord(), isEmpty);
    });
  });
}
