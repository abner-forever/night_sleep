import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/core/theme/app_theme.dart';
import 'package:night_sleep/features/home/presentation/sleep_calendar_page.dart';
import 'package:night_sleep/features/sleep/data/sleep_repository.dart';
import 'package:night_sleep/features/sleep/domain/sleep_entry.dart';
import 'package:night_sleep/features/sleep/domain/sleep_quality.dart';

SleepEntry _night({
  required String id,
  required DateTime wake,
  double hours = 8,
  SleepQuality quality = SleepQuality.good,
}) {
  final start = wake.subtract(Duration(minutes: (hours * 60).round()));
  return SleepEntry(
    id: id,
    startAtUtc: start.toUtc(),
    endAtUtc: wake.toUtc(),
    timeZoneId: 'UTC',
    quality: quality,
    createdAtUtc: wake.toUtc(),
    updatedAtUtc: wake.toUtc(),
  );
}

void main() {
  Future<void> pumpCalendar(
    WidgetTester tester,
    List<SleepEntry> entries,
  ) async {
    tester.view.physicalSize = const Size(430, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sleepEntriesProvider.overrideWith((ref) => entries),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const SleepCalendarPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('按最近记录所在月份显示月度概览', (tester) async {
    await pumpCalendar(tester, [
      _night(id: 'sep-22', wake: DateTime(2026, 9, 22, 7)),
      _night(id: 'sep-21', wake: DateTime(2026, 9, 21, 7), hours: 7),
      _night(id: 'aug-30', wake: DateTime(2026, 8, 30, 7), hours: 6),
    ]);

    expect(find.text('睡眠日历'), findsOneWidget);
    expect(find.text('2026 年 9 月'), findsOneWidget);
    expect(find.textContaining('2'), findsWidgets);
    expect(find.text('平均时长'), findsOneWidget);
    expect(find.text('7.5 h'), findsOneWidget);
    expect(find.text('平均评分'), findsOneWidget);
  });

  testWidgets('点选有记录的日期会显示当晚摘要', (tester) async {
    await pumpCalendar(tester, [
      _night(id: 'sep-22', wake: DateTime(2026, 9, 22, 7)),
      _night(id: 'sep-21', wake: DateTime(2026, 9, 21, 7)),
    ]);

    await tester.tap(find.text('21'));
    await tester.pumpAndSettle();

    expect(find.text('9 月 21 日'), findsOneWidget);
    expect(find.text('这一晚已记录'), findsOneWidget);
    expect(find.text('查看详情'), findsOneWidget);
  });

  testWidgets('可以翻到上一个月', (tester) async {
    await pumpCalendar(tester, [
      _night(id: 'aug-30', wake: DateTime(2026, 8, 30, 7)),
      _night(id: 'sep-01', wake: DateTime(2026, 9, 1, 7)),
    ]);

    await tester.tap(find.bySemanticsLabel('上个月'));
    await tester.pumpAndSettle();

    expect(find.text('2026 年 8 月'), findsOneWidget);
  });

  testWidgets('左右滑动日历可以切换月份', (tester) async {
    await pumpCalendar(tester, [
      _night(id: 'aug-30', wake: DateTime(2026, 8, 30, 7)),
      _night(id: 'sep-01', wake: DateTime(2026, 9, 1, 7)),
    ]);
    final calendar = find.byKey(calendarMonthPageViewKey);
    expect(calendar, findsOneWidget);

    await tester.fling(calendar, const Offset(260, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('2026 年 8 月'), findsOneWidget);

    await tester.fling(calendar, const Offset(-260, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('2026 年 9 月'), findsOneWidget);
  });
}
