import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/core/config/app_config.dart';
import 'package:night_sleep/core/database/app_database.dart'
    hide SleepStageSegment;
import 'package:night_sleep/core/theme/app_theme.dart';
import 'package:night_sleep/core/theme/app_tokens.dart';
import 'package:night_sleep/core/widgets/wheel_picker.dart';
import 'package:night_sleep/features/log/presentation/review_page.dart';
import 'package:night_sleep/features/sleep/data/sleep_repository.dart';
import 'package:night_sleep/features/sleep/domain/sleep_entry.dart';
import 'package:night_sleep/features/sleep/domain/sleep_quality.dart';
import 'package:night_sleep/features/sleep/domain/sleep_stage.dart';
import 'package:night_sleep/features/sleep/presentation/widgets/quality_rating.dart';

/// 回顾页：给已有的一晚补主观感受。
///
/// 夹具沿用 `pages_widget_test.dart` 的写法——`Scaffold(body:)` + provider 覆盖，
/// **不订阅 drift 的 `watch*` 流**（它们靠定时器驱动，在 FakeAsync 里会留下
/// pending timer）。记录真的写进内存库，写路径的用例直接断言数据库。
void main() {
  late AppDatabase database;
  late SleepRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = SleepRepository(database);
  });
  tearDown(() => database.close());

  /// 一条真实记录。`date` 是**醒来日**，入睡在它前一天 23:00、起床 07:00。
  SleepEntry realEntry({
    required String date,
    String? id,
    SleepQuality? quality = SleepQuality.good,
    String source = 'session',
    String notes = '',
    List<SleepStageSegment> stages = const [],
  }) {
    final wake = DateTime.parse(date);
    final start = DateTime(wake.year, wake.month, wake.day - 1, 23, 0);
    final end = DateTime(wake.year, wake.month, wake.day, 7, 0);
    return SleepEntry(
      id: id ?? date,
      startAtUtc: start.toUtc(),
      endAtUtc: end.toUtc(),
      timeZoneId: 'UTC',
      quality: quality,
      notes: notes,
      source: source,
      stages: stages,
      createdAtUtc: start.toUtc(),
      updatedAtUtc: start.toUtc(),
    );
  }

  /// 一条演示记录：`source == 'demo'`。
  SleepEntry demoEntry({String date = '2026-08-01'}) {
    final wake = DateTime.parse(date);
    final start = DateTime(wake.year, wake.month, wake.day - 1, 23, 0);
    final end = DateTime(wake.year, wake.month, wake.day, 7, 0);
    return SleepEntry(
      id: 'demo-$date',
      startAtUtc: start.toUtc(),
      endAtUtc: end.toUtc(),
      timeZoneId: 'UTC',
      quality: SleepQuality.good,
      source: AppConfig.demoSource,
      createdAtUtc: start.toUtc(),
      updatedAtUtc: start.toUtc(),
    );
  }

  /// 把 [entries] 真的写进库，再让页面通过 provider 覆盖读到它们。
  ///
  /// 写进库不是多余的：保存类用例断言的是数据库，只覆盖 provider 不落库，
  /// 「写回同一条 id」就无从谈起。
  Future<void> pumpReview(
    WidgetTester tester, {
    required List<SleepEntry> entries,
  }) async {
    for (final entry in entries) {
      await repository.save(
        id: entry.id,
        startAtUtc: entry.startAtUtc,
        endAtUtc: entry.endAtUtc,
        timeZoneId: entry.timeZoneId,
        quality: entry.quality,
        notes: entry.notes,
        events: entry.loggedEvents,
        stages: entry.stages,
        source: entry.source,
      );
    }
    final stored = await repository.loadAll();

    tester.view.physicalSize = const Size(430, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          sleepEntriesProvider.overrideWith((ref) => stored),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: ReviewPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('默认补充最近一条真实记录', (tester) async {
    await pumpReview(tester, entries: [realEntry(date: '2026-08-30')]);

    expect(find.textContaining('8月30日'), findsOneWidget);
    expect(find.text('来自：睡眠会话'), findsOneWidget);
  });

  testWidgets('只有演示数据时说明不可补充', (tester) async {
    await pumpReview(tester, entries: [demoEntry()]);

    expect(find.textContaining('演示'), findsWidgets);
    expect(find.text('手动补录某一晚'), findsOneWidget);
  });

  testWidgets('没有任何记录时走空状态', (tester) async {
    await pumpReview(tester, entries: const []);

    expect(find.text('还没有可回顾的记录'), findsOneWidget);
  });

  testWidgets('可以换到别的晚上', (tester) async {
    await pumpReview(tester, entries: [
      realEntry(date: '2026-08-30', id: 'a'),
      realEntry(date: '2026-08-29', id: 'b'),
    ]);

    expect(find.textContaining('8月30日'), findsOneWidget);

    await tester.tap(find.textContaining('8月30日'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('8月29日'));
    await tester.pumpAndSettle();

    expect(find.textContaining('8月29日'), findsWidgets);
    // 换过之后记录头不能再停在原来那一晚。
    expect(find.textContaining('8月30日'), findsNothing);
  });

  testWidgets('选择器里不出现演示记录', (tester) async {
    await pumpReview(tester, entries: [
      realEntry(date: '2026-08-30'),
      demoEntry(date: '2026-08-01'),
    ]);

    await tester.tap(find.textContaining('8月30日'));
    await tester.pumpAndSettle();

    // 选择器确实开了，且真实记录在里面——这样「演示记录不在」才不是空断言。
    expect(find.text('换一晚回顾'), findsOneWidget, reason: '选择器没打开');
    expect(find.text('8月30日'), findsWidgets, reason: '选择器里应有真实记录');
    expect(find.text('8月1日'), findsNothing, reason: '演示记录不该出现在选择器里');
  });

  testWidgets('未评分的记录，药丸一个都不选中', (tester) async {
    await pumpReview(tester,
        entries: [realEntry(date: '2026-08-30', quality: null)]);

    final choice = tester.widget<QualityChoice>(find.byType(QualityChoice));
    expect(choice.value, isNull);
    // v3.34 起未选时**不摆占位符、也不显示任何一句即时反馈**——原来那个
    // 「未评分」的占位符随五星一起删掉了（规格 §3.3）。默认高亮某一档
    // 等于应用替用户打了一个分，那是偏差 #26 的红线。
    expect(find.text('未评分'), findsNothing);
    for (final feedback in const [
      '今晚早点休息',
      '要留意一下节律',
      '还算平稳',
      '状态不错',
      '休息得很好',
    ]) {
      expect(find.text(feedback), findsNothing, reason: '未选时不该有反馈句');
    }
  });

  testWidgets('质量选中态不给整项或星标圆铺底色', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await pumpReview(tester, entries: [realEntry(date: '2026-08-30')]);

      final item = find.bySemanticsLabel('睡眠质量 良好');
      final containers = find.descendant(
        of: item,
        matching: find.byType(AnimatedContainer),
      );
      final outer = tester
          .widget<AnimatedContainer>(containers.first)
          .decoration! as BoxDecoration;
      final orb = tester.widget<AnimatedContainer>(containers.at(1)).decoration!
          as BoxDecoration;
      expect(outer.color, Colors.transparent);
      expect(
        orb.color,
        Colors.transparent,
        reason: '选中态不能再用色块填充背景',
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('睡眠事件按设计稿使用胶囊选中色，安稳项不显示勾选', (tester) async {
    await pumpReview(tester, entries: [realEntry(date: '2026-08-30')]);

    final calmChip = find.byKey(const ValueKey('review-event-calm'));
    final calm = find
        .descendant(of: calmChip, matching: find.byType(AnimatedContainer))
        .first;
    final tokens = AppTokens.of(tester.element(calmChip));
    var calmDecoration =
        tester.widget<AnimatedContainer>(calm).decoration! as BoxDecoration;
    expect(
      calmDecoration.color,
      colorMix(tokens.good, 0.18, tokens.bgCard),
    );
    expect(
      find.descendant(of: calmChip, matching: find.byType(SvgPicture)),
      findsOneWidget,
      reason: '「一切安稳」的设计稿只有月亮图标，没有额外勾选',
    );

    await tester.tap(find.text('打鼾'));
    await tester.pumpAndSettle();

    final snoreChip = find.byKey(const ValueKey('review-event-打鼾'));
    final snore = find
        .descendant(of: snoreChip, matching: find.byType(AnimatedContainer))
        .first;
    calmDecoration =
        tester.widget<AnimatedContainer>(calm).decoration! as BoxDecoration;
    final snoreDecoration =
        tester.widget<AnimatedContainer>(snore).decoration! as BoxDecoration;
    expect(calmDecoration.color, tokens.bgCard);
    expect(
      snoreDecoration.color,
      colorMix(tokens.warn, 0.14, tokens.bgCard),
    );
    expect(
      find.descendant(of: snoreChip, matching: find.byType(SvgPicture)),
      findsNWidgets(2),
      reason: '普通事件选中后应保留事件图标并追加勾选',
    );
  });

  testWidgets('保存写回同一条 id，不新增副本', (tester) async {
    await pumpReview(tester,
        entries: [realEntry(date: '2026-08-30', id: 'night-a')]);

    await tester.tap(find.text('保存补充'));
    await tester.pumpAndSettle();

    final rows = await database.allRecords();
    expect(rows, hasLength(1));
    expect(rows.single.id, 'night-a');
  });

  testWidgets('保存补充时不改动起止时刻', (tester) async {
    final before = realEntry(date: '2026-08-30', id: 'night-a');
    await pumpReview(tester, entries: [before]);

    await tester.tap(find.text('保存补充'));
    await tester.pumpAndSettle();

    final row = (await database.allRecords()).single;
    // drift 读回来的是本地时区表示，域对象存的是 UTC——比同一个瞬间，不比表示。
    expect(row.startAtUtc.toUtc(), before.startAtUtc);
    expect(row.endAtUtc.toUtc(), before.endAtUtc);
  });

  testWidgets('在回顾页改入睡时间后保存会写回新的起止时刻', (tester) async {
    final before = realEntry(date: '2026-08-30', id: 'night-time');
    await pumpReview(tester, entries: [before]);

    await tester.tap(find.text('入睡时间'));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byType(WheelColumn).first,
      const Offset(0, -WheelColumn.itemExtent),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存补充'));
    await tester.pumpAndSettle();

    final row = (await database.allRecords()).single;
    expect(row.startAtUtc.toUtc(), isNot(before.startAtUtc));
    expect(row.endAtUtc.toUtc(), before.endAtUtc);
  });

  testWidgets('保存补充不会清空已有的睡眠阶段', (tester) async {
    // 设备测到的阶段必须活过这次「补感受」。`save()` 的 `stages` 传 null 才是
    // 「保持不变」；传空列表就会把整段记录抹掉。
    final start = DateTime(2026, 8, 29, 23, 0).toUtc();
    final end = DateTime(2026, 8, 30, 7, 0).toUtc();
    final before = realEntry(
      date: '2026-08-30',
      id: 'night-stages',
      stages: [
        SleepStageSegment(
          stage: SleepStageType.deep,
          startAtUtc: start,
          endAtUtc: start.add(const Duration(minutes: 90)),
          source: 'import',
        ),
        SleepStageSegment(
          stage: SleepStageType.light,
          startAtUtc: start.add(const Duration(minutes: 90)),
          endAtUtc: end,
          source: 'import',
        ),
      ],
    );
    await pumpReview(tester, entries: [before]);

    await tester.tap(find.text('保存补充'));
    await tester.pumpAndSettle();

    final reloaded = (await repository.loadAll()).single;
    expect(reloaded.stages, hasLength(2), reason: '补感受不能抹掉测到的阶段');
    expect(reloaded.stages.first.stage, SleepStageType.deep);
  });

  testWidgets('保存的是用户改过的质量，不是原值', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await pumpReview(
        tester,
        entries: [
          realEntry(
              date: '2026-08-30', id: 'night-q', quality: SleepQuality.veryPoor)
        ],
      );

      await tester.tap(find.bySemanticsLabel('睡眠质量 极好'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存补充'));
      await tester.pumpAndSettle();

      expect(
        (await database.allRecords()).single.quality,
        SleepQuality.excellent.value,
        reason: '落库的该是用户点的那一档，不是记录原来的值',
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('保存补充是大圆角居中按钮', (tester) async {
    await pumpReview(tester, entries: [realEntry(date: '2026-08-30')]);

    final button = find.byKey(const ValueKey('review-save'));
    final buttonRect = tester.getRect(button);
    final labelRect = tester.getRect(find.text('保存补充'));
    final container = tester.widget<Container>(
      find.descendant(of: button, matching: find.byType(Container)).first,
    );
    final decoration = container.decoration! as BoxDecoration;

    expect(buttonRect.height, greaterThanOrEqualTo(54));
    expect(
      labelRect.center.dx,
      moreOrLessEquals(buttonRect.center.dx, epsilon: 1),
    );
    expect(decoration.borderRadius, BorderRadius.circular(27));
  });

  testWidgets('睡眠时间三行的标签列与值列等宽', (tester) async {
    await pumpReview(tester, entries: [realEntry(date: '2026-08-30')]);

    for (final label in ['日期', '入睡时间', '起床时间']) {
      final labelCell = tester.getSize(
        find.byKey(ValueKey('review-time-label-cell-$label')),
      );
      final valueCell = tester.getSize(
        find.byKey(ValueKey('review-time-value-cell-$label')),
      );
      expect(
        labelCell.width,
        moreOrLessEquals(valueCell.width, epsilon: 0.01),
        reason: '$label 行的标签和值没有按两端等宽布局',
      );
    }
  });
}
