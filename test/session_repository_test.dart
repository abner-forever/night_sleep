// 只要 `Value`：整个 `drift/drift.dart` 会连带引入它自己的 `isNull`（SQL 表达式），
// 与 `flutter_test` 的 `isNull` 匹配器撞名。
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/core/database/app_database.dart';
import 'package:night_sleep/features/sleep/data/session_repository.dart';
import 'package:night_sleep/features/sleep/domain/sleep_quality.dart';

void main() {
  late AppDatabase database;
  late SessionRepository repo;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repo = SessionRepository(database);
  });
  tearDown(() => database.close());

  // 用**本地时刻**构造再 `.toUtc()`，不要硬编 UTC 偏移：断言的语义是
  // 「本地 8/30 23:14 入睡、本地 8/31 07:02 醒来」，在任何时区的 runner 上都成立。
  final start = DateTime(2026, 8, 30, 23, 14).toUtc();
  final end = DateTime(2026, 8, 31, 7, 2).toUtc();

  test('没有会话时 load 返回 null', () async {
    expect(await repo.load(), isNull);
  });

  test('start 写入一行，且默认值正确', () async {
    final session = await repo.start(now: start.toLocal());

    expect(session.startAtUtc, start);
    expect(session.alarmEnabled, isFalse, reason: '闹钟默认关，不继承任何偏好');
    expect(session.noiseId, isNull, reason: '不替用户选一个音');
    expect(session.noiseVolume, 0.5);
    expect(await repo.load(), isNotNull);
  });

  test('start 采用传入的起床时间，未传时用 07:00', () async {
    expect((await repo.start(now: start.toLocal())).wakeMinutes, 7 * 60);
    await repo.discard();
    expect(
      (await repo.start(now: start.toLocal(), wakeMinutes: 6 * 60 + 30))
          .wakeMinutes,
      390,
    );
  });

  /// 用户设过起床提醒时**复用那个时刻**，不落在 07:00 的默认值上——会话页的
  /// 起床时间与设置页的起床提醒本来就是同一个概念，用户多半只该设一次。
  test('未传 wakeMinutes 时复用设置里的起床提醒时刻', () async {
    await database.updateSettings(
      const AppSettingsCompanion(wakeReminderMinutes: Value(390)),
    );

    expect((await repo.start(now: start.toLocal())).wakeMinutes, 390);
  });

  test('update 只改传入的字段', () async {
    await repo.start(now: start.toLocal());
    await repo.update(alarmEnabled: true, wakeMinutes: 8 * 60);

    final session = (await repo.load())!;
    expect(session.alarmEnabled, isTrue);
    expect(session.wakeMinutes, 480);
    expect(session.startAtUtc, start, reason: '开始时刻不该被改');
  });

  test('update 可以把 noiseId 显式清回 null', () async {
    await repo.start(now: start.toLocal());
    await repo.update(noiseId: 'rain');
    expect((await repo.load())!.noiseId, 'rain');

    await repo.update(noiseId: null);
    expect((await repo.load())!.noiseId, isNull, reason: '取消选择必须能存下去');
  });

  test('finish 写一条 source=session 的记录并清掉会话行', () async {
    await repo.start(now: start.toLocal(), wakeMinutes: 7 * 60);
    await repo.finish(now: end.toLocal(), quality: SleepQuality.good);

    expect(await repo.load(), isNull, reason: '会话行必须被删掉');

    final rows = await database.allRecords();
    expect(rows, hasLength(1));
    expect(rows.single.source, 'session');
    // 用 `isAtSameMomentAs` 而不是 `==`：这里是直接读原始 drift 行，而 drift
    // 读回来的 `DateTime` 带的是**本地**标记，`==` 会连这个标记一起比——
    // 先例与详细理由见 `test/schema_migration_test.dart`（v1 记录升级那条）。
    // 要保住的是**瞬时值**；墙钟读法由上层 `.toLocal()` 派生。
    expect(rows.single.startAtUtc.isAtSameMomentAs(start), isTrue);
    expect(rows.single.endAtUtc.isAtSameMomentAs(end), isTrue);
    expect(rows.single.quality, SleepQuality.good.value);
  });

  test('finish 允许质量为空（跳过评星）', () async {
    await repo.start(now: start.toLocal());
    await repo.finish(now: end.toLocal(), quality: null);

    expect((await database.allRecords()).single.quality, isNull);
  });

  test('finish 不写任何阶段', () async {
    await repo.start(now: start.toLocal());
    await repo.finish(now: end.toLocal(), quality: null);

    final id = (await database.allRecords()).single.id;
    expect(await database.stagesFor(id), isEmpty);
  });

  test('finish 按醒来日归档', () async {
    await repo.start(now: start.toLocal());
    await repo.finish(now: end.toLocal(), quality: null);

    final row = (await database.allRecords()).single;
    expect(row.endAtUtc.toLocal().day, 31);
  });

  test('没有会话时 finish 抛错，不写记录', () async {
    await expectLater(
      repo.finish(now: end.toLocal(), quality: null),
      throwsA(isA<StateError>()),
    );
    expect(await database.allRecords(), isEmpty);
  });

  /// 仓库里那道「再挡一道」的守门：调用方漏检时也不能静默写出一条 71 小时的
  /// 睡眠记录。会话行**保留**——用户还能自己选择丢弃还是补录。
  test('超过 24 小时的会话 finish 被拒，不写记录、会话还在', () async {
    await repo.start(now: start.toLocal());

    await expectLater(
      repo.finish(
        now: start.add(const Duration(hours: 30)).toLocal(),
        quality: null,
      ),
      throwsA(isA<StateError>()),
    );

    expect(await database.allRecords(), isEmpty, reason: '越界时不得落库');
    expect(await repo.load(), isNotNull, reason: '会话要留给用户决定丢弃或补录');
  });

  /// 「点了开始就立刻点结束」：零时长同样不得变成一条记录。
  test('零时长的会话 finish 被拒，不写记录', () async {
    await repo.start(now: start.toLocal());

    await expectLater(
      repo.finish(now: start.toLocal(), quality: null),
      throwsA(isA<StateError>()),
    );

    expect(await database.allRecords(), isEmpty);
  });

  test('discard 只删会话行，不写记录', () async {
    await repo.start(now: start.toLocal());
    await repo.discard();

    expect(await repo.load(), isNull);
    expect(await database.allRecords(), isEmpty);
  });

  test('删除全部本地数据会清掉残留的会话', () async {
    await repo.start(now: start.toLocal());
    await database.deleteAllUserData();

    expect(await repo.load(), isNull);
  });

  test('重启后会话仍在（数据在库里，不靠内存）', () async {
    await repo.start(now: start.toLocal(), wakeMinutes: 6 * 60);

    final reopened = SessionRepository(database);
    expect((await reopened.load())!.wakeMinutes, 360);
  });

  test('场景 id 写进会话行，重开还在', () async {
    await repo.start(now: start.toLocal());
    await repo.update(sceneId: 'galaxy');

    expect((await repo.load())!.sceneId, 'galaxy');
  });

  test('不传 sceneId 时不动它；显式传 null 才清回默认', () async {
    await repo.start(now: start.toLocal());
    await repo.update(sceneId: 'ocean');

    // 改别的字段不该顺手把场景抹掉——`_unset` 哨兵存在的全部理由。
    await repo.update(alarmEnabled: true);
    expect((await repo.load())!.sceneId, 'ocean');

    await repo.update(sceneId: null);
    expect((await repo.load())!.sceneId, isNull);
  });
}
