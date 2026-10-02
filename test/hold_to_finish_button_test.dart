import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/core/theme/app_theme.dart';
import 'package:night_sleep/features/session/presentation/widgets/hold_to_finish_button.dart';

void main() {
  Future<void> pumpButton(
    WidgetTester tester, {
    required VoidCallback onFinish,
    VoidCallback? onHint,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Center(
            child: HoldToFinishButton(onFinish: onFinish, onHint: onHint),
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
}
