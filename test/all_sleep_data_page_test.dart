import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/core/config/app_config.dart';
import 'package:night_sleep/core/theme/app_theme.dart';
import 'package:night_sleep/features/sleep/data/sleep_repository.dart';
import 'package:night_sleep/features/sleep/domain/sleep_entry.dart';
import 'package:night_sleep/features/sleep/domain/sleep_insight.dart';
import 'package:night_sleep/features/sleep/domain/sleep_quality.dart';
import 'package:night_sleep/features/stats/presentation/all_sleep_data_page.dart';

/// 全部睡眠数据页的 widget 测试。
///
/// 分组口径本身在 `test/sleep_history_test.dart` 里钉死；这里管的是界面：
/// 换分组、汇总卡、行内容与空状态。
void main() {
  /// 醒来时刻固定在本地 07:00，所以归到哪一天与机器时区无关。
  ///
  /// [quality] 显式传 `null` 才是**未评分**：本地估算只要有质量打分就会给分，
  /// 想造一条没有分数的记录只能走这条路。
  SleepEntry night(
    DateTime wakeDay, {
    double hours = 8,
    int? insightScore,
    SleepQuality? quality = SleepQuality.good,
  }) {
    final end = DateTime(wakeDay.year, wakeDay.month, wakeDay.day, 7);
    final start = end.subtract(Duration(minutes: (hours * 60).round()));
    return SleepEntry(
      id: 'r${wakeDay.month}-${wakeDay.day}',
      startAtUtc: start.toUtc(),
      endAtUtc: end.toUtc(),
      timeZoneId: 'UTC',
      quality: quality,
      createdAtUtc: end.toUtc(),
      updatedAtUtc: end.toUtc(),
      insight: insightScore == null
          ? null
          : Insight(
              id: 'i${wakeDay.month}-${wakeDay.day}',
              recordId: 'r',
              content: '总结',
              provider: 'deepseek',
              model: 'deepseek-chat',
              score: insightScore,
              generatedAtUtc: end.toUtc(),
              // **`status` 不能省**：不是 `ok` 的洞察不算数（`isUsable` 为假），
              // 分数会回落到本地估算，夹具就钉不住期望值了。
              status: InsightStatus.ok,
            ),
    );
  }

  /// 一条演示记录：来源标记为 `demo`，其余与真实记录一样。
  SleepEntry demoNight(DateTime wakeDay) => SleepEntry(
        id: 'demo-${wakeDay.month}-${wakeDay.day}',
        startAtUtc:
            DateTime(wakeDay.year, wakeDay.month, wakeDay.day, 23).toUtc(),
        endAtUtc:
            DateTime(wakeDay.year, wakeDay.month, wakeDay.day + 1, 7).toUtc(),
        timeZoneId: 'UTC',
        quality: SleepQuality.good,
        source: AppConfig.demoSource,
        createdAtUtc:
            DateTime(wakeDay.year, wakeDay.month, wakeDay.day, 8).toUtc(),
        updatedAtUtc:
            DateTime(wakeDay.year, wakeDay.month, wakeDay.day, 8).toUtc(),
      );

  Future<void> pumpRoute(
    WidgetTester tester, {
    List<SleepEntry> entries = const [],
  }) async {
    tester.view.physicalSize = const Size(430, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sleepEntriesProvider.overrideWith((ref) => entries)],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const AllSleepDataPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 三晚：两晚在 10 月（同属一周），一晚在 9 月且**未评分**。
  ///
  /// 两条口径是**故意错开**的：10 月那组平均 7.0h，9 月那组是 4.0h，全库是 6.0h。
  /// 三处若有一处取错了源（比如组抬头误用全库平均），断言立刻变红——夹具里各组的
  /// 平均与全库平均相等时，这一整页的口径其实无人看管。
  List<SleepEntry> threeNights() => [
        night(DateTime(2026, 10, 14), hours: 8, insightScore: 90),
        night(DateTime(2026, 10, 13), hours: 6, insightScore: 70),
        night(DateTime(2026, 9, 30), hours: 4, quality: null),
      ];

  testWidgets('默认按月分组，抬头带条数与平均', (tester) async {
    await pumpRoute(tester, entries: threeNights());

    expect(find.text('2026年10月'), findsOneWidget);
    expect(find.text('2026年9月'), findsOneWidget);
    // 10 月两晚：8h 与 6h → 平均 7.0h；两条都有评分 → 平均 80。
    expect(find.text('2 晚 · 平均 7.0h · 评分 80'), findsOneWidget);
    // 9 月那晚 4h、未评分：平均是本组的 4.0h（**不是**全库的 6.0h），整段不写评分。
    expect(find.text('1 晚 · 平均 4.0h'), findsOneWidget);
    expect(find.textContaining('全库'), findsNothing);
  });

  testWidgets('记录行是日期加周几、起止时刻与时长', (tester) async {
    await pumpRoute(tester, entries: threeNights());

    expect(find.text('10月14日 周三'), findsOneWidget);
    expect(find.text('10月13日 周二'), findsOneWidget);
    expect(find.text('8h 0m'), findsOneWidget);
    expect(find.text('6h 0m'), findsOneWidget);
    expect(find.text('评分 90'), findsOneWidget);
    expect(find.text('评分 70'), findsOneWidget);

    // 未评分的那条不写评分行，也不写占位符。
    expect(find.text('评分 0'), findsNothing);
    expect(find.text('未评分'), findsNothing);
  });

  testWidgets('顶部汇总卡：条数、平均时长与平均评分', (tester) async {
    await pumpRoute(tester, entries: threeNights());

    expect(find.text('全部记录'), findsOneWidget);
    expect(find.text('3'), findsOneWidget, reason: '记录数');
    // 全库平均是 6.0h，与任何一个组的平均都不同——取错了源这里就红。
    expect(find.text('6.0h'), findsOneWidget, reason: '三晚 8/6/4 小时的全库平均');
    expect(find.text('80'), findsWidgets, reason: '两条有评分的平均');
    expect(find.textContaining('覆盖 9月30日 – 10月14日'), findsOneWidget);
  });

  testWidgets('全库都没评分时汇总卡写「未评分」', (tester) async {
    await pumpRoute(
      tester,
      entries: [night(DateTime(2026, 10, 14), quality: null)],
    );

    expect(find.text('未评分'), findsOneWidget);
    // 组抬头与记录行都不写评分——「没有」就是没有，不摆一个占位数字。
    // 用正则而不是 `textContaining('评分')`：汇总卡的**标签**就叫「平均评分」。
    expect(find.textContaining(RegExp(r'评分 \d')), findsNothing);
    expect(find.text('1 晚 · 平均 8.0h'), findsOneWidget);
  });

  testWidgets('切到按周：抬头换成周区间', (tester) async {
    await pumpRoute(tester, entries: threeNights());

    await tester.tap(find.text('按周'));
    await tester.pumpAndSettle();

    // 2026-10-14 与 10-13 同属 10-12（周一）那一周。抬头带年份：行里只有月日，
    // 年份得由抬头给，否则相隔几年的同一个日历区间会长得一模一样。
    expect(find.text('2026年10月12日 – 10月18日'), findsOneWidget);
    expect(find.text('2026年9月28日 – 10月4日'), findsOneWidget);
    expect(find.text('2026年10月'), findsNothing);
  });

  testWidgets('切到按年：同一年并成一组', (tester) async {
    await pumpRoute(tester, entries: threeNights());

    await tester.tap(find.text('按年'));
    await tester.pumpAndSettle();

    expect(find.text('2026年'), findsOneWidget);
    expect(find.text('3 晚 · 平均 6.0h · 评分 80'), findsOneWidget);
  });

  testWidgets('本地估算的分数写「估算」，不冒充「评分」', (tester) async {
    // 只有自评质量、没有阶段与录音的一晚：分数由本地规则算出来。
    // 首页对同一条记录写的也是「估算 NN」，详情弹层还会标「本地估算」。
    await pumpRoute(tester, entries: [night(DateTime(2026, 10, 14))]);

    expect(find.textContaining('估算 '), findsOneWidget);
    expect(find.textContaining(RegExp(r'估算 \d+')), findsOneWidget);
  });

  testWidgets('演示记录照列，但在汇总卡里如实说明有几条', (tester) async {
    await pumpRoute(tester, entries: [
      night(DateTime(2026, 10, 14)),
      demoNight(DateTime(2026, 10, 13)),
      demoNight(DateTime(2026, 10, 12)),
    ]);

    // 照列：演示行也在列表里（与统计页同口径）。
    expect(find.text('10月13日 周二'), findsOneWidget);
    expect(find.text('3'), findsOneWidget, reason: '条数含演示记录');
    expect(find.text('其中 2 条是演示数据，不是你的记录'), findsOneWidget);
  });

  testWidgets('没有演示记录时不写那一句', (tester) async {
    await pumpRoute(tester, entries: [night(DateTime(2026, 10, 14))]);

    expect(find.textContaining('演示数据'), findsNothing);
  });

  testWidgets('一条记录都没有时是空状态', (tester) async {
    await pumpRoute(tester);

    expect(find.text('还没有睡眠记录'), findsOneWidget);
    expect(find.text('按周'), findsNothing, reason: '没有数据就没有可切的分组');
  });
}
