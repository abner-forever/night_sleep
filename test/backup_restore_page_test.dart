import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/core/database/app_database.dart' show AppDatabase;
import 'package:night_sleep/core/theme/app_theme.dart';
import 'package:night_sleep/features/settings/data/export_storage.dart';
import 'package:night_sleep/features/settings/data/sleep_backup_service.dart';
import 'package:night_sleep/features/settings/domain/sleep_backup.dart';
import 'package:night_sleep/features/settings/domain/sleep_export.dart';
import 'package:night_sleep/features/settings/presentation/backup_restore_page.dart';
import 'package:night_sleep/features/sleep/data/clip_store.dart';
import 'package:night_sleep/features/sleep/data/sleep_repository.dart';
import 'package:night_sleep/features/sleep/domain/sleep_entry.dart';
import 'package:night_sleep/features/sleep/domain/sound_event.dart';

class _Picker implements BackupFilePicker {
  String? result = 'backup.zip';

  @override
  Future<String?> pick() async => result;
}

class _Storage implements ExportStorage {
  String? latest;

  @override
  Future<ExportLocation> location() async => const ExportLocation(
        label: '下载/夜深',
        custom: false,
        canChoose: true,
      );

  @override
  Future<ExportLocation?> chooseLocation() async => null;

  @override
  Future<ExportLocation> resetLocation() => location();

  @override
  Future<String?> latestBackupPath() async => latest;

  @override
  Future<ExportSaveResult> save(List<ExportFile> files) async =>
      ExportSaveResult(savedCount: files.length, fileCount: files.length);
}

class _Prepared extends PreparedSleepBackup {
  _Prepared(SleepBackup backup) : super(backup, '');

  bool disposed = false;

  @override
  Future<void> dispose() async => disposed = true;
}

class _Service extends SleepBackupService {
  _Service(AppDatabase superDatabase, this.prepared)
      : super(
          database: superDatabase,
          clips: ClipFileStore(baseDirectory: () async => Directory.systemTemp),
        );

  final _Prepared prepared;
  String? error;
  String? preparedPath;
  int restores = 0;

  @override
  Future<PreparedSleepBackup> prepare(String filePath) async {
    if (error != null) throw FormatException(error!);
    preparedPath = filePath;
    return prepared;
  }

  @override
  Future<BackupImportResult> restore(PreparedSleepBackup prepared) async {
    restores++;
    return const BackupImportResult(imported: 1, skipped: 0, audioCount: 0);
  }
}

void main() {
  late AppDatabase database;
  late _Picker picker;
  late _Service service;
  late _Storage storage;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    picker = _Picker();
    storage = _Storage();
    final now = DateTime.utc(2026, 10, 21, 8);
    service = _Service(
        database,
        _Prepared(SleepBackup(
          audioPaths: {},
          entries: [
            SleepEntry(
              id: 'night',
              startAtUtc: now.subtract(const Duration(hours: 8)),
              endAtUtc: now,
              timeZoneId: 'UTC',
              quality: null,
              createdAtUtc: now,
              updatedAtUtc: now,
              soundClips: [
                SoundClip(
                  id: 'clip',
                  kind: SoundEventKind.snore,
                  startedAtUtc: now,
                  durationMs: 1000,
                ),
              ],
            ),
          ],
        )));
  });

  tearDown(() => database.close());

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        backupFilePickerProvider.overrideWithValue(picker),
        exportStorageProvider.overrideWithValue(storage),
        sleepBackupServiceProvider.overrideWithValue(service),
        sleepEntriesProvider.overrideWith((ref) async => []),
      ],
      child:
          MaterialApp(theme: AppTheme.light(), home: const BackupRestorePage()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('先预览并提示缺失音频，确认后才恢复并显示结果', (tester) async {
    await pumpPage(tester);
    expect(find.text('从备份恢复'), findsOneWidget);
    expect(find.text('小米手环'), findsNothing);
    expect(find.text('下载/夜深'), findsOneWidget);
    await tester.tap(find.text('换一份'));
    await tester.pumpAndSettle();
    expect(find.text('备份内容'), findsOneWidget);
    expect(find.textContaining('1 个声音事件没有录音文件'), findsOneWidget);
    expect(service.restores, 0);
    await tester.ensureVisible(find.text('确认恢复'));
    await tester.tap(find.text('确认恢复'));
    await tester.pumpAndSettle();
    expect(service.restores, 1);
    expect(find.textContaining('已恢复 1 条记录、0 段录音'), findsOneWidget);
    expect(service.prepared.disposed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('取消选文件无报错且不导入', (tester) async {
    picker.result = null;
    await pumpPage(tester);
    await tester.tap(find.text('换一份'));
    await tester.pumpAndSettle();
    expect(service.restores, 0);
    expect(find.text('确认恢复'), findsNothing);
    expect(find.textContaining('无法读取'), findsNothing);
  });

  testWidgets('坏文件页内报错且不出现确认恢复', (tester) async {
    service.error = '备份缺少录音文件';
    await pumpPage(tester);
    await tester.tap(find.text('换一份'));
    await tester.pumpAndSettle();
    expect(find.text('备份缺少录音文件'), findsOneWidget);
    expect(find.text('确认恢复'), findsNothing);
    expect(service.restores, 0);
  });

  testWidgets('默认位置有备份时直接读取最新一份', (tester) async {
    storage.latest = '/cache/latest.zip';
    await pumpPage(tester);

    await tester.tap(find.text('读取备份'));
    await tester.pumpAndSettle();

    expect(find.text('备份内容'), findsOneWidget);
    expect(service.preparedPath, '/cache/latest.zip');
    expect(picker.result, 'backup.zip', reason: '不应退回手动选择文件');
  });

  testWidgets('默认位置没有备份时如实说明', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.text('读取备份'));
    await tester.pumpAndSettle();

    expect(find.text('默认位置还没有可导入的 ZIP 或 JSON 备份。'), findsOneWidget);
    expect(find.text('确认恢复'), findsNothing);
  });
}
