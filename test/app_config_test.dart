import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/core/config/app_config.dart';

void main() {
  group('天气接口环境', () {
    test('beta 构建使用 Preview Worker', () {
      expect(
        AppConfig.resolveWeatherApiBaseUrl(
          configuredUrl: '',
          releaseChannel: 'beta',
          debug: false,
          platform: TargetPlatform.android,
        ),
        AppConfig.betaWeatherApiBaseUrl,
      );
    });

    test('main 构建使用 Production Worker', () {
      expect(
        AppConfig.resolveWeatherApiBaseUrl(
          configuredUrl: '',
          releaseChannel: 'main',
          debug: false,
          platform: TargetPlatform.iOS,
        ),
        AppConfig.productionWeatherApiBaseUrl,
      );
    });

    test('debug 构建继续使用本机服务', () {
      expect(
        AppConfig.resolveWeatherApiBaseUrl(
          configuredUrl: '',
          releaseChannel: 'beta',
          debug: true,
          platform: TargetPlatform.android,
        ),
        'http://10.0.2.2:8080/api',
      );
      expect(
        AppConfig.resolveWeatherApiBaseUrl(
          configuredUrl: '',
          releaseChannel: 'main',
          debug: true,
          platform: TargetPlatform.iOS,
        ),
        'http://localhost:8080/api',
      );
    });

    test('显式配置覆盖分支默认值', () {
      expect(
        AppConfig.resolveWeatherApiBaseUrl(
          configuredUrl: ' https://api.example.com/api ',
          releaseChannel: 'beta',
          debug: false,
          platform: TargetPlatform.android,
        ),
        'https://api.example.com/api',
      );
    });

    test('未知发布分支不启用天气请求', () {
      expect(
        AppConfig.resolveWeatherApiBaseUrl(
          configuredUrl: '',
          releaseChannel: '',
          debug: false,
          platform: TargetPlatform.android,
        ),
        '',
      );
    });
  });
}
