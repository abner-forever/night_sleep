import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/app/app.dart';
import 'package:night_sleep/core/database/app_database.dart';
import 'package:night_sleep/features/onboarding/presentation/onboarding_overlay.dart';
import 'package:night_sleep/features/onboarding/presentation/splash_screen.dart';
import 'package:night_sleep/features/sleep/data/session_repository.dart';
import 'package:night_sleep/features/sleep/data/sleep_repository.dart';

/// 开屏页（`/` 外壳最上层的那一屏）。
///
/// 时间轴是**有限时长的一条 `AnimationController`**，所以这些用例可以用
/// `pump(时长)` 精确推进，而不必依赖 `pumpAndSettle`。这一点是有意的：
/// 原型的星点闪烁 / 光晕脉动 / 轨道环自转都是 `infinite`，照抄会让
/// `pumpAndSettle()` 永不收敛（`sleep_moon_mark.dart` 的 `_sync()` 注释记的
/// 就是同一个坑）。
void main() {
  late AppDatabase database;

  setUp(() => database = AppDatabase(NativeDatabase.memory()));
  tearDown(() => database.close());

  AppSetting settings({bool onboarded = true}) => AppSetting(
        id: 'default',
        themeMode: 'system',
        sleepGoalMinutes: 480,
        bedtimeReminderEnabled: false,
        bedtimeReminderMinutes: null,
        wakeReminderEnabled: false,
        wakeReminderMinutes: null,
        soundRecordingEnabled: false,
        onboarded: onboarded,
        insightProvider: null,
        insightModel: null,
      );

  /// 单独挂一屏开屏页。它自己返回 `Positioned.fill`，所以外面必须是 `Stack`。
  Future<void> pumpSplash(
    WidgetTester tester, {
    required VoidCallback onFinished,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(children: [SplashScreen(onFinished: onFinished)]),
        ),
      ),
    );
    // **`pumpWidget` 那一帧只是把 ticker 排上**：`AnimationController` 的起点是
    // ticker **第一次 tick** 的时刻，也就是下一帧。少了这一下，接着的
    // `pump(duration)` 会把起点定在那一帧上，动画其实一步都没走。
    await tester.pump();
  }

  /// 播完整条时间轴（多给一点余量，免得恰好在终点上差一个浮点位）。
  Future<void> settleSplash(WidgetTester tester) async {
    await tester.pump(SplashScreen.duration + const Duration(milliseconds: 50));
    // 状态监听里的 `setState` 要下一帧才重建。
    await tester.pump();
  }

  /// 挂真外壳，设置由 [stream] 供给。
  Future<void> pumpApp(
    WidgetTester tester,
    Stream<AppSetting> stream,
  ) async {
    tester.view.physicalSize = const Size(430, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          sleepEntriesProvider.overrideWith((ref) => const []),
          settingsProvider.overrideWith((ref) => stream),
          activeSessionProvider.overrideWith((ref) => null),
        ],
        child: const NightSleepApp(),
      ),
    );
    // 同上：起表 + 让设置流的第一帧落地。
    await tester.pump();
  }

  testWidgets('画的是品牌文案，播完回调一次且只有一次', (tester) async {
    var finished = 0;
    await pumpSplash(tester, onFinished: () => finished++);

    expect(find.text('夜深'), findsOneWidget);
    expect(find.text('听见夜晚，看见睡眠'), findsOneWidget);
    expect(finished, 0, reason: '还没播完就先回调了');

    await settleSplash(tester);
    expect(finished, 1);

    // 再等一会儿：状态监听不许反复触发。
    await tester.pump(const Duration(seconds: 2));
    expect(finished, 1, reason: '播完的回调被触发了不止一次');
  });

  testWidgets('开启「减弱动态效果」时立即播完，不会把应用卡在开屏', (tester) async {
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(
      tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
    );

    var finished = 0;
    await pumpSplash(tester, onFinished: () => finished++);
    // 框架不会把时长真的归零，而是压到原先的 5%（这里 1.6s → 80ms）。
    await tester.pump(const Duration(milliseconds: 120));

    expect(finished, 1, reason: '减弱动态效果下开屏没有尽快播完');
    expect(tester.binding.hasScheduledFrame, isFalse,
        reason: '减弱动态效果下还有排帧，说明时间轴没停表');
  });

  testWidgets('开屏排在引导页之前，播完才轮到引导页', (tester) async {
    await pumpApp(tester, Stream.value(settings(onboarded: false)));

    expect(find.byType(SplashScreen), findsOneWidget);
    expect(
      find.byType(OnboardingOverlay),
      findsNothing,
      reason: '引导页压在开屏上就等于开屏根本没播——原型里两者 z-index 相同、'
          '引导页在 DOM 里更靠后，首次启动正是这个结果',
    );

    await settleSplash(tester);

    expect(find.byType(SplashScreen), findsNothing);
    expect(find.byType(OnboardingOverlay), findsOneWidget);
  });

  testWidgets('设置还没读到第一帧时，开屏不会先收起', (tester) async {
    // 只看计时器的话，外壳会先露出来、引导页随后再盖上去——用户看到的是
    // 「闪一下主界面再跳出引导」。所以收起条件还要求设置已经有结论。
    final stream = StreamController<AppSetting>.broadcast();
    addTearDown(stream.close);

    await pumpApp(tester, stream.stream);
    await settleSplash(tester);

    expect(
      find.byType(SplashScreen),
      findsOneWidget,
      reason: '设置还没读到就先把开屏收了',
    );

    stream.add(settings(onboarded: true));
    await tester.pump();
    await tester.pump();

    expect(find.byType(SplashScreen), findsNothing);
  });

  testWidgets('已引导过的用户：开屏之后直接进外壳，没有引导页', (tester) async {
    await pumpApp(tester, Stream.value(settings(onboarded: true)));
    await settleSplash(tester);

    expect(find.byType(SplashScreen), findsNothing);
    expect(find.byType(OnboardingOverlay), findsNothing);
  });
}
