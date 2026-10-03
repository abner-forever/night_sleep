/// 五条助眠音效的目录，指向打包在应用里的循环素材。
///
/// **这批素材是实景录音，不是合成的。** 2026-10-03 之前这里是一个 DSP 合成器
/// （`noise_synth.dart`：白/棕/粉噪、雨、海浪、篝火、森林、风扇八种），当时的裁定是
/// 「不打包任何第三方音频、无授权与署名负担」。使用方提供了实景录音素材后改成本文件的
/// 做法，合成器整个删掉，理由与取舍见
/// `docs/superpowers/specs/2026-10-03-noise-real-recordings-design.md`。
///
/// **授权是未了事项**：素材来自爱给网（aigei.com），仅供个人试用，**可商用授权尚未落实**。
/// 发布前必须确认或更换（同上规格 §3.1）；界面里刻意没有致谢页——那会读作授权已确认。
///
/// [id] 沿用旧值 `ocean` / `fire` / `forest`，因此旧会话里存过的这几个 id 仍然认得出；
/// 其余三个（`white` / `brown` / `pink` / `rain` / `fan`）已不存在，读到会返回 `null`，
/// 调用方按「不认识的 id」处理即可（`noise_session.dart` 冷启动对账本就会清空它们）。
library;

enum NoiseKind {
  ocean('ocean'),
  fire('fire'),
  forest('forest'),
  stream('stream'),
  wind('wind');

  const NoiseKind(this.id);

  /// 与 `kNoiseOptions` 的 `id`、以及会话表里那一列的值一一对应。
  final String id;

  /// 打包资源路径。文件名与 [id] 同名，改 id 就是改文件名。
  String get assetPath => 'assets/noise/$id.m4a';

  static NoiseKind? fromId(String id) {
    for (final kind in values) {
      if (kind.id == id) return kind;
    }
    return null;
  }
}
