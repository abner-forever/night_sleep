// 对一个目录（或若干个文件）里的夜间录音片段量一遍声学特征，打印特征表。
//
// **它不再打印任何判定。** 2026-10-16 之前这里跑的是那套手写阈值，而那张表存在的
// 理由是「让人能自己核」——使用方听着片段、对着表判断机器说的对不对。那套规则已被
// 证伪并删除（47 段上覆盖 2% / 准确 0%），判定换成了 YAMNet 模型分。
//
// **模型不能在 `dart run` 里跑**：`tflite_flutter` 要一个平台原生库，命令行 Dart
// 没有。所以判定只在 App 里跑，逐段的模型分与判定线摆在详情页的展开区。
//
// 剩下的这个脚本只干一件事：**把实测的声学特征摆出来给人核对**。这些数仍然是真测量
// （`measureClip` 的 FFT / 包络都是单测钉过的），只是**已经不参与判定了**——
// 拿它去推断机器为什么这么判会推错。
//
// 用法：
//   dart run tool/analyse_clips.dart <目录或 .wav 文件>...
//
// 它**只读**，不改任何文件、不连数据库、不碰平台通道。

import 'dart:io';

import 'package:night_sleep/features/sleep/data/wav_file.dart';
import 'package:night_sleep/features/sleep/domain/clip_analysis.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('用法: dart run tool/analyse_clips.dart <目录或 .wav 文件>...');
    exit(2);
  }

  final files = <File>[];
  for (final arg in args) {
    final entity = FileSystemEntity.typeSync(arg);
    if (entity == FileSystemEntityType.directory) {
      files.addAll(
        Directory(arg)
            .listSync()
            .whereType<File>()
            .where((f) => f.path.toLowerCase().endsWith('.wav')),
      );
    } else if (entity == FileSystemEntityType.file) {
      files.add(File(arg));
    } else {
      stderr.writeln('找不到: $arg');
      exit(2);
    }
  }
  files.sort((a, b) => a.path.compareTo(b.path));

  if (files.isEmpty) {
    stderr.writeln('没有找到任何 .wav 文件');
    exit(2);
  }

  // 表头**必须与下面打的列一一对上**：这一整张表的用处就是让人拿它反驳机器，
  // 列名错位等于把判据指错。（曾经把最后一列写成「音节」，而打的是 `pitchStrength`
  // ——那正是参与判定的那一条，读者会照着错的列去核。）
  //
  // 「单音」= `spectralPeakShare`，也是判据之一（鼾声不是乐音），打印出来才能核。
  // ignore: avoid_print
  print(
    '${'文件'.padRight(24)}${'时长'.padLeft(7)}${'响度'.padLeft(8)}'
    '${'低频'.padLeft(7)}${'语音'.padLeft(7)}${'高频'.padLeft(7)}'
    '${'质心'.padLeft(7)}${'平坦'.padLeft(7)}${'过零'.padLeft(7)}'
    '${'呼吸'.padLeft(7)}${'周期性'.padLeft(7)}${'单音'.padLeft(7)}',
  );

  var unreadable = 0;

  for (final file in files) {
    final name = file.uri.pathSegments.last;
    final audio = await readWavFile(file.path);
    if (audio == null || audio.isEmpty) {
      unreadable++;
      // ignore: avoid_print
      print('${_clip(name, 24)}  —— 读不出来（空文件或不是 PCM16 WAV）');
      continue;
    }

    final features = measureClip(audio.samples, sampleRate: audio.sampleRate);

    // ignore: avoid_print
    print(
      '${_clip(name, 24)}'
      '${'${audio.duration.inMilliseconds / 1000}s'.padLeft(7)}'
      '${features.dbfs.toStringAsFixed(1).padLeft(8)}'
      '${_pct(features.lowRatio).padLeft(7)}'
      '${_pct(features.speechRatio).padLeft(7)}'
      '${_pct(features.highRatio).padLeft(7)}'
      '${features.spectralCentroid.round().toString().padLeft(7)}'
      '${features.spectralFlatness.toStringAsFixed(2).padLeft(7)}'
      '${features.zeroCrossingRate.toStringAsFixed(3).padLeft(7)}'
      '${_pct(features.breathBandRatio).padLeft(7)}'
      '${features.pitchStrength.toStringAsFixed(2).padLeft(7)}'
      '${_pct(features.spectralPeakShare).padLeft(7)}',
    );
  }

  // ignore: avoid_print
  print('\n共 ${files.length} 段，读不出来 $unreadable 段');
  // ignore: avoid_print
  print(
    '\n**这张表里没有判定。** 机器判定 2026-10-16 起由 YAMNet 给出，而 `dart run` '
    '起不了 TFLite——判定只在 App 里跑，依据串在详情页展开区。',
  );
  // ignore: avoid_print
  print(
    '所以这个脚本现在的用处只剩一件：把**实测的声学特征**逐段摆出来，'
    '让你拿耳朵对着数核一遍这些测量本身对不对。',
  );
  // ignore: avoid_print
  print(
    '要算模型判定和你标注的一致率，先让手机上的端侧测量产出分档表，'
    '再 `dart run tool/eval_clips.dart <scores.txt> <labels.txt>`。',
  );
}

String _clip(String value, int width) =>
    value.length <= width ? value.padRight(width) : value.substring(0, width);

String _pct(double value) => '${(value * 100).round()}%';
