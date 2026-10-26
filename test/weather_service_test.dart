import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:night_sleep/core/telemetry/event_log.dart';
import 'package:night_sleep/features/home/data/device_location.dart';
import 'package:night_sleep/features/home/data/weather_service.dart';
import 'package:night_sleep/features/home/domain/location_fix.dart';
import 'package:night_sleep/features/home/domain/weather_snapshot.dart';

/// 记录 track 调用的假埋点，别的什么都不做。
class _RecordingLog implements EventLog {
  final events = <String>[];
  final fields = <Map<String, Object?>>[];

  @override
  void track(String event, [Map<String, Object?> data = const {}]) {
    events.add(event);
    fields.add(Map.of(data));
  }

  @override
  Future<List<EventLogEntry>> readAll() async => const [];

  @override
  Future<String> exportContent() async => '{}';

  @override
  Future<void> clear() async {}
}

/// 永远返回一个固定坐标的假定位。
///
/// provider 级用例在测试环境里按移动平台处理（测试环境默认 android），
/// 不覆盖定位的话，weatherProvider 会先抛 [WeatherLocationRequired]，
/// 轮不到要测的请求与埋点路径。
class _StaticLocation implements DeviceLocation {
  const _StaticLocation();

  static const _fix = LocationFix(latitude: 31.23, longitude: 121.47);

  @override
  Future<DeviceLocationResult> current({bool interactive = false}) async =>
      const DeviceLocationFix(_fix);

  @override
  Future<void> openAppSettings() async {}

  @override
  Future<void> openLocationSettings() async {}
}

void main() {
  test('请求本地天气接口并按服务端结构解析', () async {
    Uri? requested;
    final client = MockClient((request) async {
      requested = request.url;
      return http.Response.bytes(
        utf8.encode(jsonEncode({
          'success': true,
          'code': 0,
          'message': 'success',
          'data': {
            'city': '上海',
            'latitude': 31.23,
            'longitude': 121.47,
            'forecastDate': '2026-10-25',
            'temperature': 24.4,
            'temperatureMax': 27,
            'temperatureMin': 19,
            'weatherCode': 1,
            'weatherText': '多云',
            'weatherEmoji': '⛅',
            'isDay': false,
            'windspeed': 12,
            'humidity': 68,
          },
        })),
        200,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      );
    });

    final snapshot = await WeatherService(
      baseUrl: 'http://localhost:8080/api',
      client: client,
      location: '上海',
    ).fetchCurrent();

    expect(
      requested,
      Uri.parse(
        'http://localhost:8080/api/weather?location=%E4%B8%8A%E6%B5%B7',
      ),
    );
    expect(snapshot.city, '上海');
    expect(snapshot.temperature, 24.4);
    expect(snapshot.weatherText, '多云');
    expect(snapshot.weatherEmoji, '⛅');
    expect(snapshot.humidity, 68);
  });

  test('非 200 响应只保留状态码，不展示响应正文', () async {
    final client = MockClient(
      (_) async => http.Response('sensitive response body', 503),
    );

    await expectLater(
      WeatherService(
        baseUrl: 'http://localhost:8080/api',
        client: client,
      ).fetchCurrent(),
      throwsA(
        isA<WeatherServiceException>()
            .having((error) => error.statusCode, 'statusCode', 503)
            .having(
              (error) => error.toString(),
              'message',
              isNot(contains('sensitive response body')),
            ),
      ),
    );
  });

  test('不可用占位数据不能作为真实天气展示', () {
    expect(
      () => WeatherSnapshot.fromJson(const {
        'city': '北京',
        'temperature': 0,
        'temperatureMax': 0,
        'temperatureMin': 0,
        'weatherCode': 0,
        'weatherText': '晴',
        'weatherEmoji': '☀️',
        'isDay': true,
        'windspeed': 0,
        'unavailable': true,
      }),
      throwsFormatException,
    );
  });

  test('provider 层把请求失败上报为埋点，异常继续往上抛', () async {
    final log = _RecordingLog();
    final client = MockClient(
      (_) async => http.Response('sensitive response body', 503),
    );
    final container = ProviderContainer(
      overrides: [
        eventLogProvider.overrideWithValue(log),
        weatherHttpClientProvider.overrideWithValue(client),
        deviceLocationProvider.overrideWithValue(const _StaticLocation()),
      ],
    );
    addTearDown(container.dispose);

    // 异常本身不能被埋点吞掉：界面仍然要拿到同一个错误。
    await expectLater(
      container.read(weatherProvider.future),
      throwsA(isA<WeatherServiceException>()),
    );

    expect(log.events, ['weather_fetch_failed']);
    // 只记类别与状态码；正文里可能有不该回显的内容，绝不进日志。
    expect(log.fields.single, {'kind': 'http', 'statusCode': 503});
  });

  test('请求成功不上报埋点', () async {
    final log = _RecordingLog();
    final client = MockClient((request) async => http.Response(
          jsonEncode({
            'city': '上海',
            'latitude': 31.23,
            'longitude': 121.47,
            'forecastDate': '2026-10-25',
            'temperature': 24.4,
            'temperatureMax': 27,
            'temperatureMin': 19,
            'weatherCode': 1,
            'weatherText': '多云',
            'weatherEmoji': '⛅',
            'isDay': false,
            'windspeed': 12,
            'humidity': 68,
          }),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        ));
    final container = ProviderContainer(
      overrides: [
        eventLogProvider.overrideWithValue(log),
        weatherHttpClientProvider.overrideWithValue(client),
        deviceLocationProvider.overrideWithValue(const _StaticLocation()),
      ],
    );
    addTearDown(container.dispose);

    await container.read(weatherProvider.future);

    expect(log.events, isEmpty);
  });
}
