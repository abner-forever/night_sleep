import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/reminder_sync.dart';
import 'core/config/app_config.dart';
import 'core/database/app_database.dart';
import 'core/platform/reminders.dart';
import 'features/settings/data/insight_credentials.dart';
import 'features/sleep/data/demo_seed.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final database = await AppDatabase.open();
  final scheduler = LocalReminderScheduler();
  await scheduler.initialize();

  // 演示数据只装一次，且只在开关打开的构建里。判断依据、以及「失败也不许把应用
  // 带下水」的兜底都在 `installDemoSeedIfNeeded` 里——那条路径需要有测试盯着，
  // 而 `main()` 在测试里跑不起来，所以它必须待在能被单独调用的地方。
  await installDemoSeedIfNeeded(
    database,
    enabled: AppConfig.demoDataEnabled,
  );

  // 密钥在钥匙串里，启动时读一次。**必须在这里 await**，不能让 provider 自己
  // 异步补：那会留下一个「输入框先空一下」的窗口（详见 `insightApiKeySeedProvider`）。
  // `read()` 内部把「读不到」和「没有」归成同一个结果，所以这里不会把启动带下水。
  final insightApiKey = (await const SecureInsightKeyStore().read()) ?? '';

  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(database),
        insightApiKeySeedProvider.overrideWithValue(insightApiKey),
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
