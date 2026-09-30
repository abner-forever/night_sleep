import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:night_sleep/app/app.dart';
import 'package:night_sleep/app/app_toast.dart';
import 'package:night_sleep/app/noise_session.dart';
import 'package:night_sleep/core/database/app_database.dart';
import 'package:night_sleep/core/platform/reminders.dart';
import 'package:night_sleep/core/theme/app_theme.dart';
import 'package:night_sleep/core/widgets/ios_controls.dart';
import 'package:night_sleep/features/session/presentation/sleep_session_page.dart';
import 'package:night_sleep/features/sleep/data/noise_player.dart';
import 'package:night_sleep/features/sleep/data/noise_synth.dart';
import 'package:night_sleep/features/sleep/data/session_repository.dart';
import 'package:night_sleep/features/sleep/data/sleep_repository.dart';
import 'package:night_sleep/features/sleep/domain/sleep_entry.dart';
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
  }) async {
    tester.view.physicalSize =
        wide ? const Size(1200, 2000) : const Size(430, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          activeSessionProvider.overrideWith((ref) => session),
          // 真的调度器在测试里没有平台通道，`initialize` 也从没跑过；换成空实现，
          // 免得测试依赖「它恰好会静默降级」这个实现细节。
          reminderSchedulerProvider.overrideWithValue(NoopReminderScheduler()),
          // 真播放器会碰平台通道；白噪音的播放接缝挂在 app 级 provider 上。
          noisePlayerProvider.overrideWithValue(player ?? _FakeNoisePlayer()),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: SleepSessionPage(now: now),
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

    expect(find.text('正在睡眠'), findsNothing, reason: '收起就是离开会话页');
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
}
