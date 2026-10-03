/// 由实景录音源素材生成 `assets/noise/` 下的五条循环素材。
///
/// 跑法（需要 `ffmpeg` 在 PATH 上）：
///
/// ```bash
/// dart run tool/generate_noise_assets.dart [源素材目录]
/// ```
///
/// 源素材目录默认 `~/Downloads/白噪音素材`。**只在这里手动跑**——它改文件，
/// 不该混进 `flutter test`（与 `tool/generate_app_icons.dart` 同一条理由）。
///
/// ## 素材出处与授权
///
/// 源文件来自**爱给网（aigei.com）**，由使用方于 2026-10-03 提供，**仅供个人试用，
/// 可商用授权尚未落实**。发布前必须确认授权或更换素材，见
/// `docs/superpowers/specs/2026-10-03-noise-real-recordings-design.md` §3.1。
/// 界面里刻意没有「素材来源」页——那会读作授权已确认。
///
/// ## 为什么是这条滤镜链
///
/// 三处写错会**静默出错**（不报错、听不出、量一下才知道），逐条记在这里：
///
///  * **`asplit=3` 不能省。** 把 `loudnorm` 的输出直接写成三条分支时，响度归一
///    **静默失效**——实测成品停在输入的 −35.6 LUFS。显式 `asplit` 后才是 −20.1。
///  * **接缝是「把循环点**之后**的延续折回开头」**，不是「把尾巴淡入开头」。后者会把一个
///    天然前驱是 `L-1` 的样本接到 `L+fade` 之后，要消除的那个阶跃仍在（同 `_foldSeam`）。
///  * **`loudnorm` 的 `TP` 要留 2 dB 给交叉淡化。** 等功率淡化叠加两路信号时峰值会抬升
///    1–2 dB；取 `TP=-1.5` 成品会顶到 0 dBFS，取 `TP=-3` 才落在 −1.9 ~ −3.0。
library;

import 'dart:io';

/// 一条素材的生成参数。源文件名里带中文与全角标点，逐字照抄。
class _Recipe {
  const _Recipe({
    required this.id,
    required this.source,
    required this.loopSeconds,
    required this.targetLufs,
  });

  /// 目标文件名（不带扩展名），与 `NoiseKind.id` 相同。
  final String id;

  /// 源素材文件名。
  final String source;

  /// 循环长度（秒）。`ffmpeg` 会再往后取 2 秒做接缝交叉淡化，所以源必须 ≥ 长度 + 2。
  final int loopSeconds;

  /// 响度归一目标（LUFS）。
  ///
  /// 多数是 −22；**篝火单独用 −19**——它的源里有一段近乎静音加一声 0 dBFS 的爆裂
  /// （峰均比 38.6 dB），动态归一对它**稳定欠冲约 2.9 LU**，按文件预补偿后才落到同量级。
  /// 这个常数是量出来的，不是猜的。
  final int targetLufs;
}

const _fadeSeconds = 2;

/// 归一时的真峰上限。留 2 dB 余量给接缝淡化（见文件头）。
const _normalisePeakDb = -3;

const _recipes = <_Recipe>[
  _Recipe(
    id: 'forest',
    source: '1、《霖落林海听声》大自然实景录制白噪音I原生态音效I森林鸟_爱给网_aigei_com.mp3',
    loopSeconds: 75,
    targetLufs: -22,
  ),
  _Recipe(
    id: 'fire',
    source: '篝火噼啪声-环境音-冬季_爱给网_aigei_com.mp3',
    loopSeconds: 71,
    targetLufs: -19,
  ),
  _Recipe(
    id: 'ocean',
    source: '海风海浪声；海浪拍打礁石；大海氛围音效。真实场景录制，冰葡萄_爱给网_aigei_com.mp3',
    loopSeconds: 75,
    targetLufs: -22,
  ),
  _Recipe(
    id: 'stream',
    source: '溪水声；河水声；大自然氛围音效；小河流水哗啦啦；溪水流淌叮咚_爱给网_aigei_com.mp3',
    loopSeconds: 75,
    targetLufs: -22,
  ),
  _Recipe(
    id: 'wind',
    source: '大自然风声；田野风声；窗外风声；室外风声；秋风瑟瑟；马路上的_爱给网_aigei_com.mp3',
    loopSeconds: 44,
    // 风的目标比其余各条低 1 LU：它峰均比最低（17.6 dB），同样的目标会**过冲**，
    // 落到 −21.3——比别的条都响。压 1 dB 后才与其他四条齐平。
    targetLufs: -23,
  ),
];

/// 输出：`assets/noise/`，AAC-LC 单声道 22.05 kHz 80 kbps。
const _sampleRate = 22050;
const _bitrate = '80k';

String _filterGraph(_Recipe recipe) {
  final loop = recipe.loopSeconds;
  final span = loop + _fadeSeconds;
  const fade = _fadeSeconds;

  // 逐段说明见文件头。`[m1]` 取头做淡出、`[m2]` 取循环点**之后**的延续做淡入、
  // `[m3]` 是去掉被淡化那段的其余主体。
  return '[0:a]atrim=0:$span,asetpts=N/SR/TB,'
      'aformat=channel_layouts=mono,aresample=$_sampleRate,'
      'loudnorm=I=${recipe.targetLufs}:TP=$_normalisePeakDb:LRA=11,asplit=3[m1][m2][m3];'
      '[m1]atrim=0:$fade,asetpts=N/SR/TB,afade=t=out:st=0:d=$fade:curve=qsin[head];'
      '[m2]atrim=$loop:$span,asetpts=N/SR/TB,afade=t=in:st=0:d=$fade:curve=qsin[cont];'
      '[head][cont]amix=inputs=2:duration=longest:normalize=0[blend];'
      '[m3]atrim=$fade:$loop,asetpts=N/SR/TB[body];'
      '[blend][body]concat=n=2:v=0:a=1[out]';
}

Future<void> main(List<String> args) async {
  final sourceDir = args.isNotEmpty
      ? args.first
      : '${Platform.environment['HOME']}/Downloads/白噪音素材';
  final outDir = Directory('assets/noise');

  if (!Directory(sourceDir).existsSync()) {
    stderr.writeln('源素材目录不存在：$sourceDir');
    stderr.writeln('用法：dart run tool/generate_noise_assets.dart [源素材目录]');
    exit(2);
  }
  outDir.createSync(recursive: true);

  for (final recipe in _recipes) {
    final source = File('$sourceDir/${recipe.source}');
    if (!source.existsSync()) {
      stderr.writeln('源素材缺失：${source.path}');
      exit(2);
    }
    final out = File('${outDir.path}/${recipe.id}.m4a');
    final result = await Process.run('ffmpeg', [
      '-y',
      '-v',
      'error',
      '-i',
      source.path,
      '-filter_complex',
      _filterGraph(recipe),
      '-map',
      '[out]',
      '-c:a',
      'aac',
      '-b:a',
      _bitrate,
      '-ar',
      '$_sampleRate',
      '-ac',
      '1',
      out.path,
    ]);
    if (result.exitCode != 0) {
      stderr.writeln('生成 ${recipe.id} 失败：\n${result.stderr}');
      exit(1);
    }
    final kb = (out.lengthSync() / 1024).round();
    // ignore: avoid_print
    print(
        '${recipe.id.padRight(7)} ${recipe.loopSeconds}s  ${kb}KB  → ${out.path}');
  }
}
