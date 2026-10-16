// 跑模型那一半：载入 `yamnet.tflite`、把一段波形逐窗打成两类分数。
//
// 判定规则**不在这个文件里**——那在 `domain/clip_yamnet.dart`，因为它必须能在
// `flutter test` 里被完整钉死，而这里的一切（原生库、模型文件）在单测环境里都不存在。
//
// 这个文件也**不读 WAV、不碰数据库**：它拿到的已经是归一化好的 `[−1, 1]` 浮点采样。
// 读文件在 `clip_analyzer.dart` 里，与 `wav_file.dart` 的分工一致。

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../domain/clip_yamnet.dart';

/// 模型在包里的路径。只有这一处写它——`pubspec.yaml` 的 `assets/model/` 与之对应。
///
/// **这个文件是提交进仓库的**（4,126,810 字节）。它的许可证官方至今没有正面声明，
/// 照 `assets/noise/` 的先例记成发布阻塞项，见 README「未实现」表与
/// `docs/superpowers/specs/2026-10-16-snore-detection-approaches-design.md` §5.3。
const String kYamnetAssetPath = 'assets/model/yamnet.tflite';

/// 打分的接缝。**真实现跑模型，测试注入假分数**——这是让整条分析管线在
/// `flutter test` 里有覆盖的唯一办法（原生库在单测环境里加载不了）。
///
/// 实现是**有状态**的（真实现手里是一个 interpreter），所以用完要 [dispose]。
abstract class ClipScorer {
  /// 逐窗打分。**读不出来 / 跑不动就抛异常**，由调用方接住并如实记成失败。
  ///
  /// [sampleRate] 是显式传的，不是常量：模型只吃 16 kHz，而采样率来自文件头
  /// （`wav_file.dart` 那条「不是假定 16000」）。对不上就该炸，不该静默算错。
  ClipScores score(Float64List samples, int sampleRate);

  void dispose();
}

/// 造一个打分器。**必须是顶层函数或纯数据闭包**——它会被送进 `Isolate.run`，
/// 而顶层变量在新 isolate 里是各自一份，捕获不进去的东西在那边就是没有。
typedef ClipScorerFactory = ClipScorer Function(Uint8List modelBytes);

/// 把模型从打包资源里读出来。**只能在主 isolate 调**：
/// `rootBundle` 要走平台通道，后台 isolate 收不到（Flutter 官方 isolates 文档明说
/// 后台 isolate 不能接收平台主动推来的消息）。读到的字节再跟着批处理送进 isolate。
Future<Uint8List> loadYamnetModelBytes() async {
  final data = await rootBundle.load(kYamnetAssetPath);
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

/// 默认的 [ClipScorerFactory]。
ClipScorer createYamnetScorer(Uint8List modelBytes) => YamnetScorer(modelBytes);

/// [ClipScorer] 的 TFLite 实现。
///
/// 三件从 2026-10-16 那次端侧探针上原样带过来的事实（都是实测撞出来的，不是猜的）：
///
///  1. **输入张量的形状是 `[15600]`（rank-1），喂一个扁平的 `Float32List` 正好**；
///  2. **输出是 `[1, 521]`，必须喂嵌套一层、而且里层要用 `List<double>`**。
///     给 `[Float32List(521)]` 会在回填那一步抛
///     「type 'List<double>' is not a subtype of type 'Float32List'」；
///  3. **模型自己在图内算频谱**（`RFFT2D` + `COMPLEX_ABS` + `LOG`，16 个算子全是
///     builtin、没有 `custom_code`），所以**不需要 Flex delegate、不需要
///     `AudioSpectrogram` / `Mfcc` 那两个自定义算子、Dart 侧也不用自己算 mel**。
///     这也是官方输入规格写 `1 × 15600` 而不是「mel 谱图」的原因——预处理装在模型里了。
class YamnetScorer implements ClipScorer {
  YamnetScorer(Uint8List modelBytes)
      : _interpreter = Interpreter.fromBuffer(modelBytes);

  final Interpreter _interpreter;

  /// 输入容器复用。**每一窗都要先清干净再填**：上一窗的尾巴留在里面，
  /// 短片段（补零那一支）就会拿上一段的音频去算。
  final Float32List _input = Float32List(kYamnetWindowSamples);

  /// 输出容器复用。理由同上，且 `run` 会按形状递归回填它。
  final List<List<double>> _output = [
    List<double>.filled(kYamnetClassCount, 0),
  ];

  @override
  ClipScores score(Float64List samples, int sampleRate) {
    if (sampleRate != kYamnetSampleRate) {
      throw UnsupportedError(
        'YAMNet 只吃 $kYamnetSampleRate Hz，这段是 $sampleRate Hz',
      );
    }

    final starts = yamnetWindowStarts(samples.length);
    if (starts.isEmpty) {
      throw const FormatException('没有任何采样点，跑不出窗口');
    }

    final snore = <double>[];
    final speech = <double>[];
    for (final start in starts) {
      final end = start + kYamnetWindowSamples;
      _input.fillRange(0, kYamnetWindowSamples, 0);
      for (var i = start; i < end && i < samples.length; i++) {
        _input[i - start] = samples[i];
      }
      _interpreter.run(_input, _output);
      snore.add(_output[0][kSnoringIndex]);
      speech.add(_output[0][kSpeechIndex]);
    }
    return ClipScores(snore: snore, speech: speech);
  }

  @override
  void dispose() => _interpreter.close();
}
