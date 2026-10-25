import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/core/config/app_config.dart';
import 'package:night_sleep/core/theme/app_theme.dart';
import 'package:night_sleep/core/theme/app_tokens.dart';
import 'package:night_sleep/core/widgets/app_basics.dart';
import 'package:night_sleep/features/sleep/data/sleep_repository.dart';
import 'package:night_sleep/features/sleep/domain/sleep_entry.dart';
import 'package:night_sleep/features/sleep/domain/sleep_insight.dart';
import 'package:night_sleep/features/sleep/domain/sleep_quality.dart';
import 'package:night_sleep/features/stats/presentation/all_sleep_data_page.dart';

/// 「全部数据」页的 widget 测试。
///
/// 周期口径本身在 `test/sleep_history_test.dart` 里钉死；这里管的是界面：
/// 默认周期、翻页与禁用、三种粒度的柱状图、汇总卡、行内容与两处空状态。
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
  ///
  /// **[bedtime] 是入睡那一晚的日期**，不是醒来日：它按 23:00 → 次日 07:00 造，
  /// 而归组用的是**醒来日**（`SleepEntry.archiveDay`）。`demoNight(10 月 11 日)`
  /// 落在 10 月 12 日那一格，别按参数名猜它归到哪天。
  SleepEntry demoNight(DateTime bedtime) => SleepEntry(
        id: 'demo-${bedtime.month}-${bedtime.day}',
        startAtUtc:
            DateTime(bedtime.year, bedtime.month, bedtime.day, 23).toUtc(),
        endAtUtc:
            DateTime(bedtime.year, bedtime.month, bedtime.day + 1, 7).toUtc(),
        timeZoneId: 'UTC',
        quality: SleepQuality.good,
        source: AppConfig.demoSource,
        createdAtUtc:
            DateTime(bedtime.year, bedtime.month, bedtime.day, 8).toUtc(),
        updatedAtUtc:
            DateTime(bedtime.year, bedtime.month, bedtime.day, 8).toUtc(),
      );

  Future<void> pumpRoute(
    WidgetTester tester, {
    List<SleepEntry> entries = const [],
    Size size = const Size(430, 2600),
  }) async {
    // 视口给得足够高，`ListView(children:)` 才会把每一段都铺出来——
    // 屏外的那几段不参与布局，溢出也就无从发现。
    tester.view.physicalSize = size;
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

  /// 三晚：两晚在 10 月**同一周**（8h / 6h，都有模型评分），一晚在 9 月底且未评分。
  ///
  /// 特意让三种粒度的数字各不相同：周平均 7.0h、月平均 6.0h、年平均 6.0h，
  /// 哪一处取错了源（比如年视图拿了某一晚而不是当月平均）断言就红。
  List<SleepEntry> threeNights() => [
        night(DateTime(2026, 10, 14), hours: 8, insightScore: 90),
        night(DateTime(2026, 10, 13), hours: 6, insightScore: 70),
        night(DateTime(2026, 9, 30), hours: 4, quality: null),
      ];

  PeriodBarChart chartOf(WidgetTester tester) =>
      tester.widget<PeriodBarChart>(find.byKey(allDataCurrentChartKey));

  /// 柱子按标签索引，断言里就不用数下标。
  Map<String, double?> barsByLabel(WidgetTester tester) =>
      {for (final bar in chartOf(tester).bars) bar.label: bar.value};

  bool nextEnabled(WidgetTester tester) =>
      tester.widget<Pressable>(find.byKey(periodNextButtonKey)).onTap != null;

  Future<void> tapSegment(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets('默认是本周：抬头是本周区间，下面写本周期条数', (tester) async {
    await pumpRoute(tester, entries: threeNights());

    expect(find.text('全部数据'), findsOneWidget);
    expect(find.text('所有睡眠数据'), findsNothing);
    // 分段控件是周 / 月 / 年三档（不是「按周 / 按月 / 按年」）。
    expect(find.text('周'), findsOneWidget);
    expect(find.text('月'), findsOneWidget);
    expect(find.text('年'), findsOneWidget);
    // 2026-10-12（周一）到 10-18（周日）；10-14 与 10-13 都在这一周里。
    expect(find.text('2026年10月12日 – 10月18日'), findsOneWidget);
    expect(find.text('2 条睡眠记录'), findsOneWidget);
  });

  testWidgets('默认周视图的柱状图是七根，只有这两天有值', (tester) async {
    await pumpRoute(tester, entries: threeNights());

    final chart = chartOf(tester);
    expect(chart.bars.length, 7);
    expect(
      chart.bars.map((bar) => bar.label).toList(),
      ['一', '二', '三', '四', '五', '六', '日'],
    );
    // 周一 10-12 没记录 → null（画淡条，不是 0）。周二 6h，周三 8h。
    expect(
      chart.bars.map((bar) => bar.value).toList(),
      [null, 6.0, 8.0, null, null, null, null],
    );
  });

  testWidgets('汇总卡：平均时长、达标判断与三格指标', (tester) async {
    await pumpRoute(tester, entries: threeNights());

    expect(find.text('平均睡眠时长'), findsOneWidget);
    // (8 + 6) / 2；分母是记录条数，不是日历天数。
    expect(find.text('7.0'), findsOneWidget);
    expect(find.text('小时'), findsOneWidget);
    expect(find.text('已达到睡眠目标'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('已达到睡眠目标')).style?.color,
      AppTokens.light.good,
      reason: '达标这句话用 good 薄荷绿',
    );

    expect(find.text('平均评分'), findsOneWidget);
    // 只有两条有评分：(90 + 70) / 2。
    expect(find.text('80'), findsOneWidget);
    expect(find.text('达标率'), findsOneWidget);
    // 只有 8h 那一晚够 7 小时：1 / 2 = 50%。
    expect(find.text('50%'), findsOneWidget);
    expect(find.text('记录夜数'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('平均不足 7 小时时写「目标 7 小时」', (tester) async {
    await pumpRoute(
      tester,
      entries: [night(DateTime(2026, 10, 14), hours: 5, insightScore: 62)],
    );

    expect(find.text('目标 7 小时'), findsOneWidget);
    expect(find.text('已达到睡眠目标'), findsNothing);
    expect(find.text('5.0'), findsWidgets, reason: '36px 数字与柱顶各一处');
  });

  testWidgets('翻到上一周期：抬头换了，周期内没有记录就是周期空状态', (tester) async {
    await pumpRoute(tester, entries: threeNights());

    await tester.tap(find.byKey(periodPreviousButtonKey));
    await tester.pumpAndSettle();

    expect(find.text('2026年10月5日 – 10月11日'), findsOneWidget);
    expect(find.text('0 条睡眠记录'), findsOneWidget);
    expect(find.text('这个周期还没有睡眠记录'), findsOneWidget);
    expect(find.text('可切换其他周期查看历史数据'), findsOneWidget);
    // 汇总卡照旧在，只是没有数字可写。列位不写占位符的规矩也一样。
    expect(find.text('—'), findsWidgets);
    expect(find.text('0%'), findsOneWidget);
    // **空库那句整页空状态不许出现**——库里明明有记录，只是这一周期没有。
    expect(find.text('还没有睡眠记录'), findsNothing);
  });

  testWidgets('已是最新周期时「下一个」禁用，往前翻过才可用', (tester) async {
    await pumpRoute(tester, entries: threeNights());

    expect(nextEnabled(tester), isFalse, reason: '开局就在最新一条所在的周期');
    expect(
      tester.widget<Pressable>(find.byKey(periodPreviousButtonKey)).onTap,
      isNotNull,
      reason: '往前翻没有边界',
    );

    await tester.tap(find.byKey(periodPreviousButtonKey));
    await tester.pumpAndSettle();
    expect(nextEnabled(tester), isTrue);

    await tester.tap(find.byKey(periodNextButtonKey));
    await tester.pumpAndSettle();
    expect(find.text('2026年10月12日 – 10月18日'), findsOneWidget);
    expect(nextEnabled(tester), isFalse, reason: '翻回最新周期后再次禁用');
  });

  testWidgets('在图表上右滑看上一周期，左滑回到最新周期', (tester) async {
    await pumpRoute(tester, entries: threeNights());
    final chart = find.byKey(allDataChartPageViewKey);
    expect(chart, findsOneWidget);

    await tester.fling(chart, const Offset(260, 0), 1000);
    await tester.pumpAndSettle();

    expect(find.text('2026年10月5日 – 10月11日'), findsOneWidget);
    expect(nextEnabled(tester), isTrue);

    await tester.pump();
    await tester.fling(
      find.byKey(allDataChartPageViewKey),
      const Offset(-260, 0),
      1000,
    );
    await tester.pumpAndSettle();

    expect(find.text('2026年10月12日 – 10月18日'), findsOneWidget);
    expect(nextEnabled(tester), isFalse);
  });

  testWidgets('最新周期继续左滑不会越过边界', (tester) async {
    await pumpRoute(tester, entries: threeNights());

    await tester.drag(
      find.byKey(allDataChartPageViewKey),
      const Offset(-180, 0),
    );
    await tester.pumpAndSettle();

    expect(find.text('2026年10月12日 – 10月18日'), findsOneWidget);
    expect(nextEnabled(tester), isFalse);
  });

  testWidgets('切到月：柱数换成当月天数，标签只在一号与逢五的日子写', (tester) async {
    await pumpRoute(tester, entries: threeNights());

    await tapSegment(tester, '月');

    expect(find.text('2026年10月'), findsOneWidget);
    expect(find.text('2 条睡眠记录'), findsOneWidget);
    final chart = chartOf(tester);
    expect(chart.bars.length, 31, reason: '2026 年 10 月有 31 天');
    expect(
      chart.bars.where((bar) => bar.showLabel).map((bar) => bar.label).toList(),
      ['1', '5', '10', '15', '20', '25', '30'],
    );
    final values = barsByLabel(tester);
    expect(values['13'], 6.0);
    expect(values['14'], 8.0);
    expect(values['15'], isNull);
  });

  testWidgets('切到年：12 根柱子，值取当月平均', (tester) async {
    await pumpRoute(tester, entries: threeNights());

    await tapSegment(tester, '年');

    expect(find.text('2026年'), findsOneWidget);
    expect(find.text('3 条睡眠记录'), findsOneWidget);
    final chart = chartOf(tester);
    expect(chart.bars.length, 12);
    expect(
      chart.bars.map((bar) => bar.label).toList(),
      [for (var month = 1; month <= 12; month++) '$month月'],
    );
    final values = barsByLabel(tester);
    // 10 月是 (8 + 6) / 2 的**当月平均**，不是某一晚也不是全年的 6.0。
    expect(values['10月'], 7.0);
    expect(values['9月'], 4.0);
    expect(values['11月'], isNull);
  });

  testWidgets('未评分的那一晚不写评分，也不写占位符', (tester) async {
    await pumpRoute(
      tester,
      entries: [night(DateTime(2026, 10, 14), quality: null)],
    );

    // 行里与汇总卡都不出现「评分 N」；卡里那格写破折号。
    expect(find.textContaining(RegExp(r'评分 \d')), findsNothing);
    expect(find.text('未评分'), findsNothing);
    expect(find.text('—'), findsWidgets);
    expect(find.text('8.0 小时'), findsOneWidget);
  });

  testWidgets('本地估算的分数写「估算」，不冒充「评分」', (tester) async {
    // 只有自评质量、没有阶段与录音的一晚：分数由本地规则算出来。
    // 首页对同一条记录写的也是「估算 NN」，详情弹层还会标「本地估算」。
    await pumpRoute(tester, entries: [night(DateTime(2026, 10, 14))]);

    expect(find.textContaining(RegExp(r'估算 \d')), findsOneWidget);
    expect(find.textContaining(RegExp(r'评分 \d')), findsNothing);
  });

  testWidgets('演示记录照列，并在汇总卡里如实说明有几条', (tester) async {
    await pumpRoute(tester, entries: [
      night(DateTime(2026, 10, 14)),
      // 醒来日分别是 10-13 与 10-12，都在本周（10-12 到 10-18）里。
      demoNight(DateTime(2026, 10, 12)),
      demoNight(DateTime(2026, 10, 11)),
    ]);

    // 照列：演示行也在列表里（与统计页同口径），徽章上是它们各自的醒来日。
    expect(find.text('14'), findsOneWidget);
    expect(find.text('13'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('3 条睡眠记录'), findsOneWidget, reason: '条数含演示记录');
    expect(find.text('其中 2 条是演示数据，不是你的记录'), findsOneWidget);
  });

  testWidgets('没有演示记录时不写那一句', (tester) async {
    await pumpRoute(tester, entries: [night(DateTime(2026, 10, 14))]);

    expect(find.textContaining('演示数据'), findsNothing);
  });

  testWidgets('一条记录都没有时是整页空状态，不是周期空状态', (tester) async {
    await pumpRoute(tester);

    expect(find.text('还没有睡眠记录'), findsOneWidget);
    // 没有数据就没有可翻的周期，也没有图可画。
    expect(find.text('周'), findsNothing);
    expect(find.text('这个周期还没有睡眠记录'), findsNothing);
    expect(find.byType(PeriodBarChart), findsNothing);
  });

  testWidgets('390 宽下不溢出（含 31 根柱子的月视图与一整个月的记录列表）', (
    tester,
  ) async {
    final month = [
      for (var day = 1; day <= 31; day++)
        night(DateTime(2026, 10, day),
            hours: 6 + day % 5, insightScore: 60 + day),
    ];
    await pumpRoute(tester, entries: month, size: const Size(390, 2600));

    await tapSegment(tester, '月');

    // 溢出是 `FlutterError`，会自己变成测试失败；这一句是显式的收据。
    expect(tester.takeException(), isNull);
    expect(chartOf(tester).bars.length, 31);
    // 一屏 31 行都在布局里：长时长（两位数）+ 质量标签 + 评分行是最挤的一行。
    expect(find.text('31 条睡眠记录'), findsOneWidget);
    expect(find.text('10.0 小时'), findsWidgets, reason: '两位数时长是最挤的一种');
  });
}
