import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/core/telemetry/event_log.dart';
import 'package:night_sleep/core/theme/app_theme.dart';
import 'package:night_sleep/core/widgets/ios_controls.dart';
import 'package:night_sleep/features/settings/data/export_storage.dart';
import 'package:night_sleep/features/settings/domain/sleep_export.dart';
import 'package:night_sleep/features/settings/presentation/event_log_page.dart';

/// 运行日志页的 widget 测试。
///
/// 埋点与导出通道都换成假实现：这里只断言页面把**正确的条数与内容**交给
/// 导出通道、把「没有」如实说成「没有」，不进平台文件保存。
class _FakeEventLog implements EventLog {
  _FakeEventLog([List<EventLogEntry>? initial]) : entries = [...?initial];

  final List<EventLogEntry> entries;
  final tracked = <String>[];
  int clears = 0;

  @override
  void track(String event, [Map<String, Object?> data = const {}]) {
    tracked.add(event);
  }

  @override
  Future<List<EventLogEntry>> readAll() async => List.of(entries);

  @override
  Future<String> exportContent() async => jsonEncode({
        'count': entries.length,
        'entries': [for (final entry in entries) entry.toJson()],
      });

  @override
  Future<void> clear() async {
    clears++;
    entries.clear();
  }
}

class _FakeStorage implements ExportStorage {
  ExportSaveResult result = const ExportSaveResult(savedCount: 1, fileCount: 1);
  List<ExportFile>? received;

  @override
  Future<ExportSaveResult> save(List<ExportFile> files) async {
    received = files;
    return ExportSaveResult(
      savedCount: result.savedCount,
      fileCount: files.length,
      failed: result.failed,
    );
  }

  @override
  Future<ExportLocation> location() async => const ExportLocation(
        label: '下载/夜深',
        custom: false,
        canChoose: true,
      );

  @override
  Future<ExportLocation?> chooseLocation() async => null;

  @override
  Future<ExportLocation> resetLocation() async => const ExportLocation(
        label: '下载/夜深',
        custom: false,
        canChoose: true,
      );

  @override
  Future<String?> latestBackupPath() async => null;
}

void main() {
  EventLogEntry entry(String event, [Map<String, Object?> data = const {}]) =>
      EventLogEntry(
        time: DateTime.utc(2026, 10, 25, 8),
        event: event,
        data: data,
      );

  /// 二级页由路由器推入：页面自己带 Scaffold（`Subpage`），这里补的
  /// MaterialApp 只提供主题与 Material 祖先，不额外包 Scaffold。
  Future<void> pumpRoute(
    WidgetTester tester, {
    required _FakeEventLog log,
    required _FakeStorage storage,
  }) async {
    tester.view.physicalSize = const Size(430, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          eventLogProvider.overrideWithValue(log),
          exportStorageProvider.overrideWithValue(storage),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const EventLogPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('有记录时显示条数与每条事件', (tester) async {
    await pumpRoute(
      tester,
      log: _FakeEventLog([
        entry('app_start'),
        entry('tab_select', {'to': 'stats'}),
      ]),
      storage: _FakeStorage(),
    );

    expect(find.text('当前有 2 条记录'), findsOneWidget);
    expect(find.text('app_start'), findsOneWidget);
    expect(find.text('tab_select'), findsOneWidget);
    // 结构化字段拼出来给人看：k=v 的形式。
    expect(find.text('to=stats'), findsOneWidget);
  });

  testWidgets('导出把记录交给保存通道，文件名带时间戳', (tester) async {
    final storage = _FakeStorage();
    await pumpRoute(
      tester,
      log: _FakeEventLog([entry('app_start')]),
      storage: storage,
    );

    await tester.tap(find.text('导出日志数据'));
    await tester.pumpAndSettle();

    final files = storage.received;
    expect(files, hasLength(1));
    expect(files!.single.fileName, startsWith('night_sleep_events_'));
    expect(files.single.mimeType, 'application/json');
    expect(
      (jsonDecode(files.single.content) as Map<String, Object?>)['count'],
      1,
    );
    expect(find.text('已导出 1 条记录。'), findsOneWidget);
  });

  testWidgets('没有记录时导出不出空文件、清空禁用', (tester) async {
    final log = _FakeEventLog();
    final storage = _FakeStorage();
    await pumpRoute(tester, log: log, storage: storage);

    await tester.tap(find.text('导出日志数据'));
    await tester.pumpAndSettle();

    expect(storage.received, isNull);
    expect(find.text('还没有可导出的记录。'), findsOneWidget);

    final clearFinder = find.text('清空日志');
    expect(clearFinder, findsOneWidget);
    final item = tester.widget<IosListItem>(
      find.ancestor(of: clearFinder, matching: find.byType(IosListItem)),
    );
    expect(item.onTap, isNull);
  });
}
