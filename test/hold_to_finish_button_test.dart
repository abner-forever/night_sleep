import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/core/theme/app_theme.dart';
import 'package:night_sleep/features/session/presentation/widgets/hold_to_finish_button.dart';

void main() {
  Future<void> pumpButton(
    WidgetTester tester, {
    required VoidCallback onFinish,
    VoidCallback? onHint,
    bool disableAnimations = false,
  }) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // 默认**不开** `disableAnimations`：`AnimationController` 在减弱动态效果下会把时长
    // 压到 5%，1.5 秒的按住会缩成 75ms，「没按满就松手」与「滑开作废」两条用例会假红。
    // 只有专门验这条缺陷的用例才把它打开（见「减弱动态效果…」那条）。
    if (disableAnimations) {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: HoldToFinishButton(onFinish: onFinish, onHint: onHint),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 按下并按住 [held]。
  ///
  /// **第一帧不能省**：`AnimationController` 的起点是在 ticker 的第一次 tick 上记的，
  /// 不先跑一帧，接着的 `pump(时长)` 只会让动画停在 0——「按满」用例会假红，
  /// 而「没按满」用例会假绿。
  Future<TestGesture> pressAndHold(
    WidgetTester tester,
    Duration held,
  ) async {
    final gesture = await tester.press(find.byType(HoldToFinishButton));
    await tester.pump();
    await tester.pump(held);
    return gesture;
  }

  testWidgets('按住满 1.5 秒触发结束', (tester) async {
    var finished = 0;
    await pumpButton(tester, onFinish: () => finished++);

    final gesture =
        await pressAndHold(tester, const Duration(milliseconds: 1600));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(finished, 1);
  });

  testWidgets('没按满就松手不结束，之后再按满仍然有效', (tester) async {
    var finished = 0;
    await pumpButton(tester, onFinish: () => finished++);

    final short = await pressAndHold(tester, const Duration(milliseconds: 600));
    await short.up();
    await tester.pumpAndSettle();

    expect(finished, 0, reason: '松开时环没满，不该结束会话');

    // 取消一次之后按钮不能卡住——再按满照样要生效。
    final full = await pressAndHold(tester, const Duration(milliseconds: 1600));
    await full.up();
    await tester.pumpAndSettle();

    expect(finished, 1, reason: '半途取消不该把按钮弄坏');
  });

  testWidgets('短按只给提示，不结束', (tester) async {
    var finished = 0;
    var hints = 0;
    await pumpButton(
      tester,
      onFinish: () => finished++,
      onHint: () => hints++,
    );

    await tester.tap(find.byType(HoldToFinishButton));
    await tester.pumpAndSettle();

    expect(finished, 0);
    expect(hints, 1, reason: '短按要告诉用户「按住不放」才有效');
  });

  testWidgets('按满触发后指针被取消，再短按仍给提示', (tester) async {
    var finished = 0;
    var hints = 0;
    await pumpButton(
      tester,
      onFinish: () => finished++,
      onHint: () => hints++,
    );

    // 先按满：触发一次结束，内部把 `_fired` 置真（还在按着，等抬手收尾）。
    final full = await pressAndHold(tester, const Duration(milliseconds: 1600));
    expect(finished, 1);
    await tester.pumpAndSettle();

    // 指针不是正常抬起，而是被系统取消（来电、手势被别的识别器夺走）。
    await full.cancel();
    await tester.pumpAndSettle();

    // 取消路径必须已经把 `_fired` 复位：紧接着的短按仍要给出「按住不放」的提示，
    // 否则这次短按会被当成上一轮触发的收尾而静默吞掉。
    await tester.tap(find.byType(HoldToFinishButton));
    await tester.pumpAndSettle();

    expect(hints, 1, reason: '取消后不复位 `_fired`，下一次短按会被吞掉、不给提示');
  });

  testWidgets('按住后滑开再松手不结束', (tester) async {
    var finished = 0;
    await pumpButton(tester, onFinish: () => finished++);

    final gesture = await tester.press(find.byType(HoldToFinishButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.moveBy(const Offset(0, -80));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1600));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(finished, 0, reason: '手指滑开了就该作废，躺着翻身蹭到也能反悔');
  });

  testWidgets('按钮是全宽的横向胶囊，不是圆形', (tester) async {
    await pumpButton(tester, onFinish: () {});

    final size = tester.getSize(find.byType(HoldToFinishButton));
    expect(size.width, greaterThan(size.height * 3),
        reason: '原型那个按钮是全宽胶囊；退回圆形会在这里变红');
    expect(size.width, 390, reason: '要撑满父宽：430 画布 − 左右各 20 内边距');
    expect(size.height, greaterThanOrEqualTo(56),
        reason: '胶囊是 minHeight，内容高度可以更高，但不该低于 NightStyle.holdButtonMinHeight');
  });

  testWidgets('开启减弱动态效果时，1.5 秒守卫仍按真实时长计时', (tester) async {
    var finished = 0;
    await pumpButton(
      tester,
      onFinish: () => finished++,
      disableAnimations: true,
    );

    final gesture =
        await pressAndHold(tester, const Duration(milliseconds: 600));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(finished, 0,
        reason: '这 1.5 秒是误触守卫、不是装饰动效；Reduce Motion 把时长缩成 75ms 等于没闸门');
  });
}
