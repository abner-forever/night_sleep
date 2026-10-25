import 'package:flutter/foundation.dart';

/// 天气服务返回的当前天气。
@immutable
class WeatherSnapshot {
  const WeatherSnapshot({
    required this.city,
    required this.temperature,
    required this.temperatureMax,
    required this.temperatureMin,
    required this.weatherCode,
    required this.weatherText,
    required this.weatherEmoji,
    required this.isDay,
    required this.windspeed,
    this.forecastDate,
    this.precipitation,
    this.humidity,
  });

  final String city;
  final double temperature;
  final double temperatureMax;
  final double temperatureMin;
  final int weatherCode;
  final String weatherText;
  final String weatherEmoji;
  final bool isDay;
  final double windspeed;
  final String? forecastDate;
  final double? precipitation;
  final double? humidity;

  factory WeatherSnapshot.fromJson(Map<String, dynamic> json) {
    if (json['unavailable'] == true) {
      throw const FormatException('天气服务暂不可用');
    }
    final fallback = json['fallback'];
    if (fallback is Map && fallback['isFallback'] == true) {
      throw const FormatException('天气服务未解析出城市');
    }

    final city = _string(json, 'city');
    final weatherText = _string(json, 'weatherText');
    final weatherEmoji = _string(json, 'weatherEmoji');
    final temperature = _double(json, 'temperature');
    final temperatureMax = _double(json, 'temperatureMax');
    final temperatureMin = _double(json, 'temperatureMin');
    final windspeed = _double(json, 'windspeed');

    return WeatherSnapshot(
      city: city,
      temperature: temperature,
      temperatureMax: temperatureMax,
      temperatureMin: temperatureMin,
      weatherCode: _int(json, 'weatherCode'),
      weatherText: weatherText,
      weatherEmoji: weatherEmoji,
      isDay: _bool(json, 'isDay'),
      windspeed: windspeed,
      forecastDate: json['forecastDate'] is String
          ? json['forecastDate'] as String
          : null,
      precipitation: _optionalDouble(json, 'precip'),
      humidity: _optionalDouble(json, 'humidity'),
    );
  }

  static String _string(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('天气字段 $key 缺失');
    }
    return value.trim();
  }

  static double _double(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! num) throw FormatException('天气字段 $key 缺失');
    return value.toDouble();
  }

  static double? _optionalDouble(Map<String, dynamic> json, String key) {
    final value = json[key];
    return value is num ? value.toDouble() : null;
  }

  static int _int(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! num) throw FormatException('天气字段 $key 缺失');
    return value.round();
  }

  static bool _bool(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! bool) throw FormatException('天气字段 $key 缺失');
    return value;
  }
}
