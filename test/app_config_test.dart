import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/core/config/app_config.dart';

void main() {
  group('天气接口环境', () {
    test('beta 构建使用测试服', () {
      expect(
        AppConfig.releaseWeatherApiBaseUrlFor('beta'),
        AppConfig.betaWeatherApiBaseUrl,
      );
    });

    test('main 构建使用正式服', () {
      expect(
        AppConfig.releaseWeatherApiBaseUrlFor('main'),
        AppConfig.productionWeatherApiBaseUrl,
      );
    });

    test('分支名两端空白不影响判定', () {
      expect(
        AppConfig.releaseWeatherApiBaseUrlFor(' beta\n'),
        AppConfig.betaWeatherApiBaseUrl,
      );
    });

    test('未知发布分支不启用天气请求', () {
      expect(AppConfig.releaseWeatherApiBaseUrlFor(''), '');
      expect(AppConfig.releaseWeatherApiBaseUrlFor('feature/x'), '');
    });

    test('本地探测候选先本机、后模拟器映射', () {
      // 顺序即优先级：回环先答应就不必等 10.0.2.2 那个 800ms 超时。
      expect(AppConfig.debugLocalWeatherApiBaseUrls, [
        'http://localhost:8080/api',
        'http://10.0.2.2:8080/api',
      ]);
    });
  });
}
