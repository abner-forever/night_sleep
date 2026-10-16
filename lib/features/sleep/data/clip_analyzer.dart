// 片段分析的 I/O 侧：读 WAV 文件、交给 YAMNet 打分、把判定写回库。
//
// 三块分得很清，搬动任何一块之前先读这里：
//
//  * **判定规则** —— `domain/clip_yamnet.dart`。纯函数，`flutter test` 里完整可测。
//  * **跑模型** —— `data/yamnet_scorer.dart`。要原生库与模型文件，单测环境里都没有。
//  * **这个文件** —— 读磁盘、开 isolate、写数据库。只写 `auto_analysis` 与
//    `analysis_status` 两列，**不碰 `kind`、不碰 `labeled_at_utc`、不碰 `transcript`**
//    ——那三样各有主人。
//
// **整批只起一个 isolate、只加载一次模型。** 早先的版本是「一段一个 `Isolate.run`」，
// 那对手写特征无所谓（每段算几毫秒）；换成模型之后不行了：4 MB 的模型要解一遍、
// 原生解释器要建一次，一晚几十段就是几十次白付的开销。现在是一个批处理进去、
// 一串结论出来。

import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../domain/clip_analysis.dart';
import '../domain/clip_yamnet.dart';
import 'wav_file.dart';
import 'yamnet_scorer.dart';

/// 模型没能跑起来——**一段都没看**，与「看过但一段都没把握」是两件事。
///
/// 前者是这个安装坏了（模型没打进包、原生库加载不了），后者是机器诚实地弃权。
/// 抛出来而不是用返回值表示，是因为调用方的 catch 本来就会把它原样说给用户
/// （`detail_sheet._reanalyseSounds` 的 `'分析失败：$error'`）——**不改任何签名**，
/// 那一句就成了「分析失败：YAMNet 模型没能加载起来，这次一段都没分析。」
class ClipModelUnavailable implements Exception {
  const ClipModelUnavailable(this.cause);

  /// 底下真正的错（文件不在、原生库打不开……）。**只进日志，不进界面**——
  /// 它对用户没有意义，但排查时是唯一的线索。
  final Object cause;

  @override
  String toString() => 'YAMNet 模型没能加载起来，这次一段都没分析。';
}

/// 把一晚（或全部待分析）的片段跑一遍模型判定并落库。
class ClipAnalyzer {
  ClipAnalyzer(
    this._db, {
    this.params = const YamnetParams(),
    ClipScorerFactory scorerFactory = createYamnetScorer,
    Future<Uint8List> Function() loadModel = loadYamnetModelBytes,
    DateTime Function() clock = DateTime.now,
  })  : _scorerFactory = scorerFactory,
        _loadModel = loadModel,
        _clock = clock;

  final AppDatabase _db;
  final YamnetParams params;
  final ClipScorerFactory _scorerFactory;
  final Future<Uint8List> Function() _loadModel;
  final DateTime Function() _clock;

  /// 分析指定记录的所有片段。返回**这次真的定了几段**（含弃权，不含读不动的）。
  ///
  /// 详情页的「重新分析这一晚」与「结束会话后的自动分析」都走它。
  Future<int> analyseRecord(String recordId) async {
    final byRecord = await _db.allClipsByRecord();
    return _serialised(() => _analyseAll(byRecord[recordId] ?? const []));
  }

  /// 分析所有**还没被机器看过**的真实片段（冷启动补跑用）。
  ///
  /// 这一条是专为「装上新版本之前就已经录好的那些片段」准备的：用户不需要做任何事，
  /// 已有的录音会被自动补上分析。判定引擎换代时会由迁移把旧结论清回 `pending`
  /// （见 `app_database.dart` 的 v8），于是它同时也承担了「旧片段重算」这件事。
  Future<int> analysePending() async {
    return _serialised(
        () async => _analyseAll(await _db.clipsAwaitingAnalysis()));
  }

  /// 同一时刻只跑一批。
  ///
  /// **批处理把并发的代价抬高了**：以前一段一个 isolate，撞上了只是白算一遍特征；
  /// 现在一个批次里有一份 4 MB 的模型加一个原生解释器，两次撞车就是两份。而
  /// `analyseRecord` 是**不 await** 地从两处踢出去的（会话结束时一次、详情页点
  /// 「重新分析」一次），撞车不难发生。
  ///
  /// 后来者排队而不是被丢掉：丢掉就得返回一个假的「0 段」，那与「没有可分析的片段」
  /// 在界面上同形，正是这个仓最挡的那种含糊。
  Future<int> _serialised(Future<int> Function() work) {
    final previous = _inFlight;
    final next = () async {
      if (previous != null) {
        // 前一批的失败不该连累这一批。
        try {
          await previous;
        } catch (_) {}
      }
      return work();
    }();
    _inFlight = next;
    return next;
  }

  /// 最近一批。只为串行化，不做别的用途。
  Future<int>? _inFlight;

  Future<int> _analyseAll(List<SoundClip> clips) async {
    // 没有音频的片段（已被保留期限裁掉）没有原料，跳过——**不记 `failed`**：
    // 「音频没了」是已知的真相，不是分析失败。
    final jobs = <({String id, String path})>[];
    for (final clip in clips) {
      final path = clip.localUri;
      if (path == null) continue;
      jobs.add((id: clip.id, path: path));
    }
    // **空批次要在加载模型之前就返回**：冷启动每次都会走这条路（`app.dart`），
    // 而绝大多数次是一段都没有——不该为此解一遍 4 MB 的模型再起一个 isolate。
    if (jobs.isEmpty) return 0;

    // 模型在**主 isolate** 读：`rootBundle` 要走平台通道，后台 isolate 收不到。
    // 读到的字节再跟着这次批处理送进 isolate。
    final Uint8List modelBytes;
    try {
      modelBytes = await _loadModel();
    } catch (error) {
      // **不写任何状态**：一段都没看，就不是「看过、没把握」，也不该记成
      // 「音频读不出来」。抛出去让调用方如实说明。
      debugPrint('YAMNet 模型加载失败，本次一段都没分析：$error');
      throw ClipModelUnavailable(error);
    }

    // **先取到局部变量再进闭包。** 闭包直接写 `params` / `_scorerFactory` 就是引用
    // `this`，于是隐式捕获整个 `ClipAnalyzer`——连同它手里的数据库句柄一起被塞进
    // isolate 消息，`SendPort.send()` 当场报「object is unsendable」，整段分析无声地
    // 退化成「失败」。这个坑 2026-10-14 踩过一次。
    //
    // `_scorerFactory` 尤其要小心：它是个字段，写 `_scorerFactory` 就是
    // `this._scorerFactory`，捕获的是整个对象。测试注入的假工厂也必须捕获纯数据
    // 并且**别把数据库圈进闭包的作用域**——`Isolate.run` 的文档明说闭包可能因为
    // 实现限制而隐式送走意外的东西，其中包括送不出去的对象。
    final localJobs = jobs;
    final localFactory = _scorerFactory;
    final localParams = params;
    final List<_ClipOutcome> results;
    try {
      results = await Isolate.run(
        () => _analyseBatch(localJobs, modelBytes, localFactory, localParams),
      );
    } catch (error) {
      // 整批一起没了：模型在 isolate 里建不起来、原生库打不开、或是被 OOM 杀掉。
      // **行不写任何状态**（留着 `pending` 让它下次再试），但**不能沉默**——
      // 这与「跑完了、一段都没把握」在界面上必须分得开。
      debugPrint('片段分析整批失败：$error');
      throw ClipModelUnavailable(error);
    }

    var settled = 0;
    for (final result in results) {
      if (result.failed) {
        await _markFailed(result.id);
        continue;
      }
      try {
        await _db.updateClipAutoAnalysis(
          result.id,
          payload: AutoAnalysis(
            verdict: result.verdict,
            analyzedAtUtc: _clock().toUtc(),
          ).encode(),
          status: 'analysed',
        );
      } catch (error) {
        // 库出了问题：记下这一段、继续写下面的，别让一条写不进去拖垮整晚。
        debugPrint('片段 ${result.id} 的判定写不进去：$error');
        continue;
      }
      settled++;
    }
    return settled;
  }

  /// 记 `failed`。**这一段音频还在、还能回放**，只是机器没能给出看法。
  ///
  /// 连状态都写不进去（库坏了）时**不抛**：返回码里那一段不会被算进 `settled`，
  /// 一次写失败不该让整晚的分析停在这里。
  Future<void> _markFailed(String clipId) async {
    try {
      await _db.updateClipAutoAnalysis(clipId, payload: null, status: 'failed');
    } catch (error) {
      debugPrint('片段 $clipId 连失败状态都写不进去：$error');
    }
  }
}

/// 一段的结局。
///
/// **两种「没有结论」必须分得开**，同 `wav_file.dart` 的 `null`-不抛异常是同一条口径：
///  * `failed == true` —— **根本读不出来**（不是 PCM16 WAV、截断、空文件、采样率不是
///    16 kHz）。落库记 `failed`，那一段要用户去查文件。
///  * `failed == false` 且 `verdict == null` —— 读出来了，但机器没把握（**弃权**）。
///    落库记 `analysed`。这两件事对用户的含义完全不同。
typedef _ClipOutcome = ({String id, AutoVerdict? verdict, bool failed});

/// isolate 里跑的那一整批：模型建一次，逐段打分判定。
///
/// **必须是顶层函数**，闭包捕获的东西越少越好（理由见 `_analyseAll` 里那段注释）。
///
/// 模型的构造与释放都在这里：`Interpreter` 手里是原生资源，不能跨 isolate 传，
/// 而 `Model.fromBuffer` 会把字节拷进原生内存（`tflite_flutter` 的 `model.dart`），
/// 所以传进来的 `Uint8List` 在这之后就可以不管了。
List<_ClipOutcome> _analyseBatch(
  List<({String id, String path})> jobs,
  Uint8List modelBytes,
  ClipScorerFactory scorerFactory,
  YamnetParams params,
) {
  final scorer = scorerFactory(modelBytes);
  try {
    return [
      for (final job in jobs) _analyseOneClip(job.id, job.path, scorer, params),
    ];
  } finally {
    scorer.dispose();
  }
}

/// 一段：字节 → 判定。**一段读不动不许连累整晚**，所以异常在这一层就被吃掉。
_ClipOutcome _analyseOneClip(
  String id,
  String path,
  ClipScorer scorer,
  YamnetParams params,
) {
  try {
    final audio = parsePcm16Wav(File(path).readAsBytesSync());
    if (audio == null) throw const FormatException('不是可解析的 PCM16 WAV');
    if (audio.isEmpty) throw const FormatException('WAV 里没有任何采样');
    // **采样率不对就判不了，这一条不归打分器管。** YAMNet 只吃 16 kHz，而采样率
    // 来自文件头（`wav_file.dart` 那条「不是假定 16000」）。喂错了不是「分低一点」，
    // 是**整段频率都错位**——模型照样会给出一个分数，而那个分数毫无意义。
    // 采集端固定 16 kHz，所以这一段是防御性的；`YamnetScorer` 里还有一道同样的闸。
    if (audio.sampleRate != kYamnetSampleRate) {
      throw FormatException(
        '采样率 ${audio.sampleRate} 不是 $kYamnetSampleRate，模型吃不了',
      );
    }
    // 数字静音不必喂给模型：那对它是分布外的输入，而「模型会说什么」没有测量。
    // 闸在打分之前，省下的那一次推理是顺带的。
    final dbfs = rmsDbfs(audio.samples);
    if (dbfs < kSilenceDbfs) {
      return (id: id, verdict: null, failed: false);
    }
    final scores = scorer.score(audio.samples, audio.sampleRate);
    return (
      id: id,
      verdict: verdictFromScores(scores, dbfs: dbfs, params: params),
      failed: false,
    );
  } catch (error) {
    // **要留下日志**：静默吞掉的话，现场只会看到一堆「分析失败」而没有任何线索，
    // 连是文件坏了还是模型炸了都分不出来。
    debugPrint('片段 $id 分析失败：$error');
    return (id: id, verdict: null, failed: true);
  }
}

final clipAnalyzerProvider = Provider<ClipAnalyzer>((ref) {
  return ClipAnalyzer(ref.watch(databaseProvider));
});
