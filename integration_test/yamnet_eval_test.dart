// 端侧测量：用**生产用的那个打分器**把手机上真实录到的片段跑一遍，落两份产出。
//
// 回答三个问题，一个都不能靠推断答：
//
//  1. **模型在这台手机上跑得动吗、一晚要多久、吃多少内存**——4 MB 的体积不是问题，
//     但「跑得动」与「跑得合适」是两件事，而录音期间不许卡界面。
//  2. **端侧算出来的分与桌面离线复算是不是同一个数**——不同就是有一边错了。
//  3. **每段真实录音的整段均分是多少**——那是 `tool/eval_clips.dart` 算正确率的原料：
//     没有这个文件，那一半「用数字收账」的规矩就落不了地。
//
// 它刻意**只测量、不判定、不写库**：判定规则在 `clip_yamnet.dart` 里由单测钉死，
// 这里只产出分数。这样这个测试跑多少次、在哪台机器上跑，都改不了库里的任何东西。
//
// 跑法：
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/yamnet_eval_test.dart -d <serial>
//   adb exec-out run-as com.example.night_sleep cat files/yamnet_scores.txt > scores.txt
//
// 它读的是**手机上真实录到的片段**（`getApplicationSupportDirectory()/clips/`），
// 不是打包进来的样本——所以它量到的就是使用方那个房间、那台手机上的东西。

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:night_sleep/features/sleep/data/wav_file.dart';
import 'package:night_sleep/features/sleep/data/yamnet_scorer.dart';
import 'package:night_sleep/features/sleep/domain/clip_analysis.dart';
import 'package:night_sleep/features/sleep/domain/clip_yamnet.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('YAMNet 端侧：加载耗时 / 逐窗推理耗时 / 内存 / 逐段均分', (tester) async {
    final report = StringBuffer();
    // **分档表**：`<片段 id>\t<snore 均分>\t<speech 均分>`，喂给 `tool/eval_clips.dart`。
    // 表里没有的片段一律按弃权计——静音那一段就是如此（见下）。
    final scores = StringBuffer();
    void say(String line) {
      report.writeln(line);
      debugPrint(line);
    }

    // **无论成败都落盘。** 第一次真机跑就撞在这上面：`debugPrint` 在 `flutter drive`
    // 的输出里根本不出现，而中途抛异常时末尾那次 `_save` 也走不到——一趟 7 分钟的
    // 构建只换来一句类型错误，前面量到的数全丢了。
    addTearDown(() {
      _save('yamnet_report.txt', report.toString());
      // **分档表为空就一个字都不写。** 一个 0 字节的文件与「所有片段都弃权」在
      // `tool/eval_clips.dart` 眼里长得一样（都读不出记录），而前者的真相是
      // 「什么也没量到」——那种含糊正是这个仓最挡的。
      if (scores.isNotEmpty) _save('yamnet_scores.txt', scores.toString());
    });

    say('== YAMNet 端侧测量 ==');
    say('时间 ${DateTime.now().toIso8601String()}');
    say('设备 ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
    say('RSS 起始 ${_rssMb()} MB');

    // ── 模型：从**打包进 APK 的 asset** 读 ──
    //
    // 一开始走的是「adb push 到 App 的外部私有目录」，**真机上撞死了**：`flutter drive`
    // 每跑一次都会把 `Android/data/<包名>` 整个清掉（同一个 APK 再跑一次也照样清），
    // 于是模型在测试开始前就没了。打进 APK 才不受这条影响。
    final loadWatch = Stopwatch()..start();
    final modelBytes = await loadYamnetModelBytes();
    final scorer = createYamnetScorer(modelBytes);
    loadWatch.stop();
    say('模型 ${modelBytes.length} 字节 '
        '(${(modelBytes.length / 1024 / 1024).toStringAsFixed(2)} MiB)');
    say('加载耗时 ${loadWatch.elapsedMilliseconds} ms（含 asset 解码与建解释器）');
    say('RSS 加载后 ${_rssMb()} MB');
    // **模型接口核对**：这一条确认的是「不用在 Dart 侧自己算 mel」那句结论。
    // 形状对不上就说明拿错了模型文件，后面所有的分数都没有意义。
    say('输入 $kYamnetWindowSamples 点 = '
        '${(kYamnetWindowSamples / kYamnetSampleRate).toStringAsFixed(3)} 秒');
    say('输出 $kYamnetClassCount 类，Snoring=$kSnoringIndex / Speech=$kSpeechIndex');
    say('');

    // ── 片段：手机上真实录到的那些 ──
    final support = await getApplicationSupportDirectory();
    final clipsDir = Directory(path.join(support.path, 'clips'));
    final wavs = clipsDir.existsSync()
        ? (clipsDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.toLowerCase().endsWith('.wav'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path)))
        : <File>[];

    // **一段真实录音都没有时，退到合成信号上量耗时。**
    //
    // 这一步只回答「模型在这台手机上跑得动吗」，**不是**在测判定准不准：
    // 合成信号不对应任何真实声音，它算出来的分没有任何含义。所以这条路上
    // **一行分档表都不写**——那份表必须只装真实录音，否则 `tool/eval_clips.dart`
    // 会拿一堆合成噪声去和人的标注对账。
    //
    // 为什么要有这条路：`flutter drive` 每次跑完都会把应用卸掉，所以「先手动塞几段
    // WAV 进去、再跑一次」是不成立的；而手机上现在确实一段录音都没有（应用是刚装上的）。
    // 不这么做的话，「推理耗时在手机上有没有读数」会永远留在未验证里。
    if (wavs.isEmpty) {
      say('**片段目录里一段真实录音都没有**'
          '（${clipsDir.path}${clipsDir.existsSync() ? '' : '，目录都还不存在'}）。');
      say('退到合成信号上量耗时——这一段只量「跑不跑得动」，'
          '**不算任何正确率**，也不写分档表。');
      say('');
      say('${'合成信号'.padRight(28)}${'时长'.padLeft(8)}${'窗数'.padLeft(6)}'
          '${'均(ms)'.padLeft(9)}${'中位'.padLeft(8)}${'最慢'.padLeft(8)}'
          '   备注');

      final probeRuns = <int>[];
      var probeWindows = 0;
      for (final seconds in [1.0, 3.0, 10.0, 30.0]) {
        final samples = _probeSignal(seconds);
        final watch = Stopwatch()..start();
        final scored = scorer.score(samples, kYamnetSampleRate);
        watch.stop();
        final windows = scored.windowCount;
        probeRuns.add(watch.elapsedMicroseconds);
        probeWindows += windows;
        say('${'${seconds.toStringAsFixed(1)} 秒'.padRight(28)}'
            '${'${seconds.toStringAsFixed(1)}s'.padLeft(8)}'
            '${windows.toString().padLeft(6)}'
            '${(watch.elapsedMicroseconds / windows / 1000).toStringAsFixed(1).padLeft(9)}'
            '${'一段'.padLeft(8)}'
            '${'${watch.elapsedMilliseconds}ms'.padLeft(8)}'
            '   合成，分无意义');
      }
      final perWindow = probeRuns.reduce((a, b) => a + b) / probeWindows / 1000;
      say('');
      say('== 汇总（**合成信号**，只量耗时）==');
      say('窗口合计 $probeWindows，折成一窗 ${perWindow.toStringAsFixed(1)} ms，'
          '即 ${(1000 / perWindow).toStringAsFixed(1)} 窗/秒、'
          '${(kYamnetHopSamples / kYamnetSampleRate * 1000 / perWindow).toStringAsFixed(1)} 倍实时');
      say('按本机实测密度（一晚 223 秒音频 ≈ 458 窗）推算：'
          '${(perWindow * 458 / 1000).toStringAsFixed(1)} 秒');
      say('RSS 结束 ${_rssMb()} MB');
      say('');
      say('**未验证**：真实录音上的分数、端侧与桌面离线是否同一个数——'
          '这一轮手机上一段录音都没有。');
      scorer.dispose();
      return;
    }

    say('片段目录里 ${wavs.length} 个 WAV');
    say('');
    say('${'文件'.padRight(28)}${'时长'.padLeft(8)}${'窗数'.padLeft(6)}'
        '${'均(ms)'.padLeft(9)}${'中位'.padLeft(8)}${'最慢'.padLeft(8)}'
        '   snore / speech 均分');

    final allRuns = <int>[];
    var scored = 0;
    var silent = 0;
    var unreadable = 0;
    var totalAudioSeconds = 0.0;

    for (final wav in wavs) {
      final id = path.basenameWithoutExtension(wav.path);
      final audio = await readWavFile(wav.path);
      if (audio == null || audio.isEmpty) {
        unreadable++;
        say('${path.basename(wav.path).padRight(28)}  读不出来，跳过');
        continue;
      }
      if (audio.sampleRate != kYamnetSampleRate) {
        unreadable++;
        say('${path.basename(wav.path).padRight(28)}  采样率 '
            '${audio.sampleRate} != $kYamnetSampleRate，跳过');
        continue;
      }

      // **与 App 里同一道闸**：数字静音不喂给模型。这里照做，好让这份分档表
      // 与 `ClipAnalyzer` 眼里的世界一致——静音那段在两边的结局都是「没有行/弃权」。
      final dbfs = rmsDbfs(audio.samples);
      if (dbfs < kSilenceDbfs) {
        silent++;
        say('${path.basename(wav.path).padRight(28)}  '
            '${dbfs.toStringAsFixed(1)} dBFS 是数字静音，不喂给模型');
        continue;
      }

      final watch = Stopwatch()..start();
      final clipScores = scorer.score(audio.samples, audio.sampleRate);
      watch.stop();

      final perWindow = clipScores.windowCount;
      allRuns.add(watch.elapsedMicroseconds);
      totalAudioSeconds += audio.samples.length / kYamnetSampleRate;
      scored++;

      final snoreMean = meanScore(clipScores.snore);
      final speechMean = meanScore(clipScores.speech);
      scores.writeln('$id\t${snoreMean.toStringAsFixed(4)}\t'
          '${speechMean.toStringAsFixed(4)}');

      final perWindowMean =
          watch.elapsedMicroseconds / perWindow / 1000; // 一窗多少毫秒
      say('${path.basename(wav.path).padRight(28)}'
          '${'${(audio.samples.length / kYamnetSampleRate).toStringAsFixed(1)}s'.padLeft(8)}'
          '${perWindow.toString().padLeft(6)}'
          '${perWindowMean.toStringAsFixed(1).padLeft(9)}'
          '${'一段'.padLeft(8)}'
          '${'${watch.elapsedMilliseconds}ms'.padLeft(8)}'
          '   ${snoreMean.toStringAsFixed(3)} / '
          '${speechMean.toStringAsFixed(3)}');
    }

    if (allRuns.isEmpty) {
      say('一段都没跑成（读不出来 $unreadable，静音 $silent）');
      fail('no clips scored');
    }

    final sortedAll = [...allRuns]..sort();
    // **一窗多少毫秒**才是有意义的那个数：片段的长度千差万别，整段耗时直接平均
    // 只会把「长片段的耗时」算成「模型慢」。一窗的耗时与片段长度无关。
    final totalWindows = <int>[];
    for (final wav in wavs) {
      final audio = await readWavFile(wav.path);
      if (audio == null || audio.isEmpty) continue;
      totalWindows.add(yamnetWindowStarts(audio.samples.length).length);
    }
    final windowCount = totalWindows.fold<int>(0, (a, b) => a + b);

    say('');
    say('== 汇总 ==');
    say('片段 ${wavs.length}：跑成 $scored，数字静音 $silent，读不出来 $unreadable');
    say('音频合计 ${totalAudioSeconds.toStringAsFixed(1)} 秒、'
        '窗口合计 $windowCount');
    say('逐段推理：均 ${(allRuns.reduce((a, b) => a + b) / allRuns.length / 1000).toStringAsFixed(1)} ms / 中位 ${sortedAll[sortedAll.length ~/ 2] / 1000} ms '
        '/ 最慢 ${sortedAll.last / 1000} ms');
    final perWindowAll = allRuns.reduce((a, b) => a + b) / windowCount / 1000;
    say('折成一窗 ${perWindowAll.toStringAsFixed(1)} ms，'
        '即 ${(1000 / perWindowAll).toStringAsFixed(1)} 窗/秒、'
        '${(kYamnetHopSamples / kYamnetSampleRate * 1000 / perWindowAll).toStringAsFixed(1)} 倍实时');
    // 一晚的推算：27 段 / 223 秒真实数据 → 约 46 窗/段，见验证记录 v3.35。
    say('按本机实测密度（一晚 223 秒音频 ≈ 458 窗）推算：'
        '${(perWindowAll * 458 / 1000).toStringAsFixed(1)} 秒');
    say('RSS 结束 ${_rssMb()} MB');
    say('');
    say('分档表已写出 ${scores.toString().trim().split('\n').length} 行——'
        '取回之后 `dart run tool/eval_clips.dart <scores.txt> <labels.txt>`');

    scorer.dispose();
  });
}

/// 一段**合成**信号，只用来量推理耗时。
///
/// 用定种子的伪随机噪声而不是正弦：噪声每一窗的谱都不同，比一段纯音更像「真实音频
/// 会让模型干什么活」。**但它的分数没有任何意义**——见调用处那段注释。
Float64List _probeSignal(double seconds) {
  final rng = math.Random(20261016);
  final n = (kYamnetSampleRate * seconds).round();
  final out = Float64List(n);
  var previous = 0.0;
  for (var i = 0; i < n; i++) {
    // 一点点低通，免得整段都是白噪声那种最坏情况。
    previous = 0.7 * previous + 0.3 * (rng.nextDouble() * 2 - 1);
    out[i] = 0.3 * previous;
  }
  return out;
}

String _rssMb() => (ProcessInfo.currentRss / 1024 / 1024).toStringAsFixed(1);

/// 报告写进 App 的**内部**目录，跑完用 `run-as` 取：
///   adb exec-out run-as com.example.night_sleep cat files/yamnet_scores.txt
///
/// **不用外部私有目录**：真机上实测 `addTearDown` 里那次 `getExternalStorageDirectory()`
/// 拿不到目录（测试失败后平台通道已经拆了），异常还被这里的 catch 吞掉，报告凭空消失。
/// 内部目录在 `addTearDown` 里照样写得进去（`getApplicationSupportDirectory` 不依赖
/// 那次拆解），两条路径都试一遍，哪条成了写在哪条。
///
/// **`adb` 的取法只能用 `exec-out`**：`adb shell cat > 文件` 会把 CRLF 和编码搞坏，
/// 拉二进制更是会弄出一个损坏的文件——验证记录 v3.19 与 v3.35 各踩过一次。
Future<void> _save(String name, String content) async {
  final tried = <String>[];
  for (final entry in <(String, Future<Directory?> Function())>[
    ('support', getApplicationSupportDirectory),
    ('external', getExternalStorageDirectory),
  ]) {
    final (label, resolve) = entry;
    try {
      final dir = await resolve();
      if (dir == null) {
        tried.add('$label: null');
        continue;
      }
      final file = File(path.join(dir.path, name));
      await file.writeAsString(content);
      debugPrint('已写入 $label ${file.path}');
      return;
    } catch (error) {
      tried.add('$label: $error');
    }
  }
  debugPrint('$name 写不进去：${tried.join(' | ')}');
}
