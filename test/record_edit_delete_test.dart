import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/app/app.dart';
import 'package:night_sleep/core/database/app_database.dart'
    show AppDatabase, AppSetting, SoundClipsCompanion, databaseProvider;
import 'package:night_sleep/core/theme/app_theme.dart';
import 'package:night_sleep/core/theme/app_tokens.dart';
import 'package:night_sleep/core/widgets/app_basics.dart';
import 'package:night_sleep/core/widgets/app_icons.dart';
import 'package:night_sleep/features/home/presentation/home_page.dart';
import 'package:night_sleep/features/log/presentation/log_page.dart';
import 'package:night_sleep/features/sleep/data/clip_store.dart';
import 'package:night_sleep/features/sleep/data/demo_seed.dart';
import 'package:night_sleep/features/sleep/data/session_repository.dart';
import 'package:night_sleep/features/sleep/data/sleep_repository.dart';
import 'package:night_sleep/features/sleep/domain/sleep_entry.dart';
import 'package:night_sleep/features/sleep/domain/sleep_quality.dart';
import 'package:night_sleep/features/sleep/domain/sleep_score.dart';
import 'package:night_sleep/features/sleep/domain/sleep_stage.dart';

/// Correcting and removing a night that is already saved.
///
/// Two invariants carry most of the weight here, and both are easy to break
/// without noticing:
///
///  * Re-saving must land on the **same** record. A form that quietly inserts a
///    second copy would leave the user with a duplicate night and a wrong
///    weekly average.
///  * Re-saving must not touch the hypnogram. The form has no stage fields, so
///    "save what the form shows" would erase measured stages that the form never
///    knew about.
/// 假的片段文件仓库：**不碰文件系统**，只记下「谁被删了」。
///
/// 真 `ClipFileStore.platform()` 要 `path_provider` 的平台通道，而它继承下来的
/// `pathFor()` 还会真的建目录——两样在 `testWidgets` 的 FakeAsync 里都会挂住。
/// 与 `recording_settings_test.dart` 那个假仓库同一手法。
class _RecordingClipStore extends ClipFileStore {
  _RecordingClipStore()
      : super(baseDirectory: () async => Directory.systemTemp);

  final List<String?> deleted = [];

  @override
  Future<void> deleteClip(String? localUri) async => deleted.add(localUri);
}

void main() {
  late AppDatabase database;
  late SleepRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = SleepRepository(database);
  });

  tearDown(() => database.close());

  // 声明「系统开了减弱动态效果」。首页 hero 的月晕是**永远在跑**的呼吸动画
  // （规格 §3.4），只要有它挂着，`pumpAndSettle` 就永不收敛——凡是把首页建出来的
  // 用例都会踩到。放在 `setUp` 里，本文件每个 harness 都覆盖到。
  setUp(() {
    TestWidgetsFlutterBinding
            .instance.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
  });
  tearDown(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher
        .clearAccessibilityFeaturesTestValue();
  });

  // Anchored from local wall-clock so the assertions below read the same in any
  // machine time zone: the form shows `bedtimeLocal.toUtc().toLocal()`.
  final bedtime = DateTime(2026, 9, 26, 23, 30).toUtc();
  final wakeTime = DateTime(2026, 9, 27, 7, 0).toUtc();

  Future<SleepEntry> seedManual({
    String id = 'manual-1',
    SleepQuality quality = SleepQuality.good,
    String notes = '原始备注',
    List<SleepStageSegment> stages = const [],
  }) async {
    await repository.save(
      id: id,
      startAtUtc: bedtime,
      endAtUtc: wakeTime,
      timeZoneId: 'UTC',
      quality: quality,
      notes: notes,
      events: LoggedEvents.none,
      stages: stages,
    );
    final entries = await repository.loadAll();
    return entries.firstWhere((entry) => entry.id == id);
  }

  /// The settings row as a finished onboarding would leave it.
  AppSetting testSettings() => const AppSetting(
        id: 'default',
        themeMode: 'system',
        sleepGoalMinutes: 480,
        bedtimeReminderEnabled: false,
        bedtimeReminderMinutes: null,
        wakeReminderEnabled: false,
        wakeReminderMinutes: null,
        soundRecordingEnabled: false,
        onboarded: true,
        insightProvider: null,
        insightModel: null,
      );

  Future<void> pump(
    WidgetTester tester,
    Widget page, {
    List<SleepEntry> entries = const [],
    ClipFileStore? files,
  }) async {
    tester.view.physicalSize = const Size(430, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          sleepEntriesProvider.overrideWith((ref) => entries),
          settingsProvider.overrideWith(
            (ref) => Stream.value(testSettings()),
          ),
          // 首页会读 `activeSessionProvider`。不覆盖它会真订阅 drift 的
          // `watch*` 流，在 widget 测试里留下 pending timer（见 pages_widget_test
          // 文件头）。这些用例不关心会话，直接给 null。
          activeSessionProvider.overrideWith((ref) => null),
          // 真 `ClipFileStore.platform()` 要 `path_provider` 的平台通道。删一条
          // 没有录音的记录不会碰到它（`deleteClip(null)` 直接返回），但只要用例里
          // 有文件要删，就必须换成指向临时目录的这一份。
          if (files != null) clipFileStoreProvider.overrideWithValue(files),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: page),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 编辑表单现在是**推入页**：保存走 `Navigator.pop`。保存类用例必须真的把它
  /// 压在一个能 pop 的路由之上，否则会退到 `context.go('/')` 并因没有 GoRouter 抛错。
  /// 表单本身的内容用例仍可用 [pump] 直接挂载。
  Future<void> pumpPushed(
    WidgetTester tester,
    Widget page, {
    List<SleepEntry> entries = const [],
  }) async {
    tester.view.physicalSize = const Size(430, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          sleepEntriesProvider.overrideWith((ref) => entries),
          settingsProvider.overrideWith(
            (ref) => Stream.value(testSettings()),
          ),
          activeSessionProvider.overrideWith((ref) => null),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: Center(child: Text('外壳'))),
        ),
      ),
    );
    await tester.pumpAndSettle();
    tester
        .state<NavigatorState>(find.byType(Navigator).first)
        .push(MaterialPageRoute<void>(builder: (_) => page));
    await tester.pumpAndSettle();
  }

  // The nights arrive through the provider override, not the constructor.
  Widget home() => HomePage(
        animateRing: false,
        onRingConsumed: () {},
        onOpenNoise: () {},
        onStartSleep: () {},
      );

  group('详情弹层的入口', () {
    testWidgets('手动记录可以编辑和删除', (tester) async {
      final entry = await seedManual();
      await pump(tester, home(), entries: [entry]);

      await tester.tap(find.byType(HomeRecordRow).first);
      await tester.pumpAndSettle();

      expect(find.text('睡眠详情'), findsOneWidget);
      expect(find.text('编辑记录'), findsOneWidget);
      expect(find.text('删除记录'), findsOneWidget);
    });

    testWidgets('删除记录按钮与编辑记录一样带图标', (tester) async {
      final entry = await seedManual();
      await pump(tester, home(), entries: [entry]);

      await tester.tap(find.byType(HomeRecordRow).first);
      await tester.pumpAndSettle();

      final deleteAction = find.ancestor(
        of: find.text('删除记录'),
        matching: find.byType(Pressable),
      );
      expect(deleteAction, findsOneWidget, reason: '找不到「删除记录」按钮');
      // 图标身份断得到：`SvgPicture.bytesLoader` 是公开字段，`SvgStringLoader`
      // 又实现了值相等（逐字符比 SVG 文本、比 theme 与 colorMapper）。
      final tokens = AppTokens.of(tester.element(find.text('删除记录')));
      final rendered = tester.widget<SvgPicture>(
        find.descendant(of: deleteAction, matching: find.byType(SvgPicture)),
      );
      final expected = AppIcons.trash(
        size: 16,
        color: tokens.danger,
        strokeWidth: 2,
      );
      expect(
        rendered.bytesLoader,
        (expected as SvgPicture).bytesLoader,
        reason: '「删除记录」画的不是垃圾桶图标（或又变回纯文字了）',
      );
    });

    testWidgets('演示记录不给编辑删除入口，并说明原因', (tester) async {
      await DemoSeed.install(database, now: DateTime(2026, 9, 27, 12));
      final entries = await repository.loadAll();
      await pump(tester, home(), entries: entries);

      await tester.tap(find.byType(HomeRecordRow).first);
      await tester.pumpAndSettle();

      expect(find.text('编辑记录'), findsNothing);
      expect(find.text('删除记录'), findsNothing);
      expect(find.textContaining('这是演示数据，不能编辑或删除'), findsOneWidget);
    });
  });

  group('编辑入口打通整条链路', () {
    // The tests above drive the form directly. This one goes the way a user
    // does — record card → detail sheet → 编辑记录 → route — because the wiring
    // in between (route registration, the hand-off of the night through
    // go_router's `extra`) is exactly the part that no unit test would catch.
    //
    // The data still arrives through provider overrides rather than the real
    // drift streams: those drive their updates off timers, and a subscribed
    // query leaves a pending timer that the widget tester refuses to tear down.
    testWidgets('从详情弹层进入编辑页，表单已预填', (tester) async {
      final entry = await seedManual(notes: '待编辑的一晚');

      tester.view.physicalSize = const Size(430, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(database),
            sleepEntriesProvider.overrideWith((ref) => [entry]),
            settingsProvider.overrideWith(
              (ref) => Stream.value(testSettings()),
            ),
            // 外壳里的首页会读 `activeSessionProvider`。不覆盖它会真订阅 drift
            // 的流，测试拆树时留下 pending timer（见本文件上方注释）。
            activeSessionProvider.overrideWith((ref) => null),
          ],
          child: const NightSleepApp(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(HomeRecordRow).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑记录'));
      await tester.pumpAndSettle();

      expect(find.text('保存修改'), findsOneWidget, reason: '应落在编辑模式的表单上');
      expect(find.text('待编辑的一晚'), findsOneWidget, reason: '记录应随路由传递过来');
      expect(find.text('今天睡得怎么样？'), findsNothing, reason: '不应退化成新增表单');

      // Saving pops back to the shell. This is the branch the direct-form tests
      // cannot reach: there they are the root route, so nothing is poppable.
      await tester.tap(find.text('保存修改'));
      await tester.pumpAndSettle();

      expect(find.text('保存修改'), findsNothing, reason: '保存后应离开编辑页');
      expect(find.text('保存中…'), findsNothing, reason: '保存流程必须能走完');
      expect(find.text('夜深'), findsOneWidget, reason: '应回到标签外壳');
      expect(
        await database.allRecords(),
        hasLength(1),
        reason: '整条链路走完，仍然只能有一条记录',
      );

      // The toast this save raised is on a 3.6s auto-dismiss timer. That timer
      // is intentional, so the test has to run it out rather than the app
      // having to avoid it.
      await tester.pump(const Duration(seconds: 4));
    });
  });

  group('编辑表单', () {
    testWidgets('预填被编辑记录的原值', (tester) async {
      final entry = await seedManual(
        quality: SleepQuality.excellent,
        notes: '昨晚做梦了',
      );
      await pump(tester, LogPage(editing: entry));

      // Heading is the pushed page's, not the new-record one.
      expect(find.text('编辑记录'), findsOneWidget);
      expect(find.text('今天睡得怎么样？'), findsNothing);
      expect(find.text('保存修改'), findsOneWidget);

      expect(find.text('23:30'), findsOneWidget, reason: '入睡时间应预填');
      expect(find.text('07:00'), findsOneWidget, reason: '起床时间应预填');
      expect(find.text('2026-09-27'), findsOneWidget, reason: '日期按醒来日预填');
      expect(find.text('精力充沛'), findsOneWidget, reason: '主观质量应预填');
      expect(find.text('昨晚做梦了'), findsOneWidget, reason: '备注应预填');

      // The edit form is pushed over the shell and therefore inherits none of
      // its padding. This is the same trap that made the settings sub-pages
      // render edge-to-edge.
      expect(
        tester.getRect(find.text('睡眠时长')).left,
        greaterThanOrEqualTo(16),
        reason: '手机宽度下应有 16px 内边距',
      );
    });

    testWidgets('保存修改写回同一条记录，不新增也不改创建时间', (tester) async {
      // The stars are glyphs with no text, so they are reached through the
      // semantics label that also makes them usable with a screen reader.
      // `ensureSemantics` has to be released inside the test body: the binding
      // checks for leaked handles before tear-downs run.
      final semantics = tester.ensureSemantics();
      try {
        final entry = await seedManual(quality: SleepQuality.good);
        final createdAtBefore =
            (await database.findRecord(entry.id))!.createdAt;

        await pumpPushed(tester, LogPage(editing: entry));

        await tester.tap(find.bySemanticsLabel('睡眠质量 一般'));
        await tester.pumpAndSettle();
        expect(find.text('一般'), findsOneWidget, reason: '点击后标签应切换到「一般」');

        await tester.tap(find.text('保存修改'));
        await tester.pumpAndSettle();

        expect(find.text('外壳'), findsOneWidget, reason: '保存后应 pop 回下面的路由');
        expect(find.text('保存修改'), findsNothing, reason: '保存后应离开编辑页');

        final rows = await database.allRecords();
        expect(rows, hasLength(1), reason: '编辑不能变成新增');
        expect(rows.single.id, entry.id, reason: '必须落在原 id 上');
        expect(rows.single.quality, SleepQuality.fair.value);
        expect(
          rows.single.createdAt,
          createdAtBefore,
          reason: 'createdAt 是「最初记录时间」，不该被编辑改写',
        );
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('保存修改不会清空已有睡眠阶段', (tester) async {
      final entry = await seedManual(
        stages: [
          SleepStageSegment(
            stage: SleepStageType.deep,
            startAtUtc: bedtime,
            endAtUtc: bedtime.add(const Duration(minutes: 90)),
            source: 'import',
          ),
          SleepStageSegment(
            stage: SleepStageType.light,
            startAtUtc: bedtime.add(const Duration(minutes: 90)),
            endAtUtc: wakeTime,
            source: 'import',
          ),
        ],
      );
      expect(entry.hasStages, isTrue);

      await pumpPushed(tester, LogPage(editing: entry));
      await tester.tap(find.text('保存修改'));
      await tester.pumpAndSettle();

      final reloaded = (await repository.loadAll()).single;
      expect(
        reloaded.stages,
        hasLength(2),
        reason: '表单没有阶段字段，保存不能把测到的阶段抹掉',
      );
      expect(reloaded.stages.first.stage, SleepStageType.deep);
    });
  });

  group('删除记录', () {
    testWidgets('取消二次确认后记录仍在', (tester) async {
      final entry = await seedManual();
      await pump(tester, home(), entries: [entry]);

      await tester.tap(find.byType(HomeRecordRow).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除记录'));
      await tester.pumpAndSettle();

      expect(find.textContaining('删除 2026-09-27 的记录？'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(await database.allRecords(), hasLength(1), reason: '取消不得删除');
    });

    testWidgets('确认后记录被删除', (tester) async {
      final entry = await seedManual();
      await pump(tester, home(), entries: [entry]);

      await tester.tap(find.byType(HomeRecordRow).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除记录'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();

      expect(await database.allRecords(), isEmpty);
    });

    /// 这个洞是真机上报出来的：删完之后 **9 条片段行全没了、9 个 WAV 一个不少地留在
    /// 盘上**，而确认框写的是「声音事件都会被永久删除，此操作无法撤销」
    /// （`docs/verification-log.md` v3.19）。所以入口这一层也要有一条盯着它——
    /// 只测 `clip_pruning.dart` 里那个函数，挡不住有人把这里改回只删行。
    ///
    /// **这里断言的是「走到了文件仓库」，不是「文件真的没了」。** 真正删文件那一半在
    /// `test/clip_pruning_test.dart` 的普通 `test()` 里验——那是真实的文件系统操作，
    /// 而 `testWidgets` 的测试体跑在 FakeAsync 里，`Directory.createTemp` /
    /// `File.writeAsBytes` 这类真实 I/O 的 Future **永远不会完成**，测试会一路挂到
    /// 10 分钟超时（这不是推测，这条用例第一版就是这么挂的）。
    testWidgets('确认后记录被删除，并且真的走到了删录音文件那一步', (tester) async {
      final entry = await seedManual();
      const path = '/data/user/0/com.abner.night_sleep/files/clips/clip-1.wav';

      await database.insertClips([
        SoundClipsCompanion.insert(
          id: 'clip-1',
          recordId: entry.id,
          kind: 'noise',
          startedAtUtc: bedtime,
          durationMs: 3000,
          localUri: const Value(path),
          source: const Value('recording'),
        ),
      ]);

      final files = _RecordingClipStore();
      await pump(tester, home(), entries: [entry], files: files);
      await tester.tap(find.byType(HomeRecordRow).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除记录'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();

      expect(await database.allRecords(), isEmpty);
      expect(files.deleted, contains(path),
          reason: '确认框承诺「声音事件都会被永久删除」，删记录这条路就得走到文件仓库');
    });
  });
}
