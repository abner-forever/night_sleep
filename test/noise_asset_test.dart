/// 钉住打包的助眠音效素材，以及它与音效目录的一一对应。
///
/// 断言对象是**仓库里已提交的 `.m4a` 文件本身**，不是生成器的中间结果——这样任何人
/// 手改产物、或改坏生成器后重跑，都会在这里变红，而不是等到用户戴上耳机才发现。
/// 生成经过见 `docs/superpowers/specs/2026-10-03-noise-real-recordings-design.md`。
///
/// 授权提醒：素材来自爱给网（aigei.com），**可商用授权尚未落实**，见规格 §3.1。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/features/sleep/data/noise_asset.dart';
import 'package:night_sleep/features/sleep/presentation/widgets/noise_controls.dart';

void main() {
  group('素材目录', () {
    test('NoiseKind 与 kNoiseOptions 一一对应', () {
      // 双向相等，不是单向包含：多一条、少一条、id 拼错都要红。
      // 两边对不上时，界面上会出现一个点了没反应的格子（找不到对应的音），
      // 或者一个永远选不中的音（没有格）。
      final kindIds = NoiseKind.values.map((kind) => kind.id).toSet();
      final optionIds = kNoiseOptions.map((option) => option.id).toSet();
      expect(optionIds, kindIds);
      expect(NoiseKind.values, hasLength(kNoiseOptions.length));
    });

    test('每条素材都真实存在，且不是空壳', () {
      for (final kind in NoiseKind.values) {
        final file = File(kind.assetPath);
        expect(file.existsSync(), isTrue, reason: '缺少素材：${kind.assetPath}');
        // 44–75 秒的单声道 80 kbps 大约 435–800 KB；100 KB 这条只是防「写了个空壳」。
        expect(
          file.lengthSync(),
          greaterThan(100 * 1024),
          reason: '${kind.assetPath} 太小，像是空文件',
        );
      }
    });

    test('每个文件都是合法的 MPEG-4 容器', () {
      for (final kind in NoiseKind.values) {
        final bytes = File(kind.assetPath).readAsBytesSync();
        expect(bytes.length, greaterThan(12));
        // 头 4 字节是首个 box 的长度，紧接着是 box 类型；MP4/M4A 的首个 box 必是 `ftyp`。
        // 换了编码格式（比如误存成 WAV）或文件被截断都会在这里红。
        final boxType = String.fromCharCodes(bytes.sublist(4, 8));
        expect(boxType, 'ftyp', reason: '${kind.assetPath} 不是 MPEG-4 容器');
      }
    });

    test('素材总占用落在预期区间', () {
      final total = NoiseKind.values
          .map((kind) => File(kind.assetPath).lengthSync())
          .fold<int>(0, (sum, size) => sum + size);
      final mb = total / 1024 / 1024;
      // 实测 3.40 MB。区间给得宽，只挡「误把 320 kbps 的原始 MP3 打进来」（约 48 MB）
      // 或「素材被清空」这两种事故，不挡正常的重新生成。
      expect(mb, greaterThan(3.0));
      expect(mb, lessThan(3.8));
    });

    test('assetPath 由 id 推出，且都在 assets/noise/ 下', () {
      for (final kind in NoiseKind.values) {
        expect(kind.assetPath, 'assets/noise/${kind.id}.m4a');
      }
    });
  });
}
