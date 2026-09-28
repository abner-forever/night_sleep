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

  setUp(() => database = AppDatabase(NativeDatabase.memory()));
  tearDown(() => database.close());

  AppSetting settings() => const AppSetting(
        id: 'default',
        themeMode: 'system',
        sleepGoalMinutes: 480,
        bedtimeReminderEnabled: false,
        bedtimeReminderMinutes: 22 * 60 + 30,
        wakeReminderEnabled: false,
        wakeReminderMinutes: 7 * 60,
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
          settingsProvider.overrideWith((ref) => Stream.value(settings())),
          reminderSchedulerProvider.overrideWithValue(scheduler),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: SettingsPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
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
    expect(row.bedtimeReminderMinutes, 22 * 60 + 30,
        reason: '全新安装时该列是 NULL，打开开关必须把界面显示的时刻一并落库——'
            '否则计划里没有这一项，sync 只 cancel 不 schedule，开关开着却不会响');
    expect(scheduler.lastSynced?.bedtimeMinutes, 22 * 60 + 30);
    expect(scheduler.lastSynced?.wakeMinutes, isNull, reason: '起床提醒还关着');
  });

  testWidgets('权限不是 granted 时给出「去系统设置」入口', (tester) async {
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

    await tester.tap(reminderToggle(0));
    await tester.pumpAndSettle();

    final row = await database.getSettings();
    expect(row.bedtimeReminderEnabled, isFalse);
    expect(toastOf(tester), contains('无法安排本地通知'));
  });
}
