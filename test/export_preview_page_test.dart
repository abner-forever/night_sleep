import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/core/theme/app_theme.dart';
import 'package:night_sleep/features/settings/presentation/export_preview_page.dart';
import 'package:night_sleep/features/sleep/data/sleep_repository.dart';
import 'package:night_sleep/features/sleep/domain/sleep_entry.dart';
import 'package:night_sleep/features/sleep/domain/sleep_quality.dart';
import 'package:night_sleep/features/sleep/domain/sleep_stage.dart';

/// 导出表格预览页的 widget 测试。
///
/// 这一页的表格来自 `SleepExporter.tables()`，与文件同源那一条由
/// `test/sleep_export_test.dart` 的往返断言钉住；这里管的是界面：
/// 换表、截断说明、空状态与「推入页要自己带 Material」。
void main() {
  /// 第 [index] 晚：醒来时刻按天递增，好让导出顺序与 id 顺序一致。
  SleepEntry entry({
    required int index,
    String? id,
    String source = 'manual',
    int stages = 0,
    String notes = '',
  }) {
    final end = DateTime.utc(2026, 9, 1, 7).add(Duration(days: index));
    final start = end.subtract(const Duration(hours: 8));
    return SleepEntry(
      id: id ?? 'r$index',
      startAtUtc: start,
      endAtUtc: end,
      timeZoneId: 'UTC',
      quality: SleepQuality.good,
      notes: notes,
      source: source,
      createdAtUtc: end,
      updatedAtUtc: end,
      stages: [
        for (var i = 0; i < stages; i++)
          SleepStageSegment(
            stage: SleepStageType.deep,
            startAtUtc: start.add(Duration(hours: i)),
            endAtUtc: start.add(Duration(hours: i + 1)),
          ),
      ],
    );
  }

  /// 二级页由路由器推入：**没有 Scaffold**，页面自己带。
  /// 这里补 Scaffold 就等于把背景和 Material 白送给它，测试会全绿而真机是黑底。
  Future<void> pumpRoute(
    WidgetTester tester, {
    List<SleepEntry> entries = const [],
    // 表格是**一个**子项：`Subpage` 的 ListView 只会整块建它，而表格下面那几行
    // 说明要等它建完才轮得到。行多的时候得把视口开高，否则说明还没被建出来
    // ——那不是「没写」，只是「还没滚到」。
    Size surface = const Size(430, 2600),
  }) async {
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sleepEntriesProvider.overrideWith((ref) => entries)],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ExportPreviewPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('默认是记录表：表头、单元格与文件名都在页面上', (tester) async {
    await pumpRoute(tester, entries: [entry(index: 0, stages: 2)]);

    expect(find.text('日期'), findsOneWidget);
    expect(find.text('记录ID'), findsOneWidget);
    expect(find.text('r0'), findsOneWidget);
    expect(find.textContaining('夜深-睡眠记录-'), findsOneWidget);
    expect(find.textContaining('共 1 行'), findsOneWidget);

    // 阶段表还没被选中，它的表头不该在页面上（「时长(分钟)」两张表都有，用它区分不了）。
    expect(find.text('开始时间'), findsNothing);
  });

  testWidgets('切到阶段表换成另一张表的表头与行', (tester) async {
    await pumpRoute(tester, entries: [entry(index: 0, stages: 2)]);

    await tester.tap(find.text('阶段'));
    await tester.pumpAndSettle();

    expect(find.text('开始时间'), findsOneWidget);
    expect(find.text('深睡'), findsNWidgets(2), reason: '一行一段');
    expect(find.textContaining('夜深-睡眠阶段-'), findsOneWidget);
    expect(find.text('日期'), findsNothing);
  });

  testWidgets('超过上限时如实说明，且不渲染上限之外的行', (tester) async {
    await pumpRoute(
      tester,
      entries: [for (var i = 0; i < 60; i++) entry(index: i)],
      surface: const Size(430, 4400),
    );

    expect(find.textContaining('共 60 行'), findsOneWidget);
    expect(find.textContaining('预览只显示前 50 行'), findsOneWidget);
    expect(find.textContaining('文件包含全部 60 行'), findsOneWidget);

    // 边界两侧各钉一格：少了这一对，说明文字写得再准也管不住真的渲染了几行。
    expect(find.text('r49'), findsOneWidget);
    expect(find.text('r50'), findsNothing);
  });

  testWidgets('行数不超上限时没有那句说明', (tester) async {
    await pumpRoute(tester, entries: [
      for (var i = 0; i < 50; i++) entry(index: i),
    ]);

    expect(find.text('r49'), findsOneWidget);
    expect(find.textContaining('预览只显示前'), findsNothing);
  });

  testWidgets('演示记录不进预览，并说明排除了几条', (tester) async {
    await pumpRoute(tester, entries: [
      entry(index: 0),
      entry(index: 1, id: 'demo-1', source: 'demo'),
    ]);

    expect(find.text('r0'), findsOneWidget);
    expect(find.text('demo-1'), findsNothing);
    expect(find.textContaining('已排除 1 条演示记录'), findsOneWidget);
    expect(find.textContaining('共 1 行'), findsOneWidget);
  });

  testWidgets('一条可导出的记录都没有时是空状态', (tester) async {
    await pumpRoute(tester, entries: [
      entry(index: 0, id: 'demo-1', source: 'demo'),
      entry(index: 1, id: 'demo-2', source: 'demo'),
    ]);

    expect(find.text('暂无可预览的记录'), findsOneWidget);
    expect(find.textContaining('这 2 条都是演示记录'), findsOneWidget);
    expect(find.text('日期'), findsNothing);
  });

  testWidgets('推入页自己带 Material：文字不带错误样式的下划线', (tester) async {
    await pumpRoute(tester, entries: [entry(index: 0)]);

    final header = find.text('日期');
    expect(
      DefaultTextStyle.of(tester.element(header)).style.decoration,
      isNot(TextDecoration.underline),
      reason: '带下划线说明它落在了 Flutter 的无 Material 错误样式上',
    );
    expect(
      find.ancestor(of: header, matching: find.byType(Material)),
      findsWidgets,
    );
  });
}
