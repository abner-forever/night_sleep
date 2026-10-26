import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:night_sleep/features/home/data/device_location.dart';

/// geolocator 自己的通道。这条通道在测试里必须被打桩——真机上它背后是
/// GPS/融合定位，测试里调它只会永远不回复。
const _geolocatorChannel = MethodChannel('flutter.baseflow.com/geolocator');

/// 本工程手写的 Android 网络定位通道，
/// 实现见 `android/.../NetworkLocationHandler.kt`。
const _networkChannel = MethodChannel('night_sleep/network_location');

/// 记录每个通道被调了几次，用来断言「拿到就不该再往下试」。
class _Calls {
  int network = 0;
  int lastKnown = 0;
  int current = 0;
  int requestPermission = 0;
}

Map<String, Object?> _position({
  required double latitude,
  required double longitude,
  required Duration age,
}) {
  return {
    'latitude': latitude,
    'longitude': longitude,
    'accuracy': 2000.0,
    'timestamp': DateTime.now().subtract(age).millisecondsSinceEpoch.toDouble(),
  };
}

Future<void> _stub({
  required _Calls calls,
  Map<String, Object?>? networkResult,
  Map<String, Object?>? lastKnown,
  Object? currentError,
  LocationPermission permission = LocationPermission.whileInUse,
  bool serviceEnabled = true,
}) async {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  messenger.setMockMethodCallHandler(_networkChannel, (call) async {
    calls.network++;
    return networkResult;
  });

  messenger.setMockMethodCallHandler(_geolocatorChannel, (call) async {
    switch (call.method) {
      case 'isLocationServiceEnabled':
        return serviceEnabled;
      case 'checkPermission':
        return permission.index;
      case 'requestPermission':
        calls.requestPermission++;
        return permission.index;
      case 'getLastKnownPosition':
        calls.lastKnown++;
        return lastKnown;
      case 'getCurrentPosition':
        calls.current++;
        if (currentError != null) throw currentError;
        return null;
    }
    return null;
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_networkChannel, null);
    messenger.setMockMethodCallHandler(_geolocatorChannel, null);
  });

  test('Android 先问 network provider，拿到就不再去碰 GPS', () async {
    // 这条是本文件存在的理由：小米 9 上 geolocator 每条路径都超时，
    // 唯一能出结果的是系统的 network provider。
    final calls = _Calls();
    await _stub(
      calls: calls,
      networkResult: {
        'latitude': 22.5766,
        'longitude': 113.9191,
        'accuracy': 2000.0,
        'ageMs': 4,
      },
    );

    final result = await const GeolocatorDeviceLocation().current();

    expect(result, isA<DeviceLocationFix>());
    final fix = (result as DeviceLocationFix).fix;
    expect(fix.latitude, closeTo(22.5766, 1e-4));
    expect(fix.longitude, closeTo(113.9191, 1e-4));
    expect(fix.query, '113.92,22.58');
    expect(calls.network, 1);
    expect(calls.lastKnown, 0, reason: '有坐标就不该再读缓存');
    expect(calls.current, 0, reason: '有坐标就不该再等实时定位');
  });

  test('network 拿不到时退回足够新的已知位置', () async {
    final calls = _Calls();
    await _stub(
      calls: calls,
      networkResult: null,
      lastKnown: _position(
        latitude: 31.2345,
        longitude: 121.4712,
        age: const Duration(minutes: 2),
      ),
    );

    final result = await const GeolocatorDeviceLocation().current();

    expect(result, isA<DeviceLocationFix>());
    expect((result as DeviceLocationFix).fix.query, '121.47,31.23');
    expect(calls.lastKnown, 1);
    expect(calls.current, 0, reason: '缓存够新就不该再等实时定位');
  });

  test('已知位置太旧时宁可不给，也不拿几小时前的城市充数', () async {
    final calls = _Calls();
    await _stub(
      calls: calls,
      networkResult: null,
      lastKnown: _position(
        latitude: 39.9042,
        longitude: 116.4074,
        age: const Duration(hours: 6),
      ),
      currentError: PlatformException(code: 'TIMEOUT'),
    );

    final result = await const GeolocatorDeviceLocation().current();

    expect(result, isA<DeviceLocationMiss>());
    expect(
      (result as DeviceLocationMiss).reason,
      DeviceLocationFailure.unavailable,
    );
    // 缓存被读过两次：一次找「够新」的，一次是实时失败后的放宽兜底。
    expect(calls.lastKnown, 2);
    expect(calls.current, 1);
  });

  test('没授权时静默路径不申请权限，也不问任何 provider', () async {
    final calls = _Calls();
    await _stub(calls: calls, permission: LocationPermission.denied);

    final result = await const GeolocatorDeviceLocation().current();

    expect(result, isA<DeviceLocationMiss>());
    expect(
      (result as DeviceLocationMiss).reason,
      DeviceLocationFailure.permissionDenied,
    );
    expect(calls.requestPermission, 0);
    expect(calls.network, 0);
  });

  test('系统定位总开关关着时单独归类，界面才好指向定位开关', () async {
    final calls = _Calls();
    await _stub(calls: calls, serviceEnabled: false);

    final result = await const GeolocatorDeviceLocation().current();

    expect(result, isA<DeviceLocationMiss>());
    expect(
      (result as DeviceLocationMiss).reason,
      DeviceLocationFailure.serviceDisabled,
    );
  });
}
