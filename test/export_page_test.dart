import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/core/theme/app_theme.dart';
import 'package:night_sleep/core/database/app_database.dart' show AppDatabase;
import 'package:night_sleep/core/theme/app_tokens.dart';
import 'package:night_sleep/features/settings/data/export_sharer.dart';
import 'package:night_sleep/features/settings/data/sleep_backup_service.dart';
import 'package:night_sleep/features/settings/domain/sleep_export.dart';
import 'package:night_sleep/features/settings/presentation/export_page.dart';
import 'package:night_sleep/features/sleep/data/sleep_repository.dart';
import 'package:night_sleep/features/sleep/data/clip_store.dart';
import 'package:night_sleep/features/sleep/domain/sleep_entry.dart';
import 'package:night_sleep/features/sleep/domain/sleep_quality.dart';
import 'package:night_sleep/features/sleep/domain/sleep_stage.dart';

/// 导出页的 widget 测试。
///
/// 分享走的是平台通道，在 FakeAsync 下会挂死，所以这里喂一个假的 [ExportSharer]，
/// 只断言「交出去的内容对不对」。
class _FakeSharer implements ExportSharer {
  _FakeSharer({this.outcome = ShareOutcome.shared});

  final ShareOutcome outcome;
  List<ExportFile>? received;
  String? subject;

  @override
  Future<ShareOutcome> share({
    required List<ExportFile> files,
    required String subject,
  }) async {
    received = files;
    this.subject = subject;
    return outcome;
  }
}

class _FakeBackupService extends SleepBackupService {
  _FakeBackupService(AppDatabase database)
      : super(
          database: database,
          clips: ClipFileStore(baseDirectory: () async => Directory.systemTemp),
        );

  List<SleepEntry>? received;

  @override
  Future<BackupExport> export(List<SleepEntry> entries,
      {required DateTime now}) async {
    received = entries;
    return const BackupExport(
      ExportFile.local(
        fileName: '完整备份.zip',
        localPath: '/temp/完整备份.zip',
        mimeType: 'application/zip',
      ),
      missingAudioCount: 1,
    );
  }
}

void main() {
  SleepEntry entry(
          {required String id, String source = 'manual', int stages = 0}) =>
      SleepEntry(
        id: id,
        startAtUtc: DateTime.utc(2026, 9, 26, 23),
        endAtUtc: DateTime.utc(2026, 9, 27, 7),
        timeZoneId: 'UTC',
        quality: SleepQuality.good,
        source: source,
        createdAtUtc: DateTime.utc(2026, 9, 27, 8),
        updatedAtUtc: DateTime.utc(2026, 9, 27, 8),
        stages: [
          for (var i = 0; i < stages; i++)
            SleepStageSegment(
              stage: SleepStageType.deep,
              startAtUtc: DateTime.utc(2026, 9, 26, 23 + i),
              endAtUtc: DateTime.utc(2026, 9, 27, i),
            ),
        ],
      );

  /// 二级页由路由器推入：**没有 Scaffold**，页面自己带。
  /// 这里补 Scaffold 就等于把背景和 Material 白送给它，测试会全绿而真机是黑底。
  Future<void> pumpRoute(
    WidgetTester tester, {
    required ExportSharer sharer,
    SleepBackupService? backupService,
    List<SleepEntry> entries = const [],

    /// 让 provider 落到**错误**态：这一支要证明「读不到」没有被说成「没有」。
    bool readError = false,
  }) async {
    tester.view.physicalSize = const Size(430, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sleepEntriesProvider.overrideWith((ref) async {
            if (readError) throw StateError('数据库坏了');
            return entries;
          }),
          exportSharerProvider.overrideWithValue(sharer),
          if (backupService != null)
            sleepBackupServiceProvider.overrideWithValue(backupService),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ExportPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('没有真实记录时两个动作禁用并说明原因', (tester) async {
    final sharer = _FakeSharer();
    await pumpRoute(tester, sharer: sharer, entries: [
      entry(id: 'd1', source: 'demo'),
      entry(id: 'd2', source: 'demo'),
    ]);

    expect(find.text('暂无可导出的记录'), findsOneWidget);
    expect(find.text('睡眠数据管理'), findsOneWidget);
    expect(find.text('从备份恢复'), findsOneWidget);
    expect(find.textContaining('已排除 2 条演示记录'), findsOneWidget);

    // 禁用态的文字必须降级，规格明写「置灰」。
    final emptyColor = tester.widget<Text>(find.text('导出 CSV')).style?.color;
    expect(
      emptyColor,
      AppTokens.of(tester.element(find.text('导出 CSV'))).textMuted,
    );

    await tester.tap(find.text('导出 CSV'));
    await tester.pumpAndSettle();
    expect(sharer.received, isNull, reason: '禁用的动作不该调用分享层');
  });

  testWidgets('预览表格与两个导出动作一起禁用并置灰', (tester) async {
    await pumpRoute(tester, sharer: _FakeSharer(), entries: [
      entry(id: 'd1', source: 'demo'),
    ]);

    expect(find.text('预览表格'), findsOneWidget);
    final previewColor = tester.widget<Text>(find.text('预览表格')).style?.color;
    expect(
      previewColor,
      AppTokens.of(tester.element(find.text('预览表格'))).textMuted,
      reason: '与两个导出动作同一套禁用口径',
    );
  });

  testWidgets('有真实记录时预览行是正常色', (tester) async {
    await pumpRoute(tester, sharer: _FakeSharer(), entries: [entry(id: 'a')]);

    final preview = find.text('预览表格');
    expect(
      tester.widget<Text>(preview).style?.color,
      AppTokens.of(tester.element(preview)).textPrimary,
    );
  });

  testWidgets('读不到记录时说读不到，不说「暂无可导出」', (tester) async {
    await pumpRoute(tester, sharer: _FakeSharer(), readError: true);

    expect(find.text('无法读取记录'), findsOneWidget);
    expect(find.text('从备份恢复'), findsOneWidget);
    expect(find.textContaining('数据库坏了'), findsOneWidget);
    // 库里可能有一堆记录，只是这一刻读不出来——把它说成「没有」就是替用户下了
    // 一个没根据的结论，那正是这一页最不该犯的错。
    expect(find.text('暂无可导出的记录'), findsNothing);
    expect(find.text('预览表格'), findsNothing, reason: '读不到就不摆一个点不动的入口');
  });

  testWidgets('条数统计只数真实记录', (tester) async {
    await pumpRoute(
      tester,
      sharer: _FakeSharer(),
      entries: [
        entry(id: 'a', stages: 3),
        entry(id: 'b', stages: 1),
        entry(id: 'd', source: 'demo', stages: 9),
      ],
    );

    expect(find.text('2'), findsOneWidget, reason: '记录数');
    expect(find.text('4'), findsOneWidget, reason: '阶段段数');
    expect(find.textContaining('已排除 1 条演示记录'), findsOneWidget);
    expect(find.text('暂无可导出的记录'), findsNothing);
  });

  testWidgets('点导出 CSV 交出两张表', (tester) async {
    final sharer = _FakeSharer();
    await pumpRoute(tester,
        sharer: sharer, entries: [entry(id: 'a', stages: 2)]);

    await tester.tap(find.text('导出 CSV'));
    await tester.pumpAndSettle();

    expect(sharer.received, hasLength(2));
    expect(sharer.received!.first.fileName, startsWith('夜深-睡眠记录-'));
    expect(sharer.received!.last.fileName, startsWith('夜深-睡眠阶段-'));
    expect(sharer.received!.first.content, contains('a'));
    // 这一页没有演示记录，就不该出现「已排除」那一行。
    expect(find.textContaining('已排除'), findsNothing);
  });

  testWidgets('完整备份按钮交出 ZIP 文件并提示缺失录音', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final backup = _FakeBackupService(database);
    final sharer = _FakeSharer();
    await pumpRoute(tester,
        sharer: sharer, backupService: backup, entries: [entry(id: 'a')]);
    await tester.tap(find.text('导出完整备份（含录音）'));
    await tester.pumpAndSettle();
    expect(backup.received!.single.id, 'a');
    expect(sharer.received!.single.mimeType, 'application/zip');
    expect(sharer.received!.single.localPath, '/temp/完整备份.zip');
    expect(find.text('1 段音频文件已缺失，备份中保留了对应的声音事件。'), findsOneWidget);
  });

  testWidgets('点导出 JSON 交出一份完整存档', (tester) async {
    final sharer = _FakeSharer();
    await pumpRoute(tester, sharer: sharer, entries: [entry(id: 'a')]);

    await tester.tap(find.text('导出 JSON'));
    await tester.pumpAndSettle();

    expect(sharer.received, hasLength(1));
    expect(sharer.received!.single.fileName, startsWith('夜深-睡眠数据-'));
    expect(sharer.received!.single.content, contains('night-sleep-export'));
    expect(sharer.subject, '夜深睡眠数据导出');
  });

  testWidgets('分享失败如实报错，且提示留在页内', (tester) async {
    final sharer = _FakeSharer(outcome: ShareOutcome.failed);
    await pumpRoute(tester, sharer: sharer, entries: [entry(id: 'a')]);

    await tester.tap(find.text('导出 JSON'));
    await tester.pumpAndSettle();

    // 反馈必须是页内文案：全局 toast 挂在 AppScaffold，会被二级页整个盖住。
    final error = find.text('导出失败，文件没有交出去。');
    expect(error, findsOneWidget, reason: '失败必须有页内可见的反馈');
    expect(
      tester.widget<Text>(error).style?.color,
      AppTokens.of(tester.element(error)).danger,
      reason: '失败文案取 tokens.danger',
    );
  });

  testWidgets('用户取消分享面板不算失败，不报错', (tester) async {
    final sharer = _FakeSharer(outcome: ShareOutcome.dismissed);
    await pumpRoute(tester, sharer: sharer, entries: [entry(id: 'a')]);

    await tester.tap(find.text('导出 JSON'));
    await tester.pumpAndSettle();

    // 正向锚点：先证明这一次点击真的走到了分享层。否则「没有提示」可以因为
    // 点击根本没落到按钮上而空转通过。
    expect(sharer.received, isNotNull);
    expect(find.text('导出失败，文件没有交出去。'), findsNothing);
  });
}
