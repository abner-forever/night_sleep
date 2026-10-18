import 'package:flutter/material.dart';

import '../platform/haptics.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import 'glass_surface.dart';
import 'liquid_glass.dart';
import 'quiet_surface.dart';

/// `ios-toggle` — a 52×32 track with a 26px thumb that travels 20px.
///
/// The prototype animates the thumb with a springy curve and briefly widens it
/// while pressed; both are reproduced here because they are the most tactile
/// detail in the settings screen.
///
/// **开关可以拖。** 按住滑块横向拖动，滑块跟着手指走，松手时按位置与甩动速度
/// 决定开 / 关；中途跨过中线补一次轻微触感。点击仍然是切换，两条路共用
/// [_IosToggleState._commit]——否则「点」与「拖」会在父层拒绝时给出两种不同的收尾。
class IosToggle extends StatefulWidget {
  const IosToggle({
    super.key,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;

  @override
  State<IosToggle> createState() => _IosToggleState();
}

class _IosToggleState extends State<IosToggle> with TickerProviderStateMixin {
  /// 轨道内宽减去滑块后的行程：52 - 3×2 - 26。
  static const double _travel = 20;

  /// 拖拽时滑块最多横向拉长多少（iOS 那种「被拉出来一截」的手感）。
  static const double _maxStretch = 7;

  /// 甩动超过这个速度（逻辑像素/秒）就直接按方向判，不看松手位置。
  static const double _flingVelocity = 260;

  /// 0 = 关、1 = 开。拖拽时直接写值，点击与外部改值走动画。
  late final AnimationController _progress = AnimationController(
    vsync: this,
    value: widget.value ? 1 : 0,
    duration: AppDurations.springy,
  );

  /// 滑块横向拉伸的独立进度：按下拉长，松手缩回。
  late final AnimationController _stretch = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );

  late final Listenable _repaint = Listenable.merge([_progress, _stretch]);

  /// 这次拖拽是否已经跨过中线。跨过时补一次触感，一来一回只响两次。
  bool _crossed = false;

  bool get _enabled => widget.onChanged != null;

  @override
  void didUpdateWidget(covariant IosToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      _animateTo(widget.value ? 1 : 0);
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    _stretch.dispose();
    super.dispose();
  }

  void _animateTo(double target) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _progress.value = target;
      return;
    }
    _progress.animateTo(
      target,
      duration: AppDurations.springy,
      curve: AppMotion.springyCurve,
    );
  }

  /// 提交一个目标值。
  ///
  /// 先让滑块朝目标走，再通知父层。**父层没接住就弹回去**——权限被拒、写库失败
  /// 时界面必须回到库里那个值，不能停在一个只是「看起来打开了」的位置。
  void _commit(bool target) {
    final previous = widget.value;
    _animateTo(target ? 1 : 0);
    if (target == previous) return;
    AppHaptics.select();
    widget.onChanged?.call(target);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.value == previous) _animateTo(previous ? 1 : 0);
    });
  }

  void _onDragStart(DragStartDetails details) {
    if (!_enabled) return;
    _progress.stop();
    _crossed = _progress.value >= 0.5;
    _stretch.forward();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_enabled) return;
    final next = (_progress.value + details.delta.dx / _travel).clamp(0.0, 1.0);
    _progress.value = next;
    if ((next >= 0.5) != _crossed) {
      _crossed = next >= 0.5;
      AppHaptics.select();
    }
  }

  void _onDragEnd(DragEndDetails details) {
    if (!_enabled) return;
    _stretch.reverse();
    final velocity = details.primaryVelocity ?? 0;
    final target = velocity.abs() >= _flingVelocity
        ? velocity > 0
        : _progress.value >= 0.5;
    _commit(target);
  }

  void _onDragCancel() {
    if (!_enabled) return;
    _stretch.reverse();
    _animateTo(widget.value ? 1 : 0);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final enabled = _enabled;

    return Semantics(
      label: widget.semanticLabel,
      toggled: widget.value,
      enabled: enabled,
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? () => _commit(!widget.value) : null,
          onHorizontalDragStart: enabled ? _onDragStart : null,
          onHorizontalDragUpdate: enabled ? _onDragUpdate : null,
          onHorizontalDragEnd: enabled ? _onDragEnd : null,
          onHorizontalDragCancel: enabled ? _onDragCancel : null,
          child: SizedBox(
            width: 52,
            height: 32,
            child: AnimatedBuilder(
              animation: _repaint,
              builder: (context, _) {
                // 拉伸只在拖拽时出现。位置按「轨道内剩余行程」算，于是滑块
                // 拉长时两端仍然不会越界——拉长的是滑块，不是轨道。
                final knobWidth = 26 + _maxStretch * _stretch.value;
                final t = _progress.value.clamp(0.0, 1.0);
                final left = 3 + t * (46 - knobWidth);
                final trackColor = Color.lerp(
                  const Color(0x52787880),
                  tokens.accent,
                  t,
                )!;
                final borderColor = Color.lerp(
                  Colors.white.withValues(alpha: 0.34),
                  Colors.transparent,
                  t,
                )!;

                return Stack(
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: trackColor,
                          borderRadius: BorderRadius.circular(AppRadii.pill),
                          border: Border.all(color: borderColor),
                          boxShadow: t <= 0
                              ? null
                              : [
                                  BoxShadow(
                                    color: tokens.accent
                                        .withValues(alpha: 0.28 * t),
                                    blurRadius: 9,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: left,
                      top: 3,
                      width: knobWidth,
                      height: 26,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(AppRadii.pill),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.24),
                              blurRadius: 3,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Segment label style, shared by the width measurement and the painted text so
/// the two can never disagree.
const _kSegmentTextStyle = TextStyle(
  fontSize: 14,
  fontWeight: FontWeight.w600,
  fontFeatures: AppTheme.tabular,
);

/// `ios-segmented-control` — a recessed track with a sliding raised selection.
///
/// The design uses this for the 7/14/30-day range on Statistics and the
/// appearance picker in Settings; both have exactly three options, but the
/// widget stays generic.
class SegmentedControl<T> extends StatelessWidget {
  const SegmentedControl({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
    this.expand = false,
  });

  final List<SegmentOption<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  /// When true the control fills its parent (Settings); otherwise it hugs its
  /// content (Statistics).
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final index = segments.indexWhere((segment) => segment.value == selected);
    final activeIndex = index < 0 ? 0 : index;

    return LayoutBuilder(
      builder: (context, constraints) {
        final double segmentWidth;
        if (expand) {
          // Fill the parent: the design's `calc((100% - 6px) / 3)`.
          segmentWidth = (constraints.maxWidth - 6) / segments.length;
        } else {
          // Hug content. Every segment is given the same width so the sliding
          // capsule can be positioned by simple multiplication — measuring the
          // widest label rather than dividing the parent width, which would
          // place the capsule where no segment actually sits.
          var widest = 0.0;
          for (final segment in segments) {
            final painter = TextPainter(
              text: TextSpan(text: segment.label, style: _kSegmentTextStyle),
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
            )..layout();
            if (painter.width > widest) widest = painter.width;
          }
          // `px-4` on both sides.
          segmentWidth = widest + 32;
        }

        final totalWidth = segmentWidth * segments.length + 6;

        return SizedBox(
          width: totalWidth,
          child: LiquidGlass(
            borderRadius: BorderRadius.circular(10),
            blur: 18,
            saturation: 1.45,
            tint: tokens.bgInput,
            // 小控件上整圈白边会显得太粗；留一点轮廓就够了。
            rimOpacity: 0.6,
            // 轨道是「凹进去」的，不跟内容卡共用那层大阴影。
            shadow: const [],
            expandWidth: false,
            padding: const EdgeInsets.all(3),
            child: Stack(
              children: [
                AnimatedPositioned(
                  duration: AppDurations.selection,
                  curve: AppMotion.standardCurve,
                  left: activeIndex * segmentWidth,
                  top: 0,
                  bottom: 0,
                  width: segmentWidth,
                  child: _SegmentCapsule(tokens: tokens),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final segment in segments)
                      _Segment(
                        label: segment.label,
                        active: segment.value == selected,
                        width: segmentWidth,
                        onTap: () {
                          AppHaptics.select();
                          onChanged(segment.value);
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 分段控件里那块会被推着走的选中片。
///
/// 它不单独做背景模糊：玻璃叠玻璃既读不清、又白花一次采样。改为一块
/// 「抬起来的」实面——外圈一条内缘亮边，底部一点投影；**顶部不画 1px 镜面线**，
/// 浅色模式下那条白线会在胶囊上缘留下一道硬边。
class _SegmentCapsule extends StatelessWidget {
  const _SegmentCapsule({required this.tokens});

  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.bgCardSolid,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tokens.liquidRim, width: 0.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
    );
  }
}

class SegmentOption<T> {
  const SegmentOption({required this.value, required this.label});

  final T value;
  final String label;
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.active,
    required this.onTap,
    this.width,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          // 文字颜色跟着胶囊一起走，而不是等胶囊落位后「啪」地换色。
          child: AnimatedDefaultTextStyle(
            duration: AppDurations.control,
            curve: AppMotion.standardCurve,
            style: _kSegmentTextStyle.copyWith(
              color: active ? tokens.textPrimary : tokens.textMuted,
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}

/// `ios-list-group` — a rounded grouped container whose rows are divided by a
/// hairline rule.
class IosListGroup extends StatelessWidget {
  const IosListGroup({
    super.key,
    required this.children,
    this.footer,
    this.onTap,
    this.semanticLabel,
    this.quiet = false,
  });

  final List<Widget> children;

  /// Optional muted row rendered under the group, inset to align with the
  /// primary text column (used by the sleep-import entry).
  final Widget? footer;
  final VoidCallback? onTap;
  final String? semanticLabel;

  /// 用**安静实体面**装这一组，而不是玻璃。
  ///
  /// 原型末层把 `.settings-surface` 这一族划给了「安静实体」——表单与列表容器
  /// 不参与氛围（见规格 §一）。默认仍是玻璃：容器形态本身没变，是**哪一页**用它
  /// 在变，所以由调用方点名，别的页面一个字节不受影响。
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    final body = Column(
      mainAxisSize: MainAxisSize.min,
      // Rows must fill the group. `center` (the default) shrink-wraps each row
      // to its own content and then centres it, which is what made a plain
      // label row look centred instead of left-aligned.
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) Divider(height: 0.5, thickness: 0.5, color: tokens.border),
          children[i],
        ],
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: SizedBox(
              width: double.infinity,
              child: DefaultTextStyle.merge(
                style: TextStyle(fontSize: 12, color: tokens.textMuted),
                child: footer!,
              ),
            ),
          ),
      ],
    );

    // 两种面只差「用哪一个」：`QuietSurface` 与 `GlassSurface` 的这五个参数同名同义。
    final radius = BorderRadius.circular(AppRadii.group);
    return quiet
        ? QuietSurface(
            borderRadius: radius,
            onTap: onTap,
            semanticLabel: semanticLabel,
            child: body,
          )
        : GlassSurface(
            borderRadius: radius,
            onTap: onTap,
            semanticLabel: semanticLabel,
            child: body,
          );
  }
}

/// `ios-list-item` — a 56px minimum row with a 12px internal gap.
///
/// 可点的行在按下时垫一层淡色底（iOS 表格那种按压反馈）。底色是矩形的，
/// 但行总是住在 `IosListGroup` 的圆角裁剪里，首行 / 末行的圆角由容器裁出来，
/// 这里不需要知道自己在组里的位置。
class IosListItem extends StatefulWidget {
  const IosListItem({
    super.key,
    required this.child,
    this.onTap,
    this.padding,
    this.minHeight = 56,
    this.haptic = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;
  final double minHeight;
  final bool haptic;

  @override
  State<IosListItem> createState() => _IosListItemState();
}

class _IosListItemState extends State<IosListItem> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final row = AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: AppMotion.standardCurve,
      constraints: BoxConstraints(minHeight: widget.minHeight),
      padding: widget.padding ??
          const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      color: _pressed ? tokens.bgInput : Colors.transparent,
      child: widget.child,
    );

    if (widget.onTap == null) return row;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapCancel: () => _setPressed(false),
      onTapUp: (_) => _setPressed(false),
      onTap: () {
        if (widget.haptic) AppHaptics.tap();
        widget.onTap!();
      },
      child: row,
    );
  }
}

/// The rounded square icon badge used at the leading edge of list rows.
class ListIconBadge extends StatelessWidget {
  const ListIconBadge({
    super.key,
    required this.child,
    required this.background,
    this.size = 32,
    this.radius = 12,
  });

  final Widget child;
  final Color background;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(radius),
      ),
      alignment: Alignment.center,
      child: child,
    );
  }
}
