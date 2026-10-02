import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:night_sleep/app/app.dart';
import 'package:night_sleep/app/app_shell.dart';
import 'package:night_sleep/app/app_toast.dart';
import 'package:night_sleep/app/noise_session.dart';
import 'package:night_sleep/core/database/app_database.dart';
import 'package:night_sleep/core/platform/reminders.dart';
import 'package:night_sleep/core/theme/app_theme.dart';
import 'package:night_sleep/core/widgets/ios_controls.dart';
import 'package:night_sleep/features/log/presentation/log_new_page.dart';
import 'package:night_sleep/features/session/presentation/sleep_session_page.dart';
import 'package:night_sleep/features/sleep/data/noise_player.dart';
import 'package:night_sleep/features/sleep/data/noise_synth.dart';
import 'package:night_sleep/features/sleep/data/session_repository.dart';
import 'package:night_sleep/features/sleep/data/sleep_repository.dart';
import 'package:night_sleep/features/sleep/domain/sleep_entry.dart';
import 'package:night_sleep/features/sleep/domain/sleep_quality.dart';
import 'package:night_sleep/features/sleep/domain/sleep_session.dart';

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

void main() {
  late AppDatabase database;

  setUp(() => database = AppDatabase(NativeDatabase.memory()));
  tearDown(() => database.close());

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
    NoisePlayer? player,
    ReminderScheduler? scheduler,
  }) async {
    tester.view.physicalSize =
        wide ? const Size(1200, 2000) : const Size(430, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

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
        ],
        child: MaterialApp.router(
          theme: AppTheme.dark(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 按**语义标签**取抽屉里的开关，不靠它在树里的位置——
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

  testWidgets('显示已睡时长与设定的起床时间', (tester) async {
    final start = DateTime(2026, 8, 30, 23, 14);
    await pumpSession(
      tester,
      session: sessionAt(start),
      now: start.add(const Duration(hours: 3, minutes: 42)),
    );

    expect(find.text('正在睡眠'), findsOneWidget);
    // 中心读数的文案是确定的，所以断言精确的整串——`textContaining('3')`
    // 这条页面上到处都能满足，等于没测。
    expect(find.text('3h 42m'), findsOneWidget);
    // 「定了几点起」必须在收合态就看得见。
    expect(find.text('23:14'), findsOneWidget);
    expect(find.text('07:00'), findsOneWidget);
  });

  testWidgets('超过起床时间后给出「已超过」而不是让弧溢出', (tester) async {
    final start = DateTime(2026, 8, 30, 23, 14);
    await pumpSession(
      tester,
      session: sessionAt(start),
      now: start.add(const Duration(hours: 9)),
    );

    expect(find.textContaining('已超过起床时间'), findsOneWidget);
  });

  testWidgets('闹钟关着时胶囊说自然醒后手动结束', (tester) async {
    final start = DateTime(2026, 8, 30, 23, 14);
    await pumpSession(
      tester,
      session: sessionAt(start),
      now: start.add(const Duration(hours: 1)),
    );

    expect(find.textContaining('自然醒后手动结束'), findsOneWidget);
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
    expect(find.text('起床闹钟已开 · 还有 4h 4m'), findsOneWidget);
    // 规格点名「这句话是功能的一部分」：逐字断言，不是「页面里大概有这么句」。
    expect(
      find.text('由系统通知投递；休眠模式下可能晚几分钟，强度不如系统闹钟。'),
      findsOneWidget,
    );
  });

  /// 睡过头那一刻的两句不能打架：上方日晷写「已超过起床时间」，下方胶囊就不能
  /// 还写「还有 0h 0m」。剩余/已过的口径回到模型里，胶囊只负责措辞。
  testWidgets('超过起床时间后闹钟胶囊说「已过」，不再说「还有 0h 0m」', (tester) async {
    final start = DateTime(2026, 8, 30, 23, 14);
    await pumpSession(
      tester,
      session: sessionAt(start, alarmEnabled: true),
      now: start.add(const Duration(hours: 9)),
    );

    expect(find.textContaining('已超过起床时间'), findsOneWidget,
        reason: '前提：日晷确实写着已超过');
    expect(find.text('起床闹钟已过 · 请手动结束睡眠'), findsOneWidget);
    expect(find.textContaining('还有 0h'), findsNothing,
        reason: '两句打架：上方说已超过 42m，下方说还有 0h 0m');
    expect(find.textContaining('起床闹钟已开'), findsNothing);
  });

  testWidgets('入睡与闹钟时刻都补零到两位', (tester) async {
    // 23:14 / 07:00 两个数本来都是两位数，`padLeft` 等于没被行使；这里换成
    // 一位数的小时与分钟，补零逻辑才真的被测到。
    final start = DateTime(2026, 8, 30, 9, 5);
    await pumpSession(
      tester,
      session: sessionAt(start, wakeMinutes: 6 * 60 + 5),
      now: start.add(const Duration(hours: 1)),
    );

    expect(find.text('09:05'), findsOneWidget);
    expect(find.text('06:05'), findsOneWidget);
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

    final heading = find.text('正在睡眠');
    expect(
      DefaultTextStyle.of(tester.element(heading)).style.decoration,
      isNot(TextDecoration.underline),
      reason: '落到 Flutter 的无 Material 错误样式了（黄色双下划线）',
    );
    expect(find.byType(Material), findsWidgets);
  });

  testWidgets('没有会话时不崩，显示空状态并可返回', (tester) async {
    tester.view.physicalSize = const Size(430, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          activeSessionProvider.overrideWith((ref) => null),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: SleepSessionPage(now: DateTime(2026, 8, 30, 23, 14)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('没有正在进行的睡眠'), findsOneWidget);
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

    expect(find.text('正在睡眠'), findsOneWidget, reason: '推入后应停在会话页');

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

  testWidgets('点摘要条展开抽屉，四组设定都在', (tester) async {
    final start = DateTime(2026, 8, 30, 23, 14);
    await pumpSession(
      tester,
      session: sessionAt(start),
      now: start.add(const Duration(hours: 1)),
    );

    expect(find.text('今晚的设定'), findsNothing, reason: '收合态不该看到抽屉内容');

    await tester.tap(find.textContaining('白噪音'));
    await tester.pumpAndSettle();

    expect(find.text('今晚的设定'), findsOneWidget);
    expect(find.text('起床闹钟'), findsOneWidget);
    expect(find.text('鼾声/梦话记录'), findsOneWidget);
    expect(find.text('白噪音'), findsOneWidget);
  });

  testWidgets('抽屉里的白噪音定时最长 60 分钟，没有「不限」与 90m', (tester) async {
    final start = DateTime(2026, 8, 30, 23, 14);
    await pumpSession(
      tester,
      session: sessionAt(start),
      now: start.add(const Duration(hours: 1)),
    );
    await tester.tap(find.textContaining('白噪音'));
    await tester.pumpAndSettle();

    expect(find.text('15m'), findsOneWidget);
    expect(find.text('30m'), findsOneWidget);
    expect(find.text('45m'), findsOneWidget);
    expect(find.text('60m'), findsOneWidget);
    expect(find.text('不限'), findsNothing, reason: '会话里的白噪音必须有上限');
    expect(find.text('90m'), findsNothing);
  });

  testWidgets('鼾声/梦话开关带上「尚未接入录音」的说明（plan A）', (tester) async {
    final start = DateTime(2026, 8, 30, 23, 14);
    await pumpSession(
      tester,
      session: sessionAt(start),
      now: start.add(const Duration(hours: 1)),
    );
    await tester.tap(find.textContaining('白噪音'));
    await tester.pumpAndSettle();

    expect(find.textContaining('尚未接入录音'), findsOneWidget);
  });

  /// 这一条与上一条**互斥**：plan B 落地录音时必须把上一条删掉、这一条补上。
  /// 两轮之间不存在一个两边都写的中间状态。
  testWidgets('白噪音区注明后台播放未接入', (tester) async {
    final start = DateTime(2026, 8, 30, 23, 14);
    await pumpSession(
      tester,
      session: sessionAt(start),
      now: start.add(const Duration(hours: 1)),
    );
    await tester.tap(find.textContaining('白噪音'));
    await tester.pumpAndSettle();

    expect(find.textContaining('退到后台或锁屏后声音会停'), findsOneWidget);
  });

  testWidgets('拨动鼾声开关会写回设置', (tester) async {
    final start = DateTime(2026, 8, 30, 23, 14);
    await pumpSession(
      tester,
      session: sessionAt(start),
      now: start.add(const Duration(hours: 1)),
    );
    await tester.tap(find.textContaining('白噪音'));
    await tester.pumpAndSettle();

    // 按语义标签取，不数位置：抽屉里有两个开关，顺序一变 `.last` 就指错了对象。
    await tester.tap(toggleLabeled('鼾声/梦话记录'));
    await tester.pumpAndSettle();

    final stored = await database.getSettings();
    expect(stored.soundRecordingEnabled, isTrue,
        reason: '会话页与设置页必须共用 AppSettings 里同一个字段');
  });

  testWidgets('抽屉里闹钟开着时，投递强度标注就在那一行', (tester) async {
    final start = DateTime(2026, 8, 30, 23, 14);
    await pumpSession(
      tester,
      session: sessionAt(start, alarmEnabled: true),
      now: start.add(const Duration(hours: 1)),
    );
    await tester.tap(find.textContaining('白噪音'));
    await tester.pumpAndSettle();

    // 收合态由胶囊承担这条标注；展开后胶囊让位，标注必须改由抽屉里的闹钟行承担
    // ——用户正是在那一行打开闹钟，标注不能恰好在那一刻消失。
    expect(find.text(ReminderScheduler.wakeAlarmDeliveryNote), findsOneWidget);
  });

  testWidgets('闹钟开关被拒时回弹，且不写入会话的 alarmEnabled', (tester) async {
    final start = DateTime(2026, 8, 30, 23, 14);
    // 会话行真的落库，才看得见「有没有写进去」。
    await database.saveActiveSession(
      ActiveSessionsCompanion.insert(
        id: 'active',
        startAtUtc: start.toUtc(),
        wakeMinutes: 7 * 60,
        createdAt: start.toUtc(),
      ),
    );
    await pumpSession(
      tester,
      session: sessionAt(start),
      now: start.add(const Duration(hours: 1)),
    );
    await tester.tap(find.textContaining('白噪音'));
    await tester.pumpAndSettle();

    // NoopReminderScheduler.requestPermission() 返回 unsupported——这正是「平台
    // 安排不了」那条分支，与设置页走的是同一个闸口。
    await tester.tap(toggleLabeled('起床闹钟'));
    await tester.pumpAndSettle();

    expect(
      (await database.activeSession())?.alarmEnabled ?? true,
      isFalse,
      reason: '被拒时不得写入一个开着却不会响的开关',
    );
    // 测试树里没有 ToastOverlay（它活在外壳里），只能直接读 provider。
    expect(
      ProviderScope.containerOf(tester.element(find.byType(SleepSessionPage)))
          .read(toastProvider),
      contains('闹钟未开启'),
      reason: '被拒必须给出说明，不能静默弹回',
    );
  });

  testWidgets('选中白噪音会交给播放器，再点一次停掉', (tester) async {
    final player = _FakeNoisePlayer();
    final start = DateTime(2026, 8, 30, 23, 14);
    await pumpSession(
      tester,
      session: sessionAt(start),
      now: start.add(const Duration(hours: 1)),
      player: player,
    );
    await tester.tap(find.textContaining('白噪音'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('雨声'));
    // 选中即起 1 秒周期的倒计时，`pumpAndSettle` 会因它永不收敛而超时，
    // 所以这里显式 pump（与 `test/noise_sheet_test.dart` 同一手法）。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(player.calls.first, 'play:rain:0.50', reason: '应把雨声与当前音量交给播放器');

    await tester.tap(find.text('雨声'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(player.calls, contains('stop'), reason: '再点一次就是取消选择');
  });

  testWidgets('白噪音倒计时到点会停掉，并清空会话里的选中值', (tester) async {
    final player = _FakeNoisePlayer();
    final start = DateTime(2026, 8, 30, 23, 14);
    await database.saveActiveSession(
      ActiveSessionsCompanion.insert(
        id: 'active',
        startAtUtc: start.toUtc(),
        wakeMinutes: 7 * 60,
        createdAt: start.toUtc(),
      ),
    );
    await pumpSession(
      tester,
      session: sessionAt(start),
      now: start.add(const Duration(hours: 1)),
      player: player,
    );
    await tester.tap(find.textContaining('白噪音'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('雨声'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect((await database.activeSession())?.noiseId, 'rain',
        reason: '这一列的定义是「选中并正在播放」');

    // 默认定时 30 分钟；把假时钟推过它就是「到点」。
    await tester.pump(const Duration(minutes: 30));
    await tester.pump(const Duration(milliseconds: 50));

    expect(player.calls, contains('stop'));
    expect((await database.activeSession())?.noiseId, isNull,
        reason: '到点之后不能留下一个「在播」的假值');
  });

  testWidgets('收起抽屉不会停掉正在播放的白噪音', (tester) async {
    final player = _FakeNoisePlayer();
    final start = DateTime(2026, 8, 30, 23, 14);
    await database.saveActiveSession(
      ActiveSessionsCompanion.insert(
        id: 'active',
        startAtUtc: start.toUtc(),
        wakeMinutes: 7 * 60,
        createdAt: start.toUtc(),
      ),
    );
    await pumpSession(
      tester,
      session: sessionAt(start),
      now: start.add(const Duration(hours: 1)),
      player: player,
    );

    await tester.tap(find.textContaining('白噪音'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('雨声'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    player.calls.clear();

    // 再点摘要条收起。用带「音量」的那条文案定位——展开时「白噪音」三个字同时
    // 出现在摘要条和八宫格的那一格上，`textContaining('白噪音')` 会数到两个。
    await tester.tap(find.textContaining('白噪音 · 音量'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(player.calls, isNot(contains('stop')),
        reason: '收起抽屉只是藏起面板，声音要继续响（使用方裁定）');
    expect(
      (await database.activeSession())?.noiseId,
      'rain',
      reason: '库里写着「在播」而实际没声，正是这次要消掉的假值',
    );
  });

  /// 播放器挂在 app 级 provider 上，所以离开会话页也只是藏起面板。
  testWidgets('pop 掉会话页后白噪音继续响', (tester) async {
    final player = _FakeNoisePlayer();
    final start = DateTime(2026, 8, 30, 23, 14);
    final navigator = GlobalKey<NavigatorState>();

    tester.view.physicalSize = const Size(430, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

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
          // 会话页是**推入**的：外壳留在下面，pop 只是回到它。
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      ),
    );
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) =>
            SleepSessionPage(now: start.add(const Duration(hours: 1))),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('白噪音'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('雨声'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    player.calls.clear();

    navigator.currentState!.pop();
    // 倒计时在跑，不能用 `pumpAndSettle`；显式推两帧让路由转场走完。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('雨声'), findsNothing, reason: '会话页已经离开');
    expect(player.calls, isNot(contains('stop')), reason: '收起的是页面，不是声音');
  });

  testWidgets('结束睡眠先问一次星级', (tester) async {
    final start = DateTime(2026, 8, 30, 23, 14);
    await pumpSession(
      tester,
      session: sessionAt(start),
      now: start.add(const Duration(hours: 7, minutes: 48)),
    );

    await tester.tap(find.text('结束睡眠'));
    await tester.pumpAndSettle();

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

    await tester.tap(find.text('结束睡眠'));
    await tester.pumpAndSettle();
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
    expect(find.text('结束睡眠'), findsNothing, reason: '会话页应已离开');
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

    await tester.tap(find.text('结束睡眠'));
    await tester.pumpAndSettle();
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

    await tester.tap(find.text('结束睡眠'));
    await tester.pumpAndSettle();

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

    await tester.tap(find.text('结束睡眠'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('手动补录某一晚'));
    await tester.pumpAndSettle();

    expect(find.text('手动补录'), findsOneWidget, reason: '应落在手动补录页的标题上');
    expect(find.text('Page Not Found'), findsNothing, reason: '路由必须真的注册过');
    expect(find.text('保存记录'), findsOneWidget, reason: '补录表单应已渲染');
    expect(find.text('正在睡眠'), findsNothing, reason: '会话页应已离开');
  });

  testWidgets('时长超过 24 小时同样不落库', (tester) async {
    final start = DateTime(2026, 8, 30, 23, 14);
    await pumpSession(
      tester,
      session: sessionAt(start),
      now: start.add(const Duration(hours: 30)),
    );

    await tester.tap(find.text('结束睡眠'));
    await tester.pumpAndSettle();

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

    await tester.tap(find.text('结束睡眠'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('跳过'));
    await tester.pumpAndSettle();

    expect(await database.allRecords(), hasLength(1), reason: '记录必须落库');
    expect(container.read(activeTabProvider), AppTab.log,
        reason: '收尾失败也要切到「回顾」');
    expect(container.read(toastProvider), isNotNull, reason: '收尾失败也要给出反馈');
    expect(find.text('结束睡眠'), findsNothing, reason: '收尾失败也要离开会话页');
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

    await tester.tap(find.text('结束睡眠'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('丢弃这次会话'));
    await tester.pumpAndSettle();

    expect(await database.allRecords(), isEmpty);
    expect(await database.activeSession(), isNull);
    // 丢弃删的是同一行会话，而 9003 是抽屉里那个开关排的、那次调用同时让 9002
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
    expect(find.text('结束睡眠'), findsNothing, reason: '会话页应已离开');
  });
}
