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

  /// 编译期显式指定的接口基址（`--dart-define=WEATHER_API_BASE_URL=...`）。
  ///
  /// 非空时**优先于一切**——既不探测本地服务，也不看发布分支。
  static const String configuredWeatherApiBaseUrl = String.fromEnvironment(
    'WEATHER_API_BASE_URL',
    defaultValue: '',
  );

  /// 发布分支名，由 Android 工作流注入（`beta` / `main`）。
  static const String releaseChannel = String.fromEnvironment(
    'APP_RELEASE_CHANNEL',
    defaultValue: '',
  );

  /// Beta 测试分支的天气接口基址：腾讯云服务器的测试服（PM2 `night-sleep-beta`）。
  ///
  /// 过渡态——域名 `foreverheart.top` 解析就绪前先直连 IP。改成 HTTPS 域名后，
  /// 记得把 Android 的 `res/xml/network_security_config.xml` 与
  /// `ios/Runner/Info.plist` 里为明文 HTTP 开的例外一并删掉。
  static const String betaWeatherApiBaseUrl = 'http://110.40.226.136:8081/api';

  /// 正式分支的天气接口基址：同一台服务器的正式服（PM2 `night-sleep-prod`）。
  ///
  /// 域名上线后改成 `https://foreverheart.top/api`。
  static const String productionWeatherApiBaseUrl =
      'http://110.40.226.136:8080/api';

  /// debug 构建下本地开发服务的候选地址，按顺序探测。
  ///
  /// `localhost` 覆盖 iOS 模拟器与 `adb reverse tcp:8080 tcp:8080`；
  /// `10.0.2.2` 是 Android 模拟器映射宿主机的专用地址——**真机上它不存在**，
  /// 连过去是静默丢包，所以探测必须带短超时（见 `weather_service.dart`）。
  static const List<String> debugLocalWeatherApiBaseUrls = [
    'http://localhost:8080/api',
    'http://10.0.2.2:8080/api',
  ];

  /// 发布构建按分支取的接口基址；未知分支返回空串，此时不请求天气。
  ///
  /// debug 构建不走这里——本地服务起没起要看运行时探测，
  /// 见 `weather_service.dart` 的 `resolveWeatherApiBaseUrl`。
  static String releaseWeatherApiBaseUrlFor(String channel) {
    return switch (channel.trim()) {
      'beta' => betaWeatherApiBaseUrl,
      'main' => productionWeatherApiBaseUrl,
      _ => '',
    };
  }

  /// 可选城市名。为空时服务端根据请求 IP 解析城市级大致位置。
  static const String weatherLocation = String.fromEnvironment(
    'WEATHER_LOCATION',
    defaultValue: '',
  );
}
