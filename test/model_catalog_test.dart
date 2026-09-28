import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:night_sleep/features/settings/data/model_catalog.dart';

/// The model list is the one place this app talks to a third party with the
/// user's credential, so the tests here are as much about what must NOT happen
/// — leaking the key, inventing a model, trusting a malformed body — as about
/// the happy path.
void main() {
  const key = 'sk-super-secret-value';

  http.Client clientReturning(
    int status,
    String body, {
    void Function(http.Request request)? inspect,
  }) {
    return MockClient((request) async {
      inspect?.call(request);
      // Explicit UTF-8 bytes, with no `charset` in Content-Type — which is how
      // most providers actually answer. `http.Response(String, ...)` would
      // encode as latin-1, which is exactly the case the client must not
      // assume.
      return http.Response.bytes(utf8.encode(body), status);
    });
  }

  InsightProvider deepseek() => providerFor(InsightProviderId.deepseek);

  group('fetchProviderModels', () {
    test('返回服务商给出的模型 id，并排序', () async {
      final models = await fetchProviderModels(
        provider: deepseek(),
        apiKey: key,
        client: clientReturning(
          200,
          jsonEncode({
            'object': 'list',
            'data': [
              {'id': 'deepseek-v4-pro', 'object': 'model'},
              {'id': 'deepseek-flash', 'object': 'model'},
            ],
          }),
        ),
      );

      expect(models, ['deepseek-flash', 'deepseek-v4-pro']);
    });

    test('只取 data[].id，忽略响应里的其他字段', () async {
      final models = await fetchProviderModels(
        provider: deepseek(),
        apiKey: key,
        client: clientReturning(
          200,
          jsonEncode({
            'data': [
              {
                'id': 'deepseek-flash',
                'owned_by': 'deepseek',
                'balance': '¥18.60',
                'permission': [
                  {'allow': true}
                ],
              },
            ],
          }),
        ),
      );

      // The prototype shows a per-provider balance; nothing like it may leak
      // into the model list just because the payload happened to carry it.
      expect(models, ['deepseek-flash']);
    });

    test('响应不带 charset 时按 UTF-8 解码，中文不会乱码', () async {
      // `http.Response.body` falls back to latin-1 when the response omits
      // `charset`, which turns any non-ASCII provider text into mojibake. The
      // client reads the raw bytes as UTF-8 instead, because JSON is UTF-8 by
      // definition.
      final models = await fetchProviderModels(
        provider: deepseek(),
        apiKey: key,
        client: clientReturning(
          200,
          '{"data":[{"id":"deepseek-flash","name":"鼎深·闪电"}]}',
        ),
      );

      expect(models, ['deepseek-flash']);
    });

    test('非 200 抛出的错误里不回显响应体', () async {
      // Provider error payloads can quote request headers back, so the body is
      // deliberately dropped rather than surfaced.
      final failure = await _captureFailure(
        () => fetchProviderModels(
          provider: deepseek(),
          apiKey: key,
          client: clientReturning(
            500,
            'upstream error for Authorization: Bearer $key',
          ),
        ),
      );

      expect(failure.message, contains('500'));
      expect(failure.message, isNot(contains(key)));
      expect(failure.message, isNot(contains('Bearer')));
    });

    test('401 给出可操作的提示', () async {
      final failure = await _captureFailure(
        () => fetchProviderModels(
          provider: deepseek(),
          apiKey: key,
          client: clientReturning(401, '{"error":"invalid api key"}'),
        ),
      );

      expect(failure.message, contains('API Key'));
    });

    test('空 key 直接拒绝，不发请求', () async {
      var called = false;
      final failure = await _captureFailure(
        () => fetchProviderModels(
          provider: deepseek(),
          apiKey: '   ',
          client: clientReturning(200, '{"data":[]}',
              inspect: (_) => called = true),
        ),
      );

      expect(failure.message, contains('API Key'));
      expect(called, isFalse, reason: '没有密钥就不该发出请求');
    });

    test('响应体不是预期结构时报错而不是返回空列表', () async {
      final failure = await _captureFailure(
        () => fetchProviderModels(
          provider: deepseek(),
          apiKey: key,
          client: clientReturning(200, '{"models":["a"]}'),
        ),
      );

      expect(failure.message, contains('格式'));
    });

    test('data 为空也视为失败，不显示一个空的下拉', () async {
      final failure = await _captureFailure(
        () => fetchProviderModels(
          provider: deepseek(),
          apiKey: key,
          client: clientReturning(200, '{"data":[]}'),
        ),
      );

      expect(failure.message, contains('没有返回任何模型'));
    });

    test('请求带上 bearer 头与正确的地址', () async {
      String? auth;
      Uri? uri;
      await fetchProviderModels(
        provider: deepseek(),
        apiKey: key,
        client: clientReturning(
          200,
          '{"data":[{"id":"deepseek-flash"}]}',
          inspect: (request) {
            auth = request.headers['Authorization'];
            uri = request.url;
          },
        ),
      );

      expect(auth, 'Bearer $key');
      expect(uri.toString(), 'https://api.deepseek.com/models');
    });

    test('Claude 用 x-api-key 而不是 bearer', () async {
      Map<String, String>? headers;
      await fetchProviderModels(
        provider: providerFor(InsightProviderId.claude),
        apiKey: key,
        client: clientReturning(
          200,
          '{"data":[{"id":"claude-sonnet-5"}]}',
          inspect: (request) => headers = request.headers,
        ),
      );

      expect(headers?['x-api-key'], key);
      expect(headers?['anthropic-version'], isNotNull);
      expect(headers?.containsKey('Authorization'), isFalse);
    });
  });

  group('内置列表', () {
    test('只有核实过的服务商才带模型名', () async {
      // OpenAI's documentation could not be read, so guessing ids for it would
      // be putting a plausible-looking string in front of the user that 404s on
      // use. An empty list plus a live fetch is the honest state.
      final openai = providerFor(InsightProviderId.openai);
      expect(openai.curated, isEmpty);
      expect(openai.curationSource, isNotEmpty);
    });

    test('每个内置模型都记录了核实日期', () async {
      for (final provider in kInsightProviders) {
        for (final model in provider.curated) {
          expect(
            model.checkedOn,
            matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')),
            reason: '${provider.label} 的 ${model.id} 缺少核实日期',
          );
        }
      }
    });

    test('DeepSeek 是默认服务商，且自带可用模型', () async {
      expect(InsightProviderId.fromId(null), isNull);
      final deepseek = providerFor(InsightProviderId.deepseek);
      expect(deepseek.curated.map((m) => m.id), contains('deepseek-flash'));
    });

    test('未知的服务商 id 不会崩，回退到 null 由调用方决定', () async {
      expect(InsightProviderId.fromId('gemini'), isNull);
      expect(InsightProviderId.fromId('deepseek'), InsightProviderId.deepseek);
    });
  });
}

Future<ModelFetchFailure> _captureFailure(Future<void> Function() body) async {
  try {
    await body();
  } on ModelFetchFailure catch (failure) {
    return failure;
  }
  fail('预期抛出 ModelFetchFailure，但没有');
}
