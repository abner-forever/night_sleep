import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/database/app_database.dart';
import '../core/platform/system_bars.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/app_tokens.dart';
import '../core/widgets/atmosphere.dart';
import '../features/compass/presentation/compass_page.dart';
import '../features/home/presentation/home_page.dart';
import '../features/log/presentation/log_edit_page.dart';
import '../features/log/presentation/log_new_page.dart';
import '../features/log/presentation/review_page.dart';
import '../features/onboarding/presentation/onboarding_overlay.dart';
import '../features/onboarding/presentation/splash_screen.dart';
import '../features/settings/presentation/appearance_settings_page.dart';
import '../features/settings/presentation/demo_data_page.dart';
import '../features/settings/presentation/export_page.dart';
import '../features/settings/presentation/insight_config_page.dart';
import '../features/settings/presentation/settings_page.dart';
import '../features/settings/presentation/sleep_import_page.dart';
import '../features/settings/presentation/sleep_settings_page.dart';
import '../features/session/presentation/sleep_session_page.dart';
import '../features/sleep/data/clip_analyzer.dart';
import '../features/sleep/data/clip_pruning.dart';
import '../features/sleep/data/clip_store.dart';
import '../features/sleep/presentation/sheets/noise_sheet.dart';
import '../features/stats/presentation/stats_page.dart';
import 'app_shell.dart';
import 'app_toast.dart';
import 'night_recording.dart';

final settingsProvider = StreamProvider<AppSetting>((ref) {
  return ref.watch(databaseProvider).watchSettings();
});

final themeModeProvider = Provider<ThemeMode>((ref) {
  final mode = ref.watch(settingsProvider).valueOrNull?.themeMode ?? 'system';
  return switch (mode) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
});

/// Sub-pages are declared as children of `/`, so pushing them covers the shell
/// — which is how the design hides the tab bar on a settings sub-page.
final _router = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const AppScaffold(),
      routes: [
        // 外观与睡眠设置是 v3.5 从设置根页收进来的两个二级页：根页只留导航行。
        GoRoute(
          path: 'settings/appearance',
          builder: (context, state) => const AppearanceSettingsPage(),
        ),
        GoRoute(
          path: 'settings/sleep',
          builder: (context, state) => const SleepSettingsPage(),
        ),
        GoRoute(
          path: 'settings/import',
          builder: (context, state) => const SleepImportPage(),
        ),
        GoRoute(
          path: 'settings/export',
          builder: (context, state) => const ExportPage(),
        ),
        GoRoute(
          path: 'settings/insight',
          builder: (context, state) => const InsightConfigPage(),
        ),
        GoRoute(
          path: 'settings/demo',
          builder: (context, state) => const DemoDataPage(),
        ),
        GoRoute(
          path: 'settings/compass',
          builder: (context, state) => const CompassPage(),
        ),
        // The night is handed over as `extra` rather than looked up again: the
        // list it came from is already in memory, and editing is about the
        // snapshot the user tapped, not whatever the row says a moment later.
        GoRoute(
          path: 'log/edit',
          builder: (context, state) => LogEditPage(routeArgument: state.extra),
        ),
        // 手动补录：回顾页底部的入口与会话时长越界的说明层都推到这里。
        GoRoute(
          path: 'log/new',
          builder: (context, state) => const LogNewPage(),
        ),
        // 会话页与设置子页同一层级：推入后覆盖标签外壳，全屏。
        //
        // 2026-10-14 起它**从底部升起**（不再走平台默认的推入转场），并可从顶部
        // 标题行下拉滑走——呈现上是一个整屏面板（使用方要的「底部弹出」）。
        //
        // **没有换成 `showAppSheet` 那种 dialog**：这一页里有 `context.go('/')`
        // 与 `context.push('/log/new')`，而 `go` 不会 pop 一个 dialog 路由，结束或
        // 丢弃会话会**在一个仍然可见的弹层底下**导航。保住这条 go_router 路由，
        // `go` / `push` / `canPop` 就全部照常。
        GoRoute(
          path: 'sleep/session',
          pageBuilder: (context, state) => CustomTransitionPage<void>(
            // **`key` 不能省。** `Navigator` 按 `Page.key` 与已有路由配对；缺了它，
            // 每次重建都会当成新路由把这一页重挂一遍——草稿被清、计时器重起。
            key: state.pageKey,
            // 非不透明：往下拉时底下露出的要是**真的首页**。
            // 蒙层不用另做——`ModalRoute` 无条件建一层 `ModalBarrier`，它吃指针，
            // 所以「不点蒙层关闭」是白送的，设 `barrierDismissible` 反而会多一种。
            opaque: false,
            transitionDuration: AppDurations.standard,
            reverseTransitionDuration: AppDurations.standard,
            transitionsBuilder: (context, animation, secondary, child) =>
                SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 1),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(
                  parent: animation,
                  curve: AppMotion.standardCurve,
                ),
              ),
              child: child,
            ),
            child: const SleepSessionPage(),
          ),
        ),
      ],
    ),
  ],
);

class NightSleepApp extends ConsumerWidget {
  const NightSleepApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: '夜深',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: _router,
      // 系统栏（状态栏 / 导航栏）的样式。**必须挂在 `builder` 上**：这里在主题
      // 之内、路由之上下，`Theme.of(context)` 拿到的才是应用当前生效的明暗。
      builder: appSystemUiOverlayRegion,
    );
  }
}

/// The tab host: atmosphere, navigation shell, onboarding gate and the noise
/// sheet.
class AppScaffold extends ConsumerStatefulWidget {
  const AppScaffold({super.key});

  @override
  ConsumerState<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends ConsumerState<AppScaffold> {
  /// The hero ring draws itself only on the first arrival at Home, matching the
  /// prototype's `homeRingHasPlayed` ref — it is an arrival cue, not a
  /// route-transition effect.
  bool _ringHasPlayed = false;

  /// 开屏页的时间轴是否播完。
  ///
  /// 它是 **State 字段而不是 provider**：`AppScaffold` 是 `/` 这条路由的 builder，
  /// push 子页时它留在 Navigator 里、State 被复用，所以这个标记不会在来回跳转时重置；
  /// 而放进 provider 一旦被 invalidate，开屏就会重播。
  bool _splashFinished = false;

  /// 设置是否已经读到过结论（成功或失败都算）。
  ///
  /// 记成「见过一次就再也不翻回去」的**单向**标记，而不是每次都去看
  /// `settingsAsync.isLoading`：后者在 provider 被 invalidate 时会重新变回 true，
  /// 于是开屏会在应用跑到一半时**重新冒出来**。今天没有人 invalidate
  /// `settingsProvider`，但那是随时可能被加上的调用。
  bool _settingsSeen = false;

  @override
  void initState() {
    super.initState();
    // 冷启动对账：会话可能是**重启之前**开的（`active_sessions` 那一行跨重启存活），
    // 而进程一被杀，录音早就跟着停了。这里按开关与白噪音重新对齐一次——不这么做的话，
    // 用户重启一次 App，剩下的半夜就再也不会被录。
    //
    // **它不是「假装还在录」**：`syncWithSession` 只负责去真的把录音起起来，起不来
    // 界面就如实显示停止原因；界面读的始终是录音服务的实际状态，不是偏好值。
    //
    // 放在 `addPostFrameCallback` 里而不是直接调：这一步会去读库、甚至申请麦克风，
    // 不该挡着第一帧。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        ref.read(nightRecordingControllerProvider.notifier).syncWithSession(),
      );
      unawaited(_pruneRecordings().then((_) => _analysePendingClips()));
    });
  }

  /// 启动时清一次录音：超期的那几晚删文件、置空 `localUri`（行保留），
  /// 以及删掉那些永远不会入库的孤儿文件。
  ///
  /// **两件都不该挡着启动，失败了也不该让应用起不来**——它们是打扫，不是功能。
  /// 与 `syncWithSession` 并行跑：孤儿清理要分辨「还没入库」与「没人要了」，
  /// 靠的是它自己去库里读那份会话清单，不依赖对账跑完没有。
  Future<void> _pruneRecordings() async {
    try {
      final database = ref.read(databaseProvider);
      final files = ref.read(clipFileStoreProvider);
      await pruneExpiredRecordings(database: database, files: files);
      await deleteOrphanRecordings(database: database, files: files);
    } catch (error) {
      debugPrint('清理录音失败：$error');
    }
  }

  /// 把还没被机器看过的片段补上分析。
  ///
  /// **排在清理之后**，两个理由：清理会删掉超期音频，先分析再删等于白算一遍；
  /// 而且清理过后剩下的那些才是真的有文件可读的。
  ///
  /// 它是**为「装上新版本之前就已经录好的片段」准备的**：用户不需要做任何事。
  /// 也是会话结束时那次分析没跑完的兜底（页面被关、进程被杀）。
  ///
  /// 同样不挡启动：串行跑、每段之间让出事件循环，失败只记一行日志。
  Future<void> _analysePendingClips() async {
    try {
      await ref.read(clipAnalyzerProvider).analysePending();
    } catch (error) {
      debugPrint('补跑片段分析失败：$error');
    }
  }

  void _selectTab(AppTab tab) {
    if (tab == ref.read(activeTabProvider)) return;
    ref.read(activeTabProvider.notifier).state = tab;
  }

  void _openNoiseSheet() {
    showNoiseSheet(context);
  }

  /// 打开会话页。**它不写库。**
  ///
  /// v3.3 起记录起点在页内那颗「开始睡眠」上（原型 `SleepView` 就是这个语义：
  /// 进睡眠模式只是进了一屏睡前设定）。这里只负责推入——没有会话行时那一页显示
  /// 入睡前态，用户按下「开始睡眠」才写行、翻到进行中态。于是「点进来看一眼又退出」
  /// 不会留下一段并不存在的睡眠。
  void _openSession(BuildContext context) {
    context.push('/sleep/session');
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final settingsAsync = ref.watch(settingsProvider);
    final settings = settingsAsync.valueOrNull;
    final tab = ref.watch(activeTabProvider);

    // **开屏要等设置读到第一帧才收起，不能只看计时器。**
    //
    // `settingsProvider` 是异步流：只看计时器的话，它还没吐出第一帧时外壳就先露出来，
    // 引导页随后再盖上去——用户看到的是「闪一下主界面再跳出引导」。
    //
    // 用 `isLoading` 而不是 `valueOrNull != null`：读取**失败**时也算「有结论了」，
    // 否则库里一出错，开屏就永远收不起来（`AsyncValue` 的 `isLoading` 在
    // data / error 两种终态下都是 false）。结果记进 [_settingsSeen]，之后不再翻回去。
    if (!settingsAsync.isLoading) _settingsSeen = true;
    final splashVisible = !_splashFinished || !_settingsSeen;
    final showOnboarding =
        !splashVisible && settings != null && !settings.onboarded;

    return Scaffold(
      backgroundColor: tokens.bgBase,
      body: Atmosphere(
        child: Stack(
          children: [
            SafeArea(
              top: false,
              bottom: false,
              child: AppShell(
                current: tab,
                onSelect: _selectTab,
                onOpenNoise: _openNoiseSheet,
                child: _TabContent(
                  tab: tab,
                  ringHasPlayed: _ringHasPlayed,
                  onRingConsumed: () => _ringHasPlayed = true,
                  onOpenNoise: _openNoiseSheet,
                  onStartSleep: () => _openSession(context),
                ),
              ),
            ),
            const ToastOverlay(),
            if (showOnboarding)
              OnboardingOverlay(
                onDone: () async {
                  await ref.read(databaseProvider).updateSettings(
                        const AppSettingsCompanion(onboarded: Value(true)),
                      );
                },
              ),
            // 开屏**排在最后**：它要盖住外壳与引导页。
            //
            // 原型里两者的 `z-index` 都是 200，而引导页在 DOM 里更靠后，于是首次
            // 启动时引导页把开屏**整个盖住**、开屏等于没播。那是原型的层叠疏漏，
            // 这里按显然的意图做：先开屏、后引导（见规格偏差表）。
            if (splashVisible)
              SplashScreen(
                onFinished: () => setState(() => _splashFinished = true),
              ),
          ],
        ),
      ),
    );
  }
}

/// 切换当前页面，并按设计把内容列居中限宽在 720px。
class _TabContent extends StatelessWidget {
  const _TabContent({
    required this.tab,
    required this.ringHasPlayed,
    required this.onRingConsumed,
    required this.onOpenNoise,
    required this.onStartSleep,
  });

  final AppTab tab;
  final bool ringHasPlayed;
  final VoidCallback onRingConsumed;
  final VoidCallback onOpenNoise;
  final VoidCallback onStartSleep;

  @override
  Widget build(BuildContext context) {
    // Honours the design's `max-width: 720px` content column on wide layouts.
    // The horizontal gutter is *not* applied here — see [pageGutter].
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        // 顶部留白改由各页自己的滚动视图施加——见 [pageTopInset]。
        child: switch (tab) {
          AppTab.home => HomePage(
              animateRing: !ringHasPlayed,
              onRingConsumed: onRingConsumed,
              onOpenNoise: onOpenNoise,
              onStartSleep: onStartSleep,
            ),
          AppTab.log => const ReviewPage(),
          AppTab.stats => const StatsPage(),
          AppTab.settings => const SettingsPage(),
        },
      ),
    );
  }
}
