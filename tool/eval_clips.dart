// 把机器的自动判定与人的标注逐段对照，算出正确率。
//
// **这是「阈值到底对不对」唯一能给出数字的工具。** 与 `analyse_clips.dart` 的分工：
// 那个是给你用耳朵复核单段的特征表，这个是拿你**已经标过**的那些段算总账。
//
// 用法：
//   dart run tool/eval_clips.dart <片段目录> <标注文件> [--sweep=参数名]
//
// 标注文件按行写 `<片段 id> <标注>`，空行与 `#` 开头的行忽略。标注取值：
//   snore / talk / noise  —— 与 `SoundEventKind` 的 id 一致
//   -                     —— 没标过，跳过
// 从真机库里导出这个文件：
//   sqlite3 night_sleep.sqlite \
//     "select id, kind from sound_clips where labeled_at_utc is not null;" > labels.txt
//
// **正确率必须连同「弃权多少」一起读。** 机器靠弃权可以轻易把正确率做到 100%
// （判一段都不判），所以这个工具同时报出**覆盖率**——机器肯开口的那部分占多少。
// 单看任何一个数都会得出相反的结论。
//
// ignore_for_file: avoid_print

import 'dart:io';

import 'package:night_sleep/features/sleep/data/wav_file.dart';
import 'package:night_sleep/features/sleep/domain/clip_analysis.dart';

/// 标注 id → 机器标签。人只说「梦话」，机器只说「疑似人声」——两者对齐在这里，
/// 且只在这里：名字不同是刻意的，别为了对齐把机器的说法改成「梦话」。
const _humanToAuto = {
  'snore': AutoLabel.snore,
  'talk': AutoLabel.voice,
  'noise': AutoLabel.noise,
};

/// 可扫的阈值：名字 → (参数名, 取值序列)。用来回答「调大调小会怎样」。
final _sweepable = <String, (String, List<double>)>{
  'snoreLowRatio': (
    'snoreLowRatio',
    [0.30, 0.35, 0.40, 0.45, 0.50, 0.55, 0.60]
  ),
  'snoreCentroid': ('snoreCentroid', [400, 500, 600, 700, 800, 1000, 1200]),
  'snorePitchStrength': (
    'snorePitchStrength',
    [0.20, 0.30, 0.40, 0.45, 0.50, 0.60, 0.70]
  ),
  'snoreMaxPeakShare': (
    'snoreMaxPeakShare',
    [0.20, 0.25, 0.30, 0.35, 0.40, 0.50, 0.70]
  ),
  'voiceSpeechRatio': (
    'voiceSpeechRatio',
    [0.40, 0.45, 0.50, 0.55, 0.60, 0.65, 0.70]
  ),
  'voiceCentroid': ('voiceCentroid', [500, 600, 700, 800, 900, 1000, 1200]),
  'voicePitchStrength': (
    'voicePitchStrength',
    [0.20, 0.30, 0.40, 0.45, 0.50, 0.60, 0.70]
  ),
  'minEventMs': ('minEventMs', [500, 1000, 1500, 2000, 2500, 3000, 4000]),
};

Future<void> main(List<String> args) async {
  final flags = args.where((a) => a.startsWith('--')).toList();
  final positional = args.where((a) => !a.startsWith('--')).toList();
  if (positional.length < 2) {
    stderr.writeln('用法：dart run tool/eval_clips.dart <片段目录> <标注文件> '
        '[--sweep=参数名]');
    stderr.writeln('可扫参数：${_sweepable.keys.join(" / ")}');
    exit(2);
  }

  final labels = _readLabels(File(positional[1]));
  if (labels.isEmpty) {
    stderr.writeln('标注文件里没有一条有效标注：${positional[1]}');
    exit(2);
  }

  final samples = await _loadClips(Directory(positional[0]));
  if (samples.isEmpty) {
    stderr.writeln('片段目录里没有能读的 WAV：${positional[0]}');
    exit(2);
  }

  final sweepNames = flags
      .where((f) => f.startsWith('--sweep='))
      .map((f) => f.substring('--sweep='.length))
      .toList();
  final sweep = sweepNames.isEmpty ? null : sweepNames.first;

  final evaluated = <_Case>[];
  for (final s in samples) {
    final human = labels[s.id];
    if (human == null) continue;
    evaluated.add(_Case(
      id: s.id,
      human: human,
      seconds: s.audio.duration.inMilliseconds / 1000,
      verdict: classifyClip(s.audio.samples, sampleRate: s.audio.sampleRate),
    ));
  }
  if (evaluated.isEmpty) {
    stderr.writeln('片段与标注对不上号：没有一个片段在标注文件里。');
    exit(2);
  }

  _printTable(evaluated);
  _printScore(evaluated);

  if (sweep != null) {
    final entry = _sweepable[sweep];
    if (entry == null) {
      stderr.writeln('不能扫的参数：$sweep。可扫：${_sweepable.keys.join(" / ")}');
      exit(2);
    }
    _printSweep(sweep, samples, labels, entry.$1, entry.$2);
  }
}

/// 一段被评估的录音：人标的、机器判的、以及它的时长。
class _Case {
  _Case({
    required this.id,
    required this.human,
    required this.seconds,
    required this.verdict,
  });

  final String id;
  final AutoLabel human;
  final double seconds;
  final AutoVerdict? verdict;

  AutoLabel? get machine => verdict?.label;

  bool get abstained => verdict == null;

  bool get correct => machine == human;
}

/// 目录里一段读得动的录音。
class _Sample {
  _Sample(this.id, this.audio);

  final String id;
  final Pcm16Audio audio;
}

Future<List<_Sample>> _loadClips(Directory dir) async {
  if (!dir.existsSync()) return const [];
  final files = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.toLowerCase().endsWith('.wav'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final out = <_Sample>[];
  for (final file in files) {
    final audio = await readWavFile(file.path);
    if (audio == null) {
      stderr.writeln('跳过读不开的文件：${file.path}');
      continue;
    }
    out.add(_Sample(_clipIdOf(file.uri.pathSegments.last), audio));
  }
  return out;
}

/// 文件名 `clip-<时间戳>.wav` → 片段 id。其余形状原样返回（标注文件照它对齐）。
String _clipIdOf(String fileName) {
  final stem = fileName.substring(0, fileName.length - 4);
  return stem;
}

Map<String, AutoLabel> _readLabels(File file) {
  if (!file.existsSync()) {
    stderr.writeln('标注文件不存在：${file.path}');
    exit(2);
  }
  final labels = <String, AutoLabel>{};
  for (final raw in file.readAsLinesSync()) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    // 空白或 `|` 分隔都收：`sqlite3` 默认的列分隔符就是 `|`。
    final parts = line.split(RegExp(r'[\s|]+'));
    if (parts.length < 2) continue;
    final label = _humanToAuto[parts[1]];
    if (label == null) {
      stderr.writeln('认不出的标注「${parts[1]}」，跳过：$line');
      continue;
    }
    labels[parts[0]] = label;
  }
  return labels;
}

void _printTable(List<_Case> cases) {
  print('${'片段'.padRight(22)}${'时长'.padLeft(7)}${'人标'.padLeft(8)}'
      '${'机器'.padLeft(12)}${'位置'.padLeft(20)}判定');
  print('-' * 82);
  for (final c in cases) {
    final span = c.verdict?.event?.spanLabel ?? '';
    final mark = c.abstained ? '弃权' : (c.correct ? '✓' : '✗ 不符');
    print('${c.id.padRight(22)}'
        '${'${c.seconds.toStringAsFixed(1)}s'.padLeft(7)}'
        '${c.human.label.padLeft(8)}'
        '${(c.machine?.label ?? '—').padLeft(12)}'
        '${span.padLeft(20)}  $mark');
  }
}

void _printScore(List<_Case> cases) {
  final total = cases.length;
  final spoke = cases.where((c) => !c.abstained).toList();
  final right = spoke.where((c) => c.correct).length;
  final abstained = total - spoke.length;

  print('');
  print('共 $total 段：机器开口 ${spoke.length} 段（覆盖 '
      '${(spoke.length * 100 / total).toStringAsFixed(0)}%），弃权 $abstained 段');
  if (spoke.isEmpty) {
    print('开口 0 段——正确率无从谈起。这是一个「什么都不判」的分类器。');
  } else {
    print('开口的里面判对 $right 段 → 准确率 '
        '${(right * 100 / spoke.length).toStringAsFixed(0)}%');
  }
  // 把弃权当作「判错」看的整体正确率：这是最保守的口径，也是唯一不会因为
  // 「多弃权」而变好看的那个数。
  print('把弃权也记为错：$right/$total = '
      '${(right * 100 / total).toStringAsFixed(0)}%');

  const labels = AutoLabel.values;
  print('');
  print('${'类别'.padRight(10)}${'人标数'.padLeft(8)}${'机器判数'.padLeft(10)}'
      '${'判对'.padLeft(8)}${'召回'.padLeft(8)}${'精确'.padLeft(8)}');
  for (final label in labels) {
    final humanCount = cases.where((c) => c.human == label).length;
    final machineCount = spoke.where((c) => c.machine == label).length;
    final hit =
        cases.where((c) => c.human == label && c.machine == label).length;
    // 召回的分母是该类真实存在的段数；没有样本时打「—」而不是 0%，
    // 因为 0/0 不是「一个都没召回」，是「根本没样本可召回」。
    final recall = humanCount == 0
        ? '—'
        : '${(hit * 100 / humanCount).toStringAsFixed(0)}%';
    final precision = machineCount == 0
        ? '—'
        : '${(hit * 100 / machineCount).toStringAsFixed(0)}%';
    print('${label.label.padRight(10)}${'$humanCount'.padLeft(8)}'
        '${'$machineCount'.padLeft(10)}${'$hit'.padLeft(8)}'
        '${recall.padLeft(8)}${precision.padLeft(8)}');
  }
}

/// 扫一个阈值，打印它取各个值时的（覆盖率, 准确率, 保守正确率）。
///
/// **别只看准确率那一列。** 把门槛调严会让准确率一路升到 100%，代价是覆盖率掉到 0
/// ——那一列必须同时在眼前。
void _printSweep(
  String name,
  List<_Sample> samples,
  Map<String, AutoLabel> labels,
  String paramName,
  List<double> values,
) {
  print('');
  print('扫 $paramName：');
  print('${'取值'.padLeft(10)}${'开口'.padLeft(8)}${'覆盖'.padLeft(8)}'
      '${'准确'.padLeft(8)}${'保守'.padLeft(8)}  逐类命中（鼾/声/杂）');
  for (final value in values) {
    final params = _withParam(paramName, value);
    final cases = <_Case>[];
    for (final s in samples) {
      final human = labels[s.id];
      if (human == null) continue;
      cases.add(_Case(
        id: s.id,
        human: human,
        seconds: s.audio.duration.inMilliseconds / 1000,
        verdict: classifyClip(s.audio.samples,
            sampleRate: s.audio.sampleRate, params: params),
      ));
    }
    final spoke = cases.where((c) => !c.abstained).toList();
    final right = spoke.where((c) => c.correct).length;
    final hits = AutoLabel.values
        .map((l) => cases.where((c) => c.human == l && c.machine == l).length)
        .join('/');
    final accuracy = spoke.isEmpty
        ? '—'
        : '${(right * 100 / spoke.length).toStringAsFixed(0)}%';
    final coverage =
        '${(spoke.length * 100 / cases.length).toStringAsFixed(0)}%';
    print('${value.toString().padLeft(10)}${'${spoke.length}'.padLeft(8)}'
        '${coverage.padLeft(8)}${accuracy.padLeft(8)}'
        '${'${(right * 100 / cases.length).toStringAsFixed(0)}%'.padLeft(8)}  $hits');
  }
}

/// 造一个只改了一个参数的 [ClipAnalysisParams]。
ClipAnalysisParams _withParam(String name, double value) {
  const d = ClipAnalysisParams();
  return ClipAnalysisParams(
    snoreLowRatio: name == 'snoreLowRatio' ? value : d.snoreLowRatio,
    snoreCentroid: name == 'snoreCentroid' ? value : d.snoreCentroid,
    snorePitchStrength:
        name == 'snorePitchStrength' ? value : d.snorePitchStrength,
    snoreMaxPeakShare:
        name == 'snoreMaxPeakShare' ? value : d.snoreMaxPeakShare,
    voiceSpeechRatio: name == 'voiceSpeechRatio' ? value : d.voiceSpeechRatio,
    voiceCentroid: name == 'voiceCentroid' ? value : d.voiceCentroid,
    voicePitchStrength:
        name == 'voicePitchStrength' ? value : d.voicePitchStrength,
    minEventMs: name == 'minEventMs' ? value.round() : d.minEventMs,
  );
}
