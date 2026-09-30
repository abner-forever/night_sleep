import 'package:drift/drift.dart' show Value;

import '../core/database/app_database.dart';
import '../core/platform/reminders.dart';

/// 由已存偏好构造调度计划。
///
/// 这条映射是一份**契约**：关掉的那一项必须是 `null`，`sync` 才会取消它。
/// 启动路径与设置页路径共用这一份——各写一遍的话，将来多一种提醒（或给时刻加个
/// 回退值）时漏改一处，症状就是「开关开着却不响」，正是这个功能要消灭的那类 bug。
///
/// 放在 `app/` 而不是 `core/platform/reminders.dart`：那个文件属于平台层，
/// 不该认识数据库的行类型。
ReminderPlan reminderPlanFrom(AppSetting settings) => ReminderPlan(
      bedtimeMinutes: settings.bedtimeReminderEnabled
          ? settings.bedtimeReminderMinutes
          : null,
      wakeMinutes:
          settings.wakeReminderEnabled ? settings.wakeReminderMinutes : null,
    );

/// 让已调度的通知与数据库里的偏好保持一致。每次启动都跑。
///
/// 有两件事会脱节：改时区或系统清理会让已排的调度悄悄消失；而用户在系统设置里
/// 撤销授权后，偏好仍然写着「开」却再也响不了。后一种在这里被**修好**而不是仅仅
/// 显示出来——设置页因此永远不会出现一个说谎的开关。
///
/// 顶层函数而不是 `main()` 里的私有实现：下面三个分支里，「`unsupported` 时不动偏好」
/// 守着的是「一次偶发的时区查询失败不该清空用户设置」，值得有测试盯着。
Future<void> reconcileReminders(
  AppDatabase database,
  ReminderScheduler scheduler,
) async {
  try {
    final stored = await database.getSettings();
    final wantsBedtime = stored.bedtimeReminderEnabled;
    final wantsWake = stored.wakeReminderEnabled;
    final permission = await scheduler.permission();

    // **只认 `denied`，不写 `!= granted`。**
    //
    // `unsupported` 的含义是「本设备此刻安排不了」，它可能只是一次偶发的时区查询
    // 失败——`initialize()` 是刻意做成可重试的正是为了这种情况。把它也当成「用户
    // 撤销了授权」，就会在启动路径上**把用户的提醒偏好清空**，而用户完全看不见：
    // 下次启动时区好了，偏好已经没了。
    //
    // `denied` 才是「系统明确说了不行」。而偏好为真只可能来自一次成功授权，
    // 所以那才是「用户在应用之外撤销了授权」。
    if (permission == ReminderPermission.denied &&
        (wantsBedtime || wantsWake)) {
      await database.updateSettings(
        const AppSettingsCompanion(
          bedtimeReminderEnabled: Value(false),
          wakeReminderEnabled: Value(false),
        ),
      );
      // 空计划：两个开关刚被写回 false，9001/9002 都要排掉。
      // 这一条**不能**只调 `syncSessionAlarm`——它不会把 9002 排回来（见下）。
      await syncAllReminders(database, scheduler, plan: const ReminderPlan());
      return;
    }

    await syncAllReminders(database, scheduler);
  } catch (_) {
    // 调度是尽力而为：排不上提醒不该影响任何别的功能。
  }
}

/// 一次性把两类提醒都推到系统里：日常提醒（9001/9002）+ 会话闹钟（9003）。
///
/// **这两步必须成对。** [syncSessionAlarm] 是不对称的：它能让 9002 让位，
/// 却永远不会把 9002 排回来——单独调它会让「会话闹钟关掉之后、日常起床
/// 提醒也不响」，而那和「开关开着却不响」是同一类缺陷。
///
/// 收成一个函数而不是靠注释提醒调用方「记得先调 [ReminderScheduler.sync]」：
/// 顺序与配对是结构性的事实，写成约定就一定会有一条路径漏掉它。
///
/// [plan] 给「偏好刚被改写、`stored` 已经过期」的调用方用（比如权限被撤销那条
/// 分支要的是空计划）；不给则按库里当前偏好推导。
Future<void> syncAllReminders(
  AppDatabase database,
  ReminderScheduler scheduler, {
  ReminderPlan? plan,
}) async {
  final stored = await database.getSettings();
  await scheduler.sync(plan ?? reminderPlanFrom(stored));
  await syncSessionAlarm(database, scheduler);
}

/// 让**会话闹钟**与「今晚有没有会话、闹钟开着没」保持一致。
///
/// 与 [reconcileReminders] 里那套日常提醒**分开推导**，因为两者的生命周期不同：
/// 日常提醒由偏好驱动，会话闹钟由「今晚有没有会话」驱动。
/// 但推导只有这一处。
Future<void> syncSessionAlarm(
  AppDatabase database,
  ReminderScheduler scheduler,
) async {
  final session = await database.activeSession();

  if (session != null && session.alarmEnabled) {
    // **今晚的闹钟胜过日常起床提醒。** 两者很容易被设成同一个钟点，排在一起
    // 用户会在同一分钟收到两条通知。起床提醒说的是「记录一下昨晚」，而这件事
    // 会话已经替你做了。就寝提醒不受影响——「该睡了」与闹钟无关。
    await scheduler.yieldWakeReminder();
    await scheduler.syncAlarm(
      ReminderRequest(
        id: ReminderScheduler.wakeAlarmId,
        // **起床时间就是闹钟时间**，会话页上没有第二个钟点。
        minutesOfDay: session.wakeMinutes,
        title: ReminderScheduler.wakeAlarmTitle,
        body: ReminderScheduler.wakeAlarmBody,
      ),
    );
    return;
  }

  // 没有会话（或闹钟关着）时把闹钟排掉，日常提醒照常。
  await scheduler.syncAlarm(null);
}
