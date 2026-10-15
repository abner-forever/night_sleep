// 片段分析的 I/O 侧：把 WAV 文件读出来、交给纯函数层、把结果写回库。
//
// 纯计算部分（读字节 → 特征 → 判定）全部在 `domain/clip_analysis.dart` 里，那才是
// 能被完整单测的一半。这个文件只负责三件在单测里做不到的事：读磁盘、开 isolate、
// 写数据库。
//
// **它只读音频、只写 `auto_analysis` 与 `analysis_status` 两列。** 不碰 `kind`、
// 不碰 `labeled_at_utc`、不碰 `transcript`——那三样都有各自的主人。

import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../domain/clip_analysis.dart';
import 'wav_file.dart';

/// 把一晚（或全部待分析）的片段跑一遍声学分析并落库。
class ClipAnalyzer {
  ClipAnalyzer(
    this._db, {
    this.params = const ClipAnalysisParams(),
    DateTime Function() clock = DateTime.now,
  }) : _clock = clock;

  final AppDatabase _db;
  final ClipAnalysisParams params;
  final DateTime Function() _clock;

  /// 分析指定记录的所有片段。返回**这次真的写了几条**。
  ///
  /// 详情页的「重新分析这一晚」与「结束会话后的自动分析」都走它。
  Future<int> analyseRecord(String recordId) async {
    final byRecord = await _db.allClipsByRecord();
    final clips = byRecord[recordId] ?? const [];
    return _analyseAll(clips);
  }

  /// 分析所有**还没被机器看过**的真实片段（冷启动补跑用）。
  ///
  /// 这一条是专为「装上新版本之前就已经录好的那些片段」准备的：用户不需要做任何事，
  /// 已有的录音会被自动补上分析。
  Future<int> analysePending() async {
    return _analyseAll(await _db.clipsAwaitingAnalysis());
  }

  Future<int> _analyseAll(List<SoundClip> clips) async {
    var written = 0;
    for (final clip in clips) {
      final path = clip.localUri;
      if (path == null) continue; // 音频已被保留期限裁掉：没有原料，跳过
      if (await _analyseOne(clip.id, path)) written++;
    }
    return written;
  }

  /// 分析一段并写回。**读不开 / 解不了也算写完**（写的是 `failed`），
  /// 所以返回 `true` 表示「这一段的结论已经定案」，不是「判出来了」。
  Future<bool> _analyseOne(String clipId, String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      // **计算丢进 isolate**：16 kHz 下一段几十万采样、一晚可能上百段，
      // 放主 isolate 会把界面卡住。传进去的是字节，传回来的是几个数。
      //
      // **`params` 必须先取到局部变量。** 闭包直接写 `params` 就是引用
      // `this.params`，于是隐式捕获 `this`——连同它手里的数据库句柄一起被塞进
      // isolate 消息，`SendPort.send()` 当场报「object is unsendable」，整段分析
      // 无声地退化成「失败」。局部变量把捕获范围缩到两个可发送的值。
      final localParams = params;
      final verdict = await Isolate.run(() => _compute(bytes, localParams));
      await _db.updateClipAutoAnalysis(
        clipId,
        payload: AutoAnalysis(verdict: verdict, analyzedAtUtc: _clock().toUtc())
            .encode(),
        status: 'analysed',
      );
      return true;
    } catch (error) {
      // 一段读不动不该让整晚全军覆没。如实记 `failed`——那段音频还在，还能回放，
      // 只是机器没能给出看法。
      //
      // **但要留下日志**：静默吞掉的话，现场只会看到一堆「分析失败」而没有任何
      // 线索，连是文件坏了还是代码炸了都分不出来。
      debugPrint('片段 $clipId 分析失败：$error');
      try {
        await _db.updateClipAutoAnalysis(clipId,
            payload: null, status: 'failed');
      } catch (inner) {
        // 连状态都写不进去（库出问题了）：放弃这一段，继续下一段。
        debugPrint('片段 $clipId 连失败状态都写不进去：$inner');
      }
      return false;
    }
  }
}

/// isolate 里跑的那一段：字节 → 判定。**必须是顶层函数**，闭包捕获的东西越少越好。
///
/// 返回值有两种「没有结论」，**必须分得开**：
///  * 返回 `null` —— 读出来了，但机器没把握（**弃权**）。落库记 `analysed`。
///  * 抛出异常 —— **根本读不出来**（不是 PCM16 WAV、截断、空文件）。落库记 `failed`。
///
/// 混成一种的话，「这段音频坏了」会伪装成「机器看过觉得没什么」，而那两件事对
/// 用户的含义完全不同：前者要他去查文件，后者只是机器没把握。
AutoVerdict? _compute(Uint8List bytes, ClipAnalysisParams params) {
  final audio = parsePcm16Wav(bytes);
  if (audio == null) {
    throw const FormatException('不是可解析的 PCM16 WAV');
  }
  if (audio.isEmpty) {
    throw const FormatException('WAV 里没有任何采样');
  }
  return classifyClip(
    audio.samples,
    sampleRate: audio.sampleRate,
    params: params,
  );
}

final clipAnalyzerProvider = Provider<ClipAnalyzer>((ref) {
  return ClipAnalyzer(ref.watch(databaseProvider));
});
