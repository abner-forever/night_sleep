import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_shell.dart';
import '../../../core/config/app_config.dart';
import '../../../core/platform/system_bars.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_basics.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/glass_surface.dart';
import '../../../core/widgets/quiet_surface.dart';
import '../../sleep/data/session_repository.dart';
import '../../sleep/data/sleep_repository.dart';
import '../../sleep/domain/sleep_entry.dart';
import '../../sleep/domain/sleep_session.dart';
import '../../sleep/presentation/sheets/detail_sheet.dart';
import '../../sleep/presentation/widgets/stage_chart.dart';
import '../../sleep/presentation/widgets/sleep_summary.dart';
import '../../sleep/presentation/widgets/stage_style.dart';
import '../data/weather_location.dart';
import '../data/weather_service.dart';
import '../domain/home_insight.dart';
import '../domain/weather_snapshot.dart';
import 'widgets/sleep_hero.dart';
import 'widgets/tonight_comfort.dart';

/// 「现在」的读取接缝。
///
/// 默认现读系统时钟；测试把它冻住，好让「已睡 3h 42m」这类读数不随运行测试的
/// 日期漂移——与 `SleepSessionPage.now` 是同一条规则，只是首页是 `ConsumerWidget`，
/// 没有 state 可以放这个字段。
///
/// 返回**函数**而不是时刻：`Provider<DateTime>` 会缓存第一次读到的值，卡片上的
/// 时长就永远停在应用启动那一刻。每次 build 现读一次才是对的。
final homeNowProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Home — sleep overview, the night just gone, and the recent history.
class HomePage extends ConsumerWidget {
  const HomePage({
    super.key,
    required this.animateRing,
    required this.onRingConsumed,
    required this.onOpenNoise,
    required this.onStartSleep,
  });

  final bool animateRing;
  final VoidCallback onRingConsumed;
  final VoidCallback onOpenNoise;

  /// 开始一个新会话：写入会话行并推入会话页。没有会话时主按钮走它。
  final VoidCallback onStartSleep;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(sleepEntriesProvider);
    final session = ref.watch(activeSessionProvider).valueOrNull;
    final clock = ref.watch(homeNowProvider);
    final now = clock();
    final weather = ref.watch(weatherProvider);

    // 外壳不再兜底留白，状态栏留白由页面自己补（见 [pageTopInset]），
    // 所以加载与错误分支也要和数据分支的 ListView 用同一套顶部与横向留白。
    final inset = EdgeInsets.only(
      top: pageTopInset(context),
      bottom: pageBottomInset(context),
      left: pageGutter(context),
      right: pageGutter(context),
    );

    return entries.when(
      loading: () => Padding(
        padding: inset,
        child: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, stack) => Padding(
        padding: inset,
        child: EmptyState(
          icon: AppIcons.moon(
              size: 30, color: Theme.of(context).colorScheme.error),
          title: '无法读取记录',
          body: '本地数据库打开失败：$error',
        ),
      ),
      data: (records) => _HomeContent(
        records: records,
        session: session,
        now: now,
        clock: clock,
        weather: weather,
        animateRing: animateRing,
        onRingConsumed: onRingConsumed,
        onOpenNoise: onOpenNoise,
        onStartSleep: onStartSleep,
      ),
    );
  }
}

class _HomeContent extends StatelessWidget {
  const _HomeContent({
    required this.records,
    required this.session,
    required this.now,
    required this.clock,
    required this.weather,
    required this.animateRing,
    required this.onRingConsumed,
    required this.onOpenNoise,
    required this.onStartSleep,
  });

  final List<SleepEntry> records;
  final SleepSession? session;
  final DateTime now;
  final DateTime Function() clock;
  final AsyncValue<WeatherSnapshot?> weather;
  final bool animateRing;
  final VoidCallback onRingConsumed;
  final VoidCallback onOpenNoise;
  final VoidCallback onStartSleep;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final today = records.firstOrNull;
    final wide = MediaQuery.sizeOf(context).width >= kWideLayoutBreakpoint;
    if (animateRing) {
      WidgetsBinding.instance.addPostFrameCallback((_) => onRingConsumed());
    }
    final stages = today == null
        ? null
        : Padding(
            padding: EdgeInsets.all(wide ? 24 : 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader('睡眠阶段', padding: EdgeInsets.zero),
                SleepStageSummary(entry: today, horizontal: wide),
              ],
            ),
          );
    final overview = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _masthead(context, wide, clock, weather),
        SizedBox(height: wide ? 18 : 14),
        if (today != null)
          SleepHeroCard(entry: today, animateRing: animateRing, wide: wide)
        else
          QuietSurface(
            key: const ValueKey('home-first-night'),
            tint: wide ? tokens.bgCard : const Color(0xFC0D1C3A),
            borderColor: wide ? tokens.border : Colors.transparent,
            padding: const EdgeInsets.all(20),
            onTap: session == null
                ? onStartSleep
                : () => context.push('/sleep/session'),
            semanticLabel: session == null ? '开始入睡' : '返回正在进行的睡眠',
            child: Row(children: [
              AppIcons.moon(
                  size: 34, color: wide ? tokens.accent : Colors.white),
              const SizedBox(width: 15),
              Expanded(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('还没有睡眠记录',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: wide ? tokens.textPrimary : Colors.white)),
                  const SizedBox(height: 5),
                  Text('从今晚开始，了解你的睡眠',
                      style: TextStyle(
                          fontSize: 12,
                          color: wide
                              ? tokens.textMuted
                              : const Color(0xFFA0B9D5))),
                ],
              )),
            ]),
          ),
        if (wide && stages != null)
          QuietSurface(
            borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(19)),
            child: stages,
          ),
      ],
    );
    final insight = today == null
        ? null
        : QuietSurface(
            padding: const EdgeInsets.all(14),
            onTap: () => showSleepDetailSheet(context, today),
            semanticLabel: '查看睡眠时长变化与详情',
            child: Row(children: [
              Container(
                width: 39,
                height: 39,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: tokens.good.withValues(alpha: .16)),
                child: Center(
                    child: AppIcons.moon(size: 24, color: tokens.accent)),
              ),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      durationInsightSentence(durationDelta(records
                          .map((entry) => entry.durationHours)
                          .toList())),
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: tokens.textPrimary)),
                  const SizedBox(height: 4),
                  Text(durationAdviceSentence(today.durationHours),
                      style: TextStyle(
                          fontSize: 10, height: 1.5, color: tokens.textMuted)),
                ],
              )),
              const SizedBox(width: 6),
              AppIcons.chevronRight(size: 17, color: tokens.textMuted),
            ]),
          );
    final actions = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (insight != null) ...[insight, const SizedBox(height: 17)],
        // 天气拿不到时这张卡整张不出现：没有天气就没有建议，不画占位卡。
        // 它排在「开始入睡」之前——建议要贴着它促成的那件事。
        if (weather.valueOrNull case final snapshot?) ...[
          TonightComfortCard(
            weather: snapshot,
            actionLabel: session == null ? '开始入睡' : '返回睡眠中',
            onAction: session == null
                ? onStartSleep
                : () => context.push('/sleep/session'),
          ),
          const SizedBox(height: 17),
        ],
        if (session != null)
          _ActiveSessionCard(session: session!, now: now)
        else
          Pressable(
            key: const ValueKey('home-start-sleep'),
            onTap: onStartSleep,
            semanticLabel: '开始入睡',
            child: Container(
              constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              decoration: BoxDecoration(
                  color: tokens.primaryActionFill,
                  borderRadius: BorderRadius.circular(28)),
              child:
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                AppIcons.bed(size: 21, color: Colors.white),
                const SizedBox(width: 8),
                const Flexible(
                    child: Text('开始入睡',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Colors.white))),
              ]),
            ),
          ),
        const SizedBox(height: 17),
        _utilities(context),
        if (records.any((entry) => entry.source == AppConfig.demoSource)) ...[
          const SizedBox(height: 17),
          const _DemoBadge(),
        ],
      ],
    );
    final history = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('最近记录'),
        QuietSurface(
          borderRadius: BorderRadius.circular(17),
          child: Column(children: [
            for (var index = 0; index < records.take(5).length; index++) ...[
              if (index > 0) Divider(height: 1, color: tokens.border),
              HomeRecordRow(entry: records[index]),
            ],
          ]),
        ),
      ],
    );
    return LayoutBuilder(builder: (context, constraints) {
      final twoColumns = wide && constraints.maxWidth >= 850;
      Widget buildList([ScrollController? controller]) => ListView(
            controller: controller,
            padding: EdgeInsets.only(bottom: pageBottomInset(context)),
            children: [
              if (wide)
                Padding(
                  padding:
                      EdgeInsets.fromLTRB(36, pageTopInset(context), 36, 0),
                  child: twoColumns
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                              Expanded(
                                  flex: 115,
                                  child: Column(children: [
                                    overview,
                                    const SizedBox(height: 20),
                                    actions,
                                  ])),
                              const SizedBox(width: 30),
                              Expanded(
                                  flex: 100,
                                  child: Padding(
                                      padding: const EdgeInsets.only(top: 85),
                                      child: history)),
                            ])
                      : Column(children: [
                          overview,
                          const SizedBox(height: 20),
                          actions,
                          if (records.isNotEmpty) ...[
                            const SizedBox(height: 27),
                            history,
                          ],
                        ]),
                )
              else ...[
                AnnotatedRegion<SystemUiOverlayStyle>(
                    value: appSystemUiOverlayStyle(Theme.of(context).brightness)
                        .copyWith(
                      statusBarBrightness: Brightness.dark,
                      statusBarIconBrightness: Brightness.light,
                    ),
                    child: Stack(children: [
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        bottom: 34,
                        // 矮屏或数据较多时，深色头部可能越过首屏；底边渐隐到页面底色，
                        // 避免滚动后出现一条生硬的蓝白分界。
                        child: ShaderMask(
                          shaderCallback: (rect) => const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black,
                              Colors.black,
                              Colors.transparent,
                            ],
                            stops: [0, .62, 1],
                          ).createShader(rect),
                          blendMode: BlendMode.dstIn,
                          child: const DecoratedBox(
                            key: ValueKey('home-header-background'),
                            decoration: BoxDecoration(
                              image: DecorationImage(
                                  image: AssetImage(
                                      'assets/images/night-lake.jpg'),
                                  fit: BoxFit.cover,
                                  alignment: Alignment(0, -.2)),
                            ),
                            child: DecoratedBox(
                                decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  homeHeaderTopColor,
                                  Color(0x80183F76),
                                  Color(0xFF0C2344)
                                ],
                                stops: [0, .45, 1],
                              ),
                            )),
                          ),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                            16 + MediaQuery.paddingOf(context).left,
                            pageTopInset(context),
                            16 + MediaQuery.paddingOf(context).right,
                            0),
                        child: overview,
                      ),
                    ])),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                      18 + MediaQuery.paddingOf(context).left,
                      20,
                      18 + MediaQuery.paddingOf(context).right,
                      0),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (stages != null) ...[
                          stages,
                          const SizedBox(height: 17)
                        ],
                        actions,
                        if (records.isNotEmpty) ...[
                          const SizedBox(height: 27),
                          history
                        ],
                      ]),
                ),
              ],
            ],
          );
      return wide ? buildList() : _HomePullBackground(builder: buildList);
    });
  }

  Widget _masthead(
    BuildContext context,
    bool wide,
    DateTime Function() clock,
    AsyncValue<WeatherSnapshot?> weather,
  ) {
    final tokens = AppTokens.of(context);
    final foreground = wide ? tokens.textPrimary : Colors.white;
    final brand = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '夜深',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w600,
            color: foreground,
            letterSpacing: -.84,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          '让每一次睡眠都有迹可循',
          style: TextStyle(
            fontSize: 12,
            color: wide ? tokens.textMuted : const Color(0xFFDFECFF),
          ),
        ),
      ],
    );
    final calendarAction = Semantics(
      button: true,
      label: '打开睡眠日历',
      child: Pressable(
        onTap: () => context.push('/calendar'),
        child: Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color:
                wide ? tokens.accentSoft : Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color:
                  wide ? tokens.border : Colors.white.withValues(alpha: 0.20),
            ),
          ),
          child: AppIcons.calendar(
            size: 20,
            color: wide ? tokens.accent : Colors.white,
            strokeWidth: 1.7,
          ),
        ),
      ),
    );
    final clockAndWeather = _HomeClock(
      clock: clock,
      weather: weather,
      wide: wide,
    );

    if (wide) {
      // 比例从 3:6 收成 2:3：品牌段少占一点，时间与天气更早开始，横屏下的
      // 观感是「两个内容块」而不是「三段各自漂浮」。宽度必须保持弹性——
      // 768~850dp 的横屏放不下固定宽的时间+天气组合（实测会溢出 90+px）。
      return ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 96),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(flex: 2, child: brand),
            const SizedBox(width: 24),
            Expanded(flex: 3, child: clockAndWeather),
            const SizedBox(width: 18),
            calendarAction,
          ],
        ),
      );
    }

    return SizedBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: brand),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: calendarAction,
              ),
            ],
          ),
          const SizedBox(height: 18),
          clockAndWeather,
        ],
      ),
    );
  }

  Widget _utilities(BuildContext context) {
    final tokens = AppTokens.of(context);
    final recent = records.take(7).toList();
    final average = recent.isEmpty
        ? null
        : recent.fold<double>(0, (sum, entry) => sum + entry.durationHours) /
            recent.length;
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: QuietSurface(
            key: const ValueKey('home-noise-card'),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(children: [
                  AppIcons.moon(size: 18, color: tokens.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('最近 7 条平均时长',
                        style:
                            TextStyle(fontSize: 10, color: tokens.textMuted)),
                  ),
                ]),
                const SizedBox(height: 10),
                Text(
                    average == null
                        ? '暂无记录'
                        : '${average.toStringAsFixed(1)} h',
                    style: AppTheme.num(context,
                        size: average == null ? 14 : 23,
                        weight: FontWeight.w500,
                        color: tokens.accent)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: QuietSurface(
            padding: const EdgeInsets.all(14),
            onTap: onOpenNoise,
            semanticLabel: '助眠音效',
            child: Row(
              children: [
                AppIcons.music(size: 19, color: tokens.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '助眠音效',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: tokens.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '海浪 · 篝火 · 自然之声',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.4,
                          color: tokens.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  key: const ValueKey('home-noise-chevron'),
                  child: AppIcons.chevronRight(
                    size: 15,
                    color: tokens.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}

class _HomeClock extends StatefulWidget {
  const _HomeClock({
    required this.clock,
    required this.weather,
    required this.wide,
  });

  final DateTime Function() clock;
  final AsyncValue<WeatherSnapshot?> weather;
  final bool wide;

  @override
  State<_HomeClock> createState() => _HomeClockState();
}

class _HomeClockState extends State<_HomeClock> {
  late DateTime _now;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _now = widget.clock();
    _scheduleNextMinute();
  }

  @override
  void didUpdateWidget(covariant _HomeClock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.clock != oldWidget.clock) {
      _now = widget.clock();
      _scheduleNextMinute();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _scheduleNextMinute() {
    _timer?.cancel();
    final nextMinute = DateTime(
      _now.year,
      _now.month,
      _now.day,
      _now.hour,
      _now.minute + 1,
    );
    final delay = nextMinute.difference(_now);
    _timer = Timer(
      delay > Duration.zero ? delay : const Duration(minutes: 1),
      () {
        if (!mounted) return;
        setState(() => _now = widget.clock());
        _scheduleNextMinute();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final hour = _now.hour.toString().padLeft(2, '0');
    final minute = _now.minute.toString().padLeft(2, '0');
    final weekday = const ['一', '二', '三', '四', '五', '六', '日'][_now.weekday - 1];
    final date = '${_now.month} 月 ${_now.day} 日';
    final weatherLabel = widget.weather.when(
      loading: () => '，天气获取中',
      error: (error, stack) => '，天气暂不可用',
      data: (snapshot) => snapshot == null
          ? ''
          : '，${snapshot.city}，${snapshot.weatherText}，'
              '${snapshot.temperature.round()} 度',
    );
    final hasWeather = widget.weather.when(
      loading: () => true,
      error: (error, stack) => true,
      data: (snapshot) => snapshot != null,
    );
    final onImage = !widget.wide;
    final primary = onImage ? Colors.white : tokens.textPrimary;
    final muted = onImage ? const Color(0xAFFFFFFF) : tokens.textMuted;

    return Semantics(
      key: const ValueKey('home-clock'),
      container: true,
      label: '当前时间 $hour:$minute，$date，星期$weekday$weatherLabel',
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 350;
          final timeReadout = _HomeTimeReadout(
            time: '$hour:$minute',
            date: date,
            weekday: weekday,
            primary: primary,
            muted: muted,
          );
          final weatherReadout = _HomeWeather(
            weather: widget.weather,
            wide: widget.wide,
          );

          if (!hasWeather) return timeReadout;
          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                timeReadout,
                const SizedBox(height: 14),
                weatherReadout,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 46px 的「23:49」约 150 宽；宽屏稍留余量，避免 FittedBox 缩字。
              SizedBox(
                width: widget.wide ? 162 : 132,
                child: timeReadout,
              ),
              Container(
                width: 1,
                height: 64,
                margin: const EdgeInsets.symmetric(horizontal: 14),
                color: onImage
                    ? Colors.white.withValues(alpha: 0.20)
                    : tokens.border,
              ),
              Expanded(child: weatherReadout),
            ],
          );
        },
      ),
    );
  }
}

class _HomeTimeReadout extends StatelessWidget {
  const _HomeTimeReadout({
    required this.time,
    required this.date,
    required this.weekday,
    required this.primary,
    required this.muted,
  });

  final String time;
  final String date;
  final String weekday;
  final Color primary;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    // 时间块从「此刻」标签起头，删掉标签后它比右侧天气卡矮一截，靠外层
    // Row 的 center 对齐居中——上下留白自然相等，不需要额外补 padding。
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            time,
            maxLines: 1,
            // 宽屏不缩字号：时间是一屏里最大的数字，缩到 40 反而比竖屏小，
            // 与旁边的天气卡拉不开层级。
            style: AppTheme.num(
              context,
              size: 46,
              weight: FontWeight.w500,
              color: primary,
              letterSpacing: -1.8,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 7,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              date,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: primary,
              ),
            ),
            Container(
              width: 3,
              height: 3,
              decoration: BoxDecoration(
                color: muted,
                shape: BoxShape.circle,
              ),
            ),
            Text(
              '周$weekday',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: muted,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _HomeWeather extends ConsumerWidget {
  const _HomeWeather({
    required this.weather,
    required this.wide,
  });

  final AsyncValue<WeatherSnapshot?> weather;
  final bool wide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTokens.of(context);
    final onImage = !wide;
    final primary = onImage ? Colors.white : tokens.textPrimary;
    final muted = onImage ? const Color(0xAFFFFFFF) : tokens.textMuted;
    final location = ref.watch(weatherLocationProvider);

    return weather.when(
      loading: () => _WeatherSurface(
        onImage: onImage,
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: muted,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '正在获取天气',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: primary,
              ),
            ),
          ],
        ),
      ),
      error: (error, stack) => _WeatherUnavailable(
        onImage: onImage,
        location: location,
        onLocate: () =>
            ref.read(weatherLocationProvider.notifier).requestPermission(),
        onOpenAppSettings: () =>
            ref.read(weatherLocationProvider.notifier).openAppSettings(),
        onOpenLocationSettings: () =>
            ref.read(weatherLocationProvider.notifier).openLocationSettings(),
      ),
      data: (snapshot) {
        if (snapshot == null) return const SizedBox.shrink();
        return Semantics(
          label:
              '${snapshot.city}，${snapshot.weatherText}，${snapshot.temperature.round()} 度',
          excludeSemantics: true,
          child: _WeatherSurface(
            onImage: onImage,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Text(
                    snapshot.weatherEmoji,
                    style: const TextStyle(fontSize: 29),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${snapshot.temperature.round()}°',
                            style: AppTheme.num(
                              context,
                              size: 29,
                              weight: FontWeight.w600,
                              color: primary,
                              letterSpacing: -1,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Text(
                                snapshot.weatherText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: primary,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        snapshot.city,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: muted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 10,
                        runSpacing: 3,
                        children: [
                          _WeatherMetric(
                            text: '↑ ${snapshot.temperatureMax.round()}°',
                            color: muted,
                          ),
                          _WeatherMetric(
                            text: '↓ ${snapshot.temperatureMin.round()}°',
                            color: muted,
                          ),
                          if (snapshot.humidity != null)
                            _WeatherMetric(
                              text: '湿度 ${snapshot.humidity!.round()}%',
                              color: muted,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 天气没出来时卡片显示什么。
///
/// 要分开的两种情况：**有位置、只是请求失败**（那是网络或服务端的锅，用户没有
/// 任何可做的事，只能说「稍后自动重试」），和**根本没有位置**（这里必须给一条
/// 出路，否则那张卡片就是一个永远点不动的死物）。
///
/// 失败原因不同，出路也不同：能再问的给「重试」，被永久拒绝或系统定位关着的
/// 只能去设置。把三种都写成「稍后自动重试」，等于让用户一直点一个不会好的按钮。
class _WeatherUnavailable extends StatelessWidget {
  const _WeatherUnavailable({
    required this.onImage,
    required this.location,
    required this.onLocate,
    required this.onOpenAppSettings,
    required this.onOpenLocationSettings,
  });

  final bool onImage;
  final WeatherLocationState location;
  final VoidCallback onLocate;
  final VoidCallback onOpenAppSettings;
  final VoidCallback onOpenLocationSettings;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final primary = onImage ? Colors.white : tokens.textPrimary;
    final muted = onImage ? const Color(0xAFFFFFFF) : tokens.textMuted;

    if (location.status == WeatherLocationStatus.locating) {
      return _WeatherSurface(
        onImage: onImage,
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: muted,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '正在获取位置',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: primary,
              ),
            ),
          ],
        ),
      );
    }

    final (String title, String? action, VoidCallback? onTap) =
        switch (location.status) {
      WeatherLocationStatus.idle => ('位置未知', '使用我的位置', onLocate),
      WeatherLocationStatus.permissionDenied => ('未获得定位权限', '重试', onLocate),
      WeatherLocationStatus.permissionDeniedForever => (
          '定位权限已关闭',
          '去设置',
          onOpenAppSettings,
        ),
      WeatherLocationStatus.serviceDisabled => (
          '系统定位未开启',
          '去设置',
          onOpenLocationSettings,
        ),
      WeatherLocationStatus.unavailable => ('无法获取位置', '重试', onLocate),
      _ => ('天气暂不可用', null, null),
    };

    return _WeatherSurface(
      onImage: onImage,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: primary,
            ),
          ),
          const SizedBox(height: 6),
          if (action != null && onTap != null)
            _LocationAction(label: action, onTap: onTap, onImage: onImage)
          else
            Text(
              '稍后自动重试',
              style: TextStyle(fontSize: 10, color: muted),
            ),
        ],
      ),
    );
  }
}

/// 「使用我的位置 / 重试 / 去设置」那颗小胶囊。
///
/// 做成按钮而不是把整张卡变成可点区域：卡片平时是纯展示，一旦整块可点，
/// 用户会以为点它能看到更详细的天气，结果弹出一个权限框。
class _LocationAction extends StatelessWidget {
  const _LocationAction({
    required this.label,
    required this.onTap,
    required this.onImage,
  });

  final String label;
  final VoidCallback onTap;
  final bool onImage;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final foreground = onImage ? Colors.white : tokens.accent;

    return Pressable(
      key: const ValueKey('home-weather-locate'),
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 5, 8, 5),
        decoration: BoxDecoration(
          color: onImage
              ? Colors.white.withValues(alpha: 0.14)
              : tokens.accentSoft,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color:
                onImage ? Colors.white.withValues(alpha: 0.22) : tokens.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: foreground,
              ),
            ),
            const SizedBox(width: 2),
            AppIcons.chevronRight(size: 13, color: foreground),
          ],
        ),
      ),
    );
  }
}

class _WeatherSurface extends StatelessWidget {
  const _WeatherSurface({
    required this.child,
    required this.onImage,
  });

  final Widget child;
  final bool onImage;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Container(
      key: const ValueKey('home-weather'),
      constraints: const BoxConstraints(minHeight: 88),
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: onImage ? null : tokens.bgRaised,
        gradient: onImage
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0x26FFFFFF), Color(0x0FFFFFFF)],
              )
            : null,
        borderRadius: BorderRadius.circular(AppRadii.panel),
        border: Border.all(
          color: onImage ? Colors.white.withValues(alpha: 0.16) : tokens.border,
        ),
      ),
      child: child,
    );
  }
}

class _WeatherMetric extends StatelessWidget {
  const _WeatherMetric({
    required this.text,
    required this.color,
  });

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w500,
        color: color,
        fontFeatures: AppTheme.tabular,
      ),
    );
  }
}

class _HomePullBackground extends StatefulWidget {
  const _HomePullBackground({required this.builder});

  final Widget Function(ScrollController) builder;

  @override
  State<_HomePullBackground> createState() => _HomePullBackgroundState();
}

class _HomePullBackgroundState extends State<_HomePullBackground> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.builder(_controller),
      builder: (context, child) {
        final distance = _controller.hasClients
            ? (_controller.position.minScrollExtent - _controller.offset)
                .clamp(0.0, double.infinity)
            : 0.0;
        return ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (distance > 0)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: distance + 1,
                  child: AnnotatedRegion<SystemUiOverlayStyle>(
                    value: appSystemUiOverlayStyle(Brightness.dark),
                    child: const DecoratedBox(
                      key: ValueKey('home-pull-background'),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFF0C2344), homeHeaderTopColor],
                        ),
                      ),
                    ),
                  ),
                ),
              child!,
            ],
          ),
        );
      },
    );
  }
}

/// 会话进行中时占住首页主按钮位的那张卡。
///
/// 它替代「开始入睡」而不是并排放在一起：会话在跑时再给一个开始按钮，等于
/// 允许同时开出两个。卡片本身没有新能力——圆环画的是「已过时长 ÷ 计划时长」，
/// 两个数都是推导的，点它只是回到会话页。
class _ActiveSessionCard extends StatelessWidget {
  const _ActiveSessionCard({required this.session, required this.now});

  final SleepSession session;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final elapsed = session.elapsedLabelAt(now);

    return GlassSurface(
      borderRadius: BorderRadius.circular(AppRadii.panel),
      padding: const EdgeInsets.all(18),
      onTap: () => context.push('/sleep/session'),
      semanticLabel: '正在睡眠，已睡 $elapsed，回到会话页',
      child: Row(
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: session.progressAt(now),
                  strokeWidth: 3,
                  backgroundColor: tokens.border,
                  valueColor: AlwaysStoppedAnimation<Color>(tokens.accent),
                ),
                AppIcons.moon(size: 18, color: tokens.accent, strokeWidth: 1.8),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '正在睡眠',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: tokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '已睡 $elapsed',
                  style: TextStyle(fontSize: 13, color: tokens.textMuted),
                ),
              ],
            ),
          ),
          AppIcons.chevronRight(
              size: 18, color: tokens.textMuted, strokeWidth: 2),
        ],
      ),
    );
  }
}

/// Warns that sample rows are present, so a demo night is never mistaken for a
/// real recording.
class _DemoBadge extends StatelessWidget {
  const _DemoBadge();

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: tokens.bgMuted,
        borderRadius: BorderRadius.circular(AppRadii.panel),
      ),
      child: Row(
        children: [
          AppIcons.sparkle(size: 14, color: tokens.textMuted, strokeWidth: 1.8),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '正在显示演示数据，可在「设置 › 演示数据」中清除。',
              style: TextStyle(fontSize: 12, color: tokens.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

/// A night in the recent-records list: date, quality, duration, stage ribbon.
///
/// 外框是**列表行**，不是卡片：没有圆角、没有阴影、没有自己的描边——行与行
/// 之间的那条 1px 线由容器画。行内的内容与文案一字未改，只是外框变了：
/// v3.34 之前它叫 `RecordCard`，是 5 张各自独立的玻璃卡（规格 §4.1）。
class HomeRecordRow extends StatelessWidget {
  const HomeRecordRow({super.key, required this.entry});

  final SleepEntry entry;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final score = entry.score;

    return Pressable(
      onTap: () => showSleepDetailSheet(context, entry),
      semanticLabel: '查看 ${entry.dateLabel} 的睡眠记录',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            entry.shortDateLabel,
                            style: AppTheme.num(
                              context,
                              size: 14,
                              weight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (entry.quality != null)
                            Tag(label: entry.quality!.label),
                          if (entry.hasSnore) ...[
                            const SizedBox(width: 4),
                            AppIcons.snore(
                                size: 12,
                                color: tokens.accentBlue,
                                strokeWidth: 1.6),
                          ],
                          if (entry.hasTalk) ...[
                            const SizedBox(width: 4),
                            AppIcons.bubble(
                              size: 12,
                              color: tokens.accentViolet,
                              strokeWidth: 1.6,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          AppIcons.bed(
                              size: 11,
                              color: tokens.textMuted,
                              strokeWidth: 1.8),
                          const SizedBox(width: 4),
                          Text(
                            entry.bedtimeLabel,
                            style: AppTheme.num(
                              context,
                              size: 12,
                              color: tokens.textMuted,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              '→',
                              style: TextStyle(
                                  fontSize: 12, color: tokens.borderStrong),
                            ),
                          ),
                          AppIcons.sun(
                              size: 11,
                              color: tokens.textMuted,
                              strokeWidth: 1.8),
                          const SizedBox(width: 4),
                          Text(
                            entry.wakeLabel,
                            style: AppTheme.num(
                              context,
                              size: 12,
                              color: tokens.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          entry.durationHours.toStringAsFixed(1),
                          style: AppTheme.num(
                            context,
                            size: 22,
                            weight: FontWeight.w700,
                            color:
                                durationBandColor(tokens, entry.durationHours),
                          ),
                        ),
                        const SizedBox(width: 2),
                        Text(
                          'h',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: tokens.textMuted,
                          ),
                        ),
                      ],
                    ),
                    if (score != null)
                      Text(
                        '${entry.isEstimated ? '估算' : '评分'} $score',
                        style: AppTheme.num(
                          context,
                          size: 12,
                          weight: FontWeight.w600,
                          color: scoreBandColor(tokens, score),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            if (entry.hasStages) ...[
              const SizedBox(height: 12),
              StageRibbon(stages: entry.stages),
              const SizedBox(height: 10),
              StageLegend(
                stages: entry.stages,
                style: StageLegendStyle.labelled,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
