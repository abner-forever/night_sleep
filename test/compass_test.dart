import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/core/platform/compass.dart';
import 'package:night_sleep/core/theme/app_theme.dart';
import 'package:night_sleep/features/compass/domain/compass_heading.dart';
import 'package:night_sleep/features/compass/presentation/compass_page.dart';

class FakeCompassSource extends CompassSource {
  final controller = StreamController<CompassReading>.broadcast(sync: true);
  int subscriptions = 0;

  @override
  Stream<CompassReading> readings() {
    subscriptions++;
    return controller.stream;
  }
}

CompassReading reading(double? heading,
        {double timestamp = 1,
        double rotationRate = 0,
        double tilt = 0,
        int accuracy = 3,
        double fieldStrength = 45}) =>
    CompassReading(
      heading: heading,
      timestamp: timestamp,
      rotationRate: rotationRate,
      tilt: tilt,
      accuracy: accuracy,
      fieldStrength: fieldStrength,
    );

void main() {
  test('方向与二十四山边界正确，负角度和整圈归一化', () {
    expect(normalizeHeading(-1), 359);
    expect(normalizeHeading(720), 0);
    expect(headingDirection(22.49), '北');
    expect(headingDirection(22.5), '东北');
    expect(headingDirection(90), '东');
    expect(headingDirection(337.5), '北');
    expect(headingMountain(7.49), '子');
    expect(headingMountain(7.5), '癸');
    expect(headingMountain(352.5), '子');
    expect(headingMountain(315), '乾');
    expect(headingDelta(359, 1), 2);
    expect(headingDelta(1, 359), -2);
  });

  test('陀螺仪预测转动，磁场修正漂移，跨北方不绕远路', () {
    final filter = CompassHeadingFilter();
    expect(filter.update(reading(359)), 359);
    final north = filter.update(reading(1, timestamp: 1.02))!;
    expect(north, greaterThan(359));
    expect(north, lessThan(360));
    filter.reset();
    filter.update(reading(0));
    final rotated =
        filter.update(reading(9, timestamp: 1.1, rotationRate: math.pi / 2))!;
    expect(rotated, closeTo(9, .0001));
    expect(filter.update(reading(null, timestamp: 1.2)), isNull);
    expect(filter.update(reading(270, timestamp: 4)), 270);
  });

  Future<void> pumpPage(WidgetTester tester, CompassSource source,
      {bool dark = false,
      Size size = const Size(390, 844),
      double textScale = 1}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: dark ? AppTheme.dark() : AppTheme.light(),
      home: MediaQuery(
        data: MediaQueryData(
            size: size,
            padding: const EdgeInsets.only(top: 44, bottom: 34),
            textScaler: TextScaler.linear(textScale)),
        child: CompassPage(source: source),
      ),
    ));
    await tester.pump();
  }

  testWidgets('锁定保留读数，解锁恢复实时方位，离开页面停止采样', (tester) async {
    final source = FakeCompassSource();
    addTearDown(source.controller.close);
    await pumpPage(tester, source);
    expect(find.text('—°'), findsOneWidget);
    source.controller.add(reading(90));
    await tester.pump();
    expect(find.text('90°'), findsOneWidget);
    await tester.tap(find.text('锁定'));
    source.controller.add(reading(180, timestamp: 2));
    await tester.pump();
    expect(find.text('90°'), findsOneWidget);
    expect(find.text('已锁定'), findsOneWidget);
    await tester.tap(find.text('已锁定'));
    await tester.pump();
    expect(find.text('180°'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(source.controller.hasListener, isFalse);
  });

  testWidgets('后台取消订阅，回前台重新连接', (tester) async {
    final source = FakeCompassSource();
    addTearDown(source.controller.close);
    await pumpPage(tester, source);
    expect(source.controller.hasListener, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(source.controller.hasListener, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(source.subscriptions, 2);
    expect(source.controller.hasListener, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('无硬件不显示假角度，传感器无响应提示重试', (tester) async {
    final source = FakeCompassSource();
    addTearDown(source.controller.close);
    await pumpPage(tester, source);
    await tester.pump(const Duration(seconds: 5));
    expect(find.textContaining('未收到传感器数据'), findsOneWidget);
    expect(find.text('—°'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('重新连接'), 150);
    await tester.tap(find.text('重新连接'));
    await tester.pump();
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pumpAndSettle();
    expect(source.subscriptions, 2);
    source.controller.addError(const CompassUnavailable('此设备没有可用的罗盘传感器'));
    await tester.pumpAndSettle();
    expect(find.text('此设备没有可用的罗盘传感器'), findsOneWidget);
    expect(find.text('0°'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('倾斜与磁场校准提示，失效读数清空', (tester) async {
    final source = FakeCompassSource();
    addTearDown(source.controller.close);
    await pumpPage(tester, source);
    source.controller.add(reading(null, tilt: 75));
    await tester.pump();
    expect(find.text('请将手机屏幕朝上，保持水平'), findsOneWidget);
    expect(find.text('—°'), findsOneWidget);
    source.controller.add(reading(30, accuracy: 0));
    await tester.pump();
    expect(find.textContaining('缓慢画「8」字校准'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  for (final dark in [false, true]) {
    testWidgets('${dark ? '深色' : '浅色'}罗盘完整布局', (tester) async {
      final source = FakeCompassSource();
      addTearDown(source.controller.close);
      await pumpPage(tester, source, dark: dark);
      source.controller.add(reading(45));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('窄屏大字体仍可滚动且无溢出', (tester) async {
    final source = FakeCompassSource();
    addTearDown(source.controller.close);
    await pumpPage(tester, source, size: const Size(320, 640), textScale: 1.6);
    source.controller.add(reading(359.8));
    await tester.pumpAndSettle();
    expect(find.text('0°'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
