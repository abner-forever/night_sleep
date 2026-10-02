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
      required this.fieldStrength,
      required this.accuracy});

  factory CompassReading.fromMap(Map<Object?, Object?> values) =>
      CompassReading(
        heading: (values['heading'] as num?)?.toDouble(),
        timestamp: (values['timestamp'] as num).toDouble(),
        rotationRate: (values['rotationRate'] as num).toDouble(),
        tilt: (values['tilt'] as num).toDouble(),
        fieldStrength: (values['fieldStrength'] as num).toDouble(),
        accuracy: (values['accuracy'] as num).toInt(),
      );

  final double? heading;
  final double timestamp;
  final double rotationRate;
  final double tilt;
  final double fieldStrength;
  final int accuracy;

  bool get needsCalibration => accuracy < 1 || fieldStrength > 100;
}

class CompassHeadingFilter {
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
      final correction = 1 - math.exp(-elapsed / 0.18);
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
