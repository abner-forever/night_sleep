import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/core/database/app_database.dart' as db;
import 'package:night_sleep/features/settings/data/sleep_backup_service.dart';
import 'package:night_sleep/features/settings/domain/sleep_backup.dart';
import 'package:night_sleep/features/settings/domain/sleep_export.dart';
import 'package:night_sleep/features/sleep/data/clip_store.dart';
import 'package:night_sleep/features/sleep/data/sleep_repository.dart';
import 'package:night_sleep/features/sleep/domain/clip_analysis.dart';
import 'package:night_sleep/features/sleep/domain/sleep_entry.dart';
import 'package:night_sleep/features/sleep/domain/sleep_insight.dart';
import 'package:night_sleep/features/sleep/domain/sleep_score.dart';
import 'package:night_sleep/features/sleep/domain/sleep_stage.dart';
import 'package:night_sleep/features/sleep/domain/sound_event.dart';

class _FailingClipStore extends ClipFileStore {
  _FailingClipStore(Directory directory)
      : super(baseDirectory: () async => directory);

  int _calls = 0;

  @override
  Future<String> pathFor(String clipId) async {
    if (++_calls == 2) throw const FileSystemException('disk full');
    return super.pathFor(clipId);
  }
}

void main() {
  late Directory directory;
  late db.AppDatabase database;
  late SleepBackupService service;
  late ClipFileStore clips;
  final now = DateTime.utc(2026, 10, 21, 8);
  final audioBytes = utf8.encode('RIFF test audio bytes');

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('sleep-backup-test-');
    database = db.AppDatabase(NativeDatabase.memory());
    clips = ClipFileStore(baseDirectory: () async => directory);
    service = SleepBackupService(
      database: database,
      clips: clips,
      temporaryDirectory: () async => directory,
    );
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  Future<SleepEntry> entry({String id = 'night', int audioCount = 1}) async {
    final soundClips = <SoundClip>[];
    for (var index = 0; index < audioCount; index++) {
      final file = File('${directory.path}/original-$id-$index.wav');
      await file.writeAsBytes(audioBytes);
      soundClips.add(SoundClip(
        id: '$id-clip-$index',
        kind: SoundEventKind.talk,
        startedAtUtc: now.subtract(const Duration(hours: 2)),
        durationMs: 4200,
        localUri: file.path,
        transcript: '睡得很好',
        analysis: '真实分析',
        source: 'recording',
        analysisStatus: SoundAnalysisStatus.analysed,
        waveformEnvelope: const [0.1, 0.4, 1.0],
        labeledAtUtc: now,
        autoAnalysis: AutoAnalysis(
          verdict: const AutoVerdict(
            label: AutoLabel.voice,
            margin: 0.8,
            basis: 'YAMNet',
          ),
          analyzedAtUtc: now,
        ),
      ));
    }
    return SleepEntry(
      id: id,
      startAtUtc: now.subtract(const Duration(hours: 8)),
      endAtUtc: now,
      timeZoneId: 'Asia/Shanghai',
      quality: null,
      source: 'session',
      notes: '一条真实记录',
      tags: const ['tag'],
      loggedEvents: const LoggedEvents(snore: true),
      stages: [
        SleepStageSegment(
          stage: SleepStageType.deep,
          startAtUtc: now.subtract(const Duration(hours: 8)),
          endAtUtc: now.subtract(const Duration(hours: 7)),
        ),
      ],
      soundClips: soundClips,
      insight: Insight(
        id: '$id-insight',
        recordId: id,
        content: '真实洞察',
        provider: 'provider',
        model: 'model',
        score: 81,
        generatedAtUtc: now,
        status: InsightStatus.ok,
      ),
      createdAtUtc: now,
      updatedAtUtc: now,
    );
  }

  Future<PreparedSleepBackup> prepareZip(List<SleepEntry> entries) async {
    final exported = await service.export(entries, now: now);
    return service.prepare(exported.file.localPath!);
  }

  test('完整备份跨目录恢复音频、阶段、标注、波形和洞察，重复恢复保留本机版本', () async {
    final original = await entry();
    final exported = await service.export([original], now: now);
    expect(exported.missingAudioCount, 0);
    final prepared = await service.prepare(exported.file.localPath!);
    expect(prepared.backup.audioPaths, hasLength(1));
    await File(original.soundClips.single.localUri!).delete();

    final result = await service.restore(prepared);
    expect(result.imported, 1);
    expect(result.audioCount, 1);
    final restored = (await SleepRepository(database).loadAll()).single;
    expect(restored.quality, isNull);
    expect(restored.startAtUtc.toUtc(), original.startAtUtc.toUtc());
    expect(restored.timeZoneId, original.timeZoneId);
    expect(restored.createdAtUtc.toUtc(), original.createdAtUtc.toUtc());
    expect(restored.notes, original.notes);
    expect(restored.tags, original.tags);
    expect(restored.loggedEvents.snore, isTrue);
    expect(restored.stages.single.stage, SleepStageType.deep);
    expect(restored.insight!.content, '真实洞察');
    expect(restored.insight!.score, 81);
    final clip = restored.soundClips.single;
    expect(clip.localUri, isNot(original.soundClips.single.localUri));
    expect(await File(clip.localUri!).readAsBytes(), audioBytes);
    expect(clip.waveformEnvelope, [0.1, 0.4, 1.0]);
    expect(clip.labeledAtUtc, now);
    expect(clip.transcript, '睡得很好');
    expect(clip.autoAnalysis!.verdict!.label, AutoLabel.voice);
    await (database.update(database.sleepRecords)
          ..where((table) => table.id.equals('night')))
        .write(const db.SleepRecordsCompanion(notes: Value('本机修改')));
    final duplicate = await service.restore(prepared);
    expect(duplicate.imported, 0);
    expect(duplicate.skipped, 1);
    expect(duplicate.audioCount, 0);
    expect((await database.findRecord('night'))!.notes, '本机修改');
    expect((await database.clipsFor('night')).single.localUri, clip.localUri);
    await prepared.dispose();
  });

  test('旧 JSON 可恢复记录与事件，忽略设备路径且没有伪造可回放音频', () async {
    final original = await entry();
    final document =
        jsonDecode(SleepExporter.json([original], now: now).single.content)
            as Map<String, dynamic>;
    document['schemaVersion'] = 2;
    final clip =
        document['records'][0]['soundClips'][0] as Map<String, dynamic>;
    clip.remove('autoAnalysis');
    clip.remove('waveformEnvelope');
    clip.remove('labeledAtUtc');
    clip['localUri'] = '/private/another-device/file.wav';
    final file = File('${directory.path}/old.json');
    await file.writeAsString(jsonEncode(document));
    final prepared = await service.prepare(file.path);
    expect(prepared.backup.audioPaths, isEmpty);
    final result = await service.restore(prepared);
    expect(result.audioCount, 0);
    final restored = (await SleepRepository(database).loadAll()).single;
    expect(restored.soundClips.single.localUri, isNull);
    expect(restored.soundClips.single.autoAnalysis, isNull);
    await prepared.dispose();
  });

  test('缺失录音如实计数，声音事件仍然可以恢复', () async {
    final original = await entry();
    await File(original.soundClips.single.localUri!).delete();
    final exported = await service.export([original], now: now);
    expect(exported.missingAudioCount, 1);
    final prepared = await service.prepare(exported.file.localPath!);
    expect(prepared.backup.clipCount, 1);
    expect(prepared.backup.audioPaths, isEmpty);
    await service.restore(prepared);
    expect((await database.clipsFor('night')).single.localUri, isNull);
    await prepared.dispose();
  });

  test('音频写入失败回滚所有记录并清理已经复制的录音', () async {
    final prepared = await prepareZip([await entry(audioCount: 2)]);
    final failing = SleepBackupService(
      database: database,
      clips: _FailingClipStore(directory),
      temporaryDirectory: () async => directory,
    );
    await expectLater(
        failing.restore(prepared), throwsA(isA<FileSystemException>()));
    expect(await database.allRecords(), isEmpty);
    expect(await database.clipsFor('night'), isEmpty);
    expect(await clips.totalBytes(), 0);
    await prepared.dispose();
  });

  test('当前睡眠进行中不恢复', () async {
    final prepared = await prepareZip([await entry()]);
    await database.into(database.activeSessions).insert(
          db.ActiveSessionsCompanion.insert(
            id: 'active',
            startAtUtc: now,
            wakeMinutes: 480,
            createdAt: now,
          ),
        );
    await expectLater(service.restore(prepared), throwsStateError);
    expect(await database.allRecords(), isEmpty);
    await prepared.dispose();
  });

  test('损坏字段、未来版本和重复记录在写入前拒绝', () async {
    final original = await entry();
    Map<String, dynamic> document() =>
        jsonDecode(SleepExporter.json([original], now: now).single.content)
            as Map<String, dynamic>;
    final future = document()..['version'] = 999;
    final futureSchema = document()..['schemaVersion'] = 999;
    final invalid = document();
    invalid['records'][0]['quality'] = 100;
    final duplicate = document();
    duplicate['records'].add(duplicate['records'][0]);
    duplicate['recordCount'] = 2;
    for (final data in [future, futureSchema, invalid, duplicate]) {
      expect(() => SleepBackup.parse(jsonEncode(data), withAudio: false),
          throwsFormatException);
    }
    expect(await database.allRecords(), isEmpty);
  });

  test('缺少音频、路径越界和校验损坏的 ZIP 在写入前拒绝', () async {
    final original = await entry();
    final document =
        jsonDecode(SleepExporter.json([original], now: now).single.content)
            as Map<String, dynamic>;
    document['format'] = 'night-sleep-backup';
    document['records'][0]['soundClips'][0]['audioPath'] = 'audio/0.wav';
    Future<void> rejects(Archive archive) async {
      final file = File('${directory.path}/bad.zip');
      await file.writeAsBytes(ZipEncoder().encode(archive));
      await expectLater(service.prepare(file.path), throwsFormatException);
      expect(await database.allRecords(), isEmpty);
    }

    await rejects(Archive()
      ..add(ArchiveFile.string('manifest.json', jsonEncode(document))));
    await rejects(Archive()
      ..add(ArchiveFile.string('manifest.json', jsonEncode(document)))
      ..add(ArchiveFile.string('../escaped.wav', 'bad')));
    final zip = ZipEncoder().encode(
        Archive()
          ..add(ArchiveFile.string('manifest.json', jsonEncode(document)))
          ..add(ArchiveFile('audio/0.wav', audioBytes.length, audioBytes)),
        level: 0);
    final offset = _indexOf(zip, audioBytes);
    expect(offset, greaterThan(0));
    zip[offset] ^= 1;
    final corrupt = File('${directory.path}/corrupt.zip');
    await corrupt.writeAsBytes(zip);
    await expectLater(service.prepare(corrupt.path), throwsFormatException);
  });
}

int _indexOf(List<int> bytes, List<int> needle) {
  for (var offset = 0; offset <= bytes.length - needle.length; offset++) {
    var matches = true;
    for (var index = 0; index < needle.length; index++) {
      if (bytes[offset + index] != needle[index]) {
        matches = false;
        break;
      }
    }
    if (matches) return offset;
  }
  return -1;
}
