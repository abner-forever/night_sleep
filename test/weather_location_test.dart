import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:night_sleep/features/home/data/device_location.dart';
import 'package:night_sleep/features/home/data/weather_location.dart';
import 'package:night_sleep/features/home/data/weather_service.dart';
import 'package:night_sleep/features/home/domain/location_fix.dart';

/// 假定位：记录**有没有开口要权限**，并按预设结果答复。
///
/// 这个字段是本文件的核心断言对象：静默路径一旦偷偷调了 `requestPermission()`，
/// 真机上就会在用户没点任何东西的时候弹系统框——那是规格明令禁止的。
class _FakeDeviceLocation implements DeviceLocation {
  _FakeDeviceLocation(this.result);

  DeviceLocationResult result;
  bool askedForPermission = false;
  String? openedSettings;

  @override
  Future<DeviceLocationResult> current({bool interactive = false}) async {
    if (interactive) askedForPermission = true;
    return result;
  }

  @override
  Future<void> openAppSettings() async => openedSettings = 'app';

  @override
  Future<void> openLocationSettings() async => openedSettings = 'location';
}

const _shanghai = LocationFix(latitude: 31.2345, longitude: 121.4712);

http.Response _weatherResponse() => http.Response(
      jsonEncode({
        'city': '上海',
        'latitude': 31.23,
        'longitude': 121.47,
        'forecastDate': '2026-10-26',
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
    );

ProviderContainer _container({
  required DeviceLocation location,
  required void Function(Uri url) onRequest,
}) {
  return ProviderContainer(
    overrides: [
      deviceLocationProvider.overrideWithValue(location),
      weatherHttpClientProvider.overrideWithValue(MockClient((request) async {
        onRequest(request.url);
        return _weatherResponse();
      })),
    ],
  );
}

void main() {
  test('坐标按「经度,纬度」、两位小数序列化', () {
    // 顺序反了会落到一千多公里外；多一位小数对「今天多少度」没有任何帮助。
    expect(_shanghai.query, '121.47,31.23');
  });

  test('桌面端拿不到位置时请求不带 location，交给服务端按 IP 兜底', () async {
    // 测试宿主按 OS 判成桌面平台（本仓库跑在 Windows 上），但显式写出来，
    // 这条用例守护的就是「桌面端保留 IP 兜底」这个决定。
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final location = _FakeDeviceLocation(
      const DeviceLocationMiss(DeviceLocationFailure.permissionDenied),
    );
    Uri? requested;
    final container = _container(
      location: location,
      onRequest: (url) => requested = url,
    );
    addTearDown(container.dispose);

    await container.read(weatherProvider.future);

    expect(location.askedForPermission, isFalse);
    expect(requested!.queryParameters.containsKey('location'), isFalse);
  });

  test('移动端拿不到位置时不发请求——IP 归属地在国内经常错到邻市', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final location = _FakeDeviceLocation(
      const DeviceLocationMiss(DeviceLocationFailure.unavailable),
    );
    var requests = 0;
    final container = _container(
      location: location,
      onRequest: (_) => requests++,
    );
    addTearDown(container.dispose);

    // 抛专用异常，界面据此走「无法获取位置 / 重试」分支，而不是显示一个
    // 按请求 IP 猜出来的、可能是另一座城市的天气。
    await expectLater(
      container.read(weatherProvider.future),
      throwsA(isA<WeatherLocationRequired>()),
    );
    expect(requests, isZero);
  });

  test('已授权时静默取坐标，请求带上经纬度', () async {
    final location = _FakeDeviceLocation(const DeviceLocationFix(_shanghai));
    Uri? requested;
    final container = _container(
      location: location,
      onRequest: (url) => requested = url,
    );
    addTearDown(container.dispose);

    await container.read(weatherProvider.future);

    expect(location.askedForPermission, isFalse);
    expect(requested!.queryParameters['location'], '121.47,31.23');
  });

  test('用户点了按钮才索要权限，拿到坐标后状态变为 ready', () async {
    final location = _FakeDeviceLocation(const DeviceLocationFix(_shanghai));
    final container = ProviderContainer(
      overrides: [deviceLocationProvider.overrideWithValue(location)],
    );
    addTearDown(container.dispose);

    // 初始是 idle：没配置城市、也没授权。界面据此给出「使用我的位置」。
    expect(
      container.read(weatherLocationProvider).status,
      WeatherLocationStatus.idle,
    );
    expect(location.askedForPermission, isFalse);

    await container.read(weatherLocationProvider.notifier).requestPermission();

    final state = container.read(weatherLocationProvider);
    expect(location.askedForPermission, isTrue);
    expect(state.status, WeatherLocationStatus.ready);
    expect(state.query, '121.47,31.23');
    expect(state.isResolved, isTrue);
  });

  test('定位完成后天气会带着新坐标重新请求', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final location = _FakeDeviceLocation(
      const DeviceLocationMiss(DeviceLocationFailure.permissionDenied),
    );
    final requests = <Uri>[];
    final container = _container(
      location: location,
      onRequest: requests.add,
    );
    addTearDown(container.dispose);

    // 没有位置：移动端直接要求位置，不发请求。
    await expectLater(
      container.read(weatherProvider.future),
      throwsA(isA<WeatherLocationRequired>()),
    );
    expect(requests, isEmpty);

    // 用户点了「使用我的位置」，这次拿到了坐标，天气随之重建。
    location.result = const DeviceLocationFix(_shanghai);
    await container.read(weatherLocationProvider.notifier).requestPermission();
    await container.read(weatherProvider.future);

    expect(requests, hasLength(1));
    expect(requests.single.queryParameters['location'], '121.47,31.23');
  });

  group('取不到位置时按原因分流，界面才不会指错方向', () {
    const cases = [
      (
        DeviceLocationFailure.permissionDenied,
        WeatherLocationStatus.permissionDenied
      ),
      (
        DeviceLocationFailure.permissionDeniedForever,
        WeatherLocationStatus.permissionDeniedForever,
      ),
      (
        DeviceLocationFailure.serviceDisabled,
        WeatherLocationStatus.serviceDisabled
      ),
      (DeviceLocationFailure.unavailable, WeatherLocationStatus.unavailable),
    ];

    for (final (failure, expected) in cases) {
      test('$failure → $expected', () async {
        final location = _FakeDeviceLocation(DeviceLocationMiss(failure));
        final container = ProviderContainer(
          overrides: [deviceLocationProvider.overrideWithValue(location)],
        );
        addTearDown(container.dispose);

        await container
            .read(weatherLocationProvider.notifier)
            .requestPermission();

        final state = container.read(weatherLocationProvider);
        expect(state.status, expected);
        // 失败时绝不能留下一个坐标——那会让界面显示上一次的城市。
        expect(state.query, isNull);
        expect(state.isResolved, isFalse);
      });
    }
  });
}
