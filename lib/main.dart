import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/reminder_sync.dart';
import 'core/config/app_config.dart';
import 'core/database/app_database.dart';
import 'core/platform/reminders.dart';
import 'features/sleep/data/demo_seed.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final database = await AppDatabase.open();
  final scheduler = LocalReminderScheduler();
  await scheduler.initialize();

  // 演示数据只装一次，且只在开关打开的构建里。
  //
  // 判据是「还没有演示行」而不是「表是空的」，这样后开开关才真的生效。
  // 已有的真实记录一律不碰：演示行带 `source = 'demo'`，界面会标注它们，
  // 而 `deleteDemoData` 只删这些行。
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
        // Web 不能走这条：`defaultTargetPlatform` 在 Web 上报告的是**宿主操作系统**，
        // 所以 `reminderSchedulerProvider` 自己的 `kIsWeb` 守卫会被这个 override 绕过。
        reminderSchedulerProvider.overrideWithValue(
          kIsWeb ? NoopReminderScheduler() : scheduler,
        ),
      ],
      child: const NightSleepApp(),
    ),
  );

  // 排通知不该挡着启动，失败也不该让应用起不来。
  unawaited(reconcileReminders(database, scheduler));
}
