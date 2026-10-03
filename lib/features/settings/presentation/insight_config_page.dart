import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app.dart';
import '../../../core/database/app_database.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_basics.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/app_menu_field.dart';
import '../../../core/widgets/glass_surface.dart';
import '../../../core/widgets/ios_controls.dart';
import '../../../core/widgets/subpage.dart';
import '../data/insight_credentials.dart';
import '../data/insight_service.dart';
import '../data/model_catalog.dart';

/// Insight service configuration.
///
/// The provider and model selection is persisted. The API key is **not** written
/// anywhere yet: the spec requires platform secure storage for it, and keeping
/// it out of SQLite is what stops it reaching exports and backups. Until secure
/// storage lands the field writes to a session-only in-memory holder
/// ([insightApiKeyProvider]) and says so — that holder is also what lets the
/// sleep-detail sheet generate a summary without asking for the key again.
///
/// Three things can be done from here, and each one is only offered where it
/// actually works: 「获取可用模型」 (`GET /models`), 「连通性测试」 (one minimal
/// completion), and 「查询余额」 (`GET /user/balance`, DeepSeek only). Providers
/// without a verified endpoint show an inert 「未接入」 pill instead of a button
/// that fails — see 偏差 #3 and #46.
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

  /// The most recent balance reading, or null before the first query. Cleared
  /// with the model list when the provider changes — one provider's money is
  /// not another's.
  ProviderBalance? _balance;
  bool _checkingBalance = false;

  bool _pinging = false;

  /// True while any of the three actions is in flight. They all use the same
  /// key and the same page-level notice, so letting two run at once would
  /// produce two writers racing for one message slot.
  bool get _busy => _fetching || _checkingBalance || _pinging;

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
  void initState() {
    super.initState();
    // 密钥活在 provider 里而不是这个页面里：离开再回来（或从详情页生成洞察）
    // 都要拿得到同一把。页面只是它的一个视图，`dispose` 不会把它抹掉。
    _keyController.text = ref.read(insightApiKeyProvider);
  }

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
    return curatedModelIds(providerFor(_providerId));
  }

  /// The model a request would actually use. [stored] is passed in rather than
  /// read here so `build` can keep watching the settings stream while the
  /// action handlers read it once.
  ///
  /// Delegates to [resolveInsightModel] so this page and the sleep-detail sheet
  /// can never disagree about which model is "the one selected" — that
  /// disagreement is what hid the 「重新生成」 button.
  String? _modelFrom(String? stored) =>
      resolveInsightModel(options: _modelOptions, stored: stored);

  String get _balanceLabel {
    final balance = _balance;
    if (balance == null) return '查询余额';
    if (!balance.isAvailable) return '账户不可用';
    return '余额 ${balance.display}';
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
        apiKey: ref.read(insightApiKeyProvider),
        client: ref.read(insightHttpClientProvider),
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
    } on InsightFailure catch (failure) {
      // 失败必须看得见。此前异常只往被盖住的全局 toast 里写，首页以外看不到。
      if (!mounted) return;
      setState(() {
        _fetching = false;
        _error = failure.message;
      });
    }
  }

  /// Reads the account balance. Only offered where the provider publishes one
  /// (DeepSeek); everyone else keeps the honest 「未接入」 pill.
  Future<void> _checkBalance() async {
    setState(() {
      _checkingBalance = true;
      _error = null;
      _success = null;
    });
    try {
      final balance = await fetchProviderBalance(
        provider: providerFor(_providerId),
        apiKey: ref.read(insightApiKeyProvider),
        client: ref.read(insightHttpClientProvider),
      );
      if (!mounted) return;
      setState(() {
        _balance = balance;
        _checkingBalance = false;
      });
    } on InsightFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _checkingBalance = false;
        // 读数失败就把上一次的读数一起清掉：留着它，用户会以为那是现在的余额。
        _balance = null;
        _error = failure.message;
      });
    }
  }

  /// 清掉钥匙串里的密钥。用户既然能把它存下来，就得能把它拿掉。
  Future<void> _clearKey() async {
    await ref.read(insightApiKeyProvider.notifier).clear();
    if (!mounted) return;
    _keyController.clear();
    setState(() {
      // 余额是拿密钥读出来的，密钥没了就不该继续挂在页面上。
      _balance = null;
      _error = null;
      _success = '已清除密钥。';
    });
  }

  /// Sends one minimal completion to prove key + model + network all work.
  Future<void> _ping() async {
    final provider = providerFor(_providerId);
    final model =
        _modelFrom(ref.read(settingsProvider).valueOrNull?.insightModel) ?? '';
    setState(() {
      _pinging = true;
      _error = null;
      _success = null;
    });
    try {
      await pingProvider(
        provider: provider,
        model: model,
        apiKey: ref.read(insightApiKeyProvider),
        client: ref.read(insightHttpClientProvider),
      );
      if (!mounted) return;
      setState(() {
        _pinging = false;
        _success = '连通正常：${provider.label} · $model。'
            '推理模型可能只返回推理过程、正文为空，这同样算连通。';
      });
    } on InsightFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _pinging = false;
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
    final model = _modelFrom(storedModel);
    final curated = _fetchedModels == null;
    // 从 notifier 读而不是从输入框读：输入框每敲一下都会推 state，这里才跟着
    // rebuild，「清除密钥」才会在填上之后出现、清掉之后消失。
    final keySet = ref.watch(insightApiKeyProvider).trim().isNotEmpty;

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
                    child: AppMenuField(
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
                          // 一个服务商的余额不是另一个的：切过去就把读数清掉，
                          // 否则会挂着上一个服务商的钱数。
                          _balance = null;
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
                    child: AppMenuField(
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
              Text(
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
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _ActionPill(
                    label: _fetching ? '获取中…' : '获取可用模型',
                    busy: _fetching,
                    onTap: _busy ? null : _fetchModels,
                  ),
                  // Only where we have a verified endpoint; Claude keeps the
                  // honest 「暂不支持」 absence rather than a button that fails.
                  if (provider.supportsChat)
                    _ActionPill(
                      label: _pinging ? '测试中…' : '连通性测试',
                      busy: _pinging,
                      onTap: _busy ? null : _ping,
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
                        // 每次改动都写进会话内存的 provider：详情页生成洞察时
                        // 要用同一把钥匙。只写内存，不落库、不落日志。
                        onChanged: (value) => ref
                            .read(insightApiKeyProvider.notifier)
                            .update(value),
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
              Text(
                '密钥存在系统钥匙串里（iOS / macOS 钥匙串、Android Keystore），'
                '不写入数据库、日志与导出文件；重启后仍在。',
                style: TextStyle(fontSize: 12, color: tokens.textMuted),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (provider.supportsBalance)
                    _ActionPill(
                      label: _balanceLabel,
                      busy: _checkingBalance,
                      onTap: _busy ? null : _checkBalance,
                    )
                  else
                    // 没有可调用的余额接口就如实说没有：不做假按钮，也不显示
                    // 一个我们读不到的余额（偏差 #3）。
                    const _ActionPill(label: '余额查询未接入', enabled: false),
                  // 密钥一旦能跨重启留存，就必须给得出一个删除入口。
                  if (keySet)
                    _ActionPill(
                      label: '清除密钥',
                      onTap: _busy ? null : _clearKey,
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

/// The pill-shaped action used for every provider call on this page.
///
/// Three actions share one look on purpose: fetching models, testing
/// connectivity and reading the balance are all "press this, wait, get told
/// what happened", and the page shows their results in one place.
class _ActionPill extends StatelessWidget {
  const _ActionPill({
    required this.label,
    this.onTap,
    this.busy = false,
    this.enabled = true,
  });

  final String label;
  final VoidCallback? onTap;
  final bool busy;

  /// False renders the inert "not available here" state — used for providers
  /// with no balance endpoint. Never wire an inert pill to a real action.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Pressable(
        onTap: enabled ? onTap : null,
        haptic: false,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: enabled ? tokens.accentSoft : tokens.bgMuted,
            borderRadius: BorderRadius.circular(AppRadii.pill),
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
