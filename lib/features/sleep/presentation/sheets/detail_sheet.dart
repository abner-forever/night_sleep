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
import '../../../../core/widgets/quiet_surface.dart';
import '../../../settings/data/insight_credentials.dart';
import '../../../settings/data/insight_service.dart';
import '../../../settings/data/model_catalog.dart';
import '../../data/clip_analyzer.dart';
import '../../data/clip_pruning.dart';
import '../../data/clip_store.dart';
import '../../data/sleep_repository.dart';
import '../../domain/insight_prompt.dart';
import '../../domain/sleep_entry.dart';
import '../../domain/sleep_insight.dart';
import '../widgets/sleep_summary.dart';
import '../widgets/stage_chart.dart';
import 'sound_card.dart';

/// Opens the detail sheet for [entry].
Future<void> showSleepDetailSheet(BuildContext context, SleepEntry entry) {
  return showAppSheet<void>(
    context: context,
    expanded: true,
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

  /// 播放控制器的引用，只在 `dispose` 里用来停掉正在播的那一段。
  ///
  /// **「页面关了还在响」这件事由详情页负责，不是每张卡片自己负责。** 片段列表
  /// 改成按需构建之后，卡片滚出视口也会被拆解；如果还留在卡片里，滚动就会掐断
  /// 正在播的声音。
  late final ClipPlaybackController _playback;

  @override
  void initState() {
    super.initState();
    _playback = ref.read(clipPlaybackProvider);
  }

  @override
  void dispose() {
    final playing = _playback.playingClipId;
    // `detach` 而不是 `stop`：此刻别的卡片也在拆解，`notifyListeners` 会去
    // `markNeedsBuild` 已卸载的元素。
    if (playing != null) _playback.detach(playing);
    super.dispose();
  }

  /// The sheet's own copy of the entry. Regenerating an insight writes to the
  /// database *and* here: the sheet was handed a value, not a stream, so
  /// without this the new summary would only appear after closing and
  /// reopening.
  late SleepEntry _entry = widget.entry;

  bool _generating = false;

  /// 正在重跑这一晚的声音分析。
  bool _analysingSounds = false;

  /// 重新分析这一晚的片段。
  ///
  /// **与「重新生成」（AI 洞察）是两件事**：这一个在本机跑声学特征，不联网、不花
  /// API 钱。入口的措辞与位置都要让这件事一眼看得出来，别让人以为点一下要计费。
  ///
  /// 分析写回的是 `sound_clips`，而那张表有变更流（`clipsProvider`），所以这里
  /// 重新读一次条目就能看到新的自动标注。
  Future<void> _reanalyseSounds() async {
    if (_analysingSounds) return;
    setState(() => _analysingSounds = true);
    try {
      final settled =
          await ref.read(clipAnalyzerProvider).analyseRecord(_entry.id);
      final refreshed = await ref.read(sleepRepositoryProvider).loadAll();
      SleepEntry? updated;
      for (final candidate in refreshed) {
        if (candidate.id == _entry.id) {
          updated = candidate;
          break;
        }
      }
      if (!mounted) return;
      final refreshedEntry = updated;
      if (refreshedEntry != null) {
        setState(() => _entry = refreshedEntry);
      }
      ref
          .read(toastProvider.notifier)
          .show(_analysisSummary(settled, refreshedEntry));
    } catch (error) {
      if (!mounted) return;
      ref.read(toastProvider.notifier).show('分析失败：$error');
    } finally {
      if (mounted) setState(() => _analysingSounds = false);
    }
  }

  /// 「重新分析」跑完之后要说的那一句。
  ///
  /// **零结论也必须说。** 这个动作在本机跑完，最常见的结局恰恰是「一段都没把握」
  /// ——判定规则宁弃权不猜，界面于是从标题到展开区一个字都没变，用户只会以为按钮
  /// 没生效（2026-10-16 的原话：「点击重新分析音频都还是待标注」）。所以如实报出
  /// 「看过几段、其中几段有结论」，哪怕两个数里有一个是零。
  String _analysisSummary(int settled, SleepEntry? entry) {
    if (settled == 0) return '没有可分析的片段（录音可能已被保留期限清掉）';
    final verdicts =
        entry?.soundClips.where((clip) => clip.hasAutoVerdict).length ?? 0;
    if (verdicts == 0) return '看过 $settled 段，没有一段有把握，仍留待标注';
    return '看过 $settled 段，其中 $verdicts 段给出了自动判断';
  }

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
  Widget build(BuildContext context) => Theme(
        data: AppTheme.dark(),
        child: Builder(builder: _buildContent),
      );

  Widget _buildContent(BuildContext context) {
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

    final blocks = <Widget>[
      Padding(
        padding: EdgeInsets.only(
          top: MediaQuery.sizeOf(context).width >= 768 ? 24 : 12,
          bottom: 20,
        ),
        child: Row(children: [
          Pressable(
            key: const ValueKey('sleep-detail-back'),
            onTap: () => Navigator.of(context).pop(),
            semanticLabel: '返回上一页',
            child: SizedBox(
                width: 44,
                height: 44,
                child: Center(
                    child: Transform.flip(
                        flipX: true,
                        child: AppIcons.chevronRight(
                            size: 20, color: tokens.textPrimary)))),
          ),
          Expanded(
              child: Text('睡眠详情',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: tokens.textPrimary))),
          SizedBox(
              width: 44,
              child: Center(
                  child: AppIcons.moon(size: 18, color: tokens.textSecondary))),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(7, 0, 7, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(entry.dateLabel,
              style: AppTheme.num(context,
                  size: 11,
                  weight: FontWeight.w400,
                  color: tokens.textSecondary)),
          const SizedBox(height: 13),
          Wrap(
              spacing: 23,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SleepDuration(hours: entry.durationHours, size: 46),
                if (score != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 17, vertical: 9),
                    decoration: BoxDecoration(
                        color: const Color(0x5C3478F6),
                        border: Border.all(color: const Color(0x3073A8FF)),
                        borderRadius: BorderRadius.circular(25)),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text('$score 分',
                          style: AppTheme.num(context,
                              size: 22, weight: FontWeight.w500)),
                      const SizedBox(height: 3),
                      Text(entry.isEstimated ? '本地估算' : '睡眠评分',
                          style: TextStyle(
                              fontSize: 9, color: tokens.textSecondary)),
                    ]),
                  ),
              ]),
          const SizedBox(height: 15),
          SleepTimes(entry: entry, size: 11),
        ]),
      ),
      QuietSurface(
        tint: const Color(0xDD10243C),
        borderColor: const Color(0x0DADC9ED),
        borderRadius: BorderRadius.circular(20),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionHeader('睡眠阶段', padding: EdgeInsets.zero),
          if (entry.hasStages) ...[
            const SizedBox(height: 20),
            StageBarChart(
              stages: entry.stages,
              height: 95,
              caption:
                  '${entry.bedtimeLabel} 入睡 → ${entry.wakeLabel} 起床 · 柱高代表睡眠阶段',
            ),
          ],
          SleepStageSummary(entry: entry),
        ]),
      ),
      const SizedBox(height: 15),

      // ── Sound events ───────────────────────────────────────────────
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(
            child: Text(
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
          ),
          // **与下面那个「重新生成」是两件事，措辞必须能分开。**
          // 这一个在本机跑声学特征：不联网、不花 API 钱、随时可以重跑。
          // 它只在真有片段可分析时出现——没录到东西时点它没有任何意义。
          if (entry.hasSoundEvents)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _analysingSounds ? null : _reanalyseSounds,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 2,
                ),
                child: Text(
                  _analysingSounds ? '分析中…' : '重新分析',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _analysingSounds ? tokens.textMuted : tokens.accent,
                  ),
                ),
              ),
            ),
        ],
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
                      style: TextStyle(fontSize: 14, color: tokens.textMuted),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '可能是整夜安静，也可能是没有录音。',
                      style: TextStyle(fontSize: 12, color: tokens.textMuted),
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
              () =>
                  _expandedClipId = _expandedClipId == clip.id ? null : clip.id,
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
          border: Border.all(color: tokens.accent.withValues(alpha: 0.19)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AppIcons.ai(size: 15, color: tokens.accent, strokeWidth: 1.8),
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
              onTap: _generating || generation == null ? null : _regenerate,
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
    ];

    // 面板定高，正文一律**按需构建**：第一帧只建视口里那几张卡，不再把整晚的
    // 卡片连同各自的 38 根波形条一次建完——那一步会把弹层的进场动画整个吃掉。
    return AppSheet(
      expanded: true,
      showHandle: false,
      background: const _DetailBackground(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => blocks[index],
              childCount: blocks.length,
            ),
          ),
        ),
      ],
    );
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

class _DetailBackground extends StatelessWidget {
  const _DetailBackground();

  @override
  Widget build(BuildContext context) => const ColoredBox(
        color: Color(0xFF061426),
        child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            height: 340,
            width: double.infinity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                  image: DecorationImage(
                      image: AssetImage('assets/images/night-lake.jpg'),
                      fit: BoxFit.cover,
                      alignment: Alignment(0, -.12))),
              child: DecoratedBox(
                  decoration: BoxDecoration(
                      gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                    Color(0xED0D2B60),
                    Color(0x99102950),
                    Color(0xFF061426)
                  ],
                          stops: [
                    0,
                    .48,
                    1
                  ]))),
            ),
          ),
        ),
      );
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
