import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/features/session/presentation/night_scene.dart';
import 'package:night_sleep/features/session/presentation/widgets/night_backdrop.dart';

/// 把背景当前这一帧真的光栅化出来。
///
/// 这是这一份测试唯一能钉住「动画到底动没动」的办法：pixel 比较不会因为
/// `CustomPaint` 的画笔是私有的就变成一句空断言。
///
/// 取的是 `NightBackdrop` **自己**那层 `RepaintBoundary`（它在 `build` 里的根就是），
/// 而不是 `find.byType(RepaintBoundary).first`——后者会落到路由
/// `_ModalScope` 那个祖先边界上，框进来的是整屏，不是被测组件。
Future<Uint8List> snapshot(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find
        .descendant(
          of: find.byType(NightBackdrop),
          matching: find.byType(RepaintBoundary),
        )
        .first,
  );
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  });
  return bytes!;
}

void main() {
  Future<void> pumpBackdrop(
    WidgetTester tester, {
    required NightScene scene,
    bool reduceMotion = true,
  }) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: reduceMotion);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: NightBackdrop(scene: scene))),
    );
    // 这里**不能**用 pumpAndSettle：开了动画时它会 `timed out`。
    await tester.pump();
  }

  testWidgets('八种场景都能渲染，不抛异常', (tester) async {
    for (final scene in NightScene.values) {
      await pumpBackdrop(tester, scene: scene);
      expect(tester.takeException(), isNull, reason: '${scene.id} 画崩了');
      expect(find.byType(NightBackdrop), findsOneWidget);
    }
  });

  testWidgets('减弱动态效果时停表：隔两秒的画面一模一样', (tester) async {
    // 用雨夜：它的周期最短（2.8 秒），两秒内一定有肉眼可见的位移。
    // 用流星夜的话这条会变成空断言——流星那三条在前两秒还没进入可见窗口
    // （`p < .82` 直接跳过），画面本来就一模一样，停没停表都测不出来。
    await pumpBackdrop(tester, scene: NightScene.rain);
    final before = await snapshot(tester);

    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }

    expect(await snapshot(tester), before, reason: '开了「减弱动态效果」还在动 = 无障碍要求没落实');

    // 画面没变还不够：表本身也得停。`repeat()` 会让每一帧都再排一帧，
    // 时钟还在转就该有排队的帧；两秒推完仍没有，才算真的停表。
    expect(tester.binding.hasScheduledFrame, isFalse,
        reason: '视觉上静止但时钟还在转 = 白烧电池，不是「停表」');
  });

  testWidgets('没开减弱动态效果时相位真的在走：画面会变', (tester) async {
    await pumpBackdrop(tester, scene: NightScene.rain, reduceMotion: false);
    final before = await snapshot(tester);

    // 显式推帧而不是 pumpAndSettle——60 秒的循环表永远不会「settle」。
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }

    expect(await snapshot(tester), isNot(before),
        reason: '动画根本没跑起来（变异验证：把重复控制器摘掉，这条必须变红）');
  });

  testWidgets('换场景后重绘不抛异常', (tester) async {
    await pumpBackdrop(tester, scene: NightScene.meteor);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: NightBackdrop(scene: NightScene.galaxy)),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
