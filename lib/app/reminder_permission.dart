import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/platform/reminders.dart';
import 'app_toast.dart';

/// 系统通知权限的最近一次观测结果。
///
/// 插件分不清「从未询问」与「已被拒绝」——两者都返回 `isEnabled: false`——
/// 所以界面也不去分。只要不是 granted，就说明提醒此刻响不了。
final reminderPermissionProvider = FutureProvider<ReminderPermission>((ref) {
  return ref.watch(reminderSchedulerProvider).permission();
});

/// 打开提醒类开关前的**权限闸口**。
///
/// 返回 `true` 表示可以继续写入偏好；`false` 表示被拒或平台安排不了——此时已经
/// 弹过说明、已让权限观测失效，调用方**不要再落库**，让开关自己弹回去。
///
/// 设置页与会话页的起床闹钟共用它。这三步（申请 → 被拒则弹说明 + 失效观测 →
/// 不落库）各写一遍的话，两边会慢慢分叉，而「开关写着开却不会响」正是这个功能
/// 要消灭的假状态。
///
/// [target] 是被宾语化的开关名（「提醒」/「闹钟」），让同一句话在两处都说得通。
Future<bool> ensureNotificationPermission(
  BuildContext context,
  WidgetRef ref, {
  required String target,
}) async {
  final permission =
      await ref.read(reminderSchedulerProvider).requestPermission();
  if (permission == ReminderPermission.granted) return true;
  if (!context.mounted) return false;

  // 这里不说「这个平台不支持」：走到这一步也可能是**这台设备上**取不到可用
  // 时区导致的初始化失败，那是应用侧的问题，不是平台的限制。两种情况都成立的
  // 实话是「当前设备无法安排本地通知」。
  ref.read(toastProvider.notifier).show(
        permission == ReminderPermission.unsupported
            ? '当前设备无法安排本地通知，$target未开启。'
            : '没有获得通知权限，$target未开启。可在系统设置中允许「夜深」发送通知。',
      );
  ref.invalidate(reminderPermissionProvider);
  return false;
}
