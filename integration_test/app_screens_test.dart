import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:night_sleep/core/widgets/subpage.dart';
import 'package:night_sleep/features/session/presentation/widgets/hold_to_finish_button.dart';
import 'package:night_sleep/features/sleep/presentation/sheets/sound_card.dart';
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
///
/// **会话页（v3.2 起）不能用 `pumpAndSettle`。** 那一页挂着一个 60 秒循环的夜景
/// 动画控制器，`pumpAndSettle` 永远等不到「没有动画」的那一刻，会直接 `timed out`。
/// 走到会话页之后一律走 [settle] 里的显式推帧分支——判据是页面上有没有
/// `HoldToFinishButton`（进行中）或「准备好休息了吗？」（v3.3 起的入睡前态，
/// 它挂着同一套夜景；`pumpAndSettle` 在那里同样收敛不了）——步进时长与原本的等待相当。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// How long each screen is held. The sampler runs every ~1.3s, so this is
  /// several frames per screen.
  const hold = Duration(seconds: 5);

  Future<void> settle(WidgetTester tester) async {
    // 先推一帧：刚触发的导航（比如点「开始入睡」）要在这一帧之后才把目标页建出来，
    // 会话页的判据才有意义。
    await tester.pump();
    // 会话页两态（v3.2 的进行中、v3.3 的入睡前）的背景都是一个 60 秒循环的夜景动画，
    // `pumpAndSettle` 在这里**永远收敛不了**，会 `timed out`。用显式推帧代替，
    // 步进时长与原本的等待相当。
    final onSessionNight =
        find.byType(HoldToFinishButton).evaluate().isNotEmpty ||
            find.text('准备好休息了吗？').evaluate().isNotEmpty;
    if (onSessionNight) {
      await tester.pump(const Duration(milliseconds: 900));
      return;
    }
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
  /// 「睡眠洞察」实测落在 y=821.8、屏高 874，正好被那条胶囊压住。
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

  /// 长按「结束睡眠」并显式推帧。
  ///
  /// 不能只 `await Future.delayed`：这一轮实测下来，集成测试的 live binding 里
  /// 动画只在**推帧**时前进，光等时钟过去，结束按钮的填充条会停在原地。
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

    // ── 会话页：入睡前态 ───────────────────────────────────────────────────
    // **趁状态干净时走**：会话要「先开一个」才到得了，而开完会把首页从「开始入睡」
    // 换成「正在睡眠」。放在首页步骤之后、其余步骤之前，末尾按住到底把会话结束，
    // 首页也就还原了——顺带把「按住 → 评星」这条链路也拍进巡检。
    //
    // v3.3 起进页面还**没有**开始记录：首页那颗按钮只进页面，页内那颗「开始睡眠」
    // 才写会话行。所以这一步拍入睡前态，下一步（会话页）才拍进行中态。
    await step(tester, 'session-setup', () async {
      // 先把浮层收干净：前一步若留着没关的弹层，后面每一次点按都只打在遮罩上，
      // 看着点到了其实没有。
      tester
          .state<NavigatorState>(find.byType(Navigator).first)
          .popUntil((route) => route.isFirst);
      await settle(tester);
      await goHome(tester);

      // 上一轮巡检可能留下一个没结束的会话，那首页就没有「开始入睡」。
      if (find.text('开始入睡').evaluate().isNotEmpty) {
        await tapText(tester, '开始入睡');
      } else {
        await tapContaining(tester, '正在睡眠');
      }
      await settle(tester);

      if (find.text('准备好休息了吗？').evaluate().isEmpty) {
        // ignore: avoid_print
        print('TOUR 没进到入睡前那一屏');
      }
      await Future<void>.delayed(hold);
    });

    // 打开白噪音底部弹窗：**入口在这一屏**（进行中那一屏照原型只回显，不给入口）。
    // 拍完必须收掉——它是模态弹窗，会盖住下面的内容。
    await step(tester, 'session-noise', () async {
      await tapText(tester, '完整设置');
      await Future<void>.delayed(hold);
      if (find.text('完成').evaluate().isNotEmpty) {
        await tester.tap(find.text('完成'));
        await settle(tester);
      }
    });

    // **真的选中一个音，并把弹窗再打开一次。**
    //
    // 这一步是 2026-10-03 在 macOS 上撞见 `PathNotFoundException` 之后补的：整条巡检
    // 里只有这里会走到 `NoisePlayer` 的真实合成与落盘，而在此之前脚本只开弹窗、从不选
    // 声音——等于那条路径一次也没被走过，报错自然也就没被拦住。选中会真的出声，所以
    // 紧接着点「关闭」那格停掉；`_ensureFile` 的落盘断言另有一条不需要界面的
    // `integration_test/noise_playback_test.dart` 钉着，这里管的是「界面上点了有没有事」。
    await step(tester, 'session-noise-play', () async {
      await tapText(tester, '完整设置');
      await Future<void>.delayed(hold);
      // **弹窗里那几格要用宫格限定住。** 弹窗是叠在入睡前那一屏上的，底下那棵树
      // 还在——「雨声 / 海浪 / 棕噪音 / 风扇」四个标签在常用白噪音四格里也各有一份，
      // 直接 `find.text('风扇')` 会命中两个，`ensureVisible` 当场抛
      // `Bad state: Too many elements`（2026-10-03 实测，还把后面三步一起带塌）。
      // 整个 `lib/` 里只有这个弹窗用 `GridView`，拿它做范围最准。
      Finder tile(String label) => find.descendant(
            of: find.byType(GridView),
            matching: find.text(label),
          );

      // 面板是 `SingleChildScrollView`，小屏上宫格可能有一半在折线以下；
      // `tapText` 只在「找不到」时才滚，所以这里显式滚到可见再点。
      await tester.ensureVisible(tile('风扇'));
      await settle(tester);
      await tester.tap(tile('风扇'));
      await settle(tester);
      // 合成要几十毫秒，起播还要过一层平台通道。
      await Future<void>.delayed(hold);

      // 失败文案是红色的那一行（`noise.failure`）。它出现就意味着声音没出来，
      // 而界面还停在「已选中」——正是最不能放过的那种状态。这条文案只在弹窗里，
      // 底下那一屏没有「无法」二字（实测 grep 过）。
      final failure = find.textContaining('无法');
      if (failure.evaluate().isNotEmpty) {
        // ignore: avoid_print
        print('TOUR 白噪音报错：${tester.widget<Text>(failure.first).data}');
      }

      await tester.ensureVisible(tile('关闭'));
      await tester.tap(tile('关闭'));
      await settle(tester);
      await tapText(tester, '完成');
    });

    // 按下「开始睡眠」→ 页面自己翻到进行中态（记录从这一刻起算）。
    await step(tester, 'session', () async {
      await tapText(tester, '开始睡眠');
      await settle(tester);

      if (find.byType(HoldToFinishButton).evaluate().isEmpty) {
        // ignore: avoid_print
        print('TOUR 没进到会话页');
      }
      await Future<void>.delayed(hold);
    });

    // 长按结束睡眠，填充条扫到一半左右就松手（1.5 秒才满）。
    await step(tester, 'session-hold', () async {
      await holdFinishButton(tester, 12);
      await Future<void>.delayed(hold);
    });

    // 长按到底 → 评星弹层；跳过收尾，把首页还原成「开始入睡」。
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

    // v3.5 起外观与睡眠设置各是一个二级页，根页只剩导航行。
    await step(tester, 'settings-appearance', () async {
      await tapText(tester, '外观');
      await Future<void>.delayed(hold);
      await goBack(tester);
    });

    await step(tester, 'settings-sleep', () async {
      await tapText(tester, '睡眠设置');
      await Future<void>.delayed(hold);
      await goBack(tester);
    });

    await step(tester, 'settings-import', () async {
      await tapText(tester, '睡眠数据导入');
      await Future<void>.delayed(hold);
      await goBack(tester);
    });

    await step(tester, 'settings-insight', () async {
      await tapText(tester, '睡眠洞察');
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
      //
      // **按控件点，不按文字点。** 展开之后「打鼾」会同时出现在两个地方：卡片标题
      // 与标注选项里的那一项。`find.text('打鼾')` 因此会命中两个 widget，
      // `tester.tap` 直接抛「Found 2 widgets」。这里要的是展开那张卡，所以认
      // `SoundCard` 本身。
      final card = find.byType(SoundCard).first;
      if (card.evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          card,
          240,
          scrollable: find.byType(Scrollable).first,
          maxScrolls: 12,
        );
      }
      await tester.tap(card);
      await Future<void>.delayed(hold);
      await goBack(tester);
    });

    await step(tester, 'noise-sheet', () async {
      await tapText(tester, '白噪音');
      await Future<void>.delayed(hold);
    });
  });
}
