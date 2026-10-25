import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/platform/haptics.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_basics.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/quiet_surface.dart';
import '../../../core/widgets/subpage.dart';
import '../../sleep/data/sleep_repository.dart';
import '../../sleep/domain/sleep_entry.dart';
import '../../sleep/presentation/sheets/detail_sheet.dart';

/// 月历网格轮播的 key。
const Key calendarMonthPageViewKey = Key('calendar-month-page-view');

/// 睡眠日历：按月回看每一晚，并从日期直接进入当晚详情。
class SleepCalendarPage extends ConsumerWidget {
  const SleepCalendarPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTokens.of(context);
    return ref.watch(sleepEntriesProvider).when(
          loading: () => const Subpage(
            title: '睡眠日历',
            children: [
              SizedBox(
                height: 280,
                child: Center(child: CircularProgressIndicator()),
              ),
            ],
          ),
          error: (error, stack) => Subpage(
            title: '睡眠日历',
            children: [
              EmptyState(
                icon: AppIcons.calendar(
                  size: 30,
                  color: tokens.danger,
                  strokeWidth: 1.6,
                ),
                title: '无法读取睡眠记录',
                body: '本地数据库打开失败：$error',
              ),
            ],
          ),
          data: (records) => Subpage(
            title: '睡眠日历',
            maxContentWidth: 720,
            children: [_SleepCalendar(records: records)],
          ),
        );
  }
}

class _SleepCalendar extends StatefulWidget {
  const _SleepCalendar({required this.records});

  final List<SleepEntry> records;

  @override
  State<_SleepCalendar> createState() => _SleepCalendarState();
}

class _SleepCalendarState extends State<_SleepCalendar> {
  final GlobalKey<_CalendarMonthViewState> _monthViewKey = GlobalKey();

  late DateTime _month;
  String? _selectedDate;

  List<SleepEntry> get _sorted {
    final entries = [...widget.records]
      ..sort((a, b) => b.dateLabel.compareTo(a.dateLabel));
    return entries;
  }

  @override
  void initState() {
    super.initState();
    final sorted = _sorted;
    final latest = sorted.isEmpty ? DateTime.now() : sorted.first.wakeLocal;
    _month = DateTime(latest.year, latest.month);
    _selectedDate = sorted.isEmpty ? null : sorted.first.dateLabel;
  }

  void _selectMonth(DateTime month) {
    setState(() {
      _month = DateTime(month.year, month.month);
      _selectedDate = null;
    });
  }

  void _selectDate(String date) {
    AppHaptics.select();
    setState(() => _selectedDate = date);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final sorted = _sorted;
    final recordMap = <String, SleepEntry>{
      for (final entry in sorted.reversed) entry.dateLabel: entry,
    };
    final prefix = '${_month.year}-${_month.month.toString().padLeft(2, '0')}';
    final monthRecords =
        sorted.where((entry) => entry.dateLabel.startsWith(prefix)).toList();
    final averageHours = monthRecords.isEmpty
        ? null
        : monthRecords.fold<double>(
              0,
              (sum, entry) => sum + entry.durationHours,
            ) /
            monthRecords.length;
    final scored = monthRecords.where((entry) => entry.score != null).toList();
    final averageScore = scored.isEmpty
        ? null
        : (scored.fold<int>(0, (sum, entry) => sum + entry.score!) /
                scored.length)
            .round();
    final selected = _selectedDate == null ? null : recordMap[_selectedDate!];
    final demoCount =
        sorted.where((entry) => entry.source == AppConfig.demoSource).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CalendarHero(
          month: _month.month,
          count: monthRecords.length,
          streak: _streak(sorted),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _Metric(
                icon: AppIcons.moon(
                  size: 18,
                  color: tokens.accent,
                  strokeWidth: 1.7,
                ),
                label: '平均时长',
                value: averageHours == null
                    ? '—'
                    : '${averageHours.toStringAsFixed(1)} h',
                iconColor: tokens.accent,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Metric(
                icon: AppIcons.sparkle(
                  size: 18,
                  color: tokens.accentViolet,
                  strokeWidth: 1.7,
                ),
                label: '平均评分',
                value: averageScore == null ? '—' : '$averageScore 分',
                iconColor: tokens.accentViolet,
              ),
            ),
          ],
        ),
        if (demoCount > 0) ...[
          const SizedBox(height: 10),
          Text(
            '这 $demoCount 条是演示记录，不是真实测量；可在「设置 › 演示数据」中清除。',
            style:
                TextStyle(fontSize: 11, height: 1.5, color: tokens.textMuted),
          ),
        ],
        const SizedBox(height: 18),
        QuietSurface(
          borderRadius: BorderRadius.circular(22),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
          child: Column(
            children: [
              Row(
                children: [
                  _MonthButton(
                    semanticLabel: '上个月',
                    onTap: () => _monthViewKey.currentState?.showPrevious(),
                    icon: Transform.rotate(
                      angle: 3.1415926535897932,
                      child: AppIcons.chevronRight(
                        size: 18,
                        color: tokens.textSecondary,
                        strokeWidth: 1.9,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '${_month.year} 年 ${_month.month} 月',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: tokens.textPrimary,
                      ),
                    ),
                  ),
                  _MonthButton(
                    semanticLabel: '下个月',
                    onTap: () => _monthViewKey.currentState?.showNext(),
                    icon: AppIcons.chevronRight(
                      size: 18,
                      color: tokens.textSecondary,
                      strokeWidth: 1.9,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final day in const ['一', '二', '三', '四', '五', '六', '日'])
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        child: Text(
                          day,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 10,
                            color: tokens.textMuted,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              _CalendarMonthView(
                key: _monthViewKey,
                month: _month,
                records: recordMap,
                selectedDate: _selectedDate,
                onSelectDate: _selectDate,
                onMonthChanged: _selectMonth,
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: tokens.good,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '已记录睡眠',
                    style: TextStyle(fontSize: 10, color: tokens.textMuted),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (_selectedDate != null && selected == null)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: tokens.borderStrong),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _dayLabel(_selectedDate!),
                  style: TextStyle(fontSize: 10, color: tokens.textMuted),
                ),
                const SizedBox(height: 4),
                Text(
                  '这一天还没有记录',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: tokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        if (selected != null)
          _SelectedNightCard(
            entry: selected,
            onTap: () => showSleepDetailSheet(context, selected),
          ),
      ],
    );
  }

  static int _streak(List<SleepEntry> records) {
    final dates = records.map((entry) => entry.archiveDay).toSet().toList()
      ..sort((a, b) => b.compareTo(a));
    if (dates.isEmpty) return 0;
    var streak = 1;
    for (var index = 1; index < dates.length; index++) {
      if (dates[index - 1].difference(dates[index]).inDays != 1) break;
      streak++;
    }
    return streak;
  }

  static String _dayLabel(String date) {
    final parts = date.split('-');
    return '${int.parse(parts[1])} 月 ${int.parse(parts[2])} 日';
  }
}

/// 月历网格轮播。
///
/// 三页分别是上月、当前月、下月；左右滑动吸附后提交新月份并回到中间页，
/// 因而可以连续向前或向后翻，而不用一次构建所有月份。
class _CalendarMonthView extends StatefulWidget {
  const _CalendarMonthView({
    super.key,
    required this.month,
    required this.records,
    required this.selectedDate,
    required this.onSelectDate,
    required this.onMonthChanged,
  });

  final DateTime month;
  final Map<String, SleepEntry> records;
  final String? selectedDate;
  final ValueChanged<String> onSelectDate;
  final ValueChanged<DateTime> onMonthChanged;

  @override
  State<_CalendarMonthView> createState() => _CalendarMonthViewState();
}

class _CalendarMonthViewState extends State<_CalendarMonthView> {
  late final PageController _pageController = PageController(initialPage: 1);

  bool _committingPage = false;
  int _visiblePage = 1;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void showPrevious() {
    _animateToPage(0);
  }

  void showNext() {
    _animateToPage(2);
  }

  void _animateToPage(int page) {
    if (!_pageController.hasClients) return;
    _pageController.animateToPage(
      page,
      duration: MediaQuery.maybeDisableAnimationsOf(context) ?? false
          ? Duration.zero
          : const Duration(milliseconds: 300),
      curve: AppMotion.standardCurve,
    );
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is! ScrollEndNotification ||
        _committingPage ||
        !_pageController.hasClients) {
      return false;
    }

    final metrics = notification.metrics;
    final page = metrics is PageMetrics
        ? metrics.page?.round() ?? _visiblePage
        : _visiblePage;
    if (page == 0) {
      _commitMonth(-1);
    } else if (page == 2) {
      _commitMonth(1);
    }
    return false;
  }

  void _commitMonth(int offset) {
    _committingPage = true;
    _visiblePage = 1;
    _pageController.jumpToPage(1);
    widget.onMonthChanged(
      DateTime(widget.month.year, widget.month.month + offset),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _committingPage = false;
    });
  }

  DateTime _monthAt(int index) => DateTime(
        widget.month.year,
        widget.month.month + (index - 1),
      );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final dayExtent = constraints.maxWidth / 7;
        return SizedBox(
          height: dayExtent * 6,
          child: NotificationListener<ScrollEndNotification>(
            onNotification: _onScrollNotification,
            child: PageView.builder(
              key: calendarMonthPageViewKey,
              controller: _pageController,
              itemCount: 3,
              padEnds: false,
              allowImplicitScrolling: true,
              physics: const PageScrollPhysics(),
              onPageChanged: (page) {
                _visiblePage = page;
                if (!_committingPage) AppHaptics.select();
              },
              itemBuilder: (context, index) {
                return _CalendarMonthGrid(
                  month: _monthAt(index),
                  records: widget.records,
                  selectedDate: index == 1 ? widget.selectedDate : null,
                  onSelectDate: widget.onSelectDate,
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _CalendarMonthGrid extends StatelessWidget {
  const _CalendarMonthGrid({
    required this.month,
    required this.records,
    required this.selectedDate,
    required this.onSelectDate,
  });

  final DateTime month;
  final Map<String, SleepEntry> records;
  final String? selectedDate;
  final ValueChanged<String> onSelectDate;

  @override
  Widget build(BuildContext context) {
    final prefix = '${month.year}-${month.month.toString().padLeft(2, '0')}';
    final leading =
        (DateTime(month.year, month.month).weekday - DateTime.monday) % 7;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final cells = <int?>[
      for (var index = 0; index < 42; index++)
        if (index >= leading && index - leading < daysInMonth)
          index - leading + 1
        else
          null,
    ];

    return GridView.builder(
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        childAspectRatio: 1,
      ),
      itemCount: cells.length,
      itemBuilder: (context, index) {
        final day = cells[index];
        if (day == null) return const SizedBox.shrink();
        final date = '$prefix-${day.toString().padLeft(2, '0')}';
        return Padding(
          padding: const EdgeInsets.all(2),
          child: _DayCell(
            day: day,
            date: date,
            entry: records[date],
            selected: date == selectedDate,
            onTap: () => onSelectDate(date),
          ),
        );
      },
    );
  }
}

class _CalendarHero extends StatelessWidget {
  const _CalendarHero({
    required this.month,
    required this.count,
    required this.streak,
  });

  final int month;
  final int count;
  final int streak;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 154),
      padding: const EdgeInsets.fromLTRB(24, 22, 18, 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF123A73), Color(0xFF315CBE), Color(0xFF6855BC)],
          stops: [0, 0.54, 1],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x331E488B),
            blurRadius: 38,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            right: -76,
            bottom: -106,
            child: Container(
              width: 190,
              height: 190,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0x21FFFFFF)),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$month 月睡眠足迹',
                      style: const TextStyle(
                        color: Color(0xB3FFFFFF),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.44,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '$count',
                            style: AppTheme.num(
                              context,
                              size: 34,
                              weight: FontWeight.w600,
                              color: Colors.white,
                              letterSpacing: -1.36,
                            ),
                          ),
                          const TextSpan(
                            text: ' 晚已记录',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      streak > 1 ? '已连续记录 $streak 天，继续保持' : '每一次记录，都让睡眠更清晰',
                      style: const TextStyle(
                        color: Color(0xB8FFFFFF),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const _CalendarMoon(),
            ],
          ),
        ],
      ),
    );
  }
}

class _CalendarMoon extends StatelessWidget {
  const _CalendarMoon();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 84,
      height: 84,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 12,
            top: 12,
            width: 60,
            height: 60,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.white, Color(0xFFDBE8FF)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x80D3E7FF),
                    blurRadius: 30,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: -1,
            top: 5,
            width: 58,
            height: 58,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color(0xFF315CBE),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            right: 1,
            top: 3,
            child: _StarDot(size: 4),
          ),
          Positioned(
            right: 3,
            bottom: 8,
            child: _StarDot(size: 3, opacity: 0.65),
          ),
        ],
      ),
    );
  }
}

class _StarDot extends StatelessWidget {
  const _StarDot({required this.size, this.opacity = 1});

  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: opacity),
        shape: BoxShape.circle,
        boxShadow: const [
          BoxShadow(color: Colors.white, blurRadius: 8),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.icon,
    required this.label,
    required this.value,
    required this.iconColor,
  });

  final Widget icon;
  final String label;
  final String value;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return QuietSurface(
      borderRadius: BorderRadius.circular(18),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: icon,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 9, color: tokens.textMuted),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.num(
                    context,
                    size: 19,
                    weight: FontWeight.w600,
                    color: tokens.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthButton extends StatelessWidget {
  const _MonthButton({
    required this.semanticLabel,
    required this.onTap,
    required this.icon,
  });

  final String semanticLabel;
  final VoidCallback onTap;
  final Widget icon;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Pressable(
        haptic: false,
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: tokens.bgMuted,
            shape: BoxShape.circle,
          ),
          child: icon,
        ),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.date,
    required this.entry,
    required this.selected,
    required this.onTap,
  });

  final int day;
  final String date;
  final SleepEntry? entry;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final color = _qualityColor(tokens, entry?.quality?.value);
    final hasRecord = entry != null;

    return Semantics(
      button: true,
      selected: selected,
      label: '$day 日，${hasRecord ? '有睡眠记录' : '无睡眠记录'}',
      excludeSemantics: true,
      child: Pressable(
        haptic: false,
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppDurations.control,
          curve: AppMotion.standardCurve,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? color
                : hasRecord
                    ? color.withValues(alpha: 0.12)
                    : Colors.transparent,
            shape: BoxShape.circle,
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.25),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Center(
                child: Text(
                  '$day',
                  style: AppTheme.num(
                    context,
                    size: 12,
                    weight: hasRecord ? FontWeight.w700 : FontWeight.w500,
                    color: selected
                        ? Colors.white
                        : hasRecord
                            ? color
                            : tokens.textSecondary,
                  ),
                ),
              ),
              if (hasRecord)
                Positioned(
                  right: -1,
                  bottom: -1,
                  child: Container(
                    width: 13,
                    height: 13,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: tokens.good,
                      shape: BoxShape.circle,
                      border: Border.all(color: tokens.bgCardSolid, width: 2),
                    ),
                    child: AppIcons.check(
                      size: 7,
                      color: Colors.white,
                      strokeWidth: 3,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static Color _qualityColor(AppTokens tokens, int? quality) {
    return switch (quality) {
      1 => tokens.danger,
      2 => tokens.warn,
      3 => tokens.caution,
      4 => tokens.good,
      5 => tokens.accentViolet,
      _ => tokens.accent,
    };
  }
}

class _SelectedNightCard extends StatelessWidget {
  const _SelectedNightCard({required this.entry, required this.onTap});

  final SleepEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final local = entry.wakeLocal;
    return QuietSurface(
      borderRadius: BorderRadius.circular(20),
      padding: const EdgeInsets.all(18),
      onTap: onTap,
      semanticLabel: '查看 ${local.month} 月 ${local.day} 日睡眠详情',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${local.month} 月 ${local.day} 日',
                      style: TextStyle(fontSize: 10, color: tokens.textMuted),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '这一晚已记录',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: tokens.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '查看详情',
                style: TextStyle(fontSize: 10, color: tokens.accent),
              ),
              const SizedBox(width: 3),
              AppIcons.chevronRight(
                size: 13,
                color: tokens.accent,
                strokeWidth: 2,
              ),
            ],
          ),
          const SizedBox(height: 13),
          Container(height: 1, color: tokens.border),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 8,
                child: _NightStat(
                  label: '时长',
                  value: '${entry.durationHours.toStringAsFixed(1)}h',
                ),
              ),
              Container(width: 1, height: 34, color: tokens.border),
              Expanded(
                flex: 15,
                child: Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: _NightStat(
                    label: '时间',
                    value: '${entry.bedtimeLabel}–${entry.wakeLabel}',
                  ),
                ),
              ),
              Container(width: 1, height: 34, color: tokens.border),
              Expanded(
                flex: 7,
                child: Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: _NightStat(
                    label: '评分',
                    value: entry.score?.toString() ?? '—',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NightStat extends StatelessWidget {
  const _NightStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 9, color: tokens.textMuted)),
        const SizedBox(height: 5),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTheme.num(
            context,
            size: 14,
            weight: FontWeight.w600,
            color: tokens.textPrimary,
          ),
        ),
      ],
    );
  }
}
