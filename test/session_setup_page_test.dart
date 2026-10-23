import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:night_sleep/app/app_toast.dart';
import 'package:night_sleep/app/noise_session.dart';
import 'package:night_sleep/core/database/app_database.dart';
import 'package:night_sleep/core/platform/reminders.dart';
import 'package:night_sleep/core/theme/app_theme.dart';
import 'package:night_sleep/core/widgets/ios_controls.dart';
import 'package:night_sleep/features/session/presentation/night_scene.dart';
import 'package:night_sleep/features/session/presentation/sleep_session_page.dart';
import 'package:night_sleep/features/session/presentation/widgets/night_backdrop.dart';
import 'package:night_sleep/features/session/presentation/widgets/session_setup.dart';
import 'package:night_sleep/features/session/presentation/widgets/sleep_moon_mark.dart';
import 'package:night_sleep/features/sleep/data/noise_player.dart';
import 'package:night_sleep/features/sleep/data/noise_asset.dart';
import 'package:night_sleep/features/sleep/data/session_repository.dart';
import 'package:night_sleep/features/sleep/domain/sleep_session.dart';

/// 记下每一次播放器调用的假实现（与 `sleep_session_page_test.dart` 里那份同款）。
class _FakeNoisePlayer extends NoisePlayer {
  final List<String> calls = [];

  @override
  Future<void> play(NoiseKind kind, {required double volume}) async {
    calls.add('play:${kind.id}:${volume.toStringAsFixed(2)}');
  }

  @override
  Future<void> setVolume(double volume) async {
    calls.add('volume:${volume.toStringAsFixed(2)}');
  }

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Future<void> dispose() async => calls.add('dispose');
}

/// 权限给得了、排定什么都记下来的调度器。
///
/// 会话闹钟（9003）与日常起床提醒（9002）必须成对推导，所以两条路都要可见。
class _GrantingReminderScheduler extends NoopReminderScheduler {
  final List<String> calls = [];

  @override
  Future<ReminderPermission> requestPermission() async =>
      ReminderPermission.granted;

  /// `syncSessionAlarm` 看的是 `permission()`（观测），不是 `requestPermission()`：
  /// 只给前者授权，9003 还是排不出来。
  @override
  Future<ReminderPermission> permission() async => ReminderPermission.granted;

  @override
  Future<void> sync(ReminderPlan plan) async => calls.add('syncDaily');

  @override
  Future<void> syncAlarm(ReminderRequest? request) async =>
      calls.add('syncAlarm:${request?.id}');
}

void main() {
  late AppDatabase database;

  setUp(() => database = AppDatabase(NativeDatabase.memory()));
  tearDown(() => database.close());

  /// 会话页背景是 60 秒循环动画，开着它 `pumpAndSettle()` 会 timed out（已实测）。
  void disableAnimations(WidgetTester tester) {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }

  /// 挂「没有会话」的会话页——也就是入睡前态。
  ///
  /// `activeSessionProvider` 覆盖成 `null` 而不是让它去读库：读库那条路订阅的是
  /// drift 的 `watch*` 流，widget 测试的假时钟不推进，订阅它会留下 pending timer
  /// （见 `.claude/skills/flutter-pitfalls`）。开局没有会话行，这个覆盖与真值一致。
  Future<void> pumpSetup(
    WidgetTester tester, {
    NoisePlayer? player,
    ReminderScheduler? scheduler,
    Size size = const Size(430, 2000),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    disableAnimations(tester);

    final router = GoRouter(
      initialLocation: '/sleep/session',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('首页占位'))),
        ),
        GoRoute(
          path: '/sleep/session',
          builder: (context, state) =>
              SleepSessionPage(now: DateTime(2026, 8, 30, 23, 14)),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          activeSessionProvider.overrideWith((ref) => null),
          reminderSchedulerProvider
              .overrideWithValue(scheduler ?? NoopReminderScheduler()),
          noisePlayerProvider.overrideWithValue(player ?? _FakeNoisePlayer()),
        ],
        child: MaterialApp.router(
          theme: AppTheme.dark(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder toggleLabeled(String label) => find.byWidgetPredicate(
        (widget) => widget is IosToggle && widget.semanticLabel == label,
      );

  NightScene backdropScene(WidgetTester tester) =>
      tester.widget<NightBackdrop>(find.byType(NightBackdrop)).scene;

  String? playingNoiseId(WidgetTester tester) => ProviderScope.containerOf(
        tester.element(find.byType(SleepSessionPage)),
      ).read(noiseSessionControllerProvider).activeId;

  group('入睡前态', () {
    testWidgets('是「准备入睡」而不是「没有正在进行的睡眠」', (tester) async {
      await pumpSetup(tester);

      expect(find.text('准备好休息了吗？'), findsOneWidget);
      expect(find.text('放下今天，让夜晚慢下来。'), findsOneWidget);
      expect(find.text('睡眠模式'), findsOneWidget);
      expect(find.text('夜景氛围'), findsOneWidget);
      expect(find.text('常用白噪音'), findsOneWidget);
      expect(find.text('开始睡眠'), findsOneWidget);
      expect(find.text('屏幕将保持暗色，轻触夜景即可切换氛围'), findsOneWidget);
      // 旧空状态已被 setup 态取代。
      expect(find.text('没有正在进行的睡眠'), findsNothing);
    });

    testWidgets('进页面什么都不写库', (tester) async {
      await pumpSetup(tester);

      expect(
        await database.activeSession(),
        isNull,
        reason: '记录起点是页内的「开始睡眠」，不是进页面',
      );
    });

    testWidgets('点「开始睡眠」才写会话行，入睡时刻就是按下的时刻', (tester) async {
      await pumpSetup(tester);

      await tester.tap(find.text('开始睡眠'));
      await tester.pumpAndSettle();

      final session = await database.activeSession();
      expect(session, isNotNull);
      expect(session!.startAtUtc.toLocal(), DateTime(2026, 8, 30, 23, 14));
      expect(session.alarmEnabled, isFalse, reason: '没开闹钟就不许排一个');
      expect(session.noiseId, isNull, reason: '没选音就不许写一条在放的音');
    });

    testWidgets('草稿随行一次写进去：场景、白噪音、音量', (tester) async {
      final player = _FakeNoisePlayer();
      // 横向场景列表是懒加载的：手机宽度下第七张「银河」还没上舞台，
      // `find.text` 够不着它（`session_night_widgets_test.dart` 的 pumpPicker 同理）。
      await pumpSetup(tester, player: player, size: const Size(900, 2000));

      await tester.tap(find.text('银河'));
      await tester.pumpAndSettle();
      expect(backdropScene(tester), NightScene.galaxy, reason: '点一下整屏就该换');

      await tester.tap(find.text('篝火'));
      await tester.pumpAndSettle();
      expect(player.calls, contains('play:fire:0.50'), reason: 'setup 里点选即试听');
      expect(
        await database.activeSession(),
        isNull,
        reason: '攒草稿阶段一个字都不许落库',
      );

      await tester.tap(find.text('开始睡眠'));
      await tester.pumpAndSettle();

      final session = (await database.activeSession())!;
      expect(session.sceneId, 'galaxy');
      expect(session.noiseId, 'fire');
      expect(session.noiseVolume, 0.50);
    });

    testWidgets('点「收起」停掉试听、不写库、回上一页', (tester) async {
      final player = _FakeNoisePlayer();
      await pumpSetup(tester, player: player);

      await tester.tap(find.text('篝火'));
      await tester.pumpAndSettle();

      // 收起之后这一页就没了，容器引用要先抓住。
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SleepSessionPage)),
      );

      await tester.tap(find.text('收起'));
      await tester.pumpAndSettle();

      expect(find.text('首页占位'), findsOneWidget, reason: '收起就是离开这一页');
      expect(
        await database.activeSession(),
        isNull,
        reason: '收起不是开始：一个字都不许写',
      );
      expect(player.calls.last, 'stop', reason: '没有会话在跑，试听不该留在后台');
      expect(container.read(noiseSessionControllerProvider).activeId, isNull);
    });

    testWidgets('草稿不跨页存活：再进来回到流星夜、白噪音没选中', (tester) async {
      final player = _FakeNoisePlayer();
      await pumpSetup(tester, player: player, size: const Size(900, 2000));

      await tester.tap(find.text('银河'));
      await tester.tap(find.text('篝火'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('收起'));
      await tester.pumpAndSettle();

      // 回首页再进一次（这一页是推入的，路由回退后再推）。
      GoRouter.of(tester.element(find.text('首页占位'))).push('/sleep/session');
      await tester.pumpAndSettle();

      expect(backdropScene(tester), NightScene.meteor,
          reason: '草稿活在 State 里，卸载即丢');
      expect(playingNoiseId(tester), isNull);
    });
  });

  /// 「会话行一写下去，页面就翻到进行中态」这条链的**接线**部分。
  ///
  /// 这里不挂 widget：页面那一半（provider 里有会话就渲染进行中态）本仓库到处都是，
  /// 而 `activeSessionProvider` 的更新靠的是它 `ref.watch` 的 drift 流——**在
  /// `testWidgets` 里订阅那条流会留下 pending timer**（`AutomatedTestWidgetsFlutterBinding`
  /// 拆树后会断言失败，已实测），这正是本文件与 `sleep_session_page_test.dart` 的夹具
  /// 全都覆盖它的原因。所以这条用不挂树的 `ProviderContainer` 验。
  test('写下会话行之后，activeSessionProvider 会把新会话推上来', () async {
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(database)],
    );
    addTearDown(container.dispose);

    final seen = <SleepSession?>[];
    container.listen(
      activeSessionProvider,
      (_, next) => seen.add(next.valueOrNull),
      fireImmediately: true,
    );
    await container.read(activeSessionProvider.future);
    expect(seen.last, isNull, reason: '开局没有会话');

    await SessionRepository(database).start(now: DateTime(2026, 8, 30, 23, 14));

    // drift 的 watch 流是异步推的，给它几轮事件循环。
    for (var i = 0; i < 25 && seen.last == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(seen.last, isNotNull, reason: '写库之后必须把新会话推上来');
    expect(seen.last!.startAtUtc.toLocal(), DateTime(2026, 8, 30, 23, 14));
  });

  group('起床闹钟（草稿）', () {
    testWidgets('权限被拒时开关弹回、不写库，也不拦着开始睡眠', (tester) async {
      // NoopReminderScheduler.requestPermission() 返回 unsupported——「平台安排不了」
      // 那条分支，与设置页走同一个闸口。
      await pumpSetup(tester);

      await tester.tap(toggleLabeled('起床闹钟'));
      await tester.pumpAndSettle();

      expect(
        tester.widget<IosToggle>(toggleLabeled('起床闹钟')).value,
        isFalse,
        reason: '被拒时开关自己弹回去',
      );
      expect(await database.activeSession(), isNull);
      expect(
        ProviderScope.containerOf(tester.element(find.byType(SleepSessionPage)))
            .read(toastProvider),
        contains('闹钟未开启'),
        reason: '被拒必须给出说明，不能静默弹回',
      );

      // 没设闹钟不影响开始这一晚——闸口只挡闹钟，不挡睡眠本身。
      await tester.tap(find.text('开始睡眠'));
      await tester.pumpAndSettle();
      expect((await database.activeSession())?.alarmEnabled, isFalse);
    });

    testWidgets('时刻草稿取自设置里的起床提醒，开始睡眠时写进会话行', (tester) async {
      await database.updateSettings(
        const AppSettingsCompanion(wakeReminderMinutes: Value(390)),
      );
      final scheduler = _GrantingReminderScheduler();
      await pumpSetup(tester, scheduler: scheduler);

      await tester.tap(toggleLabeled('起床闹钟'));
      await tester.pumpAndSettle();

      expect(tester.widget<IosToggle>(toggleLabeled('起床闹钟')).value, isTrue);
      expect(find.text('06:30'), findsOneWidget, reason: '草稿复用设置里的起床提醒时刻');
      expect(
        await database.activeSession(),
        isNull,
        reason: '开关本身还没开始这一晚，不该写会话行',
      );

      await tester.tap(find.text('开始睡眠'));
      await tester.pumpAndSettle();

      final session = (await database.activeSession())!;
      expect(session.alarmEnabled, isTrue);
      expect(session.wakeMinutes, 390);
      expect(
        scheduler.calls,
        contains('syncAlarm:${ReminderScheduler.wakeAlarmId}'),
        reason: '写完会话行要立刻排会话闹钟',
      );
      expect(scheduler.calls, contains('syncDaily'),
          reason: '9003 与 9002 必须走 syncAllReminders 成对推导');
    });
  });

  /// 最终生效层的媒体查询（`index.css:1937` 起）：窄屏把 deck 的内边距收到 13，
  /// 并让常用白噪音四格竖排。
  ///
  /// **原本还有第二条**（高屏把 hero 从 230 撑到 285），2026-10-03 起不再是布尔判断，
  /// 见下面「hero 的高度按可用高度连续取值」那条。
  group('最终生效层的媒体查询：窄屏 deck', () {
    testWidgets('窄屏（375）四格改竖排：图标在上、标签在下', (tester) async {
      await pumpSetup(tester, size: const Size(375, 2000));

      final tile = find.ancestor(
        of: find.text('篝火'),
        matching: find.byWidgetPredicate((w) => w is AnimatedContainer),
      );
      expect(tile, findsOneWidget, reason: '「篝火」那一格应当就是这一块');

      final icon = find.descendant(of: tile, matching: find.byType(SvgPicture));
      expect(icon, findsOneWidget);
      expect(
        tester.getCenter(find.text('篝火')).dy,
        greaterThan(tester.getCenter(icon).dy + 6),
        reason: '竖排时标签在图标下方（并排时两者同一行，差不到 6）',
      );
    });

    testWidgets('宽屏（430）四格并排：图标与标签同一行', (tester) async {
      await pumpSetup(tester);

      final tile = find.ancestor(
        of: find.text('篝火'),
        matching: find.byWidgetPredicate((w) => w is AnimatedContainer),
      );
      final icon = find.descendant(of: tile, matching: find.byType(SvgPicture));
      expect(
        (tester.getCenter(find.text('篝火')).dy - tester.getCenter(icon).dy)
            .abs(),
        lessThan(3),
        reason: '并排时两者居中对齐',
      );
      expect(
        tester.getCenter(find.text('篝火')).dx,
        greaterThan(tester.getCenter(icon).dx),
        reason: '并排时标签在图标右侧',
      );
    });

    testWidgets('hero 的高度按可用高度连续取值', (tester) async {
      Future<double> heroHeight(WidgetTester tester) async {
        final box = find.ancestor(
          of: find.byType(SleepMoonOrbit),
          matching: find.byType(ConstrainedBox),
        );
        return tester.getSize(box.first).height;
      }

      await pumpSetup(tester);
      expect(await heroHeight(tester), 285, reason: '2000 高的视口给得下设计的高屏值');

      // 矮屏：**必须比 285 矮**（挡「把 285 写死」），但也**不能压到三段文案以下**
      // （挡「为了塞下一屏把文案挤没」）。
      await pumpSetup(tester, size: const Size(430, 800));
      final short = await heroHeight(tester);
      expect(short, lessThan(285), reason: '矮屏不该拿到高屏那支的 285');
      expect(short, greaterThanOrEqualTo(210),
          reason: '月亮 + 三段文案本身就约 210 高，低于它就是压内容了');
    });
  });

  /// 底部安全区与「一屏放下」的护栏。
  ///
  /// 用户 2026-10-03 报的：手机底部那颗「开始睡眠」被安全区切掉一截。两件事分开钉——
  ///
  ///  * **硬要求**：按钮在**任何**机型上都完整落在底部安全区之上（它不参与滚动）；
  ///  * **软要求**：常见机型上整页不滚动（上半区的 `maxScrollExtent == 0`）。
  ///
  /// 安全区取 59 / 34，与带灵动岛的 iPhone 一致。
  group('底部安全区与一屏放下', () {
    Future<void> pumpPhone(WidgetTester tester, Size logical) async {
      tester.view.padding = const FakeViewPadding(top: 59, bottom: 34);
      addTearDown(tester.view.reset);
      await pumpSetup(tester, size: logical);
    }

    /// 底部安全区在这一批用例里的上沿（屏幕坐标）。
    const safeTop = 34.0;

    Rect buttonRect(WidgetTester tester) => tester.getRect(
          find
              .ancestor(
                of: find.text('开始睡眠'),
                matching: find.byType(Container),
              )
              .first,
        );

    double upperScrollExtent(WidgetTester tester) {
      final scroll = find.descendant(
        of: find.byType(SessionSetupBody),
        matching: find.byType(SingleChildScrollView),
      );
      return tester
          .widget<SingleChildScrollView>(scroll)
          .controller!
          .position
          .maxScrollExtent;
    }

    for (final size in const [
      Size(393, 852), // iPhone 15 / 16 基础款
      Size(402, 874), // iPhone 16 Pro
      Size(430, 932), // 大屏
    ]) {
      testWidgets(
          '${size.width.toInt()}×${size.height.toInt()}：一屏放下，'
          '按钮在安全区之上', (tester) async {
        await pumpPhone(tester, size);

        expect(
          buttonRect(tester).bottom,
          lessThan(size.height - safeTop),
          reason: '按钮不能被底部安全区切掉',
        );
        expect(
          upperScrollExtent(tester),
          0,
          reason: '这一档机型上整页应当一屏放下、一点都不用滚',
        );
        expect(
          tester.getRect(find.text('屏幕将保持暗色，轻触夜景即可切换氛围')).top -
              buttonRect(tester).bottom,
          greaterThanOrEqualTo(8),
          reason: '开始睡眠按钮与下方提示文案之间要留出间距',
        );
      });
    }

    testWidgets('矮屏（375×667）放不下时：卡片可以滚，按钮照样不被切', (tester) async {
      await pumpPhone(tester, const Size(375, 667));

      expect(upperScrollExtent(tester), greaterThan(0),
          reason: '这一档确实放不下，上半区应当可滚');
      expect(
        buttonRect(tester).bottom,
        lessThan(667 - safeTop),
        reason: '**放不下也不许把按钮挤进安全区**——这是这条修复的本体',
      );
    });
  });

  testWidgets('宽屏下两态内容居中限宽 540', (tester) async {
    await pumpSetup(tester, size: const Size(1200, 2000));

    // 量内容列本身。**不能再用 `ListView.first`**：v3.10 起入睡前态是一条
    // `SingleChildScrollView`（钉底按钮 + 上半区），`.first` 会落到卡片里那条
    // 横向滚动的场景选择器上，量到的宽度是「680 − 两侧 20 − 卡片描边」。
    final content = find.descendant(
      of: find.byType(SleepSessionPage),
      matching: find.byType(SessionSetupBody),
    );
    expect(tester.getSize(content).width, 540);
    expect(
      tester.getCenter(content).dx,
      600,
      reason: '限宽之后要居中，不是靠左',
    );
  });
}
