import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
// `material.dart` 不带出 `ValueListenable`，而假录音服务要拿它当返回类型。
import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:night_sleep/app/app.dart';
import 'package:night_sleep/app/app_shell.dart';
import 'package:night_sleep/app/app_toast.dart';
import 'package:night_sleep/app/night_recording.dart';
import 'package:night_sleep/app/noise_session.dart';
import 'package:night_sleep/core/database/app_database.dart';
import 'package:night_sleep/core/platform/reminders.dart';
import 'package:night_sleep/core/platform/system_bars.dart';
import 'package:night_sleep/core/theme/app_theme.dart';
import 'package:night_sleep/core/widgets/ios_controls.dart';
import 'package:night_sleep/features/log/presentation/log_new_page.dart';
import 'package:night_sleep/features/session/presentation/night_scene.dart';
import 'package:night_sleep/features/session/presentation/night_style.dart';
import 'package:night_sleep/features/session/presentation/sheets/night_noise_sheet.dart';
import 'package:night_sleep/features/session/presentation/sleep_session_page.dart';
import 'package:night_sleep/features/session/presentation/widgets/hold_to_finish_button.dart';
import 'package:night_sleep/features/session/presentation/widgets/night_backdrop.dart';
import 'package:night_sleep/features/session/presentation/widgets/night_scene_picker.dart';
import 'package:night_sleep/features/sleep/data/night_recorder.dart';
import 'package:night_sleep/features/sleep/data/noise_player.dart';
import 'package:night_sleep/features/sleep/data/noise_asset.dart';
import 'package:night_sleep/features/sleep/data/session_repository.dart';
import 'package:night_sleep/features/sleep/data/sleep_repository.dart';
import 'package:night_sleep/features/sleep/domain/clip_journal.dart';
import 'package:night_sleep/features/sleep/domain/sleep_entry.dart';
import 'package:night_sleep/features/sleep/domain/sleep_quality.dart';
import 'package:night_sleep/features/sleep/domain/sleep_session.dart';

import 'system_bar_probe.dart';

/// 记下每一次播放器调用的假实现。
///
/// 会话里的白噪音由 app 级控制器驱动，这条接缝与 `NoiseSheet` 的 `player` 参数同款——
/// 没有它，选择、取消、倒计时到点这几条路径一条都测不到。
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

/// 记下调度器被要求做什么的假实现。
///
/// 测试里排不了真通知，但「有没有要求它重排」是看得见的，而闹钟重排恰恰是这个
/// 功能最容易悄悄退化的地方：`syncAlarm` 能让日常起床提醒 9002 让位，却不会把它
/// 排回来，所以两条路径都必须走 [syncAllReminders]——两笔都要记下来。
class _RecordingReminderScheduler extends NoopReminderScheduler {
  final List<String> calls = [];

  @override
  Future<void> sync(ReminderPlan plan) async => calls.add('syncDaily');

  @override
  Future<void> syncAlarm(ReminderRequest? request) async =>
      calls.add('syncAlarm:${request?.id}');
}

/// 停不掉声音的播放器。平台音频通道同样会抛，而收尾不允许被它挡住。
class _ThrowingNoisePlayer extends _FakeNoisePlayer {
  @override
  Future<void> stop() async => throw PlatformException(code: 'boom');
}

/// 排什么都会炸的调度器。
///
/// `LocalReminderScheduler` 调平台插件时没有护栏，`PlatformException` 是真会抛的
/// 那一种失败。记录早已落库，用户可见的收尾一条都不该被它吃掉。
class _ThrowingReminderScheduler extends NoopReminderScheduler {
  @override
  Future<void> sync(ReminderPlan plan) async =>
      throw PlatformException(code: 'boom');

  @override
  Future<void> syncAlarm(ReminderRequest? request) async =>
      throw PlatformException(code: 'boom');
}

/// 只回答「我现在是什么状态」的假录音服务。
///
/// 鼾声那一行的副标题由**录音服务的真实状态**驱动，所以要测它就必须能把状态捏成
/// 任意一态。与 `recording_settings_test.dart` 那个只答权限的假实现不同，这个的重点
/// 是 [status]。
class _StatusRecorder implements NightRecorder {
  _StatusRecorder(NightRecordingStatus status)
      : _status = ValueNotifier<NightRecordingStatus>(status);

  final ValueNotifier<NightRecordingStatus> _status;

  @override
  ValueListenable<NightRecordingStatus> get status => _status;

  @override
  Stream<ClipDraft> get closedClips => const Stream.empty();

  @override
  Future<bool> ensurePermission() async => true;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async => _status.dispose();
}

void main() {
  late AppDatabase database;

  setUp(() => database = AppDatabase(NativeDatabase.memory()));
  tearDown(() => database.close());

  /// 把系统「减弱动态效果」打开，画面停在夜景背景的静态层。
  ///
  /// 会话页的背景是一个 60 秒循环的动画，**开着它 `pumpAndSettle()` 会 timed out**
  /// （已实测）。`pumpSession` 已经在夹具里调过；不走 `pumpSession` 的用例
  /// （自己搭 widget 树的那几条）要显式调一次。
  void disableAnimations(WidgetTester tester) {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }

  /// 冻住时钟渲染会话页。
  ///
  /// 这里**必须**传固定的 `now`：页面在 `now` 非空时不起定时器，读数才不会被
  /// 真实时钟覆写。不传的话「3h 42m」「23:14」这类断言会随跑测试的日期时间
  /// 随机变红。（pending timer 不是这里的理由——拆树时 `dispose()` 会 cancel。）
  Future<void> pumpSession(
    WidgetTester tester, {
    required SleepSession session,
    required DateTime now,
    bool wide = false,
    Size? size,
    NoisePlayer? player,
    ReminderScheduler? scheduler,
    ThemeData? appTheme,
    NightRecorder? recorder,
  }) async {
    // 默认给一块很高的视口，好让整页一次渲染完（断言不用先滚）。
    // 要测「屏幕外」这类几何问题，传一个真实手机尺寸的 `size`。
    tester.view.physicalSize =
        size ?? (wide ? const Size(1200, 2000) : const Size(430, 2000));
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // 会话页的背景是一个 60 秒循环的动画，**开着它 `pumpAndSettle()` 会 timed out**
    // （已实测）。夹具统一把「减弱动态效果」打开，画面停在静态层。
    disableAnimations(tester);

    // 会话行**真的写进库**。覆盖 `activeSessionProvider` 只是为了冻住时钟、免起
    // 定时器；结束流程写的是真实数据库——`SessionRepository.finish()` 会 `load()`
    // 会话行，读不到就抛 `StateError`。只覆盖 provider 不写库，页面看到的会话与
    // 仓库读到的会话就是两回事，「跳过评星」「评了分」那两条永远红，而且测出来的
    // 根本不是真实链路。
    await database.saveActiveSession(
      ActiveSessionsCompanion.insert(
        id: SessionRepository.sessionId,
        startAtUtc: session.startAtUtc,
        timeZoneId: Value(session.timeZoneId),
        wakeMinutes: session.wakeMinutes,
        alarmEnabled: Value(session.alarmEnabled),
        noiseId: Value(session.noiseId),
        noiseVolume: Value(session.noiseVolume),
        createdAt: session.createdAtUtc,
      ),
    );

    // 结束流程会 `context.go('/')` 与 `context.push('/log/new')`；裸
    // `MaterialApp(home:)` 里没有 GoRouter，`GoRouter.of` 会直接断言失败。
    // 起一个最小路由，把这两个落点都注册上。
    final router = GoRouter(
      initialLocation: '/sleep/session',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(body: SizedBox.shrink()),
        ),
        GoRoute(
          path: '/sleep/session',
          builder: (context, state) => SleepSessionPage(now: now),
        ),
        // 真实的手动补录页，不是占位：时长越界说明层的出口按钮指向这里，
        // 用空 Scaffold 占位会把「出口是不是真的到了补录页」这条断言架空。
        GoRoute(
          path: '/log/new',
          builder: (context, state) => const LogNewPage(),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          activeSessionProvider.overrideWith((ref) => session),
          // 真的调度器在测试里没有平台通道，`initialize` 也从没跑过；换成空实现，
          // 免得测试依赖「它恰好会静默降级」这个实现细节。
          reminderSchedulerProvider
              .overrideWithValue(scheduler ?? NoopReminderScheduler()),
          // 真播放器会碰平台通道；白噪音的播放接缝挂在 app 级 provider 上。
          noisePlayerProvider.overrideWithValue(player ?? _FakeNoisePlayer()),
          // 真录音器会去开麦克风（平台通道）。不传就沿用默认实现——但**任何**碰到
          // 鼾声那一行副标题的用例都该传一个，否则测的是「还没对账过」的 idle。
          if (recorder != null)
            nightRecorderProvider.overrideWithValue(recorder),
        ],
        child: MaterialApp.router(
          theme: appTheme ?? AppTheme.dark(),
          // 与 `NightSleepApp` 同构：外层这一层系统栏样式挂在 `builder` 上，
          // 会话页自己那一层压在它上面。少了它，「页面覆写压过外层」这条根本测不到
          // （同 `test/system_bars_test.dart` 的说明）。
          builder: appSystemUiOverlayRegion,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 按**语义标签**取设定区里的开关，不靠它在树里的位置——
  /// 位置一变（多一行、换个顺序）就会指到另一个开关上，而且不报错。
  Finder toggleLabeled(String label) => find.byWidgetPredicate(
        (widget) => widget is IosToggle && widget.semanticLabel == label,
      );

  SleepSession sessionAt(
    DateTime start, {
    int wakeMinutes = 7 * 60,
    bool alarmEnabled = false,
  }) =>
      SleepSession(
        startAtUtc: start.toUtc(),
        timeZoneId: 'UTC',
        wakeMinutes: wakeMinutes,
        alarmEnabled: alarmEnabled,
        createdAtUtc: start.toUtc(),
      );

  /// 把当前弹层推到底。
  ///
  /// 守门生效时弹层是**说明层**，里面没有「跳过」，此调用是空操作；守门被删掉时
  /// 这里是**评星弹层**，点「跳过」会真的走完整条落库链路——正是这样，守门用例
  /// 里那些库断言才不是「因为流程还没走完所以当然为空」。
  Future<void> completeSheet(WidgetTester tester) async {
    final skip = find.text('跳过');
    if (skip.evaluate().isEmpty) return;
    await tester.tap(skip);
    await tester.pumpAndSettle();
  }

  /// 按住「结束睡眠」到外圈圆环填满。
  ///
  /// **这里显式推够 1.6 秒，而不是用 `tap`。** 结束按钮按下即开始计时，`tap` 的
  /// 按下—抬起间隔远不够填满圆环，走的是「没按满」那条路径。第一帧 `pump()` 也不能省
  /// ——`AnimationController` 的起点是在 ticker 的第一次 tick 上记的。
  Future<void> holdToFinish(WidgetTester tester) async {
    final gesture = await tester.press(find.byType(HoldToFinishButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1600));
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('显示当前时刻、已过时长与设定的起床时间', (tester) async {
    final start = DateTime(2026, 8, 30, 23, 14);
    await pumpSession(
      tester,
      // 闹钟开着：这一行只在闹钟开着（或已经睡过头）时渲染，标题才带得出时刻。
      session: sessionAt(start, alarmEnabled: true),
      now: start.add(const Duration(hours: 3, minutes: 42)),
    );

    expect(find.text('睡眠进行中'), findsOneWidget);
    // start 23:14、已过 3h42m → 现在是 02:56，秒表读 03:42:00。
    expect(find.text('02:56'), findsOneWidget);
    expect(find.text('03:42:00'), findsOneWidget);
    // 事件卡抬头写着这一晚是从几点开始的。
    expect(find.textContaining('23:14 开始'), findsOneWidget);
    // 闹钟那一行的标题带时刻。
    expect(find.text('07:00 起床闹钟'), findsOneWidget);
  });

  testWidgets('常暗的会话页自己那一层系统栏样式压过应用那一层', (tester) async {
    final start = DateTime(2026, 8, 30, 23, 14);
    // 外层给**浅色**主题：那样 `appSystemUiOverlayRegion` 算出的是「浅色页面配深色
    // 图标」。而这一页常暗，必须是浅色图标才看得见——所以量到的只能是页面自己那层。
    await pumpSession(
      tester,
      session: sessionAt(start),
      now: start.add(const Duration(hours: 3)),
      appTheme: AppTheme.light(),
    );

    expect(
      systemBarStyleAt(tester),
      appSystemUiOverlayStyle(Brightness.dark),
      reason: '状态栏取的是应用那一层——浅色主题配深色图标，压在满屏夜景上等于没有',
    );
    expect(
      systemBarStyleAt(tester, top: false),
      appSystemUiOverlayStyle(Brightness.dark),
      reason: '导航栏同上',
    );
    // 顺带钉住「不是 `SystemUiOverlayStyle.light` 那个预设」：预设的导航栏是
    // 不透明黑，换回去时上面这条会红，而状态栏那条看不出来。
    expect(
      systemBarStyleAt(tester, top: false)!.systemNavigationBarColor,
      Colors.transparent,
    );
  });

  testWidgets('超过起床时间后在闹钟行给出「已超过」与手动结束的指令', (tester) async {
    final start = DateTime(2026, 8, 30, 23, 14);
    await pumpSession(
      tester,
      session: sessionAt(start),
      now: start.add(const Duration(hours: 9)),
    );

    expect(find.textContaining('已超过起床时间'), findsOneWidget);
    // 睡过头那一刻睁眼看手机时最关键的半句是「怎么办」：只报「已超过」而不给
    // 动作指令，用户不知道该做什么。逐字钉住这半句，别让它随版式一起漂走。
    expect(find.textContaining('请手动结束睡眠'), findsOneWidget);
  });

  /// 闹钟关着时那一行**整个不渲染**（原型 `{alarmEnabled && …}`）：开关与时刻都在
  /// 入睡前那一屏定好了，这一屏不再回显一个「没设」的空洞。
  testWidgets('闹钟关着时没有起床闹钟行', (tester) async {
    final start = DateTime(2026, 8, 30, 23, 14);
    await pumpSession(
      tester,
      session: sessionAt(start),
      now: start.add(const Duration(hours: 1)),
    );

    expect(find.textContaining('起床闹钟'), findsNothing);
    expect(toggleLabeled('起床闹钟'), findsNothing, reason: '这一屏没有可取用的闹钟开关');
    expect(find.text('鼾声/梦话记录'), findsOneWidget, reason: '鼾声行与闹钟无关，照旧在');
  });

  testWidgets('闹钟开着时报剩余时间，并带上后台投递的如实标注', (tester) async {
    final start = DateTime(2026, 8, 30, 23, 14);
    await pumpSession(
      tester,
      session: sessionAt(start, alarmEnabled: true),
      now: start.add(const Duration(hours: 3, minutes: 42)),
    );

    // 计划时长 = 23:14 → 次日 07:00 = 7h46m；已过 3h42m，剩 4h4m。
    // （设计稿里 236 行写「3h 42m」、242 行写「还有 3h 18m」，两个数自相矛盾；
    // 以算出来的为准。）
    expect(find.text('将在设定时间轻柔唤醒 · 还有 4h 4m'), findsOneWidget);
    // 规格点名「这句话是功能的一部分」：逐字断言，不是「页面里大概有这么句」。
    expect(
      find.text('由系统通知投递；休眠模式下可能晚几分钟，强度不如系统闹钟。'),
      findsOneWidget,
    );
  });

  /// 睡过头那一刻的两句不能打架：闹钟行写「已超过起床时间」，就不能还写
  /// 「还有 0h 0m」。剩余/已过的口径回到模型里，事件卡只负责措辞。
  testWidgets('超过起床时间后闹钟行说「已过」，不再说「还有 0h 0m」', (tester) async {
    final start = DateTime(2026, 8, 30, 23, 14);
    await pumpSession(
      tester,
      session: sessionAt(start, alarmEnabled: true),
      now: start.add(const Duration(hours: 9)),
    );

    expect(find.textContaining('已超过起床时间'), findsOneWidget);
    expect(find.textContaining('还有 0h'), findsNothing,
        reason: '两句打架：先说已超过 42m，又说还有 0h 0m');
  });

  testWidgets('入睡与闹钟时刻都补零到两位', (tester) async {
    // 23:14 / 07:00 两个数本来都是两位数，`padLeft` 等于没被行使；这里换成
    // 一位数的小时与分钟，补零逻辑才真的被测到。
    final start = DateTime(2026, 8, 30, 9, 5);
    await pumpSession(
      tester,
      session: sessionAt(start, wakeMinutes: 6 * 60 + 5, alarmEnabled: true),
      now: start.add(const Duration(hours: 1)),
    );

    // 事件卡抬头的「09:05 开始」与闹钟行的标题「06:05 起床闹钟」各一处。
    expect(find.text('09:05 开始'), findsOneWidget);
    expect(find.text('06:05 起床闹钟'), findsOneWidget);
    expect(find.text('9:5'), findsNothing);
    expect(find.text('6:5'), findsNothing);
  });

  testWidgets('推入页自己提供 Material 祖先与背景', (tester) async {
    final start = DateTime(2026, 8, 30, 23, 14);
    await pumpSession(
      tester,
      session: sessionAt(start),
      now: start.add(const Duration(hours: 1)),
    );

    final heading = find.text('睡眠进行中');
    expect(
      DefaultTextStyle.of(tester.element(heading)).style.decoration,
      isNot(TextDecoration.underline),
      reason: '落到 Flutter 的无 Material 错误样式了（黄色双下划线）',
    );
    expect(find.byType(Material), findsWidgets);
  });

  /// 「收起」= 离开页面但**不结束会话**。这条只能在真实路由上验：`pop()` 的语义
  /// 就是「回到上一页」，裸渲染一个页面测不到它。
  ///
  /// 用的是 `NightSleepApp` 自己那个路由，所以顺带覆盖了 `lib/app/app.dart` 里
  /// 注册的 `path: 'sleep/session'`——在测试里另起一份路由达不到这个效果。
  testWidgets('点「收起」回到上一页，不结束会话也不写库', (tester) async {
    tester.view.physicalSize = const Size(430, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    disableAnimations(tester);

    final start = DateTime(2026, 8, 30, 23, 14);

    // 外壳与首页各自订阅了 drift 的 `watch*` 流；widget 测试的假时钟不推进，
    // 订阅它们会留下 pending timer（见 `.claude/skills/flutter-pitfalls`）。
    // 这里把这几条流全换成 provider override，真路由才跑得起来。
    await database
        .updateSettings(const AppSettingsCompanion(onboarded: Value(true)));
    final appSettings = await database.getSettings();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          settingsProvider.overrideWith((ref) => Stream.value(appSettings)),
          sleepEntriesProvider.overrideWith((ref) => const <SleepEntry>[]),
          activeSessionProvider.overrideWith((ref) => sessionAt(start)),
          reminderSchedulerProvider.overrideWithValue(NoopReminderScheduler()),
        ],
        child: const NightSleepApp(),
      ),
    );
    await tester.pumpAndSettle();

    // 会话页是**推入**的，这里也走推入。
    GoRouter.of(tester.element(find.byType(AppScaffold)))
        .push('/sleep/session');
    await tester.pumpAndSettle();

    expect(find.text('睡眠进行中'), findsOneWidget, reason: '推入后应停在会话页');

    await tester.tap(find.text('收起'));
    await tester.pumpAndSettle();

    // 首页在会话进行中也会显示「正在睡眠」卡（Task 8），所以不能再靠这两个字
    // 判断在不在会话页——改用只有会话页才有的「收起」，并确认回到了首页。
    expect(find.text('收起'), findsNothing, reason: '收起就是离开会话页');
    expect(find.text('睡眠概览'), findsOneWidget, reason: '收起应回到首页');
    expect(
      await SleepRepository(database).loadAll(),
      isEmpty,
      reason: '收起不是结束：不该写出一条睡眠记录',
    );
    expect(
      await database.activeSession(),
      isNull,
      reason: '会话行是夹具给的，收起不该往库里写任何东西',
    );
  });

  /// v3.3 起这一屏**只回显**：白噪音行只在真有声音在放时出现，闹钟行只在闹钟开着时
  /// 出现，两行都不再可点（睡前设定搬去了入睡前那一屏）。
  testWidgets('事件卡只回显：夜里没有白噪音行，也没有任何入口', (tester) async {
    final start = DateTime(2026, 8, 30, 23, 14);
    await pumpSession(
      tester,
      session: sessionAt(start, alarmEnabled: true),
      now: start.add(const Duration(hours: 1)),
    );

    expect(find.text('当前睡眠事件'), findsOneWidget);
    expect(find.text('开始睡眠'), findsOneWidget);
    expect(find.text('07:00 起床闹钟'), findsOneWidget);
    expect(find.text('已设置'), findsOneWidget, reason: '右侧只写状态，不再是开关');
    expect(find.text('鼾声/梦话记录'), findsOneWidget);
    // 从前这里钉的是「尚未接入录音，开关只保存偏好」。plan B 落地后那句话成了
    // 一句假话（偏差 #7 作废），所以反过来钉：它**必须不在**。
    expect(find.text('尚未接入录音，开关只保存偏好。'), findsNothing,
        reason: '录音已经接入了，留着这句话就是让应用撒谎');

    // 没在放音 → 没有白噪音行（原型 `{selectedNoise && …}`）。
    expect(find.text('白噪音'), findsNothing);
    expect(find.textContaining('未开启'), findsNothing);
    // 闹钟开着也只有状态字，没有可点的时刻胶囊、没有开关。
    expect(toggleLabeled('起床闹钟'), findsNothing);
    expect(find.text('白噪音设置'), findsNothing);
    expect(find.text('15m'), findsNothing);
  });

  testWidgets('鼾声那一行写的是录音的真实状态，不是一句占位说明', (tester) async {
    final start = DateTime(2026, 8, 30, 23, 14);
    await pumpSession(
      tester,
      session: sessionAt(start),
      now: start.add(const Duration(hours: 1)),
    );

    // 开关常驻，状态说明也必须跟着常驻——但它必须是**真的**。
    expect(find.textContaining('尚未接入录音'), findsNothing,
        reason: '偏差 #7 在 plan B 落地后作废，这句假话不许再出现');
    expect(find.textContaining('有声响的片段'), findsOneWidget,
        reason: '说清楚它录的是「有声响的片段」，不是「鼾声」——没有自动识别');
  });

  testWidgets('拨动鼾声开关会写回设置', (tester) async {
    final start = DateTime(2026, 8, 30, 23, 14);
    await pumpSession(
      tester,
      session: sessionAt(start),
      now: start.add(const Duration(hours: 1)),
    );

    // 按语义标签取，不数位置：常驻设定区有两个开关，顺序一变 `.last` 就指错了对象。
    await tester.tap(toggleLabeled('鼾声/梦话记录'));
    await tester.pumpAndSettle();

    final stored = await database.getSettings();
    expect(stored.soundRecordingEnabled, isTrue,
        reason: '会话页与设置页必须共用 AppSettings 里同一个字段');
  });

  testWidgets('闹钟开着时，投递强度标注就在那一行', (tester) async {
    final start = DateTime(2026, 8, 30, 23, 14);
    await pumpSession(
      tester,
      session: sessionAt(start, alarmEnabled: true),
      now: start.add(const Duration(hours: 1)),
    );

    // 标注跟着「起床闹钟」那一行常驻，**只有一处**——四行事件卡整块不折叠，
    // 任何时刻都不该出现第二份。
    expect(find.text(ReminderScheduler.wakeAlarmDeliveryNote), findsOneWidget);
  });

  /// 播放器挂在 app 级 provider 上，所以离开会话页也只是藏起面板。
  /// 播放器挂在 app 级 controller 上，所以离开会话页也只是藏起面板。
  ///
  /// 听音的入口现在只在**入睡前**那一屏（进行中那一屏照原型只回显），所以这里从外壳
  /// 上的一颗按钮打开弹窗：这条要证的本来就不是入口在哪，而是「控制器比页面长命」。
  testWidgets('pop 掉会话页后白噪音继续响', (tester) async {
    final player = _FakeNoisePlayer();
    final start = DateTime(2026, 8, 30, 23, 14);
    final navigator = GlobalKey<NavigatorState>();

    tester.view.physicalSize = const Size(430, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    disableAnimations(tester);

    await database.saveActiveSession(
      ActiveSessionsCompanion.insert(
        id: 'active',
        startAtUtc: start.toUtc(),
        wakeMinutes: 7 * 60,
        createdAt: start.toUtc(),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          activeSessionProvider.overrideWith((ref) => sessionAt(start)),
          reminderSchedulerProvider.overrideWithValue(NoopReminderScheduler()),
          noisePlayerProvider.overrideWithValue(player),
        ],
        child: MaterialApp(
          navigatorKey: navigator,
          theme: AppTheme.dark(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showNightNoiseSheet(context),
                  child: const Text('打开白噪音'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('打开白噪音'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('溪流'));
    // 选中即起 1 秒周期的倒计时，`pumpAndSettle` 会因它永不收敛而超时。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    player.calls.clear();

    await tester.tap(find.text('完成'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(player.calls, isNot(contains('stop')), reason: '关弹窗只是藏起面板，声音要继续响');

    // 再把会话页推上来又 pop 掉：页面进出都不该碰声音。
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) =>
            SleepSessionPage(now: start.add(const Duration(hours: 1))),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    navigator.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('睡眠进行中'), findsNothing, reason: '会话页已经离开');
    expect(player.calls, isNot(contains('stop')), reason: '收起的是页面，不是声音');
  });

  testWidgets('列出八种夜景氛围，选中的写回会话行', (tester) async {
    final start = DateTime(2026, 8, 30, 23, 14);
    // 场景选择器是**横向懒加载**列表：430 宽的视口里后几张卡还没被 build，
    // 「列出八种」这条断言就得给它一块够宽的视口。
    await pumpSession(
      tester,
      session: sessionAt(start),
      now: start.add(const Duration(hours: 1)),
      wide: true,
    );

    for (final label in ['流星夜', '极光', '深海', '月海', '云上', '萤火', '银河', '雨夜']) {
      expect(find.text(label), findsOneWidget, reason: '漏了「$label」');
    }

    await tester.tap(find.text('银河'));
    await tester.pumpAndSettle();

    final row = await database.activeSession();
    expect(row!.sceneId, 'galaxy', reason: '选了场景却没写回会话行');
  });

  testWidgets('收起过的场景在重进页面时还在', (tester) async {
    final start = DateTime(2026, 8, 30, 23, 14);
    await pumpSession(
      tester,
      session: sessionAt(start),
      now: start.add(const Duration(hours: 1)),
      wide: true,
    );
    await tester.tap(find.text('雨夜'));
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    // 再进一次：从**同一个库**读出会话，场景必须还是雨夜。
    await pumpSession(
      tester,
      session: (await SessionRepository(database).load())!,
      now: start.add(const Duration(hours: 1)),
      wide: true,
    );
    expect(find.byType(NightBackdrop), findsOneWidget);
    final badge = tester.widget<NightSceneChoice>(
      find.byWidgetPredicate((w) => w is NightSceneChoice && w.selected),
    );
    expect(badge.scene, NightScene.rain);
  });

  testWidgets('浅色主题下会话页仍然是深色', (tester) async {
    // 原型的睡眠模式是常暗的（setup 页写着「屏幕将保持暗色」）。这条钉住
    // 「页面自己套 dark Theme」这件事，防止有人顺手把它删掉。
    final start = DateTime(2026, 8, 30, 23, 14);
    tester.view.physicalSize = const Size(430, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    disableAnimations(tester);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          // 覆盖会话 provider：真的那条是 drift `watch` 流，widget 测试的假时钟
          // 不推进，订阅它会在拆树时留下 pending timer（见
          // `.claude/skills/flutter-pitfalls`）。这条用例验的是**主题**，不是数据源。
          activeSessionProvider.overrideWith((ref) => sessionAt(start)),
        ],
        child: MaterialApp(
          // 应用是**浅色**的。
          theme: AppTheme.light(),
          home: SleepSessionPage(now: start.add(const Duration(hours: 1))),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final context = tester.element(find.text('睡眠进行中'));
    expect(Theme.of(context).brightness, Brightness.dark);
  });

  testWidgets('结束睡眠先问一次星级', (tester) async {
    final start = DateTime(2026, 8, 30, 23, 14);
    await pumpSession(
      tester,
      session: sessionAt(start),
      now: start.add(const Duration(hours: 7, minutes: 48)),
    );

    await holdToFinish(tester);

    expect(find.text('昨晚睡得怎么样？'), findsOneWidget);
    expect(find.text('跳过'), findsOneWidget);
  });

  testWidgets('跳过评星：记录落库但质量为 null 且没有评分', (tester) async {
    final player = _FakeNoisePlayer();
    final start = DateTime(2026, 8, 30, 23, 14);
    await pumpSession(
      tester,
      session: sessionAt(start),
      now: start.add(const Duration(hours: 7, minutes: 48)),
      player: player,
    );

    // 先抓住容器：切走之后 `find.byType(SleepSessionPage)` 就找不到了。
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SleepSessionPage)),
    );

    await holdToFinish(tester);
    await tester.tap(find.text('跳过'));
    await tester.pumpAndSettle();

    final row = (await database.allRecords()).single;
    expect(row.quality, isNull);
    expect(row.source, 'session');
    expect(await database.activeSession(), isNull);
    // 会话结束了声音还在响说不通。
    expect(player.calls, contains('stop'), reason: '结束后必须停掉白噪音');
    // 收尾必须真的走完，而不是停在半路。
    expect(container.read(activeTabProvider), AppTab.log, reason: '应切到「回顾」');
    expect(find.byType(HoldToFinishButton), findsNothing, reason: '会话页应已离开');
  });

  testWidgets('评了分：质量写进记录', (tester) async {
    // `ensureSemantics` 必须在用例体内释放：绑定会在 tearDown 里检查。
    final semantics = tester.ensureSemantics();
    final start = DateTime(2026, 8, 30, 23, 14);
    await pumpSession(
      tester,
      session: sessionAt(start),
      now: start.add(const Duration(hours: 7, minutes: 48)),
    );

    await holdToFinish(tester);
    // 点第 5 颗星，**按语义标签点**。原先用 `find.byType(QualityStars)` 点的是
    // 组件包围盒的**中心**，落的是第 3 颗「一般」；而 `isNotNull` 分辨不出
    // 「用户点的那一档」与「任意一档」。
    await tester.tap(find.bySemanticsLabel('睡眠质量 极好'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(
      (await database.allRecords()).single.quality,
      SleepQuality.excellent.value,
      reason: '用户点的是「极好」，落库的就该是「极好」',
    );
    semantics.dispose();
  });

  /// 时长守门：点了开始就立刻结束，**不许**静默写出一条零时长记录。
  testWidgets('时长过短不落库，给出说明与两个出口', (tester) async {
    final start = DateTime(2026, 8, 30, 23, 14);
    await pumpSession(
      tester,
      session: sessionAt(start),
      now: start,
    );

    await holdToFinish(tester);

    // 守门最要紧的那条：**没有**走到评星——过了评星这一步就是落库。
    expect(find.text('昨晚睡得怎么样？'), findsNothing, reason: '时长越界时不该走到评星弹层');
    expect(find.textContaining('太短'), findsOneWidget);
    expect(find.text('手动补录某一晚'), findsOneWidget);
    expect(find.text('丢弃这次会话'), findsOneWidget);

    // 把弹层推到底再断言库。注意时长守门**有两道**（页面这道 +
    // `SessionRepository.finish` 里那道），所以「库里没有记录」只删页面这道是打不
    // 红的——真正打红的是上面那条「没走到评星」。这两条库断言守的是另一类回归：
    // 有人绕过 `finish()` 直接写库。
    await completeSheet(tester);

    expect(await database.allRecords(), isEmpty);
    expect(await database.activeSession(), isNotNull, reason: '会话仍在，等用户决定');
  });

  /// 时长越界说明层的出口真的通到手动补录页，而不是 go_router 的「Page Not
  /// Found」。这条走的是真实路由：夹具此前把 `/log/new` 注册成空 Scaffold，结构上
  /// 盖住了「路由没注册」——真机上点下去只会看到找不到页面的屏幕。
  testWidgets('时长越界的出口通往手动补录页', (tester) async {
    final start = DateTime(2026, 8, 30, 23, 14);
    await pumpSession(tester, session: sessionAt(start), now: start);

    await holdToFinish(tester);
    await tester.tap(find.text('手动补录某一晚'));
    await tester.pumpAndSettle();

    expect(find.text('手动补录'), findsOneWidget, reason: '应落在手动补录页的标题上');
    expect(find.text('Page Not Found'), findsNothing, reason: '路由必须真的注册过');
    expect(find.text('保存记录'), findsOneWidget, reason: '补录表单应已渲染');
    expect(find.text('睡眠进行中'), findsNothing, reason: '会话页应已离开');
  });

  testWidgets('时长超过 24 小时同样不落库', (tester) async {
    final start = DateTime(2026, 8, 30, 23, 14);
    await pumpSession(
      tester,
      session: sessionAt(start),
      now: start.add(const Duration(hours: 30)),
    );

    await holdToFinish(tester);

    expect(find.text('昨晚睡得怎么样？'), findsNothing, reason: '时长越界时不该走到评星弹层');
    expect(find.textContaining('超过 24 小时'), findsOneWidget);

    await completeSheet(tester);

    expect(await database.allRecords(), isEmpty);
    expect(await database.activeSession(), isNotNull, reason: '会话仍在，等用户决定');
  });

  /// 「尽力而为」必须是**事实**，不是注释里的一句话。
  ///
  /// 收尾的两步（停声音、撤闹钟）**同时**真抛——两者都走平台插件，都没有护栏。
  /// 记录已经落库，用户可见的收尾一条都不能少：把用户撂在一个没有会话、也没有
  /// 任何反馈的页面上，是这条路径最坏的失败形态。这条用例与夹具默认注入的
  /// `NoopReminderScheduler` 无关：它注入的就是两个会炸的实现。
  testWidgets('收尾失败不影响记录、反馈与跳转', (tester) async {
    final start = DateTime(2026, 8, 30, 23, 14);
    await pumpSession(
      tester,
      session: sessionAt(start),
      now: start.add(const Duration(hours: 7, minutes: 48)),
      player: _ThrowingNoisePlayer(),
      scheduler: _ThrowingReminderScheduler(),
    );

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SleepSessionPage)),
    );

    await holdToFinish(tester);
    await tester.tap(find.text('跳过'));
    await tester.pumpAndSettle();

    expect(await database.allRecords(), hasLength(1), reason: '记录必须落库');
    expect(container.read(activeTabProvider), AppTab.log,
        reason: '收尾失败也要切到「回顾」');
    expect(container.read(toastProvider), isNotNull, reason: '收尾失败也要给出反馈');
    expect(find.byType(HoldToFinishButton), findsNothing,
        reason: '收尾失败也要离开会话页');
  });

  testWidgets('丢弃这次会话：不写记录、会话消失、闹钟一并重排', (tester) async {
    final player = _FakeNoisePlayer();
    final scheduler = _RecordingReminderScheduler();
    final start = DateTime(2026, 8, 30, 23, 14);
    await pumpSession(
      tester,
      session: sessionAt(start),
      now: start,
      player: player,
      scheduler: scheduler,
    );

    await holdToFinish(tester);
    await tester.tap(find.text('丢弃这次会话'));
    await tester.pumpAndSettle();

    expect(await database.allRecords(), isEmpty);
    expect(await database.activeSession(), isNull);
    // 丢弃删的是同一行会话，而 9003 是设定区那个开关排的、那次调用同时让 9002
    // 让了位。不重排的话，一个已经不存在的会话会留着起床闹钟，日常起床提醒还
    // 继续被压着——正是 `reminder_sync.dart` 里那条规则要防的失败类。
    expect(scheduler.calls, contains('syncDaily'),
        reason: '日常提醒没有重新推导，9002 会继续被压着');
    expect(scheduler.calls, contains('syncAlarm:null'),
        reason: '会话没了，9003 该撤掉');
    // 会话没了，白噪音不该还在响。
    expect(player.calls, contains('stop'), reason: '丢弃后必须停掉白噪音');
    // UI 结果：说明层关掉、离开会话页（回到 `/`）。
    expect(find.text('丢弃这次会话'), findsNothing, reason: '说明层应已关闭');
    expect(find.byType(HoldToFinishButton), findsNothing, reason: '会话页应已离开');
  });

  /// 按住确认的闸门：环没填满就松手，什么都不该发生。
  testWidgets('没按满就松手不结束会话', (tester) async {
    final start = DateTime(2026, 8, 30, 23, 14);
    await pumpSession(
      tester,
      session: sessionAt(start),
      now: start.add(const Duration(hours: 7, minutes: 48)),
    );

    final gesture = await tester.press(find.byType(HoldToFinishButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('昨晚睡得怎么样？'), findsNothing, reason: '环没满却走到了评星，等于这道闸没起作用');
    expect(await database.allRecords(), isEmpty);
    expect(await database.activeSession(), isNotNull, reason: '会话仍在');
    expect(find.byType(HoldToFinishButton), findsOneWidget, reason: '会话页还在');
  });

  testWidgets('短按结束按钮只给提示，不结束', (tester) async {
    final start = DateTime(2026, 8, 30, 23, 14);
    await pumpSession(
      tester,
      session: sessionAt(start),
      now: start.add(const Duration(hours: 7, minutes: 48)),
    );

    await tester.tap(find.byType(HoldToFinishButton));
    await tester.pumpAndSettle();

    expect(await database.allRecords(), isEmpty);
    expect(find.text('昨晚睡得怎么样？'), findsNothing);
    // 测试树里没有 ToastOverlay（它活在外壳里），只能直接读 provider。
    expect(
      ProviderScope.containerOf(tester.element(find.byType(SleepSessionPage)))
          .read(toastProvider),
      contains('按住不放'),
      reason: '短按必须告诉用户正确的操作方式',
    );
  });

  /// 「录音中」那颗小灯。它只在 `recording` 这一态亮，所以断言它等于断言状态。
  ///
  /// 按颜色找而不是按下标找：那颗灯是唯一一个拿 `NightStyle.liveDot` 当底色的
  /// 容器，改成别的颜色就会红——那正是我们要盯住的那件事。
  Finder liveDot() => find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.decoration is BoxDecoration &&
            (widget.decoration! as BoxDecoration).color == NightStyle.liveDot,
      );

  /// 让录音控制器去对一次账。
  ///
  /// 会话页只在「按下开始睡眠」那一步叫它；已经在会话里的页面不会自己再叫一次
  /// （那是冷启动 `syncWithSession` 的事）。少了这一下，控制器读到的永远是 idle，
  /// 断言就落在了一个跟被测行为无关的分支上。
  Future<void> syncRecording(WidgetTester tester) async {
    await ProviderScope.containerOf(
            tester.element(find.byType(SleepSessionPage)))
        .read(nightRecordingControllerProvider.notifier)
        .syncWithSession();
    await tester.pumpAndSettle();
  }

  testWidgets('真在录的时候，那一行写「录音中」，灯亮着', (tester) async {
    final start = DateTime(2026, 8, 30, 23, 14);
    await database.updateSettings(
      const AppSettingsCompanion(soundRecordingEnabled: Value(true)),
    );
    await pumpSession(
      tester,
      session: sessionAt(start),
      now: start.add(const Duration(hours: 1)),
      recorder: _StatusRecorder(
        const NightRecordingStatus(NightRecordingState.recording),
      ),
    );
    await syncRecording(tester);

    expect(find.textContaining('录音中 · 还没录到有声响的片段'), findsOneWidget);
    expect(liveDot(), findsOneWidget, reason: '真在录，灯就该亮');
  });

  /// 实测（MI 9 / Android 11）：应用一离开前台，平台就静音录音端口并**持续交付零
  /// 样本**，而 `record` 插件不报任何中断。没有这一段，界面会整夜写着「录音中」，
  /// 用户第二天才发现什么都没录到，还分不清是自己一夜没出声还是根本没在录。
  /// 见 `docs/verification-log.md` v3.19 与 `test/night_recorder_test.dart` 的
  /// 「平台静音」一组。
  testWidgets('平台把麦克风静音时如实说出来，并且那盏灯不许亮', (tester) async {
    final start = DateTime(2026, 8, 30, 23, 14);
    await database.updateSettings(
      const AppSettingsCompanion(soundRecordingEnabled: Value(true)),
    );
    await pumpSession(
      tester,
      session: sessionAt(start),
      now: start.add(const Duration(hours: 1)),
      recorder: _StatusRecorder(
        const NightRecordingStatus(
          NightRecordingState.silenced,
          reason: kSilencedMicReason,
        ),
      ),
    );
    await syncRecording(tester);

    expect(find.textContaining('麦克风被系统静音'), findsOneWidget);
    expect(find.textContaining('录音中'), findsNothing,
        reason: '这一夜它确实没有在录，说「录音中」是假话');
    expect(liveDot(), findsNothing,
        reason: '一盏写着「正在聆听」却什么都没在听的灯，正是偏差 #31 当初要挡的东西');
  });
}
