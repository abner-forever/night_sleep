import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/app_config.dart';
import '../../../core/telemetry/event_log.dart';
import '../domain/weather_snapshot.dart';
import 'device_location.dart';
import 'weather_location.dart';

final weatherHttpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final weatherProvider = FutureProvider<WeatherSnapshot?>((ref) async {
  final baseUrl = AppConfig.weatherApiBaseUrl;
  if (baseUrl.isEmpty) return null;

  final timer = Timer(const Duration(minutes: 30), ref.invalidateSelf);
  ref.onDispose(timer.cancel);

  final location = await _resolveLocationQuery(ref);

  // 移动端有自己的定位能力，**拿不到位置就不该让服务端按请求 IP 猜城市**：
  // 国内宽带与移动网络的 IP 归属地登记经常不在所在城市（深圳的出口写成广州
  // 是典型），用户会把那个错误城市当成真的。宁可让卡片走「使用我的位置」，
  // 也不显示一个可能错到隔壁市的天气。桌面端没有定位能力，IP 兜底是唯一
  // 来源，保持不变。
  if (location == null && _deviceCanLocate) {
    ref.read(eventLogProvider).track('weather_location_required');
    throw const WeatherLocationRequired();
  }

  try {
    return await WeatherService(
      baseUrl: baseUrl,
      client: ref.watch(weatherHttpClientProvider),
      location: location ?? '',
    ).fetchCurrent();
  } on Object catch (error) {
    // 埋点上报失败。异常继续往上抛：界面该显示什么错误仍显示什么，
    // 埋点只是旁路，不改变任何一条既有路径。
    ref
        .read(eventLogProvider)
        .track('weather_fetch_failed', weatherFailureFields(error));
    rethrow;
  }
});

/// 移动端有真定位能力（Android / iOS），桌面端没有。
bool get _deviceCanLocate {
  final platform = defaultTargetPlatform;
  return platform == TargetPlatform.android || platform == TargetPlatform.iOS;
}

/// 移动端这次没有可靠位置。界面不看异常类型，而是按 [weatherLocationProvider]
/// 的状态给出对应出路（「使用我的位置 / 重试 / 去设置」）。
class WeatherLocationRequired implements Exception {
  const WeatherLocationRequired();
}

/// 这次请求带什么位置。
///
/// 优先级：**用户主动定位到的坐标 > 编译期指定的城市 > 已授权时的静默定位 >
/// 什么都不带（仅桌面端；移动端此时直接抛 [WeatherLocationRequired]）**。
///
/// 编译期城市排在静默定位前面，是为了让 `--dart-define=WEATHER_LOCATION=上海`
/// 仍然能当成「固定看某个城市」的联调开关用；用户真按了「使用我的位置」，
/// 那是更明确的意图，所以排最前。
///
/// 静默那一档**只查权限、不弹框**：已经授权过的设备不必每次启动都点一次按钮，
/// 没授权就安静地返回空，等用户自己决定。
Future<String?> _resolveLocationQuery(Ref ref) async {
  final selected =
      ref.watch(weatherLocationProvider.select((state) => state.query));
  if (selected != null && selected.isNotEmpty) return selected;

  // 定位是**旁路**，不能拖死天气：插件缺失、平台不支持、权限接口本身卡住时，
  // 这里一律退成「不带位置」，让服务端按 IP 兜底。没有这层兜底，一个卡住的
  // 平台调用会让卡片永远停在「正在获取天气」。
  try {
    final result = await ref
        .read(deviceLocationProvider)
        .current()
        .timeout(const Duration(seconds: 8));
    return result is DeviceLocationFix ? result.fix.query : null;
  } on Object {
    return null;
  }
}

/// 失败埋点的结构化字段。
///
/// **响应正文永远不进日志**——与界面不回显正文是同一条红线：服务端响应体
/// 里可能有不该出现在日志里的内容，埋点只保留失败类别与状态码。
Map<String, Object?> weatherFailureFields(Object error) {
  if (error is WeatherServiceException) {
    return {'kind': 'http', 'statusCode': error.statusCode};
  }
  if (error is TimeoutException) return const {'kind': 'timeout'};
  if (error is FormatException) return const {'kind': 'format'};
  if (error is http.ClientException) return const {'kind': 'network'};
  return {'kind': 'unknown', 'type': error.runtimeType.toString()};
}

class WeatherService {
  WeatherService({
    required this.baseUrl,
    required this.client,
    this.location = '',
  });

  final String baseUrl;
  final http.Client client;
  final String location;

  static const _timeout = Duration(seconds: 6);

  Future<WeatherSnapshot> fetchCurrent() async {
    final normalizedBase = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    final endpoint = Uri.parse(normalizedBase).resolve('weather');
    final uri = location.trim().isEmpty
        ? endpoint
        : endpoint.replace(queryParameters: {'location': location.trim()});

    final response = await client.get(
      uri,
      headers: const {'Accept': 'application/json'},
    ).timeout(_timeout);
    if (response.statusCode != 200) {
      throw WeatherServiceException(response.statusCode);
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('天气响应格式错误');
    }
    final payload = decoded['data'];
    if (payload is Map<String, dynamic>) {
      return WeatherSnapshot.fromJson(payload);
    }
    return WeatherSnapshot.fromJson(decoded);
  }
}

class WeatherServiceException implements Exception {
  const WeatherServiceException(this.statusCode);

  final int statusCode;

  @override
  String toString() => '天气服务请求失败（HTTP $statusCode）';
}
