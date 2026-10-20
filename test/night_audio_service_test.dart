import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/core/platform/night_audio_service.dart';

/// `MethodChannelNightAudioService` 的**解码**那一半。
///
/// 平台通道用 `setMockMethodCallHandler` 假应答：**不碰真平台、不碰真服务**，
/// 测的是「Kotlin 侧回什么码，Dart 侧认成什么结果」——那正是两侧唯一靠约定对齐的
/// 地方，也是错一处就静默走错分支的地方。
///
/// 为什么测试里走得到这条通道：`defaultTargetPlatform` 在测试环境里**一律报
/// android**（`package:flutter/src/foundation/platform.dart` 的文档原话），
/// 所以平台闸口不会把它拦在 `unsupported` 上。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const service = MethodChannelNightAudioService();
  const channel = MethodChannel(MethodChannelNightAudioService.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// 装一个应答器。`handler` 抛 `PlatformException` 就等价于平台侧回了 error 信封。
  void answer(Object? Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(channel, (call) async => handler(call));
  }

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  group('结果码解码', () {
    test('四个码各解成自己的结果', () async {
      const table = {
        'started': NightAudioServiceResult.started,
        'notForeground': NightAudioServiceResult.notForeground,
        'missingPermission': NightAudioServiceResult.missingPermission,
        'failed': NightAudioServiceResult.failed,
      };
      for (final entry in table.entries) {
        answer((call) => entry.key);
        expect(await service.start(), entry.value, reason: entry.key);
      }
    });

    test('认不出来的码一律 failed，不猜', () async {
      // 猜错的方向是「以为服务起来了、其实没有」，那会连着开一个收不到声音的麦克风，
      // 而界面写着「录音中」。
      answer((call) => 'recording_started_maybe');
      expect(await service.start(), NightAudioServiceResult.failed);

      // 回了个空的成功信封（Kotlin 侧不会这么干，但真到了这一步也不能当成已起来）。
      answer((call) => null);
      expect(await service.start(), NightAudioServiceResult.failed);
    });

    test('平台侧回 error 信封 → failed', () async {
      answer((call) => throw PlatformException(code: 'boom'));
      expect(await service.start(), NightAudioServiceResult.failed);
    });

    test('这条通道没人应答 → unsupported，不把录音拦下来', () async {
      // **裸字节层面回 null**，也就是「这条通道在本平台不存在」——`MethodChannel`
      // 收到 null 会抛 `MissingPluginException`。iOS 上、以及 widget 测试里
      // 没有平台通道时会走的都是这一条。漏了它，测试里的夜间录音会被全数拦下，
      // 表现成「录音永远起不来」。
      messenger.setMockMessageHandler(channel.name, (message) async => null);
      expect(await service.start(), NightAudioServiceResult.unsupported);
      // 撤服务那一路同样不许抛：收尾那一段后面还有「把已经录到的片段写进清单」。
      await service.stop();
    });

    test('start 走的是 start、stop 走的是 stop 这两个 method', () async {
      final called = <String>[];
      answer((call) {
        called.add(call.method);
        return 'started';
      });

      await service.start();
      await service.stop();

      expect(called, ['start', 'stop']);
    });
  });

  group('平台闸口', () {
    test('非 Android 上一个请求都不发，直接 unsupported', () async {
      var calls = 0;
      answer((call) {
        calls++;
        return 'started';
      });

      // iOS 上根本没有这条通道。真要调一次也能拿到 MissingPluginException，但那一次
      // 多余往返是每次起录都要付的，所以在本地按平台挡住。
      for (final platform in const [TargetPlatform.iOS, TargetPlatform.macOS]) {
        debugDefaultTargetPlatformOverride = platform;
        expect(await service.start(), NightAudioServiceResult.unsupported);
        await service.stop();
      }
      expect(calls, 0, reason: '拦在本地就够了，不必让平台往返一趟才知道它没有');
    });
  });

  group('空实现', () {
    test('unsupported —— 调用方据此照旧开流', () async {
      const noop = NoopNightAudioService();
      expect(await noop.start(), NightAudioServiceResult.unsupported);
      await noop.stop();
    });
  });
}
