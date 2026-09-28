import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/app/app.dart';
import 'package:night_sleep/app/app_toast.dart';
import 'package:night_sleep/core/database/app_database.dart';
import 'package:night_sleep/core/platform/reminders.dart';
import 'package:night_sleep/core/theme/app_theme.dart';
import 'package:night_sleep/core/widgets/ios_controls.dart';
import 'package:night_sleep/features/settings/presentation/settings_page.dart';
import 'package:night_sleep/features/sleep/data/sleep_repository.dart';

class _FakeScheduler extends ReminderScheduler {
  _FakeScheduler({
    this.grants = false,
    ReminderPermission current = ReminderPermission.denied,
  }) : _current = current;

  final bool grants;
  ReminderPermission _current;
  int settingsOpened = 0;
  ReminderPlan? lastSynced;

  @override
  Future<void> initialize() async {}

  @override
  Future<ReminderPermission> permission() async => _current;

  @override
  Future<ReminderPermission> requestPermission() async {
    // 只在授予时改状态，否则保留构造时给的初值。
    //
    // 写成 `_current = grants ? granted : denied` 会让 `unsupported` **不可达**：
    // 传 `current: unsupported, grants: false` 会被改写成 denied，于是「平台不支持」
    // 那条用例永远拿不到它要断言的提示——一个在任何实现下都过不了的用例。
    if (grants) _current = ReminderPermission.granted;
    return _current;
  }

  @override
  Future<void> openSystemSettings() async => settingsOpened++;

  @override
  Future<void> cancel(int id) async {}

  @override
  Future<void> schedule(ReminderRequest request) async {}

  @override
  Future<void> sync(ReminderPlan plan) async => lastSynced = plan;
}

void main() {
  late AppDatabase database;
  late StreamController<AppSetting> settingsStream;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    settingsStream = StreamController<AppSetting>.broadcast();
  });
  tearDown(() async {
    await settingsStream.close();
    await database.close();
  });

  /// 夹具里的时刻也用 `SettingsPage` 的常量，不重抄字面量：
  /// 整条用例的前提就是「界面显示的默认值」，抄一遍就等于把断言和被断言的对象分开维护。
  AppSetting settings() => const AppSetting(
        id: 'default',
        themeMode: 'system',
        sleepGoalMinutes: 480,
        bedtimeReminderEnabled: false,
        bedtimeReminderMinutes: SettingsPage.defaultBedtimeMinutes,
        wakeReminderEnabled: false,
        wakeReminderMinutes: SettingsPage.defaultWakeMinutes,
        soundRecordingEnabled: false,
        onboarded: true,
        insightProvider: null,
        insightModel: null,
      );

  /// [SettingsPage] 是标签页，真机上确实活在壳的 Scaffold 里，所以这里给一个。
  Future<void> pumpSettings(
      WidgetTester tester, ReminderScheduler scheduler) async {
    tester.view.physicalSize = const Size(430, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          sleepEntriesProvider.overrideWith((ref) => const []),
          settingsProvider.overrideWith((ref) => settingsStream.stream),
          reminderSchedulerProvider.overrideWithValue(scheduler),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: SettingsPage()),
        ),
      ),
    );
    // 首帧之后再投初值：broadcast 流不重放，订阅是在 pumpWidget 的第一帧建立的。
    settingsStream.add(settings());
    await tester.pumpAndSettle();
  }

  /// 把某一项的新值回投给界面，**模拟写库回流**。
  ///
  /// 生产里 `settingsProvider` 就是 `database.watchSettings()`，写库会自己流回界面；
  /// 测试不能用那个（widget 测试订阅 drift 的 `watch*` 流会因假时钟不推进而留下
  /// pending timer），所以用一个手动回投的流保持同构。
  ///
  /// 这不是装饰：`IosToggle` 的 onTap 是 `onChanged!(!value)`，**它读的是界面上的值**。
  /// 界面若不回流，开关永远显示为关，于是每次点击都只送出 `true`——「再点一次关掉它」
  /// 这类用例根本走不到，而且没有任何报错提示你。
  void echoSettings({bool? bedtimeEnabled, bool? wakeEnabled}) {
    settingsStream.add(
      settings().copyWith(
        bedtimeReminderEnabled: bedtimeEnabled,
        wakeReminderEnabled: wakeEnabled,
      ),
    );
  }

  /// 设置页里前两个开关依次是就寝提醒与起床提醒，第三个是夜间声音录制。
  Finder reminderToggle(int index) => find.byType(IosToggle).at(index);

  /// 提示条的文字。
  ///
  /// 测试树里**没有** `ToastOverlay`——它活在应用外壳 `AppScaffold` 里，而这个
  /// 测试只挂了 `SettingsPage`。所以不能用 `find.text`，只能直接读 provider。
  String? toastOf(WidgetTester tester) => ProviderScope.containerOf(
        tester.element(find.byType(SettingsPage)),
      ).read(toastProvider);

  testWidgets('权限被拒时开关回弹且不写库', (tester) async {
    final scheduler = _FakeScheduler(grants: false);
    await pumpSettings(tester, scheduler);

    await tester.tap(reminderToggle(0));
    await tester.pumpAndSettle();

    final row = await database.getSettings();
    expect(row.bedtimeReminderEnabled, isFalse, reason: '被拒时不得写入一个开了却不会响的偏好');
    expect(scheduler.lastSynced, isNull, reason: '没开成就不必重排');
    expect(toastOf(tester), contains('没有获得通知权限'));
  });

  testWidgets('权限被授予时写入偏好并按计划重排', (tester) async {
    final scheduler = _FakeScheduler(grants: true);
    await pumpSettings(tester, scheduler);

    await tester.tap(reminderToggle(0));
    await tester.pumpAndSettle();

    final row = await database.getSettings();
    expect(row.bedtimeReminderEnabled, isTrue);
    // 绑常量而不是重写一遍字面量：断言的正是「存下来的就是界面显示的那个默认值」，
    // 常量改了字号也不会让这条断言悄悄失去意义。
    expect(row.bedtimeReminderMinutes, SettingsPage.defaultBedtimeMinutes,
        reason: '全新安装时该列是 NULL，打开开关必须把界面显示的时刻一并落库——'
            '否则计划里没有这一项，sync 只 cancel 不 schedule，开关开着却不会响');
    expect(scheduler.lastSynced?.bedtimeMinutes,
        SettingsPage.defaultBedtimeMinutes);
    expect(scheduler.lastSynced?.wakeMinutes, isNull, reason: '起床提醒还关着');
  });

  testWidgets('关掉提醒时写回 false 且计划里那一项变成 null', (tester) async {
    // 先开再关。这一条同时覆盖两处**此前零覆盖**的路径：
    // ① `_syncReminders` 把关掉的那一项传 `null`（只测「从未开启」走不到）；
    // ② 关掉时把 `enabled` 写回 `false`（写不回去的话，关掉的提醒还会照响）。
    final scheduler = _FakeScheduler(grants: true);
    await pumpSettings(tester, scheduler);

    await tester.tap(reminderToggle(0));
    await tester.pumpAndSettle();
    // 必须回投：不回投的话界面上的开关永远显示「关」，第二次点击还会送出 `true`。
    echoSettings(bedtimeEnabled: true);
    await tester.pumpAndSettle();

    await tester.tap(reminderToggle(0));
    await tester.pumpAndSettle();

    final row = await database.getSettings();
    expect(row.bedtimeReminderEnabled, isFalse, reason: '关掉必须写回 false');
    expect(scheduler.lastSynced?.bedtimeMinutes, isNull,
        reason: '关掉的提醒不能再进计划，否则它还会照响');
  });

  testWidgets('权限被拒时给出可点的「去系统设置」入口', (tester) async {
    final scheduler = _FakeScheduler(current: ReminderPermission.denied);
    await pumpSettings(tester, scheduler);

    expect(find.textContaining('未获得通知权限'), findsOneWidget);

    await tester.tap(find.textContaining('未获得通知权限'));
    await tester.pumpAndSettle();
    expect(scheduler.settingsOpened, 1);
  });

  testWidgets('权限已授予时不显示「去系统设置」入口', (tester) async {
    final scheduler = _FakeScheduler(current: ReminderPermission.granted);
    await pumpSettings(tester, scheduler);

    expect(find.textContaining('未获得通知权限'), findsNothing);
  });

  testWidgets('平台不支持时如实说明，不假装已开启', (tester) async {
    final scheduler = _FakeScheduler(current: ReminderPermission.unsupported);
    await pumpSettings(tester, scheduler);

    // 这一行**只在 denied 时出现**：unsupported 的成因可能是本设备取不到时区，
    // 与授权无关，说「未获得通知权限」是假话，而那个按钮点了也不会有反应。
    expect(find.textContaining('未获得通知权限'), findsNothing);

    await tester.tap(reminderToggle(0));
    await tester.pumpAndSettle();

    final row = await database.getSettings();
    expect(row.bedtimeReminderEnabled, isFalse);
    expect(toastOf(tester), contains('无法安排本地通知'));
  });
}
