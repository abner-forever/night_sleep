import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_shell.dart';
import '../../../app/app_toast.dart';
import '../../../app/night_recording.dart';
import '../../../app/noise_session.dart';
import '../../../app/reminder_permission.dart';
import '../../../app/reminder_sync.dart';
import '../../../app/session_teardown.dart';
import '../../../core/database/app_database.dart';
import '../../../core/platform/haptics.dart';
import '../../../core/platform/reminders.dart';
import '../../../core/platform/system_bars.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_basics.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/wheel_picker.dart';
import '../../sleep/data/clip_analyzer.dart';
import '../../sleep/data/session_repository.dart';
import '../../sleep/domain/sleep_session.dart';
import 'night_scene.dart';
import 'session_panel_transition.dart';
import 'night_style.dart';
import 'sheets/quality_rating_sheet.dart';
import 'widgets/hold_to_finish_button.dart';
import 'widgets/night_backdrop.dart';
import 'widgets/night_scene_picker.dart';
import 'widgets/session_events_card.dart';
import 'widgets/session_header.dart';
import 'widgets/session_setup.dart';
import 'widgets/sleep_moon_mark.dart';

/// 睡眠会话页，**一个路由两态**：
///
/// - **入睡前（`activeSessionProvider` 为 null）**：原型 `SleepView` 的 setup 分支。
///   攒草稿——场景 / 常用白噪音 / 起床闹钟 / 鼾声偏好，**什么都不写库**。
/// - **进行中**：v3.2 照原型重建的那一屏（夜景 / `HH:MM:SS` / 事件卡 / 长按结束）。
///
/// 记录起点因此是页内的「开始睡眠」，不是首页那颗按钮：点首页按钮只进页面
/// （`app.dart` 的注释里记了这条）。
///
/// **它不测量任何东西**：两个时刻来自用户按下的按钮，起床时间来自用户的设定。
/// 没有阶段、没有鼾声判定、没有「睡眠质量」的推断——那些要么由用户自己补，
/// 要么在夜间录音那一轮才谈得上。
class SleepSessionPage extends ConsumerStatefulWidget {
  const SleepSessionPage({
    super.key,
    this.now,
    this.tick = const Duration(seconds: 1),
  });

  /// 固定「现在」的**测试接缝**。
  ///
  /// 非空时页面只按这一个时刻渲染，且不起定时器。这条接缝的意义是**让读数
  /// 与执行时刻无关**：真起了定时器，`_now` 就会被真实时钟覆写，于是
  /// 「3h 42m」「23:14」这类断言会随跑测试的日期时间随机变红。
  /// （pending timer 另有人兜：拆树时 `dispose()` 会 cancel 掉它。）
  final DateTime? now;

  /// 实时模式下重绘的间隔。
  final Duration tick;

  @override
  ConsumerState<SleepSessionPage> createState() => _SleepSessionPageState();
}

class _SleepSessionPageState extends ConsumerState<SleepSessionPage>
    with SingleTickerProviderStateMixin {
  Timer? _timer;
  late DateTime _now = widget.now ?? DateTime.now();

  /// 页面滚动位置。
  final ScrollController _scroll = ScrollController();

  /// 位移的出口（转场那一层的 notifier）。页面被单独挂载时为 null。
  ValueNotifier<double>? _dragSink;

  /// 标题行下拉的跟手位移（逻辑像素，正数向下）。
  ///
  /// **`unbounded`**：它不驱动动画进度，只是被当「当前位移」读写——下拉时直接赋值，
  /// 松手回弹时 `animateTo(0)`。范围不设上界，往下拉多少就是多少。
  ///
  /// 它维护手势与回弹，并把每一帧的位移**报告给转场**（那一层用同一个数字算遮罩的
  /// 浓度）。面板自己的位移仍由这一页施加——理由见页面 `build()` 里那段。
  ///
  /// 出口是从 `SessionPanelDrag` 这个作用域认领来的（转场提供）。页面被单独挂载
  /// （测试里直接挂它、没有转场）时没有出口，位移照样工作，只是没有遮罩。
  late final AnimationController _drag = AnimationController.unbounded(
    vsync: this,
    value: 0,
  );

  // ── 入睡前的草稿 ────────────────────────────────────────────────────────
  //
  // 只活在这一次挂载里：收起再进来就回到初值（原型的组件状态也是 unmount 即丢）。
  // 白噪音不在此列——它的选中与音量由 app 级的 `NoiseSessionController` 拿着。
  NightScene _draftScene = NightScene.fallback;
  bool _draftAlarm = false;

  /// 起床时刻的草稿。先用默认值起，读到设置里的起床提醒时刻再换上去
  /// （与 `SessionRepository.start()` 的缺省口径同一个：用户设过就复用）。
  int _draftWakeMinutes = SessionRepository.defaultWakeMinutes;

  /// 「开始睡眠」不能被点两遍：第二遍会把 `startAtUtc` 冲掉。
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    // 冻住时钟时**不要**起定时器：给定时刻就不该再被真实时钟覆写，否则界面
    // 读数会随执行时刻漂移。定时器本身有 `dispose()` 兜底，但那不是这条接缝
    // 的理由——它要挡的是「覆写」，不是「pending timer」。
    if (widget.now == null) {
      _timer = Timer.periodic(widget.tick, (_) {
        if (mounted) setState(() => _now = DateTime.now());
      });
    }
    // 位移每变一次就报给转场（包括回弹的每一帧：面板要跟着一起回去）。
    _drag.addListener(_reportDrag);
    _loadWakeDraft();
  }

  /// 把当前位移报给转场。没有出口（页面被单独挂载）时什么都不做。
  void _reportDrag() {
    final sink = _dragSink;
    if (sink != null) sink.value = _drag.value;
  }

  /// 认领转场提供的位移出口。
  ///
  /// 用 `didChangeDependencies` 而不是 `initState`：`initState` 里读不了
  /// `InheritedWidget`。这里**不补报当前值**——第一次挂载时两边都是 0，而之后
  /// 出口不会再换（转场的 State 与这个 State 同生共死），补报反而会在建树期间写值。
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dragSink = SessionPanelDrag.maybeOf(context);
  }

  /// 只读一次，**不订阅** `settingsProvider` 那条 drift 流：widget 测试的假时钟
  /// 不推进，订阅 `watch*` 会留下 pending timer（见 `.claude/skills/flutter-pitfalls`）。
  Future<void> _loadWakeDraft() async {
    final settings = await ref.read(databaseProvider).getSettings();
    if (!mounted) return;
    final stored = settings.wakeReminderMinutes;
    if (stored == null) return;
    setState(() => _draftWakeMinutes = stored);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scroll.dispose();
    _drag.removeListener(_reportDrag);
    _drag.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(activeSessionProvider).valueOrNull;
    // 没有会话时，背景跟的是**草稿**里那个场景——用户在选择器上点一下，整屏夜色
    // 立刻跟着换（原型 setup 分支也是这么做的）。
    final scene =
        session == null ? _draftScene : NightScene.fromId(session.sceneId);

    // 会话页是**常暗**的（原型的睡眠模式就是这么设计的：setup 页写着「屏幕将保持
    // 暗色」），而应用主题可能是浅色。包一层 dark `Theme` 之后，复用的共享组件
    // （白噪音宫格 / 音量条 / 时长 chip / `IosToggle` / `EmptyState`）照常从
    // `AppTokens` 取深色值，不必给它们抄第二份。
    final page = Theme(
      data: AppTheme.dark(),
      child: Scaffold(
        // 透明，让夜景背景透出来；这个 Scaffold 只为 Material 祖先与键盘内边距
        // 而存在，不是为了它的颜色。推入的路由继承不到外壳的任何东西。
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Positioned.fill(child: NightBackdrop(scene: scene)),
            SafeArea(
              minimum: const EdgeInsets.only(top: 20),
              // 两态都居中限宽 680：原型最终生效层给 `.sleep-setup` 与
              // `.sleep-active` 的 shell 都是 `width: min(100%, 680px)`
              // （index.css:1734 / 1915）。不限宽的话宽屏上会整条拉满。
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: session == null
                      ? SessionSetupBody(
                          scene: _draftScene,
                          alarmEnabled: _draftAlarm,
                          wakeMinutes: _draftWakeMinutes,
                          onSceneChanged: (picked) =>
                              setState(() => _draftScene = picked),
                          onAlarmToggled: _toggleAlarmDraft,
                          onWakeTimePicked: _pickWakeTimeDraft,
                          onCollapse: _collapseCurrentState,
                          onHeaderDragUpdate: _onHeaderDragUpdate,
                          onHeaderDragEnd: _onHeaderDragEnd,
                          onHeaderDragCancel: _onHeaderDragCancel,
                          onStart: _beginSleep,
                          scrollController: _scroll,
                        )
                      : _SessionBody(
                          session: session,
                          now: _now,
                          scene: scene,
                          onSceneChanged: (picked) => ref
                              .read(sessionRepositoryProvider)
                              .update(sceneId: picked.id),
                          onFinish: () => _finish(session),
                          onFinishHint: () => ref
                              .read(toastProvider.notifier)
                              .show('按住不放，填充条扫满才结束。'),
                          onCollapse: _collapseCurrentState,
                          onHeaderDragUpdate: _onHeaderDragUpdate,
                          onHeaderDragEnd: _onHeaderDragEnd,
                          onHeaderDragCancel: _onHeaderDragCancel,
                          scrollController: _scroll,
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    // 系统栏另行声明成深色底上的样式：这一页常暗，而系统栏跟的是**应用主题**的明暗
    // ——亮色主题下时间是黑字，压在满屏夜景上等于没有。
    //
    // 用的是与应用同一份 [appSystemUiOverlayStyle]，不是 `SystemUiOverlayStyle.light`
    // 预设：那个预设把导航栏写成不透明黑，进这一页会重新压出一条黑带。
    //
    // **`AnnotatedRegion` 必须在 `Transform` 外面**：它按自己的矩形判定系统栏样式，
    // 而框架探的是屏幕顶端那一小块。把它塞进位移里，拖过一个状态栏高度它就滑出了顶端，
    // 系统栏随即翻回**应用主题**的样式（浅色主题下图标变深色，压在暗掉的首页上）。
    // 位移只施加给 `page`——面板走，这一圈不动。
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: appSystemUiOverlayStyle(Brightness.dark),
      child: AnimatedBuilder(
        animation: _drag,
        // **必须带 `child:`**：不带的话每一帧都会重建整棵页面（含夜景与列表）。
        builder: (context, child) => Transform.translate(
          offset: Offset(0, _drag.value),
          child: child,
        ),
        child: page,
      ),
    );
  }

  /// 标题行跟手下拉。**手势只挂在标题行上**——面板主体是两个滚动视图，整面板级的
  /// 竖直手势会和它们抢（同 `app_sheet.dart` 里 `_SheetHandle` 那条注释）。
  void _onHeaderDragUpdate(double dy) {
    _drag.stop();
    _drag.value = (_drag.value + dy).clamp(0.0, double.infinity);
  }

  /// 手势被抢走（例如某一侧的滚动视图赢了竞技场）：**把它当作松手回弹**。
  ///
  /// 不处理的话面板就停在拉到的那个位置——一次被抢走的手势会留下一块错位的面板，
  /// 而手指早就松开了。
  void _onHeaderDragCancel() => _settleDrag();

  /// 松手：甩得够快、或拉得够远就滑走，否则弹回去。
  ///
  /// 两个阈值与底部弹层**同一份**（[kPanelDismissVelocity] / [kPanelDismissFraction]）；
  /// 面板就是整屏，所以「面板高度」取屏幕高度。
  void _onHeaderDragEnd(double velocity) {
    final flung = velocity > kPanelDismissVelocity;
    final pulled =
        _drag.value > MediaQuery.sizeOf(context).height * kPanelDismissFraction;
    if (flung || pulled) {
      // **不复位 `_drag.value`**：路由的退出动画接着从这里往下滑走；复位会让面板
      // 先跳回顶部再下滑，是个明显的闪跳（`app_sheet.dart` 的 `_onDragEnd` 同样不复位）。
      unawaited(_collapseCurrentState());
      return;
    }
    _settleDrag();
  }

  /// 回弹：面板滑回顶边，遮罩随之淡回不可见（浓度就取自这个位移）。
  void _settleDrag() {
    if (!mounted) return;
    _drag.animateTo(
      0,
      duration: AppDurations.standard,
      curve: AppMotion.standardCurve,
    );
  }

  /// 收起：**按当前态分派**，胶囊与下拉共用这一条。
  ///
  /// 两态的收尾刻意不同：入睡前要停掉试听、什么都不写库（偏差 #37），进行中则会话
  /// 继续跑、白噪音继续响（偏差 #28）。下拉要是自己另写一套，就会悄悄改掉其中一个。
  Future<void> _collapseCurrentState() async {
    if (ref.read(activeSessionProvider).valueOrNull == null) {
      await _collapseSetup();
    } else {
      _collapse(context);
    }
  }

  /// 「开始睡眠」：把草稿一次写全，从这一刻开始计时。
  ///
  /// **写库只发生在这里。** 进页面什么都不写（原型的睡眠模式也是这个语义：进去只是
  /// 一屏睡前设定），所以记录里的入睡时刻就是按下这颗按钮的时刻。
  Future<void> _beginSleep() async {
    if (_starting) return;

    // 与进行中态同一个闸口：闹钟开着但通知权限被拒（或平台安排不了）时，不写库、
    // 也不开始这一晚——否则会留下一个「设了闹钟却不会响」的会话。
    if (_draftAlarm &&
        !await ensureNotificationPermission(context, ref, target: '闹钟')) {
      return;
    }
    if (!mounted) return;

    setState(() => _starting = true);
    final noise = ref.read(noiseSessionControllerProvider);
    try {
      await ref.read(sessionRepositoryProvider).start(
            now: widget.now,
            wakeMinutes: _draftWakeMinutes,
            alarmEnabled: _draftAlarm,
            sceneId: _draftScene.id,
            // 正在试听的那条音直接成为这一晚的音：控制器的语义就是「选中并正在播放」，
            // 所以这里不做第二次 `play`，也不给它第二个真源。
            noiseId: noise.activeId,
            noiseVolume: noise.volume,
          );
      // 与收尾同款：会话闹钟（9003）与日常起床提醒（9002）必须成对推导。
      await syncAllReminders(
        ref.read(databaseProvider),
        ref.read(reminderSchedulerProvider),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _starting = false);
      ref.read(toastProvider.notifier).show('开始失败：$error');
      return;
    }

    // `syncAllReminders` 是平台调用，回到这里时页面可能已经被 pop 掉了。
    // 少了这道守卫，下面那句 `ref.read` 会在一个已释放的 `ConsumerState` 上抛错，
    // 把一次「用户自己退出去」变成一条未处理异常。
    if (!mounted) return;

    // 会话行已经写下去了，现在才轮到录音。**顺序不能反**：录音控制器要先能读到
    // 那一行（它据此判断「有没有会话」，以及有没有白噪音挡着），才谈得上开始录。
    // 正在试听的白噪音照样会挡住录音——这一条由控制器自己按 `isPlaying` 判断。
    await ref.read(nightRecordingControllerProvider.notifier).syncWithSession();

    if (!mounted) return;
    AppHaptics.success();
    // 不 pop、不 push：会话行一写下去，`activeSessionProvider` 自己把本页翻到
    // 进行中态（`_starting` 随之作废——那一态根本没有「开始」按钮）。
  }

  /// 入睡前态收起：停掉试听再走，**什么都不写库**。
  ///
  /// 试听要停——没有会话在跑，就没有理由让声音留在后台（原型的 setup 分支卸载时
  /// 也 `stop()`）。这与进行中态的收起**刻意不同**：那一态会话还在跑，白噪音要陪着
  /// （偏差 #28）。
  Future<void> _collapseSetup() async {
    await ref.read(noiseSessionControllerProvider).stop();
    if (!mounted) return;
    _collapse(context);
  }

  /// 闹钟开关只改草稿；真正排定在 `_beginSleep` 写完会话行之后。
  Future<void> _toggleAlarmDraft(bool value) async {
    if (value &&
        !await ensureNotificationPermission(context, ref, target: '闹钟')) {
      return; // 被拒：草稿不动，开关自己弹回去。
    }
    if (!mounted) return;
    setState(() => _draftAlarm = value);
  }

  /// 起床时刻也只在草稿里改。只有「完成」才提交——滚了轮再点取消不该生效。
  Future<void> _pickWakeTimeDraft() async {
    var draft = minutesToClock(_draftWakeMinutes);
    final confirmed = await showPickerSheet(
      context: context,
      title: '起床闹钟',
      child: AppTimePicker(value: draft, onChanged: (value) => draft = value),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _draftWakeMinutes = clockToMinutes(draft));
  }

  /// 结束这次会话：评星 → 落库 → 停白噪音 → 撤闹钟 → 切到「回顾」。
  ///
  /// **时长越界时不落库。** 会产生越界的只有两种操作：点了开始就立刻点结束，
  /// 或者点了开始忘了结束、放了好几天。两种都不该静默变成一条睡眠记录，所以
  /// 这里把决定权交回用户（[SessionRepository.finish] 里还有第二道同样的守门）。
  Future<void> _finish(SleepSession session) async {
    final now = widget.now ?? DateTime.now();
    final rejection =
        validateSessionDuration(now.toUtc().difference(session.startAtUtc));

    if (rejection != SessionFinishRejection.none) {
      if (!mounted) return;
      await showAppSheet<void>(
        context: context,
        builder: (context) => _RejectedSheet(
          rejection: rejection,
          onDiscard: () => _discard(context),
        ),
      );
      return;
    }

    final quality = await showQualityRatingSheet(context);
    if (!mounted) return;

    // **录音必须在 `finish()` 之前收尾，而且要等它把最后一次清单写完。**
    // `finish()` 会在同一个事务里读这一行会话的 `clipJournal` 来落片段行；这时候
    // 还挂着的那一段（往往就是整晚唯一的一段）如果没先定案，就永远进不了库。
    // `stopForSessionEnd` 内部已经包含了「等清单落库」那一步。
    await ref
        .read(nightRecordingControllerProvider.notifier)
        .stopForSessionEnd();
    if (!mounted) return;

    final String recordId;
    try {
      recordId = await ref
          .read(sessionRepositoryProvider)
          .finish(now: now, quality: quality);
    } catch (error) {
      if (!mounted) return;
      ref.read(toastProvider.notifier).show('保存失败：$error');
      return;
    }

    // 把这一晚的片段交给自动分析。**不 await**：读磁盘、跑 FFT，一晚几十上百段
    // 可能要好几秒，不能让它拦着页面收尾。分析完会写回 `sound_clips`，而
    // `sleepEntriesProvider` 订阅着那张表，详情页自然就看到了。
    //
    // 半路被杀也不要紧：下次冷启动的补跑会把没分析完的片段捡回来
    // （`ClipAnalyzer.analysePending`）。
    unawaited(ref.read(clipAnalyzerProvider).analyseRecord(recordId));

    // 记录已经落库，下面全是收尾。收尾一步都不许抛出去——一旦抛了，用户就被
    // 撂在一个没有会话、也没有任何反馈的页面上。见 [teardownSession]。
    await teardownSession(ref);

    if (!mounted) return;
    unawaited(AppHaptics.success());
    ref.read(toastProvider.notifier).show('睡眠记录已保存，补充一下今晚的感受吧。');
    ref.read(activeTabProvider.notifier).state = AppTab.log;
    context.go('/');
  }

  /// 「丢弃这次会话」：不写记录，只删会话行。
  Future<void> _discard(BuildContext sheetContext) async {
    // 录音先停、已录到的文件先删。**排在 `discard()` 之前**：会话行还在的时候
    // 才读得到那份片段清单，行一删就再也说不清哪些文件是这一晚的了。
    await ref
        .read(nightRecordingControllerProvider.notifier)
        .discardRecordings();
    await ref.read(sessionRepositoryProvider).discard();
    // 与结束路径**同一套收尾**（[teardownSession]）。丢弃删的是同一行会话，而
    // 9003 是设定区那个闹钟开关排的、那次调用同时让 9002 让了位：这里若不重排，
    // 一个已经不存在的会话会留着起床闹钟，日常起床提醒还继续被压着——正是
    // `reminder_sync.dart` 里那条规则要防的失败类。
    await teardownSession(ref);
    // 关掉的是**说明层**（它自己的 context），回首页走页面自己的 context——
    // 两个 context 各有各的 mounted 守卫，混着用会在弹层已拆的情况下解引用它。
    if (!mounted || !sheetContext.mounted) return;
    Navigator.of(sheetContext).pop();
    context.go('/');
  }
}

class _SessionBody extends StatelessWidget {
  const _SessionBody({
    required this.session,
    required this.now,
    required this.scene,
    required this.onSceneChanged,
    required this.onFinish,
    required this.onFinishHint,
    required this.onCollapse,
    required this.onHeaderDragUpdate,
    required this.onHeaderDragEnd,
    required this.onHeaderDragCancel,
    required this.scrollController,
  });

  final SleepSession session;
  final DateTime now;
  final NightScene scene;
  final ValueChanged<NightScene> onSceneChanged;
  final VoidCallback onFinish;
  final VoidCallback onFinishHint;
  final VoidCallback onCollapse;
  final ValueChanged<double> onHeaderDragUpdate;
  final ValueChanged<double> onHeaderDragEnd;
  final VoidCallback onHeaderDragCancel;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        SessionHeader.live(
          onCollapse: onCollapse,
          onDragUpdate: onHeaderDragUpdate,
          onDragEnd: onHeaderDragEnd,
          onDragCancel: onHeaderDragCancel,
        ),
        const SizedBox(height: 4),
        _TimerBlock(session: session, now: now),
        const SizedBox(height: 12),
        NightScenePicker(scene: scene, onChanged: onSceneChanged),
        const SizedBox(height: 12),
        SessionEventsCard(session: session, now: now),
        const SizedBox(height: 20),
        // 结束按钮在事件卡下方：它是这一页唯一的出口，也是拇指最顺的位置。
        HoldToFinishButton(onFinish: onFinish, onHint: onFinishHint),
      ],
    );
  }
}

/// 中央：月亮 + 当前时刻 + `HH:MM:SS` + 「已进入睡眠模式」。
class _TimerBlock extends StatelessWidget {
  const _TimerBlock({required this.session, required this.now});

  final SleepSession session;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final clock = now.toLocal();
    final hhmm = '${clock.hour.toString().padLeft(2, '0')}:'
        '${clock.minute.toString().padLeft(2, '0')}';
    final elapsed = session.elapsedClockAt(now);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          const SleepMoonOrbit(size: 132, live: true),
          const SizedBox(height: 24),
          Text(
            hhmm,
            style: const TextStyle(
              fontSize: 13,
              letterSpacing: 1.6,
              color: NightStyle.clockText,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            elapsed,
            style: AppTheme.num(
              context,
              size: 46,
              weight: FontWeight.w500,
              letterSpacing: 1.1,
              color: NightStyle.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            '已进入睡眠模式',
            style: TextStyle(fontSize: 12, color: NightStyle.textFaint),
          ),
        ],
      ),
    );
  }
}

///
/// 只有两种操作会产生它：点了开始就立刻点结束，或者点了开始忘了结束、放了好几天。
/// 两种都不该静默变成一条睡眠记录，所以这里**不落库**，让用户自己选。
class _RejectedSheet extends StatelessWidget {
  const _RejectedSheet({required this.rejection, required this.onDiscard});

  final SessionFinishRejection rejection;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final tooShort = rejection == SessionFinishRejection.tooShort;

    return AppSheet(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tooShort ? '这次会话太短' : '这次会话超过 24 小时',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: tokens.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              tooShort
                  ? '还没有睡够一分钟，先不记录。如果你是刚点错了，丢弃它就好。'
                  : '看起来是忘了结束睡眠。这么长的记录多半不是真的，'
                      '与其写一条不可信的时长，不如你自己补上准确的那一晚。',
              textAlign: TextAlign.center,
              style:
                  TextStyle(fontSize: 13, height: 1.5, color: tokens.textMuted),
            ),
            const SizedBox(height: 20),
            PrimaryAction(
              label: '手动补录某一晚',
              onTap: () {
                Navigator.of(context).pop();
                context.push('/log/new');
              },
            ),
            const SizedBox(height: 10),
            Pressable(
              onTap: onDiscard,
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  '丢弃这次会话',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: tokens.danger,
                  ),
                ),
              ),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
          ],
        ),
      ),
    );
  }
}

void _collapse(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go('/');
  }
}
