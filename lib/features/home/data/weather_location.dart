import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import 'device_location.dart';

/// 天气卡片的位置从哪儿来。
enum WeatherLocationStatus {
  /// 编译期 `--dart-define=WEATHER_LOCATION` 指定了城市。优先级最高：
  /// 联调时想固定看某个城市，不该被设备定位覆盖。
  configured,

  /// 还没有位置，也还没问过用户。卡片给一个「使用我的位置」入口。
  idle,

  /// 系统权限框或定位本身正在进行。
  locating,

  /// 拿到坐标了，天气请求会带上 `location=经度,纬度`。
  ready,

  /// 这一次拒绝了，可以再问。
  permissionDenied,

  /// 被永久拒绝，只能去系统设置。
  permissionDeniedForever,

  /// 系统的定位总开关关着。
  serviceDisabled,

  /// 权限和服务都正常，但这次没取到坐标。
  unavailable,
}

@immutable
class WeatherLocationState {
  const WeatherLocationState({required this.status, this.query});

  final WeatherLocationStatus status;

  /// 传给天气接口的 `location`。`null` 表示这一次不带位置，让服务端按请求 IP 兜底。
  final String? query;

  bool get hasQuery => query != null && query!.isNotEmpty;

  /// 有位置可用时不需要再引导用户做任何事。
  bool get isResolved =>
      status == WeatherLocationStatus.ready ||
      status == WeatherLocationStatus.configured;

  static const idle = WeatherLocationState(status: WeatherLocationStatus.idle);
}

/// 天气位置来源。
///
/// **启动时不弹权限框。** `AGENTS.md` 的规矩是「权限在用户启用对应功能时申请」，
/// 而天气卡片是首页自动加载的——一进首页就弹定位框，等于在用户没表达意图时
/// 索要权限。所以这里只在 [requestPermission]（用户点了「使用我的位置」）里
/// 调 `requestPermission`，其余路径一律静默。
///
/// 已经授权过的设备不会每次都点：`weatherProvider` 在没有显式位置时会先走一次
/// 静默尝试（[DeviceLocation.current] 的 `interactive: false`），有权限就直接
/// 出天气，没权限才落到 [WeatherLocationState.idle] 等用户点。
class WeatherLocationController extends Notifier<WeatherLocationState> {
  bool _disposed = false;

  @override
  WeatherLocationState build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);

    final configured = AppConfig.weatherLocation.trim();
    if (configured.isEmpty) return WeatherLocationState.idle;
    return WeatherLocationState(
      status: WeatherLocationStatus.configured,
      query: configured,
    );
  }

  /// 用户主动点「使用我的位置」。**这一步会弹系统权限框。**
  Future<void> requestPermission() async {
    if (state.status == WeatherLocationStatus.locating) return;
    state = const WeatherLocationState(status: WeatherLocationStatus.locating);

    final result =
        await ref.read(deviceLocationProvider).current(interactive: true);
    if (_disposed) return;
    state = _stateFor(result);
  }

  /// 权限被永久拒绝时去应用设置；系统定位关着时去定位开关。
  Future<void> openAppSettings() =>
      ref.read(deviceLocationProvider).openAppSettings();

  Future<void> openLocationSettings() =>
      ref.read(deviceLocationProvider).openLocationSettings();

  WeatherLocationState _stateFor(DeviceLocationResult result) {
    return switch (result) {
      DeviceLocationFix(:final fix) => WeatherLocationState(
          status: WeatherLocationStatus.ready,
          query: fix.query,
        ),
      DeviceLocationMiss(:final reason) => WeatherLocationState(
          status: switch (reason) {
            DeviceLocationFailure.permissionDenied =>
              WeatherLocationStatus.permissionDenied,
            DeviceLocationFailure.permissionDeniedForever =>
              WeatherLocationStatus.permissionDeniedForever,
            DeviceLocationFailure.serviceDisabled =>
              WeatherLocationStatus.serviceDisabled,
            DeviceLocationFailure.unavailable =>
              WeatherLocationStatus.unavailable,
          },
        ),
    };
  }
}

final weatherLocationProvider =
    NotifierProvider<WeatherLocationController, WeatherLocationState>(
  WeatherLocationController.new,
);
