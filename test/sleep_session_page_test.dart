import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/core/database/app_database.dart';
import 'package:night_sleep/core/platform/reminders.dart';
import 'package:night_sleep/core/theme/app_theme.dart';
import 'package:night_sleep/features/session/presentation/sleep_session_page.dart';
import 'package:night_sleep/features/sleep/data/session_repository.dart';
import 'package:night_sleep/features/sleep/domain/sleep_session.dart';

void main() {
  late AppDatabase database;

  setUp(() => database = AppDatabase(NativeDatabase.memory()));
  tearDown(() => database.close());

  /// 冻住时钟渲染会话页。
  ///
  /// `now` 非空时页面**不起定时器**，所以这里不会留下 pending timer——
  /// 这是这个测试接缝存在的全部理由，不要图省事改成「起定时器再 pump 掉」。
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

  SleepSession sessionAt(DateTime start, {int wakeMinutes = 7 * 60}) =>
      SleepSession(
        startAtUtc: start.toUtc(),
        timeZoneId: 'UTC',
        wakeMinutes: wakeMinutes,
        alarmEnabled: false,
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
}
