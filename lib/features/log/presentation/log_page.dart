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
import '../../sleep/presentation/widgets/event_tiles.dart';
import '../../sleep/presentation/widgets/moon_arc.dart';
import '../../sleep/presentation/widgets/quality_rating.dart';
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

  /// 未评分为 `null`，且**表单初始就是无选中**。
  ///
  /// 原来是 `SleepQuality.good`，那等于应用替用户说了一句他没说过的话，
  /// 并让评分凭空带上 17.5 分的质量分。现在不选就不写。
  SleepQuality? _quality;
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
            QualityStars(
              value: _quality,
              onChanged: (quality) => setState(() => _quality = quality),
            ),
            // 星级行与标签之间留 12px：原来是星级行尾部 10px 间隔加 2px，
            // 提成共享组件后尾部间隔归组件自己管，这里补回同一个观感。
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                _quality?.label ?? '未评分',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: qualityColor(tokens, _quality),
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),

      // ── Events ─────────────────────────────────────────────────────────
      const SectionHeader('睡眠事件'),
      EventTileGrid(
        events: _events,
        onChanged: (events) => setState(() => _events = events),
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

    // 编辑表单是压在标签外壳之上的推入页，自带一套外框与留白；
    // 新建表单是个 tab，顶部与底部留白由下面的 ListView 自己补（见 pageTopInset）。
    if (_isEditing) {
      return Subpage(title: '编辑记录', children: items);
    }
    return ListView(
      padding: EdgeInsets.fromLTRB(
        pageGutter(context),
        pageTopInset(context),
        pageGutter(context),
        pageBottomInset(context),
      ),
      children: items,
    );
  }
}

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
