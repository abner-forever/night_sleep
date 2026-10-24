import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../platform/haptics.dart';
import '../theme/app_tokens.dart';
import 'quiet_surface.dart';

/// How many bottom sheets are on screen.
///
/// The prototype retires the top scroll fade while a sheet is open, so the
/// navigation chrome has to know. A counter rather than a flag, because sheets
/// stack — a wheel picker opens on top of the sound sheet.
///
/// It is driven by the host's lifecycle, not by the `showAppSheet` future: a
/// sheet that is torn down without being popped would otherwise leave the count
/// permanently above zero and retire the fade for good.
final openSheetCount = ValueNotifier<int>(0);

/// 面板下滑关闭的两个判据：甩动速度够快，或者位移超过面板高度的这个比例。
///
/// **顶部常量而不是 [_SheetHostState] 的私有字段**：会话页那个整屏面板
/// （`sleep_session_page.dart` 的下拉关闭）要用同一份。两份拷贝会漂，而
/// `.claude/skills/flutter-pitfalls/SKILL.md` 已经把这两个数写成了项目级知识。
const double kPanelDismissVelocity = 700.0;
const double kPanelDismissFraction = 0.28;

/// Opens a bottom sheet styled like the prototype's `.sheet-panel`.
///
/// Built on a dialog route rather than [showModalBottomSheet] for two reasons:
///
///  * the design blurs its own scrim (`backdrop-filter: blur(14px)`), and
///    `showModalBottomSheet` gives no way to blur the barrier;
///  * the scrim has to **fade**, not ride up with the panel. When the scrim is
///    a child of the sheet, it inherits the sheet's slide transition and appears
///    to be dragged in from the bottom edge.
///
/// [_SheetRoute] 只是 `RawDialogRoute` 加了一条「退场时长」。`showGeneralDialog`
/// 不暴露那个参数，而进场 340ms / 退场 240ms 的差别正是「升起来从容、收回去干脆」
/// 的来处——两者共用一个时长时，关闭看起来像先愣了一下再走。
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isDismissible = true,
  bool expanded = false,
}) {
  // `rootNavigator: true` 与原来的 `showGeneralDialog` 默认值一致：弹层挂在根
  // Navigator 上，不随调用点的局部 Navigator 走。
  return Navigator.of(context, rootNavigator: true).push<T>(
    _SheetRoute<T>(
      barrierDismissible: isDismissible,
      barrierLabel: '关闭',
      // The host paints the blurred scrim itself — a barrier colour would be an
      // opaque layer *over* that blur. Transparent keeps the route's own modal
      // semantics and focus handling without painting anything.
      barrierColor: Colors.transparent,
      transitionDuration: AppDurations.sheetIn,
      pageBuilder: (context, animation, secondaryAnimation) => _SheetHost(
        animation: animation,
        isDismissible: isDismissible,
        expanded: expanded,
        child: Builder(builder: builder),
      ),
    ),
  );
}

class _SheetRoute<T> extends RawDialogRoute<T> {
  _SheetRoute({
    required super.pageBuilder,
    required super.barrierDismissible,
    required super.barrierColor,
    required super.barrierLabel,
    required super.transitionDuration,
  });

  @override
  Duration get reverseTransitionDuration => AppDurations.sheetOut;
}

/// Lets any [AppSheet] nested in the host wire its drag handle to the host's
/// gesture state without threading callbacks through every sheet body.
class _SheetDragScope extends InheritedWidget {
  const _SheetDragScope({
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onHandleTap,
    required super.child,
  });

  final ValueChanged<double> onDragUpdate;
  final void Function(double velocity) onDragEnd;
  final VoidCallback onHandleTap;

  static _SheetDragScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SheetDragScope>();

  @override
  bool updateShouldNotify(_SheetDragScope oldWidget) => false;
}

class _SheetHost extends StatefulWidget {
  const _SheetHost({
    required this.child,
    required this.isDismissible,
    required this.animation,
    required this.expanded,
  });

  final Widget child;
  final bool isDismissible;
  final Animation<double> animation;
  final bool expanded;

  @override
  State<_SheetHost> createState() => _SheetHostState();
}

class _SheetHostState extends State<_SheetHost>
    with SingleTickerProviderStateMixin {
  /// 进场 / 退场各用各的曲线。`FadeTransition` 与 `SlideTransition` 共用它，
  /// 蒙层才不会在面板收回去之后还多留一截。
  late final CurvedAnimation _curved = CurvedAnimation(
    parent: widget.animation,
    curve: AppMotion.sheetEnterCurve,
    reverseCurve: AppMotion.sheetExitCurve,
  );

  /// 面板的下拉位移（逻辑像素，正数向下）。
  ///
  /// 用控制器而不是 `setState` 的数字：松手没够着关闭阈值时要**弹回去**，
  /// 直接赋 0 是瞬移，没有回弹。
  late final AnimationController _drag = AnimationController.unbounded(
    vsync: this,
    value: 0,
  );

  /// 进场时面板从 98.5% 长到 100%，落位有一点「压下来」的重量感。
  late final Animation<double> _scale = Tween<double>(
    begin: 0.985,
    end: 1,
  ).animate(_curved);

  double _panelHeight = 0;

  @override
  void initState() {
    super.initState();
    _adjustSheetCount(1);
  }

  @override
  void dispose() {
    // Paired with `initState` rather than with the route future, so the count
    // cannot drift if a host goes away without being popped.
    _adjustSheetCount(-1);
    _curved.dispose();
    _drag.dispose();
    super.dispose();
  }

  /// Moves [openSheetCount] without notifying mid-build.
  ///
  /// Both `initState` and `dispose` run inside the build phase — a route is
  /// mounted and unmounted while the tree is being built or finalised. Notifying
  /// there makes the navigation chrome's `ValueListenableBuilder` call
  /// `setState` mid-build, which throws "setState() called during build". It only
  /// surfaces once a sheet and the shell are on screen together, so it appears
  /// on every real open and close and in no isolated widget test.
  static void _adjustSheetCount(int delta) {
    scheduleMicrotask(() {
      final next = openSheetCount.value + delta;
      openSheetCount.value = next < 0 ? 0 : next;
    });
  }

  void _onDragUpdate(double delta) {
    if (!widget.isDismissible) return;
    // 下拉时直接跟手，不经过动画——中间那一帧的延迟会被手指看成「粘」。
    _drag.stop();
    _drag.value = (_drag.value + delta).clamp(0.0, double.infinity);
  }

  void _onDragEnd(double velocity) {
    if (!widget.isDismissible) return;
    final flung = velocity > kPanelDismissVelocity;
    final pulled =
        _panelHeight > 0 && _drag.value > _panelHeight * kPanelDismissFraction;
    if (flung || pulled) {
      // 不复位位移：路由的退场动画接着从这里往下滑走。复位会让面板先跳回
      // 原位再下滑，是一次看得见的闪跳。
      Navigator.of(context).pop();
      return;
    }
    // 没够着阈值：弹回原位，而不是瞬移回去。
    _drag.animateTo(
      0,
      duration: AppDurations.sheetSettle,
      curve: AppMotion.standardCurve,
    );
  }

  void _dismiss() {
    if (!widget.isDismissible) return;
    AppHaptics.tap();
    // 点蒙层 / 点把手时可能还有一次回弹在跑，先停下，退场动画自己会接管。
    _drag.stop();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final media = MediaQuery.of(context);
    final isWide = media.size.width >= (widget.expanded ? 768 : 640);

    // The scrim fades. Only the panel slides.
    final scrim = FadeTransition(
      opacity: _curved,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: ColoredBox(color: tokens.overlayScrim),
      ),
    );

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.isDismissible ? _dismiss : null,
            child: scrim,
          ),
        ),
        Positioned.fill(
          left: media.padding.left,
          right: media.padding.right,
          bottom: media.viewInsets.bottom,
          child: Align(
            alignment: widget.expanded && isWide
                ? Alignment.center
                : Alignment.bottomCenter,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 1),
                end: Offset.zero,
              ).animate(_curved),
              // 位移在缩放的**外面**：拖拽跟手的是屏幕像素，不该被进场时那
              // 1.5% 的缩放折算一遍。
              child: AnimatedBuilder(
                animation: _drag,
                builder: (context, child) => Transform.translate(
                  offset: Offset(0, _drag.value),
                  child: child,
                ),
                child: ScaleTransition(
                  scale: _scale,
                  alignment: Alignment.bottomCenter,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      _panelHeight = constraints.maxHeight;
                      return ConstrainedBox(
                        // 宽屏限宽，但**下沿一律贴屏幕底**。原型那条「宽屏浮起
                        // 24px」是桌面浏览器的规则：这里照搬会在面板下缘留出
                        // 一条遮罩，面板像是悬空断在屏幕底之上（使用方在 iPad
                        // 横屏上实测后裁定，见规格第 8 章）。
                        constraints: BoxConstraints(
                          maxWidth: isWide
                              ? (widget.expanded ? 620 : 560)
                              : double.infinity,
                          maxHeight: math.max(
                            0,
                            widget.expanded
                                ? constraints.maxHeight - (isWide ? 56 : 0)
                                : math.min(constraints.maxHeight * 0.92,
                                    constraints.maxHeight - media.padding.top),
                          ),
                        ),
                        child: _SheetDragScope(
                          onDragUpdate: _onDragUpdate,
                          onDragEnd: _onDragEnd,
                          onHandleTap: _dismiss,
                          child: widget.child,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The grabber.
///
/// Visually it is the design's 34×5px bar, but it carries a taller invisible hit
/// area and owns the sheet's two dismiss gestures: tap to close, and a
/// finger-following pull. The drag deliberately lives **here** and not on the
/// whole panel — the detail sheet's body is a scroll view, and a panel-wide
/// vertical drag would fight it for every scroll.
class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final scope = _SheetDragScope.maybeOf(context);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: scope?.onHandleTap,
      onVerticalDragUpdate: scope == null
          ? null
          : (details) => scope.onDragUpdate(details.delta.dy),
      onVerticalDragEnd: scope == null
          ? null
          : (details) => scope.onDragEnd(details.primaryVelocity ?? 0),
      child: SizedBox(
        height: 28,
        child: Center(
          child: Container(
            width: 34,
            height: 5,
            decoration: BoxDecoration(
              color: tokens.textMuted.withValues(alpha: 0.44),
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
          ),
        ),
      ),
    );
  }
}

class AppSheet extends StatelessWidget {
  const AppSheet({
    super.key,
    this.child,
    this.slivers,
    this.showHandle = true,
    this.padding,
    this.scrollable = false,
    this.heightFactor,
    this.expanded = false,
    this.background,
    this.respectTopSafeArea = true,
  }) : assert(
          (child == null) != (slivers == null),
          'AppSheet 要么给 child，要么给 slivers——两者只能有一个。',
        );

  final Widget? child;
  final bool showHandle;
  final EdgeInsetsGeometry? padding;

  /// Wraps [child] in a scroll view; used by the tall detail sheet.
  final bool scrollable;

  /// 面板高度 = 屏幕高度 × 这个比例；`null` = 按内容收放（上限仍是宿主的 92%）。
  ///
  /// 睡眠详情页用 2/3 固定一个「半弹窗」：内容多了在面板里滚，内容少了面板也不缩。
  final double? heightFactor;
  final bool expanded;
  final Widget? background;

  /// 是否由 [AppSheet] 统一避让顶部安全区。
  ///
  /// 普通弹层保持开启；带自绘吸顶导航的全屏弹层要关掉，让导航底板从屏幕
  /// 物理顶部开始绘制，再由导航自身把状态栏高度算进行高。否则状态栏和
  /// 导航会各铺一层不同背景，交界处出现一条硬边。
  final bool respectTopSafeArea;

  /// 直接由 sliver 组成的正文，与 [child] 二选一。
  ///
  /// 详情页的片段列表可能上百条，`SingleChildScrollView` + `Column` 会一次建完
  /// **整份**内容（每张卡还带 38 根波形条），弹窗第一帧因此被拖到动画都看不见。
  /// 改由 sliver 列表按需构建，只有真正进到视口里的卡片才存在。
  ///
  /// 走这条路时面板占满宿主给的可用高度（详情页再按 [heightFactor] 定成 2/3 屏）。
  final List<Widget>? slivers;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final media = MediaQuery.of(context);
    const radius = Radius.circular(AppRadii.sheet);

    final Widget content;
    if (slivers != null) {
      content = CustomScrollView(
        slivers: [
          ...slivers!,
          // 安全区留白放在滚动内容**里面**，与 `scrollable` 那条路同一个口径。
          SliverToBoxAdapter(child: SizedBox(height: media.padding.bottom)),
        ],
      );
    } else {
      Widget padded = Padding(
        padding: padding ?? EdgeInsets.zero,
        child: child!,
      );
      if (scrollable) {
        padded = SingleChildScrollView(
          padding: EdgeInsets.only(bottom: media.padding.bottom),
          child: padded,
        );
      } else {
        padded = Padding(
          padding: EdgeInsets.only(bottom: media.padding.bottom),
          child: padded,
        );
      }
      content = padded;
    }

    final panel = QuietSurface(
      borderRadius: expanded
          ? (media.size.width >= 768
              ? BorderRadius.circular(25)
              : BorderRadius.zero)
          : const BorderRadius.vertical(top: radius),
      tint: tokens.sheetBg,
      // 弹层按内容收放：不要像卡片那样强行撑满宿主宽度。
      expandWidth: false,
      borderColor: Colors.transparent,
      // 阴影放在裁剪之外才不会被丢掉；原先写在 `ClipRRect` 里面，实际是看不见的。
      shadow: const [
        BoxShadow(
          color: Color(0x15091729),
          blurRadius: 30,
          offset: Offset(0, -6),
        ),
      ],
      // A sheet is not a `Dialog`, and `showGeneralDialog` — unlike
      // `showDialog` — wraps its route in nothing. Without a `Material`
      // ancestor every `Text` in here falls back to Flutter's error style,
      // which renders as a yellow double underline under all of it.
      child: Stack(
        children: [
          if (background != null) Positioned.fill(child: background!),
          Material(
            type: MaterialType.transparency,
            child: SafeArea(
              top: respectTopSafeArea &&
                  expanded &&
                  media.size.width < kWideLayoutBreakpoint,
              bottom: false,
              left: false,
              right: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showHandle) const _SheetHandle(),
                  Flexible(child: content),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    if (expanded) return SizedBox.expand(child: panel);
    if (heightFactor == null) return panel;
    return SizedBox(height: media.size.height * heightFactor!, child: panel);
  }
}

/// `关闭 / 标题 / 占位` toolbar used by the noise sheet.
class SheetToolbar extends StatelessWidget {
  const SheetToolbar({
    super.key,
    required this.title,
    this.subtitle,
    this.onClose,
    this.closeLabel = '关闭',
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onClose;
  final String closeLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.border, width: 0.5)),
      ),
      child: Row(
        children: [
          if (onClose != null)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                AppHaptics.tap();
                onClose!();
              },
              child: SizedBox(
                width: 40,
                child: Text(
                  closeLabel,
                  style: TextStyle(fontSize: 16, color: tokens.textMuted),
                ),
              ),
            )
          else
            const SizedBox(width: 40),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: tokens.textPrimary,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontFeatures: const [ui.FontFeature.tabularFigures()],
                      color: tokens.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 40),
        ],
      ),
    );
  }
}
