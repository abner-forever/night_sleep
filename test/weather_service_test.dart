import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:night_sleep/features/home/data/weather_service.dart';
import 'package:night_sleep/features/home/domain/weather_snapshot.dart';

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
}
