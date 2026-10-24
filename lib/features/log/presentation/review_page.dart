import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_shell.dart';
import '../../../app/app_toast.dart';
import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_basics.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/ios_controls.dart';
import '../../../core/widgets/quiet_surface.dart';
import '../../../core/widgets/wheel_picker.dart';
import '../../sleep/data/sleep_repository.dart';
import '../../sleep/domain/sleep_entry.dart';
import '../../sleep/domain/sleep_math.dart';
import '../../sleep/domain/sleep_quality.dart';
import '../../sleep/domain/sleep_score.dart';
import '../../sleep/domain/sleep_window.dart';
import '../../sleep/presentation/widgets/quality_rating.dart';
import '../../sleep/presentation/widgets/event_tiles.dart';
import '../../sleep/presentation/widgets/sleep_summary.dart';
import '../../sleep/presentation/widgets/stage_style.dart';
import 'review_duration_hero.dart';
import 'review_night_picker.dart';

/// 回顾 Tab：给已经存在的一晚补充时间、感受、事件和备注。
///
/// 页面默认指向最近一条真实记录。演示数据不会被当作用户记录改写；需要补录时
/// 走 `/log/new`。
class ReviewPage extends ConsumerStatefulWidget {
  const ReviewPage({super.key});

  @override
  ConsumerState<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends ConsumerState<ReviewPage> {
  /// 只存 id，不存记录对象；刷新后仍能回到最新版本。
  String? _selectedId;

  SleepEntry? _resolve(List<SleepEntry> entries) {
    final id = _selectedId;
    if (id != null) {
      for (final entry in entries) {
        if (entry.id == id) return entry;
      }
    }
    return entries.isEmpty ? null : entries.first;
  }

  Future<void> _pickNight(List<SleepEntry> entries, SleepEntry current) async {
    final picked = await showReviewNightPicker(
      context,
      entries: entries,
      currentId: current.id,
    );
    if (picked == null || !mounted) return;
    setState(() => _selectedId = picked.id);
  }

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(sleepEntriesProvider);
    final inset = EdgeInsets.only(
      top: pageTopInset(context),
      bottom: pageBottomInset(context),
      left: pageGutter(context),
      right: pageGutter(context),
    );

    return entries.when(
      loading: () => Padding(
        padding: inset,
        child: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, stack) => Padding(
        padding: inset,
        child: EmptyState(
          icon: AppIcons.moon(
            size: 30,
            color: Theme.of(context).colorScheme.error,
          ),
          title: '无法读取记录',
          body: '本地数据库打开失败：$error',
        ),
      ),
      data: (records) => _content(context, records),
    );
  }

  Widget _content(BuildContext context, List<SleepEntry> records) {
    final real =
        records.where((entry) => entry.source != AppConfig.demoSource).toList();
    final selected = _resolve(real);
    final children = <Widget>[
      const PageHeading(title: '睡得怎么样？'),
      const SizedBox(height: 5),
      Text(
        '补充醒来后的感受；时间和事件也可以在这里修正。',
        style: TextStyle(
          fontSize: 13,
          height: 1.6,
          color: AppTokens.of(context).textSecondary,
        ),
      ),
      const SizedBox(height: 20),
    ];

    if (selected == null) {
      children.add(_NoNightState(hasDemoData: records.isNotEmpty));
    } else {
      children.add(
        _ReviewEditor(
          key: ValueKey(selected.id),
          entry: selected,
          onPickNight: () => _pickNight(real, selected),
        ),
      );
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(
        pageGutter(context),
        pageTopInset(context),
        pageGutter(context),
        pageBottomInset(context),
      ),
      children: children,
    );
  }
}

/// 空状态：没有可回顾的真实记录。
class _NoNightState extends StatelessWidget {
  const _NoNightState({required this.hasDemoData});

  final bool hasDemoData;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return EmptyState(
      icon: AppIcons.moon(size: 30, color: tokens.accent, strokeWidth: 1.6),
      title: hasDemoData ? '只有演示数据，不能补充' : '还没有可回顾的记录',
      body: hasDemoData
          ? '演示记录是样本，不是你自己的睡眠。要回顾自己的某一晚，先手动补录一条。'
          : '补录第一晚之后，就能在这里补充当晚的感受了。',
      actionLabel: '手动补录某一晚',
      onAction: () => context.push('/log/new'),
    );
  }
}

class _ReviewEditor extends ConsumerStatefulWidget {
  const _ReviewEditor({
    super.key,
    required this.entry,
    required this.onPickNight,
  });

  final SleepEntry entry;
  final VoidCallback onPickNight;

  @override
  ConsumerState<_ReviewEditor> createState() => _ReviewEditorState();
}

class _ReviewEditorState extends ConsumerState<_ReviewEditor> {
  late SleepQuality? _quality;
  late LoggedEvents _events;
  late final TextEditingController _notesController;
  late final String _originalDate;
  late final String _originalBedtime;
  late final String _originalWakeTime;
  late String _date;
  late String _bedtime;
  late String _wakeTime;
  bool _saving = false;

  SleepEntry get _entry => widget.entry;

  SleepWindow get _window => buildSleepWindow(
        wakeDate: parseIsoDate(_date, _entry.wakeLocal),
        bedtime: _bedtime,
        wakeTime: _wakeTime,
      );

  bool get _timingChanged =>
      _date != _originalDate ||
      _bedtime != _originalBedtime ||
      _wakeTime != _originalWakeTime;

  @override
  void initState() {
    super.initState();
    _quality = _entry.quality;
    _events = _entry.loggedEvents;
    _notesController = TextEditingController(text: _entry.notes);
    _originalDate = formatIsoDate(_entry.wakeLocal);
    _originalBedtime = formatClock(_entry.bedtimeLocal);
    _originalWakeTime = formatClock(_entry.wakeLocal);
    _date = _originalDate;
    _bedtime = _originalBedtime;
    _wakeTime = _originalWakeTime;
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    await showPickerSheet(
      context: context,
      title: '选择日期',
      child: AppDatePicker(
        value: _date,
        onChanged: (value) => setState(() => _date = value),
      ),
    );
  }

  Future<void> _pickTime({required bool bedtime}) async {
    await showPickerSheet(
      context: context,
      title: bedtime ? '入睡时间' : '起床时间',
      child: AppTimePicker(
        value: bedtime ? _bedtime : _wakeTime,
        onChanged: (value) => setState(() {
          if (bedtime) {
            _bedtime = value;
          } else {
            _wakeTime = value;
          }
        }),
      ),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    final window = _window;
    if (_timingChanged && !window.isPlausible) {
      ref.read(toastProvider.notifier).show('睡眠时长需要在 0 到 24 小时之间。');
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(sleepRepositoryProvider).save(
            id: _entry.id,
            startAtUtc: _timingChanged ? window.startAtUtc : _entry.startAtUtc,
            endAtUtc: _timingChanged ? window.endAtUtc : _entry.endAtUtc,
            timeZoneId: _timingChanged ? window.timeZoneId : _entry.timeZoneId,
            quality: _quality,
            notes: _notesController.text.trim(),
            events: _events,
            source: _entry.source,
            // 留空 = 保持已有阶段不变。补感受或改时间都不能抹掉设备测量。
          );
      if (!mounted) return;
      setState(() => _saving = false);
      ref.read(toastProvider.notifier).show('已更新这一晚的感受。');
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ref.read(toastProvider.notifier).show('保存失败：$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final window = _window;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 720;
            final available = constraints.maxWidth - (wide ? 28 : 0);
            final left = SizedBox(
              width: wide ? available / 2.2 : available,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ReviewDurationHero(
                    onTap: widget.onPickNight,
                    semanticLabel: '换一晚回顾',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                formatDate(_entry.wakeLocal),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: tokens.textSecondary,
                                ),
                              ),
                            ),
                            AppIcons.moon(
                              size: 22,
                              color: tokens.accent,
                              strokeWidth: 1.6,
                            ),
                            const SizedBox(width: 10),
                            AppIcons.chevronDown(
                              size: 16,
                              color: tokens.textMuted,
                              strokeWidth: 1.8,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SleepDuration(
                          hours: window.durationHours,
                          size: 46,
                        ),
                        const SizedBox(height: 14),
                        _DurationStatus(
                          hours: window.durationHours,
                          color: durationBandColor(
                            tokens,
                            window.durationHours,
                          ),
                        ),
                        const SizedBox(height: 11),
                        Text(
                          '来自：${_sourceLabel(_entry.source)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: tokens.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const SectionHeader('睡眠时间'),
                  IosListGroup(
                    quiet: true,
                    children: [
                      _FieldRow(
                        label: '日期',
                        value: _date,
                        onTap: _pickDate,
                      ),
                      _FieldRow(
                        label: '入睡时间',
                        value: _bedtime,
                        onTap: () => _pickTime(bedtime: true),
                      ),
                      _FieldRow(
                        label: '起床时间',
                        value: _wakeTime,
                        onTap: () => _pickTime(bedtime: false),
                      ),
                    ],
                  ),
                  const SizedBox(height: 9),
                  Text(
                    '日期按醒来当天记录，时长会自动计算。',
                    style: TextStyle(fontSize: 10, color: tokens.textMuted),
                  ),
                ],
              ),
            );
            final right = SizedBox(
              width: wide ? available / 2.2 * 1.2 : available,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ReviewSectionHeading(
                    title: '睡眠质量',
                    trailing: _quality == null
                        ? null
                        : Text(
                            _quality!.label,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _qualityColor(tokens, _quality!),
                            ),
                          ),
                  ),
                  QuietSurface(
                    borderRadius: BorderRadius.circular(AppRadii.card),
                    borderColor: colorMix(
                      tokens.border,
                      0.6,
                      Colors.transparent,
                    ),
                    padding: const EdgeInsets.all(10),
                    child: QualityChoice(
                      value: _quality,
                      onChanged: (quality) =>
                          setState(() => _quality = quality),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const _ReviewSectionHeading(
                    title: '睡眠事件',
                    hint: '可多选',
                  ),
                  SleepEventPicker(
                    events: _events,
                    onChanged: (events) => setState(() => _events = events),
                    keyPrefix: 'review-event',
                  ),
                  const SizedBox(height: 20),
                  const _ReviewSectionHeading(title: '备注', hint: '选填'),
                  QuietSurface(
                    borderRadius: BorderRadius.circular(AppRadii.panel),
                    child: TextField(
                      controller: _notesController,
                      maxLines: 3,
                      style: TextStyle(
                        fontSize: 14,
                        color: tokens.textPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: '梦境、感受、特殊情况……',
                        hintStyle: TextStyle(
                          fontSize: 14,
                          color: tokens.textMuted,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );

            return Flex(
              direction: wide ? Axis.horizontal : Axis.vertical,
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                left,
                SizedBox(width: wide ? 28 : 0, height: wide ? 0 : 24),
                right,
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        _ReviewSaveAction(
          saving: _saving,
          onTap: _saving ? null : _save,
        ),
        const SizedBox(height: 8),
        const _ManualEntryLink(),
      ],
    );
  }

  static String _sourceLabel(String source) => switch (source) {
        'session' => '睡眠会话',
        'import' => '导入',
        _ => '手动记录',
      };

  static Color _qualityColor(AppTokens tokens, SleepQuality quality) {
    return switch (quality) {
      SleepQuality.veryPoor => tokens.danger,
      SleepQuality.poor => tokens.warn,
      SleepQuality.fair => tokens.caution,
      SleepQuality.good => tokens.good,
      SleepQuality.excellent => tokens.accentViolet,
    };
  }
}

class _ReviewSaveAction extends StatelessWidget {
  const _ReviewSaveAction({required this.saving, required this.onTap});

  final bool saving;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Opacity(
      opacity: onTap == null ? 0.55 : 1,
      child: Pressable(
        key: const ValueKey('review-save'),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 54),
          decoration: BoxDecoration(
            color: tokens.primaryActionFill,
            borderRadius: BorderRadius.circular(27),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcons.check(
                size: 18,
                color: Colors.white,
                strokeWidth: 2.2,
              ),
              const SizedBox(width: 8),
              Text(
                saving ? '保存中…' : '保存补充',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              // 与左侧图标 + 间距等宽，保证文案中心就是按钮中心。
              const SizedBox(width: 26),
            ],
          ),
        ),
      ),
    );
  }
}

class _DurationStatus extends StatelessWidget {
  const _DurationStatus({required this.hours, required this.color});

  final double hours;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final (label, icon) = switch (hours) {
      <= 0 => ('请检查睡眠时间', AppIcons.moon),
      > 9 => ('睡眠偏长', AppIcons.moon),
      >= 7 => ('时长达标', AppIcons.check),
      >= 6 => ('略显不足', AppIcons.moon),
      _ => ('睡眠不足', AppIcons.moon),
    };
    return Row(
      children: [
        icon(size: 13, color: color, strokeWidth: 2),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: color),
        ),
        const Spacer(),
        Text(
          '建议 7–9 小时',
          style: TextStyle(fontSize: 10, color: tokens.textMuted),
        ),
      ],
    );
  }
}

class _ReviewSectionHeading extends StatelessWidget {
  const _ReviewSectionHeading({
    required this.title,
    this.hint,
    this.trailing,
  });

  final String title;
  final String? hint;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: tokens.textPrimary,
              ),
            ),
          ),
          if (hint != null)
            Text(
              hint!,
              style: TextStyle(fontSize: 10, color: tokens.textMuted),
            ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return IosListItem(
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            key: ValueKey('review-time-label-cell-$label'),
            child: Text(
              key: ValueKey('review-time-label-$label'),
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: tokens.textPrimary,
              ),
            ),
          ),
          Expanded(
            key: ValueKey('review-time-value-cell-$label'),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: AppTheme.num(
                      context,
                      size: 14,
                      weight: FontWeight.w600,
                      color: tokens.accent,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                AppIcons.chevronRight(
                  size: 16,
                  color: tokens.borderStrong,
                  strokeWidth: 2,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ManualEntryLink extends StatelessWidget {
  const _ManualEntryLink();

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Center(
      child: Pressable(
        onTap: () => context.push('/log/new'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '手动补录某一晚',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: tokens.accent,
                ),
              ),
              const SizedBox(width: 4),
              AppIcons.chevronRight(
                size: 14,
                color: tokens.accent,
                strokeWidth: 2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
