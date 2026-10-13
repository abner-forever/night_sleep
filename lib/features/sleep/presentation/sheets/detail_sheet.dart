import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app.dart';
import '../../../../app/app_toast.dart';
import '../../../../core/config/app_config.dart';
// `show` 只取这一个类型：整份 `app_database.dart` 里有一个 drift 生成的
// `Insight` 行类，与本文件用的领域模型 `Insight` 同名。
import '../../../../core/database/app_database.dart'
    show AppSetting, databaseProvider;
import '../../../../core/platform/haptics.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/app_basics.dart';
import '../../../../core/widgets/app_icons.dart';
import '../../../../core/widgets/app_sheet.dart';
import '../../../../core/widgets/confirm_dialog.dart';
import '../../../settings/data/insight_credentials.dart';
import '../../../settings/data/insight_service.dart';
import '../../../settings/data/model_catalog.dart';
import '../../data/clip_pruning.dart';
import '../../data/clip_store.dart';
import '../../data/sleep_repository.dart';
import '../../domain/insight_prompt.dart';
import '../../domain/sleep_entry.dart';
import '../../domain/sleep_insight.dart';
import '../../domain/sleep_stage.dart';
import '../widgets/score_ring.dart';
import '../widgets/stage_chart.dart';
import '../widgets/stage_style.dart';
import 'sound_card.dart';

/// Opens the detail sheet for [entry].
Future<void> showSleepDetailSheet(BuildContext context, SleepEntry entry) {
  return showAppSheet<void>(
    context: context,
    builder: (context) => DetailSheet(entry: entry),
  );
}

/// Everything measured about one night.
///
/// Blocks appear only when they have real content: a night with no hypnogram
/// shows no stage section, and a night with no sound clips says so plainly
/// rather than showing an empty player — and it says **only** that, without
/// claiming a detection concluded the night was quiet.
class DetailSheet extends ConsumerStatefulWidget {
  const DetailSheet({super.key, required this.entry});

  final SleepEntry entry;

  @override
  ConsumerState<DetailSheet> createState() => _DetailSheetState();
}

class _DetailSheetState extends ConsumerState<DetailSheet> {
  String? _expandedClipId;

  /// The sheet's own copy of the entry. Regenerating an insight writes to the
  /// database *and* here: the sheet was handed a value, not a stream, so
  /// without this the new summary would only appear after closing and
  /// reopening.
  late SleepEntry _entry = widget.entry;

  bool _generating = false;

  /// 生成失败的原因，显示在区块内。失败**不写库、不覆盖**已有洞察——
  /// 一次网络抖动不该把用户手里的结论抹掉（偏差 #47）。
  String? _generateError;

  /// What a generation would use right now, or null when something is missing.
  ///
  /// Built from values passed in rather than read here: `build` must `watch` (so
  /// the button appears the moment the key is filled in) while the tap handler
  /// must `read` (`ref.watch` outside the build phase is not a subscription and
  /// is not allowed).
  ///
  /// The provider and model come from [resolveInsightSelection], which applies
  /// the same defaults the settings page shows. Reading the raw columns here
  /// instead is what made this sheet tell a user with a working key that they
  /// had not configured anything.
  _Generation? _generation(String apiKey, AppSetting? settings) {
    final selection = resolveInsightSelection(
      providerId: settings?.insightProvider,
      model: settings?.insightModel,
    );
    if (!selection.isRunnable || apiKey.trim().isEmpty) return null;
    return _Generation(provider: selection.provider, model: selection.model!);
  }

  /// Why there is no button, phrased so the user knows which single thing to
  /// fix. 「去配置」 with no noun is what made a working setup look broken.
  String _blockedReason(AppSetting? settings) {
    final selection = resolveInsightSelection(
      providerId: settings?.insightProvider,
      model: settings?.insightModel,
    );
    if (!selection.provider.supportsChat) {
      return '${selection.provider.label} 暂不支持生成洞察，可在设置 · 睡眠洞察里换一个服务商。';
    }
    if (selection.model == null) {
      return '还没有可用模型，请先在设置 · 睡眠洞察里点一次「获取可用模型」。';
    }
    return '「重新生成」需要 API Key：去设置 · 睡眠洞察填好并点一次「连通性测试」，'
        '回来就能用了。';
  }

  Future<void> _regenerate() async {
    final generation = _generation(
      ref.read(insightApiKeyProvider),
      ref.read(settingsProvider).valueOrNull,
    );
    if (generation == null) return;
    final provider = generation.provider;
    final model = generation.model;

    setState(() {
      _generating = true;
      _generateError = null;
    });

    try {
      final prompt = buildRecordSummaryPrompt(_entry);
      final generated = await generateSummary(
        provider: provider,
        model: model,
        apiKey: ref.read(insightApiKeyProvider),
        systemPrompt: prompt.system,
        userPrompt: prompt.user,
        client: ref.read(insightHttpClientProvider),
      );
      final now = DateTime.now().toUtc();
      await ref.read(sleepRepositoryProvider).saveInsight(
            recordId: _entry.id,
            content: generated.summary,
            provider: provider.label,
            model: model,
            score: generated.score,
            generatedAtUtc: now,
          );
      if (!mounted) return;
      setState(() {
        _generating = false;
        _entry = _entry.copyWith(
          insight: Insight(
            id: '${_entry.id}-insight',
            recordId: _entry.id,
            content: generated.summary,
            provider: provider.label,
            model: model,
            score: generated.score,
            generatedAtUtc: now,
            status: InsightStatus.ok,
          ),
        );
      });
      // 首页与统计读的是 `sleepEntriesProvider`，而它只监听记录表；
      // 洞察行写进去不会自动推新值，必须显式失效。
      ref.invalidate(sleepEntriesProvider);
    } on InsightFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _generating = false;
        _generateError = failure.message;
      });
    }
  }

  /// Demo rows are samples, not the user's own data, and they are the only rows
  /// that carry a measured hypnogram. Editing one would leave a record that is
  /// no longer demo (so 「清除演示数据」 stops matching it) while its stages still
  /// describe the old window — a night that lies about what was measured.
  bool get _isEditable => widget.entry.source != AppConfig.demoSource;

  void _edit() {
    // Captured before the sheet closes, so the push does not depend on a
    // context that is on its way out.
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.push('/log/edit', extra: widget.entry);
  }

  Future<void> _delete() async {
    final confirmed = await showConfirmDialog(
      context,
      title: '删除 ${widget.entry.dateLabel} 的记录？',
      message: '这一晚的睡眠记录、睡眠阶段与声音事件都会被永久删除，此操作无法撤销。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (confirmed != true) return;

    // **走这一条，不是 `SleepRepository.delete()`。** 光删行会让这一晚的录音文件留在
    // 磁盘上，而确认框刚刚才向用户承诺「声音事件都会被永久删除」。
    await deleteRecordWithRecordings(
      database: ref.read(databaseProvider),
      files: ref.read(clipFileStoreProvider),
      recordId: widget.entry.id,
    );
    if (!mounted) return;
    Navigator.of(context).pop();
    ref.read(toastProvider.notifier).show('记录已删除。');
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final entry = _entry;
    final score = entry.score;
    // The tag has to describe the text printed next to it, so both come from
    // the same place: model output when the model produced usable content,
    // otherwise the local rule-based summary. A model insight that came back
    // without a score still shows here — only the score falls back to the
    // local rules (see `SleepEntry.scoreSource`), never the text.
    final modelText = entry.insightText;
    final insightText = modelText ?? entry.estimatedSummary;
    final isModelInsight = modelText != null;
    final appSettings = ref.watch(settingsProvider).valueOrNull;
    final generation = _generation(
      ref.watch(insightApiKeyProvider),
      appSettings,
    );

    return AppSheet(
      scrollable: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Title + score ──────────────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.dateLabel,
                        style: AppTheme.num(
                          context,
                          size: 12,
                          color: tokens.textMuted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '睡眠详情',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.9,
                          color: tokens.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (score != null) ...[
                  const SizedBox(width: 12),
                  ScoreRing(score: score),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '睡眠评分',
                        style: TextStyle(fontSize: 12, color: tokens.textMuted),
                      ),
                      Text(
                        score >= 85
                            ? '优秀'
                            : score >= 70
                                ? '良好'
                                : '一般',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color:
                              score >= 85 ? tokens.accentViolet : tokens.accent,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),

            // ── Bedtime / duration / wake ──────────────────────────────────
            Row(
              children: [
                _StatTile(
                  label: '入睡',
                  value: entry.bedtimeLabel,
                  color: tokens.accent,
                ),
                const SizedBox(width: 8),
                _StatTile(
                  label: '时长',
                  value: _durationLabel(entry),
                  color: tokens.textPrimary,
                ),
                const SizedBox(width: 8),
                _StatTile(
                  label: '起床',
                  value: entry.wakeLabel,
                  color: tokens.accentViolet,
                ),
              ],
            ),

            // ── Hypnogram ──────────────────────────────────────────────────
            if (entry.hasStages) ...[
              const SizedBox(height: 16),
              InsetPanel(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '睡眠阶段',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.14,
                        color: tokens.textMuted,
                      ),
                    ),
                    const SizedBox(height: 12),
                    StageBarChart(
                      stages: entry.stages,
                      height: 56,
                      legend: true,
                      caption:
                          '${entry.bedtimeLabel} 入睡 → ${entry.wakeLabel} 起床 · 柱高代表睡眠阶段',
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        for (final stage in SleepStageType.charted) ...[
                          Expanded(
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: tokens.bgCard,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    stage.label,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: tokens.textMuted,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${entry.stagePercent(stage)}%',
                                    style: AppTheme.num(
                                      context,
                                      size: 18,
                                      weight: FontWeight.w700,
                                      color: stageColor(tokens, stage),
                                    ),
                                  ),
                                  Text(
                                    '${entry.minutesFor(stage)}m',
                                    style: AppTheme.num(
                                      context,
                                      size: 12,
                                      color: tokens.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],

            // ── Sound events ───────────────────────────────────────────────
            const SizedBox(height: 16),
            Text(
              entry.hasSoundEvents
                  ? '声音记录 · ${entry.soundClips.length}条'
                  : '声音记录 · 无片段',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.14,
                color: tokens.textMuted,
              ),
            ),
            const SizedBox(height: 12),
            if (!entry.hasSoundEvents)
              InsetPanel(
                child: Row(
                  children: [
                    AppIcons.moon(
                        size: 22, color: tokens.textMuted, strokeWidth: 1.5),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // **不下没有依据的结论。** 原先这里写「全程安静，无异常
                          // 声音」，把「跑过检测、结论是没有」与「这一晚根本没录」
                          // 说成了同一件事——使用方就曾被它误导（他在 iPad 上以为
                          // 录音开着，界面却像检测完了一样下了「安静」的结论）。
                          // 零片段在两种情形下都是真的，所以只说零片段。
                          Text(
                            '这一晚没有声音片段',
                            style: TextStyle(
                                fontSize: 14, color: tokens.textMuted),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '可能是整夜安静，也可能是没有录音。',
                            style: TextStyle(
                                fontSize: 12, color: tokens.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            else
              for (final clip in entry.soundClips) ...[
                SoundCard(
                  clip: clip,
                  expanded: _expandedClipId == clip.id,
                  onToggle: () => setState(
                    () => _expandedClipId =
                        _expandedClipId == clip.id ? null : clip.id,
                  ),
                ),
                const SizedBox(height: 8),
              ],

            // ── Insight ────────────────────────────────────────────────────
            //
            // 常显，不再是「有内容才出现」：这一块现在挂着「重新生成」入口，
            // 而最需要它的场景恰恰是「这一晚还什么都没有」的记录。
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: tokens.accentSoft,
                borderRadius: BorderRadius.circular(AppRadii.panel),
                border:
                    Border.all(color: tokens.accent.withValues(alpha: 0.19)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      AppIcons.ai(
                          size: 15, color: tokens.accent, strokeWidth: 1.8),
                      const SizedBox(width: 8),
                      Text(
                        '睡眠洞察',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: tokens.accent,
                        ),
                      ),
                      if (isModelInsight || entry.isEstimated) ...[
                        const SizedBox(width: 8),
                        Tag(
                          label: isModelInsight ? '模型生成' : '本地估算',
                          background: tokens.bgMuted,
                          foreground: tokens.textMuted,
                          fontSize: 12,
                        ),
                      ],
                    ],
                  ),
                  if (isModelInsight && entry.providerLabel.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${entry.providerLabel} · ${entry.insight?.model ?? ''}',
                      style: TextStyle(fontSize: 11, color: tokens.textMuted),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    insightText ?? '这一晚还没有洞察。',
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: insightText == null
                          ? tokens.textMuted
                          : tokens.textSecondary,
                    ),
                  ),
                  if (isModelInsight) ...[
                    const SizedBox(height: 10),
                    Text(
                      '由 ${entry.providerLabel} 生成，属模型推断，不构成医疗建议。',
                      style: TextStyle(fontSize: 12, color: tokens.textMuted),
                    ),
                  ] else if (entry.isEstimated) ...[
                    const SizedBox(height: 10),
                    Text(
                      '该评分为本地规则估算，不构成医疗建议。',
                      style: TextStyle(fontSize: 12, color: tokens.textMuted),
                    ),
                  ],
                  const SizedBox(height: 12),
                  // **按钮常驻**。此前是「跑不了就整个不渲染」，结果用户填好了
                  // key 也只看到一行字，无从判断是自己没配对还是功能没做
                  // —— 这条被连着报回来两次。改成一个变灰的按钮 + 下方一句
                  // 指名道姓的说明，与 `PrimaryAction` 的禁用态同一套做法：
                  // 不假装可用，但把入口和原因都摆在明面上。
                  _InsightAction(
                    label: _generating ? '生成中…' : '重新生成',
                    busy: _generating,
                    enabled: generation != null,
                    // 生成中禁用，避免连点发出多次计费请求。
                    onTap:
                        _generating || generation == null ? null : _regenerate,
                  ),
                  if (generation == null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _blockedReason(appSettings),
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: tokens.textMuted,
                      ),
                    ),
                  ],
                  if (_generateError != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _generateError!,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: tokens.danger,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // ── Notes ──────────────────────────────────────────────────────
            if (entry.notes.trim().isNotEmpty) ...[
              const SizedBox(height: 16),
              InsetPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '备注',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: tokens.textMuted,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      entry.notes,
                      style: TextStyle(
                        fontSize: 14,
                        fontStyle: FontStyle.italic,
                        height: 1.5,
                        color: tokens.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // ── Actions ────────────────────────────────────────────────────
            const SizedBox(height: 24),
            if (_isEditable)
              Row(
                children: [
                  Expanded(
                    child: _SheetAction(
                      label: '编辑记录',
                      icon: AppIcons.pen(
                          size: 16, color: tokens.accent, strokeWidth: 2),
                      foreground: tokens.accent,
                      background: tokens.accentSoft,
                      onTap: _edit,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SheetAction(
                      label: '删除记录',
                      icon: AppIcons.trash(
                          size: 16, color: tokens.danger, strokeWidth: 2),
                      foreground: tokens.danger,
                      background: tokens.danger.withValues(alpha: 0.12),
                      onTap: _delete,
                    ),
                  ),
                ],
              )
            else
              InsetPanel(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppIcons.sparkle(
                        size: 16, color: tokens.textMuted, strokeWidth: 1.8),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '这是演示数据，不能编辑或删除。可在「设置 › 演示数据」中一次性清除。',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: tokens.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _durationLabel(SleepEntry entry) {
    final hours = entry.durationHours.floor();
    final minutes = ((entry.durationHours - hours) * 60).round();
    return '${hours}h ${minutes}m';
  }
}

/// A full-width action button in the detail sheet's footer.
class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.label,
    required this.foreground,
    required this.background,
    required this.onTap,
    this.icon,
  });

  final String label;
  final Color foreground;
  final Color background;
  final VoidCallback onTap;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: () {
        AppHaptics.tap();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppRadii.panel),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              IconTheme.merge(
                data: IconThemeData(color: foreground),
                child: icon!,
              ),
              const SizedBox(width: 7),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: tokens.bgMuted,
          borderRadius: BorderRadius.circular(AppRadii.panel),
        ),
        child: Column(
          children: [
            Text(label,
                style: TextStyle(fontSize: 12, color: tokens.textMuted)),
            const SizedBox(height: 4),
            Text(
              value,
              style: AppTheme.num(context,
                  size: 17, weight: FontWeight.w700, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// 「重新生成」按钮。
///
/// 与洞察配置页那三个动作同一套观感（胶囊 + 转圈），但底色用卡片自身的
/// 强调色系而不是 `accentSoft`：它嵌在已经铺了 `accentSoft` 的洞察卡里，
/// 同色会糊成一片。
class _InsightAction extends StatelessWidget {
  const _InsightAction({
    required this.label,
    this.onTap,
    this.busy = false,
    this.enabled = true,
  });

  final String label;
  final VoidCallback? onTap;
  final bool busy;

  /// False draws the muted "can't run yet" state. The caller pairs it with a
  /// line saying exactly what is missing — never leave a disabled control
  /// unexplained.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Pressable(
        onTap: onTap,
        haptic: false,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: enabled ? tokens.bgCard : tokens.bgMuted,
            borderRadius: BorderRadius.circular(AppRadii.pill),
            border: Border.all(
              color: enabled
                  ? tokens.accent.withValues(alpha: 0.35)
                  : tokens.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy) ...[
                const SizedBox(
                  width: 11,
                  height: 11,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: enabled ? tokens.accent : tokens.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The provider and model a 「重新生成」 would use.
///
/// Only ever constructed when the call can actually run — a key is present,
/// the provider speaks the OpenAI-compatible protocol, and a model resolves.
/// Absence of this object *is* the "no button" state.
class _Generation {
  const _Generation({required this.provider, required this.model});

  final InsightProvider provider;
  final String model;
}
