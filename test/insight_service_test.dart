import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:night_sleep/features/settings/data/insight_service.dart';
import 'package:night_sleep/features/settings/data/model_catalog.dart';

/// The network layer behind 余额查询 / 连通性测试 / 重新生成.
///
/// Two of these carry more weight than the happy paths:
///
///  * **The key must never come back out.** Provider error payloads quote the
///    credential at you (DeepSeek's 401 literally echoes a masked form of it),
///    so the tests feed a response body containing the key and assert no
///    failure message ever contains it.
///  * **An empty completion is still a connected provider.** The model this was
///    verified against is a reasoning model that emits nothing but
///    `reasoning_content` when the token budget is small; a "must have text"
///    rule would report a working key as broken.
void main() {
  const key = 'sk-super-secret-value';

  InsightProvider deepseek() => providerFor(InsightProviderId.deepseek);

  http.Client returning(
    int status,
    String body, {
    void Function(http.Request request)? inspect,
  }) {
    return MockClient((request) async {
      inspect?.call(request);
      return http.Response.bytes(utf8.encode(body), status);
    });
  }

  Future<InsightServiceFailure> capture(Future<void> Function() body) async {
    try {
      await body();
    } on InsightServiceFailure catch (failure) {
      return failure;
    }
    fail('期望抛出 InsightServiceFailure，但没有');
  }

  group('fetchProviderBalance', () {
    test('读出币种、金额与可用性，金额原样保留字符串', () async {
      final balance = await fetchProviderBalance(
        provider: deepseek(),
        apiKey: key,
        client: returning(
          200,
          jsonEncode({
            'is_available': true,
            'balance_infos': [
              {
                'currency': 'CNY',
                'total_balance': '42.51',
                'granted_balance': '0.00',
                'topped_up_balance': '42.51',
              },
            ],
          }),
        ),
      );

      expect(balance.currency, 'CNY');
      // 不转 double 再格式化：`42.51` 必须原样显示成 `42.51`。
      expect(balance.totalBalance, '42.51');
      expect(balance.isAvailable, isTrue);
      expect(balance.display, '¥42.51');
    });

    test('账户不可用时如实标出，而不是显示一个能用的余额', () async {
      final balance = await fetchProviderBalance(
        provider: deepseek(),
        apiKey: key,
        client: returning(
          200,
          jsonEncode({
            'is_available': false,
            'balance_infos': [
              {'currency': 'CNY', 'total_balance': '0.00'},
            ],
          }),
        ),
      );

      expect(balance.isAvailable, isFalse);
    });

    test('不认识的币种照「金额 币种」显示，不猜符号', () async {
      final balance = await fetchProviderBalance(
        provider: deepseek(),
        apiKey: key,
        client: returning(
          200,
          jsonEncode({
            'is_available': true,
            'balance_infos': [
              {'currency': 'JPY', 'total_balance': '1200'},
            ],
          }),
        ),
      );

      expect(balance.display, '1200 JPY');
    });

    test('结构不对时给一句可读的失败，不是崩溃', () async {
      final failure = await capture(
        () => fetchProviderBalance(
          provider: deepseek(),
          apiKey: key,
          client: returning(200, jsonEncode({'balance_infos': []})),
        ),
      );

      expect(failure.message, contains('余额'));
    });

    test('没有余额接口的服务商不发明一个请求', () async {
      var called = false;
      final failure = await capture(
        () => fetchProviderBalance(
          provider: providerFor(InsightProviderId.openai),
          apiKey: key,
          client: MockClient((request) async {
            called = true;
            return http.Response('{}', 200);
          }),
        ),
      );

      expect(called, isFalse, reason: '没有接口就不该发请求');
      expect(failure.message, contains('没有可调用的余额接口'));
    });

    test('空密钥不发请求', () async {
      var called = false;
      final failure = await capture(
        () => fetchProviderBalance(
          provider: deepseek(),
          apiKey: '   ',
          client: MockClient((request) async {
            called = true;
            return http.Response('{}', 200);
          }),
        ),
      );

      expect(called, isFalse);
      expect(failure.message, '请先填写 API Key');
    });
  });

  group('pingProvider', () {
    test('200 且返回补全结果就算连通', () async {
      http.Request? seen;
      await pingProvider(
        provider: deepseek(),
        model: 'deepseek-flash',
        apiKey: key,
        client: returning(
          200,
          jsonEncode({
            'choices': [
              {
                'message': {'role': 'assistant', 'content': ''},
                'finish_reason': 'length',
              }
            ],
          }),
          inspect: (request) => seen = request,
        ),
      );

      // 只发一次、且是最小预算的对话请求。
      final body = jsonDecode(seen!.body) as Map<String, dynamic>;
      expect(body['model'], 'deepseek-flash');
      expect(body['max_tokens'], 16);
      expect(seen!.headers['Authorization'], 'Bearer $key');
    });

    test('推理模型只吐推理过程、正文为空，仍然算连通', () async {
      // 这是实测到的真实形状：`deepseek-flash` 在 16 token 预算下
      // `content` 是空串，正文全在 `reasoning_content`。
      await expectLater(
        pingProvider(
          provider: deepseek(),
          model: 'deepseek-flash',
          apiKey: key,
          client: returning(
            200,
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'role': 'assistant',
                    'content': '',
                    'reasoning_content': 'The user just said "ping".',
                  },
                  'finish_reason': 'length',
                }
              ],
            }),
          ),
        ),
        completes,
      );
    });

    test('密钥被拒时给出可操作的文案', () async {
      final failure = await capture(
        () => pingProvider(
          provider: deepseek(),
          model: 'deepseek-flash',
          apiKey: key,
          client: returning(401, '{"error":"nope"}'),
        ),
      );

      expect(failure.message, 'API Key 被拒绝，请检查是否填写正确');
    });

    test('返回体里带着密钥时，失败文案一个字都不许带出来', () async {
      final failure = await capture(
        () => pingProvider(
          provider: deepseek(),
          model: 'deepseek-flash',
          apiKey: key,
          client: returning(
            500,
            // 服务商可能把请求头原样引回来——这正是不能回显响应体的原因。
            '{"error":"upstream failed for Authorization: Bearer $key"}',
          ),
        ),
      );

      expect(failure.message, isNot(contains(key)));
      expect(failure.message, isNot(contains('Authorization')));
      expect(failure.message, contains('HTTP 500'));
    });

    test('没有对话接口就不发请求', () async {
      final failure = await capture(
        () => pingProvider(
          provider: providerFor(InsightProviderId.claude),
          model: 'claude-sonnet-5',
          apiKey: key,
          client: MockClient((request) async => http.Response('{}', 200)),
        ),
      );

      expect(failure.message, contains('暂不支持'));
    });
  });

  group('generateSummary', () {
    Future<GeneratedSummary> generate(http.Client client) => generateSummary(
          provider: deepseek(),
          model: 'deepseek-flash',
          apiKey: key,
          systemPrompt: 'system',
          userPrompt: 'user',
          client: client,
        );

    test('解析出 JSON 模式返回的评分与总结', () async {
      final generated = await generate(
        returning(
          200,
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': jsonEncode({
                    'score': 88,
                    'summary': '9月27日23:12入睡，07:03起床，整体睡眠良好。',
                  }),
                },
              }
            ],
          }),
        ),
      );

      expect(generated.score, 88);
      expect(generated.summary, contains('整体睡眠良好'));
    });

    test('请求带上 JSON 模式与足够的预算', () async {
      http.Request? seen;
      await generate(
        returning(
          200,
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': jsonEncode({'score': 70, 'summary': '还行'}),
                },
              }
            ],
          }),
          inspect: (request) => seen = request,
        ),
      );

      final body = jsonDecode(seen!.body) as Map<String, dynamic>;
      // 推理模型会先花掉预算：16 token 时正文为空，实测 2048 才稳定拿到 JSON。
      expect(body['max_tokens'], 2048);
      expect(body['response_format'], {'type': 'json_object'});
      expect(body['messages'], hasLength(2));
    });

    test('超出 0-100 的评分置空，而不是照单全收', () async {
      final generated = await generate(
        returning(
          200,
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': jsonEncode({'score': 900, 'summary': '不错的夜晚'}),
                },
              }
            ],
          }),
        ),
      );

      expect(generated.score, isNull);
      expect(generated.summary, '不错的夜晚');
    });

    test('模型没走 JSON 模式时，正文原样当总结、评分留空', () async {
      final generated = await generate(
        returning(
          200,
          jsonEncode({
            'choices': [
              {
                'message': {'content': '昨晚睡得挺沉，继续保持。'},
              }
            ],
          }),
        ),
      );

      expect(generated.summary, '昨晚睡得挺沉，继续保持。');
      expect(generated.score, isNull);
    });

    test('空回复是一次失败，不是一条空洞察', () async {
      final failure = await capture(
        () => generate(
          returning(
            200,
            jsonEncode({
              'choices': [
                {
                  'message': {'content': '   '},
                }
              ],
            }),
          ),
        ),
      );

      expect(failure.message, contains('空回复'));
    });

    test('失败文案同样不回显响应体', () async {
      final failure = await capture(
        () => generate(returning(400, '{"error":"bad key $key"}')),
      );

      expect(failure.message, isNot(contains(key)));
    });
  });
}
