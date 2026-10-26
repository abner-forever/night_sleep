import 'package:flutter/foundation.dart';

/// 一次定位得到的坐标。
///
/// **只带经纬度，不带城市名。** 城市由服务端用和风 GeoAPI 的「坐标反查」得出
/// （`server/src/weather/weather.service.ts` 的 `lookupLocation`），所以客户端
/// 不需要逆地理编码插件，也不需要把地名猜一遍再传上去——猜错就会显示成别的城市。
@immutable
class LocationFix {
  const LocationFix({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

  /// 和风天气 `location` 参数接受的「经度,纬度」。
  ///
  /// **顺序是经度在前**：`121.47,31.23` 是上海，写成 `31.23,121.47` 会落到
  /// 一千多公里外的山里，GeoAPI 直接查不到城市。
  ///
  /// 两位小数约 1.1 km：城市级天气完全够用，也是能少暴露一点就少暴露一点的
  /// 默认值。精度再高对「今天多少度」没有任何帮助。
  String get query =>
      '${longitude.toStringAsFixed(2)},${latitude.toStringAsFixed(2)}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LocationFix &&
          other.latitude == latitude &&
          other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() => 'LocationFix($latitude, $longitude)';
}
