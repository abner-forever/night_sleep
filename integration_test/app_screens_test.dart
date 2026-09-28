import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:night_sleep/core/widgets/subpage.dart';
import 'package:night_sleep/main.dart' as app;

/// Walks every screen and pauses on each one so a host-side `simctl` loop can
/// photograph it. See README "界面截图巡检" for the two-command recipe.
///
/// This is a *tour*, not an assertion suite. Its job is to reach states nothing
/// else in the suite can look at: the widget tests assert geometry and
/// structure, which catches a mis-sized control but not a clipped shadow, a fade
/// with a hard edge, or text rendered in Flutter's error style. Those need real
/// frames and a pair of eyes.
///
/// It pauses rather than calling `binding.takeScreenshot`: that channel proved
/// unreliable on this setup, while `simctl io screenshot` never missed.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// How long each screen is held. The sampler runs every ~1.3s, so this is
  /// several frames per screen.
  const hold = Duration(seconds: 5);

  Future<void> settle(WidgetTester tester) async {
    try {
      await tester.pumpAndSettle(const Duration(seconds: 2));
    } catch (_) {
      // Several screens animate forever — the home ring, the waveform
      // indicator — so settling is best-effort by design.
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  /// Runs one step, reporting rather than rethrowing.
  ///
  /// A tour finishes: one unreachable control costs its own screen, not every
  /// screen after it.
  Future<void> step(String name, Future<void> Function() body) async {
    try {
      await body();
    } catch (error) {
      // ignore: avoid_print
      print('TOUR skipped $name: $error');
    }
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    final finder = find.text(text);
    if (finder.evaluate().isEmpty) {
      // A `ListView` does not build what is below the fold, so an item that is
      // simply scrolled out of view looks identical to one that is absent.
      try {
        await tester.scrollUntilVisible(
          finder,
          240,
          scrollable: find.byType(Scrollable).first,
          maxScrolls: 12,
        );
      } catch (_) {
        throw StateError('找不到「$text」');
      }
    }
    await tester.tap(finder.first);
    await settle(tester);
  }

  /// Leaves whatever is on top. `pageBack()` is unusable here: sub-pages carry
  /// the design's own back pill rather than an AppBar.
  Future<void> goBack(WidgetTester tester) async {
    final pill = find.descendant(
      of: find.byType(Subpage),
      matching: find.byType(GestureDetector),
    );
    if (pill.evaluate().isNotEmpty) {
      await tester.tap(pill.first);
    } else {
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    }
    await settle(tester);
  }

  testWidgets('每屏停留，供宿主机采样', (tester) async {
    app.main();
    await settle(tester);

    await step('onboarding', () async {
      // The last page's button reads 开始使用, not 下一步. Stopping at the first
      // missing 下一步 leaves the overlay up, and then every subsequent step
      // reports "not found" while actually staring at the onboarding art.
      for (var i = 0; i < 8; i++) {
        final action = find.text('开始使用').evaluate().isNotEmpty
            ? find.text('开始使用')
            : find.text('下一步');
        if (action.evaluate().isEmpty) break;
        await tester.tap(action.first);
        await settle(tester);
      }
    });

    await step('home', () => Future<void>.delayed(hold));

    // Scrolled, so the top fade and the bar's band are both on screen.
    await step('home-scrolled', () async {
      await tester.drag(find.byType(ListView).first, const Offset(0, -300));
      await settle(tester);
      await Future<void>.delayed(hold);
    });

    await step('log', () async {
      await tapText(tester, '记录');
      await Future<void>.delayed(hold);
    });

    await step('stats', () async {
      await tapText(tester, '统计');
      await Future<void>.delayed(hold);
      await tapText(tester, '30天');
      await Future<void>.delayed(hold);
    });

    await step('settings', () async {
      await tapText(tester, '设置');
      await Future<void>.delayed(hold);
    });

    await step('settings-import', () async {
      await tapText(tester, '小米手环睡眠数据');
      await Future<void>.delayed(hold);
      await goBack(tester);
    });

    await step('settings-insight', () async {
      await tapText(tester, '洞察服务配置');
      await Future<void>.delayed(hold);
      await goBack(tester);
    });

    await step('settings-demo', () async {
      await tapText(tester, '演示数据');
      await Future<void>.delayed(hold);
      await goBack(tester);
    });

    await step('detail-sheet', () async {
      await tapText(tester, '首页');
      await tapText(tester, '详情');
      await Future<void>.delayed(hold);
      // Expanded, so the waveform and transcript are on screen too.
      await tapText(tester, '打鼾');
      await Future<void>.delayed(hold);
      await goBack(tester);
    });

    await step('noise-sheet', () async {
      await tapText(tester, '白噪音');
      await Future<void>.delayed(hold);
    });
  });
}
