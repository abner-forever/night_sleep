/// Everything this app asks a model provider to do besides listing models:
/// read the account balance, prove the key and model actually work, and write
/// one night's summary.
///
/// All three follow the rules `fetchProviderModels` established, for the same
/// reason — the credential is the user's, and the provider's error payload can
/// quote request headers straight back at you:
///
///  * the key travels in a header only, and is never logged or persisted;
///  * no failure message ever contains the response body;
///  * the response is parsed for exactly the fields we asked for and nothing
///    else is displayed.
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'model_catalog.dart';

/// The HTTP client the insight calls use, or null to let each call own one.
///
/// A seam for tests only: it is the single injection point that lets a widget
/// test drive the whole generate-then-store path without a real network. It
/// carries no key and no state — nothing to leak.
final insightHttpClientProvider = Provider<http.Client?>((ref) => null);

/// A provider call that failed, with a message safe to show the user.
class InsightServiceFailure implements InsightFailure {
  const InsightServiceFailure(this.message);

  @override
  final String message;

  @override
  String toString() => message;
}

/// What one account is worth right now.
///
/// Deliberately no `double`: the provider sends money as a decimal *string*
/// (`"42.51"`), and converting it to a binary float only to format it back
/// would risk displaying a number that differs from the one the provider sent.
class ProviderBalance {
  const ProviderBalance({
    required this.currency,
    required this.totalBalance,
    required this.isAvailable,
  });

  /// ISO code as returned, e.g. `CNY`.
  final String currency;

  /// Verbatim from the provider, e.g. `42.51`.
  final String totalBalance;

  /// The provider's own "can this account be used" flag.
  final bool isAvailable;

  /// Symbol for the two currencies we can write without guessing; anything
  /// else keeps its code (`42.51 JPY`) rather than inventing a symbol.
  String get display {
    final symbol = switch (currency) {
      'CNY' => '¥',
      'USD' => r'$',
      _ => null,
    };
    return symbol == null ? '$totalBalance $currency' : '$symbol$totalBalance';
  }
}

/// A model-written night summary, plus the score it returned if it returned one.
class GeneratedSummary {
  const GeneratedSummary({required this.summary, this.score});

  final String summary;

  /// The model's own 0–100 rating, when it supplied a usable one. Null means
  /// "no usable score", never "score zero".
  final int? score;
}

/// Reads the account balance, where the provider publishes one.
///
/// DeepSeek's `GET /user/balance` was verified against a real key on
/// 2026-10-03. Providers without a callable endpoint fail here rather than
/// showing a number we made up — see 偏差 #3.
Future<ProviderBalance> fetchProviderBalance({
  required InsightProvider provider,
  required String apiKey,
  http.Client? client,
  Duration timeout = const Duration(seconds: 15),
}) async {
  final uri = provider.balanceUri;
  if (uri == null) {
    throw InsightServiceFailure('${provider.label} 没有可调用的余额接口');
  }
  final key = apiKey.trim();
  if (key.isEmpty) {
    throw const InsightServiceFailure('请先填写 API Key');
  }

  final owned = client == null;
  final http.Client httpClient = client ?? http.Client();
  try {
    final response = await httpClient
        .get(Uri.parse(uri), headers: provider.authHeaders(key))
        .timeout(timeout);

    _throwForStatus(response.statusCode, provider);

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw const InsightServiceFailure('返回格式不是预期的余额结构');
    }
    final available = decoded['is_available'];
    final infos = decoded['balance_infos'];
    if (available is! bool || infos is! List || infos.isEmpty) {
      throw const InsightServiceFailure('返回格式不是预期的余额结构');
    }
    // One currency per account in practice; show the first the provider lists.
    final first = infos.first;
    if (first is! Map || first['currency'] is! String) {
      throw const InsightServiceFailure('返回格式不是预期的余额结构');
    }
    final total = first['total_balance'];
    if (total is! String) {
      throw const InsightServiceFailure('返回格式不是预期的余额结构');
    }

    return ProviderBalance(
      currency: first['currency'] as String,
      totalBalance: total,
      isAvailable: available,
    );
  } on InsightFailure {
    rethrow;
  } catch (error) {
    throw InsightServiceFailure('查询失败：$error');
  } finally {
    if (owned) httpClient.close();
  }
}

/// Proves the key, the selected model and the network all work, by asking the
/// provider for a completion.
///
/// **An empty reply still counts as connected.** The model this was verified
/// against (`deepseek-flash`) is a reasoning model: with a small token budget
/// it spends the whole allowance thinking and returns `content: ""` with
/// `finish_reason: "length"`. Requiring non-empty text would report a working
/// key as broken. What is asserted is that the provider accepted the request
/// and answered with a well-formed completion.
Future<void> pingProvider({
  required InsightProvider provider,
  required String model,
  required String apiKey,
  http.Client? client,
  Duration timeout = const Duration(seconds: 30),
}) async {
  final uri = provider.chatUri;
  if (uri == null) {
    throw InsightServiceFailure('${provider.label} 暂不支持连通性测试');
  }
  final key = apiKey.trim();
  if (key.isEmpty) {
    throw const InsightServiceFailure('请先填写 API Key');
  }
  if (model.trim().isEmpty) {
    throw const InsightServiceFailure('请先选择模型');
  }

  final owned = client == null;
  final http.Client httpClient = client ?? http.Client();
  try {
    final response = await httpClient
        .post(
          Uri.parse(uri),
          headers: provider.completionHeaders(key),
          body: jsonEncode({
            'model': model,
            'messages': const [
              {'role': 'user', 'content': 'ping'},
            ],
            'max_tokens': 16,
          }),
        )
        .timeout(timeout);

    _throwForStatus(response.statusCode, provider);

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map || decoded['choices'] is! List) {
      throw const InsightServiceFailure('返回格式不是预期的补全结果');
    }
    final choices = decoded['choices'] as List;
    if (choices.isEmpty || choices.first is! Map) {
      throw const InsightServiceFailure('服务商没有返回任何补全结果');
    }
    // Anything beyond "there is a choice here" is deliberately not inspected:
    // see the doc comment about empty content.
  } on InsightFailure {
    rethrow;
  } catch (error) {
    throw InsightServiceFailure('连通性测试失败：$error');
  } finally {
    if (owned) httpClient.close();
  }
}

/// Asks the model to write one night's summary.
///
/// Runs in JSON mode, which DeepSeek (and the OpenAI-compatible family)
/// supports; the prompt must mention "json" for that mode to be accepted.
Future<GeneratedSummary> generateSummary({
  required InsightProvider provider,
  required String model,
  required String apiKey,
  required String systemPrompt,
  required String userPrompt,
  http.Client? client,
  Duration timeout = const Duration(seconds: 90),
}) async {
  final uri = provider.chatUri;
  if (uri == null) {
    throw InsightServiceFailure('${provider.label} 暂不支持生成洞察');
  }
  final key = apiKey.trim();
  if (key.isEmpty) {
    throw const InsightServiceFailure('请先填写 API Key');
  }
  if (model.trim().isEmpty) {
    throw const InsightServiceFailure('请先选择模型');
  }

  final owned = client == null;
  final http.Client httpClient = client ?? http.Client();
  try {
    final response = await httpClient
        .post(
          Uri.parse(uri),
          headers: provider.completionHeaders(key),
          body: jsonEncode({
            'model': model,
            'messages': [
              {'role': 'system', 'content': systemPrompt},
              {'role': 'user', 'content': userPrompt},
            ],
            // 推理模型会先把预算花在推理上：实测 16 token 时正文为空，
            // 2048 才稳定拿到完整 JSON（一次约 277 token）。
            'max_tokens': 2048,
            'temperature': 0.3,
            'response_format': const {'type': 'json_object'},
          }),
        )
        .timeout(timeout);

    _throwForStatus(response.statusCode, provider);

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map || decoded['choices'] is! List) {
      throw const InsightServiceFailure('返回格式不是预期的补全结果');
    }
    final choices = decoded['choices'] as List;
    if (choices.isEmpty || choices.first is! Map) {
      throw const InsightServiceFailure('服务商没有返回任何补全结果');
    }
    final message = (choices.first as Map)['message'];
    final content = message is Map && message['content'] is String
        ? message['content'] as String
        : '';
    final text = content.trim();
    if (text.isEmpty) {
      throw const InsightServiceFailure('服务商返回了空回复');
    }

    return _parseSummary(text);
  } on InsightFailure {
    rethrow;
  } catch (error) {
    throw InsightServiceFailure('生成失败：$error');
  } finally {
    if (owned) httpClient.close();
  }
}

/// Pulls `{score, summary}` out of the model's reply.
///
/// A model that ignores JSON mode still produced *something true*; when that
/// happens the whole reply becomes the summary and the score stays null rather
/// than being invented. Same rule as everywhere else here: show what came
/// back, never a placeholder.
GeneratedSummary _parseSummary(String text) {
  Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    return GeneratedSummary(summary: text);
  }
  if (decoded is! Map) return GeneratedSummary(summary: text);

  final rawSummary = decoded['summary'];
  final summary = rawSummary is String && rawSummary.trim().isNotEmpty
      ? rawSummary.trim()
      : text;

  final rawScore = decoded['score'];
  final score =
      rawScore is int && rawScore >= 0 && rawScore <= 100 ? rawScore : null;

  return GeneratedSummary(summary: summary, score: score);
}

/// Maps a non-200 status to a message. Deliberately does not touch the body.
void _throwForStatus(int status, InsightProvider provider) {
  if (status == 200) return;
  if (status == 401 || status == 403) {
    throw const InsightServiceFailure('API Key 被拒绝，请检查是否填写正确');
  }
  throw InsightServiceFailure('${provider.label} 返回 HTTP $status');
}
