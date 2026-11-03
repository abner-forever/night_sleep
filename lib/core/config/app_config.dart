import 'package:flutter/foundation.dart';

/// Build-time switches.
abstract final class AppConfig {
  /// Whether the bundled demo dataset is offered.
  ///
  /// The spec requires demo data to be isolated from real data and off in
  /// release builds, so this defaults to [kDebugMode] — on for debug and
  /// profile runs, off for release — and can be forced either way:
  ///
  /// ```
  /// flutter run --dart-define=DEMO_DATA=true
  /// flutter build apk --dart-define=DEMO_DATA=false
  /// ```
  ///
  /// Even when enabled, demo rows are tagged `source == 'demo'` and can be
  /// cleared from Settings, so they never mix silently with real entries.
  static const bool demoDataEnabled = bool.fromEnvironment(
    'DEMO_DATA',
    defaultValue: kDebugMode,
  );

  /// `source` value marking bundled sample rows.
  static const String demoSource = 'demo';

  /// 天气接口基址，**只从构建时注入**（`--dart-define=WEATHER_API_BASE_URL=...`）。
  ///
  /// 仓库里不保存线上地址：这是公开仓库，接口域名没必要写进源码。注入有两条路：
  ///
  /// - 发布包：GitHub Actions 按分支挂到对应的 Environment（`server-beta` /
  ///   `server-prod`），从里面的 `WEATHER_API_BASE_URL` 变量取值后写进这个变量
  ///   （见 `android.yml`）；
  /// - 本地调试：未入库的 `.env.local`，
  ///   `flutter run --dart-define-from-file=.env.local`（`tool/run_local.sh` 的用法）。
  ///
  /// 两条路都没提供时是空串，此时**不发任何天气请求**——首页那张卡不出现。
  /// 这是「没有的能力就显示为没有」，不是错误状态。
  ///
  /// 值必须带 `/api` 前缀，且是 `https://`：release 构建不允许明文 HTTP
  /// （Android `network_security_config.xml` 与 iOS `Info.plist` 都没开对线上的例外）。
  static const String weatherApiBaseUrl = String.fromEnvironment(
    'WEATHER_API_BASE_URL',
    defaultValue: '',
  );

  /// debug 构建下本地开发服务的候选地址，按顺序探测。
  ///
  /// `localhost` 覆盖 iOS 模拟器与 `adb reverse tcp:8080 tcp:8080`；
  /// `10.0.2.2` 是 Android 模拟器映射宿主机的专用地址——**真机上它不存在**，
  /// 连过去是静默丢包，所以探测必须带短超时（见 `weather_service.dart`）。
  static const List<String> debugLocalWeatherApiBaseUrls = [
    'http://localhost:8080/api',
    'http://10.0.2.2:8080/api',
  ];

  /// 可选城市名。为空时服务端根据请求 IP 解析城市级大致位置。
  static const String weatherLocation = String.fromEnvironment(
    'WEATHER_LOCATION',
    defaultValue: '',
  );
}
