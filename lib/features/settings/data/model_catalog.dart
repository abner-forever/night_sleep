import 'dart:convert';

import 'package:http/http.dart' as http;

/// The insight providers the app can be pointed at, and the models each one
/// actually serves.
///
/// Two rules shaped this file:
///
///  * **No invented model ids.** A model name that looks plausible but does not
///    exist is worse than an empty list: the user picks it, the request 404s,
///    and the failure looks like the app's fault. So a curated list only exists
///    where the provider's own documentation was read, and each one records the
///    date it was checked.
///  * **The live list wins.** Model line-ups move faster than app releases, so
///    the authoritative source is the provider's own `GET /models`, called with
///    the user's key. The curated lists are only what to show before that
///    happens.
enum InsightProviderId {
  deepseek('deepseek', 'DeepSeek'),
  openai('openai', 'OpenAI'),
  claude('claude', 'Claude');

  const InsightProviderId(this.id, this.label);

  final String id;
  final String label;

  static InsightProviderId? fromId(String? id) {
    for (final provider in InsightProviderId.values) {
      if (provider.id == id) return provider;
    }
    return null;
  }
}

/// A model the provider is known to serve.
class CuratedModel {
  const CuratedModel(this.id, this.checkedOn);

  final String id;

  /// The date the provider's documentation was read. Shown in the UI so a stale
  /// list announces itself instead of silently misleading.
  final String checkedOn;
}

class InsightProvider {
  const InsightProvider({
    required this.id,
    required this.modelsUri,
    required this.curated,
    required this.curationSource,
    this.chatUri,
    this.balanceUri,
  });

  final InsightProviderId id;
  final String modelsUri;

  /// May be empty — see [curationSource] for why.
  final List<CuratedModel> curated;

  /// Where the curated list came from, or why there isn't one.
  final String curationSource;

  /// OpenAI-compatible `POST /chat/completions`, or null when this
  /// implementation cannot talk to the provider at all.
  ///
  /// Null is a deliberate, documented gap rather than a bug: Anthropic's
  /// Messages API takes a different request *and* response shape, and no key
  /// for it was available to verify against, so no code was written for it.
  /// See 偏差 #46 in the spec.
  final String? chatUri;

  /// Where the provider publishes the account balance, or null when it has no
  /// callable balance endpoint. See 偏差 #3.
  final String? balanceUri;

  String get label => id.label;

  bool get supportsChat => chatUri != null;

  bool get supportsBalance => balanceUri != null;

  Map<String, String> authHeaders(String apiKey) => switch (id) {
        InsightProviderId.claude => {
            'x-api-key': apiKey,
            // The Models API is versioned like every other Anthropic endpoint.
            'anthropic-version': '2023-06-01',
          },
        // DeepSeek and OpenAI both take a bearer token on an OpenAI-compatible
        // `/models`.
        _ => {'Authorization': 'Bearer $apiKey'},
      };

  /// Auth headers plus a JSON content type, for the OpenAI-compatible `POST`s
  /// in `insight_service.dart`. Only ever called when [supportsChat].
  Map<String, String> completionHeaders(String apiKey) => {
        ...authHeaders(apiKey),
        'Content-Type': 'application/json',
      };
}

/// `GET /models` on each provider, checked 2026-09-27.
///
/// DeepSeek and Anthropic were read from their published documentation; OpenAI's
/// documentation is behind a bot wall, so **no** OpenAI models are listed rather
/// than guessed. Point the OpenAI entry at a key and use 「获取可用模型」.
const List<InsightProvider> kInsightProviders = [
  // chatUri / balanceUri 是否**实测过**，逐条注明——这三行决定了界面上哪些按钮
  // 会真的发请求，写没跑过的地址等于让应用当场撒谎。
  InsightProvider(
    id: InsightProviderId.deepseek,
    modelsUri: 'https://api.deepseek.com/models',
    curationSource: 'https://api-docs.deepseek.com/quick_start/pricing',
    // 两者都在 2026-10-03 用真实 key 打过 200：余额返回
    // `{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"42.51",…}]}`，
    // 对话返回 `{"choices":[{"message":{…}}]}`。
    chatUri: 'https://api.deepseek.com/chat/completions',
    balanceUri: 'https://api.deepseek.com/user/balance',
    curated: [
      CuratedModel('deepseek-flash', '2026-09-27'),
      CuratedModel('deepseek-v4-pro', '2026-09-27'),
    ],
  ),
  InsightProvider(
    id: InsightProviderId.openai,
    modelsUri: 'https://api.openai.com/v1/models',
    curationSource: 'OpenAI 文档未能核实，故不内置任何模型名',
    // OpenAI 兼容协议，与 DeepSeek 共用同一条代码路径；但**没有 key 实测过**，
    // 见 README「验证记录」。余额接口没有公开文档，故不接。
    chatUri: 'https://api.openai.com/v1/chat/completions',
    curated: [],
  ),
  InsightProvider(
    id: InsightProviderId.claude,
    modelsUri: 'https://api.anthropic.com/v1/models',
    curationSource:
        'https://platform.claude.com/docs/en/about-claude/models/overview',
    // 刻意留空：Messages API 的请求与响应形状都与 OpenAI 兼容协议不同，
    // 而手边没有可实测的 key。不写没跑过的代码，见偏差 #46。
    curated: [
      CuratedModel('claude-sonnet-5', '2026-09-27'),
      CuratedModel('claude-opus-5-5', '2026-09-27'),
      CuratedModel('claude-fable-5-1', '2026-09-27'),
      CuratedModel('claude-haiku-4-5', '2026-09-27'),
    ],
  ),
];

InsightProvider providerFor(InsightProviderId id) =>
    kInsightProviders.firstWhere((provider) => provider.id == id);

/// The curated model ids, i.e. what to offer before a live list is fetched.
List<String> curatedModelIds(InsightProvider provider) =>
    [for (final model in provider.curated) model.id];

/// Picks the model a request would use out of [options], keeping [stored] only
/// while the provider still offers it.
String? resolveInsightModel({
  required List<String> options,
  String? stored,
}) {
  if (stored != null && options.contains(stored)) return stored;
  return options.isEmpty ? null : options.first;
}

/// The provider and model the app would actually use.
class InsightSelection {
  const InsightSelection({required this.provider, required this.model});

  final InsightProvider provider;

  /// Null only when the provider serves no curated model and none was fetched.
  final String? model;

  bool get isRunnable => provider.supportsChat && model != null;
}

/// Resolves the selection from the persisted settings row, **applying the same
/// defaults the settings page displays**.
///
/// This exists because of a real bug. `AppSettings.insightProvider` and
/// `insightModel` are legitimately null on a fresh install — the user never had
/// to pick anything, since DeepSeek and its curated models are the defaults the
/// settings page shows. The detail sheet used to read the raw columns, so it
/// saw null, concluded "not configured", and offered no 「重新生成」 button to a
/// user who had already filled in a working key and successfully run both the
/// balance query and the connectivity test. Two readings of one setting is the
/// defect; this is the single reading.
InsightSelection resolveInsightSelection({
  String? providerId,
  String? model,
}) {
  final provider = providerFor(
    InsightProviderId.fromId(providerId) ?? InsightProviderId.deepseek,
  );
  return InsightSelection(
    provider: provider,
    model: resolveInsightModel(
      options: curatedModelIds(provider),
      stored: model,
    ),
  );
}

/// A provider request that failed for a reason worth showing the user.
///
/// One marker for every call this app makes to a provider — model list,
/// balance, connectivity, generation — so the settings page can report all of
/// them the same way without catching bare `Exception`s and accidentally
/// swallowing a programming error.
abstract interface class InsightFailure implements Exception {
  /// Already user-facing Chinese text. Never contains the API key or any part
  /// of the provider's response body.
  String get message;
}

/// Why a model list request failed, in terms the user can act on.
class ModelFetchFailure implements InsightFailure {
  const ModelFetchFailure(this.message);

  @override
  final String message;

  @override
  String toString() => message;
}

/// Asks the provider which models it serves right now.
///
/// The key is used for this request and nothing else — it is never logged, never
/// persisted, and never included in the thrown [ModelFetchFailure]. Only the
/// provider's own `data[].id` values come back; anything else in the response is
/// discarded rather than displayed.
Future<List<String>> fetchProviderModels({
  required InsightProvider provider,
  required String apiKey,
  http.Client? client,
  Duration timeout = const Duration(seconds: 15),
}) async {
  if (apiKey.trim().isEmpty) {
    throw const ModelFetchFailure('请先填写 API Key');
  }

  final owned = client == null;
  final http.Client httpClient = client ?? http.Client();
  try {
    final response = await httpClient
        .get(
          Uri.parse(provider.modelsUri),
          headers: provider.authHeaders(apiKey.trim()),
        )
        .timeout(timeout);

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const ModelFetchFailure('API Key 被拒绝，请检查是否填写正确');
    }
    if (response.statusCode != 200) {
      // Deliberately not echoing the body: provider error payloads can quote
      // request headers back at you.
      throw ModelFetchFailure('服务商返回 HTTP ${response.statusCode}');
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map || decoded['data'] is! List) {
      throw const ModelFetchFailure('返回格式不是预期的模型列表');
    }

    final models = <String>[];
    for (final entry in decoded['data'] as List) {
      if (entry is Map && entry['id'] is String) {
        models.add(entry['id'] as String);
      }
    }
    if (models.isEmpty) {
      throw const ModelFetchFailure('服务商没有返回任何模型');
    }
    models.sort();
    return models;
  } on ModelFetchFailure {
    rethrow;
  } catch (error) {
    throw ModelFetchFailure('获取失败：$error');
  } finally {
    if (owned) httpClient.close();
  }
}
