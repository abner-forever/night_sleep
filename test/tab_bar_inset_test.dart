import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/app/app_shell.dart';
import 'package:night_sleep/core/theme/app_theme.dart';

/// 标签条的浮起量与页面底部留白是一对：浮起量决定玻璃胶囊下边缘离屏幕底边
/// 多远，页面底部留白要能盖住胶囊的整条高度。两者共用 `tabBarFloat`
/// （`app_shell.dart`），任一侧单独改动都会立刻表现为「最后一行压进玻璃」
/// 或「玻璃上方空出一条」。
///
/// 这里断言的是**渲染出来的几何**，不是那两个函数的返回值：`SafeArea`
/// / `Scaffold` 会不会把底部安全区摘掉、`Stack` 会不会静缩，都只有真渲染
/// 一次才看得出来。
///
/// **两个平台的安全区不能互推**：iOS 的 home indicator 只占安全区底下那一小段，
/// 胶囊借得起 14pt；Android 的手势条贴在安全区下沿，借了就直接压上去。所以每条
/// 用例都用 `TargetPlatformVariant` 写明跑在哪个平台上——`flutter_test` 会把
/// `defaultTargetPlatform` **恒钉成 android**（`_platform_io.dart` 里那个
/// `FLUTTER_TEST` 环境变量判断），不显式覆盖的话 iOS 那一支永远不会被任何测试碰到。
void main() {
  const screen = Size(402, 874);

  /// 与 `AppScaffold` 同构：`Scaffold` → `SafeArea(top: false, bottom: false)`
  /// → `AppShell`。`SafeArea` 的 `bottom: false` 不会摘掉底部安全区，
  /// 外壳因此仍读得到它 —— 这正是真机上标签条拿到安全区的路径。
  Widget harness(double safeBottom) => MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(size: screen)
              .copyWith(padding: EdgeInsets.only(bottom: safeBottom)),
          child: Scaffold(
            body: SafeArea(
              top: false,
              bottom: false,
              child: AppShell(
                current: AppTab.home,
                onSelect: (_) {},
                child: Builder(
                  builder: (context) => ListView(
                    padding: EdgeInsets.only(bottom: pageBottomInset(context)),
                    children: const [SizedBox(height: 2000)],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  Future<void> pump(WidgetTester tester, double safeBottom) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness(safeBottom));
    await tester.pumpAndSettle();
  }

  /// 玻璃胶囊的矩形。取标签文字最近的 `ClipRRect` 祖先：胶囊自身就在
  /// `ClipRRect` 里，而它与文字之间不再夹别的 `ClipRRect`。
  Rect pill(WidgetTester tester) => tester.getRect(
        find
            .ancestor(of: find.text('首页'), matching: find.byType(ClipRRect))
            .first,
      );

  double gap(WidgetTester tester) =>
      tester.getRect(find.byType(AppShell)).bottom - pill(tester).bottom;

  double reserve(WidgetTester tester) => tester
      .widget<ListView>(find.byType(ListView))
      .padding!
      .resolve(TextDirection.ltr)
      .bottom;

  testWidgets(
    'iOS：带 home indicator 的设备，胶囊底边离屏幕底 20pt',
    (tester) async {
      await pump(tester, 34);

      expect(gap(tester), 20);
      // home indicator 画在底部 8–13px，胶囊必须整条避开它。
      expect(gap(tester), greaterThanOrEqualTo(16));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'iOS：小安全区也不会把浮起量削到下限以下',
    (tester) async {
      await pump(tester, 20);

      // 20 − 14 = 6，抬回下限。
      expect(gap(tester), 12);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'Android：手势条就画在安全区里，胶囊整个让开、一点都不借',
    (tester) async {
      // 真机 MI 9 / Android 11 实测：安全区 44px（16dp），手势条画在离底 20–30px
      // （约 7–11dp）那一段——安全区里几乎没有空着的地方可借。
      await pump(tester, 16);

      // 借了 iOS 那 14pt 的话这里只有 2pt，胶囊底边会落到手势条里面去。
      expect(gap(tester), 16);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    '无安全区：各平台都保留下限 12pt',
    (tester) async {
      await pump(tester, 0);

      expect(gap(tester), 12);
    },
    variant: TargetPlatformVariant.all(),
  );

  testWidgets('页面底部留白始终盖住整条胶囊', (tester) async {
    // **这一条与平台无关，所以刻意不给它 `variant`。** `reserve` 与 `gap` 同源于
    // `tabBarFloat(context)`，回收量在两边各出现一次、正好约掉，等式实际只剩
    // 「渲染出来的胶囊高度 == `_tabBarHeight`」。它抓得住的是 `_TabBar` 的
    // `Positioned(bottom:)` 与页面留白脱节、以及胶囊被谁悄悄撑高或压矮；
    // **抓不住回收量写错平台**——那一类由上面三条平台用例负责。
    for (final safeBottom in [0.0, 20.0, 34.0]) {
      await pump(tester, safeBottom);

      final pillRect = pill(tester);
      expect(
        reserve(tester),
        closeTo(gap(tester) + pillRect.height + 16, 0.01),
        reason: '底部留白与浮起量脱节（safeBottom=$safeBottom）——'
            '留白算小了最后一行压进玻璃，算大了玻璃上方空出一条',
      );
    }
  });
}
