import 'dart:math' as math;

double normalizeHeading(double heading) => (heading % 360 + 360) % 360;

double headingDelta(double from, double to) =>
    (normalizeHeading(to) - normalizeHeading(from) + 540) % 360 - 180;

const compassDirections = ['北', '东北', '东', '东南', '南', '西南', '西', '西北'];
const compassMountains = [
  '子',
  '癸',
  '丑',
  '艮',
  '寅',
  '甲',
  '卯',
  '乙',
  '辰',
  '巽',
  '巳',
  '丙',
  '午',
  '丁',
  '未',
  '坤',
  '申',
  '庚',
  '酉',
  '辛',
  '戌',
  '乾',
  '亥',
  '壬',
];

String headingDirection(double heading) =>
    compassDirections[((normalizeHeading(heading) + 22.5) / 45).floor() % 8];

String headingMountain(double heading) =>
    compassMountains[((normalizeHeading(heading) + 7.5) / 15).floor() % 24];

double headingRadians(double heading) => heading * math.pi / 180;

class CompassReading {
  const CompassReading(
      {this.heading,
      required this.timestamp,
      required this.rotationRate,
      required this.tilt,
      required this.tiltX,
      required this.tiltY,
      required this.fieldStrength,
      required this.accuracy});

  factory CompassReading.fromMap(Map<Object?, Object?> values) =>
      CompassReading(
        heading: (values['heading'] as num?)?.toDouble(),
        timestamp: (values['timestamp'] as num).toDouble(),
        rotationRate: (values['rotationRate'] as num).toDouble(),
        tilt: (values['tilt'] as num).toDouble(),
        tiltX: (values['tiltX'] as num).toDouble(),
        tiltY: (values['tiltY'] as num).toDouble(),
        fieldStrength: (values['fieldStrength'] as num).toDouble(),
        accuracy: (values['accuracy'] as num).toInt(),
      );

  final double? heading;
  final double timestamp;
  final double rotationRate;

  /// 相对水平面的总倾角（度），0 = 平放屏幕朝上。
  final double tilt;

  /// 沿设备 +X 轴（屏幕右侧）的倾斜分量（度）。
  ///
  /// 正值 = 右侧抬起。与 [tiltY] 一起供罗盘中心的水平仪定位气泡；单独用
  /// [tilt] 只能知道「斜了多少」，不知道「往哪边斜」。
  final double tiltX;

  /// 沿设备 +Y 轴（屏幕上方）的倾斜分量（度）。正值 = 顶部抬起。
  final double tiltY;

  final double fieldStrength;
  final int accuracy;

  bool get needsCalibration => accuracy < 1 || fieldStrength > 100;
}

class CompassHeadingFilter {
  /// 跟随的时间常数：既有余量压住残余噪声，又不至于拖在转动后面。
  ///
  /// **不要再按「静止 / 转动」分档加重滤波。** 试过静止 0.6 s、转动 0.18 s 的
  /// 分档：静止时不抖了，但慢速转动（角速度低于分档阈值）既不预测、又只按
  /// 每帧约 5% 蹭过去，指针一卡一卡的。稳态的平稳应当由传感器融合（Android
  /// 的旋转矢量 / iOS 的 CoreMotion）保证，这里只负责跟随。
  static const _tau = 0.18;

  double? _heading;
  double? _timestamp;

  double? update(CompassReading reading) {
    final magneticHeading = reading.heading;
    if (magneticHeading == null || !magneticHeading.isFinite) {
      reset();
      return null;
    }
    final elapsed = _timestamp == null ? 0.0 : reading.timestamp - _timestamp!;
    if (_heading == null || elapsed <= 0 || elapsed > 0.5) {
      _heading = normalizeHeading(magneticHeading);
    } else {
      final predicted =
          _heading! + reading.rotationRate * elapsed * 180 / math.pi;
      final correction = 1 - math.exp(-elapsed / _tau);
      _heading = normalizeHeading(
          predicted + headingDelta(predicted, magneticHeading) * correction);
    }
    _timestamp = reading.timestamp;
    return _heading;
  }

  void reset() {
    _heading = null;
    _timestamp = null;
  }
}
