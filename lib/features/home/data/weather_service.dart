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

/// 编译期注入的接口基址（见 `AppConfig.weatherApiBaseUrl`）。
///
/// 抽成 provider 只为一件事：常量在测试进程里永远是空串，替换不了就一条请求都发不出去。
final weatherBaseUrlProvider = Provider<String>(
  (ref) => AppConfig.weatherApiBaseUrl,
);

final weatherProvider = FutureProvider<WeatherSnapshot?>((ref) async {
  final client = ref.watch(weatherHttpClientProvider);
  final configuredUrl = ref.watch(weatherBaseUrlProvider);

  // 发布包里没有注入接口地址（自己构建的包、或仓库 Secret 没配）：直接当作「没有
  // 天气能力」，连定位都不问。反问用户去开定位、再显示一片空白，比不显示更糟。
  if (!kDebugMode && configuredUrl.trim().isEmpty) return null;

  final location = await _resolveLocationQuery(ref);

  // 移动端有自己的定位能力，**拿不到位置就不该让服务端按请求 IP 猜城市**：
  // 国内宽带与移动网络的 IP 归属地登记经常不在所在城市（深圳的出口写成广州
  // 是典型），用户会把那个错误城市当成真的。宁可让卡片走「使用我的位置」，
  // 也不显示一个可能错到隔壁市的天气。桌面端没有定位能力，IP 兜底是唯一
  // 来源，保持不变。
  //
  // 这一跳排在解析基址**之前**：既然注定不请求，就不该先花时间探本机服务。
  if (location == null && _deviceCanLocate) {
    ref.read(eventLogProvider).track('weather_location_required');
    throw const WeatherLocationRequired();
  }

  final baseUrl = await resolveWeatherApiBaseUrl(
    configuredUrl: configuredUrl,
    debug: kDebugMode,
    probe: (candidate) => _isLocalServerUp(client, candidate),
  );
  if (baseUrl.isEmpty) return null;

  final timer = Timer(const Duration(minutes: 30), ref.invalidateSelf);
  ref.onDispose(timer.cancel);

  try {
    return await WeatherService(
      baseUrl: baseUrl,
      client: client,
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

/// 这次请求要连的基址；返回空串表示**这次不发请求**。
///
/// 优先级：**构建时注入的地址 > debug 下探测到的本地服务 > 空**。
///
/// 仓库里没有兜底的线上地址（见 `AppConfig.weatherApiBaseUrl`），所以「什么都没配」
/// 是一个正常结果：release 直接用注入值，debug 先探本机、探不到就不请求。
///
/// 探测只在 debug 发生：发布包不该去连本机，也连不上——release 的网络安全配置
/// 不放行任何明文地址。
Future<String> resolveWeatherApiBaseUrl({
  required String configuredUrl,
  required bool debug,
  required Future<bool> Function(String baseUrl) probe,
}) async {
  final configured = configuredUrl.trim();
  if (configured.isNotEmpty) return configured;
  if (!debug) return '';

  for (final candidate in AppConfig.debugLocalWeatherApiBaseUrls) {
    if (await probe(candidate)) return candidate;
  }
  return '';
}

/// 本地 NestJS 服务是否在跑：`GET {base}/health` 回 200 就算在。
///
/// 超时必须短。回环上有服务时几毫秒就答应、没有时是**立刻拒绝**，800ms 只是给
/// `adb reverse` 留余量；而 `10.0.2.2` 在真机上根本不存在，连过去是**静默丢包**
/// 而不是拒绝连接，没有这个超时会把开屏一直拖到请求本身超时。
Future<bool> _isLocalServerUp(http.Client client, String baseUrl) async {
  try {
    final response = await client
        .get(_endpointOf(baseUrl, 'health'))
        .timeout(const Duration(milliseconds: 800));
    return response.statusCode == 200;
  } on Object {
    return false;
  }
}

/// 拼接口地址：`{base}/{path}`，base 末尾带不带 `/` 都行。
Uri _endpointOf(String baseUrl, String path) {
  final normalizedBase = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
  return Uri.parse(normalizedBase).resolve(path);
}

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
    final endpoint = _endpointOf(baseUrl, 'weather');
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
