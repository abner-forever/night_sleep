import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:night_sleep/features/sleep/data/noise_player.dart';
import 'package:night_sleep/features/sleep/data/noise_synth.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 真的合成一段助眠音、落盘、交给播放器。
///
/// **为什么必须跑在真设备上**：`NoisePlayer` 那条路径（DSP → 写临时目录 →
/// `just_audio` 播放）整条都在平台侧。widget 测试用的是假播放器，一步都走不到；
/// 巡检脚本虽然会打开白噪音弹窗，但只开不选，也走不到。2026-10-03 在 macOS 上
/// 撞见的 `PathNotFoundException` 就是这么漏出去的：弹窗开开关关几十次都没事，
/// 直到有人真的点了一个音。
///
/// 钉住的是这条平台事实：`getTemporaryDirectory()` 在 macOS 上返回
/// `~/Library/Caches/<bundle id>`，而 `path_provider_foundation` 只保证
/// `getApplicationSupportDirectory()` / `getApplicationCacheDirectory()` 会顺手
/// 建目录，**temp 这一支不建**。全新安装上那个目录并不存在，往里写就是 ENOENT——
/// 所以 `_ensureFile` 必须先 `create(recursive: true)`。
///
/// 跑法（桌面最快，不必开模拟器）：
/// ```bash
/// flutter drive \
///   --driver=test_driver/integration_test.dart \
///   --target=integration_test/noise_playback_test.dart \
///   -d macos
/// ```
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('选中一个音后真的落盘并开始播放', (tester) async {
    final directory = await getTemporaryDirectory();
    // 目录**可能**已经存在（这个音之前播放过就建下了），所以这里只把它打出来，
    // 好让失败信息里带着「到底是哪个路径、当时在不在」。
    // ignore: avoid_print
    print('TMP=${directory.path} exists=${directory.existsSync()}');

    final player = NoisePlayer();
    addTearDown(player.dispose);

    // 音量 0：只走路径，不在跑测试的机器上出声。
    await player.play(NoiseKind.fan, volume: 0);

    expect(player.current, NoiseKind.fan);
    final file = File(p.join(directory.path, 'noise-fan.wav'));
    expect(file.existsSync(), isTrue, reason: '合成结果没落盘：${file.path}');
    // 20 秒 22.05kHz 单声道 16 位 ≈ 860 KB；这条只是防「写了个空壳」。
    expect(file.lengthSync(), greaterThan(1000));

    // 取消选择要把播放器和状态一起收干净，别只停声音。
    await player.stop();
    expect(player.current, isNull);
  });
}
