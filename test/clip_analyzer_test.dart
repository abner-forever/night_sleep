// `ClipAnalyzer` 的端到端测试：真写临时 WAV 文件、真读回来、真落库。
//
// 信号照旧在测试里合成（本仓不提交二进制音频 fixture）。这里钉的是**管线**：
// 文件读得对不对、写回的列对不对、以及**它绝不碰它不该碰的那几列**。

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/core/database/app_database.dart';
import 'package:night_sleep/features/sleep/data/clip_analyzer.dart';
import 'package:night_sleep/features/sleep/data/wav_file.dart';
import 'package:night_sleep/features/sleep/domain/clip_analysis.dart';

const int _rate = 16000;

/// 合成一段「低频多谐波音」——特征上就是鼾声的样子。
///
/// **默认 3 秒而不是 2 秒**：判定现在带时长门槛，2 秒够不着它，会被判成弃权。
/// **谐波要铺得够多**：只取两三个等幅谐波合成出来的东西更接近**乐音**，
/// 会被 `snoreMaxPeakShare` 判掉——那是哼歌的特征，不是鼾声的
/// （见 `clip_analysis_test.dart` 里 `_snoreTone` 的注释）。
Uint8List _snoreWav({int ms = 3000}) {
  const weights = [
    1.0,
    1.0,
    0.9,
    0.8,
    0.7,
    0.6,
    0.5,
    0.4,
    0.3,
    0.25,
    0.2,
    0.15
  ];
  final n = _rate * ms ~/ 1000;
  final pcm = Int16List(n);
  var norm = 0.0;
  for (final w in weights) {
    norm += w;
  }
  for (var i = 0; i < n; i++) {
    final t = i / _rate;
    var sum = 0.0;
    for (var k = 0; k < weights.length; k++) {
      sum += weights[k] * math.sin(2 * math.pi * 60 * (k + 1) * t);
    }
    pcm[i] = (sum / norm * 0.5 * 32767).round();
  }
  final bytes = Uint8List(pcm.length * 2);
  final view = ByteData.view(bytes.buffer);
  for (var i = 0; i < pcm.length; i++) {
    view.setInt16(i * 2, pcm[i], Endian.little);
  }
  return Uint8List.fromList([
    ...pcm16WavHeader(
      sampleRate: _rate,
      channels: 1,
      dataBytes: bytes.length,
    ),
    ...bytes,
  ]);
}

/// 白噪声：既不像鼾声也不像人声。机器**应当弃权**——认不出来不等于「它是杂音」。
Uint8List _noiseWav({int ms = 2000}) {
  final rng = math.Random(3);
  final n = _rate * ms ~/ 1000;
  final bytes = Uint8List(n * 2);
  final view = ByteData.view(bytes.buffer);
  for (var i = 0; i < n; i++) {
    view.setInt16(i * 2, ((rng.nextDouble() * 2 - 1) * 0.3 * 32767).round(),
        Endian.little);
  }
  return Uint8List.fromList([
    ...pcm16WavHeader(sampleRate: _rate, channels: 1, dataBytes: bytes.length),
    ...bytes,
  ]);
}

void main() {
  late AppDatabase database;
  late Directory tempDir;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    tempDir = Directory.systemTemp.createTempSync('clip-analyzer-test');
  });

  tearDown(() async {
    await database.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<void> seedRecord() async {
    await database.saveRecord(
      SleepRecordsCompanion.insert(
        id: 'rec-1',
        startAtUtc: DateTime.utc(2026, 10, 13, 22),
        endAtUtc: DateTime.utc(2026, 10, 14, 6),
        createdAt: DateTime.utc(2026, 10, 13, 22),
        updatedAt: DateTime.utc(2026, 10, 13, 22),
      ),
    );
  }

  Future<String> writeClip(String id, Uint8List wav) async {
    final path = '${tempDir.path}/$id.wav';
    await File(path).writeAsBytes(wav);
    return path;
  }

  Future<void> seedClip(
    String id, {
    String? localUri,
    String kind = 'noise',
    String source = 'recording',
    String status = 'pending',
  }) async {
    await database.insertClips([
      SoundClipsCompanion.insert(
        id: id,
        recordId: 'rec-1',
        kind: kind,
        startedAtUtc: DateTime.utc(2026, 10, 14, 1),
        durationMs: 2000,
        localUri: Value(localUri),
        source: Value(source),
        analysisStatus: Value(status),
      ),
    ]);
  }

  ClipAnalyzer analyzerAt(DateTime now) =>
      ClipAnalyzer(database, clock: () => now);

  test('把片段判出来并落库，卡片的依据串也一起存下', () async {
    await seedRecord();
    final path = await writeClip('c-1', _snoreWav());
    await seedClip('c-1', localUri: path);

    final written =
        await analyzerAt(DateTime.utc(2026, 10, 14, 8)).analyseRecord('rec-1');
    expect(written, 1);

    final row = (await database.allRecordingClips()).single;
    final record = AutoAnalysis.decode(row.autoAnalysis);
    expect(record, isNotNull);
    expect(record!.verdict?.label, AutoLabel.snore);
    expect(record.verdict?.basis, contains('低频能量'));
    expect(record.analyzedAtUtc, DateTime.utc(2026, 10, 14, 8));
    expect(row.analysisStatus, 'analysed');
  });

  test('机器判断绝不碰 kind、transcript 与 labeled_at_utc', () async {
    // 这三列各有主人：`kind` 是人标的，`transcript` 是转写的（本轮不做），
    // `labeled_at_utc` 是人的动作。机器写回时碰了任何一列，界面三态立刻失真。
    await seedRecord();
    final path = await writeClip('c-1', _snoreWav());
    await seedClip('c-1', localUri: path);

    await analyzerAt(DateTime.utc(2026, 10, 14, 8)).analyseRecord('rec-1');

    final row = (await database.allRecordingClips()).single;
    expect(row.kind, 'noise', reason: 'kind 是人的位置，机器不许写');
    expect(row.transcript, isNull, reason: '本轮不做转写，这一列必须一直是空的');
    expect(row.labeledAtUtc, isNull, reason: '机器判断不是一次人工标注');
  });

  test('用户已经标过的那一段，机器照样只写自己那一列', () async {
    await seedRecord();
    final path = await writeClip('c-1', _snoreWav());
    await seedClip('c-1', localUri: path, kind: 'talk');
    await database.updateClipLabel(
      'c-1',
      kind: 'talk',
      labeledAtUtc: DateTime.utc(2026, 10, 14, 7),
    );

    await analyzerAt(DateTime.utc(2026, 10, 14, 8)).analyseRecord('rec-1');

    final row = (await database.allRecordingClips()).single;
    expect(row.kind, 'talk', reason: '人标的那个词不许被机器改掉');
    // drift 在原生执行器上按 unix 秒存，读回来的是**标记为本地时区**的 DateTime
    // ——与 `schema_migration_test.dart` 里记的是同一条，比之前先 toUtc()。
    expect(row.labeledAtUtc!.toUtc(), DateTime.utc(2026, 10, 14, 7));
    expect(row.autoAnalysis, isNotNull, reason: '机器当初看到的是什么，值得留下');
  });

  test('判不出来时也落库——「看过但弃权」与「没看过」必须分得开', () async {
    await seedRecord();
    // 1.1 秒的低频周期瞬态：三条阈值都过、余量也够，**只是太短**。
    // 这正是机器该闭嘴的那种片段——它看见了像鼾声的东西，但拿不准。
    final path = await writeClip('c-1', _snoreWav(ms: 1100));
    await seedClip('c-1', localUri: path);

    await analyzerAt(DateTime.utc(2026, 10, 14, 8)).analyseRecord('rec-1');

    final row = (await database.allRecordingClips()).single;
    final record = AutoAnalysis.decode(row.autoAnalysis);
    expect(record, isNotNull, reason: '机器确实看过了，这件事要留下痕迹');
    expect(record!.verdict, isNull, reason: '弃权 = 没有判断，不是「杂音」');
    expect(row.analysisStatus, 'analysed');
  });

  test('机器判不出来的片段同样弃权，不落「杂音」——`kind` 一个字节都没动', () async {
    await seedRecord();
    // 宽带白噪：机器认不出它是什么。**「认不出」不等于「它是杂音」**——报杂音等于
    // 同时断言「不是鼾声」和「不是人声」，而机器没有资格下这两个否定结论。
    final path = await writeClip('c-1', _noiseWav(ms: 3000));
    await seedClip('c-1', localUri: path);

    await analyzerAt(DateTime.utc(2026, 10, 14, 8)).analyseRecord('rec-1');

    final row = (await database.allRecordingClips()).single;
    final record = AutoAnalysis.decode(row.autoAnalysis);
    expect(record, isNotNull, reason: '机器看过了，这件事要留下痕迹');
    expect(record!.verdict, isNull, reason: '判不出来就留「待标注」');
    // **`kind` 仍然一个字节都没动**：机器判断写在 `auto_analysis` 里，
    // 从来不是替用户把 `kind` 填上。
    expect(row.kind, 'noise',
        reason: '这是 `session_repository` 落库时写的中性占位值，不是机器的判断');
    expect(row.labeledAtUtc, isNull, reason: '没人标过它，界面该显示「待标注」');
  });

  test('文件读不动记 failed，不抛异常、不连累别的片段', () async {
    await seedRecord();
    final good = await writeClip('c-good', _snoreWav());
    await seedClip('c-good', localUri: good);
    await seedClip('c-missing', localUri: '${tempDir.path}/根本没有.wav');

    final written =
        await analyzerAt(DateTime.utc(2026, 10, 14, 8)).analyseRecord('rec-1');
    expect(written, 1, reason: '只有那一段真的写完了');

    final rows = await database.allRecordingClips();
    final missing = rows.firstWhere((r) => r.id == 'c-missing');
    final ok = rows.firstWhere((r) => r.id == 'c-good');
    expect(missing.analysisStatus, 'failed');
    expect(missing.autoAnalysis, isNull);
    expect(ok.analysisStatus, 'analysed');
    expect(ok.autoAnalysis, isNotNull);
  });

  test('不是 WAV 的垃圾文件也走 failed，不抛', () async {
    await seedRecord();
    final path = '${tempDir.path}/c-1.wav';
    await File(path).writeAsBytes(Uint8List.fromList(List.filled(200, 7)));
    await seedClip('c-1', localUri: path);

    await analyzerAt(DateTime.utc(2026, 10, 14, 8)).analyseRecord('rec-1');

    final row = (await database.allRecordingClips()).single;
    expect(row.analysisStatus, 'failed');
  });

  test('没有文件路径的片段（音频已被裁掉）直接跳过，不记 failed', () async {
    // 这是**已知的真相**，不是失败：保留期限清掉音频后 `localUri` 就是空的，
    // 那一行仍然该显示「这段录音未保留在本地」，而不是「分析失败」。
    await seedRecord();
    await seedClip('c-1');

    final written =
        await analyzerAt(DateTime.utc(2026, 10, 14, 8)).analyseRecord('rec-1');
    expect(written, 0);

    final row = (await database.allRecordingClips()).single;
    expect(row.analysisStatus, 'pending', reason: '没原料不算分析过');
    expect(row.autoAnalysis, isNull);
  });

  group('冷启动补跑', () {
    test('只捡还没分析过、且有文件的真实片段', () async {
      await seedRecord();
      final path = await writeClip('c-1', _snoreWav());
      await seedClip('c-1', localUri: path);
      // 已经分析过的：不该重算。
      await seedClip('c-done', localUri: path, status: 'analysed');
      // 演示数据：它的 kind / labeledAtUtc 本来就是示例数据本身的一部分。
      await seedClip('c-demo', source: 'demo', kind: 'snore');
      // 没有文件的：没有原料。
      await seedClip('c-nofile');

      final written =
          await analyzerAt(DateTime.utc(2026, 10, 14, 8)).analysePending();

      expect(written, 1, reason: '只该捡起 c-1 那一段');
      // 用 `allClipsByRecord` 而不是 `allRecordingClips`：后者按定义只看
      // `source = 'recording'`，演示那行根本不在里面，断言会假绿。
      final all = (await database.allClipsByRecord())['rec-1']!;
      final demo = all.firstWhere((r) => r.id == 'c-demo');
      expect(demo.autoAnalysis, isNull, reason: '演示数据不该被补上机器判断');
    });
  });
}
