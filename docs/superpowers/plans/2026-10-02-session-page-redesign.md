# 会话页改版实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把「正在睡眠」页重排成:圆环 → 按住结束按钮 → 常驻设定开关 → 白噪音展开区,结束方式由点击改为按住 1.5 秒。

**Architecture:** 不改数据层、不改会话生命周期,只动 `features/session/presentation/` 的呈现层。原来的 `SessionDrawer` 拆成两个 widget:常驻的 `SessionSettingsSection`(起床闹钟 + 鼾声/梦话)与可展开的 `SessionNoiseSection`(白噪音 + 说明);结束按钮抽成独立的 `HoldToFinishButton`(原始指针事件驱动 `AnimationController`,外圈画进度弧)。

**Tech Stack:** Flutter 3.47.5 / Dart 3 / Riverpod / Drift(仅读设置)/ go_router。

**设计出处:** `docs/superpowers/specs/2026-09-30-sleep-session-design.md` §四(已原地更新)。

## Global Constraints

- 界面文案、注释、文档**一律中文**;代码标识符英文。
- 设计令牌只有一份(`AppTokens` / `AppRadii` / `AppDurations` / `AppMotion`,见 `lib/core/theme/app_tokens.dart`)。颜色、圆角、曲线、时长都从令牌取,**不在 widget 里写死**。
- 不碰 `lib/**/*.g.dart`(Drift 生成,已 gitignore)。
- 产品红线,**一个字都不许改**:
  - 鼾声开关旁必须带 `'尚未接入录音,开关只保存偏好。'`(偏差 #7)。
  - 投递强度标注必须用 `ReminderScheduler.wakeAlarmDeliveryNote` 这份字面量,不另抄一遍。
  - 空状态、时长守门 `(0, 24h]` 不落库、评星、丢弃、收起、白噪音生命周期(收起展开区/离开页面继续响)全部原样保留。
- 每条任务结束时跑一次 `flutter test test/sleep_session_page_test.dart test/hold_to_finish_button_test.dart`;Task 4 跑全量。

---

### Task 1: 按住结束按钮 `HoldToFinishButton`

**Files:**
- Create: `lib/features/session/presentation/widgets/hold_to_finish_button.dart`
- Test: `test/hold_to_finish_button_test.dart`

**Interfaces:**
- Produces:
  - `class HoldToFinishButton extends StatefulWidget`
  - 构造:`HoldToFinishButton({Key? key, required VoidCallback onFinish, VoidCallback? onHint, Duration holdDuration = const Duration(milliseconds: 1500), double size = 104})`

**背景(实现者必须知道):** 进度必须**按下即开始**。用 `GestureDetector.onLongPressStart` 不行——`LongPressGestureRecognizer` 要等 500ms 长按超时才回调,按住之后要愣一下才动。改用 `Listener` 的原始指针事件:它不进手势竞技场,在 `ListView` 里也不会和滚动手势抢。

- [ ] **Step 1: 写失败的测试**

新建 `test/hold_to_finish_button_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/core/theme/app_theme.dart';
import 'package:night_sleep/features/session/presentation/widgets/hold_to_finish_button.dart';

void main() {
  Future<void> pumpButton(
    WidgetTester tester, {
    required VoidCallback onFinish,
    VoidCallback? onHint,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Center(
            child: HoldToFinishButton(onFinish: onFinish, onHint: onHint),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('按住满 1.5 秒触发结束', (tester) async {
    var finished = 0;
    await pumpButton(tester, onFinish: () => finished++);

    final gesture = await tester.press(find.byType(HoldToFinishButton));
    await tester.pump(const Duration(milliseconds: 1600));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(finished, 1);
  });

  testWidgets('没按满就松手不结束', (tester) async {
    var finished = 0;
    await pumpButton(tester, onFinish: () => finished++);

    final gesture = await tester.press(find.byType(HoldToFinishButton));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(finished, 0, reason: '松开时环没满,不该结束会话');
  });

  testWidgets('短按只给提示,不结束', (tester) async {
    var finished = 0;
    var hints = 0;
    await pumpButton(
      tester,
      onFinish: () => finished++,
      onHint: () => hints++,
    );

    await tester.tap(find.byType(HoldToFinishButton));
    await tester.pumpAndSettle();

    expect(finished, 0);
    expect(hints, 1, reason: '短按要告诉用户「按住不放」才有效');
  });

  testWidgets('按住后滑开再松手不结束', (tester) async {
    var finished = 0;
    await pumpButton(tester, onFinish: () => finished++);

    final gesture = await tester.press(find.byType(HoldToFinishButton));
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.moveBy(const Offset(0, -80));
    await tester.pump(const Duration(milliseconds: 1600));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(finished, 0, reason: '手指滑开了就该作废,躺着翻身蹭到也能反悔');
  });
}
```

- [ ] **Step 2: 跑测试,确认失败**

Run: `flutter test test/hold_to_finish_button_test.dart`
Expected: FAIL — `Target of URI doesn't exist` / `HoldToFinishButton isn't defined`。

- [ ] **Step 3: 写实现**

新建 `lib/features/session/presentation/widgets/hold_to_finish_button.dart`:

```dart
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/platform/haptics.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/widgets/glass_surface.dart';

/// 「结束睡眠」:按住不放,外圈进度环扫满才生效。
///
/// **为什么不是点击 + 确认弹窗**:结束睡眠是躺下之后才会做的动作,误触代价高,
/// 需要一道闸;但确认弹窗把「停」和「收尾」拆成两个接连的弹窗,而按住确认把它
/// 压回一个动作(规格 §四「结束:按住 1.5 秒」)。
///
/// **进度按下即开始**:用 [Listener] 的原始指针事件驱动,不走
/// `GestureDetector.onLongPressStart`——后者要等 500ms 的长按超时才触发,按住
/// 之后要愣一下才动。原始指针事件不进手势竞技场,因此嵌在滚动视图里也不会与
/// 滚动手势抢。
class HoldToFinishButton extends StatefulWidget {
  const HoldToFinishButton({
    super.key,
    required this.onFinish,
    this.onHint,
    this.holdDuration = const Duration(milliseconds: 1500),
    this.size = 104,
  });

  /// 环扫满之后调一次。
  final VoidCallback onFinish;

  /// 短按(没按满就抬手)时调一次,用来提示「按住不放」。
  final VoidCallback? onHint;

  /// 环扫满所需时长。
  final Duration holdDuration;

  /// 含外圈的直径。
  final double size;

  @override
  State<HoldToFinishButton> createState() => _HoldToFinishButtonState();
}

class _HoldToFinishButtonState extends State<HoldToFinishButton>
    with SingleTickerProviderStateMixin {
  static const _stroke = 3.5;
  static const _gap = 6.0;

  /// 松手时进度低于这个值就当作「短按」,而不是「按到一半反悔」。
  static const _tapThreshold = 0.2;

  /// 指针离开按下点这么远就作废。
  static const _slop = 24.0;

  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: widget.holdDuration,
  );

  /// 已经触发过结束,等这次抬手收尾——不让它再被当成短按。
  bool _fired = false;

  /// 指针已经滑开,这次按住作废。
  bool _abandoned = false;

  Offset? _downAt;

  @override
  void initState() {
    super.initState();
    _progress.addStatusListener(_onStatus);
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _fired = true;
    // 先复位:评星那一步可以跳过、弹层也可以直接关掉,按钮不该卡在满圈。
    _progress.value = 0;
    // 动画状态回调跑在 transient 回调阶段,push 路由挪到帧尾更稳。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onFinish();
    });
  }

  void _onDown(PointerDownEvent event) {
    _abandoned = false;
    _downAt = event.position;
    _progress.forward();
  }

  void _onMove(PointerMoveEvent event) {
    final downAt = _downAt;
    if (_abandoned || downAt == null) return;
    if ((event.position - downAt).distance <= _slop) return;
    _abandoned = true;
    _progress.reverse();
  }

  void _onUp() {
    _downAt = null;
    if (_fired) {
      _fired = false;
      return;
    }
    if (_abandoned) return;
    if (_progress.value < _tapThreshold) _hint();
    _progress.reverse();
  }

  void _hint() {
    AppHaptics.tap();
    widget.onHint?.call();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final inner = widget.size - 2 * (_stroke + _gap);

    return Semantics(
      label: '结束睡眠',
      hint: '按住不放,圆环填满即结束',
      button: true,
      onTap: _hint,
      onLongPress: widget.onFinish,
      child: Listener(
        onPointerDown: _onDown,
        onPointerMove: _onMove,
        onPointerUp: (_) => _onUp(),
        onPointerCancel: (_) {
          _downAt = null;
          _progress.reverse();
        },
        child: AnimatedBuilder(
          animation: _progress,
          builder: (context, child) => SizedBox(
            width: widget.size,
            height: widget.size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: Size.square(widget.size),
                  painter: _HoldRingPainter(
                    progress: _progress.value,
                    color: tokens.danger,
                    trackColor: tokens.bgMuted,
                    stroke: _stroke,
                  ),
                ),
                // 按下时轻微收缩,与全 App 的按压缩放同一口径。
                Transform.scale(
                  scale: 1 - 0.03 * _progress.value,
                  child: child,
                ),
              ],
            ),
          ),
          child: GlassSurface(
            borderRadius: BorderRadius.circular(inner / 2),
            expandWidth: false,
            padding: EdgeInsets.zero,
            borderColor: tokens.danger.withValues(alpha: 0.38),
            child: SizedBox(
              width: inner,
              height: inner,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AppIcons.sun(
                      size: 18, color: tokens.danger, strokeWidth: 1.9),
                  const SizedBox(height: 6),
                  Text(
                    '结束',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: tokens.danger,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 外圈那条进度弧。画法与 `wake_dial.dart` 的 `_DialPainter` 同款:
/// 从 12 点起顺时针,`StrokeCap.round`。
class _HoldRingPainter extends CustomPainter {
  const _HoldRingPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
    required this.stroke,
  });

  final double progress;
  final Color color;
  final Color trackColor;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - stroke) / 2;
    final rect = Rect.fromCircle(center: centre, radius: radius);

    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = trackColor,
    );

    if (progress <= 0) return;

    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * progress.clamp(0.0, 1.0),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_HoldRingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.stroke != stroke;
}
```

- [ ] **Step 4: 跑测试,确认通过**

Run: `flutter test test/hold_to_finish_button_test.dart`
Expected: PASS(4 条)。

若「按住满 1.5 秒触发结束」报 `finished` 为 0,先确认 `addPostFrameCallback` 那一帧确实跑了
(`tester.pump(1600ms)` 会跑帧尾回调),再确认 `press` 之后 `_onDown` 收到了 `PointerDownEvent`。

- [ ] **Step 5: 格式化与静态检查**

Run: `dart format lib/features/session/presentation/widgets/hold_to_finish_button.dart test/hold_to_finish_button_test.dart && flutter analyze`
Expected: 无告警。

- [ ] **Step 6: 提交**

```bash
git add lib/features/session/presentation/widgets/hold_to_finish_button.dart test/hold_to_finish_button_test.dart
git commit -m "feat(session): 新增按住 1.5 秒才生效的结束按钮"
```

---

### Task 2: 把 `SessionDrawer` 拆成常驻设定区与白噪音展开区

**Files:**
- Create: `lib/features/session/presentation/widgets/session_settings_section.dart`
- Create: `lib/features/session/presentation/widgets/session_noise_section.dart`
- Modify: `lib/features/session/presentation/sleep_session_page.dart`(暂时仍按旧的「点摘要条展开抽屉」版式接线)
- Delete(在 Task 3 末尾): `lib/features/session/presentation/widgets/session_drawer.dart`

**Interfaces:**
- Consumes: Task 1 的 `HoldToFinishButton`(本任务先不接)。
- Produces:
  - `class SessionSettingsSection extends ConsumerStatefulWidget` — `SessionSettingsSection({Key? key, required SleepSession session, required DateTime now})`。自渲染 `SectionHeader('今晚的设定')`。
  - `class SessionNoiseSection extends ConsumerWidget` — `SessionNoiseSection({Key? key})`。自渲染 `SectionHeader('助眠音效')` 与说明块。

**为什么拆:** 旧的 `SessionDrawer` 一份代码里塞了三件事(常驻设定、白噪音、说明),而改版后只有白噪音可收展。拆开后「常驻」与「可展开」在类型上就分开了,页面接错也看得出来。

本任务**只搬运,不改版式**:页面继续用 `_SettingsSummary` 开合,只是开合的内容从 `SessionDrawer` 换成这两个 widget。跑完测试应当仍然全绿(除了下面指定的两条断言微调)。

- [ ] **Step 1: 写设定区**

新建 `lib/features/session/presentation/widgets/session_settings_section.dart`。
内容从 `session_drawer.dart` 的「今晚的设定」区块**整体搬过来**,再补上闹钟状态行:

```dart
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/reminder_permission.dart';
import '../../../../app/reminder_sync.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/platform/reminders.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/app_basics.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/widgets/ios_controls.dart';
import '../../../../core/widgets/wheel_picker.dart';
import '../../../sleep/data/session_repository.dart';
import '../../../sleep/domain/sleep_session.dart';

/// 会话页常驻的「今晚的设定」:起床闹钟与鼾声/梦话记录。
///
/// 两个开关常驻在结束按钮下方,不藏进展开区——它们是睡前就该确认的设定,
/// 「先展开再关开关」那条路在躺下之后太长(规格 §四)。
///
/// **闹钟那一行合并了旧版胶囊的三条信息**:剩余时间、已关提示、投递强度标注。
/// 同一件事只留一处显示,也顺带消掉「上方日晷写已超过、下方写还有 0h 0m」那种打架。
class SessionSettingsSection extends ConsumerStatefulWidget {
  const SessionSettingsSection({
    super.key,
    required this.session,
    required this.now,
  });

  final SleepSession session;
  final DateTime now;

  @override
  ConsumerState<SessionSettingsSection> createState() =>
      _SessionSettingsSectionState();
}

class _SessionSettingsSectionState
    extends ConsumerState<SessionSettingsSection> {
  bool _recordingEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadRecordingPref();
  }

  /// 只读一次偏好,**不订阅** `settingsProvider` 那条 drift 流:widget 测试的假时钟
  /// 不推进,订阅 `watch*` 会留下 pending timer(见 `.claude/skills/flutter-pitfalls`)。
  Future<void> _loadRecordingPref() async {
    final settings = await ref.read(databaseProvider).getSettings();
    if (!mounted) return;
    setState(() => _recordingEnabled = settings.soundRecordingEnabled);
  }

  Future<void> _pickWakeTime() async {
    var draft = minutesToClock(widget.session.wakeMinutes);

    // 只有「完成」才提交草稿。滚了轮再点取消不该落库。
    final confirmed = await showPickerSheet(
      context: context,
      title: '起床闹钟',
      child: AppTimePicker(
        value: draft,
        onChanged: (value) => draft = value,
      ),
    );
    if (confirmed != true) return;

    await ref
        .read(sessionRepositoryProvider)
        .update(wakeMinutes: clockToMinutes(draft));
    // 闹钟开着时,改了时刻要立刻重排——否则它会按旧时刻响。
    await _resyncAlarm();
  }

  /// 鼾声/梦话是**跨会话的偏好**,写的是 `AppSettings` 里那个唯一字段。
  Future<void> _toggleRecording(bool value) async {
    await ref.read(databaseProvider).updateSettings(
          AppSettingsCompanion(soundRecordingEnabled: Value(value)),
        );
    if (!mounted) return;
    setState(() => _recordingEnabled = value);
  }

  Future<void> _toggleAlarm(bool value) async {
    // 与设置页同一个闸口:被拒(或平台安排不了)时不写入会话,开关自己弹回去。
    if (value &&
        !await ensureNotificationPermission(context, ref, target: '闹钟')) {
      return;
    }

    await ref.read(sessionRepositoryProvider).update(alarmEnabled: value);
    await _resyncAlarm();
  }

  /// 走 [syncAllReminders] 而不是直接调 [ReminderScheduler.syncAlarm]:日常提醒与会话
  /// 闹钟必须成对推导。只调 `syncAlarm` 时它能让日常起床提醒 9002 让位,却永远不会把
  /// 9002 排回来——闹钟一关,日常起床提醒也跟着不响。
  Future<void> _resyncAlarm() => syncAllReminders(
        ref.read(databaseProvider),
        ref.read(reminderSchedulerProvider),
      );

  /// 闹钟状态的措辞。剩余量的口径只有模型一份(`remainingLabelAt`):这里不再自己
  /// 夹到 0,否则同一屏上方日晷说「已超过起床时间 42m」、下方说「还有 0h 0m」。
  String get _alarmStatus {
    if (!widget.session.alarmEnabled) return '已关闭 · 自然醒后手动结束';
    final remaining = widget.session.remainingLabelAt(widget.now);
    if (remaining == null) return '已过起床时间 · 请手动结束睡眠';
    return '还有 $remaining';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final session = widget.session;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('今晚的设定'),
        IosListGroup(
          children: [
            IosListItem(
              child: Row(
                children: [
                  ListIconBadge(
                    background: tokens.accentSoft,
                    child: AppIcons.clock(
                        size: 16, color: tokens.accent, strokeWidth: 1.8),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '起床闹钟',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: tokens.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Pressable(
                              haptic: false,
                              isButton: false,
                              onTap: _pickWakeTime,
                              child: Text(
                                minutesToClock(session.wakeMinutes),
                                style: AppTheme.num(
                                  context,
                                  size: 12,
                                  weight: FontWeight.w600,
                                  color: tokens.accentViolet,
                                ),
                              ),
                            ),
                            Text(
                              ' · ${_alarmStatus}',
                              style: TextStyle(
                                fontSize: 12,
                                color: tokens.textMuted,
                              ),
                            ),
                          ],
                        ),
                        // 投递强度的如实标注就贴在开关这一行——用户正是在这里做决定。
                        if (session.alarmEnabled) ...[
                          const SizedBox(height: 6),
                          Text(
                            ReminderScheduler.wakeAlarmDeliveryNote,
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.45,
                              color: tokens.textMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IosToggle(
                    value: session.alarmEnabled,
                    semanticLabel: '起床闹钟',
                    onChanged: _toggleAlarm,
                  ),
                ],
              ),
            ),
            IosListItem(
              child: Row(
                children: [
                  ListIconBadge(
                    background: tokens.accentViolet.withValues(alpha: 0.09),
                    child: AppIcons.snore(
                        size: 16, color: tokens.accentViolet, strokeWidth: 1.8),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '鼾声/梦话记录',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: tokens.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        // plan A 阶段录音还没接入,如实标注。plan B 落地时删掉这句,
                        // 换成真实状态(规格 §六)。
                        Text(
                          '尚未接入录音,开关只保存偏好。',
                          style:
                              TextStyle(fontSize: 12, color: tokens.textMuted),
                        ),
                      ],
                    ),
                  ),
                  IosToggle(
                    value: _recordingEnabled,
                    semanticLabel: '鼾声/梦话记录',
                    onChanged: _toggleRecording,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: 写白噪音区**

新建 `lib/features/session/presentation/widgets/session_noise_section.dart`,`session_drawer.dart` 的「助眠音效」+「说明」两块**整体搬过来**:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/noise_session.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/app_basics.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/widgets/ios_controls.dart';
import '../../../sleep/presentation/widgets/noise_controls.dart';

/// 会话页展开区里的白噪音设定:八宫格 + 音量 + 定时,外加后台播放的如实标注。
///
/// 白噪音**不归它播放**:播放器与倒计时挂在 [noiseSessionControllerProvider] 上,
/// 生命周期比这一页长——收起展开区不会静音(使用方裁定,见 [NoiseSessionController])。
class SessionNoiseSection extends ConsumerWidget {
  const SessionNoiseSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTokens.of(context);
    final noise = ref.watch(noiseSessionControllerProvider);
    final remaining = noise.remainingLabel;
    final failure = noise.failure;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('助眠音效'),
        IosListGroup(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final option in kNoiseOptions)
                        NoiseTile(
                          option: option,
                          active: option.id == noise.activeId,
                          onTap: () => noise.select(option),
                          // 四列:(宽度 - 三个间隔) / 4。
                          width: (MediaQuery.sizeOf(context).width - 110) / 4,
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  VolumeSlider(
                    value: noise.volume,
                    color: noise.activeOption?.color ?? tokens.accent,
                    onChanged: noise.changeVolume,
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      AppIcons.timer(
                          size: 14, color: tokens.textMuted, strokeWidth: 1.8),
                      const SizedBox(width: 6),
                      Text(
                        '定时关闭',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.96,
                          color: tokens.textMuted,
                        ),
                      ),
                      if (remaining != null) ...[
                        const Spacer(),
                        Text(
                          '剩余 $remaining',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: tokens.accent,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final minutes in NoiseSessionController.timerChoices)
                        TimerChip(
                          label: '${minutes}m',
                          selected: noise.timerMinutes == minutes,
                          onTap: () => noise.selectTimer(minutes),
                        ),
                    ],
                  ),
                  if (failure != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      failure,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.45,
                        color: tokens.danger,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const SectionHeader('说明'),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: tokens.bgMuted,
            borderRadius: BorderRadius.circular(AppRadii.panel),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppIcons.volume(
                  size: 15, color: tokens.textMuted, strokeWidth: 1.6),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '退到后台或锁屏后声音会停(后台播放未接入)。',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: tokens.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 3: 页面接线(版式暂不动)**

改 `sleep_session_page.dart`:

1. 删掉 `import 'widgets/session_drawer.dart';`,改成两个新 widget 的 import。
2. `_SessionBody` 的 `drawerOpen` 分支里,`SessionDrawer(session: session)` 换成:

```dart
        if (drawerOpen) ...[
          const SizedBox(height: 14),
          SessionSettingsSection(session: session, now: now),
          const SizedBox(height: 18),
          const SessionNoiseSection(),
        ],
```

3. 删掉 `_AlarmChip` 类(它的三条信息已并进 `SessionSettingsSection`),同时删掉 `_BedWakeRow` 下方
   `if (!drawerOpen) ... _AlarmChip(...)` 那段。

- [ ] **Step 4: 微调两条受影响断言**

在 `test/sleep_session_page_test.dart` 里:

- `闹钟开着时报剩余时间,并带上后台投递的如实标注`:
  `expect(find.text('起床闹钟已开 · 还有 4h 4m'), findsOneWidget);`
  → `expect(find.textContaining('还有 4h 4m'), findsOneWidget);`
  并在其下补一条收合态断言:

```dart
    // 收合态就必须看得见剩余量——闹钟那一行常驻在结束按钮下方。
    expect(find.text('还有 4h 4m'), findsOneWidget,
        reason: '开合与否都在,不再依赖展开抽屉');
```

  同时删掉该用例里「必须先展开抽屉」的注释语境(它现在断言的是常驻内容)。

- `超过起床时间后闹钟胶囊说「已过」,不再说「还有 0h 0m」`:
  `expect(find.text('起床闹钟已过 · 请手动结束睡眠'), findsOneWidget);`
  → `expect(find.text('已过起床时间 · 请手动结束睡眠'), findsOneWidget);`

- [ ] **Step 5: 跑测试**

Run: `flutter test test/sleep_session_page_test.dart`
Expected: PASS。此时 `session_drawer.dart` 还在树上被引用吗?**不在**——第 3 步已经换掉了引用,
所以本步骤之后可以删文件,但那留到 Task 3(先确认两个新 widget 跑得通)。

- [ ] **Step 6: 提交**

```bash
git add lib/features/session/presentation/widgets/session_settings_section.dart lib/features/session/presentation/widgets/session_noise_section.dart lib/features/session/presentation/sleep_session_page.dart test/sleep_session_page_test.dart
git commit -m "refactor(session): 会话抽屉拆成常驻设定区与白噪音展开区"
```

---

### Task 3: 页面重排 + 常驻开关 + 展开动画

**Files:**
- Modify: `lib/features/session/presentation/sleep_session_page.dart`
- Delete: `lib/features/session/presentation/widgets/session_drawer.dart`
- Modify: `test/sleep_session_page_test.dart`

- [ ] **Step 1: 改页面状态与接线**

`sleep_session_page.dart` 里:

1. 字段 `bool _drawerOpen = false;` → `bool _noiseOpen = false;`(注释同步改成
   「白噪音展开区开着没。它不占圆环的位置——圆环、结束按钮与常驻开关都不动」)。
2. `_SessionBody` 的参数 `drawerOpen` / `onToggleDrawer` → `noiseOpen` / `onToggleNoise`;
   新增 `onHint`。
3. `build` 里传给 `_SessionBody`:

```dart
              : _SessionBody(
                  session: session,
                  now: _now,
                  noiseOpen: _noiseOpen,
                  onToggleNoise: () =>
                      setState(() => _noiseOpen = !_noiseOpen),
                  onFinish: () => _finish(session),
                  onFinishHint: () => ref
                      .read(toastProvider.notifier)
                      .show('按住不放,圆环填满才结束。'),
                ),
```

4. `_SessionBody` 的 `children` 整段替换为:

```dart
      children: [
        Row(
          children: [
            _CollapsePill(onTap: () => _collapse(context)),
            const Spacer(),
            Text(
              '夜深 · 睡眠中',
              style: TextStyle(fontSize: 12, color: tokens.textMuted),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          '正在睡眠',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            color: tokens.textPrimary,
          ),
        ),
        const SizedBox(height: 14),
        // 圆环始终在视野里:白噪音展开区在摘要条下方撑开,不让位。
        Center(
          child: WakeDial(
            progress: session.progressAt(now),
            label: session.elapsedLabelAt(now),
            sublabel: overdue
                ? '已超过起床时间 ${session.overdueLabelAt(now)}'
                : '已入睡',
            semanticLabel: overdue
                ? '已睡 ${session.elapsedLabelAt(now)},'
                    '已超过起床时间 ${session.overdueLabelAt(now)}'
                : '已睡 ${session.elapsedLabelAt(now)}',
          ),
        ),
        const SizedBox(height: 22),
        _BedWakeRow(session: session),
        const SizedBox(height: 22),
        // 结束按钮紧跟圆环:它是这一页唯一的出口,也是拇指最顺的位置。
        Center(
          child: HoldToFinishButton(
            onFinish: onFinish,
            onHint: onFinishHint,
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: Text(
            '按住不放',
            style: TextStyle(fontSize: 12, color: tokens.textMuted),
          ),
        ),
        const SizedBox(height: 24),
        SessionSettingsSection(session: session, now: now),
        const SizedBox(height: 16),
        _NoiseSummaryBar(
          session: session,
          open: noiseOpen,
          onTap: onToggleNoise,
        ),
        AnimatedSize(
          duration: AppDurations.standard,
          curve: AppMotion.standardCurve,
          alignment: Alignment.topCenter,
          child: noiseOpen
              ? const Padding(
                  padding: EdgeInsets.only(top: 14),
                  child: SessionNoiseSection(),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
```

5. 参数表加上 `required this.onFinishHint` 与 `final VoidCallback onFinishHint;`。

- [ ] **Step 2: 换掉摘要条**

把 `_SettingsSummary` 整个类替换成 `_NoiseSummaryBar`(只改名字与措辞,结构与样式不动):

```dart
/// 白噪音摘要条,同时也是展开区的把手。
///
/// **点它开合**,不做纯上拉手势——躺着的时候拖拽不好使(规格 §四)。
/// 它始终留在页面上:展开后点同一条即可收起,脚下的圆环与常驻开关不会跟着消失。
class _NoiseSummaryBar extends StatelessWidget {
  const _NoiseSummaryBar({
    required this.session,
    required this.open,
    required this.onTap,
  });

  final SleepSession session;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final percent = (session.noiseVolume * 100).round();

    return GlassSurface(
      borderRadius: BorderRadius.circular(AppRadii.panel),
      onTap: onTap,
      semanticLabel: open ? '收起白噪音设定' : '展开白噪音设定',
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          AppIcons.volume(size: 16, color: tokens.accent, strokeWidth: 1.7),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '白噪音 · 音量 $percent%',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: tokens.textPrimary,
              ),
            ),
          ),
          Text(
            open ? '收起' : '更多',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: tokens.accent,
            ),
          ),
          const SizedBox(width: 4),
          AnimatedRotation(
            turns: open ? 0.5 : 0,
            duration: AppDurations.springy,
            curve: AppMotion.standardCurve,
            child: AppIcons.chevronDown(
              size: 16,
              color: tokens.textMuted,
              strokeWidth: 2,
            ),
          ),
        ],
      ),
    );
  }
}
```

注:原来的抽屉把手(那条 40×4 的小横杠)随抽屉概念一起删掉;箭头由 `chevronUp`/`chevronDown`
两选一改成同一个 `chevronDown` 旋转 180°,过渡才连贯。

- [ ] **Step 3: 删掉旧文件**

```bash
rm lib/features/session/presentation/widgets/session_drawer.dart
```

- [ ] **Step 4: 改写测试夹具与结束流程用例**

在 `test/sleep_session_page_test.dart` 里加一个夹具,并把所有结束流程的入口换掉:

```dart
  /// 按住「结束睡眠」到圆环填满。
  ///
  /// 这里显式推够 1.6 秒,而不是用 `tap`:结束按钮按下即开始计时,`tap` 的按下—抬起
  /// 间隔远不够填满圆环,测出来的是「没按满」那条路径。
  Future<void> holdToFinish(WidgetTester tester) async {
    final gesture = await tester.press(find.byType(HoldToFinishButton));
    await tester.pump(const Duration(milliseconds: 1600));
    await gesture.up();
    await tester.pumpAndSettle();
  }
```

把下列用例里的 `await tester.tap(find.text('结束睡眠'));` + `await tester.pumpAndSettle();`
两行,替换为一行 `await holdToFinish(tester);`:

- `结束睡眠先问一次星级`
- `跳过评星:记录落库但质量为 null 且没有评分`
- `评了分:质量写进记录`
- `时长过短不落库,给出说明与两个出口`
- `时长越界的出口通往手动补录页`
- `时长超过 24 小时同样不落库`
- `收尾失败不影响记录、反馈与跳转`
- `丢弃这次会话:不写记录、会话消失、闹钟一并重排`

把断言 `expect(find.text('结束睡眠'), findsNothing)`(共 4 处)改为
`expect(find.byType(HoldToFinishButton), findsNothing)`。

- [ ] **Step 5: 新增三条用例**

```dart
  testWidgets('没按满就松手不结束会话', (tester) async {
    final start = DateTime(2026, 8, 30, 23, 14);
    await pumpSession(
      tester,
      session: sessionAt(start),
      now: start.add(const Duration(hours: 7, minutes: 48)),
    );

    final gesture = await tester.press(find.byType(HoldToFinishButton));
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('昨晚睡得怎么样?'), findsNothing, reason: '环没满就走到了评星,等于守门失效');
    expect(await database.allRecords(), isEmpty);
    expect(find.byType(HoldToFinishButton), findsOneWidget, reason: '会话页还在');
  });

  testWidgets('短按结束按钮只给提示,不结束', (tester) async {
    final start = DateTime(2026, 8, 30, 23, 14);
    await pumpSession(
      tester,
      session: sessionAt(start),
      now: start.add(const Duration(hours: 7, minutes: 48)),
    );

    await tester.tap(find.byType(HoldToFinishButton));
    await tester.pumpAndSettle();

    expect(await database.allRecords(), isEmpty);
    expect(
      ProviderScope.containerOf(tester.element(find.byType(SleepSessionPage)))
          .read(toastProvider),
      contains('按住不放'),
      reason: '短按必须告诉用户正确的操作方式',
    );
  });

  testWidgets('设定开关常驻,点摘要条才展开白噪音区', (tester) async {
    final start = DateTime(2026, 8, 30, 23, 14);
    await pumpSession(
      tester,
      session: sessionAt(start),
      now: start.add(const Duration(hours: 1)),
    );

    // 收合态:设定开关已经看得见,白噪音区还没出现。
    expect(find.text('今晚的设定'), findsOneWidget);
    expect(find.text('起床闹钟'), findsOneWidget);
    expect(find.text('鼾声/梦话记录'), findsOneWidget);
    expect(find.text('尚未接入录音,开关只保存偏好。'), findsOneWidget);
    expect(find.text('15m'), findsNothing, reason: '白噪音区应还收着');

    await tester.tap(find.textContaining('白噪音 · 音量'));
    await tester.pumpAndSettle();

    expect(find.text('助眠音效'), findsOneWidget);
    expect(find.text('15m'), findsOneWidget);
    expect(find.textContaining('退到后台或锁屏后声音会停'), findsOneWidget);
  });
```

- [ ] **Step 6: 调整其余受影响用例**

- `显示已睡时长与设定的起床时间`:`expect(find.text('07:00'), findsOneWidget);`
  → `expect(find.text('07:00'), findsNWidgets(2), reason: '上方「入睡─闹钟」行与下方设定行各一处');`
- `入睡与闹钟时刻都补零到两位`:`expect(find.text('06:05'), findsOneWidget);`
  → `expect(find.text('06:05'), findsNWidgets(2));`
- `点摘要条展开抽屉,四组设定都在` → 删掉(已被 Step 5 的新用例取代)。
- `抽屉里的白噪音定时最长 60 分钟,没有「不限」与 90m` → 改名
  `展开区里的白噪音定时最长 60 分钟,没有「不限」与 90m`,正文不变。
- `鼾声/梦话开关带上「尚未接入录音」的说明(plan A)` → 删掉展开抽屉那两行,
  直接断言 `find.textContaining('尚未接入录音')` 为 `findsOneWidget`。
- `白噪音区注明后台播放未接入` → 保留展开动作(说明块在展开区里),正文不变。
- `拨动鼾声开关会写回设置` → 删掉展开抽屉那两行,直接 `tester.tap(toggleLabeled('鼾声/梦话记录'))`。
- `抽屉里闹钟开着时,投递强度标注就在那一行` → 改名
  `闹钟开着时,投递强度标注就在那一行`;断言收合态 `findsOneWidget`,展开白噪音区后再断言仍是
  `findsOneWidget`(标注只有一处,不随开合增减)。
- `闹钟开关被拒时回弹,且不写入会话的 alarmEnabled` → 删掉展开抽屉那两行,
  直接 `tester.tap(toggleLabeled('起床闹钟'))`。
- 其余白噪音用例(`选中白噪音会交给播放器` / `倒计时到点会停掉` / `收起抽屉不会停掉正在播放的白噪音`
  / `pop 掉会话页后白噪音继续响`)里,`find.textContaining('白噪音')` 的点按保持不变——它现在点开的
  是展开区。把用例名与注释里的「抽屉」改成「展开区」。

- [ ] **Step 7: 跑测试**

Run: `flutter test test/sleep_session_page_test.dart`
Expected: PASS。

若 `设定开关常驻,点摘要条才展开白噪音区` 在 `find.textContaining('白噪音 · 音量')` 上报
`Too many elements`,确认收合态只有摘要条一处含「白噪音」(`SessionNoiseSection` 的区块头是
「助眠音效」,不是「白噪音」)。

- [ ] **Step 8: 格式化与静态检查**

Run: `dart format . && flutter analyze`
Expected: 无告警。

- [ ] **Step 9: 提交**

```bash
git add -A lib/features/session test/sleep_session_page_test.dart
git commit -m "feat(session): 会话页重排,结束按钮上移并改为按住确认"
```

---

### Task 4: 同步文档并全量校验

**Files:**
- Modify: `README.md`(第 67 行目录说明、第 94 行「睡眠会话」段、第 160 行)
- Modify: `CHANGELOG.md`(新增 3.1 条目)
- Modify: `docs/superpowers/specs/2026-09-28-night-sleep-design.md`(版本号行)

- [ ] **Step 1: 改 README**

- 第 67 行 `session/           睡眠会话页、设定抽屉、日晷圆环、就地评星`
  → `session/           睡眠会话页、常驻设定区、白噪音展开区、日晷圆环、就地评星`
- 第 94 行的「**睡眠会话**(v3.0)」段,把「点摘要条展开设定抽屉(起床闹钟 + 鼾声/梦话
  开关 + 白噪音八宫格/音量/定时 15/30/45/60)」改成:

  > 日晷圆环画「已过时长 ÷ 计划时长」、`入睡 ─── 闹钟` 行常驻;**起床闹钟与鼾声/梦话两个开关
  > 常驻在结束按钮下方**(鼾声那行照旧注明「尚未接入录音,开关只保存偏好」),点摘要条展开
  > 白噪音区(八宫格/音量/定时 15/30/45/60,带高度动画)。**结束睡眠是圆形按钮,按住不放、
  > 圆环扫满 1.5 秒才生效**;中途松手或手指滑开即作废,短按只给提示。

- 第 160 行「收合态胶囊与抽屉里的闹钟行**共用同一份字面量**」
  → 「投递强度标注在「起床闹钟」那一行,**只此一处**」。

- [ ] **Step 2: 改规格版本号**

`docs/superpowers/specs/2026-09-28-night-sleep-design.md` 第 3 行
`> 版本:3.0(2026-09-30)` → `> 版本:3.1(2026-10-02)`。

- [ ] **Step 3: 写 CHANGELOG**

在 `CHANGELOG.md` 的 `## 3.0(2026-09-30)` 之前插入:

```markdown
## 3.1(2026-10-02)

会话页按使用方要求重排,并参考潮汐那类助眠应用的「按住起床」手感。

**结束方式改了。** 「结束睡眠」从页面底部的玻璃长条改成**圆环正下方的圆形按钮**:按住不放、
外圈进度环顺时针扫满 1.5 秒才生效;中途松手或手指滑开即作废,短按只给一句提示与轻震动。
进度**按下即开始**(用原始指针事件驱动,不走 `onLongPressStart` 的 500ms 超时),因此按住时
立刻有反馈。原规格里那句「结束会话只有『结束睡眠』一个入口,避免误触」的目的不变,手段由
「藏起来」换成「按住才生效」。

**两个设定开关从抽屉里搬出来常驻。** 起床闹钟与鼾声/梦话记录现在就在结束按钮下方,不再需要
先展开面板;原先收合态那个闹钟胶囊承担的三条信息(剩余时间、已关提示、投递强度标注)全部并进
「起床闹钟」这一行,同一件事只留一处显示。鼾声那一行的「尚未接入录音,开关只保存偏好」一字未改
(偏差 #7 仍然有效)。白噪音区(八宫格 + 音量 + 定时 + 后台播放限制说明)改为点摘要条展开,
带 `AnimatedSize` 高度动画,箭头旋转;**展开时圆环、结束按钮与常驻开关都不动**(旧版展开即藏起
圆环)。`SessionDrawer` 随之拆成 `SessionSettingsSection` 与 `SessionNoiseSection`。

不变量一个没动:空状态、时长守门 `(0, 24h]` 不落库、就地评星、丢弃、收起、白噪音生命周期
(收起展开区乃至离开会话页都继续响)。

```

- [ ] **Step 4: 全量校验**

Run: `dart format . && flutter analyze && flutter test`
Expected: 全部通过。

- [ ] **Step 5: 提交**

```bash
git add README.md CHANGELOG.md docs/
git commit -m "docs(session): 同步会话页改版后的实现范围与变更史"
```

---

## Self-Review

**Spec coverage**(对照 `2026-09-30-sleep-session-design.md` §四):

| 规格要求 | 落在哪 |
| --- | --- |
| 圆环 → 结束按钮 → 常驻设定 → 摘要条 + 展开区 | Task 3 Step 1 |
| 圆形按钮 + 外圈进度环,按住 1.5 秒 | Task 1 |
| 松手未满 / 滑开 → 取消且无副作用 | Task 1 Step 1(用例 2、4) |
| 短按给提示 + 轻震动 | Task 1 Step 1(用例 3)、Task 3 Step 5 |
| 按下即开始(不等长按超时) | Task 1 用 `Listener` |
| 无障碍 `onLongPress` | Task 1 的 `Semantics` |
| 两个开关常驻 + 闹钟三条信息并进一行 | Task 2 Step 1 |
| 鼾声标注一字不改 | Task 2 Step 1、Task 3 Step 5 |
| 点摘要条开合 + 高度动画 + 箭头旋转 | Task 3 Step 1、Step 2 |
| 展开时圆环不让位 | Task 3 Step 1(圆环移出 `if (!drawerOpen)` 分支) |
| README / CHANGELOG / 版本号 | Task 4 |

**Placeholder scan:** 无 TBD / TODO;每个代码步骤都给了可落地的完整片段。

**Type consistency:** `HoldToFinishButton.onFinish` / `onHint` 在 Task 1 定义、Task 3 Step 1 调用;
`SessionSettingsSection({session, now})` 与 `SessionNoiseSection()` 在 Task 2 定义、Task 3 Step 1 调用;
`_NoiseSummaryBar({session, open, onTap})` 在 Task 3 Step 2 定义、Step 1 调用。名称一致。

**已知风险:** Task 1 的 `addPostFrameCallback` 若在测试里没被触发,「按住满 1.5 秒」会变红;
Plan 的 Step 4 已写了排查顺序。Task 3 的 `AnimatedSize` 若让 `pumpAndSettle` 不收敛,应改用显式
`pump()`——但该动画是有限时长的,按 `flutter-pitfalls` 的判断标准不该有问题。
