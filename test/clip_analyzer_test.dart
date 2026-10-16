// `ClipAnalyzer` 的端到端测试：真写临时 WAV 文件、真读回来、真落库、**真的起 isolate**。
//
// 信号照旧在测试里合成（本仓不提交二进制音频 fixture）。这里钉的是**管线**：
// 文件读得对不对、写回的列对不对、读不动的时候记什么、以及**它绝不碰它不该碰的那几列**。
//
// ## 模型是假的，别的都是真的
//
// `flutter test` 里没有 TFLite 的原生库，模型根本加载不了。所以这里注入一个**假打分器**
// （[ClipScorer] 的接缝，见 `data/yamnet_scorer.dart`）——**但从批处理进 isolate 那一段
// 开始，走的全是生产路径**：`Isolate.run`、字节的发送、逐段 try/catch、落库。
// 这个文件是全仓唯一验证「跨 isolate 那一跳真的通」的地方，别把 isolate 也换成假的。
//
// **假工厂必须是顶层函数**：它要跟着闭包被送进新 isolate，而顶层变量在新 isolate 里
// 是各自一份——「测试里先改一个变量、isolate 里读它」这条路根本不成立。
// 分数因此写死在每个工厂里，一个工厂一种分数。
//
// ## 合成信号不再代表任何声音
//
// 2026-10-16 之前这里的 `_snoreWav` 合成的是「低频多谐波音」，因为旧规则照声学特征判，
// 信号得像鼾声才判得出来。**判定换成模型之后这层关系断了**：YAMNet 对合成正弦说什么
// 完全未知，而这里也不再需要它说什么——分数是假打分器给的。所以那些生成器现在只是
// 「一段合法的、非静音的 PCM16 WAV」，名字也照实叫。

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/core/database/app_database.dart';
import 'package:night_sleep/features/sleep/data/clip_analyzer.dart';
import 'package:night_sleep/features/sleep/data/wav_file.dart';
import 'package:night_sleep/features/sleep/data/yamnet_scorer.dart';
import 'package:night_sleep/features/sleep/domain/clip_analysis.dart';
import 'package:night_sleep/features/sleep/domain/clip_yamnet.dart';

const int _rate = 16000;

/// 一段有声音的音频：60 Hz 基频的十二个谐波。
///
/// **它不再是「鼾声的样子」**，只是一个响度远高于 −60 dBFS、长度可调的合法波形。
/// 判定归假打分器管，与这段信号像不像鼾声无关。
Float64List _loud({int ms = 3000}) {
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
  final out = Float64List(n);
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
    out[i] = 0.5 * sum / norm;
  }
  return out;
}

/// 数字静音：逐样本全零，就是平台把麦克风收走时交上来的那种东西。
Float64List _silence({int ms = 3000}) => Float64List(_rate * ms ~/ 1000);

/// 白噪声，只是为了「另一段不一样的音频」。
Float64List _noise({int ms = 3000}) {
  final rng = math.Random(3);
  final n = _rate * ms ~/ 1000;
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    out[i] = 0.3 * (rng.nextDouble() * 2 - 1);
  }
  return out;
}

Uint8List _wav(Float64List samples) {
  final bytes = Uint8List(samples.length * 2);
  final view = ByteData.view(bytes.buffer);
  for (var i = 0; i < samples.length; i++) {
    view.setInt16(
        i * 2, (samples[i].clamp(-1.0, 1.0) * 32767).round(), Endian.little);
  }
  return Uint8List.fromList([
    ...pcm16WavHeader(sampleRate: _rate, channels: 1, dataBytes: bytes.length),
    ...bytes,
  ]);
}

/// ── 假打分器 ────────────────────────────────────────────────────────────────
///
/// 每一窗都给同一个分数，于是整段均分就是那个数，判定也就完全可预测。
class _FixedScorer implements ClipScorer {
  _FixedScorer(this.snore, this.speech);

  final double snore;
  final double speech;

  @override
  ClipScores score(Float64List samples, int sampleRate) {
    final windows = yamnetWindowStarts(samples.length).length;
    return ClipScores(
      snore: List<double>.filled(windows, snore),
      speech: List<double>.filled(windows, speech),
    );
  }

  @override
  void dispose() {}
}

/// 一个**一被调用就炸**的打分器：用来证明某条路径上模型根本没被问过。
class _ExplodingScorer implements ClipScorer {
  @override
  ClipScores score(Float64List samples, int sampleRate) =>
      throw StateError('这段音频不该被喂给模型');

  @override
  void dispose() {}
}

ClipScorer _snoreScores(Uint8List _) => _FixedScorer(0.85, 0.02);
ClipScorer _voiceScores(Uint8List _) => _FixedScorer(0.10, 0.80);
ClipScorer _nothingScores(Uint8List _) => _FixedScorer(0.05, 0.01);
ClipScorer _exploding(Uint8List _) => _ExplodingScorer();

/// 造一个打分器失败——模型在 isolate 里建不起来（原生库打不开之类）。
ClipScorer _cannotBuild(Uint8List _) => throw StateError('原生库打不开');

/// 模型字节。**给的是垃圾**：假打分器不看它。
Uint8List _modelBytes() => Uint8List.fromList(List.filled(64, 7));

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
        durationMs: 3000,
        localUri: Value(localUri),
        source: Value(source),
        analysisStatus: Value(status),
      ),
    ]);
  }

  /// 默认的构建方式：假分数、假模型字节，别的都是真的。
  ClipAnalyzer analyzerAt(
    DateTime now, {
    ClipScorerFactory scorer = _snoreScores,
    Future<Uint8List> Function()? loadModel,
  }) {
    return ClipAnalyzer(
      database,
      scorerFactory: scorer,
      loadModel: loadModel ?? () async => _modelBytes(),
      clock: () => now,
    );
  }

  test('把片段判出来并落库，卡片的依据串也一起存下', () async {
    await seedRecord();
    final path = await writeClip('c-1', _wav(_loud()));
    await seedClip('c-1', localUri: path);

    final settled =
        await analyzerAt(DateTime.utc(2026, 10, 14, 8)).analyseRecord('rec-1');
    expect(settled, 1);

    final row = (await database.allRecordingClips()).single;
    final record = AutoAnalysis.decode(row.autoAnalysis);
    expect(record, isNotNull);
    expect(record!.verdict?.label, AutoLabel.snore);
    // 依据串现在是**模型分**，不是低频占比那一组——模型一个都不用那些数。
    expect(record.verdict?.basis, contains('YAMNet 鼾声分'));
    expect(record.verdict?.basis, isNot(contains('低频能量')));
    // 新判定不带区间：模型按整段给结论，画一对秒数就是没量过的东西。
    expect(record.verdict?.durationMs, 0);
    expect(record.verdict?.event, isNull);
    expect(record.analyzedAtUtc, DateTime.utc(2026, 10, 14, 8));
    expect(row.analysisStatus, 'analysed');
  });

  test('三个标签各走一遍：鼾声 / 人声 / 弃权', () async {
    await seedRecord();
    await seedClip('c-snore', localUri: await writeClip('a', _wav(_loud())));
    await seedClip('c-voice', localUri: await writeClip('b', _wav(_noise())));
    await seedClip('c-quiet', localUri: await writeClip('c', _wav(_loud())));

    // 一段一批地跑，好让每段用不同的假分数。
    await analyzerAt(DateTime.utc(2026, 10, 14, 8), scorer: _snoreScores)
        .analyseRecord('rec-1');
    var rows = await database.allRecordingClips();
    expect(
      AutoAnalysis.decode(
              rows.firstWhere((r) => r.id == 'c-snore').autoAnalysis)
          ?.verdict
          ?.label,
      AutoLabel.snore,
    );

    await analyzerAt(DateTime.utc(2026, 10, 14, 8), scorer: _voiceScores)
        .analyseRecord('rec-1');
    rows = await database.allRecordingClips();
    expect(
      AutoAnalysis.decode(
              rows.firstWhere((r) => r.id == 'c-voice').autoAnalysis)
          ?.verdict
          ?.label,
      AutoLabel.voice,
    );

    await analyzerAt(DateTime.utc(2026, 10, 14, 8), scorer: _nothingScores)
        .analyseRecord('rec-1');
    rows = await database.allRecordingClips();
    final quiet = rows.firstWhere((r) => r.id == 'c-quiet');
    expect(AutoAnalysis.decode(quiet.autoAnalysis)?.verdict, isNull,
        reason: '两条判定线都没过 → 弃权 = 没有判断，不是「杂音」');
    expect(quiet.analysisStatus, 'analysed', reason: '机器确实看过了，这件事要留下痕迹');
  });

  test('机器判断绝不碰 kind、transcript 与 labeled_at_utc', () async {
    // 这三列各有主人：`kind` 是人标的，`transcript` 是转写的（本轮不做），
    // `labeled_at_utc` 是人的动作。机器写回时碰了任何一列，界面三态立刻失真。
    await seedRecord();
    final path = await writeClip('c-1', _wav(_loud()));
    await seedClip('c-1', localUri: path);

    await analyzerAt(DateTime.utc(2026, 10, 14, 8)).analyseRecord('rec-1');

    final row = (await database.allRecordingClips()).single;
    expect(row.kind, 'noise', reason: 'kind 是人的位置，机器不许写');
    expect(row.transcript, isNull, reason: '本轮不做转写，这一列必须一直是空的');
    expect(row.labeledAtUtc, isNull, reason: '机器判断不是一次人工标注');
  });

  test('用户已经标过的那一段，机器照样只写自己那一列', () async {
    await seedRecord();
    final path = await writeClip('c-1', _wav(_loud()));
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

  test('数字静音**不喂给模型**，结果是弃权而不是失败', () async {
    // 全零对 YAMNet 是分布外输入，「它会对一串零说什么」没有任何测量，
    // 所以那道闸挡在打分之前。用「一被调用就炸」的打分器来证明它真的没被调用——
    // 若那道闸被拆掉，这一条会变成 `failed`（因为打分器炸了）。
    await seedRecord();
    await seedClip('c-1', localUri: await writeClip('a', _wav(_silence())));

    final settled = await analyzerAt(
      DateTime.utc(2026, 10, 14, 8),
      scorer: _exploding,
    ).analyseRecord('rec-1');

    expect(settled, 1);
    final row = (await database.allRecordingClips()).single;
    expect(row.analysisStatus, 'analysed', reason: '不是失败——机器看过了，只是不说');
    expect(AutoAnalysis.decode(row.autoAnalysis)?.verdict, isNull);
  });

  test('文件读不动记 failed，不抛异常、不连累同一批里的别的片段', () async {
    await seedRecord();
    final good = await writeClip('c-good', _wav(_loud()));
    await seedClip('c-good', localUri: good);
    await seedClip('c-missing', localUri: '${tempDir.path}/根本没有.wav');

    final settled =
        await analyzerAt(DateTime.utc(2026, 10, 14, 8)).analyseRecord('rec-1');
    expect(settled, 1, reason: '只有那一段真的定案了');

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

  test('采样率不是 16 kHz 的记 failed——模型只吃 16 kHz，不该静默算错', () async {
    await seedRecord();
    // 44.1 kHz 的合法 WAV，**而且是有声音的**：响度那道闸挡的是静音，
    // 采样率这一条挡的是「喂进去会算错」，两件事得分开验。
    final pcm = Uint8List(44100 * 2);
    final view = ByteData.view(pcm.buffer);
    for (var i = 0; i < 44100; i++) {
      view.setInt16(
        i * 2,
        (math.sin(2 * math.pi * 200 * i / 44100) * 0.4 * 32767).round(),
        Endian.little,
      );
    }
    final path = '${tempDir.path}/c-44k.wav';
    await File(path).writeAsBytes(Uint8List.fromList([
      ...pcm16WavHeader(sampleRate: 44100, channels: 1, dataBytes: pcm.length),
      ...pcm,
    ]));
    await seedClip('c-1', localUri: path);

    final settled =
        await analyzerAt(DateTime.utc(2026, 10, 14, 8)).analyseRecord('rec-1');

    expect(settled, 0, reason: '没定案');
    final row = (await database.allRecordingClips()).single;
    expect(row.analysisStatus, 'failed');
    expect(row.autoAnalysis, isNull);
  });

  test('没有文件路径的片段（音频已被裁掉）直接跳过，不记 failed', () async {
    // 这是**已知的真相**，不是失败：保留期限清掉音频后 `localUri` 就是空的，
    // 那一行仍然该显示「这段录音未保留在本地」，而不是「分析失败」。
    await seedRecord();
    await seedClip('c-1');

    final settled =
        await analyzerAt(DateTime.utc(2026, 10, 14, 8)).analyseRecord('rec-1');
    expect(settled, 0);

    final row = (await database.allRecordingClips()).single;
    expect(row.analysisStatus, 'pending', reason: '没原料不算分析过');
    expect(row.autoAnalysis, isNull);
  });

  test('一段都没有时**根本不去加载模型**', () async {
    // 冷启动每次都会走 `analysePending`（`app.dart`），而绝大多数次是一段都没有。
    // 解一遍 4 MB 的模型再起一个 isolate 只为了发现没活儿干，是白付的。
    await seedRecord();
    var loads = 0;
    await analyzerAt(
      DateTime.utc(2026, 10, 14, 8),
      loadModel: () async {
        loads++;
        return _modelBytes();
      },
    ).analyseRecord('rec-1');
    expect(loads, 0);
  });

  test('一批只加载一次模型，不是一段一次', () async {
    await seedRecord();
    for (final id in ['c-1', 'c-2', 'c-3']) {
      await seedClip(id, localUri: await writeClip(id, _wav(_loud())));
    }
    var loads = 0;
    final settled = await analyzerAt(
      DateTime.utc(2026, 10, 14, 8),
      loadModel: () async {
        loads++;
        return _modelBytes();
      },
    ).analyseRecord('rec-1');
    expect(settled, 3);
    expect(loads, 1, reason: '换成一整批一个 isolate 就是为了这个');
  });

  group('模型没能跑起来：说「一段都没看」，不伪装成「看过没把握」', () {
    test('模型字节读不出来 → 抛 ClipModelUnavailable，一行都不动', () async {
      await seedRecord();
      await seedClip('c-1', localUri: await writeClip('a', _wav(_loud())));

      await expectLater(
        analyzerAt(
          DateTime.utc(2026, 10, 14, 8),
          loadModel: () async => throw const FileSystemException('模型不在包里'),
        ).analyseRecord('rec-1'),
        throwsA(isA<ClipModelUnavailable>()),
      );

      final row = (await database.allRecordingClips()).single;
      expect(row.analysisStatus, 'pending', reason: '没看就是没看，留着下次再试');
      expect(row.autoAnalysis, isNull,
          reason: '**不许**写成「弃权」——那会让「安装坏了」与「机器没把握」同形');
    });

    test('打分器在 isolate 里建不起来（原生库打不开）也抛同一个错', () async {
      await seedRecord();
      await seedClip('c-1', localUri: await writeClip('a', _wav(_loud())));

      await expectLater(
        analyzerAt(DateTime.utc(2026, 10, 14, 8), scorer: _cannotBuild)
            .analyseRecord('rec-1'),
        throwsA(isA<ClipModelUnavailable>()),
      );

      final row = (await database.allRecordingClips()).single;
      expect(row.analysisStatus, 'pending');
    });

    test('这个错误自带一句能直接给用户看的中文', () async {
      // `detail_sheet` 的 catch 是 `'分析失败：$error'`，所以 toString 就是
      // 用户看到的那句话——它得说清楚「一段都没分析」，而不是甩一个类型名。
      expect(
        const ClipModelUnavailable('boom').toString(),
        contains('一段都没分析'),
      );
    });
  });

  group('冷启动补跑', () {
    test('只捡还没分析过、且有文件的真实片段', () async {
      await seedRecord();
      final path = await writeClip('c-1', _wav(_loud()));
      await seedClip('c-1', localUri: path);
      // 已经分析过的：不该重算。
      await seedClip('c-done', localUri: path, status: 'analysed');
      // 演示数据：它的 kind / labeledAtUtc 本来就是示例数据本身的一部分。
      await seedClip('c-demo', source: 'demo', kind: 'snore');
      // 没有文件的：没有原料。
      await seedClip('c-nofile');

      final settled =
          await analyzerAt(DateTime.utc(2026, 10, 14, 8)).analysePending();

      expect(settled, 1, reason: '只该捡起 c-1 那一段');
      // 用 `allClipsByRecord` 而不是 `allRecordingClips`：后者按定义只看
      // `source = 'recording'`，演示那行根本不在里面，断言会假绿。
      final all = (await database.allClipsByRecord())['rec-1']!;
      final demo = all.firstWhere((r) => r.id == 'c-demo');
      expect(demo.autoAnalysis, isNull, reason: '演示数据不该被补上机器判断');
    });
  });

  group('并发：同一时刻只跑一批', () {
    test('两次撞车时后来者排队，两边都拿到真实结果、没有谁被丢掉', () async {
      // `analyseRecord` 是**不 await** 地从两处踢出去的（会话结束时一次、详情页点
      // 「重新分析」一次）。撞车时若把后来者丢掉并返回 0，界面上那句就会变成
      // 「没有可分析的片段」——一个假话。
      await seedRecord();
      await seedClip('c-1', localUri: await writeClip('a', _wav(_loud())));

      final analyzer = analyzerAt(DateTime.utc(2026, 10, 14, 8));
      final results = await Future.wait([
        analyzer.analyseRecord('rec-1'),
        analyzer.analyseRecord('rec-1'),
      ]);

      expect(results, [1, 1], reason: '两次都真的跑了、都报了 1 段');
    });
  });
}
