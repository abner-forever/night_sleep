import 'dart:ui' as ui;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/noise_session.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/platform/haptics.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_basics.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/widgets/ios_controls.dart';
import '../../../../core/widgets/wheel_picker.dart';
import '../../../sleep/presentation/widgets/noise_controls.dart';
import '../night_scene.dart';
import '../night_style.dart';
import '../sheets/night_noise_sheet.dart';
import 'collapse_pill.dart';
import 'night_scene_picker.dart';
import 'sleep_moon_mark.dart';

/// 「入睡前」态：原型 `SleepView` 的 `!active` 分支。
///
/// **它不记录任何东西。** 这一屏只是攒草稿——场景、常用白噪音、白噪音完整设置、
/// 起床闹钟、鼾声偏好；按下「开始睡眠」才由页面写会话行、开始计时（见
/// `sleep_session_page.dart` 的 `_beginSleep`）。所以这里的每一个开关都**不落库**，
/// 唯一例外是鼾声偏好：它本来就是跨会话的偏好（`AppSettings.soundRecordingEnabled`，
/// 规格偏差 #7 的「只有一个真相来源」），与有没有会话无关。
///
/// 数值取自原型 `index.css` 最终生效层那段 `/* ── Immersive sleep controls ── */`
/// （第 1730–1960 行）：shell 限宽 680、hero 最小高 230、轨道 102、
/// deck 圆角 28、控制行高 61、开始按钮高 58。
class SessionSetupBody extends ConsumerStatefulWidget {
  const SessionSetupBody({
    super.key,
    required this.scene,
    required this.alarmEnabled,
    required this.wakeMinutes,
    required this.onSceneChanged,
    required this.onAlarmToggled,
    required this.onWakeTimePicked,
    required this.onCollapse,
    required this.onStart,
    required this.scrollController,
  });

  /// 草稿：当前选中的夜景。
  final NightScene scene;

  /// 草稿：起床闹钟开着没有。
  final bool alarmEnabled;

  /// 草稿：起床时刻（距本地午夜的分钟）。
  final int wakeMinutes;

  final ValueChanged<NightScene> onSceneChanged;

  /// 开关的写回由页面做——权限闸口在那边，被拒时开关要弹回（草稿不许改）。
  final ValueChanged<bool> onAlarmToggled;

  final VoidCallback onWakeTimePicked;
  final VoidCallback onCollapse;
  final VoidCallback onStart;
  final ScrollController scrollController;

  @override
  ConsumerState<SessionSetupBody> createState() => _SessionSetupBodyState();
}

class _SessionSetupBodyState extends ConsumerState<SessionSetupBody> {
  bool _recordingEnabled = false;

  /// 原型的「常用白噪音」四格：`['rain','ocean','brown','fan']`，顺序照抄。
  static const _quickIds = ['rain', 'ocean', 'brown', 'fan'];

  @override
  void initState() {
    super.initState();
    _loadRecordingPref();
  }

  /// 与「当前睡眠事件」卡同款：只读一次，**不订阅** `settingsProvider` 那条 drift 流
  /// ——widget 测试的假时钟不推进，订阅 `watch*` 会留下 pending timer
  /// （见 `.claude/skills/flutter-pitfalls`）。
  Future<void> _loadRecordingPref() async {
    final settings = await ref.read(databaseProvider).getSettings();
    if (!mounted) return;
    setState(() => _recordingEnabled = settings.soundRecordingEnabled);
  }

  /// 鼾声/梦话是**跨会话的偏好**，写的是 `AppSettings` 里那个唯一字段。
  Future<void> _toggleRecording(bool value) async {
    await ref.read(databaseProvider).updateSettings(
          AppSettingsCompanion(soundRecordingEnabled: Value(value)),
        );
    if (!mounted) return;
    setState(() => _recordingEnabled = value);
  }

  @override
  Widget build(BuildContext context) {
    final noise = ref.watch(noiseSessionControllerProvider);
    final quick = [
      for (final id in _quickIds)
        kNoiseOptions.firstWhere((option) => option.id == id),
    ];

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        _header(),
        _hero(context),
        _deck(noise, quick),
        _startButton(),
        const Text(
          '屏幕将保持暗色，轻触夜景即可切换氛围',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            color: NightStyle.startNoteInk,
          ),
        ),
      ],
    );
  }

  Widget _header() {
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          CollapsePill(onTap: widget.onCollapse),
          const Expanded(
            child: Center(
              child: Text(
                '睡眠模式',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                  color: NightStyle.kickerInk,
                ),
              ),
            ),
          ),
          // 右侧留一块与「收起」等宽的空白，标题才真的落在整行正中
          // （原型用 `.sleep-header-spacer` 达到同一效果）。
          const SizedBox(width: 56),
        ],
      ),
    );
  }

  /// 晚安 → 准备好休息了吗？ → 放下今天，让夜晚慢下来。
  ///
  /// 最小高按原型的 `@media (min-height: 860px)` 取值：矮屏 230、高屏 285。
  Widget _hero(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: NightStyle.tallHero(context) ? 285 : 230,
      ),
      child: const Padding(
        padding: EdgeInsets.fromLTRB(0, 24, 0, 22),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SleepMoonOrbit(size: 102),
            SizedBox(height: 15),
            Text(
              '晚安',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.8,
                color: NightStyle.greetingInk,
              ),
            ),
            SizedBox(height: 5),
            Text(
              '准备好休息了吗？',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 29,
                fontWeight: FontWeight.w700,
                letterSpacing: -1.16, // -.04em × 29
                color: NightStyle.textPrimary,
              ),
            ),
            SizedBox(height: 7),
            Text(
              '放下今天，让夜晚慢下来。',
              style: TextStyle(fontSize: 14, color: NightStyle.heroBodyInk),
            ),
          ],
        ),
      ),
    );
  }

  /// 一张卡装下睡前全部设定：场景 / 常用白噪音 / 白噪音、闹钟、鼾声三行。
  Widget _deck(NoiseSessionController noise, List<NoiseOption> quick) {
    final selected = noise.activeId;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment(-0.7, -1),
          end: Alignment(0.7, 1),
          colors: [NightStyle.deckFillTop, NightStyle.deckFillBottom],
        ),
        borderRadius: BorderRadius.circular(NightStyle.deckRadius),
        border: Border.all(color: NightStyle.deckStroke),
        boxShadow: const [
          BoxShadow(
            color: NightStyle.deckShadow,
            offset: Offset(0, 20),
            blurRadius: 50,
          ),
        ],
      ),
      child: BackdropFilter(
        filter: _deckFilter(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NightScenePicker(
              scene: widget.scene,
              onChanged: widget.onSceneChanged,
              compact: false,
            ),
            _quickSounds(context, noise, quick, selected),
            _SetupRow(
              icon: AppIcons.music(
                  size: 19, color: NightStyle.iconInk, strokeWidth: 1.6),
              title: '白噪音',
              subtitle: _noiseSummary(noise),
              trailing: AppIcons.chevronRight(
                  size: 17, color: NightStyle.iconInk, strokeWidth: 1.8),
              onTap: () => showNightNoiseSheet(context),
            ),
            _SetupRow(
              icon: AppIcons.clock(
                  size: 19, color: NightStyle.iconInk, strokeWidth: 1.6),
              title: '起床闹钟',
              subtitle: widget.alarmEnabled ? '轻柔唤醒，不改变系统闹钟' : '本次睡眠不设闹钟',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.alarmEnabled) ...[
                    _WakeTimeChip(
                      value: minutesToClock(widget.wakeMinutes),
                      onTap: widget.onWakeTimePicked,
                    ),
                    const SizedBox(width: 8),
                  ],
                  IosToggle(
                    value: widget.alarmEnabled,
                    semanticLabel: '起床闹钟',
                    onChanged: widget.onAlarmToggled,
                  ),
                ],
              ),
            ),
            _SetupRow(
              icon: AppIcons.snore(
                  size: 19, color: NightStyle.iconInk, strokeWidth: 1.6),
              title: '鼾声检测',
              // plan A 还没接录音，如实标注。**这行字是产品红线，一个字都不许改**
              // （规格偏差 #7 / #31：原型那句「仅在本机识别并保存声音片段」是我们
              // 不能说的一句话）。
              subtitle: '尚未接入录音，开关只保存偏好。',
              isLast: true,
              trailing: IosToggle(
                value: _recordingEnabled,
                semanticLabel: '鼾声/梦话记录',
                onChanged: _toggleRecording,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 常用白噪音：四格 + 右上角「完整设置」。
  Widget _quickSounds(
    BuildContext context,
    NoiseSessionController noise,
    List<NoiseOption> quick,
    String? selected,
  ) {
    final narrow = NightStyle.narrowDeck(context);
    final gutter = narrow ? NightStyle.narrowGutter : NightStyle.deckGutter;
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: NightStyle.controlRowDivider)),
      ),
      padding: EdgeInsets.fromLTRB(gutter, 5, gutter, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text(
                '常用白噪音',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: NightStyle.controlLabelInk,
                ),
              ),
              const Spacer(),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => showNightNoiseSheet(context),
                child: const Padding(
                  padding: EdgeInsets.fromLTRB(8, 3, 0, 3),
                  child: Text(
                    '完整设置',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: NightStyle.controlActionInk,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              for (var i = 0; i < quick.length; i++) ...[
                if (i > 0) const SizedBox(width: 7),
                Expanded(
                  child: _QuickSoundTile(
                    option: quick[i],
                    selected: quick[i].id == selected,
                    narrow: narrow,
                    // 控制器的 `select` 自己带「再点一次＝取消」的语义
                    // （`_activeId == option.id` 时它走 `stop()`），这里不另写一套。
                    onTap: () => noise.select(quick[i]),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _startButton() {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Pressable(
        onTap: widget.onStart,
        semanticLabel: '开始睡眠',
        child: Container(
          constraints:
              const BoxConstraints(minHeight: NightStyle.setupStartMinHeight),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: NightStyle.startGradient,
            ),
            borderRadius: BorderRadius.circular(NightStyle.setupStartRadius),
            boxShadow: const [
              BoxShadow(
                color: NightStyle.startShadow,
                offset: Offset(0, 12),
                blurRadius: 30,
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcons.sleep(
                  size: 22, color: NightStyle.startInk, strokeWidth: 1.8),
              const SizedBox(width: 9),
              const Text(
                '开始睡眠',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: NightStyle.startInk,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 「雨声 · 35% · 45 分钟」/「未开启」。
  ///
  /// 没有原型的「整晚」那一档：会话里的白噪音**必须有上限**，定时只有 15/30/45/60
  /// （见 `NoiseSessionController.timerChoices` 与规格 §四/§六）。
  String _noiseSummary(NoiseSessionController noise) {
    final option = noise.activeOption;
    if (option == null) return '未开启';
    final percent = (noise.volume * 100).round();
    return '${option.label} · $percent% · ${noise.timerMinutes} 分钟';
  }
}

/// `backdrop-filter: blur(24px) saturate(130%)`。
///
/// `ImageFilter` 没有内置的 saturate 构造器（`top_fade.dart` 的注释里记过这条路），
/// 自己按 Rec.709 权重构造饱和度矩阵，再用 `ImageFilter.compose` 与 blur 合成。
ui.ImageFilter _deckFilter() {
  const s = 1.3;
  const lr = 0.2126 * (1 - s);
  const lg = 0.7152 * (1 - s);
  const lb = 0.0722 * (1 - s);
  return ui.ImageFilter.compose(
    outer: const ui.ColorFilter.matrix(<double>[
      lr + s, lg, lb, 0, 0, //
      lr, lg + s, lb, 0, 0, //
      lr, lg, lb + s, 0, 0, //
      0, 0, 0, 1, 0, //
    ]),
    inner: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
  );
}

/// 常用白噪音的一格：`.sleep-quick-sound-list button`。
///
/// 47 高、圆角 14、`1px rgba(255,255,255,.06)`、图标 17 + 标签 10；选中换成
/// `rgba(172,188,255,.28)` 描边 + `#c3ceff` 字 + `rgba(126,145,233,.15)` 底。
class _QuickSoundTile extends StatelessWidget {
  const _QuickSoundTile({
    required this.option,
    required this.selected,
    required this.onTap,
    this.narrow = false,
  });

  final NoiseOption option;
  final bool selected;
  final VoidCallback onTap;

  /// 窄屏（`@media (max-width: 390px)`）：图标在上、标签在下；宽一点则并排。
  final bool narrow;

  @override
  Widget build(BuildContext context) {
    final ink =
        selected ? NightStyle.quickSoundSelectedInk : NightStyle.quickSoundInk;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        AppHaptics.select();
        onTap();
      },
      child: Semantics(
        selected: selected,
        button: true,
        label: option.label,
        // 格子里的标签会再生成一份语义，不排掉读屏会把「雨声」念两遍。
        excludeSemantics: true,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.ease,
          constraints:
              const BoxConstraints(minHeight: NightStyle.quickSoundMinHeight),
          decoration: BoxDecoration(
            color: selected
                ? NightStyle.quickSoundSelectedFill
                : NightStyle.quickSoundFill,
            borderRadius: BorderRadius.circular(NightStyle.quickSoundRadius),
            border: Border.all(
              color: selected
                  ? NightStyle.quickSoundSelectedStroke
                  : NightStyle.quickSoundStroke,
            ),
          ),
          child: narrow
              // 窄屏竖排：图标在上、标签在下，间距 3（原型 `flex-direction: column`）
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    option.icon(17, ink),
                    const SizedBox(height: 3),
                    Text(
                      option.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10, color: ink),
                    ),
                  ],
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    option.icon(17, ink),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        option.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10, color: ink),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// 控制行：图标底板 35×35 圆角 12 + 标题/副标题 + 右侧内容。
///
/// 与「当前睡眠事件」卡里的 `_EventRow` **不是同一个**——那一版图标是 34、
/// 住在卡片里；这一版 35、住在 deck 里，分隔线由 deck 的整行宽度决定
/// （原型里这也是两条各写各的规则）。
class _SetupRow extends StatelessWidget {
  const _SetupRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.onTap,
    this.isLast = false,
  });

  final Widget icon;
  final String title;
  final String subtitle;
  final Widget trailing;
  final VoidCallback? onTap;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final row = Container(
      constraints:
          const BoxConstraints(minHeight: NightStyle.eventRowMinHeight),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(
                bottom: BorderSide(color: NightStyle.controlRowDivider),
              ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            width: NightStyle.setupIconSize,
            height: NightStyle.setupIconSize,
            decoration: BoxDecoration(
              color: NightStyle.iconFill,
              borderRadius: BorderRadius.circular(NightStyle.eventIconRadius),
            ),
            child: Center(child: icon),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: NightStyle.textStrong,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    color: NightStyle.controlMutedInk,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          trailing,
        ],
      ),
    );

    if (onTap == null) return row;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        AppHaptics.tap();
        onTap!();
      },
      child: Semantics(
        button: true,
        label: '$title，$subtitle',
        excludeSemantics: true,
        child: row,
      ),
    );
  }
}

/// 可点的起床时刻胶囊（原型 `.sleep-alarm-time`：宽 66、圆角 9、`#bdc9ff`）。
class _WakeTimeChip extends StatelessWidget {
  const _WakeTimeChip({required this.value, required this.onTap});

  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Semantics(
        button: true,
        label: '起床时间 $value',
        child: Container(
          width: 66,
          padding: const EdgeInsets.symmetric(vertical: 5),
          decoration: BoxDecoration(
            color: NightStyle.iconFill,
            borderRadius: BorderRadius.circular(9),
          ),
          alignment: Alignment.center,
          child: Text(
            value,
            style: AppTheme.num(
              context,
              size: 12,
              weight: FontWeight.w600,
              letterSpacing: 0,
              color: NightStyle.alarmTimeInk,
            ),
          ),
        ),
      ),
    );
  }
}
