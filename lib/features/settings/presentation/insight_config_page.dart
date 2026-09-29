import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app.dart';
import '../../../core/database/app_database.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_basics.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/glass_surface.dart';
import '../../../core/widgets/ios_controls.dart';
import '../../../core/widgets/subpage.dart';
import '../data/model_catalog.dart';

/// Insight service configuration.
///
/// The provider and model selection is persisted. The API key is **not** written
/// anywhere yet: the spec requires platform secure storage for it, and keeping
/// it out of SQLite is what stops it reaching exports and backups. Until secure
/// storage lands, the field is a session-only scratchpad and says so.
///
/// The model list belongs to the provider, not to us. A curated list is shown
/// until something is fetched, marked with the date it was checked;
/// 「获取可用模型」 replaces it with what the provider actually serves right now.
/// See [kInsightProviders] for why one provider's curated list is empty.
class InsightConfigPage extends ConsumerStatefulWidget {
  const InsightConfigPage({super.key});

  @override
  ConsumerState<InsightConfigPage> createState() => _InsightConfigPageState();
}

class _InsightConfigPageState extends ConsumerState<InsightConfigPage> {
  final _keyController = TextEditingController();
  bool _showKey = false;

  /// Set once a fetch succeeds, cleared whenever the provider changes so one
  /// provider's list is never offered for another.
  List<String>? _fetchedModels;
  bool _fetching = false;

  /// 最近一次获取失败的原因，显示在页内。全局 toast 挂在 AppScaffold，二级页
  /// push 在它之上，会把提示条整个盖住——失败反馈必须留在本页，否则界面只会
  /// 表现为「点了没反应」（转圈停下之外毫无变化）。
  String? _error;

  /// 最近一次获取成功的文案，同样显示在页内（原因见 [_error]）。
  ///
  /// 与 [_error] 互斥：每次取模型、切换服务商都先把两者清空，且只设置其中一个，
  /// 因此页面上最多只出现一条提示。
  String? _success;

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  InsightProviderId get _providerId {
    final stored = ref.read(settingsProvider).valueOrNull?.insightProvider;
    return InsightProviderId.fromId(stored) ?? InsightProviderId.deepseek;
  }

  List<String> get _modelOptions {
    final fetched = _fetchedModels;
    if (fetched != null) return fetched;
    return [for (final model in providerFor(_providerId).curated) model.id];
  }

  Future<void> _update(AppSettingsCompanion values) {
    return ref.read(databaseProvider).updateSettings(values);
  }

  Future<void> _fetchModels() async {
    final id = _providerId;
    setState(() {
      _fetching = true;
      _error = null;
      _success = null;
    });
    try {
      final models = await fetchProviderModels(
        provider: providerFor(id),
        apiKey: _keyController.text,
      );
      if (!mounted) return;
      setState(() {
        _fetchedModels = models;
        _fetching = false;
        _success = '已获取 ${models.length} 个可用模型。';
      });
      // Keep the current choice only while the provider still serves it.
      final stored = ref.read(settingsProvider).valueOrNull?.insightModel;
      if (stored == null || !models.contains(stored)) {
        await _update(AppSettingsCompanion(insightModel: Value(models.first)));
      }
    } on ModelFetchFailure catch (failure) {
      // 失败必须看得见。此前异常只往被盖住的全局 toast 里写，首页以外看不到。
      if (!mounted) return;
      setState(() {
        _fetching = false;
        _error = failure.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final provider = providerFor(_providerId);
    final options = _modelOptions;
    final storedModel = ref.watch(settingsProvider).valueOrNull?.insightModel;
    final model = storedModel != null && options.contains(storedModel)
        ? storedModel
        : (options.isEmpty ? null : options.first);
    final curated = _fetchedModels == null;

    return Subpage(
      backLabel: '设置',
      title: '洞察服务配置',
      children: [
        GlassSurface(
          borderRadius: BorderRadius.circular(AppRadii.card),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListIconBadge(
                    background: tokens.accentSoft,
                    size: 40,
                    child: AppIcons.ai(
                        size: 20, color: tokens.accent, strokeWidth: 1.8),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '大模型服务',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: tokens.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '用于睡眠报告与声音分析',
                          style:
                              TextStyle(fontSize: 12, color: tokens.textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _MenuField(
                      label: '服务商',
                      value: provider.label,
                      options: [
                        for (final item in kInsightProviders) item.label,
                      ],
                      selected: provider.label,
                      onPick: (index) {
                        final picked = kInsightProviders[index];
                        setState(() {
                          _fetchedModels = null;
                          _error = null;
                          _success = null;
                        });
                        _update(
                          AppSettingsCompanion(
                            insightProvider: Value(picked.id.id),
                            // Cleared, not carried over: a model name from the
                            // previous provider means nothing here.
                            insightModel: const Value(null),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MenuField(
                      label: '模型',
                      value: model ?? '先获取可用模型',
                      options: options,
                      selected: model,
                      enabled: options.isNotEmpty,
                      onPick: (index) => _update(
                        AppSettingsCompanion(
                          insightModel: Value(options[index]),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      curated
                          ? (provider.curated.isEmpty
                              ? '未内置模型名：${provider.curationSource}'
                              : '内置列表核实于 ${provider.curated.first.checkedOn}，'
                                  '可能已过期；点右侧可拉取实时列表。')
                          : '列表来自 ${provider.label} 的实时返回。',
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.45,
                        color: tokens.textMuted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Pressable(
                    onTap: _fetching ? null : _fetchModels,
                    haptic: false,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: tokens.accentSoft,
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_fetching) ...[
                            const SizedBox(
                              width: 11,
                              height: 11,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            _fetching ? '获取中…' : '获取可用模型',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: tokens.accent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'API Key',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: tokens.textMuted,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: tokens.bgInput,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TextField(
                        controller: _keyController,
                        obscureText: !_showKey,
                        autocorrect: false,
                        enableSuggestions: false,
                        style: TextStyle(
                          fontSize: 14,
                          color: tokens.textPrimary,
                          fontFeatures: const [],
                        ),
                        decoration: InputDecoration(
                          hintText: '${provider.label} API Key',
                          hintStyle:
                              TextStyle(fontSize: 14, color: tokens.textMuted),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Pressable(
                    onTap: () => setState(() => _showKey = !_showKey),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 10),
                      child: Text(
                        _showKey ? '隐藏' : '显示',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: tokens.accent,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Divider(height: 1, color: tokens.border),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '密钥仅在当前会话内存中，尚未接入安全存储，重启即丢失。',
                      style: TextStyle(fontSize: 12, color: tokens.textMuted),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // No provider exposes a balance endpoint we can call, so the
                  // control is present but inert.
                  Opacity(
                    opacity: 0.55,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: tokens.bgMuted,
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                      ),
                      child: Text(
                        '余额查询未接入',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: tokens.textMuted,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: tokens.warn.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppIcons.sparkle(
                        size: 16, color: tokens.warn, strokeWidth: 1.8),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '安全提示：',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: tokens.textPrimary,
                              ),
                            ),
                            const TextSpan(
                              text:
                                  '在客户端直接保存并调用 API Key 存在泄露风险。正式上线应由自建后端代理转发请求，'
                                  '并在此前明确告知将发送哪些睡眠数据。',
                            ),
                          ],
                        ),
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: tokens.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: TextStyle(fontSize: 12, height: 1.5, color: tokens.danger),
          ),
        ],
        if (_success != null) ...[
          const SizedBox(height: 12),
          Text(
            _success!,
            style: TextStyle(fontSize: 12, height: 1.5, color: tokens.accent),
          ),
        ],
      ],
    );
  }
}

/// `ai-select-trigger` / `ai-select-menu` — a compact dropdown.
///
/// The menu is rendered by [PopupMenuButton] rather than as a positioned child.
/// The card this sits in is a [GlassSurface], whose `ClipRRect` would clip an
/// in-tree overlay, so the design's floating menu has to live in the app
/// overlay instead.
class _MenuField extends StatelessWidget {
  const _MenuField({
    required this.label,
    required this.value,
    required this.options,
    required this.selected,
    required this.onPick,
    this.enabled = true,
  });

  final String label;
  final String value;
  final List<String> options;
  final String? selected;
  final ValueChanged<int> onPick;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    final field = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: tokens.bgInput,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: enabled ? tokens.textPrimary : tokens.textMuted,
              ),
            ),
          ),
          AppIcons.chevronDown(
            size: 15,
            color: tokens.textMuted,
            strokeWidth: 2,
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: tokens.textMuted,
          ),
        ),
        const SizedBox(height: 6),
        // "Nothing to choose from yet" is a real state — a provider whose list
        // has not been fetched — and an empty popup would read as a broken
        // control rather than an un-fetched one.
        if (!enabled)
          field
        else
          PopupMenuButton<int>(
            tooltip: '',
            position: PopupMenuPosition.under,
            color: tokens.bgCardSolid,
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: tokens.border),
            ),
            onSelected: onPick,
            itemBuilder: (context) => [
              for (var i = 0; i < options.length; i++)
                PopupMenuItem<int>(
                  value: i,
                  height: 42,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          options[i],
                          style: TextStyle(
                            fontSize: 14,
                            color: options[i] == selected
                                ? tokens.accent
                                : tokens.textPrimary,
                          ),
                        ),
                      ),
                      if (options[i] == selected)
                        AppIcons.check(
                          size: 14,
                          color: tokens.accent,
                          strokeWidth: 2.5,
                        ),
                    ],
                  ),
                ),
            ],
            child: field,
          ),
      ],
    );
  }
}
