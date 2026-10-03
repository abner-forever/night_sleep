import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:night_sleep/features/sleep/data/noise_asset.dart';
import 'package:night_sleep/features/sleep/data/noise_player.dart';

/// 真的把一条**打包素材**交给平台解码并起播。
///
/// **为什么必须跑在真设备上**：`NoisePlayer.play()` 走的是 `setAsset` → 资源包读文件 →
/// 平台解码器 → 播放器起播，整条都在平台侧。widget 测试用的是假播放器，一步都走不到；
/// 巡检脚本虽然会打开白噪音弹窗，但只开不选，也走不到。
///
/// 2026-10-03 之前这条测试钉的是「合成的 WAV 有没有落盘」——当时素材是**运行时合成**的，
/// 撞见过 `getTemporaryDirectory()` 不建目录导致的 `PathNotFoundException`。改打包录音之后
/// 那条路径整个消失，这条测试改钉新的平台事实：**`assets/noise/` 里的素材真的能被
/// 解码器打开**。资源没打进包、路径写错、编解码器不支持——三种错都只有在这里才看得见。
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

  testWidgets('打包的助眠音效真的能被解码并起播', (tester) async {
    final player = NoisePlayer();
    addTearDown(player.dispose);

    // 音量 0：只走路径，不在跑测试的机器上出声。
    await player.play(NoiseKind.forest, volume: 0);
    expect(player.current, NoiseKind.forest);

    // `setAsset` 返回即代表资源被读进来了，但「读进来」不等于「解码器接受了」。
    // 等播放器报 `ready`：这一步只有平台解码成功才会发生。
    final ready = await player.stateStream
        .firstWhere((state) =>
            state.processingState == ProcessingState.ready ||
            state.processingState == ProcessingState.completed)
        .timeout(const Duration(seconds: 10));
    expect(
      ready.processingState,
      anyOf(ProcessingState.ready, ProcessingState.completed),
      reason: '资源没能解码到可播状态：${ready.processingState}',
    );

    // 取消选择要把播放器和状态一起收干净，别只停声音。
    await player.stop();
    expect(player.current, isNull);
  });
}
