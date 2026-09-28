import 'package:flutter/material.dart';

import '../platform/haptics.dart';
import '../theme/app_tokens.dart';
import 'app_basics.dart';
import 'app_sheet.dart';

/// One snapping column of a wheel picker.
///
/// Matches `WheelColumn` in the prototype: 44px rows, five visible at a time,
/// and type that grows, darkens and tightens toward the centre rail. The CSS
/// fades the ends with a mask, reproduced here with a [ShaderMask].
class WheelColumn extends StatefulWidget {
  const WheelColumn({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onChanged,
    this.width = 80,
  });

  final List<String> items;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final double width;

  static const double itemExtent = 44;
  static const int visibleItems = 5;

  @override
  State<WheelColumn> createState() => _WheelColumnState();
}

class _WheelColumnState extends State<WheelColumn> {
  late FixedExtentScrollController _controller;
  late int _active;

  @override
  void initState() {
    super.initState();
    _active = widget.selectedIndex.clamp(0, widget.items.length - 1);
    _controller = FixedExtentScrollController(initialItem: _active);
  }

  @override
  void didUpdateWidget(covariant WheelColumn oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-centre when a parent changes the value (e.g. switching provider resets
    // the model list).
    if (widget.selectedIndex != oldWidget.selectedIndex &&
        _controller.hasClients &&
        _controller.selectedItem != widget.selectedIndex) {
      _controller.jumpToItem(
        widget.selectedIndex.clamp(0, widget.items.length - 1),
      );
    }
    if (widget.selectedIndex != _active) {
      _active = widget.selectedIndex.clamp(0, widget.items.length - 1);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    return SizedBox(
      width: widget.width,
      height: WheelColumn.itemExtent * WheelColumn.visibleItems,
      child: ShaderMask(
        shaderCallback: (rect) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black,
            Colors.black,
            Colors.transparent,
          ],
          stops: [0.0, 0.34, 0.66, 1.0],
        ).createShader(rect),
        blendMode: BlendMode.dstIn,
        child: ListWheelScrollView.useDelegate(
          controller: _controller,
          itemExtent: WheelColumn.itemExtent,
          perspective: 0.004,
          diameterRatio: 1.7,
          physics: const FixedExtentScrollPhysics(),
          onSelectedItemChanged: (index) {
            setState(() => _active = index);
            AppHaptics.select();
            widget.onChanged(index);
          },
          childDelegate: ListWheelChildBuilderDelegate(
            childCount: widget.items.length,
            builder: (context, index) {
              final distance = (index - _active).abs();
              final isActive = distance == 0;
              final opacity = distance > 1 ? 0.45 : (distance == 1 ? 0.7 : 1.0);
              return Center(
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 150),
                  style: TextStyle(
                    fontSize: isActive ? 22 : 17,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                    letterSpacing: isActive ? -0.66 : 0,
                    color: (isActive ? tokens.textPrimary : tokens.textMuted)
                        .withValues(alpha: opacity),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  child: Text(widget.items[index], maxLines: 1),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Shared shell: the columns centred in a fixed-height band.
///
/// The prototype also draws a `wheel-selection-rail` here — two hairlines
/// bounding the selected row. They are deliberately **not** reproduced: they
/// were removed on request, and the design's own version (a 30% accent mixed
/// into `--border-strong`) is far more muted than the pure-accent lines this
/// used to paint, so it is the colour, not the element, that looked wrong.
/// Putting them back means `border-top`/`border-bottom` at that mix.
class _WheelShell extends StatelessWidget {
  const _WheelShell({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: WheelColumn.itemExtent * WheelColumn.visibleItems,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: children,
      ),
    );
  }
}

/// `TimePicker` — 24 hour and 60 minute columns joined by a centred colon.
class AppTimePicker extends StatelessWidget {
  const AppTimePicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  /// `HH:mm`.
  final String value;
  final ValueChanged<String> onChanged;

  static final _hours = List.generate(24, (i) => i.toString().padLeft(2, '0'));
  static final _minutes =
      List.generate(60, (i) => i.toString().padLeft(2, '0'));

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final parts = value.split(':');
    final hour = int.tryParse(parts.first) ?? 0;
    final minute = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;

    return _WheelShell(
      children: [
        WheelColumn(
          items: _hours,
          selectedIndex: hour.clamp(0, 23),
          width: 72,
          onChanged: (i) => onChanged('${_hours[i]}:${_minutes[minute]}'),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text(
            ':',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: tokens.accent,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        WheelColumn(
          items: _minutes,
          selectedIndex: minute.clamp(0, 59),
          width: 72,
          onChanged: (i) => onChanged('${_hours[hour]}:${_minutes[i]}'),
        ),
      ],
    );
  }
}

/// `DatePicker` — year / month / day columns over a five-year window.
class AppDatePicker extends StatelessWidget {
  const AppDatePicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.now,
  });

  /// `YYYY-MM-DD`.
  final String value;
  final ValueChanged<String> onChanged;

  /// Injectable clock so tests are not tied to the wall clock.
  final DateTime? now;

  static const _months = [
    '1月',
    '2月',
    '3月',
    '4月',
    '5月',
    '6月',
    '7月',
    '8月',
    '9月',
    '10月',
    '11月',
    '12月',
  ];

  static int _daysInMonth(int year, int month) =>
      DateTime(year, month + 1, 0).day;

  @override
  Widget build(BuildContext context) {
    final today = now ?? DateTime.now();
    final parts = value.split('-').map(int.tryParse).toList();
    final year = parts.isNotEmpty ? (parts[0] ?? today.year) : today.year;
    final month = parts.length > 1 ? (parts[1] ?? today.month) : today.month;
    final day = parts.length > 2 ? (parts[2] ?? today.day) : today.day;

    final years = List.generate(5, (i) => '${today.year - 2 + i}');
    final days = List.generate(
      _daysInMonth(year, month),
      (i) => (i + 1).toString().padLeft(2, '0'),
    );

    void emit(int y, int m, int d) {
      final maxDay = _daysInMonth(y, m);
      final clamped = d > maxDay ? maxDay : d;
      onChanged(
        '$y-${m.toString().padLeft(2, '0')}-${clamped.toString().padLeft(2, '0')}',
      );
    }

    final yearIndex = years.indexOf('$year');

    return _WheelShell(
      children: [
        WheelColumn(
          items: years,
          selectedIndex: yearIndex < 0 ? 2 : yearIndex,
          width: 76,
          onChanged: (i) => emit(int.parse(years[i]), month, day),
        ),
        WheelColumn(
          items: _months,
          selectedIndex: (month - 1).clamp(0, 11),
          width: 68,
          onChanged: (i) => emit(year, i + 1, day),
        ),
        WheelColumn(
          items: days,
          selectedIndex: (day - 1).clamp(0, days.length - 1),
          width: 60,
          onChanged: (i) => emit(year, month, i + 1),
        ),
      ],
    );
  }
}

/// `PickerSheet` — the 取消 / title / 完成 wrapper hosting a wheel.
class PickerSheet extends StatelessWidget {
  const PickerSheet({
    super.key,
    required this.title,
    required this.child,
    this.onDone,
  });

  final String title;
  final Widget child;
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    return AppSheet(
      showHandle: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 9),
            child: Row(
              children: [
                // `grid-template-columns: 1fr auto 1fr` keeps the title centred
                // regardless of label width.
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _PickerAction(
                      label: '取消',
                      // 带结果 pop：调用方要能区分「取消」与「完成」。
                      // 两者都只是 `pop()` 时，滚了轮再点取消的草稿照样会被提交。
                      onTap: () => Navigator.of(context).pop(false),
                      color: tokens.textMuted,
                    ),
                  ),
                ),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.42,
                    color: tokens.textPrimary,
                  ),
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: _PickerAction(
                      label: '完成',
                      color: tokens.accent,
                      bold: true,
                      onTap: () {
                        AppHaptics.tap();
                        onDone?.call();
                        Navigator.of(context).pop(true);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              13,
              20,
              MediaQuery.of(context).padding.bottom + 22,
            ),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _PickerAction extends StatelessWidget {
  const _PickerAction({
    required this.label,
    required this.onTap,
    required this.color,
    this.bold = false,
  });

  final String label;
  final VoidCallback onTap;
  final Color color;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      haptic: false,
      scale: 0.96,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 44),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 17,
              fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

/// Convenience for pushing a picker sheet from a page.
///
/// 返回值就是路由的结果，调用方据此决定要不要提交草稿：
/// `true` = 点了「完成」，`false` = 点了「取消」，`null` = 下滑或点遮罩关掉
/// （都算没确认）。**只有 `true` 才该落库**——弹层里的滚动是即时的，
/// 草稿与「用户确认过」是两件事。
///
/// 向后兼容：忽略返回值的调用方（编辑页的两个 picker）行为不变。
Future<bool?> showPickerSheet({
  required BuildContext context,
  required String title,
  required Widget child,
}) {
  return showAppSheet<bool>(
    context: context,
    builder: (context) => PickerSheet(title: title, child: child),
  );
}
