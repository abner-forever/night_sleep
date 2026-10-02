import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/platform/compass.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/glass_surface.dart';
import '../../../core/widgets/subpage.dart';
import '../domain/compass_heading.dart';

class CompassPage extends StatefulWidget {
  const CompassPage({super.key, this.source = const CompassSource()});

  final CompassSource source;

  @override
  State<CompassPage> createState() => _CompassPageState();
}

class _CompassPageState extends State<CompassPage> with WidgetsBindingObserver {
  StreamSubscription<CompassReading>? _subscription;
  Timer? _timeout;
  final _filter = CompassHeadingFilter();
  double? _heading;
  CompassReading? _reading;
  double? _lockedHeading;
  String? _sensorError;
  bool _starting = true;

  bool get _locked => _lockedHeading != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startSensors();
  }

  void _startSensors() {
    _timeout?.cancel();
    _filter.reset();
    _starting = true;
    _sensorError = null;
    _heading = null;
    _reading = null;
    _timeout = Timer(const Duration(seconds: 5), () {
      if (mounted && _reading == null) {
        setState(() {
          _starting = false;
          _sensorError = '未收到传感器数据，请检查设备或稍后重试';
        });
      }
    });
    _subscription = widget.source.readings().listen(
      (reading) {
        _timeout?.cancel();
        final heading = _filter.update(reading);
        if (!mounted) return;
        setState(() {
          _heading = heading;
          _reading = reading;
          _starting = false;
          _sensorError = null;
        });
      },
      onError: (Object error) {
        _timeout?.cancel();
        if (!mounted) return;
        setState(() {
          _starting = false;
          _heading = null;
          _sensorError = error is CompassUnavailable
              ? error.message
              : error is PlatformException && error.code == 'unavailable'
                  ? '此设备没有可用的罗盘传感器'
                  : '暂时无法读取传感器，请检查运动权限或稍后重试';
        });
      },
      cancelOnError: true,
    );
  }

  Future<void> _stopSensors() async {
    _timeout?.cancel();
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
  }

  void _restartSensors() {
    _timeout?.cancel();
    final subscription = _subscription;
    _subscription = null;
    subscription?.cancel();
    if (mounted) setState(_startSensors);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _restartSensors();
    } else {
      _stopSensors();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopSensors();
    super.dispose();
  }

  void _toggleLock() {
    setState(() {
      _lockedHeading = _locked ? null : _heading;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final displayHeading = _lockedHeading ?? _heading;
    final status = _sensorError ??
        (_starting
            ? '正在连接传感器…'
            : _reading!.tilt >= 60
                ? '请将手机屏幕朝上，保持水平'
                : _reading!.needsCalibration || _heading == null
                    ? '请远离磁性物体，缓慢画「8」字校准'
                    : _locked
                        ? '方向已锁定'
                        : '实时感应 · 磁北基准');

    return Subpage(
      title: '罗盘',
      children: [
        Text('天池罗盘',
            style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: tokens.textPrimary,
                letterSpacing: 2)),
        const SizedBox(height: 6),
        Text('转动手机，发现你面向的方向',
            style: TextStyle(fontSize: 13, color: tokens.textMuted)),
        const SizedBox(height: 20),
        GlassSurface(
          borderRadius: BorderRadius.circular(AppRadii.card),
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _sensorError == null &&
                              _heading != null &&
                              !(_reading?.needsCalibration ?? true)
                          ? const Color(0xFF34C759)
                          : tokens.warn,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      status,
                      style: TextStyle(fontSize: 12, color: tokens.textMuted),
                    ),
                  ),
                  _LockButton(
                      locked: _locked,
                      onTap: _heading != null || _locked ? _toggleLock : null),
                ],
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final diameter = math.min(constraints.maxWidth, 520.0);
                  return Semantics(
                    label: displayHeading == null
                        ? '罗盘尚无有效方位'
                        : '面向${headingDirection(displayHeading)}，${normalizeHeading(displayHeading.roundToDouble()).toInt()}度',
                    child: SizedBox(
                      width: diameter,
                      height: diameter,
                      child: CustomPaint(
                        painter: _CompassPainter(
                          heading: displayHeading ?? 0,
                          tokens: tokens,
                          locked: _locked,
                          fontFamily: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.fontFamily,
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              Text(
                displayHeading == null
                    ? '—°'
                    : '${normalizeHeading(displayHeading.roundToDouble()).toInt()}°',
                style: TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1.8,
                  color: tokens.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                displayHeading == null
                    ? '等待有效方位'
                    : '${headingDirection(displayHeading)} · ${headingMountain(displayHeading)}山',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: tokens.accent,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _InfoCard(
                label: '当前方向',
                value: displayHeading == null
                    ? '—'
                    : headingDirection(displayHeading),
                tokens: tokens,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _InfoCard(
                  label: '手机倾斜',
                  value: _reading == null ? '—' : '${_reading!.tilt.round()}°',
                  tokens: tokens),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (_sensorError != null) ...[
          OutlinedButton.icon(
              onPressed: _restartSensors,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('重新连接')),
          const SizedBox(height: 14),
        ],
        GlassSurface(
          borderRadius: BorderRadius.circular(AppRadii.panel),
          padding: const EdgeInsets.all(18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.screen_rotation_alt_rounded,
                  size: 22, color: tokens.accent),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('让方向更准确',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: tokens.textPrimary)),
                    const SizedBox(height: 5),
                    Text('屏幕朝上，手机顶部指向测量方向。若读数不稳，远离磁吸壳、音箱等物体，缓慢画「8」字帮助校准。',
                        style: TextStyle(
                            fontSize: 12,
                            height: 1.6,
                            color: tokens.textMuted)),
                  ])),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          '将手机平放，远离磁性物体。罗盘显示磁北方向，建筑物和电子设备可能造成短暂偏差。',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, height: 1.5, color: tokens.textMuted),
        ),
      ],
    );
  }
}

class _LockButton extends StatelessWidget {
  const _LockButton({required this.locked, required this.onTap});
  final bool locked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Semantics(
      button: true,
      label: locked ? '解锁罗盘' : '锁定方向',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 58),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: locked ? tokens.accentSoft : tokens.bgMuted,
            borderRadius: BorderRadius.circular(AppRadii.pill),
          ),
          child: Text(
            locked ? '已锁定' : '锁定',
            style: TextStyle(
              fontSize: 12,
              color: locked ? tokens.accent : tokens.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.label,
    required this.value,
    required this.tokens,
  });
  final String label;
  final String value;
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) => GlassSurface(
        borderRadius: BorderRadius.circular(AppRadii.panel),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(fontSize: 12, color: tokens.textMuted)),
            const SizedBox(height: 3),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: tokens.textPrimary,
              ),
            ),
          ],
        ),
      );
}

class _CompassPainter extends CustomPainter {
  const _CompassPainter({
    required this.heading,
    required this.tokens,
    required this.locked,
    required this.fontFamily,
  });
  final double heading;
  final AppTokens tokens;
  final bool locked;
  final String? fontFamily;

  @override
  void paint(Canvas canvas, Size size) {
    const center = Offset.zero;
    const radius = 500.0;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(size.shortestSide / 1000);
    const gold = Color(0xFFC9A86C);
    const bronze = Color(0xFF806C4D);
    const red = Color(0xFFD94A42);
    const dark = Color(0xFF10151D);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = const RadialGradient(colors: [Color(0xFF26344B), dark])
            .createShader(Rect.fromCircle(center: center, radius: radius)),
    );
    canvas.drawCircle(
      center,
      radius - 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = gold,
    );
    canvas.drawCircle(
      center,
      radius - 15,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = bronze,
    );
    canvas.drawCircle(
      center,
      radius - 90,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = bronze.withValues(alpha: .75),
    );

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-headingRadians(heading));
    final tickPaint = Paint()..strokeCap = StrokeCap.round;
    for (var index = 0; index < 180; index++) {
      final angle = index * math.pi * 2 / 180;
      final major = index % 15 == 0;
      final inner = radius -
          (major
              ? 48
              : index % 5 == 0
                  ? 35
                  : 28);
      tickPaint
        ..color = major ? gold : bronze
        ..strokeWidth = major ? 3 : 1.5;
      canvas.drawLine(
        Offset(math.sin(angle) * inner, -math.cos(angle) * inner),
        Offset(
          math.sin(angle) * (radius - 14),
          -math.cos(angle) * (radius - 14),
        ),
        tickPaint,
      );
    }
    final labels = ['北', '东北', '东', '东南', '南', '西南', '西', '西北'];
    for (var index = 0; index < labels.length; index++) {
      final angle = index * math.pi / 4;
      final position = Offset(
        math.sin(angle) * 425,
        -math.cos(angle) * 425,
      );
      final painter = TextPainter(
        text: TextSpan(
          text: labels[index],
          style: TextStyle(
            fontFamily: fontFamily,
            color: index == 0 ? red : const Color(0xFFD4C5A9),
            fontSize: index % 2 == 0 ? 34 : 24,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      canvas.save();
      canvas.translate(position.dx, position.dy);
      canvas.rotate(headingRadians(heading));
      painter.paint(
        canvas,
        -Offset(painter.width / 2, painter.height / 2),
      );
      canvas.restore();
    }
    for (final ring in [390.0, 310.0, 210.0, 170.0]) {
      canvas.drawCircle(
          center,
          ring,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = bronze);
    }
    for (var index = 0; index < 24; index++) {
      final angle = headingRadians(index * 15 - 7.5);
      canvas.drawLine(
          _polar(310, angle),
          _polar(390, angle),
          Paint()
            ..color = bronze.withValues(alpha: .6)
            ..strokeWidth = 1);
      _label(
          canvas,
          compassMountains[index],
          index * 15.0,
          350,
          index % 6 == 0
              ? red
              : index % 6 == 3
                  ? gold
                  : const Color(0xFFD4C5A9),
          32);
    }
    const bagua = ['坎', '艮', '震', '巽', '离', '坤', '兑', '乾'];
    const trigrams = [2, 4, 1, 6, 5, 0, 3, 7];
    for (var index = 0; index < 8; index++) {
      _label(canvas, bagua[index], index * 45.0, 235, gold, 25);
      canvas.save();
      canvas.rotate(headingRadians(index * 45.0));
      final linePaint = Paint()
        ..color = gold
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.square;
      for (var line = 0; line < 3; line++) {
        final vertical = -286.0 + line * 12;
        if ((trigrams[index] & (1 << (2 - line))) != 0) {
          canvas.drawLine(
              Offset(-21, vertical), Offset(21, vertical), linePaint);
        } else {
          canvas.drawLine(
              Offset(-21, vertical), Offset(-6, vertical), linePaint);
          canvas.drawLine(Offset(6, vertical), Offset(21, vertical), linePaint);
        }
      }
      canvas.restore();
    }
    canvas.drawCircle(
        center,
        155,
        Paint()
          ..shader = const RadialGradient(
                  colors: [Color(0xFF203345), Color(0xFF0A141D)])
              .createShader(Rect.fromCircle(center: center, radius: 155)));
    for (final ring in [155.0, 143.0, 130.0]) {
      canvas.drawCircle(
          center,
          ring,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = ring == 155 ? 3 : 1
            ..color = bronze);
    }
    for (var index = 0; index < 24; index++) {
      final angle = headingRadians(index * 15.0);
      canvas.drawLine(
          _polar(118, angle),
          _polar(128, angle),
          Paint()
            ..color = bronze
            ..strokeWidth = 1.5);
    }
    canvas.drawLine(const Offset(-115, 0), const Offset(115, 0),
        Paint()..color = bronze.withValues(alpha: .5));
    canvas.drawLine(const Offset(0, -115), const Offset(0, 115),
        Paint()..color = bronze.withValues(alpha: .5));
    const needleScale = 130 / (radius * .45);
    canvas.save();
    canvas.scale(needleScale);

    final needle = Path()
      ..moveTo(center.dx, center.dy - radius * .45)
      ..lineTo(center.dx - 10, center.dy + 2)
      ..lineTo(center.dx, center.dy + 10)
      ..lineTo(center.dx + 10, center.dy + 2)
      ..close();
    canvas.drawPath(needle, Paint()..color = red);
    final south = Path()
      ..moveTo(center.dx, center.dy + radius * .45)
      ..lineTo(center.dx - 10, center.dy - 2)
      ..lineTo(center.dx, center.dy - 10)
      ..lineTo(center.dx + 10, center.dy - 2)
      ..close();
    canvas.drawPath(south, Paint()..color = const Color(0xFFE8EDF2));
    canvas.drawCircle(center, 9, Paint()..color = gold);
    canvas.drawCircle(center, 4, Paint()..color = const Color(0xFFFFE28B));
    canvas.restore();
    canvas.restore();
    final pointer = Path()
      ..moveTo(-12, -490)
      ..lineTo(12, -490)
      ..lineTo(0, -465)
      ..close();
    canvas.drawPath(pointer, Paint()..color = gold);
    canvas.drawLine(
        const Offset(0, -406),
        const Offset(0, -180),
        Paint()
          ..color = gold.withValues(alpha: .3)
          ..strokeWidth = 1.5);
    if (locked) {
      canvas.drawCircle(
        center,
        radius - 5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = tokens.accent.withValues(alpha: .8),
      );
    }
    canvas.restore();
  }

  Offset _polar(double radius, double angle) =>
      Offset(math.sin(angle) * radius, -math.cos(angle) * radius);

  void _label(Canvas canvas, String text, double degrees, double radius,
      Color color, double fontSize) {
    final position = _polar(radius, headingRadians(degrees));
    canvas.save();
    canvas.translate(position.dx, position.dy);
    canvas.rotate(headingRadians(heading));
    final painter = TextPainter(
        text: TextSpan(
            text: text,
            style: TextStyle(
                fontFamily: fontFamily,
                color: color,
                fontSize: fontSize,
                fontWeight: FontWeight.w600)),
        textDirection: TextDirection.ltr)
      ..layout();
    painter.paint(canvas, -Offset(painter.width / 2, painter.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CompassPainter oldDelegate) =>
      oldDelegate.heading != heading ||
      oldDelegate.locked != locked ||
      oldDelegate.fontFamily != fontFamily ||
      oldDelegate.tokens != tokens;
}
