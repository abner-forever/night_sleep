import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_sheet.dart' show kPanelDismissFraction;
import 'night_style.dart';

/// 面板下拉位移的存放处：**页面写、转场读**。
///
/// 页面（`SleepSessionPage`）在 `didChangeDependencies` 里认领它，之后的每一个位移都写
/// 进来；转场用它算遮罩的浓度。页面被单独挂载（测试里直接挂 `SleepSessionPage`）时
/// 没有这个作用域，页面照旧自己位移，只是没有遮罩可画。
class SessionPanelDrag extends InheritedWidget {
  const SessionPanelDrag(
      {super.key, required this.value, required super.child});

  final ValueNotifier<double> value;

  static ValueNotifier<double>? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SessionPanelDrag>()?.value;

  @override
  bool updateShouldNotify(SessionPanelDrag oldWidget) =>
      oldWidget.value != value;
}

/// 会话页（`/sleep/session`）的进退场：**面板滑动，遮罩原地淡出**。
///
/// **遮罩为什么挂在这一层，而不是页面里。** 整页都在路由的转场里滑动，遮罩挂在页面内
/// 就会跟着面板一起下去——拉了一半松手时看到的是「蒙层也跟着下拉」，而它该做的是留在
/// 原地淡出（使用方 2026-10-16 提出）。放在这里它就不在滑动的那棵子树里，位置天然是
/// 钉死的，剩下的只是把浓度算出来。
///
/// **面板自己的位移仍留在页面里**（`SleepSessionPage` 那个 `Transform.translate`）。
/// 2026-10-16 的第一版把位移也搬到了这一层，代价是页面最外层那圈 `AnnotatedRegion`
/// （系统栏样式）跟着面板一起往下走：拖动超过状态栏高度（24–48px）时那个区域就滑出了
/// 顶端，框架取回**应用主题**的样式——浅色主题下拉一下，状态栏图标会翻成深色压在暗掉
/// 的首页上。页面里那句旧注释早就记着这个坑（「换成把它塞进 `Transform` 就会…」）。
/// 所以这一层只管遮罩，位移仍由页面自己对内容施加。
class SessionPanelTransition extends StatefulWidget {
  const SessionPanelTransition({
    super.key,
    required this.animation,
    required this.child,
  });

  /// 这条路由自己的转场进度：1 = 在位上，0 = 完全退出。
  final Animation<double> animation;

  final Widget child;

  @override
  State<SessionPanelTransition> createState() => _SessionPanelTransitionState();
}

class _SessionPanelTransitionState extends State<SessionPanelTransition>
    with SingleTickerProviderStateMixin {
  /// 手指拉下来的位移（逻辑像素，正数向下）。页面往里写，遮罩从这里读。
  ///
  /// **由转场持有**：它比页面活得久一点——路由被重建时这一层的 State 复用、notifier
  /// 不变，于是不存在「写的人先死、读的人还在」这种顺序问题（挂载期由页面创建过一次
  /// 的那种写法，重建时会换一个新对象，面板会当场闪回顶边一帧）。
  final ValueNotifier<double> _drag = ValueNotifier<double>(0);

  /// 独立入场是否走完。走完后把位移交还给路由动画，供返回与下拉关闭使用。
  bool _entryCompleted = false;

  /// 入场位移由这一页自己驱动。
  ///
  /// 用 GoRouter 的 `animation` 不够：实测它进入 `transitionsBuilder` 时可能已经是
  /// `completed / 1.0`，于是整段升起被跳过。这里等完整页面画出第一帧后再启动，
  /// 首帧不会再被正文构建时间抢走。
  late final AnimationController _entry = AnimationController(
    vsync: this,
    duration: AppDurations.standard,
  );

  late final Animation<Offset> _entryPosition = Tween<Offset>(
    begin: const Offset(0, 1),
    end: Offset.zero,
  ).animate(
    CurvedAnimation(
      parent: _entry,
      curve: AppMotion.standardCurve,
    ),
  );

  @override
  void initState() {
    super.initState();
    _entry.addStatusListener(_handleEntryStatus);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startEntry());
  }

  void _startEntry() {
    if (!mounted) return;
    if (NightStyle.reduceMotion(context)) {
      _entry.value = 1;
      return;
    }
    _entry.forward();
  }

  void _handleEntryStatus(AnimationStatus status) {
    if (_entryCompleted || status != AnimationStatus.completed) return;
    setState(() => _entryCompleted = true);
  }

  @override
  void dispose() {
    _entry
      ..removeStatusListener(_handleEntryStatus)
      ..dispose();
    _drag.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final routePosition = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: widget.animation,
        curve: AppMotion.standardCurve,
      ),
    );

    return SessionPanelDrag(
      value: _drag,
      child: Stack(
        // 转场拿到的是一屏的紧约束，`expand` 让面板照旧铺满（`SlideTransition`
        // 按子项自身高度的比例位移，尺寸变了位移量就跟着变）。
        fit: StackFit.expand,
        children: [
          // 排在面板**之前**：面板滑开时露出的那一层，得先画。它不参与滑动。
          Positioned.fill(
            child: SessionPanelScrim(
              drag: _drag,
              animation: widget.animation,
            ),
          ),
          SlideTransition(
            // 页面从一开始就完整挂载：入场时看到的必须是真正的夜景与设置内容，
            // 不能先给一块空白面板。独立控制器只负责补回被 GoRouter 跳过的位移。
            position: _entryCompleted ? routePosition : _entryPosition,
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

/// 面板下拉时露出来的那一层：**模糊 + 压暗**，浓度跟着手指走，退场时原地淡出。
///
/// 与底部弹层（`app_sheet.dart` 的 `_SheetHost`）同一套观感，模糊半径也照它。
/// 公开是为了让 widget 测试认得出它——「它有没有跟着面板走」正是这一条要钉的东西。
class SessionPanelScrim extends StatelessWidget {
  const SessionPanelScrim({
    super.key,
    required this.drag,
    required this.animation,
  });

  final ValueListenable<double> drag;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    // 拉到「够呛要关」那条线时刚好全浓：判据与面板自己的关闭判据同源
    // （[kPanelDismissFraction]），所以「浓度满了」与「松手就关」是同一时刻。
    final full = MediaQuery.sizeOf(context).height * kPanelDismissFraction;

    return IgnorePointer(
      child: AnimatedBuilder(
        // 两个来源合成一个 `Listenable`：浓度同时取决于手指与退场进度，
        // 分两处监听会在退场那几帧里各画各的。
        animation: Listenable.merge([drag, animation]),
        builder: (context, _) => Opacity(
          // `full` 为 0 只会出现在零高视口（测试里的极端尺寸）：那时遮罩本来就
          // 看不见，直接给 0，别让 0/0 的 NaN 落到 `Opacity` 的断言上。
          opacity: full <= 0
              ? 0
              : (drag.value / full).clamp(0.0, 1.0) * animation.value,
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            // 用夜色那一份而不是 `AppTokens.overlayScrim`：这一页常暗，而
            // `AppTokens` 在这一层取到的是**应用主题**的值（浅色主题下会偏淡）。
            child: const ColoredBox(color: NightStyle.scrim),
          ),
        ),
      ),
    );
  }
}
