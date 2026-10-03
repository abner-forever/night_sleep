import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:night_sleep/app/app.dart';
import 'package:night_sleep/core/database/app_database.dart'
    show AppDatabase, AppSetting, databaseProvider;
import 'package:night_sleep/core/theme/app_theme.dart';
import 'package:night_sleep/features/settings/data/insight_credentials.dart';
import 'package:night_sleep/features/settings/data/insight_service.dart';
import 'package:night_sleep/features/sleep/data/sleep_repository.dart';
import 'package:night_sleep/features/sleep/domain/sleep_entry.dart';
import 'package:night_sleep/features/sleep/domain/sleep_insight.dart';
import 'package:night_sleep/features/sleep/domain/sleep_quality.dart';
import 'package:night_sleep/features/sleep/domain/sleep_score.dart';
import 'package:night_sleep/features/sleep/presentation/sheets/detail_sheet.dart';

/// Generating, storing and displaying one night's model-written summary.
///
/// The invariants that matter here:
///
///  * one record holds **one** insight — a regenerate is an upsert, not a
///    second row that later reads would pick between arbitrarily;
///  * a model insight **without** a score must not wipe out the score the local
///    rules can still compute;
///  * a failed request changes nothing — no write, and no erasing of the
///    summary the user already had.
void main() {
  late AppDatabase database;
  late SleepRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = SleepRepository(database);
  });

  tearDown(() => database.close());

  final bedtime = DateTime(2026, 9, 26, 23, 12).toUtc();
  final wake = DateTime(2026, 9, 27, 7, 3).toUtc();

  Future<SleepEntry> seedRecord({
    String id = 'night-1',
    SleepQuality? quality = SleepQuality.good,
  }) async {
    await repository.save(
      id: id,
      startAtUtc: bedtime,
      endAtUtc: wake,
      timeZoneId: 'UTC',
      quality: quality,
      notes: '',
      events: LoggedEvents.none,
    );
    final entries = await repository.loadAll();
    return entries.firstWhere((entry) => entry.id == id);
  }

  group('saveInsight', () {
    test('同一条记录只有一行洞察，重新生成是覆盖不是新增', () async {
      final entry = await seedRecord();

      await repository.saveInsight(
        recordId: entry.id,
        content: '第一次',
        provider: 'DeepSeek',
        model: 'deepseek-flash',
        score: 80,
        generatedAtUtc: DateTime(2026, 9, 27, 8),
      );
      await repository.saveInsight(
        recordId: entry.id,
        content: '第二次',
        provider: 'DeepSeek',
        model: 'deepseek-flash',
        score: 90,
        generatedAtUtc: DateTime(2026, 9, 27, 9),
      );

      final reloaded = await repository.loadAll();
      expect(reloaded, hasLength(1));
      final insight = reloaded.single.insight!;
      expect(insight.content, '第二次');
      expect(insight.score, 90);
      expect(insight.provider, 'DeepSeek');
      expect(insight.model, 'deepseek-flash');
      expect(insight.status, InsightStatus.ok);
    });
  });

  group('scoreSource', () {
    test('模型没给分时回退到本地估算，而不是把评分整个吞掉', () async {
      final entry = await seedRecord();
      // 先把「模型写了总结但没给分」这条洞察挂上去。
      await repository.saveInsight(
        recordId: entry.id,
        content: '昨晚整体不错，可以再早一点睡。',
        provider: 'DeepSeek',
        model: 'deepseek-flash',
        score: null,
        generatedAtUtc: DateTime(2026, 9, 27, 8),
      );

      final reloaded = (await repository.loadAll()).single;
      expect(reloaded.insightText, isNotNull, reason: '正文仍然要显示');
      expect(reloaded.scoreSource, ScoreSource.onDeviceEstimate);
      expect(reloaded.score, isNotNull, reason: '本地规则仍应给出评分');
    });

    test('模型给了分就以模型分准', () async {
      final entry = await seedRecord();
      await repository.saveInsight(
        recordId: entry.id,
        content: '总结',
        provider: 'DeepSeek',
        model: 'deepseek-flash',
        score: 88,
        generatedAtUtc: DateTime(2026, 9, 27, 8),
      );

      final reloaded = (await repository.loadAll()).single;
      expect(reloaded.scoreSource, ScoreSource.modelInsight);
      expect(reloaded.score, 88);
    });
  });

  group('copyWith', () {
    test('只换洞察，其余字段一个不动', () async {
      final entry = await seedRecord();
      final replaced = entry.copyWith(
        insight: Insight(
          id: 'x',
          content: '新的总结',
          generatedAtUtc: DateTime(2026, 9, 27, 8),
          status: InsightStatus.ok,
        ),
      );

      expect(replaced.insightText, '新的总结');
      expect(replaced.id, entry.id);
      expect(replaced.startAtUtc, entry.startAtUtc);
      expect(replaced.quality, entry.quality);
      expect(replaced.loggedEvents.snore, entry.loggedEvents.snore);
    });
  });

  group('详情页的洞察区块', () {
    AppSetting configured({
      bool withProvider = true,
      String provider = 'deepseek',
      String model = 'deepseek-flash',
    }) =>
        AppSetting(
          id: 'default',
          themeMode: 'system',
          sleepGoalMinutes: 480,
          bedtimeReminderEnabled: false,
          bedtimeReminderMinutes: null,
          wakeReminderEnabled: false,
          wakeReminderMinutes: null,
          soundRecordingEnabled: false,
          onboarded: true,
          insightProvider: withProvider ? provider : null,
          insightModel: withProvider ? model : null,
        );

    Future<void> pumpSheet(
      WidgetTester tester,
      SleepEntry entry, {
      required AppSetting appSettings,
      required String apiKey,
      required http.Client client,
    }) async {
      tester.view.physicalSize = const Size(430, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(database),
            sleepEntriesProvider.overrideWith((ref) => [entry]),
            settingsProvider.overrideWith((ref) => Stream.value(appSettings)),
            insightApiKeyProvider.overrideWith(() => _FrozenKey(apiKey)),
            insightHttpClientProvider.overrideWithValue(client),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showSleepDetailSheet(context, entry),
                  child: const Text('打开详情'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('打开详情'));
      await tester.pumpAndSettle();
    }

    http.Client completion(String content) => MockClient(
          (request) async => http.Response.bytes(
            utf8.encode(jsonEncode({
              'choices': [
                {
                  'message': {'content': content},
                }
              ],
            })),
            200,
          ),
        );

    testWidgets('没填 API Key 时按钮仍在但变灰，并指名差的是哪一样', (tester) async {
      // 未评分 → 本地估算也为空，于是这一晚真的「什么都没有」，
      // 正是最需要出现「重新生成」入口的情形。
      final entry = await seedRecord(quality: null);
      var called = false;
      await pumpSheet(
        tester,
        entry,
        appSettings: configured(),
        apiKey: '',
        client: MockClient((request) async {
          called = true;
          return http.Response('{}', 200);
        }),
      );

      expect(find.text('睡眠洞察'), findsOneWidget);
      expect(find.text('这一晚还没有洞察。'), findsOneWidget);
      // 按钮**必须在**：藏起来的话，用户填好了 key 也只看到一行字，
      // 分不清是自己没配对还是功能没做（这条被连着报回来两次）。
      expect(find.text('重新生成'), findsOneWidget);
      // 只说「去配置」而没说配什么是没用的：这句必须点名 API Key。
      expect(find.textContaining('API Key'), findsOneWidget);

      await tester.tap(find.text('重新生成'));
      await tester.pumpAndSettle();
      expect(called, isFalse, reason: '灰按钮不该发出请求');
    });

    testWidgets('全新安装（provider / model 都还是 null）也照样给按钮', (tester) async {
      // 这是用户实机报的那个 bug：设置页把 DeepSeek · deepseek-flash 当默认值
      // 显示出来，但库里两列都是 null。详情页此前读的是裸列，于是判成「没配置」，
      // 一个已经填好 key、余额和连通性都跑通的用户反而看不到「重新生成」。
      final entry = await seedRecord();
      await pumpSheet(
        tester,
        entry,
        appSettings: configured(withProvider: false),
        apiKey: 'sk-test',
        client: completion(jsonEncode({'score': 77, 'summary': '默认服务商也能生成。'})),
      );

      expect(find.text('重新生成'), findsOneWidget);
      await tester.tap(find.text('重新生成'));
      await tester.pumpAndSettle();

      expect(find.text('默认服务商也能生成。'), findsOneWidget);
      final stored = (await repository.loadAll()).single;
      expect(stored.insight!.provider, 'DeepSeek');
      expect(stored.insight!.model, 'deepseek-flash');
    });

    testWidgets('Claude 按钮变灰，并说明是服务商不支持', (tester) async {
      final entry = await seedRecord(quality: null);
      await pumpSheet(
        tester,
        entry,
        appSettings: configured(provider: 'claude', model: 'claude-sonnet-5'),
        apiKey: 'sk-test',
        client: completion('{}'),
      );

      expect(find.text('重新生成'), findsOneWidget);
      expect(find.textContaining('Claude 暂不支持'), findsOneWidget);
    });

    testWidgets('配置齐全后重新生成：落库、回显总结与模型来源', (tester) async {
      final entry = await seedRecord();
      await pumpSheet(
        tester,
        entry,
        appSettings: configured(),
        apiKey: 'sk-test',
        client: completion(jsonEncode({
          'score': 88,
          'summary': '昨晚 23:12 入睡，整体睡眠良好，可以保持。',
        })),
      );

      expect(find.text('重新生成'), findsOneWidget);
      await tester.tap(find.text('重新生成'));
      await tester.pumpAndSettle();

      expect(find.text('昨晚 23:12 入睡，整体睡眠良好，可以保持。'), findsOneWidget);
      expect(find.text('模型生成'), findsOneWidget);
      expect(find.textContaining('DeepSeek · deepseek-flash'), findsOneWidget);

      final stored = (await repository.loadAll()).single;
      expect(stored.insight!.content, contains('整体睡眠良好'));
      expect(stored.insight!.score, 88);
      expect(stored.score, 88);
    });

    testWidgets('生成失败：页内报错、不写库、也不抹掉已有洞察', (tester) async {
      final entry = await seedRecord();
      // 先有一条已有的洞察，验证失败不会把它换掉。
      await repository.saveInsight(
        recordId: entry.id,
        content: '原有的结论',
        provider: 'DeepSeek',
        model: 'deepseek-flash',
        score: 70,
        generatedAtUtc: DateTime(2026, 9, 27, 8),
      );
      final seeded = (await repository.loadAll()).single;

      await pumpSheet(
        tester,
        seeded,
        appSettings: configured(),
        apiKey: 'sk-test',
        client: MockClient(
          (request) async => http.Response('{"error":"boom"}', 500),
        ),
      );

      expect(find.text('原有的结论'), findsOneWidget);
      await tester.tap(find.text('重新生成'));
      await tester.pumpAndSettle();

      expect(find.textContaining('HTTP 500'), findsOneWidget);
      expect(find.text('原有的结论'), findsOneWidget, reason: '失败不得清空已有洞察');

      final stored = (await repository.loadAll()).single;
      expect(stored.insight!.content, '原有的结论');
      expect(stored.insight!.score, 70);
    });
  });
}

/// A key that is already filled in, the way the settings page leaves it.
class _FrozenKey extends InsightApiKeyNotifier {
  _FrozenKey(this._value);

  final String _value;

  @override
  String build() => _value;
}
