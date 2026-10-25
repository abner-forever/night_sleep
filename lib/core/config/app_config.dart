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

  /// Beta 测试分支使用的 Cloudflare Worker Preview。
  static const String betaWeatherApiBaseUrl =
      'https://beta-night-sleep.abner-foreverheart.workers.dev/api';

  /// 正式分支使用的 Cloudflare Worker Production。
  static const String productionWeatherApiBaseUrl =
      'https://night-sleep.abner-foreverheart.workers.dev/api';

  /// 天气接口基址。
  ///
  /// 发布构建由工作流传入分支名，自动选择 Beta Preview 或 Production Worker。
  /// debug 默认连接本机 NestJS 服务；Android 模拟器使用宿主机的 10.0.2.2。
  static String get weatherApiBaseUrl {
    const configured = String.fromEnvironment(
      'WEATHER_API_BASE_URL',
      defaultValue: '',
    );
    const releaseChannel = String.fromEnvironment(
      'APP_RELEASE_CHANNEL',
      defaultValue: '',
    );
    return resolveWeatherApiBaseUrl(
      configuredUrl: configured,
      releaseChannel: releaseChannel,
      debug: kDebugMode,
      platform: defaultTargetPlatform,
    );
  }

  static String resolveWeatherApiBaseUrl({
    required String configuredUrl,
    required String releaseChannel,
    required bool debug,
    required TargetPlatform platform,
  }) {
    final configured = configuredUrl.trim();
    if (configured.isNotEmpty) return configured;
    if (debug) {
      return platform == TargetPlatform.android
          ? 'http://10.0.2.2:8080/api'
          : 'http://localhost:8080/api';
    }
    return switch (releaseChannel.trim()) {
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
