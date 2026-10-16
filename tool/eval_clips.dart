// 把机器的自动判定与人的标注逐段对照，算出正确率。
//
// **这是「阈值到底对不对」唯一能给出数字的工具。** 与 `analyse_clips.dart` 的分工：
// 那个把实测的声学特征摆出来给人核对，这个拿你**已经标过**的那些段算总账。
//
// ## 为什么要先有一份「分档表」
//
// 判定在 2026-10-16 换成了 YAMNet（`domain/clip_yamnet.dart`），而**模型不能在
// `dart run` 里跑**——`tflite_flutter` 要一个平台原生库，命令行 Dart 没有。
//
// 所以分两步：先在**真机**上跑一次端侧测量（`integration_test/yamnet_eval_test.dart`），
// 它给每一段真实录音落一份「整段均分」，再从设备上取回来喂给这个脚本：
//
//   flutter test integration_test/yamnet_eval_test.dart -d <serial>
//   adb exec-out run-as com.example.night_sleep cat \
//     files/yamnet_scores.txt > scores.txt
//
// 用法：
//   dart run tool/eval_clips.dart <分档表> <标注文件> [--sweep=snore|voice]
//
// 分档表的行：`<片段 id> <Snoring 均分> <Speech 均分>`，空白或 `|` 分隔。
// **表里没有的片段一律按弃权计**——那正是数字静音那一段的结局（它根本不喂给模型，
// 见 `clip_yamnet.dart` 的 `kSilenceDbfs`），所以「没有行」与「弃权」在这里是同一件事。
//
// 标注文件按行写 `<片段 id> <标注>`，空行与 `#` 开头的行忽略。标注取值：
//   snore / talk / noise  —— 与 `SoundEventKind` 的 id 一致
//   -                     —— 没标过，跳过
// 从真机库里导出这个文件：
//   adb exec-out run-as com.example.night_sleep cat app_flutter/night_sleep.sqlite > db.sqlite
//   sqlite3 db.sqlite "select id, kind from sound_clips where labeled_at_utc is not null;" > labels.txt
//
// **正确率必须连同「弃权多少」一起读。** 机器靠弃权可以轻易把正确率做到 100%
// （判一段都不判），所以这个工具同时报出**覆盖率**——机器肯开口的那部分占多少。
// 单看任何一个数都会得出相反的结论。
//
// ignore_for_file: avoid_print

import 'dart:io';

import 'package:night_sleep/features/sleep/domain/clip_analysis.dart';
import 'package:night_sleep/features/sleep/domain/clip_yamnet.dart';

/// 标注 id → 机器标签。人只说「梦话」，机器只说「疑似人声」——两者对齐在这里，
/// 且只在这里：名字不同是刻意的，别为了对齐把机器的说法改成「梦话」。
const _humanToAuto = {
  'snore': AutoLabel.snore,
  'talk': AutoLabel.voice,
  'noise': AutoLabel.noise,
};

/// 可扫的两条判定线。**模型分本身不能扫**，能扫的只有拿分比哪条线。
const _sweepable = <String, String>{
  'snore': '鼾声判定线',
  'voice': '人声判定线',
};

/// 每条线扫哪些取值。**现值也在里面**，好一眼看出它在整条曲线上落在哪。
const _sweepValues = <double>[0.10, 0.20, 0.30, 0.40, 0.50, 0.70, 0.90];

Future<void> main(List<String> args) async {
  final flags = args.where((a) => a.startsWith('--')).toList();
  final positional = args.where((a) => !a.startsWith('--')).toList();
  if (positional.length < 2) {
    stderr.writeln('用法：dart run tool/eval_clips.dart <分档表> <标注文件> '
        '[--sweep=${_sweepable.keys.join("|")}]');
    exit(2);
  }

  final labels = _readLabels(File(positional[1]));
  if (labels.isEmpty) {
    stderr.writeln('标注文件里没有一条有效标注：${positional[1]}');
    exit(2);
  }

  final scores = _readScores(File(positional[0]));
  if (scores.isEmpty) {
    stderr.writeln('分档表里没有一条有效记录：${positional[0]}');
    exit(2);
  }

  final sweepNames =
      flags.where((f) => f.startsWith('--sweep=')).map((f) => f.substring(8));
  final sweep = sweepNames.isEmpty ? null : sweepNames.first;

  final evaluated = <_Case>[];
  for (final entry in scores.entries) {
    final human = labels[entry.key];
    if (human == null) continue;
    evaluated.add(_Case(
      id: entry.key,
      human: human,
      score: entry.value,
      verdict: _verdictFor(entry.value, const YamnetParams()),
    ));
  }
  if (evaluated.isEmpty) {
    stderr.writeln('分档表与标注文件对不上号：没有一个片段两边都有。');
    exit(2);
  }

  _printTable(evaluated);
  _printScore(evaluated);

  if (sweep != null) {
    final title = _sweepable[sweep];
    if (title == null) {
      stderr.writeln('不能扫的判定线：$sweep。可扫：${_sweepable.keys.join(" / ")}');
      exit(2);
    }
    _printSweep(sweep, title, scores, labels);
  }
}

/// 一段的分档与它对应的判定。
class _Case {
  _Case({
    required this.id,
    required this.human,
    required this.score,
    required this.verdict,
  });

  final String id;
  final AutoLabel human;
  final _Score score;
  final AutoVerdict? verdict;

  AutoLabel? get machine => verdict?.label;

  bool get abstained => verdict == null;

  bool get correct => machine == human;
}

/// 一段的整段均分，来自真机上的端侧测量。
class _Score {
  _Score(this.snoreMean, this.speechMean);

  final double snoreMean;
  final double speechMean;
}

/// 用**同一套**判定规则算结论——这是这个工具的全部意义所在。
///
/// 把两个均分各包成「只有一个窗口」的 [ClipScores]：只剩一窗时均分就是它自己，
/// 于是这里算出来的与设备上算出来的逐字相同，**规则只有一份实现**。
///
/// `dbfs` 传 0（= 不是静音）：静音那一段在设备上根本没喂给模型、也就没有分档行，
/// 在这里按弃权计。见文件头。
AutoVerdict? _verdictFor(_Score score, YamnetParams params) {
  return verdictFromScores(
    ClipScores(snore: [score.snoreMean], speech: [score.speechMean]),
    dbfs: 0,
    params: params,
  );
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

Map<String, _Score> _readScores(File file) {
  if (!file.existsSync()) {
    stderr.writeln('分档表不存在：${file.path}');
    exit(2);
  }
  final scores = <String, _Score>{};
  for (final raw in file.readAsLinesSync()) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final parts = line.split(RegExp(r'[\s|]+'));
    if (parts.length < 3) continue;
    final snore = double.tryParse(parts[1]);
    final speech = double.tryParse(parts[2]);
    if (snore == null || speech == null) {
      stderr.writeln('分档表这一行读不出分数，跳过：$line');
      continue;
    }
    scores[parts[0]] = _Score(snore, speech);
  }
  return scores;
}

void _printTable(List<_Case> cases) {
  print('${'片段'.padRight(22)}${'人标'.padLeft(8)}'
      '${'鼾分'.padLeft(8)}${'声分'.padLeft(8)}${'机器'.padLeft(12)}判定');
  print('-' * 78);
  for (final c in cases) {
    final mark = c.abstained ? '弃权' : (c.correct ? '✓' : '✗ 不符');
    print('${c.id.padRight(22)}'
        '${c.human.label.padLeft(8)}'
        '${c.score.snoreMean.toStringAsFixed(3).padLeft(8)}'
        '${c.score.speechMean.toStringAsFixed(3).padLeft(8)}'
        '${(c.machine?.label ?? '—').padLeft(12)}  $mark');
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

/// 扫一条判定线，打印它取各个值时的（覆盖率, 准确率, 保守正确率）。
///
/// **别只看准确率那一列。** 把门槛调严会让准确率一路升到 100%，代价是覆盖率掉到 0
/// ——那一列必须同时在眼前。
///
/// **扫出来的好数字不构成定阈值的理由**：样本不够时那叫拟合，本仓的规矩是样本不足
/// 不调参。这个表的用处是让人看见「换一条线会往哪边动」，不是让人挑最大的那一格。
void _printSweep(
  String key,
  String title,
  Map<String, _Score> scores,
  Map<String, AutoLabel> labels,
) {
  print('');
  print('扫 $title：');
  print('${'判定线'.padLeft(10)}${'开口'.padLeft(8)}${'覆盖'.padLeft(8)}'
      '${'准确'.padLeft(8)}${'保守'.padLeft(8)}  逐类命中（鼾/声/杂）');
  for (final value in _sweepValues) {
    final params = key == 'snore'
        ? YamnetParams(snoreThreshold: value)
        : YamnetParams(voiceThreshold: value);

    final cases = <_Case>[];
    for (final entry in scores.entries) {
      final human = labels[entry.key];
      if (human == null) continue;
      cases.add(_Case(
        id: entry.key,
        human: human,
        score: entry.value,
        verdict: _verdictFor(entry.value, params),
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
    print('${value.toStringAsFixed(2).padLeft(10)}'
        '${'${spoke.length}'.padLeft(8)}'
        '${coverage.padLeft(8)}${accuracy.padLeft(8)}'
        '${'${(right * 100 / cases.length).toStringAsFixed(0)}%'.padLeft(8)}'
        '  $hits');
  }
}
