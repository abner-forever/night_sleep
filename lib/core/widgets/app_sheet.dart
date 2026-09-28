import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../platform/haptics.dart';
import '../theme/app_tokens.dart';

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

/// Opens a bottom sheet styled like the prototype's `.sheet-panel`.
///
/// Built on [showGeneralDialog] rather than [showModalBottomSheet] for two
/// reasons:
///
///  * the design blurs its own scrim (`backdrop-filter: blur(14px)`), and
///    `showModalBottomSheet` gives no way to blur the barrier;
///  * the scrim has to **fade**, not ride up with the panel. When the scrim is
///    a child of the sheet, it inherits the sheet's slide transition and appears
///    to be dragged in from the bottom edge.
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isDismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: isDismissible,
    barrierLabel: '关闭',
    // The host paints the blurred scrim itself — a barrier colour would be an
    // opaque layer *over* that blur. Transparent keeps the route's own modal
    // semantics and focus handling without painting anything.
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (context, animation, secondaryAnimation) => _SheetHost(
      animation: animation,
      isDismissible: isDismissible,
      child: Builder(builder: builder),
    ),
  );
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
  });

  final Widget child;
  final bool isDismissible;
  final Animation<double> animation;

  @override
  State<_SheetHost> createState() => _SheetHostState();
}

class _SheetHostState extends State<_SheetHost> {
  /// How far the user has pulled the panel down, in logical pixels.
  double _dragOffset = 0;
  double _panelHeight = 0;

  static const _velocityThreshold = 700.0;

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
    setState(
        () => _dragOffset = (_dragOffset + delta).clamp(0.0, double.infinity));
  }

  void _onDragEnd(double velocity) {
    if (!widget.isDismissible) return;
    final flung = velocity > _velocityThreshold;
    final pulled = _panelHeight > 0 && _dragOffset > _panelHeight * 0.28;
    if (flung || pulled) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _dragOffset = 0);
  }

  void _dismiss() {
    if (!widget.isDismissible) return;
    AppHaptics.tap();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final media = MediaQuery.of(context);
    final isWide = media.size.width >= 640;

    // The scrim fades. Only the panel slides.
    final scrim = FadeTransition(
      opacity: widget.animation,
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
        Align(
          alignment: Alignment.bottomCenter,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(
                parent: widget.animation,
                curve: AppMotion.standardCurve,
              ),
            ),
            child: Transform.translate(
              offset: Offset(0, _dragOffset),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _panelHeight = constraints.maxHeight;
                  return Padding(
                    // Wide layouts float the sheet 24px off the bottom edge and
                    // cap it at 560px, matching the prototype's desktop rule.
                    padding: EdgeInsets.only(bottom: isWide ? 24 : 0),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: isWide ? 560 : double.infinity,
                        maxHeight: media.size.height * 0.92,
                      ),
                      child: _SheetDragScope(
                        onDragUpdate: _onDragUpdate,
                        onDragEnd: _onDragEnd,
                        onHandleTap: _dismiss,
                        child: widget.child,
                      ),
                    ),
                  );
                },
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
    required this.child,
    this.showHandle = true,
    this.padding,
    this.scrollable = false,
  });

  final Widget child;
  final bool showHandle;
  final EdgeInsetsGeometry? padding;

  /// Wraps [child] in a scroll view; used by the tall detail sheet.
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final media = MediaQuery.of(context);
    final isWide = media.size.width >= 640;
    final radius = Radius.circular(isWide ? AppRadii.sheet : AppRadii.sheet);

    Widget content = Padding(
      padding: padding ?? EdgeInsets.zero,
      child: child,
    );
    if (scrollable) {
      content = SingleChildScrollView(
        padding: EdgeInsets.only(bottom: media.padding.bottom),
        child: content,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.vertical(top: radius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 38, sigmaY: 38),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tokens.sheetBg,
            borderRadius: BorderRadius.vertical(top: radius),
            border: Border(
              top: BorderSide(color: tokens.glassBorder),
              left: BorderSide(color: tokens.glassBorder),
              right: BorderSide(color: tokens.glassBorder),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isWide ? 0.18 : 0.14),
                blurRadius: 44,
                offset: const Offset(0, -14),
              ),
            ],
          ),
          // A sheet is not a `Dialog`, and `showGeneralDialog` — unlike
          // `showDialog` — wraps its route in nothing. Without a `Material`
          // ancestor every `Text` in here falls back to Flutter's error style,
          // which renders as a yellow double underline under all of it.
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showHandle) const _SheetHandle(),
                Flexible(child: content),
              ],
            ),
          ),
        ),
      ),
    );
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
