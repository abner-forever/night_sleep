import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:night_sleep/app/app.dart';
import 'package:night_sleep/app/app_shell.dart';
import 'package:night_sleep/core/database/app_database.dart';
import 'package:night_sleep/core/theme/app_theme.dart';
import 'package:night_sleep/core/theme/app_tokens.dart';
import 'package:night_sleep/core/widgets/app_basics.dart';
import 'package:night_sleep/core/widgets/app_icons.dart';
import 'package:night_sleep/core/widgets/app_menu_field.dart';
import 'package:night_sleep/core/widgets/glass_surface.dart';
import 'package:night_sleep/core/widgets/hero_surface.dart';
import 'package:night_sleep/core/widgets/ios_controls.dart';
import 'package:night_sleep/core/widgets/subpage.dart';
import 'package:night_sleep/core/widgets/top_fade.dart';
import 'package:night_sleep/features/home/presentation/home_page.dart';
import 'package:night_sleep/features/compass/presentation/compass_page.dart';
import 'package:night_sleep/features/log/presentation/log_page.dart';
import 'package:night_sleep/features/sleep/presentation/widgets/quality_rating.dart';
import 'package:night_sleep/features/settings/presentation/appearance_settings_page.dart';
import 'package:night_sleep/features/settings/presentation/about_page.dart';
import 'package:night_sleep/features/settings/presentation/demo_data_page.dart';
import 'package:night_sleep/features/settings/presentation/export_page.dart';
import 'package:night_sleep/features/settings/presentation/export_preview_page.dart';
import 'package:night_sleep/features/settings/data/app_cache.dart';
import 'package:night_sleep/features/settings/data/insight_credentials.dart';
import 'package:night_sleep/features/settings/data/insight_service.dart';
import 'package:night_sleep/features/settings/presentation/insight_config_page.dart';
import 'package:night_sleep/features/settings/presentation/settings_page.dart';
import 'package:night_sleep/features/settings/presentation/sleep_import_page.dart';
import 'package:night_sleep/features/settings/presentation/sleep_settings_page.dart';
import 'package:night_sleep/features/settings/presentation/widgets/goal_slider.dart';
import 'package:night_sleep/features/sleep/data/demo_seed.dart';
import 'package:night_sleep/features/sleep/data/session_repository.dart';
import 'package:night_sleep/features/sleep/data/sleep_repository.dart';
import 'package:night_sleep/features/sleep/domain/sleep_entry.dart';
import 'package:night_sleep/features/sleep/domain/sleep_quality.dart';
import 'package:night_sleep/features/sleep/domain/sleep_score.dart';
import 'package:night_sleep/features/sleep/domain/sleep_session.dart';
import 'package:night_sleep/features/sleep/domain/sleep_stage.dart';
import 'package:night_sleep/features/sleep/domain/sound_event.dart' as domain;
import 'package:night_sleep/features/stats/presentation/all_sleep_data_page.dart';
import 'package:night_sleep/features/stats/presentation/stats_page.dart';
import 'package:package_info_plus/package_info_plus.dart';

void _noop() {}

/// Widget tests for the four primary pages.
///
/// These deliberately **do not** subscribe to the app's drift streams.
/// `watchAllRecords` / `watchSettings` drive their updates off timers, which
/// the widget-tester's fake clock never advances, so a subscribed query leaves
/// a pending timer at teardown (and can hang the test outright). Instead the
/// pages are handed the same data through provider overrides, and the two tests
/// that exercise a write path assert against the database directly.
/// 一条 `daysAgo` 天前醒来的记录（本机时区的墙钟时刻，跨时区跑也稳）。
///
/// **带声音事件**：柱状图每根柱子下面那行小图标就是它们画的。不带的话那行是空的，
/// 「窄柱子上图标放不下」这件事在测试里根本不会发生——用户报的溢出正是从那里来的。
SleepEntry _nightDaysAgo(int daysAgo) {
  final end = DateTime(2026, 10, 15, 7).subtract(Duration(days: daysAgo));
  final start = end.subtract(const Duration(hours: 8));
  return SleepEntry(
    id: 'r$daysAgo',
    startAtUtc: start.toUtc(),
    endAtUtc: end.toUtc(),
    timeZoneId: 'UTC',
    quality: SleepQuality.good,
    createdAtUtc: end.toUtc(),
    updatedAtUtc: end.toUtc(),
    soundClips: [
      domain.SoundClip(
        id: 'snore-$daysAgo',
        kind: domain.SoundEventKind.snore,
        startedAtUtc: start.add(const Duration(hours: 1)).toUtc(),
        durationMs: 30000,
      ),
      domain.SoundClip(
        id: 'talk-$daysAgo',
        kind: domain.SoundEventKind.talk,
        startedAtUtc: start.add(const Duration(hours: 2)).toUtc(),
        durationMs: 8000,
      ),
    ],
  );
}

void main() {
  late AppDatabase database;

  setUp(() => database = AppDatabase(NativeDatabase.memory()));
  tearDown(() => database.close());

  // 声明「系统开了减弱动态效果」。首页 hero 的月晕是**永远在跑**的呼吸动画
  // （规格 §3.4），只要它挂着，`pumpAndSettle` 就永不收敛——凡是挂真外壳、库里
  // 有记录的用例都会踩到。`_BreathingGlow` 读到这个标志会**不启动**（而不是跑一个
  // 零幅度的动画），于是 settle 得下来。放在 `setUp` 里，本文件每个 harness
  // （含各个用例自己手搓的）都覆盖到，不必逐处重复。
  setUp(() {
    TestWidgetsFlutterBinding
            .instance.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
  });
  tearDown(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher
        .clearAccessibilityFeaturesTestValue();
  });

  // 版本号由 `package_info_plus` 提供，而测试环境没有那条平台通道——静态缓存
  // 空着时 `PackageInfo.fromPlatform()` 的 future 永不完成。这里直接填上缓存，
  // 关于卡片才会走「拿到构建信息」那一支。
  setUpAll(
    () => PackageInfo.setMockInitialValues(
      appName: '夜深',
      packageName: 'com.abner.night_sleep',
      version: '0.1.0',
      buildNumber: '1',
      buildSignature: '',
    ),
  );

  /// Seeds the demo nights and returns them as domain objects.
  Future<List<SleepEntry>> demoEntries() async {
    await DemoSeed.install(database, now: DateTime(2026, 9, 27, 12));
    return SleepRepository(database).loadAll();
  }

  AppSetting settings({
    String themeMode = 'system',
    int goalMinutes = 480,
  }) =>
      AppSetting(
        id: 'default',
        themeMode: themeMode,
        sleepGoalMinutes: goalMinutes,
        bedtimeReminderEnabled: false,
        bedtimeReminderMinutes: null,
        wakeReminderEnabled: false,
        wakeReminderMinutes: null,
        soundRecordingEnabled: false,
        onboarded: true,
        insightProvider: null,
        insightModel: null,
      );

  Future<void> pumpWithOverrides(
    WidgetTester tester,
    Widget home, {
    List<SleepEntry> entries = const [],
    AppSetting? appSettings,
    Size surface = const Size(430, 2600),
    SleepSession? activeSession,
    DateTime? clock,
    List<Override> overrides = const [],
  }) async {
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          sleepEntriesProvider.overrideWith((ref) => entries),
          settingsProvider.overrideWith(
            (ref) => Stream.value(appSettings ?? settings()),
          ),
          // 会话也走 provider 覆盖：真订阅 `activeSessionWatchProvider` 会留下
          // pending timer（见文件头的说明）。默认 null = 没有会话在跑。
          activeSessionProvider.overrideWith((ref) => activeSession),
          // 冻住「现在」，好让「已睡 3h 42m」这类读数与跑测试的日期无关。
          if (clock != null) homeNowProvider.overrideWithValue(() => clock),
          ...overrides,
        ],
        child: MaterialApp(theme: AppTheme.light(), home: home),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// A tab page. It genuinely lives inside the shell's Scaffold, so the test
  /// supplies one.
  Future<void> pumpPage(
    WidgetTester tester,
    Widget page, {
    List<SleepEntry> entries = const [],
    AppSetting? appSettings,
    Size surface = const Size(430, 2600),
    SleepSession? activeSession,
    DateTime? clock,
    List<Override> overrides = const [],
  }) {
    return pumpWithOverrides(
      tester,
      Scaffold(body: page),
      entries: entries,
      appSettings: appSettings,
      surface: surface,
      activeSession: activeSession,
      clock: clock,
      overrides: overrides,
    );
  }

  /// 真实路由外壳。用来验证「Tab 入口 → `/log/new` → 手动补录页」这条链路真的连上，
  /// 而不只是把页面单独挂起来渲染。
  Future<void> pumpRealApp(
    WidgetTester tester, {
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
            (ref) => Stream.value(settings()),
          ),
          activeSessionProvider.overrideWith((ref) => null),
        ],
        child: const NightSleepApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// A pushed sub-page, rendered the way the router renders it: **no Scaffold**.
  ///
  /// This distinction is the whole point. An earlier version of these tests
  /// wrapped sub-pages in `Scaffold(body: page)` too, which quietly supplied the
  /// two things a pushed route has to bring itself — a background and a
  /// `Material` ancestor — so the tests passed while the real pages rendered on
  /// bare black with Flutter's yellow double-underline error text.
  Future<void> pumpRoute(
    WidgetTester tester,
    Widget page, {
    List<SleepEntry> entries = const [],
    List<Override> overrides = const [],
  }) {
    return pumpWithOverrides(tester, page,
        entries: entries, overrides: overrides);
  }

  /// 手动补录表单现在是**推入页**：保存走 `Navigator.pop`。
  ///
  /// 必须真的把它压在一个能 pop 的路由之上，否则保存分支会退到 `context.go('/')`
  /// （这里没有 GoRouter，会直接抛错），「保存后 pop 掉」这条断言也就无从谈起。
  Future<void> pumpLogPushed(
    WidgetTester tester, {
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
            (ref) => Stream.value(settings()),
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
        .push(MaterialPageRoute<void>(builder: (_) => const LogPage()));
    await tester.pumpAndSettle();
  }

  /// Guards the failure above: the text must be on a `Material`, not on the
  /// framework's "no Material ancestor" error style.
  void expectProperlyRendered(WidgetTester tester, String text) {
    final finder = find.text(text);
    expect(finder, findsWidgets, reason: '找不到「$text」');
    expect(
      DefaultTextStyle.of(tester.element(finder.first)).style.decoration,
      isNot(TextDecoration.underline),
      reason: '「$text」带有下划线，说明它落在了 Flutter 的无 Material 错误样式上',
    );
    expect(
      find.ancestor(of: finder.first, matching: find.byType(Material)),
      findsWidgets,
      reason: '「$text」缺少 Material 祖先，推入路由必须自己提供',
    );
  }

  /// 首页。`onStartSleep` 默认什么都不做——它的真实接线（推入会话页）在
  /// 「点「开始入睡」只进页面，不写会话行」那条里走真实路由验证。
  Widget home({VoidCallback onStartSleep = _noop}) => HomePage(
        animateRing: false,
        onRingConsumed: () {},
        onOpenNoise: () {},
        onStartSleep: onStartSleep,
      );

  group('首页', () {
    testWidgets('空状态引导用户记录第一晚', (tester) async {
      await pumpPage(tester, home());

      expect(find.text('睡眠概览'), findsOneWidget);
      expect(find.text('还没有睡眠记录'), findsOneWidget);
      // 主按钮与空状态行动按钮都落到同一个「开始入睡」（原型首页的文案）。
      expect(find.text('开始入睡'), findsWidgets);
      // Nothing fabricated without data.
      expect(find.text('昨夜睡眠'), findsNothing);
      expect(find.text('近 7 日均时'), findsNothing);
      expect(find.textContaining('正在显示演示数据'), findsNothing);
    });

    testWidgets('有数据时渲染睡眠盘、时长与阶段图例', (tester) async {
      await pumpPage(tester, home(), entries: await demoEntries());

      expect(find.text('昨夜睡眠'), findsOneWidget);
      expect(find.text('详情'), findsOneWidget);
      expect(find.text('最近记录'), findsOneWidget);
      // 8h05m on the newest demo night.
      expect(find.text('8'), findsWidgets);
      expect(find.text('5'), findsWidgets);
      // Hypnogram legend uses the design's stage labels.
      expect(find.text('深睡'), findsWidgets);
      expect(find.text('浅睡'), findsWidgets);
      expect(find.text('REM'), findsWidgets);
    });

    testWidgets('手写记录没有阶段数据时，卡片保留结构并说明原因', (tester) async {
      // A hand-logged night has no hypnogram. The prototype's card always has
      // one, so dropping the block left the card looking half-built; filling it
      // with numbers would have meant inventing a distribution.
      await SleepRepository(database).save(
        id: 'manual-1',
        startAtUtc: DateTime(2026, 9, 26, 23, 0).toUtc(),
        endAtUtc: DateTime(2026, 9, 27, 7, 0).toUtc(),
        timeZoneId: 'UTC',
        quality: SleepQuality.good,
        notes: '',
        events: LoggedEvents.none,
      );
      final entries = await SleepRepository(database).loadAll();
      await pumpPage(tester, home(), entries: entries);

      expect(find.text('昨夜睡眠'), findsOneWidget);
      // The three stage tiles are present but explicitly empty.
      for (final stage in SleepStageType.charted) {
        expect(find.text(stage.label), findsWidgets,
            reason: '应保留 ${stage.label} 位置');
      }
      expect(find.text('—'), findsNWidgets(3), reason: '未测量应显示破折号而不是数字');
      expect(find.textContaining('没有睡眠阶段数据'), findsOneWidget);
      // 「零片段」是真实结论，但它**不等于**「检测过、结果安静」——后半句把
      // 「录过没听到」与「根本没录」说成了同一件事，使用方就曾被它误导
      // （他在 iPad 上以为录音开着，界面却像检测完了一样下了「安静」的结论）。
      expect(find.textContaining('无声音片段'), findsWidgets);
      expect(find.textContaining('全程安静'), findsNothing,
          reason: '不许再下那个没有依据的「安静」结论');
    });

    testWidgets('演示数据存在时给出可清除的来源提示', (tester) async {
      await pumpPage(tester, home(), entries: await demoEntries());
      expect(find.textContaining('正在显示演示数据'), findsOneWidget);
    });

    testWidgets('没有会话时主按钮是「开始入睡」', (tester) async {
      await pumpPage(tester, home(), activeSession: null);

      // 主按钮那一个是 `PrimaryAction`：钉住「是这一颗」，而不是「页面上有这两个字」。
      expect(find.widgetWithText(PrimaryAction, '开始入睡'), findsOneWidget);
      expect(find.text('记录昨夜睡眠'), findsNothing);
    });

    testWidgets('空状态的行动按钮也是「开始入睡」', (tester) async {
      await pumpPage(tester, home(), activeSession: null);

      expect(find.text('记录第一晚'), findsNothing);
      expect(find.widgetWithText(EmptyState, '开始入睡'), findsOneWidget);
    });

    testWidgets('有会话时显示「正在睡眠」卡并可回到会话页', (tester) async {
      final start = DateTime(2026, 8, 30, 23, 14);
      await pumpPage(
        tester,
        home(),
        activeSession: SleepSession(
          startAtUtc: start.toUtc(),
          timeZoneId: 'UTC',
          wakeMinutes: 7 * 60,
          alarmEnabled: false,
          createdAtUtc: start.toUtc(),
        ),
        clock: start.add(const Duration(hours: 3, minutes: 42)),
      );

      expect(find.text('正在睡眠'), findsOneWidget);
      // 收紧过：只断言「已睡」二字的话，时长算错也照样通过；这里钉住具体读数。
      expect(find.text('已睡 3h 42m'), findsOneWidget);
      expect(find.text('开始入睡'), findsNothing, reason: '会话在跑时不该再给开始按钮');
    });

    /// v3.3 起首页那颗按钮**只进页面**：记录起点在页内那颗「开始睡眠」上，所以
    /// 「点进来看一眼又退出」不该留下一段并不存在的睡眠。走真实路由，顺带覆盖
    /// `app.dart` 里注册的 `path: 'sleep/session'`。
    testWidgets('点「开始入睡」只进页面，不写会话行', (tester) async {
      // 会话页的夜景是 60 秒循环动画，开着它 `pumpAndSettle()` 会 timed out（已实测）。
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );

      await pumpRealApp(tester);

      await tester.tap(find.text('开始入睡').first);
      await tester.pumpAndSettle();

      expect(find.text('准备好休息了吗？'), findsOneWidget, reason: '进的是入睡前那一屏');
      expect(
        await database.activeSession(),
        isNull,
        reason: '进页面不许写会话行——写库的是页内的「开始睡眠」',
      );

      // 收起回首页，库里依然什么都没有。
      await tester.tap(find.text('收起'));
      await tester.pumpAndSettle();

      expect(find.text('睡眠概览'), findsOneWidget);
      expect(await database.activeSession(), isNull);
    });
  });

  group('记录页', () {
    testWidgets('表单分组齐全', (tester) async {
      await pumpPage(tester, const LogPage());

      expect(find.text('手动补录'), findsOneWidget, reason: '作为推入页应自带标题');
      expect(find.text('今天睡得怎么样？'), findsNothing, reason: 'Tab 版的页头已删除');
      expect(find.text('入睡时间'), findsOneWidget);
      expect(find.text('起床时间'), findsOneWidget);
      expect(find.text('睡眠质量'), findsOneWidget);
      expect(find.text('睡眠事件'), findsOneWidget);
      expect(find.text('备注'), findsOneWidget);
    });

    testWidgets('时长由起止时间派生并给出充足度提示', (tester) async {
      await pumpPage(tester, const LogPage());
      // Defaults 23:00 → 07:00.
      expect(find.text('✓ 睡眠充足'), findsOneWidget);
    });

    testWidgets('未选质量保存时，记录没有评分', (tester) async {
      await pumpLogPushed(tester);

      // 表单初始无选中：没碰质量就保存，记录**没有**评分。
      // v3.34 起未选时不摆占位符（规格 §3.3），所以这里断的是控件自身的值。
      final choice = tester.widget<QualityChoice>(find.byType(QualityChoice));
      expect(choice.value, isNull, reason: '表单初始一个药丸都不该选中');
      expect(find.text('未评分'), findsNothing, reason: '不摆占位符');

      await tester.tap(find.text('保存记录'));
      await tester.pumpAndSettle();

      // 保存后 pop 掉这一页，不再有任何「切回首页 Tab」或「2 秒后重置」的副作用。
      expect(find.text('保存记录'), findsNothing, reason: '保存后应离开补录页');
      expect(find.text('外壳'), findsOneWidget, reason: '应回到推入页下面的路由');

      final saved = await SleepRepository(database).loadAll();
      expect(saved, hasLength(1));
      expect(saved.single.quality, isNull, reason: '未选星级就不该写质量');
      expect(saved.single.durationHours, closeTo(8, 0.001));
      // 没有质量就没有分：不是喂个占位值给 estimateScore 拿半截分数冒充。
      expect(saved.single.scoreSource, ScoreSource.none);
      expect(saved.single.score, isNull);
      expect(saved.single.estimatedSummary, isNull);
      // 手写记录没有测量数据，不得声称有阶段或音频。
      expect(saved.single.hasStages, isFalse);
      expect(saved.single.hasSoundEvents, isFalse);
    });

    testWidgets('点第 4 档再保存，质量是「清醒」并按它估算', (tester) async {
      // `ensureSemantics` 必须在用例体内释放：绑定会在 tearDown 里检查。
      final semantics = tester.ensureSemantics();
      await pumpLogPushed(tester);

      await tester.tap(find.bySemanticsLabel('睡眠质量 清醒'));
      await tester.pump();

      await tester.tap(find.text('保存记录'));
      await tester.pumpAndSettle();

      expect(find.text('外壳'), findsOneWidget, reason: '保存后应 pop 回下面的路由');

      final saved = await SleepRepository(database).loadAll();
      expect(saved, hasLength(1));
      expect(saved.single.quality, SleepQuality.good);
      // 8h + 良好 + 无事件 → 45 + 26.25 + 20 = 91.25 → 91。
      expect(saved.single.scoreSource, ScoreSource.onDeviceEstimate);
      expect(saved.single.isEstimated, isTrue);
      expect(saved.single.score, 91);
      semantics.dispose();
    });
  });

  group('手动补录页', () {
    testWidgets('作为推入页渲染时自带 Material 祖先与标题', (tester) async {
      // 推入路由什么都继承不到：没有 Scaffold、没有 Material、没有背景、没有
      // 留白。这一页必须自己带齐，否则文字会落到 Flutter 的黄色双下划线错误样式。
      // `pumpRoute` 不套 Scaffold，正是为了暴露这类问题。
      await pumpRoute(tester, const LogPage());

      expectProperlyRendered(tester, '睡眠质量');
      expectProperlyRendered(tester, '手动补录');
    });

    testWidgets('回顾页底部的入口真的落在 /log/new 上', (tester) async {
      // 这条走真实路由：Tab 入口 → `/log/new` → 手动补录页。app.dart 里那条
      // 路由一旦缺失，用户看到的就是 go_router 的 Page Not Found。
      await pumpRealApp(tester, entries: const []);

      await tester.tap(find.text('回顾'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('手动补录某一晚'));
      await tester.pumpAndSettle();

      expect(find.text('手动补录'), findsOneWidget, reason: '应落在手动补录页');
      expect(find.text('Page Not Found'), findsNothing,
          reason: '/log/new 必须注册');
    });
  });

  group('图标颜色', () {
    test('SVG 用调用方给的颜色，不会退化成黑色', () {
      final svg = AppIcons.svgFor('<path d="M4 7h16"/>',
          color: const Color(0xFF5AC8FA), strokeWidth: 1.5);

      expect(svg, contains('#5ac8fa'), reason: '颜色没写进 stroke');
      expect(svg, isNot(contains('#000000')),
          reason: '出现了黑色——这正是深色模式下图标看不见的原因');
    });

    test('currentColor 会被文本替换掉，不留字面量', () {
      // flutter_svg 不解析 currentColor，留着它这些图形会被画成黑色。
      final svg = AppIcons.svgFor('<path fill="currentColor" d="M1 1"/>',
          color: const Color(0xFFFFFFFF));
      expect(svg, isNot(contains('currentColor')));
    });

    test('漏传颜色直接断言失败，而不是静默画成黑色', () {
      expect(
        () => AppIcons.glyph('<path d="M4 7h16"/>'),
        throwsA(isA<AssertionError>()),
        reason: '兜底必须是「炸」，不能是「画黑」',
      );
    });

    testWidgets('记录页的事件图标在渲染时不会触发漏传颜色的断言', (tester) async {
      // 这个用例的护栏作用来自上一条断言：任何一处调用点忘了传 color，
      // 构建这一页就会抛 AssertionError，而不是安静地渲染成黑图标。
      await pumpPage(tester, const LogPage());
      for (final label in ['打鼾', '说梦话', '辗转难眠', '噩梦']) {
        expect(find.text(label), findsOneWidget, reason: '找不到事件「$label」');
      }
    });
  });

  group('统计页', () {
    testWidgets('空数据不显示虚假趋势', (tester) async {
      await pumpPage(tester, const StatsPage());

      expect(find.text('趋势分析'), findsOneWidget);
      expect(find.text('暂无统计数据'), findsOneWidget);
      expect(find.text('每日睡眠时长'), findsNothing);
    });

    testWidgets('有数据时渲染目标线、汇总与时间范围', (tester) async {
      await pumpPage(tester, const StatsPage(), entries: await demoEntries());

      expect(find.text('每日睡眠时长'), findsOneWidget);
      expect(find.textContaining('7 小时目标'), findsOneWidget);
      expect(find.text('7h'), findsOneWidget, reason: 'y 轴目标刻度');
      expect(find.text('平均时长'), findsOneWidget);
      expect(find.text('充足天数'), findsOneWidget);
      expect(find.text('打鼾夜数'), findsOneWidget);
      expect(find.text('梦话夜数'), findsOneWidget);
      expect(find.text('7天'), findsOneWidget);
      expect(find.text('14天'), findsOneWidget);
      expect(find.text('30天'), findsOneWidget);
    });

    testWidgets('演示洞察被呈现并附免责声明', (tester) async {
      await pumpPage(tester, const StatsPage(), entries: await demoEntries());

      expect(find.text('本周睡眠评分'), findsOneWidget);
      expect(find.textContaining('不构成医疗建议'), findsWidgets);
      expect(find.text('梦话记录'), findsOneWidget);
    });

    testWidgets('14 天与 30 天在手机宽度上不溢出', (tester) async {
      // 用户报的「14 天 / 30 天时柱状列表有异常布局提示」。夹具给满 30 晚，
      // 视口用手机宽度（此前那几条用的是 430×2600 的画布，柱子再挤也不会露馅）。
      final entries = [
        for (var i = 0; i < 30; i++) _nightDaysAgo(i),
      ];

      await pumpPage(tester, const StatsPage(),
          entries: entries, surface: const Size(390, 844));
      expect(tester.takeException(), isNull, reason: '7 天就溢出的话，先记在这里');

      for (final label in ['14天', '30天']) {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$label 有溢出');
      }
    });

    testWidgets('空库时右上角没有「全部数据」入口', (tester) async {
      await pumpPage(tester, const StatsPage());
      expect(find.text('查看所有数据'), findsNothing,
          reason: '一条记录都没有时它通向一个只能显示空状态的地方');
    });

    testWidgets('有记录时右上角有「全部数据」入口', (tester) async {
      await pumpPage(tester, const StatsPage(), entries: await demoEntries());
      expect(find.text('查看所有数据'), findsOneWidget);
    });

    testWidgets('右上角入口进全部睡眠数据页，返回后仍在统计页', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(database),
            settingsProvider.overrideWith((ref) => Stream.value(settings())),
            sleepEntriesProvider.overrideWith((ref) => demoEntries()),
            activeTabProvider.overrideWith((ref) => AppTab.stats),
            activeSessionProvider.overrideWith((ref) => null),
          ],
          child: const NightSleepApp(),
        ),
      );
      await tester.pumpAndSettle();
      // 应用路由是共享实例，前一个路由测试可能仍停在别的页面。
      final router = tester
          .widget<MaterialApp>(find.byType(MaterialApp))
          .routerConfig! as GoRouter;
      router.go('/');
      await tester.pumpAndSettle();

      await tester.tap(find.text('查看所有数据'));
      await tester.pumpAndSettle();

      expect(find.byType(AllSleepDataPage), findsOneWidget);
      expect(find.byType(AppShell), findsNothing, reason: '二级页要盖住标签条');
      // 返回键只有图标，没有文字标签——按控件认，不按文字认。
      await tester.tap(find.byKey(const ValueKey('subpage-back')));
      await tester.pumpAndSettle();
      expect(find.byType(StatsPage), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('设置页', () {
    testWidgets('关于入口打开应用信息页，返回后仍在设置页', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(database),
            settingsProvider.overrideWith((ref) => Stream.value(settings())),
            sleepEntriesProvider.overrideWith((ref) => const []),
            activeTabProvider.overrideWith((ref) => AppTab.settings),
            activeSessionProvider.overrideWith((ref) => null),
          ],
          child: const NightSleepApp(),
        ),
      );
      await tester.pumpAndSettle();
      final router = tester
          .widget<MaterialApp>(find.byType(MaterialApp))
          .routerConfig! as GoRouter;
      router.go('/');
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('睡眠记录与分析'), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('睡眠记录与分析'));
      await tester.pumpAndSettle();
      expect(find.byType(AboutPage), findsOneWidget);
      expect(find.byType(AppShell), findsNothing);
      expect(find.text('关于夜深'), findsOneWidget);
      expect(find.text('0.1.0'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('subpage-back')));
      await tester.pumpAndSettle();
      expect(find.byType(AboutPage), findsNothing);
      expect(find.byType(SettingsPage), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('罗盘入口打开二级页，返回后仍在设置页', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(database),
            settingsProvider.overrideWith((ref) => Stream.value(settings())),
            sleepEntriesProvider.overrideWith((ref) => const []),
            activeTabProvider.overrideWith((ref) => AppTab.settings),
            activeSessionProvider.overrideWith((ref) => null),
          ],
          child: const NightSleepApp(),
        ),
      );
      await tester.pumpAndSettle();
      // 应用路由是共享实例，前一个路由测试可能仍停在手动补录页。
      final router = tester
          .widget<MaterialApp>(find.byType(MaterialApp))
          .routerConfig! as GoRouter;
      router.go('/');
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('罗盘'), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('罗盘'));
      await tester.pumpAndSettle();
      expect(find.byType(CompassPage), findsOneWidget);
      expect(find.byType(AppShell), findsNothing);
      expect(find.text('天池罗盘'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('subpage-back')));
      await tester.pumpAndSettle();
      expect(find.byType(CompassPage), findsNothing);
      expect(find.byType(SettingsPage), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('根页只剩三段导航行，控件都收进了二级页', (tester) async {
      await pumpPage(tester, const SettingsPage());

      expect(find.text('常用'), findsOneWidget);
      expect(find.text('数据与智能'), findsOneWidget);
      expect(find.text('数据与隐私'), findsOneWidget);
      expect(find.text('关于'), findsOneWidget);

      // 原型那五条 + 我们必须保留的四条（导出是偏差 #18、删除全部数据是规格 §7、
      // 演示数据是调试期功能、罗盘是本实现新增）。
      for (final label in [
        '外观',
        '睡眠设置',
        '罗盘',
        '睡眠数据导入',
        '睡眠洞察',
        '睡眠数据导出',
        '删除全部本地数据',
        '清除缓存',
      ]) {
        expect(find.text(label), findsOneWidget, reason: '根页少了「$label」这一行');
      }

      // 控件**不在**根页上：外观与睡眠目标既然收进了二级页，根页就不该再出现
      // 它们，否则同一条设置在两个层级各有一份可改的入口。
      expect(find.text('外观模式'), findsNothing);
      expect(find.text('睡眠目标'), findsNothing);
      expect(find.text('就寝提醒'), findsNothing);
      expect(find.text('起床提醒'), findsNothing);
      expect(find.text('夜间声音录制'), findsNothing);
    });

    testWidgets('清除缓存显示真实占用，清完变成「暂无缓存」', (tester) async {
      final cache = _FakeAppCache(bytes: 7 * 1024 * 1024);
      await pumpPage(
        tester,
        const SettingsPage(),
        overrides: [appCacheProvider.overrideWithValue(cache)],
      );

      expect(find.text('清除缓存'), findsOneWidget);
      expect(find.textContaining('7.0 MB'), findsOneWidget);

      await tester.tap(find.text('清除缓存'));
      await tester.pumpAndSettle();

      // **v3.10 起先过二次确认**：没点「清除」之前一个文件都不许删。
      expect(
        find.byType(CupertinoAlertDialog),
        findsOneWidget,
        reason: '清除缓存是不可撤销的删除，必须先弹确认',
      );
      expect(cache.cleared, isFalse, reason: '弹窗还没确认，什么都不该删');

      await tester.tap(find.text('清除'));
      await tester.pumpAndSettle();

      expect(cache.cleared, isTrue);
      // 清除结果必须落在这一行上：提示条挂在 AppScaffold，而这里只挂了页面本身，
      // 断言「清完之后这一行不再谎报占用」才是这条用例真正要守的东西。
      expect(find.text('暂无缓存'), findsOneWidget);
      expect(find.textContaining('7.0 MB'), findsNothing);
    });

    testWidgets('清除缓存：取消（或点蒙层）之后一个文件都不删', (tester) async {
      final cache = _FakeAppCache(bytes: 7 * 1024 * 1024);
      await pumpPage(
        tester,
        const SettingsPage(),
        overrides: [appCacheProvider.overrideWithValue(cache)],
      );

      await tester.tap(find.text('清除缓存'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(cache.cleared, isFalse, reason: '点了取消还删，等于没有这道闸');
      expect(
        find.textContaining('7.0 MB'),
        findsOneWidget,
        reason: '取消之后占用读数必须原样留着',
      );

      // 点蒙层同样算取消（与另外四处确认弹窗一致）。
      await tester.tap(find.text('清除缓存'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(cache.cleared, isFalse);
      expect(find.byType(CupertinoAlertDialog), findsNothing);
    });

    testWidgets('读不到占用时如实说读不到，不编一个 0 B', (tester) async {
      await pumpPage(
        tester,
        const SettingsPage(),
        overrides: [
          appCacheProvider.overrideWithValue(_FakeAppCache(fails: true)),
        ],
      );

      expect(find.text('暂时读不到占用'), findsOneWidget);
      expect(find.text('暂无缓存'), findsNothing);
    });

    testWidgets('睡眠洞察那一行不谎报「未配置」，并说清密钥在不在', (tester) async {
      // 用户实机报回来的一条：填好 key、余额与连通性都跑通了，根页却仍写着
      // 「未配置 · 当前使用本地规则估算」。库里那两列在全新安装时**就是 null**
      // （DeepSeek 与其内置模型只是默认值），读裸列会把能用的配置说成没配置。
      await pumpPage(tester, const SettingsPage());

      expect(find.textContaining('DeepSeek · deepseek-flash'), findsOneWidget);
      expect(find.textContaining('未填 API Key'), findsOneWidget);
      expect(find.textContaining('未配置'), findsNothing);
    });

    testWidgets('填好密钥后，那一行不再提「未填 API Key」', (tester) async {
      // 密钥是会话内存里的，这一行是它唯一的可见状态：填了就该消失，
      // 否则用户会以为没保存上。
      await pumpPage(
        tester,
        const SettingsPage(),
        overrides: [
          insightApiKeyProvider
              .overrideWith(() => _FrozenInsightKey('sk-test')),
        ],
      );

      expect(find.textContaining('DeepSeek · deepseek-flash'), findsOneWidget);
      expect(find.textContaining('未填 API Key'), findsNothing);
    });

    testWidgets('版本号取自构建信息而不是写死的常量', (tester) async {
      await pumpPage(tester, const SettingsPage());

      // `setMockInitialValues` 直接填 `PackageInfo` 的静态缓存，测试不必
      // 走平台通道（测试环境里那条通道没有实现）。
      expect(find.text('夜深'), findsOneWidget);
      expect(find.text('睡眠记录与分析'), findsOneWidget);
      expect(find.text('0.1.0'), findsOneWidget);
      expect(find.text('v2.0.0'), findsNothing, reason: '版本号又退回写死的常量了');
    });

    testWidgets('删除全部数据前要求二次确认', (tester) async {
      await pumpPage(tester, const SettingsPage());

      await tester.tap(find.text('删除全部本地数据'));
      await tester.pumpAndSettle();

      expect(find.text('删除全部本地数据？'), findsOneWidget);
      // Cancelling must leave the data alone.
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('删除全部本地数据'), findsOneWidget);
    });

    testWidgets('危险操作行用垃圾桶图标并套了 danger 底板', (tester) async {
      await pumpPage(tester, const SettingsPage());

      final row = find.ancestor(
        of: find.text('删除全部本地数据'),
        matching: find.byType(IosListItem),
      );
      expect(row, findsOneWidget, reason: '找不到「删除全部本地数据」那一行');
      // 这一行此前是**裸图标**，而同页其它行都有底板——补底板是本任务的一部分。
      expect(
        find.descendant(of: row, matching: find.byType(ListIconBadge)),
        findsOneWidget,
        reason: '删除行仍然没有图标底板',
      );

      // 图标身份断得到：`SvgPicture.bytesLoader` 是公开字段，`SvgStringLoader`
      // 又实现了值相等（逐字符比 SVG 文本、比 theme 与 colorMapper）。
      // 这一条钉的正是本任务要钉的行为——换回借来的「停止」方块就会红。
      final tokens = AppTokens.of(tester.element(find.byType(SettingsPage)));
      final rendered = tester.widget<SvgPicture>(
        find.descendant(of: row, matching: find.byType(SvgPicture)),
      );
      final expected = AppIcons.trash(
        size: 16,
        color: tokens.danger,
        strokeWidth: 1.8,
      );
      expect(
        rendered.bytesLoader,
        (expected as SvgPicture).bytesLoader,
        reason: '这一行画的不是垃圾桶图标',
      );
    });
  });

  group('二级页顶部导航', () {
    testWidgets('上滑吸顶：返回胶囊先随页面上移，随后钉在顶部', (tester) async {
      // 模拟安卓的状态栏（24px）：吸顶条必须铺到它背后，而不是从它下面才开始。
      tester.view.padding = const FakeViewPadding(top: 24);
      addTearDown(tester.view.resetPadding);

      await pumpWithOverrides(
        tester,
        Subpage(
          title: '测试标题',
          children: [
            for (var i = 0; i < 30; i++)
              SizedBox(height: 80, child: Text('第 $i 行')),
          ],
        ),
        surface: const Size(430, 800),
      );

      final pill = find.byKey(const ValueKey('subpage-back'));
      expect(
        tester.getTopLeft(pill).dy,
        24 + 24,
        reason: '第 0 屏：状态栏 + 原来的顶部留白',
      );

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
      await tester.pumpAndSettle();

      expect(
        tester.getTopLeft(pill).dy,
        24 + 12,
        reason: '吸顶后胶囊在状态栏下方 12px——吸顶条比原先高，不再贴着状态栏',
      );
      expect(find.text('测试标题'), findsOneWidget, reason: '标题也要跟着吸顶');

      // 底板从屏幕最顶上开始画，状态栏那一截是它的一部分——深色模式下不能有
      // 一条底色不同的横带把导航和状态栏切开。
      final band = tester.getRect(
        find.byKey(const ValueKey('subpage-header-band')),
      );
      expect(band.top, 0, reason: '吸顶底板没有铺到状态栏背后');
      expect(
        band.height,
        24 + 12 * 2 + 36,
        reason: '吸顶底板高度 = 状态栏 + 胶囊行 + 上下各 12px',
      );

      // 再滚一段：仍然钉在原处，不是滚到某个位置才生效一次。
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(pill).dy, 24 + 12);
    });

    testWidgets('返回键只有图标，没有文字标签；读屏仍然知道它是返回', (tester) async {
      await pumpWithOverrides(
        tester,
        const Subpage(
          title: '测试标题',
          children: [SizedBox(height: 400)],
        ),
        surface: const Size(430, 800),
      );

      final back = find.byKey(const ValueKey('subpage-back'));
      expect(back, findsOneWidget);
      // 删掉文案标签之后，胶囊里不该再有任何文字。
      expect(
        find.descendant(of: back, matching: find.byType(Text)),
        findsNothing,
        reason: '返回键里还剩文字标签',
      );
      // 但无障碍不能跟着一起消失。
      expect(tester.getSemantics(back).label, contains('返回'));
    });
  });

  group('设置二级页', () {
    // Sub-pages are pushed outside the tab shell, so they must apply the
    // content padding themselves. Before this was fixed they rendered
    // edge-to-edge and looked broken next to the tab pages.
    testWidgets('外观页：行内下拉切换写回数据库', (tester) async {
      await pumpRoute(tester, const AppearanceSettingsPage());

      expectProperlyRendered(tester, '显示模式');
      expect(find.text('随设备外观自动切换'), findsOneWidget);
      expect(find.text('选择「跟随系统」后，外观会随设备的浅色或深色模式自动变化。'), findsOneWidget);

      // 触发器与菜单项的文字相同，先点触发器（第一个）。
      await tester.tap(find.text('跟随系统').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('深色'));
      await tester.pumpAndSettle();

      expect((await database.getSettings()).themeMode, 'dark');
    });

    testWidgets('外观页：下拉的箭头贴在触发器右端', (tester) async {
      await pumpRoute(tester, const AppearanceSettingsPage());

      // 行内版式没有 flex 子项，靠 `minWidth` 撑出来的富余宽度不显式分配的话
      // 会全留在右边，箭头就浮在文字后面。这一条钉住「箭头贴右」。
      final field = find.byType(AppMenuField);
      final chevron =
          find.descendant(of: field, matching: find.byType(SvgPicture));
      expect(field, findsOneWidget);
      expect(chevron, findsOneWidget, reason: '下拉触发器里找不到箭头');

      // 触发器左右各 12px 内边距，箭头右缘因此应当落在距右端 12px 处。
      expect(
        tester.getRect(field).right - tester.getRect(chevron).right,
        moreOrLessEquals(12, epsilon: 1),
        reason: '箭头没有贴住下拉的右端',
      );
    });

    testWidgets('睡眠目标：快捷按钮与滑块都写回数据库', (tester) async {
      await pumpRoute(tester, const SleepSettingsPage());

      expectProperlyRendered(tester, '每晚睡眠目标');
      expect(find.text('在成年人推荐的睡眠范围内'), findsOneWidget);

      await tester.tap(find.text('9 小时'));
      await tester.pumpAndSettle();
      expect((await database.getSettings()).sleepGoalMinutes, 540);
    });

    testWidgets('睡眠目标滑块：按 0.5 小时吸附，两端不越界', (tester) async {
      await pumpRoute(tester, const SleepSettingsPage());

      final slider = find.byType(GoalSlider);
      expect(slider, findsOneWidget);
      final rect = tester.getRect(slider);

      // 若干个中间位置：落库的分钟数必须永远是 30 的整数倍（吸附到 0.5 小时）。
      for (final fraction in [0.13, 0.37, 0.61, 0.88]) {
        await tester.tapAt(
          Offset(rect.left + rect.width * fraction, rect.center.dy),
        );
        await tester.pumpAndSettle();
        final minutes = (await database.getSettings()).sleepGoalMinutes;
        expect(minutes % 30, 0,
            reason: '滑块在 $fraction 处落库 $minutes 分钟，没有吸附到 0.5 小时');
        expect(minutes, inInclusiveRange(300, 720));
      }

      // 两端夹住：按在轨道尽头之外（滑块只走到两端各让出的半个滑块处）
      // 也停在 5 / 12 小时，不会越界。
      await tester.tapAt(Offset(rect.right - 1, rect.center.dy));
      await tester.pumpAndSettle();
      expect((await database.getSettings()).sleepGoalMinutes, 720);

      await tester.tapAt(Offset(rect.left + 1, rect.center.dy));
      await tester.pumpAndSettle();
      expect((await database.getSettings()).sleepGoalMinutes, 300);
    });

    testWidgets('睡眠目标滑块：读屏的增大 / 减小一步就是 0.5 小时', (tester) async {
      await pumpRoute(tester, const SleepSettingsPage());

      final handle = tester.ensureSemantics();
      final node = tester.getSemantics(find.byType(GoalSlider));
      // `tap` / `scrollLeft` / `scrollRight` 是 `GestureDetector` 自己并上来的动作，
      // 一并写进期望里：这一条要钉的是**滑块语义与步长**，不是「没有别的动作」。
      expect(
          node,
          matchesSemantics(
            isSlider: true,
            label: '每晚睡眠目标',
            value: '8 小时',
            increasedValue: '8 小时 30 分钟',
            decreasedValue: '7 小时 30 分钟',
            hasTapAction: true,
            hasIncreaseAction: true,
            hasDecreaseAction: true,
            hasScrollLeftAction: true,
            hasScrollRightAction: true,
          ));
      handle.dispose();
    });

    testWidgets('睡眠设置页把提醒与声音检测都收在一起，并保留两条红线', (tester) async {
      await pumpRoute(tester, const SleepSettingsPage());

      expectProperlyRendered(tester, '就寝提醒');
      expect(find.text('起床提醒'), findsOneWidget);
      expect(find.text('夜间声音录制'), findsOneWidget);
      expect(find.text('提醒会根据设置的时间在本机发送通知。'), findsOneWidget);

      // 产品红线：副标题不许声称能自动检测打鼾 / 梦话（那是我们没有的能力）。
      // 旧那句「尚未接入录音」在录音接上之后成了假话，也必须消失。
      expect(find.textContaining('尚未接入录音'), findsNothing);
      expect(find.text('录下有声响的片段，由你听过之后自己标注'), findsOneWidget);
      expect(find.textContaining('检测打鼾、梦话并生成洞察'), findsNothing);
    });

    testWidgets('睡眠目标数值在卡片内水平居中', (tester) async {
      await pumpRoute(tester, const SleepSettingsPage());

      // `HeroSurface` 把子项画在 `Stack` 里，非 position 子项拿到的是宽松约束；
      // `Column` 会在那种约束下缩到最宽子项的宽度并被左锚定，
      // `crossAxisAlignment: center` 只在那一段宽度内居中，整块看着就是偏左。
      // v3.34 起这张卡从 `GlassSurface` 换成了 `HeroSurface`（偏差 #70 一族），
      // 约束形态没变，所以这条断言要守的那个 bug 仍然成立。
      final card = find.ancestor(
        of: find.text('5 小时'),
        matching: find.byType(HeroSurface),
      );
      expect(card, findsWidgets, reason: '找不到睡眠目标卡片');

      final centre = tester.getCenter(card.first).dx;
      expect(
        tester.getCenter(find.text('在成年人推荐的睡眠范围内')).dx,
        moreOrLessEquals(centre, epsilon: 1),
        reason: '目标反馈没有在卡片内居中——Column 在 Stack 的宽松约束下静缩并被左锚定了',
      );
    });

    testWidgets('数据导入页有内边距并说明适配器待接入', (tester) async {
      await pumpRoute(tester, const SleepImportPage());

      expect(find.text('睡眠数据导入'), findsOneWidget);
      expect(find.text('小米手环'), findsOneWidget);
      expect(find.text('仅睡眠阶段'), findsOneWidget);
      expect(find.text('适配器待接入'), findsOneWidget);
      expect(find.text('将导入'), findsOneWidget);
      expect(find.text('深睡眠'), findsOneWidget);
      expect(find.text('快速眼动'), findsOneWidget);
      // Audio events must not be presented as importable from the band.
      expect(find.textContaining('鼾声与梦话不从手环导入'), findsOneWidget);
      // The action exists but is inert while there is no adapter.
      expect(find.text('导入睡眠记录'), findsOneWidget);

      expectProperlyRendered(tester, '睡眠数据导入');
      final left = tester.getRect(find.text('小米手环')).left;
      expect(left, greaterThanOrEqualTo(16), reason: '手机宽度下应有 16px 内边距');
    });

    testWidgets('洞察配置页有内边距并给出实测支持的动作', (tester) async {
      await pumpRoute(tester, const InsightConfigPage());

      expect(find.text('洞察服务配置'), findsWidgets);
      expect(find.text('大模型服务'), findsOneWidget);
      expect(find.text('服务商'), findsOneWidget);
      expect(find.text('模型'), findsOneWidget);
      expect(find.text('API Key'), findsOneWidget);
      expect(find.text('DeepSeek'), findsOneWidget);
      // DeepSeek 的余额与对话接口都在 2026-10-03 用真实 key 实测过，两个按钮
      // 因此是真的可点；而「未接入」只留给没有可调用接口的服务商。
      expect(find.text('查询余额'), findsOneWidget);
      expect(find.text('连通性测试'), findsOneWidget);
      expect(find.text('余额查询未接入'), findsNothing);
      // 密钥进钥匙串，且这句话必须说清去了哪里——「存在内存里、重启即丢」已经
      // 不是事实了，留着它就是撒谎。
      expect(find.textContaining('系统钥匙串'), findsOneWidget);
      expect(find.textContaining('重启即丢失'), findsNothing);
      expect(find.textContaining('安全提示'), findsOneWidget);

      expectProperlyRendered(tester, '洞察服务配置');
      final left = tester.getRect(find.text('大模型服务')).left;
      expect(left, greaterThanOrEqualTo(16), reason: '手机宽度下应有 16px 内边距');
    });

    testWidgets('演示数据已收进二级页，并说明它是什么', (tester) async {
      await DemoSeed.install(database, now: DateTime(2026, 9, 27, 12));
      final entries = await SleepRepository(database).loadAll();
      await pumpWithOverrides(tester, const DemoDataPage(), entries: entries);

      expect(find.text('演示数据'), findsWidgets);
      expect(find.textContaining('5 条演示记录'), findsOneWidget);
      expect(find.textContaining('不是对真人睡眠的测量'), findsOneWidget);
      expect(find.text('重新安装演示数据'), findsOneWidget);
      expect(find.text('清除演示数据'), findsOneWidget);
      expectProperlyRendered(tester, '演示数据');
    });

    testWidgets('导出页自己带背景与 Material 祖先', (tester) async {
      // 推入的二级页什么都继承不到。这一页也必须自己带 `Subpage`——
      // 没有它，文字会落到 Flutter 的错误样式（黄色双下划线），背景会是黑的。
      // 这个 bug 在本项目真出现过一次，所以每个二级页都要接上这条守卫。
      await pumpRoute(tester, const ExportPage());
      expectProperlyRendered(tester, '睡眠数据导出');
    });

    testWidgets('导出页的「预览表格」进表格预览页', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(database),
            settingsProvider.overrideWith((ref) => Stream.value(settings())),
            sleepEntriesProvider.overrideWith((ref) => [
                  SleepEntry(
                    id: 'real-1',
                    startAtUtc: DateTime.utc(2026, 9, 26, 23),
                    endAtUtc: DateTime.utc(2026, 9, 27, 7),
                    timeZoneId: 'UTC',
                    quality: SleepQuality.good,
                    createdAtUtc: DateTime.utc(2026, 9, 27, 8),
                    updatedAtUtc: DateTime.utc(2026, 9, 27, 8),
                  ),
                ]),
            activeSessionProvider.overrideWith((ref) => null),
          ],
          child: const NightSleepApp(),
        ),
      );
      await tester.pumpAndSettle();
      final router = tester
          .widget<MaterialApp>(find.byType(MaterialApp))
          .routerConfig! as GoRouter;
      router.go('/settings/export');
      await tester.pumpAndSettle();

      await tester.tap(find.text('预览表格'));
      await tester.pumpAndSettle();

      expect(find.byType(ExportPreviewPage), findsOneWidget);
      expect(find.text('日期'), findsOneWidget, reason: '预览里是记录表的表头');
      await tester.tap(find.byKey(const ValueKey('subpage-back')));
      await tester.pumpAndSettle();
      expect(find.byType(ExportPreviewPage), findsNothing);
      expect(find.byType(ExportPage), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('清除演示数据只删演示行，保留用户自己的记录', (tester) async {
      await DemoSeed.install(database, now: DateTime(2026, 9, 27, 12));
      final repository = SleepRepository(database);
      await repository.save(
        id: 'manual-1',
        startAtUtc: DateTime(2026, 9, 26, 23, 0).toUtc(),
        endAtUtc: DateTime(2026, 9, 27, 7, 0).toUtc(),
        timeZoneId: 'UTC',
        quality: SleepQuality.good,
        notes: '',
        events: LoggedEvents.none,
      );
      final entries = await repository.loadAll();
      await pumpWithOverrides(tester, const DemoDataPage(), entries: entries);

      expect(find.textContaining('你自己的记录有 1 条'), findsOneWidget);

      await tester.tap(find.text('清除演示数据'));
      await tester.pumpAndSettle();

      // 清除是不可撤销的删除，与另外两处一样要过二次确认。此前它点一下就删。
      expect(find.text('清除演示数据？'), findsOneWidget);
      await tester.tap(find.text('清除'));
      await tester.pumpAndSettle();

      final remaining = await repository.loadAll();
      expect(remaining, hasLength(1), reason: '只应删掉演示行');
      expect(remaining.single.id, 'manual-1');
    });

    testWidgets('取消清除演示数据的确认后，演示行一条都不动', (tester) async {
      await DemoSeed.install(database, now: DateTime(2026, 9, 27, 12));
      final repository = SleepRepository(database);
      final entries = await repository.loadAll();
      await pumpWithOverrides(tester, const DemoDataPage(), entries: entries);

      await tester.tap(find.text('清除演示数据'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(find.text('清除演示数据？'), findsNothing, reason: '点取消后弹窗应关闭');
      expect(
        await repository.loadAll(),
        hasLength(entries.length),
        reason: '取消不得删除任何演示行',
      );
    });

    testWidgets('查询余额把读数显示在按钮上', (tester) async {
      await pumpRoute(
        tester,
        const InsightConfigPage(),
        overrides: [
          insightApiKeyProvider
              .overrideWith(() => _FrozenInsightKey('sk-test')),
          insightHttpClientProvider.overrideWithValue(
            MockClient(
              (request) async => http.Response.bytes(
                utf8.encode(jsonEncode({
                  'is_available': true,
                  'balance_infos': [
                    {'currency': 'CNY', 'total_balance': '42.51'},
                  ],
                })),
                200,
              ),
            ),
          ),
        ],
      );

      await tester.tap(find.text('查询余额'));
      await tester.pumpAndSettle();

      expect(find.text('余额 ¥42.51'), findsOneWidget);
      expect(find.text('查询余额'), findsNothing);
    });

    testWidgets('有密钥时才出现「清除密钥」，清了就消失', (tester) async {
      // 密钥一旦能跨重启留存，就必须给得出一个删除入口。
      final store = _FakeInsightKeyStore();
      await pumpRoute(
        tester,
        const InsightConfigPage(),
        overrides: [
          insightKeyStoreProvider.overrideWithValue(store),
        ],
      );
      expect(find.text('清除密钥'), findsNothing, reason: '没密钥就没有可清的');

      await tester.enterText(find.byType(TextField), 'sk-typed');
      // 用 pump 而不是 `pumpEventQueue()`：widget 测试跑在 FakeAsync 里，
      // 真实事件队列永远不会推进，那个调用会直接挂死。
      await tester.pumpAndSettle();
      expect(find.text('清除密钥'), findsOneWidget);
      // 写钥匙串是异步的，但只跨微任务，pump 之后就落定。
      expect(store.value, 'sk-typed');

      await tester.tap(find.text('清除密钥'));
      await tester.pumpAndSettle();

      expect(find.text('清除密钥'), findsNothing);
      expect(find.textContaining('已清除密钥'), findsOneWidget);
      expect(store.value, isNull);
    });

    testWidgets('连通性测试成功后在页内说明结果，并讲清楚空正文也算通', (tester) async {
      http.Request? seen;
      await pumpRoute(
        tester,
        const InsightConfigPage(),
        overrides: [
          insightApiKeyProvider
              .overrideWith(() => _FrozenInsightKey('sk-test')),
          insightHttpClientProvider.overrideWithValue(
            MockClient((request) async {
              seen = request;
              return http.Response.bytes(
                utf8.encode(jsonEncode({
                  'choices': [
                    {
                      'message': {'content': ''},
                    }
                  ],
                })),
                200,
              );
            }),
          ),
        ],
      );

      await tester.tap(find.text('连通性测试'));
      await tester.pumpAndSettle();

      expect(seen!.url.path, endsWith('/chat/completions'));
      expect(find.textContaining('连通正常'), findsOneWidget);
      // 推理模型会只吐推理过程：这条说明必须在，否则用户会以为空回复是失败。
      expect(find.textContaining('正文为空'), findsOneWidget);
    });

    testWidgets('展开下拉菜单不依赖卡片内部裁剪', (tester) async {
      await pumpRoute(tester, const InsightConfigPage());

      await tester.tap(find.text('DeepSeek'));
      await tester.pumpAndSettle();

      // The menu is drawn in the app overlay, so all three options exist and are
      // laid out inside the viewport rather than clipped by the glass card.
      expect(find.text('OpenAI'), findsOneWidget);
      expect(find.text('Claude'), findsOneWidget);
      final menuRect = tester.getRect(find.text('Claude'));
      expect(menuRect.left, greaterThanOrEqualTo(0));
      expect(menuRect.right, lessThanOrEqualTo(430));
    });
  });

  group('应用外壳', () {
    testWidgets('顶部渐变带贴在屏幕物理顶端，不被顶部安全区推下去', (tester) async {
      // 分界线来自「整条带被 SafeArea 一起下移」。把顶部安全区设成非零，
      // 这条断言才看得见东西——pad 为 0 时推不推下去都一样。
      tester.view.devicePixelRatio = 1.0;
      tester.view.padding = const FakeViewPadding(top: 47);
      addTearDown(tester.view.reset);

      await pumpWithOverrides(tester, const AppScaffold());

      final fade = find.byType(TopFade);
      expect(fade, findsOneWidget, reason: '外壳里没有顶部渐变带');
      expect(
        tester.getTopLeft(fade).dy,
        0,
        reason: '渐变带被顶部安全区推下去了——状态栏那段会完全没有渐变，'
            '而带内第一个停点是满值 alpha，两者形成一条硬分界',
      );
      expect(tester.getSize(fade).height, 144);
    });

    testWidgets('手机横屏（窄而矮）：侧边栏不溢出，中段那一列可以滚', (tester) async {
      // 844×390：宽度过了 768 的断点，于是走侧边栏；可高度只剩 390。头部的 logo 块、
      // 中段四条导航、底部的助眠音效卡三段加起来比这高时，中段必须让得开——它现在
      // 是可以滚的（用户报的「左下角白噪音处有黑黄警告条」就是这里撑破了）。
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      for (final entry in const [
        ('844x390', Size(844, 390), 1.0),
        ('800x360', Size(800, 360), 1.0),
        ('780x360', Size(780, 360), 1.0),
        ('926x428', Size(926, 428), 1.0),
        ('768x360', Size(768, 360), 1.0),
        ('844x390@1.3', Size(844, 390), 1.3),
        ('800x360@1.3', Size(800, 360), 1.3),
      ]) {
        tester.platformDispatcher.textScaleFactorTestValue = entry.$3;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await pumpWithOverrides(tester, const AppScaffold(), surface: entry.$2);
        // 溢出以异常形式抛出。
        expect(tester.takeException(), isNull, reason: '${entry.$1} 侧边栏溢出');
      }

      // 四条导航仍然都在（滚得到，不是被裁掉）。
      for (final label in ['首页', '回顾', '统计', '设置']) {
        expect(find.text(label), findsWidgets, reason: '少了「$label」');
      }
      expect(find.text('助眠音效'), findsOneWidget, reason: '底部那张卡仍在');
    });
  });

  group('读取失败的兜底留白', () {
    /// 顶部安全区非零，这样「留白有没有补上」才看得见。数据库读取失败时，
    /// 首页 / 统计页会落到 `EmptyState`（`GlassSurface`）这一支。
    Future<void> pumpError(WidgetTester tester, Widget page) async {
      tester.view.physicalSize = const Size(430, 900);
      tester.view.devicePixelRatio = 1.0;
      tester.view.padding = const FakeViewPadding(top: 47);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(database),
            sleepEntriesProvider.overrideWith(
              (ref) => Future<List<SleepEntry>>.error(StateError('数据库打不开')),
            ),
            settingsProvider.overrideWith((ref) => Stream.value(settings())),
            // 首页即使走错误分支也会 `ref.watch(activeSessionProvider)`，不覆盖
            // 它会真订阅 drift 的流，在测试拆树时留下 pending timer。
            activeSessionProvider.overrideWith((ref) => null),
          ],
          child:
              MaterialApp(theme: AppTheme.light(), home: Scaffold(body: page)),
        ),
      );
      await tester.pumpAndSettle();
    }

    void expectInset(WidgetTester tester) {
      final card = find.ancestor(
        of: find.text('无法读取记录'),
        matching: find.byType(GlassSurface),
      );
      expect(card, findsOneWidget, reason: '错误态没有渲染成 GlassSurface 卡片');
      final rect = tester.getRect(card.first);
      // pageTopInset(47 + 24) 与 pageGutter(16) —— 卡片必须落在同一套留白内。
      expect(rect.top, greaterThanOrEqualTo(47),
          reason: '错误卡片顶到了状态栏，说明这一支没补 pageTopInset');
      expect(rect.left, greaterThanOrEqualTo(16),
          reason: '错误卡片没有左侧 pageGutter');
      expect(rect.right, lessThanOrEqualTo(430 - 16),
          reason: '错误卡片没有右侧 pageGutter');
    }

    testWidgets('首页错误分支仍给状态栏留白', (tester) async {
      await pumpError(tester, home());
      expectInset(tester);
    });

    testWidgets('统计页错误分支仍给状态栏留白', (tester) async {
      await pumpError(tester, const StatsPage());
      expectInset(tester);
    });
  });
}

/// 相当于用户在设置页里已经填好的密钥：会话内存里预置一个值。
class _FrozenInsightKey extends InsightApiKeyNotifier {
  _FrozenInsightKey(this._value);

  final String _value;

  @override
  String build() => _value;
}

/// 应用缓存的内存替身：widget 测试里没有文件系统通道，也不该真去删东西。
class _FakeAppCache implements AppCache {
  _FakeAppCache({this.bytes = 0, this.fails = false});

  int bytes;
  final bool fails;
  bool cleared = false;

  @override
  Future<int> size() async {
    if (fails) throw StateError('no temp directory');
    return cleared ? 0 : bytes;
  }

  @override
  Future<int> clear() async {
    if (fails) throw StateError('no temp directory');
    cleared = true;
    final freed = bytes;
    bytes = 0;
    return freed;
  }
}

/// 钥匙串的内存替身：widget 测试里没有平台通道。
class _FakeInsightKeyStore implements InsightKeyStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async => this.value = value;

  @override
  Future<void> clear() async => value = null;
}
