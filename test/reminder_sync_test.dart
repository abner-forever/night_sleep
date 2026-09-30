import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/app/reminder_sync.dart';
import 'package:night_sleep/core/database/app_database.dart';
import 'package:night_sleep/core/platform/reminders.dart';

/// 权限固定的假调度器：只回答「现在是几点权限」，并记录收到过什么计划。
class _FakeScheduler extends ReminderScheduler {
  _FakeScheduler(this._current);

  final ReminderPermission _current;
  ReminderPlan? lastSynced;

  /// 会话闹钟最近一次被设成什么（`null` = 被排掉了）。
  ReminderRequest? lastAlarm;

  /// 日常起床提醒被显式让位过几次。
  final yieldedWake = <int>[];

  /// `cancel` 收到过的 id，按序。让「就寝提醒没被碰」这类断言有落点。
  final cancelled = <int>[];

  @override
  Future<void> initialize() async {}

  @override
  Future<ReminderPermission> permission() async => _current;

  @override
  Future<ReminderPermission> requestPermission() async => _current;

  @override
  Future<void> openSystemSettings() async {}

  @override
  Future<void> cancel(int id) async => cancelled.add(id);

  @override
  Future<void> schedule(ReminderRequest request) async {}

  @override
  Future<void> scheduleOnce(ReminderRequest request) async =>
      lastAlarm = request;

  @override
  Future<void> sync(ReminderPlan plan) async => lastSynced = plan;

  /// 记录之外**还走一遍基类**：这样「取消 9003」与「就寝提醒没被碰」是在真代码上
  /// 断言的，而不是在假实现上空转。
  @override
  Future<void> syncAlarm(ReminderRequest? request) async {
    await super.syncAlarm(request);
    lastAlarm = request;
  }

  @override
  Future<void> yieldWakeReminder() async {
    yieldedWake.add(ReminderScheduler.wakeId);
    await super.yieldWakeReminder();
  }
}

void main() {
  late AppDatabase database;

  setUp(() => database = AppDatabase(NativeDatabase.memory()));
  tearDown(() => database.close());

  /// 造一条「两项提醒都开着」的偏好。
  Future<void> seedBothOn() async {
    await database.updateSettings(
      const AppSettingsCompanion(
        bedtimeReminderEnabled: Value(true),
        bedtimeReminderMinutes: Value(22 * 60 + 30),
        wakeReminderEnabled: Value(true),
        wakeReminderMinutes: Value(7 * 60),
      ),
    );
  }

  test('权限为 granted 时按偏好重排', () async {
    await seedBothOn();
    final scheduler = _FakeScheduler(ReminderPermission.granted);

    await reconcileReminders(database, scheduler);

    expect(scheduler.lastSynced?.bedtimeMinutes, 22 * 60 + 30);
    expect(scheduler.lastSynced?.wakeMinutes, 7 * 60);
    expect((await database.getSettings()).bedtimeReminderEnabled, isTrue,
        reason: '权限正常时不该动偏好');
  });

  test('权限为 denied 时回收偏好并清空计划', () async {
    await seedBothOn();
    final scheduler = _FakeScheduler(ReminderPermission.denied);

    await reconcileReminders(database, scheduler);

    final row = await database.getSettings();
    expect(row.bedtimeReminderEnabled, isFalse, reason: '撤销授权后不该留一个说谎的开关');
    expect(row.wakeReminderEnabled, isFalse);
    expect(scheduler.lastSynced?.isEmpty, isTrue, reason: '已排的通知必须取消掉');
  });

  test('权限为 unsupported 时**不动**偏好', () async {
    // 这是本任务修掉的那个 bug 的回归守卫：`unsupported` 可能只是一次偶发的时区
    // 查询失败，把它当成「用户撤销了授权」会在启动路径上静默清空用户的提醒设置。
    // 把 `reconcileReminders` 的条件改回 `!= granted` 就会让这条变红。
    await seedBothOn();
    final scheduler = _FakeScheduler(ReminderPermission.unsupported);

    await reconcileReminders(database, scheduler);

    final row = await database.getSettings();
    expect(row.bedtimeReminderEnabled, isTrue);
    expect(row.bedtimeReminderMinutes, 22 * 60 + 30,
        reason: '偶发的时区失败不该毁掉用户存过的时刻');
    expect(row.wakeReminderEnabled, isTrue);
  });

  group('会话闹钟', () {
    Future<void> seedActiveSession({bool alarmEnabled = false}) {
      return database.saveActiveSession(
        ActiveSessionsCompanion.insert(
          // 非空且无默认值的列收裸值，可空或有默认值的列收 `Value<T>`：
          // `id` / `startAtUtc` / `wakeMinutes` / `createdAt` 都是裸值，
          // `alarmEnabled` 有默认值才是 `Value`。
          id: 'active',
          startAtUtc: DateTime.utc(2026, 8, 30, 15, 14),
          wakeMinutes: 420,
          alarmEnabled: Value(alarmEnabled),
          createdAt: DateTime.utc(2026, 8, 30, 15, 14),
        ),
      );
    }

    test('有会话且闹钟开着：排出 9003，并让日常起床提醒让位', () async {
      await seedActiveSession(alarmEnabled: true);
      await seedBothOn();

      final scheduler = _FakeScheduler(ReminderPermission.granted);
      await reconcileReminders(database, scheduler);

      expect(scheduler.lastAlarm, isNotNull);
      expect(scheduler.lastAlarm!.id, ReminderScheduler.wakeAlarmId);
      expect(scheduler.lastAlarm!.minutesOfDay, 420);
      expect(
        scheduler.yieldedWake,
        contains(ReminderScheduler.wakeId),
        reason: '两者很容易被设成同一个钟点，会响两条',
      );
    });

    test('没有会话：闹钟被排掉，日常提醒照常', () async {
      await seedBothOn();

      final scheduler = _FakeScheduler(ReminderPermission.granted);
      await reconcileReminders(database, scheduler);

      // 这里**不写** `expect(lastAlarm, isNull)`：`lastAlarm` 的初值就是 `null`，
      // 那样一条断言在任何实现下都过得去，只会让人以为「9003 被排掉了」这件事
      // 被守住了。真正载重的是下面这条——它要求 `syncAlarm(null)` 真被调用过。
      expect(scheduler.cancelled, contains(ReminderScheduler.wakeAlarmId),
          reason: '没有会话时必须把可能残留的 9003 排掉');
      expect(scheduler.yieldedWake, isEmpty);
      expect(scheduler.lastSynced!.wakeMinutes, 7 * 60);
    });

    test('有会话但闹钟关着：闹钟排掉，9002 不让位', () async {
      await seedActiveSession();
      await seedBothOn();

      final scheduler = _FakeScheduler(ReminderPermission.granted);
      await reconcileReminders(database, scheduler);

      // 同上：不写 `lastAlarm` 的 `isNull`，它抓不到「没调用」。
      expect(scheduler.cancelled, contains(ReminderScheduler.wakeAlarmId),
          reason: '闹钟关着时也要把 9003 排掉，理由同上一条');
      expect(scheduler.yieldedWake, isEmpty);
      expect(scheduler.lastSynced!.wakeMinutes, 7 * 60);
    });

    /// 规格 §五：闹钟让位只针对**起床**提醒。
    test('闹钟开着也只让起床提醒，就寝提醒 9001 不被碰', () async {
      await seedActiveSession(alarmEnabled: true);
      await seedBothOn();

      final scheduler = _FakeScheduler(ReminderPermission.granted);
      await syncSessionAlarm(database, scheduler);

      expect(
        scheduler.cancelled,
        isNot(contains(ReminderScheduler.bedtimeId)),
        reason: '「该睡了」与今晚设没设闹钟无关，不该被会话闹钟顺手取消',
      );
      expect(scheduler.cancelled, contains(ReminderScheduler.wakeId),
          reason: '起床提醒让位给闹钟');
      expect(scheduler.cancelled, contains(ReminderScheduler.wakeAlarmId),
          reason: '9003 先取消再排，幂等');
    });

    /// 权限被撤销时 `reconcileReminders` 会在回收偏好后提前 `return`——那条路径
    /// 上也要推导一次会话闹钟，否则上一晚残留在系统里的 9003 再也排不掉：那条
    /// `return` 之后的正常尾部**不会**执行。
    test('权限被撤销：残留的 9003 一样被排掉', () async {
      await seedBothOn();

      final scheduler = _FakeScheduler(ReminderPermission.denied);
      await reconcileReminders(database, scheduler);

      expect(scheduler.cancelled, contains(ReminderScheduler.wakeAlarmId),
          reason: '提前 return 前跳过 syncSessionAlarm 的话，残留的 9003 会留在系统里');
      // 同上：不写 `lastAlarm` 的 `isNull`，它抓不到「没调用」。
    });

    /// **对称性的反向护栏。** [syncSessionAlarm] 是不对称的：它能让 9002 让位，
    /// 却永远不会把 9002 排回来。所以它与 `sync` 必须成对——那一对现在收在
    /// `syncAllReminders` 里。少了 `sync` 这一步，用户在关掉会话闹钟之后会落到
    /// 「闹钟关了、日常起床提醒也不响」，与「开关开着却不响」是同一类缺陷。
    test('会话闹钟关掉后再同步：9002 被排回来', () async {
      await seedActiveSession(alarmEnabled: true);
      await seedBothOn();

      final scheduler = _FakeScheduler(ReminderPermission.granted);
      await syncAllReminders(database, scheduler);
      expect(scheduler.yieldedWake, contains(ReminderScheduler.wakeId),
          reason: '前提：闹钟开着时 9002 已让位');
      expect(scheduler.lastAlarm, isNotNull, reason: '前提：9003 已排上');

      // 用户在会话页把闹钟关掉。
      await database.updateActiveSession(
        const ActiveSessionsCompanion(alarmEnabled: Value(false)),
      );

      // 只看第二次同步的结果，先把上一次的观测清掉。
      // `lastSynced` 必须清：不清的话它仍留着第一次的计划，
      // 「`sync` 这一步被删掉」就断不出来了。
      scheduler.lastSynced = null;
      scheduler.yieldedWake.clear();

      await syncAllReminders(database, scheduler);

      expect(scheduler.yieldedWake, isEmpty, reason: '闹钟关了就不该再让位');
      expect(scheduler.lastSynced, isNotNull,
          reason: '`syncSessionAlarm` 单独一步排不回 9002，必须先走一遍日常提醒那次 sync');
      expect(scheduler.lastSynced!.wakeMinutes, 7 * 60,
          reason: '9002 必须被排回来，否则用户落到「闹钟关了、起床提醒也不响」');
    });
  });
}
