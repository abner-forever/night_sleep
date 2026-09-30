import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/core/platform/reminders.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// 调度契约的单元测试。
///
/// `sync` 的算法放在基类里，子类只提供 `cancel` / `schedule` 两个原子动作，
/// 所以这里能用一个记录调用序列的假子类**测到真代码**，而不必碰平台通道。
class _RecordingScheduler extends ReminderScheduler {
  final calls = <String>[];

  @override
  Future<void> initialize() async {}

  @override
  Future<ReminderPermission> permission() async => ReminderPermission.granted;

  @override
  Future<ReminderPermission> requestPermission() async =>
      ReminderPermission.granted;

  @override
  Future<void> openSystemSettings() async {}

  @override
  Future<void> cancel(int id) async => calls.add('cancel:$id');

  @override
  Future<void> schedule(ReminderRequest request) async =>
      calls.add('schedule:${request.id}@${request.minutesOfDay}');

  @override
  Future<void> scheduleOnce(ReminderRequest request) async =>
      calls.add('scheduleOnce:${request.id}@${request.minutesOfDay}');
}

void main() {
  // 时区数据库必须在这里就绪，不能等 `setUpAll`：`group` 的回调体是在**收集阶段**
  // 执行的，早于任何 `setUpAll`，而下面 group 体里就要调 `tz.getLocation`。
  tzdata.initializeTimeZones();

  test('两个通知 id 固定，便于整组替换', () {
    expect(ReminderScheduler.bedtimeId, 9001);
    expect(ReminderScheduler.wakeId, 9002);
  });

  test('requestsFor 只把开着的提醒变成请求', () {
    expect(ReminderScheduler.requestsFor(const ReminderPlan()), isEmpty);

    final bedtime = ReminderScheduler.requestsFor(
      const ReminderPlan(bedtimeMinutes: 22 * 60 + 30),
    );
    expect(bedtime, hasLength(1));
    expect(bedtime.single.id, ReminderScheduler.bedtimeId);
    expect(bedtime.single.hour, 22);
    expect(bedtime.single.minute, 30);
  });

  test('sync 先取消两个固定 id 再按计划排入', () async {
    final scheduler = _RecordingScheduler();
    await scheduler.sync(const ReminderPlan(bedtimeMinutes: 22 * 60 + 30));

    // 即使只开了一个提醒，两个 id 都要取消——否则关掉的那一个会留在系统里。
    expect(
        scheduler.calls, ['cancel:9001', 'cancel:9002', 'schedule:9001@1350']);
  });

  test('sync 是幂等的：连跑两次产生相同的序列', () async {
    final scheduler = _RecordingScheduler();
    const plan = ReminderPlan(bedtimeMinutes: 1350, wakeMinutes: 420);

    await scheduler.sync(plan);
    final first = List.of(scheduler.calls);
    await scheduler.sync(plan);

    expect(scheduler.calls.sublist(first.length), first,
        reason: '第二次调用必须与第一次完全一致');
    expect(first, [
      'cancel:9001',
      'cancel:9002',
      'schedule:9001@1350',
      'schedule:9002@420',
    ]);
  });

  test('空计划只取消，不排任何东西', () async {
    final scheduler = _RecordingScheduler();
    await scheduler.sync(const ReminderPlan());

    expect(scheduler.calls, ['cancel:9001', 'cancel:9002']);
  });

  test('NoopReminderScheduler 如实报告不支持', () async {
    final scheduler = NoopReminderScheduler();
    await scheduler.initialize();

    expect(await scheduler.permission(), ReminderPermission.unsupported);
    expect(
      await scheduler.requestPermission(),
      ReminderPermission.unsupported,
      reason: '不能假装权限拿到了',
    );
  });

  test('通知文案是规格钉死的那四句', () {
    final requests = ReminderScheduler.requestsFor(
      const ReminderPlan(bedtimeMinutes: 22 * 60 + 30, wakeMinutes: 7 * 60),
    );

    expect(
        requests.map((request) => request.title).toList(), ['到就寝时间了', '早上好']);
    expect(requests.map((request) => request.body).toList(),
        ['该休息了，晚安。', '记录一下昨晚睡得怎么样。']);
  });

  group('起床闹钟', () {
    test('syncAlarm 传 null 时只取消，不排', () async {
      final scheduler = _RecordingScheduler();
      await scheduler.syncAlarm(null);

      expect(scheduler.calls, ['cancel:9003']);
    });

    test('syncAlarm 排出 9003，且走的是一次性通道', () async {
      final scheduler = _RecordingScheduler();
      await scheduler.syncAlarm(
        const ReminderRequest(
          id: ReminderScheduler.wakeAlarmId,
          minutesOfDay: 7 * 60,
          title: ReminderScheduler.wakeAlarmTitle,
          body: ReminderScheduler.wakeAlarmBody,
        ),
      );

      // **必须是 `scheduleOnce` 而不是 `schedule`**：后者写死了
      // `matchDateTimeComponents.time`，那是每天重复。
      expect(scheduler.calls, ['cancel:9003', 'scheduleOnce:9003@420']);
    });

    /// 这一条是整个闹钟设计里最关键的反向护栏。
    test('日常提醒的 sync 不会碰 9003', () async {
      final scheduler = _RecordingScheduler();
      await scheduler.sync(const ReminderPlan(bedtimeMinutes: 22 * 60 + 30));

      expect(
        scheduler.calls.where((call) => call.contains('9003')),
        isEmpty,
        reason: 'sync 若取消 9003，每次启动的全量重排都会把会话闹钟抹掉',
      );
    });
  });

  group('nextOccurrence', () {
    final ny = tz.getLocation('America/New_York');
    final shanghai = tz.getLocation('Asia/Shanghai');

    final wake = ReminderScheduler.requestsFor(
      const ReminderPlan(wakeMinutes: 7 * 60),
    ).single;

    test('当天该时刻还没到时，就排在当天', () {
      final next = LocalReminderScheduler.nextOccurrence(
        wake,
        now: tz.TZDateTime(shanghai, 2026, 9, 28, 3),
      );

      expect(next, tz.TZDateTime(shanghai, 2026, 9, 28, 7));
    });

    test('当天该时刻已过时，排到第二天', () {
      final next = LocalReminderScheduler.nextOccurrence(
        wake,
        now: tz.TZDateTime(shanghai, 2026, 9, 28, 9),
      );

      expect(next, tz.TZDateTime(shanghai, 2026, 9, 29, 7));
    });

    test('跨夏令时切换日，仍落在同一墙上时刻而不是绝对时刻加 24 小时', () {
      // 美国 2026 年春季切换在 3 月 8 日 02:00 → 03:00。
      // 3 月 7 日 23:00 已过 07:00，所以下一次是 3 月 8 日。
      //
      // 若把「重建墙钟时刻」错写成「today.add(Duration(days: 1))」，
      // 结果会是 3 月 8 日 08:00（EST 07:00 的绝对时刻 +24h 落在 EDT 上），
      // 这条断言会红——这正是它是可证伪的、而不是在复述实现的原因。
      final next = LocalReminderScheduler.nextOccurrence(
        wake,
        now: tz.TZDateTime(ny, 2026, 3, 7, 23),
      );

      expect(next.year, 2026);
      expect(next.month, 3);
      expect(next.day, 8);
      expect(next.hour, 7, reason: '墙上时刻必须还是 07:00');
    });
  });
}
