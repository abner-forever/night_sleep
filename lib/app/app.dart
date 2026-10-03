import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/database/app_database.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/app_tokens.dart';
import '../core/widgets/atmosphere.dart';
import '../features/compass/presentation/compass_page.dart';
import '../features/home/presentation/home_page.dart';
import '../features/log/presentation/log_edit_page.dart';
import '../features/log/presentation/log_new_page.dart';
import '../features/log/presentation/review_page.dart';
import '../features/onboarding/presentation/onboarding_overlay.dart';
import '../features/settings/presentation/demo_data_page.dart';
import '../features/settings/presentation/export_page.dart';
import '../features/settings/presentation/insight_config_page.dart';
import '../features/settings/presentation/settings_page.dart';
import '../features/settings/presentation/sleep_import_page.dart';
import '../features/session/presentation/sleep_session_page.dart';
import '../features/sleep/presentation/sheets/noise_sheet.dart';
import '../features/stats/presentation/stats_page.dart';
import 'app_shell.dart';
import 'app_toast.dart';

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
        GoRoute(
          path: 'sleep/session',
          builder: (context, state) => const SleepSessionPage(),
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
    final settings = ref.watch(settingsProvider).valueOrNull;
    final showOnboarding = settings != null && !settings.onboarded;
    final tab = ref.watch(activeTabProvider);

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
