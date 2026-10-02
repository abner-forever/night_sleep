import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/database/app_database.dart';
import '../core/platform/reminders.dart';
import 'noise_session.dart';
import 'reminder_sync.dart';

/// 收尾一个（可能已经不存在的）睡眠会话：停白噪音 + 重新推导两类提醒。
///
/// **三条出口共用这一份**：会话结束（记录落库后）、丢弃、以及「删除全部本地数据」。
/// 各写一遍时，凡是只想到一条路径的改动都会让另一条悄悄退化——丢弃与「删除全部
/// 本地数据」先前就漏了闹钟重排，于是一个已经不存在的会话会留着 9003，日常起床
/// 提醒 9002 还继续被压着，直到下次冷启动才恢复。这正是 `reminder_sync.dart` 里
/// 那条规则要防的失败类。
///
/// 每一步都是**尽力而为**，而且各自独立 try：这两个动作都不该有能力挡住用户可见的
/// 收尾（toast / 切 Tab / 回首页）。`LocalReminderScheduler` 调平台插件时没有护栏，
/// `PlatformException` 是真会抛的；记录早已落库，为它把用户卡在一个已经没有会话的
/// 页面上，是用一个装饰性的失败换掉了整个反馈。分开 try 是因为失败模式互不相关：
/// 停不掉声音最坏多响一会儿，撤不掉通知最坏多响一次（9003 是一次性通知，响过就没了）。
Future<void> teardownSession(WidgetRef ref) async {
  try {
    await ref.read(noiseSessionControllerProvider).stop();
  } catch (_) {
    // 声音停不掉不影响下面的闹钟与跳转。
  }

  // **取消通知排在事务之后。** 顺序不能反：先撤通知再写库，一旦写库失败，
  // 用户就得到「闹钟没了、记录也没有」的最坏组合。
  //
  // 走 [syncAllReminders] 而不是只调 `syncSessionAlarm`：后者不对称——能让
  // 日常起床提醒 9002 让位，却永远不会把 9002 排回来。
  try {
    await syncAllReminders(
      ref.read(databaseProvider),
      ref.read(reminderSchedulerProvider),
    );
  } catch (_) {
    // 排不上/撤不掉提醒是多响一次或少响一次，不该吃掉用户可见的收尾。
  }
}
