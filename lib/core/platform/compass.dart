import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../features/compass/domain/compass_heading.dart';

/// 罗盘读数的来源。
///
/// **「不可用」有两种，原因不同，说法也必须不同**——`CompassPage` 对这两种
/// 早有各自的分支，所以它一个字都不用改：
///
/// - **平台还没实现**：本类直接返回 [CompassUnavailable]，
///   页面照搬它的 `message`。
/// - **设备没有传感器**：由**原生侧**发 `FlutterError(code: "unavailable")`，
///   页面把它映射成「此设备没有可用的罗盘传感器」。Android 与 iOS 走同一条
///   （`EventChannel` 把原生的错误信封解成 `PlatformException`，**code 原样保留**，
///   见 `package:flutter/src/services/platform_channel.dart` 的 `receiveBroadcastStream`）。
///
/// v3.11 时这两条被合成了一句写死的「请使用支持罗盘的 **iPhone** 打开此页面」。
/// 那句话在 Android 上是一句**假话**：机器有磁力计（真机实测 `ak0991x`），
/// 是我们没去读它。把一个「我们没做」说成「你的设备不行」，是这里最不该犯的错。
class CompassSource {
  const CompassSource();

  /// 平台未实现时的说法。
  ///
  /// 措辞刻意**不提具体平台、更不说设备不行**。
  static const _notImplemented = '当前平台暂不支持罗盘';

  Stream<CompassReading> readings() {
    if (defaultTargetPlatform != TargetPlatform.iOS &&
        defaultTargetPlatform != TargetPlatform.android) {
      return Stream.error(const CompassUnavailable(_notImplemented));
    }
    return const EventChannel('night_sleep/compass')
        .receiveBroadcastStream()
        .map((event) => CompassReading.fromMap(event as Map<Object?, Object?>));
  }
}

class CompassUnavailable implements Exception {
  const CompassUnavailable(this.message);
  final String message;
}
