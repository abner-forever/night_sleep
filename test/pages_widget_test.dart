import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/app/app.dart';
import 'package:night_sleep/core/database/app_database.dart';
import 'package:night_sleep/core/theme/app_theme.dart';
import 'package:night_sleep/features/home/presentation/home_page.dart';
import 'package:night_sleep/features/log/presentation/log_page.dart';
import 'package:night_sleep/features/settings/presentation/demo_data_page.dart';
import 'package:night_sleep/features/settings/presentation/insight_config_page.dart';
import 'package:night_sleep/features/settings/presentation/settings_page.dart';
import 'package:night_sleep/features/settings/presentation/sleep_import_page.dart';
import 'package:night_sleep/features/sleep/data/demo_seed.dart';
import 'package:night_sleep/features/sleep/data/sleep_repository.dart';
import 'package:night_sleep/features/sleep/domain/sleep_entry.dart';
import 'package:night_sleep/features/sleep/domain/sleep_quality.dart';
import 'package:night_sleep/features/sleep/domain/sleep_score.dart';
import 'package:night_sleep/features/sleep/domain/sleep_stage.dart';
import 'package:night_sleep/features/stats/presentation/stats_page.dart';

/// Widget tests for the four primary pages.
///
/// These deliberately **do not** subscribe to the app's drift streams.
/// `watchAllRecords` / `watchSettings` drive their updates off timers, which
/// the widget-tester's fake clock never advances, so a subscribed query leaves
/// a pending timer at teardown (and can hang the test outright). Instead the
/// pages are handed the same data through provider overrides, and the two tests
/// that exercise a write path assert against the database directly.
void main() {
  late AppDatabase database;

  setUp(() => database = AppDatabase(NativeDatabase.memory()));
  tearDown(() => database.close());

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
  }) {
    return pumpWithOverrides(
      tester,
      Scaffold(body: page),
      entries: entries,
      appSettings: appSettings,
      surface: surface,
    );
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
  }) {
    return pumpWithOverrides(tester, page, entries: entries);
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

  Widget home() => HomePage(
        animateRing: false,
        onRingConsumed: () {},
        onOpenNoise: () {},
        onRecordNow: () {},
      );

  group('首页', () {
    testWidgets('空状态引导用户记录第一晚', (tester) async {
      await pumpPage(tester, home());

      expect(find.text('睡眠概览'), findsOneWidget);
      expect(find.text('还没有睡眠记录'), findsOneWidget);
      expect(find.text('记录第一晚'), findsOneWidget);
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
      expect(find.textContaining('全程安静'), findsWidgets, reason: '无声音事件是真实结论');
    });

    testWidgets('演示数据存在时给出可清除的来源提示', (tester) async {
      await pumpPage(tester, home(), entries: await demoEntries());
      expect(find.textContaining('正在显示演示数据'), findsOneWidget);
    });

    testWidgets('主操作按钮回调正确', (tester) async {
      var tapped = false;
      await pumpPage(
        tester,
        HomePage(
          animateRing: false,
          onRingConsumed: () {},
          onOpenNoise: () {},
          onRecordNow: () => tapped = true,
        ),
      );
      await tester.tap(find.text('记录昨夜睡眠'));
      await tester.pump();
      expect(tapped, isTrue);
    });
  });

  group('记录页', () {
    testWidgets('表单分组齐全', (tester) async {
      await pumpPage(tester, const LogPage());

      expect(find.text('今天睡得怎么样？'), findsOneWidget);
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

    testWidgets('保存写入数据库并标记为本地估算', (tester) async {
      await pumpPage(tester, const LogPage());

      await tester.tap(find.text('保存记录'));
      // Advance past the 2s "已保存" reset so no timer is left pending.
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));

      final saved = await SleepRepository(database).loadAll();
      expect(saved, hasLength(1));
      expect(saved.single.quality.value, 4, reason: '默认质量为「良好」');
      expect(saved.single.durationHours, closeTo(8, 0.001));
      // A hand-logged night has no measurements, so it must be scored locally
      // and must not claim measured stages or audio.
      expect(saved.single.isEstimated, isTrue);
      expect(saved.single.hasStages, isFalse);
      expect(saved.single.hasSoundEvents, isFalse);
      expect(saved.single.score, isNotNull);
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
  });

  group('设置页', () {
    testWidgets('分组齐全，未接入的能力有明确说明', (tester) async {
      await pumpPage(tester, const SettingsPage());

      expect(find.text('外观模式'), findsOneWidget);
      expect(find.text('睡眠目标'), findsOneWidget);
      expect(find.text('小米手环睡眠数据'), findsOneWidget);
      expect(find.text('就寝提醒'), findsOneWidget);
      expect(find.text('起床提醒'), findsOneWidget);
      expect(find.text('夜间声音录制'), findsOneWidget);
      expect(find.text('洞察服务配置'), findsOneWidget);
      expect(find.text('删除全部本地数据'), findsOneWidget);

      // Capability gaps must be stated rather than implied as working.
      expect(find.textContaining('尚未接入录音'), findsOneWidget);
      expect(find.textContaining('鼾声、梦话仍由手机夜间录音检测'), findsOneWidget);
    });

    testWidgets('外观模式切换写回数据库', (tester) async {
      await pumpPage(tester, const SettingsPage());

      await tester.tap(find.text('深色'));
      await tester.pumpAndSettle();

      expect((await database.getSettings()).themeMode, 'dark');
    });

    testWidgets('睡眠目标步进器写回数据库', (tester) async {
      await pumpPage(tester, const SettingsPage());

      await tester.tap(find.text('+'));
      await tester.pumpAndSettle();

      expect((await database.getSettings()).sleepGoalMinutes, 510);
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
  });

  group('设置二级页', () {
    // Sub-pages are pushed outside the tab shell, so they must apply the
    // content padding themselves. Before this was fixed they rendered
    // edge-to-edge and looked broken next to the tab pages.
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

    testWidgets('洞察配置页有内边距并标注未接入项', (tester) async {
      await pumpRoute(tester, const InsightConfigPage());

      expect(find.text('洞察服务配置'), findsWidgets);
      expect(find.text('大模型服务'), findsOneWidget);
      expect(find.text('服务商'), findsOneWidget);
      expect(find.text('模型'), findsOneWidget);
      expect(find.text('API Key'), findsOneWidget);
      expect(find.text('DeepSeek'), findsOneWidget);
      // Honest states: no fake balance, and the key is not persisted yet.
      expect(find.text('余额查询未接入'), findsOneWidget);
      expect(find.textContaining('尚未接入安全存储'), findsOneWidget);
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

      final remaining = await repository.loadAll();
      expect(remaining, hasLength(1), reason: '只应删掉演示行');
      expect(remaining.single.id, 'manual-1');
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
}
