import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/config/app_config.dart';
import 'core/database/app_database.dart';
import 'core/platform/reminders.dart';
import 'features/sleep/data/demo_seed.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final database = await AppDatabase.open();
  final scheduler = LocalReminderScheduler();
  await scheduler.initialize();

  // Demo rows are installed once, and only in builds where the flag is on.
  //
  // The condition is "no demo rows yet" rather than "the table is empty", so
  // turning the flag on later actually takes effect. Existing real records are
  // never touched: demo rows carry `source = 'demo'`, the UI badges them, and
  // `deleteDemoData` removes only those rows.
  if (AppConfig.demoDataEnabled) {
    final existing = await database.allRecords();
    final hasDemo = existing.any((row) => row.source == AppConfig.demoSource);
    if (!hasDemo) {
      await DemoSeed.install(database);
    }
  }

  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(database),
        reminderSchedulerProvider.overrideWithValue(scheduler),
      ],
      child: const NightSleepApp(),
    ),
  );

  // 排通知不该挡着启动，失败也不该让应用起不来。
  unawaited(_reconcileReminders(database, scheduler));
}

/// 让已调度的通知与数据库里的偏好保持一致。每次启动都跑。
///
/// 有两件事会脱节：改时区或系统清理会让已排的调度悄悄消失；而用户在系统设置里
/// 撤销授权后，偏好仍然写着「开」却再也响不了。后一种在这里被**修好**而不是仅仅
/// 显示出来——设置页因此永远不会出现一个说谎的开关。
Future<void> _reconcileReminders(
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

    await scheduler.sync(
      ReminderPlan(
        bedtimeMinutes: wantsBedtime ? stored.bedtimeReminderMinutes : null,
        wakeMinutes: wantsWake ? stored.wakeReminderMinutes : null,
      ),
    );
  } catch (_) {
    // 调度是尽力而为：排不上提醒不该影响任何别的功能。
  }
}
