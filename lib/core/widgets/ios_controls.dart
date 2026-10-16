import 'package:flutter/material.dart';

import '../platform/haptics.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import 'glass_surface.dart';
import 'quiet_surface.dart';

/// `ios-toggle` — a 52×32 track with a 26px thumb that travels 20px.
///
/// The prototype animates the thumb with a springy curve and briefly widens it
/// while pressed; both are reproduced here because they are the most tactile
/// detail in the settings screen.
class IosToggle extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final enabled = onChanged != null;

    return Semantics(
      label: semanticLabel,
      toggled: value,
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled
              ? () {
                  AppHaptics.select();
                  onChanged!(!value);
                }
              : null,
          child: SizedBox(
            width: 52,
            height: 32,
            child: AnimatedContainer(
              duration: AppDurations.springy,
              curve: AppMotion.standardCurve,
              decoration: BoxDecoration(
                color: value ? tokens.accent : const Color(0x52787880),
                borderRadius: BorderRadius.circular(AppRadii.pill),
                border: Border.all(
                  color: value
                      ? Colors.transparent
                      : Colors.white.withValues(alpha: 0.34),
                ),
                boxShadow: value
                    ? [
                        BoxShadow(
                          color: tokens.accent.withValues(alpha: 0.28),
                          blurRadius: 9,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: AnimatedAlign(
                duration: AppDurations.springy,
                curve: AppMotion.springyCurve,
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
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
              ),
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

        return Container(
          width: totalWidth,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: const Color(0x1F767680),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Stack(
            children: [
              AnimatedPositioned(
                duration: AppDurations.selection,
                curve: AppMotion.standardCurve,
                left: activeIndex * segmentWidth,
                top: 0,
                bottom: 0,
                width: segmentWidth,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: tokens.bgCardSolid,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.14),
                        blurRadius: 5,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
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
        );
      },
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
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _kSegmentTextStyle.copyWith(
              color: active ? tokens.textPrimary : tokens.textMuted,
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
class IosListItem extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final row = Container(
      constraints: BoxConstraints(minHeight: minHeight),
      padding:
          padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: child,
    );

    if (onTap == null) return row;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (haptic) AppHaptics.tap();
        onTap!();
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
