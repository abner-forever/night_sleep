import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/app/app.dart';
import 'package:night_sleep/core/database/app_database.dart';
import 'package:night_sleep/core/platform/system_bars.dart';
import 'package:night_sleep/core/theme/app_theme.dart';
import 'package:night_sleep/features/sleep/data/session_repository.dart';
import 'package:night_sleep/features/sleep/data/sleep_repository.dart';

import 'system_bar_probe.dart';

/// Android 上「顶部一条灰带、底部一条黑带把页面截断」有两个**独立**来源，两个
/// 都不是渲染问题，而是**声明出去的样式不对**，所以这里钉的是声明出来的字段：
///
///  1. 系统在**透明**状态栏背后自动加的对比度蒙层（Android 10+ 的
///     `enforceStatusBarContrast`）。真机上量到的状态栏那一条是 `(181,181,186)`，
///     而紧挨着它的页面像素是 `(240,242,248)`——比值约 0.75，即蒙层约 25% 黑。
///  2. `SystemUiOverlayStyle.light` / `.dark` 这两个预设把 `systemNavigationBarColor`
///     写死成不透明黑，导航栏于是重新变回一条黑带。
///
/// 第二条特别容易被「顺手用预设」改回去——`AnnotatedRegion<SystemUiOverlayStyle>`
/// 写起来太顺手了，而预设长得就像为此准备的。
///
/// **本文件里最后那组「真实应用」用例不是重复**：前面几组各自搭一个 `MaterialApp`
/// 来测函数本身，它们对「`app.dart` 有没有真的挂上去」一无所知——把
/// `builder: appSystemUiOverlayRegion` 整行删掉，前面几组照样全绿。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;

  setUp(() => database = AppDatabase(NativeDatabase.memory()));
  tearDown(() => database.close());

  group('appSystemUiOverlayStyle', () {
    test('浅色主题：两条栏透明、图标深色、系统蒙层关掉', () {
      final style = appSystemUiOverlayStyle(Brightness.light);

      expect(style.statusBarColor, Colors.transparent);
      expect(style.systemNavigationBarColor, Colors.transparent);
      expect(style.systemNavigationBarDividerColor, Colors.transparent);
      expect(style.statusBarIconBrightness, Brightness.dark);
      expect(style.systemNavigationBarIconBrightness, Brightness.dark);
      expect(style.systemStatusBarContrastEnforced, isFalse);
      expect(style.systemNavigationBarContrastEnforced, isFalse);
    });

    test('深色主题：图标翻成浅色，两条栏仍然透明', () {
      final style = appSystemUiOverlayStyle(Brightness.dark);

      expect(style.statusBarColor, Colors.transparent);
      expect(style.systemNavigationBarColor, Colors.transparent);
      expect(style.statusBarIconBrightness, Brightness.light);
      expect(style.systemNavigationBarIconBrightness, Brightness.light);
      expect(style.systemStatusBarContrastEnforced, isFalse);
      expect(style.systemNavigationBarContrastEnforced, isFalse);
    });

    test('两个预设都带着不透明黑导航栏——这正是不能直接用它们的原因', () {
      // 这条不是测我们的代码，是**把上游那个坑钉在这儿**：哪天 Flutter 把这两个
      // 预设改好了，这条会红，提醒去重读一遍「为什么不用预设」那段注释。
      // 它**不会**在有人把 `appSystemUiOverlayStyle` 换成预设时变红——那种时候红的是
      // 上面两条字段断言。
      expect(
        SystemUiOverlayStyle.dark.systemNavigationBarColor,
        const Color(0xFF000000),
      );
      expect(
        SystemUiOverlayStyle.light.systemNavigationBarColor,
        const Color(0xFF000000),
      );
    });
  });

  group('appSystemUiOverlayRegion', () {
    /// 与 `NightSleepApp` 同构：`theme` / `darkTheme` / `themeMode` 三件套，
    /// `builder` 挂的是同一个函数。断言的是 `AnnotatedRegion` 真正拿到的值——
    /// `builder` 的 context 到底在不在 `Theme` 之内、`Theme.of` 拿到的又是哪一种
    /// 明暗，只有真渲一遍才算数。
    Future<SystemUiOverlayStyle> overlayStyle(
      WidgetTester tester, {
      required ThemeMode mode,
      Brightness platform = Brightness.light,
    }) async {
      tester.platformDispatcher.platformBrightnessTestValue = platform;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: mode,
          builder: appSystemUiOverlayRegion,
          home: const Scaffold(body: SizedBox.expand()),
        ),
      );

      return tester
          .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
            find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
          )
          .value;
    }

    testWidgets('浅色主题 → 深色图标', (tester) async {
      expect(
        await overlayStyle(tester, mode: ThemeMode.light),
        appSystemUiOverlayStyle(Brightness.light),
      );
    });

    testWidgets('深色主题 → 浅色图标', (tester) async {
      expect(
        await overlayStyle(tester, mode: ThemeMode.dark),
        appSystemUiOverlayStyle(Brightness.dark),
      );
    });

    testWidgets('跟的是应用主题，不是系统：系统深色 + 应用锁浅色 → 仍是深色图标', (tester) async {
      // 应用内可以单独切浅色 / 深色，系统却可能停在另一边。跟随系统的话，
      // 浅色的页面上会压出一排看不见的白字。
      expect(
        await overlayStyle(
          tester,
          mode: ThemeMode.light,
          platform: Brightness.dark,
        ),
        appSystemUiOverlayStyle(Brightness.light),
      );
    });
  });

  group('真实应用：这一层真的挂上了', () {
    /// 起真的 `NightSleepApp`（与 `pages_widget_test.pumpRealApp` 同款覆盖）。
    Future<void> pumpRealApp(WidgetTester tester,
        {String themeMode = 'system'}) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(database),
            settingsProvider.overrideWith(
              (ref) => Stream.value(
                AppSetting(
                  id: 'default',
                  themeMode: themeMode,
                  sleepGoalMinutes: 480,
                  bedtimeReminderEnabled: false,
                  bedtimeReminderMinutes: null,
                  wakeReminderEnabled: false,
                  wakeReminderMinutes: null,
                  soundRecordingEnabled: false,
                  onboarded: true,
                  insightProvider: null,
                  insightModel: null,
                ),
              ),
            ),
            sleepEntriesProvider.overrideWith((ref) => const []),
            activeSessionProvider.overrideWith((ref) => null),
          ],
          child: const NightSleepApp(),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('两条系统栏都读得到样式，且跟着应用主题', (tester) async {
      // 把 `app.dart` 里的 `builder: appSystemUiOverlayRegion` 删掉，
      // 这一条立刻变红（两条都是 null）——前面的分组一条都不会。
      await pumpRealApp(tester);
      expect(
        systemBarStyleAt(tester),
        appSystemUiOverlayStyle(Brightness.light).copyWith(
          statusBarBrightness: Brightness.dark,
          statusBarIconBrightness: Brightness.light,
        ),
      );
      expect(
        systemBarStyleAt(tester, top: false),
        appSystemUiOverlayStyle(Brightness.light),
      );
    });

    testWidgets('应用切成深色（系统仍浅色）→ 两条栏都翻成浅色图标', (tester) async {
      await pumpRealApp(tester, themeMode: 'dark');
      expect(
          systemBarStyleAt(tester), appSystemUiOverlayStyle(Brightness.dark));
      expect(
        systemBarStyleAt(tester, top: false),
        appSystemUiOverlayStyle(Brightness.dark),
      );
    });
  });

  group('enableEdgeToEdge', () {
    late List<MethodCall> calls;

    setUp(() {
      calls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        calls.add(call);
        return null;
      });
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    /// 平台判定要跑在真实分支上；`debugDefaultTargetPlatformOverride`
    /// 必须**在用例体内**还原——`testWidgets` 的收尾会断言 foundation 的调试变量
    /// 已被清干净，`addTearDown` 赶不上那一步（实测：会以「The value of a foundation
    /// debug variable was changed by the test」失败）。
    Future<void> asPlatform(
      TargetPlatform platform,
      Future<void> Function() body,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await body();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }

    test('Android：要求引擎进 edge-to-edge', () async {
      await asPlatform(TargetPlatform.android, () async {
        await enableEdgeToEdge();
      });

      // 载荷就是一整个模式名的字符串（`SystemChrome.setEnabledSystemUIMode`
      // 在 mode != manual 时只发这一个参数，已读 SDK 源核对）。
      final modes = calls
          .where((c) => c.method == 'SystemChrome.setEnabledSystemUIMode')
          .map((c) => c.arguments);
      expect(modes, [SystemUiMode.edgeToEdge.toString()]);
    });

    test('iOS / macOS：一次都不调（那边本来就边到边，不需要也不该动）', () async {
      for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
        await asPlatform(platform, () async {
          await enableEdgeToEdge();
        });
      }

      expect(calls, isEmpty);
    });
  });
}
