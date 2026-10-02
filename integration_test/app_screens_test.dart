import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:night_sleep/core/widgets/subpage.dart';
import 'package:night_sleep/features/session/presentation/widgets/hold_to_finish_button.dart';
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

  /// 直接回首页，不走返回栈。
  ///
  /// 一步失败之后必须能用它复位：`goBack` 在栈里只剩一页时会 `pop()` 掉最后一页，
  /// go_router 随即断言 `currentConfiguration.isNotEmpty`，整棵树跟着坏掉，**后面
  /// 每一步都报「找不到」**——2026-10-02 实测踩到，`settings-insight` 点空之后
  /// 全后段连带失守，包括新加的会话页几步。
  Future<void> goHome(WidgetTester tester) async {
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    (app.routerConfig! as GoRouter).go('/');
    await settle(tester);
  }

  /// Runs one step, reporting rather than rethrowing.
  ///
  /// A tour finishes: one unreachable control costs its own screen, not every
  /// screen after it.
  Future<void> step(
    WidgetTester tester,
    String name,
    Future<void> Function() body,
  ) async {
    try {
      await body();
    } catch (error) {
      // ignore: avoid_print
      print('TOUR skipped $name: $error');
      // 复位，否则这一步的烂摊子会吃掉后面每一步。
      try {
        await goHome(tester);
      } catch (_) {
        // 复位本身再失败也不该让整趟巡检停下来。
      }
    }
  }

  /// 点一个文字；找不到就先滚。
  ///
  /// **已知不足**：只在「找不到」时才滚，挡不住「找到了但点不到」——`ListView` 的
  /// cacheExtent 会建出屏幕外一点的内容，而悬浮标签条**盖在内容之上**，
  /// 「洞察服务配置」实测落在 y=821.8、屏高 874，正好被那条胶囊压住。
  /// 试过补 `ensureVisible` + 额外 `drag`，结果整趟巡检卡死（2026-10-02），已回退；
  /// 那一步的代价由 [step] 的复位兜住，不连坐。
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

  /// 同 [tapText]，但按子串找——会话页那条摘要读作「白噪音 · 音量 50%」，
  /// 音量是变的，整串匹配不上。
  Future<void> tapContaining(WidgetTester tester, String text) async {
    final finder = find.textContaining(text);
    if (finder.evaluate().isEmpty) {
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

  /// 按住「结束睡眠」并显式推帧。
  ///
  /// 不能只 `await Future.delayed`：这一轮实测下来，集成测试的 live binding 里
  /// 动画只在**推帧**时前进，光等时钟过去，进度环会停在原地。
  Future<void> holdFinishButton(WidgetTester tester, int frames) async {
    final button = find.byType(HoldToFinishButton);
    await tester.ensureVisible(button);
    await settle(tester);
    final gesture = await tester.startGesture(tester.getCenter(button));
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await gesture.up();
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
      await settle(tester);
      return;
    }
    // 弹层（睡眠详情那种 modal，不是 Subpage）用 `popUntil` 收掉——`goHome` 只换
    // 路由，收不掉它，于是后面每一次点按都打在遮罩上。**也别用裸 `pop()`**：栈里
    // 只剩一页时它会把最后一页也弹掉，go_router 随即断言并弄坏整棵树。
    tester
        .state<NavigatorState>(find.byType(Navigator).first)
        .popUntil((route) => route.isFirst);
    await settle(tester);
    await goHome(tester);
  }

  testWidgets('每屏停留，供宿主机采样', (tester) async {
    app.main();
    await settle(tester);

    await step(tester, 'onboarding', () async {
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

    await step(tester, 'home', () => Future<void>.delayed(hold));

    // Scrolled, so the top fade and the bar's band are both on screen.
    await step(tester, 'home-scrolled', () async {
      await tester.drag(find.byType(ListView).first, const Offset(0, -300));
      await settle(tester);
      await Future<void>.delayed(hold);
    });

    // ── 会话页 ────────────────────────────────────────────────────────────
    // **趁状态干净时走**：会话要「先开一个」才到得了，而开完会把首页从「开始睡眠」
    // 换成「正在睡眠」。放在首页步骤之后、其余步骤之前，末尾按住到底把会话结束，
    // 首页也就还原了——顺带把「按住 → 评星」这条链路也拍进巡检。
    await step(tester, 'session', () async {
      // 先把浮层收干净：前一步若留着没关的弹层，后面每一次点按都只打在遮罩上，
      // 看着点到了其实没有。
      tester
          .state<NavigatorState>(find.byType(Navigator).first)
          .popUntil((route) => route.isFirst);
      await settle(tester);
      await goHome(tester);

      // 上一轮巡检可能留下一个没结束的会话，那首页就没有「开始睡眠」。
      if (find.text('开始睡眠').evaluate().isNotEmpty) {
        await tapText(tester, '开始睡眠');
      } else {
        await tapContaining(tester, '正在睡眠');
      }
      await settle(tester);

      if (find.byType(HoldToFinishButton).evaluate().isEmpty) {
        // ignore: avoid_print
        print('TOUR 没进到会话页');
      }
      await Future<void>.delayed(hold);
    });

    // 按住不放、环扫到一半左右就松手（1.5 秒才满），拍进度环。
    await step(tester, 'session-hold', () async {
      await holdFinishButton(tester, 12);
      await Future<void>.delayed(hold);
    });

    // 展开白噪音区：看高度动画之后的版式，以及自动滚进视野的效果。
    await step(tester, 'session-noise', () async {
      await tapContaining(tester, '白噪音 · 音量');
      await Future<void>.delayed(hold);
    });

    // 按住到底 → 评星弹层；跳过收尾，把首页还原成「开始睡眠」。
    await step(tester, 'session-finish', () async {
      await holdFinishButton(tester, 25);
      await Future<void>.delayed(hold);
      if (find.text('跳过').evaluate().isNotEmpty) {
        await tester.tap(find.text('跳过'));
        await settle(tester);
      }
    });

    await step(tester, 'review', () async {
      await tapText(tester, '回顾');
      await Future<void>.delayed(hold);
    });

    await step(tester, 'stats', () async {
      await tapText(tester, '统计');
      await Future<void>.delayed(hold);
      await tapText(tester, '30天');
      await Future<void>.delayed(hold);
    });

    await step(tester, 'settings', () async {
      await tapText(tester, '设置');
      await Future<void>.delayed(hold);
    });

    await step(tester, 'settings-import', () async {
      await tapText(tester, '小米手环睡眠数据');
      await Future<void>.delayed(hold);
      await goBack(tester);
    });

    await step(tester, 'settings-insight', () async {
      await tapText(tester, '洞察服务配置');
      await Future<void>.delayed(hold);
      await goBack(tester);
    });

    await step(tester, 'settings-demo', () async {
      await tapText(tester, '演示数据');
      await Future<void>.delayed(hold);
      await goBack(tester);
    });

    await step(tester, 'detail-sheet', () async {
      await tapText(tester, '首页');
      await tapText(tester, '详情');
      await Future<void>.delayed(hold);
      // Expanded, so the waveform and transcript are on screen too.
      await tapText(tester, '打鼾');
      await Future<void>.delayed(hold);
      await goBack(tester);
    });

    await step(tester, 'noise-sheet', () async {
      await tapText(tester, '白噪音');
      await Future<void>.delayed(hold);
    });
  });
}
