import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/core/database/app_database.dart' show AppDatabase;
import 'package:night_sleep/core/theme/app_theme.dart';
import 'package:night_sleep/features/settings/data/sleep_backup_service.dart';
import 'package:night_sleep/features/settings/domain/sleep_backup.dart';
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
  int restores = 0;

  @override
  Future<PreparedSleepBackup> prepare(String filePath) async {
    if (error != null) throw FormatException(error!);
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

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    picker = _Picker();
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
    await tester.tap(find.text('选择备份文件'));
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
    await tester.tap(find.text('选择备份文件'));
    await tester.pumpAndSettle();
    expect(service.restores, 0);
    expect(find.text('确认恢复'), findsNothing);
    expect(find.textContaining('无法读取'), findsNothing);
  });

  testWidgets('坏文件页内报错且不出现确认恢复', (tester) async {
    service.error = '备份缺少录音文件';
    await pumpPage(tester);
    await tester.tap(find.text('选择备份文件'));
    await tester.pumpAndSettle();
    expect(find.text('备份缺少录音文件'), findsOneWidget);
    expect(find.text('确认恢复'), findsNothing);
    expect(service.restores, 0);
  });
}
