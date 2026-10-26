import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../domain/location_fix.dart';

/// 取不到位置的原因。
///
/// **每一种都要分开**，因为界面要给的出路不同：权限被永久拒绝时给「去设置」，
/// 系统定位总开关关着时给「去设置（定位）」，超时才是「重试」。把三种都说成
/// 「稍后自动重试」，等于让用户对着一个永远不会好的按钮反复点。
enum DeviceLocationFailure {
  /// 系统定位总开关关着（`isLocationServiceEnabled()` 为 false）。
  serviceDisabled,

  /// 这一次被拒绝了，还能再问一次。
  permissionDenied,

  /// 选了「不再询问」，只能去系统设置里打开。
  permissionDeniedForever,

  /// 权限和服务都正常，但没拿到坐标：超时、室内无信号，或插件压根不可用
  /// （单元测试、桌面平台）。
  unavailable,
}

/// 一次定位尝试的结果。用 sealed 而不是「返回可空坐标」，是为了让失败原因
/// 必须被处理——不然很容易写成 `?? 上海` 那种假数据兜底。
sealed class DeviceLocationResult {
  const DeviceLocationResult();
}

final class DeviceLocationFix extends DeviceLocationResult {
  const DeviceLocationFix(this.fix);

  final LocationFix fix;
}

final class DeviceLocationMiss extends DeviceLocationResult {
  const DeviceLocationMiss(this.reason);

  final DeviceLocationFailure reason;
}

/// 定位能力的接缝。测试用假实现顶掉，**绝不在测试里真调平台通道**。
abstract interface class DeviceLocation {
  /// 取当前位置。
  ///
  /// [interactive] 为 false 时**绝不弹系统权限框**——只使用已经授予的权限，
  /// 没授权就返回 [DeviceLocationMiss]。启动后的静默尝试走这条路；只有用户
  /// 主动点「使用我的位置」时才传 true。
  Future<DeviceLocationResult> current({bool interactive = false});

  /// 打开本应用的系统设置页（权限被永久拒绝时用）。
  Future<void> openAppSettings();

  /// 打开系统的定位开关页（定位服务整体关着时用）。
  Future<void> openLocationSettings();
}

/// Android 侧手写的网络定位通道，实现在
/// `android/app/src/main/kotlin/com/abner/night_sleep/NetworkLocationHandler.kt`。
const _networkLocationChannel = MethodChannel('night_sleep/network_location');

/// 真实实现：Android 先问系统 network provider，其余平台用 `geolocator`。
///
/// **只申请「大致位置」**（`ACCESS_COARSE_LOCATION`）。城市级天气不需要精确到
/// 楼栋，Android 12+ 让用户选「大致位置」本来就是更合理的默认值；申请精确定位
/// 只会多一次被拒的机会。
///
/// ## 为什么 Android 不用 `geolocator` 取位
///
/// 它在 Android 上把 provider 固定选成 GPS（`LocationManagerClient` 的
/// `determineProvider()` 顺序是 `passive → fused(API 31+) → GPS → NETWORK`），
/// 只要 GPS provider「可用」就永远不碰 network。而「可用」不等于「有信号」：
/// 室内一个 fix 都给不出来。
///
/// 小米 9（Android 11 / MIUI 12.5）上的实测，`geolocator` 每条路径都超时——
/// 融合定位（Google FLP 在境内不可用，但 GMS 包在，插件不会自动回退）、
/// LocationManager low/medium/best（请求被系统标成 ACCURACY_BLOCK 并派给 gps）、
/// `getPositionStream` 十秒无事件。同一台机器直接问 network provider，**67ms**
/// 返回 `ageMs=4` 的坐标，精度约 2km——城市级天气够用。
///
/// ## 三档兜底（共用一份总预算）
///
/// 1. network provider（Android，百毫秒级）
/// 2. 系统里的已知位置，**足够新**才直接采用
/// 3. 实时定位（室外 GPS 有信号时才会成功，室内通常白等几秒）
///
/// 第三档失败后还会再回一次已知位置：这一档的时间窗口放得更宽，因为
/// 「两小时前的坐标」对「今天多少度」仍然成立，而「没有位置」对用户毫无用处。
/// 每一档只花「总预算里剩下」的时间，不会层层叠加成一个让首页空着十几秒的等待。
class GeolocatorDeviceLocation implements DeviceLocation {
  const GeolocatorDeviceLocation();

  /// 城市级定位不需要久等。GPS 冷启动在室内常常超过这个时间，超时就如实说
  /// 拿不到，让用户自己决定要不要再试。
  ///
  /// 静默那次给得更短：用户没在等权限框，只是在等首页。
  static const _interactiveBudget = Duration(seconds: 12);
  static const _silentBudget = Duration(seconds: 5);

  /// 单看 network provider 的时间上限。正常是百毫秒级，等这么久还没有就是没有。
  static const _networkTimeout = Duration(seconds: 4);

  /// 已知位置多久算「够新」：直接采用，不打扰系统去实时定位。
  static const _freshWindow = Duration(minutes: 15);

  /// 实时定位失败后，还能退而求其次用多久以内的已知位置。
  ///
  /// 两小时内的位置对城市级天气基本成立；再旧就可能是另一座城市了，
  /// 那种情况下宁可显示「无法获取位置」。
  static const _staleWindow = Duration(hours: 2);

  @override
  Future<DeviceLocationResult> current({bool interactive = false}) async {
    // 桌面端与单元测试里没有这个插件。**一律吞成 unavailable**：定位是旁路，
    // 不能因为一台设备没有定位就让整个首页报错。
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const DeviceLocationMiss(DeviceLocationFailure.serviceDisabled);
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.deniedForever) {
        return const DeviceLocationMiss(
          DeviceLocationFailure.permissionDeniedForever,
        );
      }
      if (permission == LocationPermission.denied) {
        if (!interactive) {
          // 静默路径到此为止：没授权就什么都不做，等用户主动点。
          return const DeviceLocationMiss(
            DeviceLocationFailure.permissionDenied,
          );
        }
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.deniedForever) {
          return const DeviceLocationMiss(
            DeviceLocationFailure.permissionDeniedForever,
          );
        }
        if (permission == LocationPermission.denied) {
          return const DeviceLocationMiss(
              DeviceLocationFailure.permissionDenied);
        }
      }

      final deadline = DateTime.now().add(
        interactive ? _interactiveBudget : _silentBudget,
      );
      final fix = await _resolveFix(deadline);
      if (fix == null) {
        return const DeviceLocationMiss(DeviceLocationFailure.unavailable);
      }
      return DeviceLocationFix(fix);
    } on Object {
      return const DeviceLocationMiss(DeviceLocationFailure.unavailable);
    }
  }

  Future<LocationFix?> _resolveFix(DateTime deadline) async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final network = await _networkFix(deadline);
      if (network != null) return network;
    }

    final cached = await _knownFix(_freshWindow, deadline);
    if (cached != null) return cached;

    final live = await _liveFix(deadline);
    if (live != null) return live;

    // 最后再退一次：这一次接受更旧的坐标。走到这里说明实时定位确实拿不到
    // （多数是室内），「两小时前的城市」仍比「没有位置」有用。
    return _knownFix(_staleWindow, deadline);
  }

  /// Android 的 network provider。拿不到就返回 null，交给后面的兜底。
  Future<LocationFix?> _networkFix(DateTime deadline) async {
    final budget = _remaining(deadline, cap: _networkTimeout);
    if (budget <= Duration.zero) return null;

    try {
      // 超时交给原生侧自己收尾：Dart 这边先超时会让通道收到一个「已经完成」
      // 的回包。多留 400ms 给回包在路上。
      final payload = await _networkLocationChannel
          .invokeMethod<Map<Object?, Object?>>('current', {
        'timeoutMs': budget.inMilliseconds,
      }).timeout(budget + const Duration(milliseconds: 400));
      if (payload == null) return null;
      final latitude = (payload['latitude'] as num?)?.toDouble();
      final longitude = (payload['longitude'] as num?)?.toDouble();
      if (latitude == null || longitude == null) return null;
      return LocationFix(latitude: latitude, longitude: longitude);
    } on Object {
      // 通道缺失（测试 / 其它平台）、超时、权限异常：都当成「这次没有」。
      return null;
    }
  }

  /// 系统里缓存的最后一次位置。用 `forceAndroidLocationManager` 是有意的：
  /// 融合 provider 在这类设备上连缓存都是 null。
  Future<LocationFix?> _knownFix(Duration window, DateTime deadline) async {
    final budget = _remaining(deadline, cap: const Duration(seconds: 3));
    if (budget <= Duration.zero) return null;

    try {
      final position = await Geolocator.getLastKnownPosition(
        forceAndroidLocationManager: true,
      ).timeout(budget);
      if (position == null) return null;
      final age = DateTime.now().difference(position.timestamp);
      if (age.isNegative || age > window) return null;
      return LocationFix(
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } on Object {
      return null;
    }
  }

  Future<LocationFix?> _liveFix(DateTime deadline) async {
    final budget = _remaining(deadline, cap: const Duration(seconds: 10));
    if (budget <= Duration.zero) return null;

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: budget,
        ),
      );
      return LocationFix(
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } on Object {
      return null;
    }
  }

  /// 这一步还剩多少时间可用，且不超过 [cap]。
  Duration _remaining(DateTime deadline, {required Duration cap}) {
    final left = deadline.difference(DateTime.now());
    if (left.isNegative) return Duration.zero;
    return left < cap ? left : cap;
  }

  @override
  Future<void> openAppSettings() async {
    try {
      await Geolocator.openAppSettings();
    } on Object {
      // 跳不过去也不该打断界面，用户自己也能从系统设置里找到。
    }
  }

  @override
  Future<void> openLocationSettings() async {
    try {
      await Geolocator.openLocationSettings();
    } on Object {
      // 同上。
    }
  }
}

final deviceLocationProvider = Provider<DeviceLocation>(
  (ref) => const GeolocatorDeviceLocation(),
);
