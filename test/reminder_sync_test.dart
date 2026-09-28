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

  @override
  Future<void> initialize() async {}

  @override
  Future<ReminderPermission> permission() async => _current;

  @override
  Future<ReminderPermission> requestPermission() async => _current;

  @override
  Future<void> openSystemSettings() async {}

  @override
  Future<void> cancel(int id) async {}

  @override
  Future<void> schedule(ReminderRequest request) async {}

  @override
  Future<void> sync(ReminderPlan plan) async => lastSynced = plan;
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
}
