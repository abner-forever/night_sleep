import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// 系统是否真的会投递通知。
enum ReminderPermission { granted, denied, unsupported }

/// 用户当前想要的提醒。`null` 表示该项关闭。
class ReminderPlan {
  const ReminderPlan({this.bedtimeMinutes, this.wakeMinutes});

  /// 距本地午夜的分钟数。
  final int? bedtimeMinutes;
  final int? wakeMinutes;

  bool get isEmpty => bedtimeMinutes == null && wakeMinutes == null;
}

/// 调度器当前应当持有的一条通知。
class ReminderRequest {
  const ReminderRequest({
    required this.id,
    required this.minutesOfDay,
    required this.title,
    required this.body,
  });

  final int id;

  /// 距本地午夜的分钟数。
  final int minutesOfDay;
  final String title;
  final String body;

  int get hour => minutesOfDay ~/ 60;
  int get minute => minutesOfDay % 60;
}

/// 设备 IANA 时区名的来源。
///
/// 留一个接缝：`flutter_timezone` 是插件，而 `tz.local` 必须设对，
/// 否则每天重复的提醒会在夏令时切换后整体漂一小时。
abstract interface class TimezoneResolver {
  Future<String> identifier();
}

class SystemTimezone implements TimezoneResolver {
  const SystemTimezone();

  @override
  Future<String> identifier() async =>
      (await FlutterTimezone.getLocalTimezone()).identifier;
}

/// 就寝/起床提醒的调度。
///
/// `sync` 的**幂等全量重排**算法写在基类里，子类只提供 [cancel] 与 [schedule]
/// 两个原子动作——这样调度契约能在纯 Dart 测试里断言，不必碰平台通道。
abstract class ReminderScheduler {
  /// 固定的通知 id。[sync] 靠它们整组替换，陈旧调度因此活不过一次设置变更。
  static const bedtimeId = 9001;
  static const wakeId = 9002;

  /// 睡眠会话的起床闹钟。**与上面两个分开**，因为它是一次性的，不是每天重复。
  static const wakeAlarmId = 9003;

  static const wakeAlarmTitle = '该起床了';
  static const wakeAlarmBody = '结束睡眠，记录一下昨晚睡得怎么样。';

  /// 界面上关于**投递强度**的如实标注（规格 §五）。
  ///
  /// 只留这一份字面量：会话页收合态的胶囊与会话页抽屉里的闹钟行各引用它一次。
  /// 抄成两份的话，改一处忘一处，总有一处会在该说的时候不说——那正是这个功能
  /// 最不能有的失败形态。
  static const wakeAlarmDeliveryNote = '由系统通知投递；休眠模式下可能晚几分钟，强度不如系统闹钟。';

  static const bedtimeTitle = '到就寝时间了';
  static const bedtimeBody = '该休息了，晚安。';
  static const wakeTitle = '早上好';
  static const wakeBody = '记录一下昨晚睡得怎么样。';

  /// [plan] 要求存在的那组通知。纯函数，因此调度契约可单测。
  static List<ReminderRequest> requestsFor(ReminderPlan plan) => [
        if (plan.bedtimeMinutes != null)
          ReminderRequest(
            id: bedtimeId,
            minutesOfDay: plan.bedtimeMinutes!,
            title: bedtimeTitle,
            body: bedtimeBody,
          ),
        if (plan.wakeMinutes != null)
          ReminderRequest(
            id: wakeId,
            minutesOfDay: plan.wakeMinutes!,
            title: wakeTitle,
            body: wakeBody,
          ),
      ];

  Future<void> initialize();
  Future<ReminderPermission> permission();
  Future<ReminderPermission> requestPermission();
  Future<void> openSystemSettings();

  @protected
  Future<void> cancel(int id);

  @protected
  Future<void> schedule(ReminderRequest request);

  /// 在**下一个** [request] 的墙上时刻响一次，**不重复**。
  ///
  /// 与 [schedule] 的区别只在这一点上，但这一点是本质的：`schedule` 写死了
  /// `matchDateTimeComponents: DateTimeComponents.time`，那是每天都响。
  @protected
  Future<void> scheduleOnce(ReminderRequest request);

  /// 幂等的全量重排：先取消两个固定 id，再按计划排入。
  ///
  /// 用「先取消再新建」而不是「算差异」：否则调度器的内容与数据库里的偏好会各自
  /// 拥有独立生命周期——改时区、重启、系统清理、重装都能让两者脱节——而
  /// 「开关开着却什么都不会响」是这一块最难查的 bug。少一个生命周期，
  /// 就少一整类 bug。
  Future<void> sync(ReminderPlan plan) async {
    await cancel(bedtimeId);
    await cancel(wakeId);
    for (final request in requestsFor(plan)) {
      await schedule(request);
    }
  }

  /// 让闹钟与「今晚有没有会话、闹钟开着没」保持一致。幂等。
  ///
  /// 与 [sync] 一样是「先取消再排」：调度与偏好不能各自拥有独立生命周期。
  /// 但**两者互不干涉**——[sync] 只动 9001/9002，本方法只动 9003。
  Future<void> syncAlarm(ReminderRequest? request) async {
    await cancel(wakeAlarmId);
    if (request != null) {
      await scheduleOnce(request);
    }
  }

  /// 会话闹钟要占用起床这个钟点时，把**日常起床提醒**让出去。
  ///
  /// 做成独立方法而不是让调用方直接 `cancel(wakeId)`：`cancel` 是 `@protected`
  /// 的调度原语，让外部按 id 去取消，等于把「哪些 id 属于谁」的知识漏到调度器
  /// 之外；而且那样一行 `cancel` 是个**猜不出意图的副作用**，测试只能去数调用。
  Future<void> yieldWakeReminder() => cancel(wakeId);
}

/// 没有通知能力的平台（Web）与测试用的空实现。
class NoopReminderScheduler extends ReminderScheduler {
  @override
  Future<void> initialize() async {}

  @override
  Future<ReminderPermission> permission() async =>
      ReminderPermission.unsupported;

  @override
  Future<ReminderPermission> requestPermission() async =>
      ReminderPermission.unsupported;

  @override
  Future<void> openSystemSettings() async {}

  @override
  Future<void> cancel(int id) async {}

  @override
  Future<void> schedule(ReminderRequest request) async {}

  @override
  Future<void> scheduleOnce(ReminderRequest request) async {}
}

/// 包 `flutter_local_notifications` 的实现。
class LocalReminderScheduler extends ReminderScheduler {
  LocalReminderScheduler({
    FlutterLocalNotificationsPlugin? plugin,
    TimezoneResolver timezone = const SystemTimezone(),
  })  : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
        _timezone = timezone;

  static const _channelId = 'night_sleep_reminders';
  static const _channelName = '睡眠提醒';
  static const _channelDescription = '就寝与起床提醒';

  final FlutterLocalNotificationsPlugin _plugin;
  final TimezoneResolver _timezone;

  bool _ready = false;

  /// **可重入，且只有成功才算初始化过。**
  ///
  /// 失败时保留未初始化状态，下一次调用会重试。反过来的写法（进函数先置
  /// 「已初始化」）会把一次**偶发**的时区查询失败变成整个进程生命周期的静默失效——
  /// 用户打开提醒开关，什么都不会响，而且没有任何办法在这一进程里恢复。
  @override
  Future<void> initialize() async {
    if (_ready) return;

    try {
      // 必须两步：initializeTimeZones() 之后 tz.local 默认是 UTC，
      // 不设成设备时区的话，提醒会在错误的时刻响。
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation(await _timezone.identifier()));

      // v20 起这个插件的 `initialize` 改成了具名参数，别写回位置参数。
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            // 权限留到用户真的打开提醒开关时再申请，不在首次启动时弹。
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
          macOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );
      _ready = true;
    } catch (_) {
      // 取不到可用时区就无从按墙上时间调度。如实降级，不猜一个时区。
      _ready = false;
    }
  }

  @override
  Future<ReminderPermission> permission() async {
    if (!_ready) return ReminderPermission.unsupported;

    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return _fromDarwin(
          await _plugin
              .resolvePlatformSpecificImplementation<
                  IOSFlutterLocalNotificationsPlugin>()
              ?.checkPermissions(),
        );
      case TargetPlatform.macOS:
        return _fromDarwin(
          await _plugin
              .resolvePlatformSpecificImplementation<
                  MacOSFlutterLocalNotificationsPlugin>()
              ?.checkPermissions(),
        );
      case TargetPlatform.android:
        return _fromBool(
          await _plugin
              .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin>()
              ?.areNotificationsEnabled(),
        );
      default:
        return ReminderPermission.unsupported;
    }
  }

  @override
  Future<ReminderPermission> requestPermission() async {
    if (!_ready) return ReminderPermission.unsupported;

    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return _fromBool(
          await _plugin
              .resolvePlatformSpecificImplementation<
                  IOSFlutterLocalNotificationsPlugin>()
              ?.requestPermissions(alert: true, sound: true),
        );
      case TargetPlatform.macOS:
        return _fromBool(
          await _plugin
              .resolvePlatformSpecificImplementation<
                  MacOSFlutterLocalNotificationsPlugin>()
              ?.requestPermissions(alert: true, sound: true),
        );
      case TargetPlatform.android:
        return _fromBool(
          await _plugin
              .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin>()
              ?.requestNotificationsPermission(),
        );
      default:
        return ReminderPermission.unsupported;
    }
  }

  @override
  Future<void> openSystemSettings() async {
    if (!_ready) return;
    try {
      switch (defaultTargetPlatform) {
        case TargetPlatform.iOS:
          await _plugin
              .resolvePlatformSpecificImplementation<
                  IOSFlutterLocalNotificationsPlugin>()
              ?.openAppNotificationSettings();
        case TargetPlatform.macOS:
          await _plugin
              .resolvePlatformSpecificImplementation<
                  MacOSFlutterLocalNotificationsPlugin>()
              ?.openAppNotificationSettings();
        default:
          return;
      }
    } catch (_) {
      // 某些系统版本上跳转可能失败；界面上那行说明已经告诉用户去哪里了。
    }
  }

  @override
  Future<void> cancel(int id) async {
    if (!_ready) return;
    await _plugin.cancel(id: id);
  }

  @override
  Future<void> schedule(ReminderRequest request) async {
    if (!_ready) return;

    await _plugin.zonedSchedule(
      id: request.id,
      title: request.title,
      body: request.body,
      // 按**墙上时间**重复，因此夏令时切换后提醒跟着走，而不是漂一小时。
      matchDateTimeComponents: DateTimeComponents.time,
      scheduledDate: nextOccurrence(
        request,
        now: tz.TZDateTime.now(tz.local),
      ),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          // 前台也要展示，否则应用开着时什么都看不到。
          presentAlert: true,
          presentBanner: true,
          presentList: true,
          presentSound: true,
        ),
        macOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBanner: true,
          presentList: true,
          presentSound: true,
        ),
      ),
      // 刻意用非精确闹钟：Android 14+ 的精确闹钟要么多一个
      // SCHEDULE_EXACT_ALARM 申请流程，要么用需要上架审核的 USE_EXACT_ALARM，
      // 而「该睡了」差几分钟完全无所谓。
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  @override
  Future<void> scheduleOnce(ReminderRequest request) async {
    if (!_ready) return;

    await _plugin.zonedSchedule(
      id: request.id,
      title: request.title,
      body: request.body,
      // **不传 `matchDateTimeComponents`。** 传了就是每天重复，而这个闹钟
      // 只该响一次。排定时刻复用 `nextOccurrence`——那个纯函数已经带着
      // 跨午夜的严格比较与跨夏令时的墙上时刻规则，且有自己的测试。
      scheduledDate: nextOccurrence(request, now: tz.TZDateTime.now(tz.local)),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          // 起床闹钟**请求** `timeSensitive`，但当前产物并不能真正穿透专注模式：
          // 工程里没有配套的 Time Sensitive Notifications entitlement
          // （`ios/` 下没有任何 `.entitlements`，`macos/Runner/*.entitlements`
          // 也没有 `com.apple.developer.usernotifications.time-sensitive`），
          // 按 Apple 的规则，缺这个键时该级别会被系统降级。要真正拿到这个能力，
          // 需要加 entitlement 并在 App ID 上开启该能力，且要真机实测。
          // `critical` 更强，但需要 Apple 单独批准，本项目也没有；界面上如实写着
          // 「强度不如系统闹钟」。
          interruptionLevel: InterruptionLevel.timeSensitive,
          presentAlert: true,
          presentBanner: true,
          presentList: true,
          presentSound: true,
        ),
        macOS: DarwinNotificationDetails(
          interruptionLevel: InterruptionLevel.timeSensitive,
          presentAlert: true,
          presentBanner: true,
          presentList: true,
          presentSound: true,
        ),
      ),
      // 与日常提醒同一取舍：不申请精确闹钟权限。
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  /// 从 [now] 起，下一次该时刻落在哪。
  ///
  /// 做成**纯函数**：`now` 由调用方给，时区取自 `now.location` 而不是全局的
  /// `tz.local`。除了让依赖显式化，更要紧的是这样测试才能钉住**夏令时**那条规则——
  /// 跨切换日时提醒必须仍在同样的**墙上时刻**响，而不是「前一次的绝对时刻 + 24 小时」。
  /// 那是这段代码里唯一一处不写测试就只能靠读注释相信的地方。
  @visibleForTesting
  static tz.TZDateTime nextOccurrence(
    ReminderRequest request, {
    required tz.TZDateTime now,
  }) {
    final location = now.location;
    final today = tz.TZDateTime(
      location,
      now.year,
      now.month,
      now.day,
      request.hour,
      request.minute,
    );
    // 严格比较。等于此刻**不算未来**：那一秒已经过去，语义上归到明天。
    // 若写成 `!today.isBefore(now)`，用户恰在提醒时刻那一分钟打开开关时，
    // 调度时刻就是「此刻」，会立刻补一条通知——一个纯粹由比较符号引入的假提醒。
    if (today.isAfter(now)) return today;

    // 用「下一天 + 同一墙钟时刻」重建，而不是加 24 小时——后者跨夏令时会落到
    // 另一个钟点上（美国 2026-03-08 那次切换会让 07:00 变成 08:00）。
    return tz.TZDateTime(
      location,
      now.year,
      now.month,
      now.day + 1,
      request.hour,
      request.minute,
    );
  }

  static ReminderPermission _fromDarwin(NotificationsEnabledOptions? options) =>
      options == null
          ? ReminderPermission.unsupported
          : (options.isEnabled
              ? ReminderPermission.granted
              : ReminderPermission.denied);

  static ReminderPermission _fromBool(bool? enabled) => enabled == null
      ? ReminderPermission.unsupported
      : (enabled ? ReminderPermission.granted : ReminderPermission.denied);
}

/// 按平台选择实现。
///
/// Web 必须**显式排除**：`defaultTargetPlatform` 在 Web 上报告的是宿主操作系统，
/// 靠它判断会让 Web 走进 iOS/macOS 的分支。
final reminderSchedulerProvider = Provider<ReminderScheduler>((ref) {
  if (kIsWeb) return NoopReminderScheduler();
  return LocalReminderScheduler();
});
