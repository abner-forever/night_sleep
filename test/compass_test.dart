import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  // 下面那组 CompassSource 用例要在真实的 binaryMessenger 上装 mock handler。
  TestWidgetsFlutterBinding.ensureInitialized();

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
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  // ------------------------------------------------------------------
  // CompassSource：平台分支、wire 契约、错误 code
  //
  // **这一组只钉得住「键名、类型、null 与否、错误 code」。** 钉不住任何数值：
  // `up` 的符号、`rotationRate` 的符号、屏幕旋转的 forward 分支、accuracy 的换算，
  // 全在 Kotlin 那一侧，而本仓库没有 Kotlin 测试设施。**绿了不等于真机上是对的。**
  // ------------------------------------------------------------------

  const channel = EventChannel('night_sleep/compass');

  void usePlatform(TargetPlatform platform) {
    debugDefaultTargetPlatformOverride = platform;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
  }

  /// 装一个 mock 的 EventChannel handler。
  ///
  /// **必须有，不是可选的**：没有它时 `receiveBroadcastStream` 内部的
  /// `invokeMethod('listen')` 会抛 `MissingPluginException`，而 `EventChannel`
  /// 把它交给 `FlutterError.reportError`——那是一条**未处理的异步错误**，
  /// 会直接判用例失败，报错还长得跟被测代码无关。
  void mockChannel(void Function(MockStreamHandlerEventSink sink) drive) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
      channel,
      MockStreamHandler.inline(onListen: (arguments, sink) => drive(sink)),
    );
  }

  test('Android 走 EventChannel，事件按契约解码（无效方位不发哨兵）', () async {
    usePlatform(TargetPlatform.android);
    mockChannel((sink) => sink.success(const <Object?, Object?>{
          'timestamp': 1.5,
          'rotationRate': 0.25,
          'tilt': 0.0,
          'fieldStrength': 45.0,
          'accuracy': 2,
        }));

    final reading = await const CompassSource().readings().first;

    expect(reading.heading, isNull, reason: 'heading 缺席必须是 null，不能是 -1 或 0');
    expect(reading.timestamp, 1.5);
    expect(reading.rotationRate, 0.25);
    expect(reading.tilt, 0.0);
    expect(reading.fieldStrength, 45.0);
    expect(reading.accuracy, 2);
    expect(reading.needsCalibration, isFalse);
  });

  test('未实现的平台说「平台未支持」，不谎称设备不行', () async {
    usePlatform(TargetPlatform.macOS);

    final error = await const CompassSource()
        .readings()
        .first
        .then<Object?>((_) => null, onError: (Object error) => error);

    expect(error, isA<CompassUnavailable>());
    final message = (error! as CompassUnavailable).message;
    expect(message, contains('平台'));
    expect(message, isNot(contains('传感器')), reason: '「平台没实现」与「设备没传感器」是两回事，不能混');
    expect(message, isNot(contains('iPhone')));
  });

  test('iOS 仍走 EventChannel（防止改判定时把 iOS 弄坏）', () async {
    usePlatform(TargetPlatform.iOS);
    mockChannel((sink) => sink.success(const <Object?, Object?>{
          'timestamp': 2.0,
          'rotationRate': 0.0,
          'tilt': 12.0,
          'fieldStrength': 48.0,
          'accuracy': 2,
          'heading': 137.5,
        }));

    final reading = await const CompassSource().readings().first;

    expect(reading.heading, 137.5);
  });

  testWidgets(
    '原生 code=unavailable 落到「此设备没有可用的罗盘传感器」',
    (tester) async {
      // 这一条钉的是 **Kotlin 侧必须发的那个 code 字符串**——
      // 页面按 `error.code == 'unavailable'` 才认出「设备没有传感器」。
      mockChannel((sink) => sink.error(
            code: 'unavailable',
            message: '此设备没有可用的罗盘传感器',
          ));

      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.dark(), home: const CompassPage()),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('此设备没有可用的罗盘传感器'), findsOneWidget);
      expect(find.text('0°'), findsNothing, reason: '不可用时不得显示假角度');

      await tester.pumpWidget(const SizedBox());
    },
    // 用 variant，不要用 `debugDefaultTargetPlatformOverride`：`testWidgets`
    // 在测试体跑完后会断言 foundation 调试变量已复位，而 `addTearDown`
    // 排在那个断言**之后**——手动设了必报「debug variable was changed by the test」，
    // 且这条报错会盖住真正的失败原因。
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
