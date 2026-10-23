// 详情页「声音记录」区块：重新分析之后必须有一句结果。
//
// 这一条是 2026-10-16 使用方报出来的：他录了一整晚、点了「重新分析」，
// 屏幕上从标题到展开区一个字都没变，看起来就是那个按钮没生效。真相是判定规则
// 宁弃权不猜——那天 27 段全部弃权。**机器沉默这件事本身必须被说出来**，否则
// 「跑了、没结论」与「没跑」在界面上完全一样。
//
// 这里只钉「说了什么」，不钉声学判定本身——那一半在 `clip_analysis_test.dart`。

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/app/app.dart';
import 'package:night_sleep/app/app_toast.dart';
import 'package:night_sleep/core/database/app_database.dart'
    show
        AppDatabase,
        AppSetting,
        SleepRecordsCompanion,
        SoundClipsCompanion,
        databaseProvider;
import 'package:night_sleep/core/theme/app_theme.dart';
import 'package:night_sleep/core/widgets/app_sheet.dart';
import 'package:night_sleep/features/settings/data/insight_credentials.dart';
import 'package:night_sleep/features/sleep/data/clip_analyzer.dart';
import 'package:night_sleep/features/sleep/data/sleep_repository.dart';
import 'package:night_sleep/features/sleep/domain/sleep_entry.dart';
import 'package:night_sleep/features/sleep/presentation/sheets/detail_sheet.dart';
import 'package:night_sleep/features/sleep/presentation/sheets/sound_card.dart';

/// 假的声学分析器：**不碰磁盘、不开 isolate**。
///
/// 它只回答「这一趟算了几段」——真分析要读 WAV 文件，那是集成测试的事。
class _StubAnalyzer extends ClipAnalyzer {
  _StubAnalyzer(super.db, this.settled);

  /// `analyseRecord` 要返回的数字（真实的语义是「这一趟定案了几段」）。
  final int settled;

  int calls = 0;

  @override
  Future<int> analyseRecord(String recordId) async {
    calls++;
    return settled;
  }
}

/// 写不进去的分析器：验「失败也要说」。
class _FailingAnalyzer extends ClipAnalyzer {
  _FailingAnalyzer(super.db);

  @override
  Future<int> analyseRecord(String recordId) async => throw StateError('磁盘满了');
}

void main() {
  late AppDatabase database;

  setUp(() => database = AppDatabase(NativeDatabase.memory()));
  tearDown(() => database.close());

  Future<SleepEntry> seedNight({
    int clips = 0,
    int withVerdict = 0,
  }) async {
    await database.saveRecord(
      SleepRecordsCompanion.insert(
        id: 'rec-1',
        startAtUtc: DateTime(2026, 10, 15, 1).toUtc(),
        endAtUtc: DateTime(2026, 10, 16, 8, 30).toUtc(),
        createdAt: DateTime(2026, 10, 15, 1).toUtc(),
        updatedAt: DateTime(2026, 10, 15, 1).toUtc(),
      ),
    );
    await database.insertClips([
      for (var i = 0; i < clips; i++)
        SoundClipsCompanion.insert(
          id: 'clip-$i',
          recordId: 'rec-1',
          kind: 'noise',
          startedAtUtc: DateTime(2026, 10, 16, 1, i).toUtc(),
          durationMs: 1500,
          source: const Value('recording'),
        ),
    ]);
    // 有结论的那几段：直接按落库的形状写 `auto_analysis` + `analysed`。
    for (var i = 0; i < withVerdict; i++) {
      await database.updateClipAutoAnalysis(
        'clip-$i',
        payload: '{"kind":"snore","margin":0.5,"basis":"低频能量 66%",'
            '"startMs":0,"durationMs":3000,"atUtc":"2026-10-16T00:00:00.000Z"}',
        status: 'analysed',
      );
    }
    final entries = await SleepRepository(database).loadAll();
    return entries.single;
  }

  Future<ProviderContainer> pumpSheet(
    WidgetTester tester,
    SleepEntry entry, {
    required ClipAnalyzer analyzer,
    Size size = const Size(430, 2600),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const settings = AppSetting(
      id: 'default',
      themeMode: 'system',
      sleepGoalMinutes: 480,
      bedtimeReminderEnabled: false,
      bedtimeReminderMinutes: null,
      wakeReminderEnabled: false,
      wakeReminderMinutes: null,
      soundRecordingEnabled: true,
      onboarded: true,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          sleepEntriesProvider.overrideWith((ref) => [entry]),
          settingsProvider.overrideWith((ref) => Stream.value(settings)),
          insightApiKeyProvider.overrideWith(_NoKey.new),
          clipAnalyzerProvider.overrideWithValue(analyzer),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showSleepDetailSheet(context, entry),
                child: const Text('打开详情'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开详情'));
    await tester.pumpAndSettle();

    return ProviderScope.containerOf(
      tester.element(find.byType(DetailSheet)),
    );
  }

  testWidgets('全部弃权时说清「看过几段、一段都没把握」，而不是让界面一动不动', (tester) async {
    final entry = await seedNight(clips: 27);
    final analyzer = _StubAnalyzer(database, 27);
    final container = await pumpSheet(tester, entry, analyzer: analyzer);

    await tester.tap(find.text('重新分析'));
    await tester.pumpAndSettle();

    expect(analyzer.calls, 1);
    final toast = container.read(toastProvider);
    expect(toast, contains('看过 27 段'));
    expect(toast, contains('没有一段有把握'));
    expect(toast, contains('待标注'));
  });

  testWidgets('有结论时把「几段」报出来', (tester) async {
    final entry = await seedNight(clips: 4, withVerdict: 1);
    await pumpSheet(tester, entry, analyzer: _StubAnalyzer(database, 4));

    await tester.tap(find.text('重新分析'));
    await tester.pumpAndSettle();

    expect(
      ProviderScope.containerOf(tester.element(find.byType(DetailSheet)))
          .read(toastProvider),
      contains('其中 1 段给出了自动判断'),
    );
  });

  testWidgets('一段都没定案时说「没有可分析的片段」，不说成「都判过了」', (tester) async {
    // 真实的来法是录音已被保留期限清掉：`analyseRecord` 会把没有文件的那几段跳过。
    final entry = await seedNight(clips: 2);
    await pumpSheet(tester, entry, analyzer: _StubAnalyzer(database, 0));

    await tester.tap(find.text('重新分析'));
    await tester.pumpAndSettle();

    expect(
      ProviderScope.containerOf(tester.element(find.byType(DetailSheet)))
          .read(toastProvider),
      contains('没有可分析的片段'),
    );
  });

  testWidgets('手机详情铺满屏幕，与内容多少无关', (tester) async {
    for (final clips in [0, 2]) {
      final entry = await seedNight(clips: clips);
      await pumpSheet(
        tester,
        entry,
        analyzer: _StubAnalyzer(database, clips),
        size: const Size(430, 900),
      );

      expect(
        tester.getSize(find.byType(AppSheet)).height,
        closeTo(900, 0.5),
        reason: '$clips 段时详情没有铺满屏幕',
      );

      tester
          .state<NavigatorState>(find.byType(Navigator).first)
          .popUntil((route) => route.isFirst);
      await tester.pumpAndSettle();
    }
  });

  // 2026-10-18 使用方报的：手机上最近两晚录音很多，打开详情弹窗几乎看不到
  // 进场动画。病灶是 `SingleChildScrollView` + `Column` 一次把**所有**卡片
  // 建完，每张卡再带上千根波形条。这里钉住两条：首帧只建视口里的那几张；
  // 滚动之后后面的卡片仍然能建出来。
  testWidgets('片段很多时按需构建：首帧只建视口里的卡，滚动后仍能读到末尾', (tester) async {
    final entry = await seedNight(clips: 60);
    await pumpSheet(
      tester,
      entry,
      analyzer: _StubAnalyzer(database, 60),
      size: const Size(430, 932),
    );

    // 视口约 850 逻辑像素，一张卡约 110px；60 张卡铺开是它的三倍多。
    expect(
      find.byType(SoundCard).evaluate().length,
      lessThan(20),
      reason: '首帧把 60 张卡全建了——又回到打开卡顿的老路',
    );
    // sliver 路径的左右留白与整块滚动那条路一致（430 − 20 × 2）。
    expect(tester.getSize(find.byType(SoundCard).first).width, 398);

    await tester.scrollUntilVisible(
      find.text('编辑记录'),
      600,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 80,
    );
    expect(find.text('编辑记录'), findsOneWidget);
  });

  testWidgets('分析抛错时给出「分析失败」，不静默', (tester) async {
    final entry = await seedNight(clips: 2);
    await pumpSheet(tester, entry, analyzer: _FailingAnalyzer(database));

    await tester.tap(find.text('重新分析'));
    await tester.pumpAndSettle();

    expect(
      ProviderScope.containerOf(tester.element(find.byType(DetailSheet)))
          .read(toastProvider),
      contains('分析失败'),
    );
  });
}

/// 没有 API Key——这一组用例关心的是声学分析那一半，不该顺带把洞察那半跑起来。
class _NoKey extends InsightApiKeyNotifier {
  @override
  String build() => '';
}
