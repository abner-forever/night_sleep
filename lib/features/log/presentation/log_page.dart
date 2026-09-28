import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_shell.dart';
import '../../../app/app_toast.dart';
import '../../../core/platform/haptics.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_basics.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/glass_surface.dart';
import '../../../core/widgets/ios_controls.dart';
import '../../../core/widgets/subpage.dart';
import '../../../core/widgets/wheel_picker.dart';
import '../../sleep/data/sleep_repository.dart';
import '../../sleep/domain/sleep_entry.dart';
import '../../sleep/domain/sleep_quality.dart';
import '../../sleep/domain/sleep_score.dart';
import '../../sleep/domain/sleep_window.dart';
import '../../sleep/presentation/widgets/moon_arc.dart';
import '../../sleep/presentation/widgets/stage_style.dart';

/// Log — record last night by hand, or correct a night that is already saved.
///
/// Duration is never typed: it is derived from the two times, and the form
/// validates that the window is physically plausible before saving.
///
/// The same form serves both jobs. With [editing] set it comes up pre-filled and
/// saves back onto that record's id; pushed over the shell by [LogEditPage] it
/// brings its own chrome, while the tab-hosted new-record form does not because
/// the shell already pads it.
class LogPage extends ConsumerStatefulWidget {
  const LogPage({super.key, this.editing});

  /// The night being corrected, or `null` when logging a new one.
  final SleepEntry? editing;

  @override
  ConsumerState<LogPage> createState() => _LogPageState();
}

class _LogPageState extends ConsumerState<LogPage> {
  late String _date;
  String _bedtime = '23:00';
  String _wakeTime = '07:00';
  SleepQuality _quality = SleepQuality.good;
  LoggedEvents _events = LoggedEvents.none;
  final _notesController = TextEditingController();
  bool _saved = false;
  bool _saving = false;

  /// True for the whole life of the widget: an edit never turns into a new
  /// record, and a new record never turns into an edit.
  bool get _isEditing => widget.editing != null;

  @override
  void initState() {
    super.initState();
    final editing = widget.editing;
    if (editing == null) {
      _date = formatIsoDate(DateTime.now());
      return;
    }
    // The form's date field is the *wake* date — the day the night is archived
    // under — so it is seeded from the wake side, not the bedtime.
    _date = formatIsoDate(editing.wakeLocal);
    _bedtime = formatClock(editing.bedtimeLocal);
    _wakeTime = formatClock(editing.wakeLocal);
    _quality = editing.quality;
    _events = editing.loggedEvents;
    _notesController.text = editing.notes;
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  SleepWindow get _window => buildSleepWindow(
        wakeDate: parseIsoDate(_date, DateTime.now()),
        bedtime: _bedtime,
        wakeTime: _wakeTime,
      );

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
    final window = _window;
    if (!window.isPlausible) {
      ref.read(toastProvider.notifier).show('睡眠时长需要在 0 到 24 小时之间。');
      return;
    }

    setState(() => _saving = true);
    final editing = widget.editing;
    try {
      // `stages` is left unset: this form has no stage fields, so re-saving a
      // night must not throw away a hypnogram that a real measurement put
      // there. Only an importer or a recorder may replace stages.
      await ref.read(sleepRepositoryProvider).save(
            id: editing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
            startAtUtc: window.startAtUtc,
            endAtUtc: window.endAtUtc,
            // The window is rebuilt from the wall clock the user just confirmed,
            // so it is anchored to the zone the device is in now rather than to
            // whichever zone the record was first written in.
            timeZoneId: window.timeZoneId,
            quality: _quality,
            notes: _notesController.text.trim(),
            events: _events,
            source: editing?.source ?? 'manual',
          );
      // Deliberately not awaited, matching every other haptic call in the app.
      // The night is already committed by this point, and tactile feedback is
      // decoration: a haptic engine that is slow, absent, or never answers must
      // not leave the button stuck on「保存中…」.
      unawaited(AppHaptics.success());
      if (!mounted) return;
      setState(() {
        _saved = true;
        _saving = false;
      });

      if (editing != null) {
        // The edit form is a pushed route, so going back is the whole of the
        // "done" action and the shell underneath is still on the tab that
        // opened it. The fallback covers being opened without anything to pop.
        ref.read(toastProvider.notifier).show('记录已更新。');
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        } else {
          ref.read(activeTabProvider.notifier).state = AppTab.home;
        }
        return;
      }

      ref.read(toastProvider.notifier).show('睡眠记录已保存，明天回来看看你的趋势。');
      ref.read(activeTabProvider.notifier).state = AppTab.home;
      // Reset for the next entry.
      Future<void>.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _saved = false);
      });
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
    final hours = window.durationHours;

    final items = <Widget>[
      if (!_isEditing) ...[
        const PageHeading(eyebrow: '记录睡眠', title: '今天睡得怎么样？'),
        const SizedBox(height: 18),
      ],

      // ── Live duration preview ──────────────────────────────────────────
      GlassSurface(
        borderRadius: BorderRadius.circular(AppRadii.card),
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            MoonArc(durationHours: hours, size: 112),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '睡眠时长',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.96,
                      color: tokens.textMuted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '${hours.floor()}',
                        style: AppTheme.num(
                          context,
                          size: 38,
                          weight: FontWeight.w700,
                          letterSpacing: -1.14,
                        ),
                      ),
                      Text('h ',
                          style: TextStyle(fontSize: 20, color: tokens.accent)),
                      Text(
                        '${((hours - hours.floor()) * 60).round()}',
                        style: AppTheme.num(
                          context,
                          size: 38,
                          weight: FontWeight.w700,
                          letterSpacing: -1.14,
                        ),
                      ),
                      Text('m',
                          style: TextStyle(fontSize: 20, color: tokens.accent)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    hours >= 7
                        ? '✓ 睡眠充足'
                        : hours >= 6
                            ? '略显不足'
                            : '⚠ 睡眠不足',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: durationBandColor(tokens, hours),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),

      // ── Time fields ────────────────────────────────────────────────────
      const SectionHeader('时间'),
      IosListGroup(
        children: [
          _FieldRow(label: '日期', value: _date, onTap: _pickDate),
          _FieldRow(
              label: '入睡时间',
              value: _bedtime,
              onTap: () => _pickTime(bedtime: true)),
          _FieldRow(
              label: '起床时间',
              value: _wakeTime,
              onTap: () => _pickTime(bedtime: false)),
        ],
      ),
      const SizedBox(height: 18),

      // ── Quality ────────────────────────────────────────────────────────
      const SectionHeader('睡眠质量'),
      GlassSurface(
        borderRadius: BorderRadius.circular(AppRadii.panel),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            for (final quality in SleepQuality.values) ...[
              _QualityStar(
                quality: quality,
                selected: _quality == quality,
                filledTo: _quality.value,
                onTap: () {
                  AppHaptics.select();
                  setState(() => _quality = quality);
                },
              ),
              const SizedBox(width: 10),
            ],
            const SizedBox(width: 2),
            Flexible(
              child: Text(
                _quality.label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _qualityColor(tokens, _quality),
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),

      // ── Events ─────────────────────────────────────────────────────────
      const SectionHeader('睡眠事件'),
      Row(
        children: [
          Expanded(
            child: _EventTile(
              label: '打鼾',
              icon: AppIcons.snore(size: 18, strokeWidth: 1.5),
              color: tokens.accentBlue,
              selected: _events.snore,
              onTap: () => setState(
                () => _events = _events.copyWith(snore: !_events.snore),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _EventTile(
              label: '说梦话',
              icon: AppIcons.bubble(size: 18, strokeWidth: 1.5),
              color: tokens.accentViolet,
              selected: _events.talk,
              onTap: () => setState(
                () => _events = _events.copyWith(talk: !_events.talk),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: _EventTile(
              label: '辗转难眠',
              icon: AppIcons.sparkle(size: 18, strokeWidth: 1.5),
              color: tokens.caution,
              selected: _events.restless,
              onTap: () => setState(
                () => _events = _events.copyWith(restless: !_events.restless),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _EventTile(
              label: '噩梦',
              icon: AppIcons.moon(size: 18, strokeWidth: 1.5),
              color: tokens.danger,
              selected: _events.nightmare,
              onTap: () => setState(
                () => _events = _events.copyWith(nightmare: !_events.nightmare),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 18),

      // ── Notes ──────────────────────────────────────────────────────────
      const SectionHeader('备注'),
      GlassSurface(
        borderRadius: BorderRadius.circular(AppRadii.panel),
        child: TextField(
          controller: _notesController,
          maxLines: 3,
          style: TextStyle(fontSize: 14, color: tokens.textPrimary),
          decoration: InputDecoration(
            hintText: '梦境、感受、特殊情况……',
            hintStyle: TextStyle(fontSize: 14, color: tokens.textMuted),
            border: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ),
      const SizedBox(height: 18),

      Pressable(
        onTap: _saving ? null : _save,
        child: AnimatedContainer(
          duration: AppDurations.standard,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: _saved ? tokens.accentSoft : tokens.accent,
            borderRadius: BorderRadius.circular(AppRadii.panel),
          ),
          alignment: Alignment.center,
          child: _saved
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AppIcons.check(
                        size: 18, color: tokens.accent, strokeWidth: 2.5),
                    const SizedBox(width: 8),
                    Text(
                      '已保存',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: tokens.accent,
                      ),
                    ),
                  ],
                )
              : Text(
                  _saving
                      ? '保存中…'
                      : _isEditing
                          ? '保存修改'
                          : '保存记录',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
        ),
      ),
    ];

    // The edit form is pushed over the tab shell, so it renders its own chrome
    // and padding. The new-record form is a tab, and the shell already pads it.
    if (_isEditing) {
      return Subpage(title: '编辑记录', children: items);
    }
    return ListView(
      padding: EdgeInsets.fromLTRB(
        pageGutter(context),
        0,
        pageGutter(context),
        pageBottomInset(context),
      ),
      children: items,
    );
  }
}

Color _qualityColor(AppTokens tokens, SleepQuality quality) =>
    switch (quality) {
      SleepQuality.veryPoor => tokens.danger,
      SleepQuality.poor => tokens.warn,
      SleepQuality.fair => tokens.caution,
      SleepQuality.good => tokens.accent,
      SleepQuality.excellent => tokens.accentViolet,
    };

class _FieldRow extends StatelessWidget {
  const _FieldRow(
      {required this.label, required this.value, required this.onTap});

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
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: tokens.textPrimary,
              ),
            ),
          ),
          Text(
            value,
            style: AppTheme.num(
              context,
              size: 15,
              weight: FontWeight.w600,
              color: tokens.accent,
            ),
          ),
          const SizedBox(width: 6),
          AppIcons.chevronRight(
              size: 16, color: tokens.borderStrong, strokeWidth: 2),
        ],
      ),
    );
  }
}

class _QualityStar extends StatelessWidget {
  const _QualityStar({
    required this.quality,
    required this.selected,
    required this.filledTo,
    required this.onTap,
  });

  final SleepQuality quality;
  final bool selected;
  final int filledTo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final color = _qualityColor(tokens, quality);
    final filled = filledTo >= quality.value;

    return Semantics(
      // The rating row is five unlabelled glyphs; without this a screen reader
      // announces nothing and the control is unusable.
      button: true,
      selected: selected,
      label: '睡眠质量 ${quality.label}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedScale(
          scale: selected ? 1.1 : 1,
          duration: AppDurations.springy,
          curve: AppMotion.springyCurve,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: selected ? color.withValues(alpha: 0.16) : tokens.bgMuted,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                width: 1.5,
                color: selected ? color : Colors.transparent,
              ),
            ),
            alignment: Alignment.center,
            child: AppIcons.star(
              size: 18,
              color: filled ? color : tokens.borderStrong,
              strokeWidth: filled ? 2 : 1.5,
            ),
          ),
        ),
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Widget icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    // The icon arrives uncoloured; recolour it by rebuilding through the same
    // builder so the active state can tint it.
    return GlassSurface(
      borderRadius: BorderRadius.circular(AppRadii.panel),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      tint: selected
          ? Color.alphaBlend(color.withValues(alpha: 0.11), tokens.bgCard)
          : null,
      borderColor: selected ? color.withValues(alpha: 0.38) : null,
      onTap: () {
        AppHaptics.select();
        onTap();
      },
      child: Row(
        children: [
          IconTheme.merge(
            data: IconThemeData(color: selected ? color : tokens.textMuted),
            child: icon,
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: selected ? color : tokens.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
