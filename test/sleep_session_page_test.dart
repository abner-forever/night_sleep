import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:night_sleep/app/app.dart';
import 'package:night_sleep/core/database/app_database.dart';
import 'package:night_sleep/core/platform/reminders.dart';
import 'package:night_sleep/core/theme/app_theme.dart';
import 'package:night_sleep/features/session/presentation/sleep_session_page.dart';
import 'package:night_sleep/features/sleep/data/session_repository.dart';
import 'package:night_sleep/features/sleep/data/sleep_repository.dart';
import 'package:night_sleep/features/sleep/domain/sleep_entry.dart';
import 'package:night_sleep/features/sleep/domain/sleep_session.dart';

void main() {
  late AppDatabase database;

  setUp(() => database = AppDatabase(NativeDatabase.memory()));
  tearDown(() => database.close());

  /// 冻住时钟渲染会话页。
  ///
  /// 这里**必须**传固定的 `now`：页面在 `now` 非空时不起定时器，读数才不会被
  /// 真实时钟覆写。不传的话「3h 42m」「23:14」这类断言会随跑测试的日期时间
  /// 随机变红。（pending timer 不是这里的理由——拆树时 `dispose()` 会 cancel。）
  Future<void> pumpSession(
    WidgetTester tester, {
    required SleepSession session,
    required DateTime now,
    bool wide = false,
  }) async {
    tester.view.physicalSize =
        wide ? const Size(1200, 2000) : const Size(430, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          activeSessionProvider.overrideWith((ref) => session),
          // 真的调度器在测试里没有平台通道，`initialize` 也从没跑过；换成空实现，
          // 免得测试依赖「它恰好会静默降级」这个实现细节。
          reminderSchedulerProvider.overrideWithValue(NoopReminderScheduler()),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: SleepSessionPage(now: now),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  SleepSession sessionAt(
    DateTime start, {
    int wakeMinutes = 7 * 60,
    bool alarmEnabled = false,
  }) =>
      SleepSession(
        startAtUtc: start.toUtc(),
        timeZoneId: 'UTC',
        wakeMinutes: wakeMinutes,
        alarmEnabled: alarmEnabled,
        createdAtUtc: start.toUtc(),
      );

  testWidgets('显示已睡时长与设定的起床时间', (tester) async {
    final start = DateTime(2026, 8, 30, 23, 14);
    await pumpSession(
      tester,
      session: sessionAt(start),
      now: start.add(const Duration(hours: 3, minutes: 42)),
    );

    expect(find.text('正在睡眠'), findsOneWidget);
    // 中心读数的文案是确定的，所以断言精确的整串——`textContaining('3')`
    // 这条页面上到处都能满足，等于没测。
    expect(find.text('3h 42m'), findsOneWidget);
    // 「定了几点起」必须在收合态就看得见。
    expect(find.text('23:14'), findsOneWidget);
    expect(find.text('07:00'), findsOneWidget);
  });

  testWidgets('超过起床时间后给出「已超过」而不是让弧溢出', (tester) async {
    final start = DateTime(2026, 8, 30, 23, 14);
    await pumpSession(
      tester,
      session: sessionAt(start),
      now: start.add(const Duration(hours: 9)),
    );

    expect(find.textContaining('已超过起床时间'), findsOneWidget);
  });

  testWidgets('闹钟关着时胶囊说自然醒后手动结束', (tester) async {
    final start = DateTime(2026, 8, 30, 23, 14);
    await pumpSession(
      tester,
      session: sessionAt(start),
      now: start.add(const Duration(hours: 1)),
    );

    expect(find.textContaining('自然醒后手动结束'), findsOneWidget);
  });

  testWidgets('闹钟开着时报剩余时间，并带上后台投递的如实标注', (tester) async {
    final start = DateTime(2026, 8, 30, 23, 14);
    await pumpSession(
      tester,
      session: sessionAt(start, alarmEnabled: true),
      now: start.add(const Duration(hours: 3, minutes: 42)),
    );

    // 计划时长 = 23:14 → 次日 07:00 = 7h46m；已过 3h42m，剩 4h4m。
    // （设计稿里 236 行写「3h 42m」、242 行写「还有 3h 18m」，两个数自相矛盾；
    // 以算出来的为准。）
    expect(find.text('起床闹钟已开 · 还有 4h 4m'), findsOneWidget);
    // 规格点名「这句话是功能的一部分」：逐字断言，不是「页面里大概有这么句」。
    expect(
      find.text('由系统通知投递；休眠模式下可能晚几分钟，强度不如系统闹钟。'),
      findsOneWidget,
    );
  });

  testWidgets('入睡与闹钟时刻都补零到两位', (tester) async {
    // 23:14 / 07:00 两个数本来都是两位数，`padLeft` 等于没被行使；这里换成
    // 一位数的小时与分钟，补零逻辑才真的被测到。
    final start = DateTime(2026, 8, 30, 9, 5);
    await pumpSession(
      tester,
      session: sessionAt(start, wakeMinutes: 6 * 60 + 5),
      now: start.add(const Duration(hours: 1)),
    );

    expect(find.text('09:05'), findsOneWidget);
    expect(find.text('06:05'), findsOneWidget);
    expect(find.text('9:5'), findsNothing);
    expect(find.text('6:5'), findsNothing);
  });

  testWidgets('推入页自己提供 Material 祖先与背景', (tester) async {
    final start = DateTime(2026, 8, 30, 23, 14);
    await pumpSession(
      tester,
      session: sessionAt(start),
      now: start.add(const Duration(hours: 1)),
    );

    final heading = find.text('正在睡眠');
    expect(
      DefaultTextStyle.of(tester.element(heading)).style.decoration,
      isNot(TextDecoration.underline),
      reason: '落到 Flutter 的无 Material 错误样式了（黄色双下划线）',
    );
    expect(find.byType(Material), findsWidgets);
  });

  testWidgets('没有会话时不崩，显示空状态并可返回', (tester) async {
    tester.view.physicalSize = const Size(430, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          activeSessionProvider.overrideWith((ref) => null),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: SleepSessionPage(now: DateTime(2026, 8, 30, 23, 14)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('没有正在进行的睡眠'), findsOneWidget);
  });

  /// 「收起」= 离开页面但**不结束会话**。这条只能在真实路由上验：`pop()` 的语义
  /// 就是「回到上一页」，裸渲染一个页面测不到它。
  ///
  /// 用的是 `NightSleepApp` 自己那个路由，所以顺带覆盖了 `lib/app/app.dart` 里
  /// 注册的 `path: 'sleep/session'`——在测试里另起一份路由达不到这个效果。
  testWidgets('点「收起」回到上一页，不结束会话也不写库', (tester) async {
    tester.view.physicalSize = const Size(430, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final start = DateTime(2026, 8, 30, 23, 14);

    // 外壳与首页各自订阅了 drift 的 `watch*` 流；widget 测试的假时钟不推进，
    // 订阅它们会留下 pending timer（见 `.claude/skills/flutter-pitfalls`）。
    // 这里把这几条流全换成 provider override，真路由才跑得起来。
    await database
        .updateSettings(const AppSettingsCompanion(onboarded: Value(true)));
    final appSettings = await database.getSettings();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          settingsProvider.overrideWith((ref) => Stream.value(appSettings)),
          sleepEntriesProvider.overrideWith((ref) => const <SleepEntry>[]),
          activeSessionProvider.overrideWith((ref) => sessionAt(start)),
          reminderSchedulerProvider.overrideWithValue(NoopReminderScheduler()),
        ],
        child: const NightSleepApp(),
      ),
    );
    await tester.pumpAndSettle();

    // 会话页是**推入**的，这里也走推入。
    GoRouter.of(tester.element(find.byType(AppScaffold)))
        .push('/sleep/session');
    await tester.pumpAndSettle();

    expect(find.text('正在睡眠'), findsOneWidget, reason: '推入后应停在会话页');

    await tester.tap(find.text('收起'));
    await tester.pumpAndSettle();

    expect(find.text('正在睡眠'), findsNothing, reason: '收起就是离开会话页');
    expect(
      await SleepRepository(database).loadAll(),
      isEmpty,
      reason: '收起不是结束：不该写出一条睡眠记录',
    );
    expect(
      await database.activeSession(),
      isNull,
      reason: '会话行是夹具给的，收起不该往库里写任何东西',
    );
  });
}
