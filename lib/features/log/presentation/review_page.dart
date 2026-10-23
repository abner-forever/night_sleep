import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_shell.dart';
import '../../../app/app_toast.dart';
import '../../../core/config/app_config.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_basics.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/quiet_surface.dart';
import '../../sleep/data/sleep_repository.dart';
import '../../sleep/domain/sleep_entry.dart';
import '../../sleep/domain/sleep_math.dart';
import '../../sleep/domain/sleep_quality.dart';
import '../../sleep/domain/sleep_score.dart';
import '../../sleep/presentation/widgets/event_tiles.dart';
import '../../sleep/presentation/widgets/quality_rating.dart';
import '../../sleep/presentation/widgets/sleep_summary.dart';
import 'review_duration_hero.dart';
import 'review_night_picker.dart';

/// 回顾 Tab：给**已经存在**的一晚补上主观感受。
///
/// 默认目标是最近一条真实记录，「刚醒来那一屏」的手感不变。这里**不改起止
/// 时刻**——它补的是感受，不是记录；要改时刻走详情页的编辑记录。
///
/// 演示数据不参与：它一旦被改写就不再匹配「清除演示数据」，而且它的睡眠阶段与
/// 时间窗会互相矛盾。只有演示数据、或一条记录都没有时，页面如实说明并给出
/// 手动补录入口。
class ReviewPage extends ConsumerStatefulWidget {
  const ReviewPage({super.key});

  @override
  ConsumerState<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends ConsumerState<ReviewPage> {
  /// 当前回顾的那一晚的 id。`null` 表示还没选过，按「最近的真实记录」解析。
  ///
  /// 只存 id 不存对象：列表刷新后旧对象会过期，按 id 回到最新那一份才不会拿着
  /// 一份被别处改过的快照继续编辑。
  String? _selectedId;

  /// 解析出当前该回顾的那一晚。
  ///
  /// 选中的 id 已不在列表里（被删除、或换了筛选）时回落到最近一条真实记录。
  SleepEntry? _resolve(List<SleepEntry> real) {
    final id = _selectedId;
    if (id != null) {
      for (final entry in real) {
        if (entry.id == id) return entry;
      }
    }
    return real.isEmpty ? null : real.first;
  }

  Future<void> _pickNight(List<SleepEntry> real, SleepEntry current) async {
    final picked = await showReviewNightPicker(
      context,
      entries: real,
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
              size: 30, color: Theme.of(context).colorScheme.error),
          title: '无法读取记录',
          body: '本地数据库打开失败：$error',
        ),
      ),
      data: (records) => _content(context, records),
    );
  }

  Widget _content(BuildContext context, List<SleepEntry> records) {
    // 演示行只是样本，不算「可回顾的自己的记录」。
    final real =
        records.where((entry) => entry.source != AppConfig.demoSource).toList();
    final selected = _resolve(real);

    final children = <Widget>[
      const PageHeading(eyebrow: '回顾', title: '睡得怎么样？'),
      const SizedBox(height: 18),
    ];

    if (selected == null) {
      children.add(_NoNightState(hasDemoData: records.isNotEmpty));
    } else {
      children.add(LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        final available = constraints.maxWidth - (wide ? 28 : 0);
        return Flex(
          direction: wide ? Axis.horizontal : Axis.vertical,
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: wide ? available / 2.2 : available,
              child: _NightHeader(
                entry: selected,
                onTap: () => _pickNight(real, selected),
              ),
            ),
            SizedBox(width: wide ? 28 : 0, height: wide ? 0 : 24),
            SizedBox(
              width: wide ? available / 2.2 * 1.2 : available,
              child: _ReviewForm(key: ValueKey(selected.id), entry: selected),
            ),
          ],
        );
      }));
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

/// 记录头：日期、起止、时长与来源。点它打开换一晚的选择器。
///
/// 这一页有且只有这一张 hero（晨光，§2.2），所以它直接住进
/// [ReviewDurationHero]：手动补录页那张时长预览卡与它是同一张卡的两个内容。
class _NightHeader extends StatelessWidget {
  const _NightHeader({required this.entry, required this.onTap});

  final SleepEntry entry;
  final VoidCallback onTap;

  /// 来源文案。未知来源按「手动记录」显示，不假装它是设备导入的。
  static String sourceLabel(String source) => switch (source) {
        'session' => '睡眠会话',
        'import' => '导入',
        _ => '手动记录',
      };

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return ReviewDurationHero(
      onTap: onTap,
      semanticLabel: '换一晚回顾',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child: Text(formatDate(entry.wakeLocal),
                      style: TextStyle(
                          fontSize: 12, color: tokens.textSecondary))),
              AppIcons.moon(size: 22, color: tokens.accent),
              const SizedBox(width: 12),
              AppIcons.chevronDown(size: 16, color: tokens.textMuted),
            ],
          ),
          const SizedBox(height: 12),
          SleepDuration(hours: entry.durationHours, size: 46),
          const SizedBox(height: 15),
          SleepTimes(entry: entry, size: 12),
          const SizedBox(height: 12),
          Text('来自：${sourceLabel(entry.source)}',
              style: TextStyle(fontSize: 11, color: tokens.textMuted)),
        ],
      ),
    );
  }
}

/// 空状态：一条真实记录都没有。
///
/// 分两种情形如实说明——从没记过，还是库里只有演示数据。两者都保留手动补录入口。
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
          ? '演示记录是样本，不是你自己的睡眠：改动它会让睡眠阶段和时间窗互相矛盾，'
              '而它一旦不再是演示数据，「清除演示数据」就再也找不到它。'
              '要回顾你自己的某一晚，先手动补录一条。'
          : '补录第一晚之后，就能在这里补充当晚的感受了。',
      actionLabel: '手动补录某一晚',
      onAction: () => context.push('/log/new'),
    );
  }
}

/// 补感受的表单：质量、事件、备注。
///
/// 以选中的记录作 key 重建，所以它的状态在 `initState` 里一次性预填，不需要在
/// `build` 里同步——换一晚时整棵子树换 key，状态自然重来。
class _ReviewForm extends ConsumerStatefulWidget {
  const _ReviewForm({super.key, required this.entry});

  final SleepEntry entry;

  @override
  ConsumerState<_ReviewForm> createState() => _ReviewFormState();
}

class _ReviewFormState extends ConsumerState<_ReviewForm> {
  late SleepQuality? _quality;
  late LoggedEvents _events;
  late final TextEditingController _notesController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    // 未评分的记录，`_quality` 保持 `null`——五个药丸一个都不高亮，绝不默认某一档。
    _quality = entry.quality;
    _events = entry.loggedEvents;
    _notesController = TextEditingController(text: entry.notes);
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    final entry = widget.entry;
    try {
      await ref.read(sleepRepositoryProvider).save(
            id: entry.id,
            startAtUtc: entry.startAtUtc,
            endAtUtc: entry.endAtUtc,
            timeZoneId: entry.timeZoneId,
            quality: _quality,
            notes: _notesController.text.trim(),
            events: _events,
            source: entry.source,
            // `stages` 留空 = **保持已有阶段不变**。补充感受绝不能抹掉设备测到的
            // 睡眠阶段——这是 `save()` 那个 nullable 参数存在的全部理由。
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Quality ────────────────────────────────────────────────────────
        const SectionHeader('睡眠质量'),
        QuietSurface(
          borderRadius: BorderRadius.circular(AppRadii.panel),
          padding: const EdgeInsets.all(8),
          // 还没有评分时 `_quality` 是 `null`：五个药丸一个都不亮，行尾既不写
          // 「未评分」也不写别的占位（`QualityChoice` 自己管这一条）。
          child: QualityChoice(
            value: _quality,
            onChanged: (quality) => setState(() => _quality = quality),
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
        QuietSurface(
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

        PrimaryAction(
          label: '保存补充',
          onTap: _saving ? null : _save,
        ),
        const SizedBox(height: 10),
        const _ManualEntryLink(),
      ],
    );
  }
}

/// 底部次要入口：手动补录某一晚。
///
/// 文案「手动补录某一晚」与箭头图标分开：测试按整串文字找它，箭头只是视觉提示。
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
                  size: 14, color: tokens.accent, strokeWidth: 2),
            ],
          ),
        ),
      ),
    );
  }
}
