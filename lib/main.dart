import 'dart:async';

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

  // **`runApp` 之前只留非等不可的东西。**
  //
  // 开库只是解析路径、准备执行器（实测 1ms），而 `databaseProvider` 必须被
  // override，所以它在。除此之外只剩演示数据（理由见下）。
  //
  // 两件曾经排在这里、现在都挪到开屏之后：
  //  * 读钥匙串 —— `flutter_secure_storage` 第一次读在小米 9 上要 ~860ms
  //    （Keystore 初始化），改由 `InsightApiKeyNotifier.load()` 在开屏播完后补读；
  //  * 时区表 + 通知调度器 —— `initializeTimeZones()` 是同步解析，会挡住建帧，
  //    改由 `_reconcileRemindersWhenReady` 在开屏播完后做。
  final database = await AppDatabase.open();
  final scheduler = LocalReminderScheduler();

  // 演示数据留在 `runApp` 之前：首页第一帧就要有内容可画，晚装会让开屏收起后
  // 先闪一下空状态。它只在 `DEMO_DATA` 打开的构建里真跑（默认等于 `kDebugMode`），
  // 实测 debug 下多花 ~130ms；release 构建在这里是立即返回。
  await installDemoSeedIfNeeded(
    database,
    enabled: AppConfig.demoDataEnabled,
  );

  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(database),
        reminderSchedulerProvider.overrideWithValue(scheduler),
      ],
      child: const NightSleepApp(),
    ),
  );

  // 首帧（开屏页）上屏之后再动下面这些。**必须等首帧**：它们要么占住 UI isolate
  // （`initializeTimeZones()`），要么占住平台线程，在 `runApp` 后面直接调同样会
  // 挡住建帧。
  WidgetsBinding.instance.addPostFrameCallback((_) {
    // 排通知不该挡着启动，失败也不该让应用起不来。
    unawaited(_reconcileRemindersWhenReady(database, scheduler));
  });
}

/// 开屏播完、等调度器初始化完再对账。
///
/// **顺序不能反**：`initialize()` 没跑完时 `permission()` 返回 `unsupported`，
/// 这一轮什么也排不上（原因见 `reconcileReminders` 里那段「只认 denied」）。
///
/// **也不能紧贴首帧做**：`initializeTimeZones()` 是同步解析，`getLocalTimezone()`
/// 与插件初始化是平台调用；debug 构建里这些代码的首次执行还要 JIT 编译。实测
/// 放在首帧后立刻跑，会把开屏 1.6 秒的入场动画卡住。等动画播完再排——提醒晚
/// 两秒与「开关开着却不响」无关。
Future<void> _reconcileRemindersWhenReady(
  AppDatabase database,
  ReminderScheduler scheduler,
) async {
  // 开屏 1.6s，留 200ms 余量。
  await Future<void>.delayed(const Duration(milliseconds: 1800));
  await scheduler.initialize();
  await reconcileReminders(database, scheduler);
}
