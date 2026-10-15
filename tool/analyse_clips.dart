// 对一个目录（或若干个文件）里的夜间录音片段跑一遍声学分析与判定，打印特征表。
//
// **它存在的理由是「让人能自己核」**：`clip_analysis.dart` 那组阈值是拍的，唯一的
// 验收办法是让使用方听着片段、对着这张表判断「机器说的对不对」。所以这张表**必须把
// 原始特征一并打出来**——只打一个「疑似打鼾」是没有信息量的，读者无从反驳。
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

  // ignore: avoid_print
  print(
    '${'文件'.padRight(24)}${'时长'.padLeft(7)}${'响度'.padLeft(8)}'
    '${'低频'.padLeft(7)}${'语音'.padLeft(7)}${'高频'.padLeft(7)}'
    '${'质心'.padLeft(7)}${'平坦'.padLeft(7)}${'过零'.padLeft(7)}'
    '${'呼吸'.padLeft(7)}${'音节'.padLeft(7)}   判定',
  );

  var snore = 0;
  var voice = 0;
  var noise = 0;
  var abstain = 0;
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
    final verdict = classifyClip(audio.samples, sampleRate: audio.sampleRate);

    final String judgement;
    if (verdict == null) {
      abstain++;
      judgement = '弃权（留待标注）';
    } else {
      switch (verdict.label) {
        case AutoLabel.snore:
          snore++;
        case AutoLabel.voice:
          voice++;
        case AutoLabel.noise:
          noise++;
      }
      final span = verdict.event?.spanLabel;
      judgement = '${verdict.label.label}'
          '（余量 ${verdict.margin.toStringAsFixed(2)}'
          '${span == null ? '' : ' · $span'}）';
    }

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
      '   $judgement',
    );
  }

  // ignore: avoid_print
  print(
    '\n共 ${files.length} 段：疑似打鼾 $snore · 疑似人声 $voice · 杂音 $noise · '
    '弃权 $abstain · 读不出来 $unreadable',
  );
  // ignore: avoid_print
  print(
    '\n判为「疑似打鼾」的那几段请**听一遍**再决定阈值对不对——'
    '这张表只说明特征能把片段分开，不说明分开的就是鼾声。',
  );
  // ignore: avoid_print
  print(
    '要算「和你标注的一致率」，用 `tool/eval_clips.dart`；'
    '这个脚本是给你用耳朵逐段复核用的。',
  );
}

String _clip(String value, int width) =>
    value.length <= width ? value.padRight(width) : value.substring(0, width);

String _pct(double value) => '${(value * 100).round()}%';
