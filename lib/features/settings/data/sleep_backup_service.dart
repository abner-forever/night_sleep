import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:archive/archive_io.dart';
import 'package:drift/drift.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../../core/database/app_database.dart' as db;
import '../../sleep/data/clip_store.dart';
import '../../sleep/domain/sleep_entry.dart';
import '../domain/sleep_backup.dart';
import '../domain/sleep_export.dart';

class BackupExport {
  const BackupExport(this.file, {required this.missingAudioCount});

  final ExportFile file;
  final int missingAudioCount;
}

class PreparedSleepBackup {
  const PreparedSleepBackup(this.backup, this.directory);

  final SleepBackup backup;
  final String directory;

  Future<void> dispose() async {
    final staging = Directory(directory);
    if (await staging.exists()) await staging.delete(recursive: true);
  }
}

class BackupImportResult {
  const BackupImportResult({
    required this.imported,
    required this.skipped,
    required this.audioCount,
  });

  final int imported;
  final int skipped;
  final int audioCount;
}

abstract interface class BackupFilePicker {
  Future<String?> pick();
}

class SystemBackupFilePicker implements BackupFilePicker {
  const SystemBackupFilePicker();

  @override
  Future<String?> pick() async {
    final file = await openFile(acceptedTypeGroups: const [
      XTypeGroup(
        label: '夜深备份',
        extensions: ['zip', 'json'],
        uniformTypeIdentifiers: ['public.zip-archive', 'public.json'],
      ),
    ]);
    return file?.path;
  }
}

class SleepBackupService {
  SleepBackupService({
    required this.database,
    required this.clips,
    Future<Directory> Function()? temporaryDirectory,
  }) : _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory;

  final db.AppDatabase database;
  final ClipFileStore clips;
  final Future<Directory> Function() _temporaryDirectory;

  Future<BackupExport> export(List<SleepEntry> entries,
      {required DateTime now}) async {
    final root = await _temporaryDirectory();
    final directory =
        await Directory(path.join(root.path, 'export')).create(recursive: true);
    final output = await directory.createTemp('backup-');
    return Isolate.run(() => _writeArchive(entries, now, output.path));
  }

  Future<PreparedSleepBackup> prepare(String filePath) async {
    final root = await _temporaryDirectory();
    final directory = await root.createTemp('sleep-import-');
    try {
      return await Isolate.run(() => _prepare(filePath, directory.path));
    } catch (_) {
      await directory.delete(recursive: true);
      rethrow;
    }
  }

  Future<BackupImportResult> restore(PreparedSleepBackup prepared) async {
    final written = <File>[];
    var imported = 0;
    var skipped = 0;
    var audioCount = 0;
    final random = Random.secure();
    final token = List.generate(16, (_) => random.nextInt(256))
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    try {
      await database.transaction(() async {
        if (await database.activeSession() != null) {
          throw StateError('请先结束当前睡眠，再恢复备份');
        }
        for (final entry in prepared.backup.entries) {
          if (await database.findRecord(entry.id) != null) {
            skipped++;
            continue;
          }
          await database.saveRecord(db.SleepRecordsCompanion(
            id: Value(entry.id),
            startAtUtc: Value(entry.startAtUtc),
            endAtUtc: Value(entry.endAtUtc),
            timeZoneId: Value(entry.timeZoneId),
            quality: Value(entry.quality?.value),
            notes: Value(entry.notes),
            tagsJson: Value(jsonEncode(entry.tags)),
            source: Value(entry.source),
            flaggedSnore: Value(entry.loggedEvents.snore),
            flaggedTalk: Value(entry.loggedEvents.talk),
            flaggedRestless: Value(entry.loggedEvents.restless),
            flaggedNightmare: Value(entry.loggedEvents.nightmare),
            createdAt: Value(entry.createdAtUtc),
            updatedAt: Value(entry.updatedAtUtc),
          ));
          await database.replaceStages(entry.id, [
            for (var index = 0; index < entry.stages.length; index++)
              db.SleepStageSegmentsCompanion(
                id: Value('restored-$token-$imported-stage-$index'),
                recordId: Value(entry.id),
                stage: Value(entry.stages[index].stage.id),
                startAtUtc: Value(entry.stages[index].startAtUtc),
                endAtUtc: Value(entry.stages[index].endAtUtc),
                source: Value(entry.stages[index].source),
              ),
          ]);
          final clipRows = <db.SoundClipsCompanion>[];
          for (var index = 0; index < entry.soundClips.length; index++) {
            final clip = entry.soundClips[index];
            final clipId = 'restored-$token-$imported-$index';
            final audioPath = prepared.backup.audioPaths[clip.id];
            String? localUri;
            if (audioPath != null) {
              localUri = await clips.pathFor(clipId);
              final target = File(localUri);
              written.add(target);
              await File(path.join(prepared.directory, audioPath))
                  .copy(localUri);
              audioCount++;
            }
            clipRows.add(db.SoundClipsCompanion(
              id: Value(clipId),
              recordId: Value(entry.id),
              kind: Value(clip.kind.id),
              startedAtUtc: Value(clip.startedAtUtc),
              durationMs: Value(clip.durationMs),
              localUri: Value(localUri),
              transcript: Value(clip.transcript),
              analysis: Value(clip.analysis),
              analysisStatus: Value(clip.analysisStatus.id),
              source: const Value('recording'),
              waveformEnvelope: Value(clip.waveformEnvelope == null
                  ? null
                  : jsonEncode(clip.waveformEnvelope)),
              labeledAtUtc: Value(clip.labeledAtUtc),
              autoAnalysis: Value(clip.autoAnalysis?.encode()),
            ));
          }
          await database.insertClips(clipRows);
          final insight = entry.insight;
          if (insight != null) {
            await database.into(database.insights).insert(db.InsightsCompanion(
                  id: Value('restored-$token-$imported-insight'),
                  recordId: Value(entry.id),
                  kind: Value(insight.kind),
                  content: Value(insight.content),
                  provider: Value(insight.provider),
                  model: Value(insight.model),
                  score: Value(insight.score),
                  generatedAtUtc: Value(insight.generatedAtUtc),
                  status: Value(insight.status.id),
                ));
          }
          imported++;
        }
      });
    } catch (_) {
      for (final file in written) {
        await clips.deleteClip(file.path);
      }
      rethrow;
    }
    return BackupImportResult(
        imported: imported, skipped: skipped, audioCount: audioCount);
  }

  static BackupExport _writeArchive(
      List<SleepEntry> entries, DateTime now, String output) {
    final json = SleepExporter.json(entries, now: now).single;
    final document = jsonDecode(json.content) as Map<String, dynamic>;
    document['format'] = 'night-sleep-backup';
    final sourceEntries = SleepExporter.exportableOf(entries);
    final records = document['records'] as List;
    final encoder = ZipFileEncoder();
    final fileName = json.fileName
        .replaceFirst('睡眠数据', '完整备份')
        .replaceFirst('.json', '.zip');
    final target = File(path.join(output, fileName));
    var missing = 0;
    var audioIndex = 0;
    encoder.create(target.path);
    try {
      for (var recordIndex = 0;
          recordIndex < sourceEntries.length;
          recordIndex++) {
        final clips = sourceEntries[recordIndex].soundClips;
        final exportedClips = records[recordIndex]['soundClips'] as List;
        for (var clipIndex = 0; clipIndex < clips.length; clipIndex++) {
          final uri = clips[clipIndex].localUri;
          final file = uri == null ? null : File(uri);
          String? audioPath;
          if (file != null && file.existsSync()) {
            audioPath = 'audio/${audioIndex++}.wav';
            encoder.addFileSync(file, audioPath);
          } else if (uri != null) {
            missing++;
          }
          exportedClips[clipIndex]['audioPath'] = audioPath;
          exportedClips[clipIndex]['hasLocalAudio'] = audioPath != null;
        }
      }
      encoder.addArchiveFile(ArchiveFile.string('manifest.json',
          const JsonEncoder.withIndent('  ').convert(document)));
    } finally {
      encoder.closeSync();
    }
    return BackupExport(
      ExportFile.local(
          fileName: fileName,
          localPath: target.path,
          mimeType: 'application/zip'),
      missingAudioCount: missing,
    );
  }

  static PreparedSleepBackup _prepare(String filePath, String directory) {
    const manifestLimit = 32 * 1024 * 1024;
    const audioLimit = 32 * 1024 * 1024;
    const totalLimit = 2 * 1024 * 1024 * 1024;
    final file = File(filePath);
    if (path.extension(filePath).toLowerCase() == '.json') {
      if (file.lengthSync() > manifestLimit) {
        throw const FormatException('JSON 存档过大');
      }
      final backup = SleepBackup.parse(
          file.readAsStringSync().replaceFirst('\uFEFF', ''),
          withAudio: false);
      return PreparedSleepBackup(backup, directory);
    }
    if (file.lengthSync() > totalLimit) {
      throw const FormatException('备份超过 2 GB，请拆分后重试');
    }
    final input = InputFileStream(filePath);
    try {
      final decoder = ZipDecoder();
      final archive = decoder.decodeStream(input);
      if (decoder.directory.fileHeaders.length != archive.length) {
        throw const FormatException('备份中存在重复文件');
      }
      var total = 0;
      for (final entry in archive) {
        if (!entry.isFile ||
            entry.isSymbolicLink ||
            (entry.name != 'manifest.json' &&
                !RegExp(r'^audio/[0-9]+\.wav$').hasMatch(entry.name)) ||
            entry.size < 0 ||
            entry.size >
                (entry.name == 'manifest.json' ? manifestLimit : audioLimit)) {
          throw const FormatException('备份包含不合法的文件或文件过大');
        }
        total += entry.size;
        if (total > totalLimit) throw const FormatException('备份解压后超过 2 GB');
      }
      final manifest = archive.find('manifest.json');
      if (manifest == null) throw const FormatException('备份缺少数据清单');
      final backup = SleepBackup.parse(utf8.decode(_verifiedBytes(manifest)),
          withAudio: true);
      final expected = {'manifest.json', ...backup.audioPaths.values};
      if (archive.length != expected.length) {
        throw const FormatException('备份文件与数据清单不一致');
      }
      for (final audioPath in backup.audioPaths.values) {
        final entry = archive.find(audioPath);
        if (entry == null) throw const FormatException('备份缺少录音文件');
        final target = File(path.join(directory, audioPath));
        target.parent.createSync(recursive: true);
        target.writeAsBytesSync(_verifiedBytes(entry), flush: true);
      }
      return PreparedSleepBackup(backup, directory);
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('备份损坏或无法读取，请重新选择文件');
    } finally {
      input.closeSync();
    }
  }

  static List<int> _verifiedBytes(ArchiveFile entry) {
    final bytes = entry.readBytes();
    if (bytes == null ||
        bytes.length != entry.size ||
        getCrc32(bytes) != entry.crc32) {
      throw const FormatException('备份校验失败，文件可能已损坏');
    }
    return bytes;
  }
}

final backupFilePickerProvider = Provider<BackupFilePicker>((ref) {
  return const SystemBackupFilePicker();
});

final sleepBackupServiceProvider = Provider<SleepBackupService>((ref) {
  return SleepBackupService(
    database: ref.watch(db.databaseProvider),
    clips: ref.watch(clipFileStoreProvider),
  );
});
