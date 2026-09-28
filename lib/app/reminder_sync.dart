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
      await scheduler.sync(const ReminderPlan());
      return;
    }

    await scheduler.sync(reminderPlanFrom(stored));
  } catch (_) {
    // 调度是尽力而为：排不上提醒不该影响任何别的功能。
  }
}
