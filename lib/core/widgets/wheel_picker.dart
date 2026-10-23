import 'package:flutter/material.dart';

import '../platform/haptics.dart';
import '../theme/app_tokens.dart';
import 'app_basics.dart';
import 'app_sheet.dart';

/// `HH:mm` ↔「距本地午夜的分钟数」。
///
/// 设置页的提醒时刻与会话抽屉的起床闹钟都要这一对换算。此前两处各写了一遍
/// **逐字符相同**的实现——那是 `CLAUDE.md` 点名的反模式，本项目已经为「两份
/// `7*60`」付过一次代价：改一处忘一处，症状只在某条特定路径上才显形。
String minutesToClock(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
    '${(minutes % 60).toString().padLeft(2, '0')}';

int clockToMinutes(String clock) {
  final parts = clock.split(':').map(int.parse).toList();
  return parts[0] * 60 + parts[1];
}

/// 滚轮的一列。
///
/// 与原型 `WheelColumn` 同构：5 行可见，越靠中间字号越大、颜色越深、字距越紧，
/// CSS 那层端部淡出用 [ShaderMask] 复现。两处刻意的不同——行距 36px 而非原型的
/// 44px（§8 偏差 #53），以及时刻列可以首尾相接（[looping]，偏差 #55）。
class WheelColumn extends StatefulWidget {
  const WheelColumn({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onChanged,
    this.width = 80,
    this.looping = false,
  });

  final List<String> items;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final double width;

  /// 首尾相接：滚到底不会停住，而是绕回开头（iOS 闹钟的小时/分钟就是这样）。
  ///
  /// **只给时间用，日期不用**——「2024 年再往前」没有意义，而且滚到 13 月、
  /// 2 月 31 日这类格子只有循环列才画得出来。
  final bool looping;

  /// 一行的高度。原型是 44，v3.23 按使用方要求收紧到 36：同样一段手指行程能滚过
  /// 更多格，滚起来省力（见规格 §8 偏差 #53）。
  static const double itemExtent = 36;
  static const int visibleItems = 5;

  @override
  State<WheelColumn> createState() => _WheelColumnState();
}

class _WheelColumnState extends State<WheelColumn> {
  late FixedExtentScrollController _controller;

  /// 当前格子的下标。**循环列里它不受 `[0, items.length)` 限制**：往上滚会一直
  /// 增长、往下滚会变成负数，取值时统一走 [_wrap]。列首尾相接之后本来就「没有
  /// 头尾」，硬把它夹回一圈之内反而要额外做一次看不见的归位跳转。
  late int _active;

  int get _length => widget.items.length;

  /// 取模到 `[0, length)`。Dart 的 `%` 对负数已经返回非负结果（`-1 % 24 == 23`），
  /// 这里补一次 `+ length` 只是为了把这件事写明。
  static int _wrap(int index, int length) => (index % length + length) % length;

  /// 循环列里与 [target] 同值、离 [from] 最近的格子。
  ///
  /// 父层换了值要归位时用它：从 23 直接跳到 0 值虽然一样，用户看到的却是整圈飞转。
  int _nearest(int from, int target) {
    final forward = _wrap(target - from, _length);
    return forward <= _length ~/ 2 ? from + forward : from + forward - _length;
  }

  @override
  void initState() {
    super.initState();
    _active = widget.selectedIndex.clamp(0, _length - 1);
    _controller = FixedExtentScrollController(initialItem: _active);
  }

  @override
  void didUpdateWidget(covariant WheelColumn oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-centre when a parent changes the value (e.g. switching provider resets
    // the model list).
    if (widget.selectedIndex != oldWidget.selectedIndex) {
      final clamped = widget.selectedIndex.clamp(0, _length - 1);
      final target = widget.looping ? _nearest(_active, clamped) : clamped;
      if (target != _active) _active = target;
      if (_controller.hasClients && _controller.selectedItem != target) {
        _controller.jumpToItem(target);
      }
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
            // 对外只报一圈之内的下标：调用方拿它是去 `items[...]` 取值的。
            widget.onChanged(widget.looping ? _wrap(index, _length) : index);
          },
          childDelegate: ListWheelChildBuilderDelegate(
            // 循环列不报总数（`childCount: null`）：视口据此把上下都当成无边界的，
            // 于是两头都能继续滚（见 `_minEstimatedScrollExtent`）。
            childCount: widget.looping ? null : _length,
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
                  child: Text(
                    widget.items[_wrap(index, _length)],
                    maxLines: 1,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Shared shell: the columns centred in a fixed-height band, with the selected
/// row's backing colour painted behind them.
///
/// The prototype draws a `wheel-selection-rail` here — two hairlines bounding
/// the selected row — and those are still deliberately **not** reproduced
/// (removed on request; its own version was a 30% accent mixed into
/// `--border-strong`, far more muted than the pure-accent lines this used to
/// paint). What is painted instead is the **底色**横条 the design's iOS
/// reference has, added on request in v3.23 — see 偏差 #53. The two are
/// different elements: putting the hairlines back still means `border-top` /
/// `border-bottom`.
///
/// 底色画在**列的下面**（`Stack` 的第一层），所以它不受列自己的 `ShaderMask`
/// 影响——那个遮罩是给滚出视野的文字做淡出的，套到横条上会把两端啃掉。
class _WheelShell extends StatelessWidget {
  const _WheelShell({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    return SizedBox(
      height: WheelColumn.itemExtent * WheelColumn.visibleItems,
      child: Center(
        // 宽度贴合内容（`MainAxisSize.min` + 外面这层 `Center`），底色才不会在
        // 宽屏上拉成一整条横贯屏幕的带子——原型那两条线也是贴着数字的。
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              top: WheelColumn.itemExtent * 2,
              bottom: WheelColumn.itemExtent * 2,
              child: DecoratedBox(
                key: const ValueKey('wheel-selection-band'),
                decoration: BoxDecoration(
                  color: tokens.accentSoft,
                  borderRadius: BorderRadius.circular(AppRadii.wheelHighlight),
                ),
              ),
            ),
            // 数字离横条两端留一点边，否则贴边看着像被裁掉。
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: children,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `TimePicker` — 24 hour and 60 minute columns joined by a centred colon.
///
/// **[value] 只是初始值。** 弹层打开后父层送不进新值：`showAppSheet` 的
/// `pageBuilder` 拿到的是调用点构造好的那一个 `child` 实例，调用方再 `setState`
/// 也不会重建它（`log_page` / 睡眠设置页 / 会话页三处都是这个形状）。所以两列的
/// 当前值只能由本 widget 自己拿着——`onChanged` 若还去读上一次 build 解析出的
/// `hour` / `minute`，先滚小时再滚分钟就会拿**旧的**小时去拼新值：草稿被写成
/// `23:30`，点「完成」小时弹回原样。只滚小时的那条路径偏偏看不出问题，因为那一格
/// 没有被第二列覆盖。
class AppTimePicker extends StatefulWidget {
  const AppTimePicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  /// `HH:mm`。初始值；父层主动换一个值传进来时也以它为准。
  final String value;
  final ValueChanged<String> onChanged;

  static final _hours = List.generate(24, (i) => i.toString().padLeft(2, '0'));
  static final _minutes =
      List.generate(60, (i) => i.toString().padLeft(2, '0'));

  static int _hourOf(String value) =>
      (int.tryParse(value.split(':').first) ?? 0).clamp(0, 23);

  static int _minuteOf(String value) {
    final parts = value.split(':');
    return (parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0).clamp(0, 59);
  }

  @override
  State<AppTimePicker> createState() => _AppTimePickerState();
}

class _AppTimePickerState extends State<AppTimePicker> {
  late int _hour;
  late int _minute;

  @override
  void initState() {
    super.initState();
    _hour = AppTimePicker._hourOf(widget.value);
    _minute = AppTimePicker._minuteOf(widget.value);
  }

  @override
  void didUpdateWidget(covariant AppTimePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 父层真换了值才采纳，而且只在它和自己当前的值不同时——把刚滚出来的值原样
    // 传回来的调用方（三处都是）不该被当成一次外部改值，否则会和滚动抢方向。
    if (widget.value != oldWidget.value) {
      final hour = AppTimePicker._hourOf(widget.value);
      final minute = AppTimePicker._minuteOf(widget.value);
      if (hour != _hour || minute != _minute) {
        _hour = hour;
        _minute = minute;
      }
    }
  }

  /// 两列共用一条出口：`hour` / `minute` 在**调用时**从状态里读，所以先滚哪一列
  /// 都不会把另一列冲掉。
  ///
  /// 值没变就直接返回，不 `setState` 也不回调：`WheelColumn` 在 `didUpdateWidget`
  /// 里 `jumpToItem`（父层换了值时会走到），`ListWheelScrollView` 会**同步**回调
  /// `onSelectedItemChanged`——于是它在我们正在 build 的时候又喊一次 `onChanged`。
  /// 放它过去就是「setState() called during build」。
  void _select(int hour, int minute) {
    if (hour == _hour && minute == _minute) return;
    setState(() {
      _hour = hour;
      _minute = minute;
    });
    widget.onChanged(
      '${AppTimePicker._hours[_hour]}:${AppTimePicker._minutes[_minute]}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    return _WheelShell(
      children: [
        WheelColumn(
          items: AppTimePicker._hours,
          selectedIndex: _hour,
          width: 72,
          // 小时与分钟首尾相接：23 的上一格是 00，00 的下一格是 23。日期不循环。
          looping: true,
          onChanged: (i) => _select(i, _minute),
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
          items: AppTimePicker._minutes,
          selectedIndex: _minute,
          width: 72,
          looping: true,
          onChanged: (i) => _select(_hour, i),
        ),
      ],
    );
  }
}

/// `DatePicker` — year / month / day columns over a five-year window.
///
/// 与 [AppTimePicker] 同一条约束：[value] 只是初始值，三列的一致性由本 widget
/// 自己维持。父层送不进新值，`emit` 若去读 build 时的 `year` / `month` / `day`，
/// 先滚年再滚月年就会被旧的冲掉。日列也因此才会跟着年月重新生成——此前选完
/// 1 月 31 日再滚到 2 月，草稿已是 28 日，轮子上却还列着 31 天。
class AppDatePicker extends StatefulWidget {
  const AppDatePicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.now,
  });

  /// `YYYY-MM-DD`。初始值；父层主动换值传进来时也以它为准。
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
  State<AppDatePicker> createState() => _AppDatePickerState();
}

class _AppDatePickerState extends State<AppDatePicker> {
  late int _year;
  late int _month;
  late int _day;

  @override
  void initState() {
    super.initState();
    _adopt(widget.value);
  }

  @override
  void didUpdateWidget(covariant AppDatePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) _adopt(widget.value);
  }

  /// 解析 `YYYY-MM-DD`，缺项用今天补；日落在该月的合法范围内。
  void _adopt(String value) {
    final today = widget.now ?? DateTime.now();
    final parts = value.split('-').map(int.tryParse).toList();
    final year = parts.isNotEmpty ? (parts[0] ?? today.year) : today.year;
    final month = parts.length > 1 ? (parts[1] ?? today.month) : today.month;
    final day = parts.length > 2 ? (parts[2] ?? today.day) : today.day;
    _year = year;
    _month = month.clamp(1, 12);
    _day = day.clamp(1, AppDatePicker._daysInMonth(_year, _month));
  }

  /// 与 [AppTimePicker] 的 `_select` 同理：`year` / `month` / `day` 调用时才读，
  /// 值没变就不出声（日列收窄时 `jumpToItem` 会同步回调一次，见那里的注释）。
  void _select(int year, int month, int day) {
    // 1 月 31 日滚到 2 月，日必须跟着落回 28/29。
    final maxDay = AppDatePicker._daysInMonth(year, month);
    final clamped = day > maxDay ? maxDay : day;
    if (year == _year && month == _month && clamped == _day) return;

    setState(() {
      _year = year;
      _month = month;
      _day = clamped;
    });
    widget.onChanged(
      '$_year-${_month.toString().padLeft(2, '0')}-'
      '${_day.toString().padLeft(2, '0')}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final today = widget.now ?? DateTime.now();

    final years = List.generate(5, (i) => '${today.year - 2 + i}');
    final days = List.generate(
      AppDatePicker._daysInMonth(_year, _month),
      (i) => (i + 1).toString().padLeft(2, '0'),
    );
    final yearIndex = years.indexOf('$_year');

    return _WheelShell(
      children: [
        WheelColumn(
          items: years,
          selectedIndex: yearIndex < 0 ? 2 : yearIndex,
          width: 76,
          onChanged: (i) => _select(int.parse(years[i]), _month, _day),
        ),
        WheelColumn(
          items: AppDatePicker._months,
          selectedIndex: (_month - 1).clamp(0, 11),
          width: 68,
          onChanged: (i) => _select(_year, i + 1, _day),
        ),
        WheelColumn(
          items: days,
          selectedIndex: (_day - 1).clamp(0, days.length - 1),
          width: 60,
          onChanged: (i) => _select(_year, _month, i + 1),
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
      scrollable: true,
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
            padding: const EdgeInsets.fromLTRB(20, 13, 20, 22),
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
