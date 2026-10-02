import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../features/compass/domain/compass_heading.dart';

class CompassSource {
  const CompassSource();

  Stream<CompassReading> readings() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return Stream.error(const CompassUnavailable('请使用支持罗盘的 iPhone 打开此页面'));
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
