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

  final start = DateTime.utc(2026, 8, 30, 15, 14); // 本地 23:14（CST）
  final end = DateTime.utc(2026, 8, 30, 23, 2); // 本地 07:02

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
    // `isAtSameMomentAs`, not `==`: drift hands back a DateTime flagged local,
    // and `==` also compares that flag. What must survive the round trip is the
    // instant — `SleepSession` 会把标记摆正，但这里是直接读的原始行。
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
}
