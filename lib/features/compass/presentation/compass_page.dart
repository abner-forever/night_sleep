import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/platform/compass.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_basics.dart';
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
  CompassReading? _reading;
  String? _sensorError;
  bool _starting = true;

  /// 读数与滤波后的方位。**不 setState**：每帧重建整页（含顶栏、标题、提示）
  /// 光 build 就要 5 ms，是卡顿的一半来源。只让卡片里那棵子树跟着它重建。
  final _live = ValueNotifier<(CompassReading?, double?)>((null, null));

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
    _reading = null;
    _live.value = (null, null);
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
        _reading = reading;
        _starting = false;
        _sensorError = null;
        _live.value = (reading, heading);
      },
      onError: (Object error) {
        _timeout?.cancel();
        if (!mounted) return;
        setState(() {
          _starting = false;
          _sensorError = error is CompassUnavailable
              ? error.message
              : error is PlatformException && error.code == 'unavailable'
                  ? '此设备没有可用的罗盘传感器'
                  : '暂时无法读取传感器，请检查运动权限或稍后重试';
        });
        _live.value = (null, null);
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
    _live.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    return Subpage(
      title: '罗盘',
      action: Pressable(
        key: const ValueKey('compass-help'),
        semanticLabel: '使用说明',
        onTap: () => context.push('/settings/compass/manual'),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(Icons.menu_book_outlined,
              size: 20, color: tokens.textPrimary),
        ),
      ),
      children: [
        Text('天池罗盘',
            style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: tokens.textPrimary,
                letterSpacing: 1.6)),
        const SizedBox(height: 4),
        Text('转动手机，发现你面向的方向',
            style: TextStyle(fontSize: 12, color: tokens.textMuted)),
        const SizedBox(height: 16),
        GlassSurface(
          borderRadius: BorderRadius.circular(AppRadii.card),
          padding: const EdgeInsets.all(16),
          child: ValueListenableBuilder<(CompassReading?, double?)>(
            valueListenable: _live,
            builder: (context, live, _) {
              final reading = live.$1;
              final displayHeading = live.$2;
              final status = _sensorError ??
                  (_starting
                      ? '正在连接传感器…'
                      : reading!.tilt >= 60
                          ? '请将手机屏幕朝上，保持水平'
                          : reading.needsCalibration || displayHeading == null
                              ? '请远离磁性物体，缓慢画「8」字校准'
                              : '实时感应 · 磁北基准');
              return Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _sensorError == null &&
                                  displayHeading != null &&
                                  !(reading?.needsCalibration ?? true)
                              ? const Color(0xFF34C759)
                              : tokens.warn,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          status,
                          style:
                              TextStyle(fontSize: 12, color: tokens.textMuted),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final diameter =
                          _compassDiameter(context, constraints.maxWidth);
                      final level = reading != null && reading.tilt <= 1.5;
                      return Semantics(
                        label: displayHeading == null
                            ? '罗盘尚无有效方位'
                            : '面向${headingDirection(displayHeading)}，${normalizeHeading(displayHeading.roundToDouble()).toInt()}度'
                                '${reading == null ? '' : level ? '，水平' : '，倾斜${reading.tilt.round()}度'}',
                        child: SizedBox(
                          width: diameter,
                          height: diameter,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // 盘面单独一层：它每帧都重绘，别把水平仪一起拖进去。
                              RepaintBoundary(
                                child: SizedBox(
                                  width: diameter,
                                  height: diameter,
                                  child: CustomPaint(
                                    painter: _CompassPainter(
                                      heading: displayHeading ?? 0,
                                      tokens: tokens,
                                      fontFamily: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.fontFamily,
                                    ),
                                  ),
                                ),
                              ),
                              // 水平仪是**独立的小画笔**，叠在天池中央；它不随盘面转，
                              // 也不在罗盘的重绘范围里——这是它跟得上 60 Hz 的关键。
                              RepaintBoundary(
                                child: _LevelGauge(
                                  size: diameter * .22,
                                  tilt: reading?.tilt,
                                  tiltX: reading?.tiltX,
                                  tiltY: reading?.tiltY,
                                  tokens: tokens,
                                ),
                              ),
                              // 磁针压在液池上面：水平仪在中央，针也完整可见。
                              RepaintBoundary(
                                child: SizedBox(
                                  width: diameter,
                                  height: diameter,
                                  child: CustomPaint(
                                    painter: _CompassNeedlePainter(
                                      heading: displayHeading ?? 0,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    displayHeading == null
                        ? '—°'
                        : '${normalizeHeading(displayHeading.roundToDouble()).toInt()}°',
                    style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1.6,
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
                  const SizedBox(height: 14),
                  Container(height: 1, color: tokens.border),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _CardStat(
                          label: '当前方向',
                          value: displayHeading == null
                              ? '—'
                              : headingDirection(displayHeading),
                          tokens: tokens,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Container(width: 1, height: 18, color: tokens.border),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _CardStat(
                          label: '手机倾斜',
                          value: reading == null
                              ? '—'
                              : '${reading.tilt.round()}°',
                          tokens: tokens,
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
        if (_sensorError != null) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
              onPressed: _restartSensors,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('重新连接')),
        ],
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.screen_rotation_alt_rounded,
                size: 16, color: tokens.textMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '屏幕朝上，顶部指向测量方向；读数不稳时远离磁性物体，缓慢画「8」字校准。',
                style: TextStyle(
                    fontSize: 12, height: 1.5, color: tokens.textMuted),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 罗盘是整页唯一可以伸缩的元素：屏幕高度减掉顶部导航、页面上下留白与
  /// 其余固定内容，剩下的都给它；文字放大时固定内容变高，罗盘相应缩小。
  ///
  /// 这样常见手机上一屏就能放下整页，小屏 + 大字号时仍由 [Subpage] 的
  /// 滚动兜底（不是溢出）。
  double _compassDiameter(BuildContext context, double maxWidth) {
    final media = MediaQuery.of(context);
    // Subpage 的顶部留白 20、底部留白 24，以及吸顶导航行高。
    final chrome = media.padding.vertical + kSubpageNavigationHeight + 20 + 24;
    // 标题、读数、卡片内边距与底部提示这些不随屏幕变化的部分。
    const fixedContent = 340.0;
    final heightCap =
        media.size.height - chrome - fixedContent * media.textScaler.scale(1);
    return math.max(140, math.min(math.min(maxWidth, 520.0), heightCap));
  }
}

/// 卡片底部的紧凑读数：标签与数值排在同一行，省掉一整块卡片的高度。
class _CardStat extends StatelessWidget {
  const _CardStat({
    required this.label,
    required this.value,
    required this.tokens,
  });
  final String label;
  final String value;
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: tokens.textMuted)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: tokens.textPrimary,
              ),
            ),
          ),
        ],
      );
}

/// 外盘水准器。
///
/// **按古法放在天池之外**：罗盘的水准器装在外盘上，天池中央留给磁针。
/// 放在卡片右上角（原「锁定」的位置），既不和磁针抢地方，也能一眼看到。
class _LevelGauge extends StatelessWidget {
  const _LevelGauge({
    required this.size,
    required this.tilt,
    required this.tiltX,
    required this.tiltY,
    required this.tokens,
  });

  final double size;
  final double? tilt;
  final double? tiltX;
  final double? tiltY;
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    final level = tilt != null && tilt! <= 1.5;
    return Semantics(
      container: true,
      label: tilt == null
          ? '水平仪：尚无读数'
          : level
              ? '水平仪：水平'
              : '水平仪：倾斜${tilt!.round()}度',
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _LevelPainter(
            tilt: tilt,
            tiltX: tiltX,
            tiltY: tiltY,
            tokens: tokens,
          ),
        ),
      ),
    );
  }
}

class _LevelPainter extends CustomPainter {
  const _LevelPainter({
    required this.tilt,
    required this.tiltX,
    required this.tiltY,
    required this.tokens,
  });

  final double? tilt;
  final double? tiltX;
  final double? tiltY;
  final AppTokens tokens;

  @override
  void paint(Canvas canvas, Size size) {
    const bronze = Color(0xFF806C4D);
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2 - 1;
    final level = tilt != null && tilt! <= 1.5;
    // 未水平时用冷白，不与金色顶针 / 罗盘花纹混在一起；水平时转薄荷绿。
    final accent = level ? tokens.good : const Color(0xFFD9ECFF);

    // 液池 + 外圈
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader =
            const RadialGradient(colors: [Color(0xFF22344A), Color(0xFF0A141D)])
                .createShader(Rect.fromCircle(center: center, radius: radius)),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = level ? 2 : 1.5
        ..color = level ? tokens.good : bronze,
    );

    // 靶圈：气泡进圈即水平（约 1.5°）
    canvas.drawCircle(
      center,
      radius * .38,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = level ? tokens.good.withValues(alpha: .9) : bronze,
    );

    // 还没读到传感器就不画气泡。
    if (tiltX == null || tiltY == null) return;

    const maxTilt = 12.0;
    final travel = radius - 6;
    var offset = Offset(tiltX! / maxTilt * travel, -tiltY! / maxTilt * travel);
    if (offset.distance > travel) {
      offset = offset / offset.distance * travel;
    }
    final bubbleCenter = center + offset;
    final bubbleRadius = radius * .28;
    canvas.drawCircle(
      bubbleCenter,
      bubbleRadius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.35, -.35),
          colors: [
            const Color(0xFFFFFFFF),
            accent.withValues(alpha: .92),
          ],
        ).createShader(
            Rect.fromCircle(center: bubbleCenter, radius: bubbleRadius)),
    );
    canvas.drawCircle(
      bubbleCenter - Offset(bubbleRadius * .35, bubbleRadius * .4),
      bubbleRadius * .35,
      Paint()..color = const Color(0xB3FFFFFF),
    );
  }

  @override
  bool shouldRepaint(_LevelPainter oldDelegate) =>
      oldDelegate.tilt != tilt ||
      oldDelegate.tiltX != tiltX ||
      oldDelegate.tiltY != tiltY ||
      oldDelegate.tokens != tokens;
}

class _CompassPainter extends CustomPainter {
  const _CompassPainter({
    required this.heading,
    required this.tokens,
    required this.fontFamily,
  });
  final double heading;
  final AppTokens tokens;
  final String? fontFamily;

  /// 盘面文字是**固定**的，每帧重新 layout 几十条 TextPainter 是这页最大的
  /// 绘制开销（60 Hz 下尤其明显）。按文字 / 字号 / 颜色缓存，只做平移和旋转。
  static final Map<String, TextPainter> _textCache = {};

  TextPainter _text(
    String text,
    double fontSize,
    Color color, {
    FontWeight weight = FontWeight.w600,
  }) {
    final key =
        '$text|$fontSize|${color.toARGB32()}|${weight.value}|$fontFamily';
    return _textCache.putIfAbsent(
      key,
      () => TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontFamily: fontFamily,
            color: color,
            fontSize: fontSize,
            fontWeight: weight,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(),
    );
  }

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
    // 外圈刻度带：长刻度从 468 起、短刻度从 484 起，一律画到 495，
    // 给内侧的方位名与度数留出清楚的两圈位置。

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-headingRadians(heading));
    // **刻度批量成两条 Path。** 逐根 `drawLine` 是 180 次绘制调用，60 Hz 下
    // 光这一项就能把 raster 拖过 16 ms。
    final majorTicks = Path();
    final minorTicks = Path();
    // 120 根，每根 3°；每 15 根（45°）一根长刻度，正好和八宫方位名对齐。
    for (var index = 0; index < 120; index++) {
      final angle = index * math.pi / 60;
      final major = index % 15 == 0;
      final inner = radius -
          (major
              ? 36
              : index % 5 == 0
                  ? 30
                  : 22);
      final path = major ? majorTicks : minorTicks;
      path
        ..moveTo(math.sin(angle) * inner, -math.cos(angle) * inner)
        ..lineTo(
          math.sin(angle) * (radius - 5),
          -math.cos(angle) * (radius - 5),
        );
    }
    canvas.drawPath(
        majorTicks,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = gold
          ..strokeWidth = 3.2
          ..strokeCap = StrokeCap.round);
    // 短刻度提亮、加粗：原来那层暗铜色在深蓝底上几乎看不见。
    canvas.drawPath(
        minorTicks,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = const Color(0xFFB7A181).withValues(alpha: .9)
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round);

    // 二十四山紧贴刻度（405），度数再往外（448）；现代方位名（北/东北…）
    // 不再上盘——下方读数已经写着方向，盘上再加一圈只会把山名衬乱。
    for (var index = 0; index < 8; index++) {
      _label(
        canvas,
        '${index * 45}°',
        index * 45.0,
        448,
        const Color(0xFFD4C5A9),
        22,
      );
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
    final mountainTicks = Path();
    for (var index = 0; index < 24; index++) {
      final angle = headingRadians(index * 15 - 7.5);
      mountainTicks
        ..moveTo(_polar(310, angle).dx, _polar(310, angle).dy)
        ..lineTo(_polar(390, angle).dx, _polar(390, angle).dy);
      _label(
          canvas,
          compassMountains[index],
          index * 15.0,
          405,
          index % 6 == 0
              ? red
              : index % 6 == 3
                  ? gold
                  : const Color(0xFFD4C5A9),
          30);
    }
    canvas.drawPath(
        mountainTicks,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = const Color(0xFFB7A181).withValues(alpha: .75)
          ..strokeWidth = 1.4);

    const bagua = ['坎', '艮', '震', '巽', '离', '坤', '兑', '乾'];
    const trigrams = [2, 4, 1, 6, 5, 0, 3, 7];
    // 八卦爻线也合成一条 Path：8 组 × 3 爻原本是 24 次 drawLine，
    // 旋转直接算在坐标上，省掉 8 次 save/rotate/restore。
    final trigramPath = Path();
    void addTrigramLine(double x1, double x2, double y, double angle) {
      final c = math.cos(angle);
      final s = math.sin(angle);
      trigramPath
        ..moveTo(x1 * c - y * s, x1 * s + y * c)
        ..lineTo(x2 * c - y * s, x2 * s + y * c);
    }

    for (var index = 0; index < 8; index++) {
      _label(canvas, bagua[index], index * 45.0, 235, gold, 25);
      final angle = headingRadians(index * 45.0);
      for (var line = 0; line < 3; line++) {
        final vertical = -286.0 + line * 12;
        if ((trigrams[index] & (1 << (2 - line))) != 0) {
          addTrigramLine(-21, 21, vertical, angle);
        } else {
          addTrigramLine(-21, -6, vertical, angle);
          addTrigramLine(6, 21, vertical, angle);
        }
      }
    }
    canvas.drawPath(
        trigramPath,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = gold
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.square);
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
    final innerTicks = Path();
    for (var index = 0; index < 24; index++) {
      final angle = headingRadians(index * 15.0);
      final a = _polar(118, angle);
      final b = _polar(128, angle);
      innerTicks
        ..moveTo(a.dx, a.dy)
        ..lineTo(b.dx, b.dy);
    }
    canvas.drawPath(
        innerTicks,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = bronze
          ..strokeWidth = 1.5);
    canvas.drawLine(const Offset(-115, 0), const Offset(115, 0),
        Paint()..color = bronze.withValues(alpha: .5));
    canvas.drawLine(const Offset(0, -115), const Offset(0, 115),
        Paint()..color = bronze.withValues(alpha: .5));
    // 磁针另起一层画（见 `_CompassNeedlePainter`）：水平仪垫在它下面，
    // 针不会被液池盖住。
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
    final painter = _text(text, fontSize, color);
    painter.paint(canvas, -Offset(painter.width / 2, painter.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CompassPainter oldDelegate) =>
      oldDelegate.heading != heading ||
      oldDelegate.fontFamily != fontFamily ||
      oldDelegate.tokens != tokens;
}

/// 只画天池磁针与海底线的透明图层。
///
/// **单独一层是为了让它压在水平仪上面。** 液池垫在针下，针始终完整可见；
/// 反过来的话，中央的水平仪会把针遮掉大半。
class _CompassNeedlePainter extends CustomPainter {
  const _CompassNeedlePainter({required this.heading});

  final double heading;

  @override
  void paint(Canvas canvas, Size size) {
    const center = Offset.zero;
    const radius = 500.0;
    const gold = Color(0xFFC9A86C);
    const red = Color(0xFFD94A42);

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(size.shortestSide / 1000);
    canvas.rotate(-headingRadians(heading));

    // 天池海底线：古法在池底画红线，磁针指北端与它重合。
    canvas.drawLine(
        const Offset(0, -126),
        const Offset(0, 126),
        Paint()
          ..color = red.withValues(alpha: .45)
          ..strokeWidth = 2);

    // 磁针：红头朝北、白尾指南，中心是顶针。
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
  }

  @override
  bool shouldRepaint(_CompassNeedlePainter oldDelegate) =>
      oldDelegate.heading != heading;
}
