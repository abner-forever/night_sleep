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
  });

  final InsightProviderId id;
  final String modelsUri;

  /// May be empty — see [curationSource] for why.
  final List<CuratedModel> curated;

  /// Where the curated list came from, or why there isn't one.
  final String curationSource;

  String get label => id.label;

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
}

/// `GET /models` on each provider, checked 2026-09-27.
///
/// DeepSeek and Anthropic were read from their published documentation; OpenAI's
/// documentation is behind a bot wall, so **no** OpenAI models are listed rather
/// than guessed. Point the OpenAI entry at a key and use 「获取可用模型」.
const List<InsightProvider> kInsightProviders = [
  InsightProvider(
    id: InsightProviderId.deepseek,
    modelsUri: 'https://api.deepseek.com/models',
    curationSource: 'https://api-docs.deepseek.com/quick_start/pricing',
    curated: [
      CuratedModel('deepseek-flash', '2026-09-27'),
      CuratedModel('deepseek-v4-pro', '2026-09-27'),
    ],
  ),
  InsightProvider(
    id: InsightProviderId.openai,
    modelsUri: 'https://api.openai.com/v1/models',
    curationSource: 'OpenAI 文档未能核实，故不内置任何模型名',
    curated: [],
  ),
  InsightProvider(
    id: InsightProviderId.claude,
    modelsUri: 'https://api.anthropic.com/v1/models',
    curationSource:
        'https://platform.claude.com/docs/en/about-claude/models/overview',
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

/// Why a model list request failed, in terms the user can act on.
class ModelFetchFailure implements Exception {
  const ModelFetchFailure(this.message);

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
