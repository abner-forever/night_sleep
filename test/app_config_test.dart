import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/core/config/app_config.dart';

void main() {
  group('天气接口环境', () {
    test('仓库不内置线上接口地址，未注入时为空', () {
      // 公开仓库不保存线上域名：地址只能由构建注入（CI 的 Secret 或本地 .env.local）。
      // 这条用例钉住「默认空串」，免得谁为了跑通把地址写回源码。
      expect(AppConfig.weatherApiBaseUrl, '');
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
