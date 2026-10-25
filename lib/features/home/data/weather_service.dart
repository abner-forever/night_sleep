import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/app_config.dart';
import '../domain/weather_snapshot.dart';

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
  return WeatherService(
    baseUrl: baseUrl,
    client: ref.watch(weatherHttpClientProvider),
    location: AppConfig.weatherLocation,
  ).fetchCurrent();
});

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
