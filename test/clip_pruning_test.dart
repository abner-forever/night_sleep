import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/core/database/app_database.dart';
import 'package:night_sleep/features/sleep/data/clip_pruning.dart';
import 'package:night_sleep/features/sleep/data/clip_store.dart';
import 'package:night_sleep/features/sleep/data/session_repository.dart';
import 'package:night_sleep/features/sleep/domain/clip_journal.dart';

void main() {
  late AppDatabase database;
  late Directory tempDir;
  late ClipFileStore files;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    tempDir = await Directory.systemTemp.createTemp('clip_pruning');
    files = ClipFileStore(baseDirectory: () async => tempDir);
  });

  tearDown(() async {
    await database.close();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  /// 造一晚：一条记录 + 一个带文件的片段。`wakeDay` 是**用户醒来**那天，
  /// 也就是保留期限归档用的那个口径。
  Future<String> addNight({
    required String recordId,
    required DateTime wakeDay,
    String clipId = 'clip',
    String source = 'recording',
  }) async {
    final wake = DateTime(wakeDay.year, wakeDay.month, wakeDay.day, 7);
    await database.saveRecord(
      SleepRecordsCompanion.insert(
        id: recordId,
        startAtUtc: wake.subtract(const Duration(hours: 8)).toUtc(),
        endAtUtc: wake.toUtc(),
        createdAt: wake.toUtc(),
        updatedAt: wake.toUtc(),
        source: Value(source),
      ),
    );
    final path = await files.pathFor(clipId);
    await File(path).writeAsBytes(List<int>.filled(64, 0));
    await database.insertClips([
      SoundClipsCompanion.insert(
        id: clipId,
        recordId: recordId,
        kind: 'noise',
        startedAtUtc: wake.subtract(const Duration(hours: 5)).toUtc(),
        durationMs: 3000,
        localUri: Value(path),
        source: Value(source),
      ),
    ]);
    return path;
  }

  group('保留最近 7 晚', () {
    test('第 8 晚一到，最旧那晚的文件删掉、行留着、文件指针清空', () async {
      final paths = <String>[];
      for (var day = 1; day <= 8; day++) {
        paths.add(await addNight(
          recordId: 'r$day',
          wakeDay: DateTime(2026, 9, day),
          clipId: 'clip-$day',
        ));
      }

      final removed =
          await pruneExpiredRecordings(database: database, files: files);

      expect(removed, 1);
      expect(File(paths.first).existsSync(), isFalse,
          reason: '第 8 晚到了，最旧那晚的文件该删');
      expect(File(paths.last).existsSync(), isTrue, reason: '最近那晚必须留着');

      final clips = await database.allRecordingClips();
      expect(clips, hasLength(8), reason: '事件记录行一条都不许少');
      final oldest = clips.firstWhere((clip) => clip.id == 'clip-1');
      expect(oldest.localUri, isNull, reason: '文件没了就如实置空');
    });

    test('只有 7 晚时什么都不清', () async {
      final paths = <String>[];
      for (var day = 1; day <= 7; day++) {
        paths.add(await addNight(
          recordId: 'r$day',
          wakeDay: DateTime(2026, 9, day),
          clipId: 'clip-$day',
        ));
      }

      final removed =
          await pruneExpiredRecordings(database: database, files: files);

      expect(removed, 0);
      expect(paths.every((path) => File(path).existsSync()), isTrue);
    });

    test('演示片段不在清理范围里，哪怕它是最旧的一晚', () async {
      // 演示片段的时间落在 2020 年，远早于任何真实录音。
      final demoPath = await addNight(
        recordId: 'demo-1',
        wakeDay: DateTime(2020, 1, 1),
        clipId: 'demo-clip',
        source: 'demo',
      );
      for (var day = 1; day <= 8; day++) {
        await addNight(
          recordId: 'r$day',
          wakeDay: DateTime(2026, 9, day),
          clipId: 'clip-$day',
        );
      }

      await pruneExpiredRecordings(database: database, files: files);

      // 演示数据随它自己那套清除逻辑走（`deleteDemoData`），这里一根手指都不碰。
      expect(File(demoPath).existsSync(), isTrue);
    });
  });

  group('孤儿文件', () {
    test('既不在库里、也不在当前会话清单里的文件被删掉', () async {
      final orphan = await files.pathFor('clip-nobody');
      await File(orphan).writeAsBytes(List<int>.filled(64, 0));
      await addNight(
        recordId: 'r1',
        wakeDay: DateTime(2026, 9, 1),
        clipId: 'clip-known',
      );

      await deleteOrphanRecordings(database: database, files: files);

      expect(File(orphan).existsSync(), isFalse);
      expect(File(await files.pathFor('clip-known')).existsSync(), isTrue);
    });

    test('当前会话还没入库的片段不算孤儿', () async {
      // 进程被杀重启的现场：片段已经落盘、清单记在会话行里，但记录行还没写。
      final path = await files.pathFor('clip-pending');
      await File(path).writeAsBytes(List<int>.filled(64, 0));
      final repo = SessionRepository(database);
      await repo.start(now: DateTime.utc(2026, 10, 3, 22), wakeMinutes: 420);
      await repo.update(clipJournal: [
        ClipDraft(
          id: 'clip-pending',
          startedAtUtc: DateTime.utc(2026, 10, 4, 1),
          durationMs: 3000,
          localUri: path,
        ),
      ]);

      await deleteOrphanRecordings(database: database, files: files);

      // 变异验证：把 `pendingIds` 那一项去掉，这里立刻变红——而那就等于把
      // 用户被系统杀掉那一晚的录音当垃圾扫了。
      expect(File(path).existsSync(), isTrue);
    });
  });
}
