import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:night_sleep/app/app.dart';
import 'package:night_sleep/app/noise_session.dart';
import 'package:night_sleep/core/database/app_database.dart';
import 'package:night_sleep/core/platform/reminders.dart';
import 'package:night_sleep/core/platform/system_bars.dart';
import 'package:night_sleep/core/theme/app_tokens.dart';
import 'package:night_sleep/features/session/presentation/session_panel_transition.dart';
import 'package:night_sleep/features/session/presentation/sleep_session_page.dart';
import 'package:night_sleep/features/session/presentation/widgets/night_backdrop.dart';
import 'package:night_sleep/features/session/presentation/widgets/session_header.dart';
import 'package:night_sleep/features/sleep/data/noise_asset.dart';
import 'package:night_sleep/features/sleep/data/noise_player.dart';
import 'package:night_sleep/features/sleep/data/session_repository.dart';
import 'package:night_sleep/features/sleep/data/sleep_repository.dart';
import 'package:night_sleep/features/sleep/domain/sleep_entry.dart';
import 'package:night_sleep/features/sleep/domain/sleep_session.dart';

import 'system_bar_probe.dart';

/// 会话页的**呈现方式**：从底部升起、可从标题行下拉滑走。
///
/// 2026-10-14 由使用方拍板（原型里 `SleepView` 本来就是首页里的一个模态），四个决定：
/// 整屏升起顶部不留缝、两态都走这个呈现、关闭方式只有「收起」与下拉（**不**点蒙层）、
/// 下拉区是标题行整行且露出的是首页。
///
/// **这个文件走的是真实的 `NightSleepApp`**——`app.dart` 里那条 `pageBuilder` 只有在
/// 真实路由下才跑得到，在测试里另起一份路由会把要验的东西架空（这一条与
/// `sleep_session_page_test.dart` 里那条「点收起回到上一页」同理）。
/// 记下每一次播放器调用的假实现（与另外两个会话测试文件里那份同款）。
class _FakePlayer extends NoisePlayer {
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

void main() {
  late AppDatabase database;

  setUp(() => database = AppDatabase(NativeDatabase.memory()));
  tearDown(() => database.close());

  SleepSession sessionAt(DateTime start) => SleepSession(
        startAtUtc: start.toUtc(),
        timeZoneId: 'UTC',
        wakeMinutes: 7 * 60,
        alarmEnabled: false,
        createdAtUtc: start.toUtc(),
      );

  /// 会话页背景是 60 秒循环动画，开着它 `pumpAndSettle()` 会 timed out（已实测）。
  ///
  /// `disableAnimations` 会把**所有** `AnimationController` 的时长压到 5%，所以但凡
  /// 要看转场的中间帧，就得在挂载之后把它关掉（见 [enableAnimations]）。
  void disableAnimations(WidgetTester tester) {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }

  /// 把动画放回真实时长。
  ///
  /// **挂载时不能开着**：开屏页加上首页那几段动画永不收敛，`pumpAndSettle()` 直接
  /// timed out。所以顺序是「关着挂载、settle 完、再打开」，然后只用显式
  /// `pump(Duration)` 推进——夜景那 60 秒循环一旦跑起来就再也不能 `pumpAndSettle`。
  void enableAnimations(WidgetTester tester) {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures();
  }

  /// 挂真实的 `NightSleepApp`。
  ///
  /// `session` 传 `null` 就是入睡前态（首页那颗按钮只进页面、不写库），传一个会话
  /// 就是进行中态。
  ///
  /// `animations: true` **只在验转场那一条上用**，而且是在挂载并 settle 完之后才
  /// 把动画放回真实时长——挂载时就开着的话，`pumpAndSettle()` 根本收敛不了。
  Future<void> pumpRealApp(
    WidgetTester tester, {
    SleepSession? session,
    _FakePlayer? player,
    bool animations = false,
    Size size = const Size(430, 874),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    disableAnimations(tester);

    // 外壳与首页各自订阅了 drift 的 `watch*` 流；widget 测试的假时钟不推进，
    // 订阅它们会留下 pending timer（见 `.claude/skills/flutter-pitfalls`）。
    // 真路由要跑得起来，这几条流都得换成 provider override。
    await database
        .updateSettings(const AppSettingsCompanion(onboarded: Value(true)));
    final settings = await database.getSettings();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          settingsProvider.overrideWith((ref) => Stream.value(settings)),
          sleepEntriesProvider.overrideWith((ref) => const <SleepEntry>[]),
          activeSessionProvider.overrideWith((ref) => session),
          reminderSchedulerProvider.overrideWithValue(NoopReminderScheduler()),
          noisePlayerProvider.overrideWithValue(player ?? _FakePlayer()),
        ],
        child: const NightSleepApp(),
      ),
    );
    await tester.pumpAndSettle();

    // **`app.dart` 里那条 `GoRouter` 是进程级单例**（模块顶层 `final`），路由栈会跨
    // 用例累积：上一个用例推入的会话页仍留在栈里，本用例再推一次就会同时挂出两页
    // （实测：不加这一步，第三个用例能同时找到三个会话页；单独跑那一条却是绿的）。
    // `go('/')` 先把栈收回根，之后的推入才是从干净状态开始的。
    GoRouter.of(tester.element(find.byType(AppScaffold))).go('/');
    await tester.pumpAndSettle();

    if (animations) enableAnimations(tester);
  }

  /// 从首页推入会话页——走的正是 `app.dart` 注册的那条路由。
  Future<void> openSession(WidgetTester tester) async {
    GoRouter.of(tester.element(find.byType(AppScaffold)))
        .push('/sleep/session');
    await tester.pumpAndSettle();
  }

  /// 标题行**中间那一段**的落点。
  ///
  /// 取正中央而不是随便一点：`收起` 胶囊就在同一行的左端，从那里起手测的会是
  /// 「点击 vs 拖拽」的裁决，而不是下拉本身。
  Offset headerPoint(WidgetTester tester) =>
      tester.getRect(find.byType(SessionHeader)).center;

  /// 面板顶边的实际位置。
  ///
  /// **不能量 `SleepSessionPage`**：它最外层是 `AnnotatedRegion`，而位移用的
  /// `Transform` 在它**里面**（刻意如此——遮罩与系统栏那一层都不跟着面板走），
  /// 所以页面的盒子永远钉在顶边，量它永远得到 0。量铺满整屏的 `NightBackdrop`
  /// 才量得到真实的位移。
  Finder panelBody() => find.byType(NightBackdrop);

  /// 超过 `kPanelDismissFraction` 的下拉。**用 `timedDragFrom` 而不是 `dragFrom`**：
  /// 后者把整段位移放在一个事件里，速度算出来极大，会被判成「甩动」而掩盖掉
  /// 「距离够不够」这条判据（`app_sheet_test.dart` 记过同一条）。
  Future<void> dragHeaderSlowly(
    WidgetTester tester,
    double distance, {
    Duration duration = const Duration(milliseconds: 800),
  }) async {
    await tester.timedDragFrom(
        headerPoint(tester), Offset(0, distance), duration);
    await tester.pumpAndSettle();
  }

  group('呈现方式：整屏面板', () {
    testWidgets('挂会话页的那条路由不是不透明的——底下露出的必须是真首页', (tester) async {
      await pumpRealApp(tester,
          session: sessionAt(DateTime(2026, 8, 30, 23, 14)));
      await openSession(tester);

      final route =
          ModalRoute.of(tester.element(find.byType(SleepSessionPage)));
      expect(route!.opaque, isFalse, reason: '下拉时要能看见底下的首页');

      // 不是不透明，底下那条路由就还在树上——「露出的是首页」因此有据可查，
      // 而不是「滑开之后才发现底下是块黑板」。
      expect(
        find.text('睡眠概览'),
        findsOneWidget,
        reason: '首页应当还在下面那条路由里',
      );
    });

    testWidgets('从底部升起：转场头几帧面板还在屏幕下方，随后落到顶边', (tester) async {
      // **这条不能把动画关掉**：`disableAnimations` 会把 340ms 的转场压到 17ms，
      // 中间帧根本采不到。
      await pumpRealApp(
        tester,
        session: sessionAt(DateTime(2026, 8, 30, 23, 14)),
        animations: true,
      );

      final screenHeight = tester.view.physicalSize.height;

      GoRouter.of(tester.element(find.byType(AppScaffold)))
          .push('/sleep/session');
      // 第一帧把新路由建起来，第二帧才量得到它的子树（走 1ms，几乎没推进转场）。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));

      final atStart = tester.getTopLeft(panelBody()).dy;
      expect(atStart, greaterThan(0), reason: '升起的转场，起点应在屏幕下方而不是顶边');

      // 显式推进到转场结束（夜景那 60 秒循环永不收敛，这里不能用 `pumpAndSettle`）。
      await tester
          .pump(AppDurations.standard + const Duration(milliseconds: 20));
      expect(
        tester.getTopLeft(panelBody()).dy,
        0,
        reason: '升完之后应当正好顶到屏幕顶边',
      );
      expect(screenHeight, greaterThan(0));
    });

    testWidgets('静止时面板铺满整屏，顶边与屏幕顶对齐', (tester) async {
      await pumpRealApp(tester,
          session: sessionAt(DateTime(2026, 8, 30, 23, 14)));
      await openSession(tester);

      final size = tester.view.physicalSize;
      expect(
        tester.getRect(panelBody()),
        Rect.fromLTWH(0, 0, size.width, size.height),
        reason: '整屏升起、顶部不留缝——留了缝就是漏了位移没归零',
      );
    });
  });

  group('下拉关闭', () {
    testWidgets('进行中态：标题行下拉过阈值，面板滑走回到首页，会话继续跑', (tester) async {
      final player = _FakePlayer();
      await pumpRealApp(
        tester,
        session: sessionAt(DateTime(2026, 8, 30, 23, 14)),
        player: player,
      );
      await openSession(tester);
      expect(find.text('睡眠进行中'), findsOneWidget);

      // 430×874 上阈值是 874 × .28 ≈ 245，拉 400 足够；800ms 让速度（500/s）压在
      // 700 的甩动线之下，于是**由距离而不是速度**决定关闭。
      await dragHeaderSlowly(tester, 400);

      expect(find.byType(SleepSessionPage), findsNothing, reason: '过阈值应当滑走');
      expect(find.text('睡眠概览'), findsOneWidget, reason: '回到的是首页');
      expect(
        player.calls,
        isNot(contains('stop')),
        reason: '进行中收起只是离开页面，白噪音要陪着这一晚（偏差 #28）',
      );
    });

    testWidgets('入睡前态：下拉关闭会先停掉试听，且一个字都不写库', (tester) async {
      // 视口给高一点，四格常用白噪音不用先滚就点得到。
      final player = _FakePlayer();
      await pumpRealApp(tester, player: player, size: const Size(430, 2000));
      await openSession(tester);

      await tester.tap(find.text('篝火'));
      await tester.pumpAndSettle();
      expect(player.calls.last, startsWith('play:'), reason: '点选即试听');

      // 2000 高时阈值是 560，拉 700；2 秒把速度压到 350/s，仍由距离决定。
      await dragHeaderSlowly(
        tester,
        700,
        duration: const Duration(seconds: 2),
      );

      expect(find.text('睡眠概览'), findsOneWidget, reason: '下拉就是离开这一页');
      expect(player.calls.last, 'stop', reason: '没有会话在跑，试听不该留在后台（偏差 #37）');
      expect(
        await database.activeSession(),
        isNull,
        reason: '下拉不是开始：一个字都不许写',
      );
    });

    testWidgets('小幅下拉后松手回弹，面板保持打开', (tester) async {
      await pumpRealApp(tester,
          session: sessionAt(DateTime(2026, 8, 30, 23, 14)));
      await openSession(tester);

      // 60px：越过约 18px 的 touch slop（短于它会被判成点击，测的就不是拖拽了），
      // 又远在 245 的阈值之下。
      await dragHeaderSlowly(tester, 60);

      expect(find.byType(SleepSessionPage), findsOneWidget, reason: '距离不足应回弹');
      expect(
        tester.getTopLeft(panelBody()).dy,
        0,
        reason: '回弹要真的回到位，不能停在一半',
      );
    });

    testWidgets('拖动过程中系统栏仍是这一页的深色', (tester) async {
      await pumpRealApp(tester,
          session: sessionAt(DateTime(2026, 8, 30, 23, 14)));
      await openSession(tester);

      final gesture = await tester.startGesture(headerPoint(tester));
      // **两段位移，并且先确认面板真的动了**：这个手势的识别器与页面里的滚动视图
      // 同场竞技，跨过 slop 那一刻会把整段累计位移丢掉（同文件「遮罩」那两条的注释）。
      // 只用一段的话面板一像素都不动，这条断言写什么都会过——它此前正是这样空转的。
      await gesture.moveBy(const Offset(0, 60));
      await tester.pump();
      await gesture.moveBy(const Offset(0, 120));
      await tester.pump();

      expect(tester.getTopLeft(panelBody()).dy, greaterThan(24),
          reason: '先证明面板真的被拉下去了，下面那条断言才有意义');

      expect(
        systemBarStyleAt(tester),
        appSystemUiOverlayStyle(Brightness.dark),
        reason: '面板一往下走（已超过一个状态栏高度），顶端露出的就是被压暗的首页'
            '——系统栏不能这时翻回应用主题。区域必须留在位移之外',
      );

      await gesture.cancel();
      await tester.pumpAndSettle();
    });
  });

  group('下拉时的那层遮罩', () {
    /// 遮罩的不透明度。
    double scrimOpacity(WidgetTester tester) => tester
        .widget<Opacity>(find.descendant(
          of: find.byType(SessionPanelScrim),
          matching: find.byType(Opacity),
        ))
        .opacity;

    /// 整屏矩形。
    Rect screenOf(WidgetTester tester) => Rect.fromLTWH(
        0, 0, tester.view.physicalSize.width, tester.view.physicalSize.height);

    testWidgets('拖动时遮罩变浓，但它自己钉在整屏不动', (tester) async {
      await pumpRealApp(tester,
          session: sessionAt(DateTime(2026, 8, 30, 23, 14)));
      await openSession(tester);

      expect(scrimOpacity(tester), 0, reason: '静止时不该有任何压暗');

      final gesture = await tester.startGesture(headerPoint(tester));
      // **两段位移**：第一段会被识别器吃掉（越过 touch slop 才开拖，那之前的累计位移
      // 不补发），只用一段的话面板根本不动，这条断言就成了空转。
      await gesture.moveBy(const Offset(0, 60));
      await tester.pump();
      await gesture.moveBy(const Offset(0, 160));
      await tester.pump();

      expect(scrimOpacity(tester), greaterThan(0), reason: '面板一走，露出来的那一层就该压暗');
      expect(
        tester.getRect(find.byType(SessionPanelScrim)),
        screenOf(tester),
        reason: '遮罩钉在整屏：跟着面板往下滑的话，顶端露出的首页就是没压暗的',
      );

      await gesture.cancel();
      await tester.pumpAndSettle();
    });

    testWidgets('过阈值松手：面板继续滑走，遮罩在原地淡出', (tester) async {
      await pumpRealApp(tester,
          session: sessionAt(DateTime(2026, 8, 30, 23, 14)));
      await openSession(tester);
      // 要采退场的中间帧，这里**挂载之后**才把动画放回真实时长（挂载时就开着的话
      // `pumpAndSettle` 根本收敛不了——夜景那 60 秒循环永不停止）。
      enableAnimations(tester);

      // 430×874 上阈值是 874 × .28 ≈ 245，拉 400 足够；800ms 让速度压在甩动线之下，
      // 结论因此由**距离**决定（同「下拉关闭」那几条）。
      await tester.timedDragFrom(
        headerPoint(tester),
        const Offset(0, 400),
        const Duration(milliseconds: 800),
      );
      expect(scrimOpacity(tester), closeTo(1, 0.01), reason: '拉过阈值那一刻遮罩是全浓的');

      // 退场走到一半。
      await tester.pump(AppDurations.standard ~/ 2);

      expect(
        tester.getTopLeft(panelBody()).dy,
        greaterThan(245),
        reason: '面板要继续往下滑走，不是原地消失',
      );
      expect(
        tester.getRect(find.byType(SessionPanelScrim)),
        screenOf(tester),
        reason: '遮罩**留在原地**：跟着面板走的话，顶端露出的首页是没压暗的',
      );
      final mid = scrimOpacity(tester);
      expect(mid, lessThan(1), reason: '退场时遮罩该在淡出');
      expect(mid, greaterThan(0), reason: '还没退完，不该已经没了');

      // 走完：这一页退掉，底下是首页。
      await tester.pump(AppDurations.standard);
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(SleepSessionPage), findsNothing);
      expect(find.text('睡眠概览'), findsOneWidget);
    });
  });

  group('「收起」胶囊', () {
    testWidgets('整体位于下拉区之内（下拉区是标题行整行）', (tester) async {
      await pumpRealApp(tester,
          session: sessionAt(DateTime(2026, 8, 30, 23, 14)));
      await openSession(tester);

      expect(
        find.ancestor(
          of: find.text('收起'),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is GestureDetector &&
                widget.onVerticalDragUpdate != null,
            description: '带竖直拖拽的 GestureDetector',
          ),
        ),
        findsOneWidget,
        reason: '只包中间那段的话，从胶囊上起手拖就不算下拉了',
      );
    });

    testWidgets('点它仍然是点击，不被判成拖拽', (tester) async {
      await pumpRealApp(tester,
          session: sessionAt(DateTime(2026, 8, 30, 23, 14)));
      await openSession(tester);

      await tester.tap(find.text('收起'));
      await tester.pumpAndSettle();

      expect(find.byType(SleepSessionPage), findsNothing, reason: '点击就该收起');
      expect(find.text('睡眠概览'), findsOneWidget);
    });
  });
}
