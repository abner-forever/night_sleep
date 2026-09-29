import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/core/theme/app_theme.dart';
import 'package:night_sleep/core/theme/app_tokens.dart';
import 'package:night_sleep/core/widgets/confirm_dialog.dart';

/// 自绘确认弹窗的护栏。
///
/// 这个组件取代了原先两处 `showDialog` + `AlertDialog`（整个应用是 iOS 玻璃与令牌
/// 体系，唯独确认弹窗走 Material 默认外观）。改成自绘之后，有四件事只能靠测试守住：
///
///  * **必须自带 `Material` 祖先。**`showGeneralDialog` 不像 `showDialog` 那样自动包
///    一层，缺了它这里所有 `Text` 会落到 Flutter 的错误样式——黄色双下划线。
///    `AppSheet` 与 `Subpage` 都栽过一次，所以照同样的方式设防。
///  * **取消与点蒙层关闭返回 `false`，而不是 `null`。**三处调用方都写
///    `if (confirmed != true) return;`：返回 `null` 时它们侥幸仍然安全，但只要有人把
///    调用方简化成 `if (!confirmed)`，取消就会变成「照删不误」。返回值语义在这里钉死。
///  * **按钮左右次序**：取消在左、确认在右，与原先两处弹窗一致，避免肌肉记忆错位。
///  * **颜色与圆角取自令牌**：破坏性操作用 `danger`，其余用 `accent`。
void main() {
  const message = '这一晚的睡眠记录、睡眠阶段与声音事件都会被永久删除，此操作无法撤销。';

  /// 弹窗的宿主页面：一个普通页面上的按钮，点它打开确认弹窗。
  ///
  /// 宿主用了 `Scaffold`，但那层 `Material` 帮不到弹窗——弹窗是挂在 Navigator 的
  /// Overlay 上的另**一条**路由，不是页面的子树。所以下面那些「文字要在 Material 上」
  /// 的断言，验的只能是弹窗自己补的那层。
  Future<void> pumpHost(
    WidgetTester tester, {
    required ValueChanged<bool> onResult,
    bool destructive = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  final confirmed = await showConfirmDialog(
                    context,
                    title: '删除这条记录？',
                    message: message,
                    confirmLabel: '删除',
                    destructive: destructive,
                  );
                  onResult(confirmed);
                },
                child: const Text('触发'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openDialog(
    WidgetTester tester, {
    required ValueChanged<bool> onResult,
    bool destructive = true,
  }) async {
    await pumpHost(tester, onResult: onResult, destructive: destructive);
    await tester.tap(find.text('触发'));
    await tester.pumpAndSettle();
  }

  /// 弹窗里的文字必须落在 `Material` 上，且不带错误样式。
  void expectProperlyRendered(WidgetTester tester, String text) {
    final finder = find.text(text);
    expect(finder, findsOneWidget, reason: '找不到「$text」');
    expect(
      DefaultTextStyle.of(tester.element(finder)).style.decoration,
      isNot(TextDecoration.underline),
      reason: '「$text」带了下划线，说明它落在了 Flutter 的无 Material 错误样式上',
    );
    expect(
      find.ancestor(of: finder, matching: find.byType(Material)),
      findsWidgets,
      reason: '「$text」缺少 Material 祖先，showGeneralDialog 不会替你补',
    );
  }

  testWidgets('弹窗自带 Material 祖先，文字不带错误下划线；取消返回 false', (tester) async {
    var result = true;
    await openDialog(tester, onResult: (value) => result = value);

    expectProperlyRendered(tester, '删除这条记录？');
    expectProperlyRendered(tester, message);
    expectProperlyRendered(tester, '取消');
    expectProperlyRendered(tester, '删除');

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(find.text('删除这条记录？'), findsNothing, reason: '点取消后弹窗应关闭');
    expect(result, false, reason: '取消必须返回 false，否则调用方会误删');
  });

  testWidgets('点确认返回 true', (tester) async {
    var result = false;
    await openDialog(tester, onResult: (value) => result = value);

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(find.text('删除这条记录？'), findsNothing);
    expect(result, true);
  });

  testWidgets('点蒙层关闭同样返回 false', (tester) async {
    var result = true;
    await openDialog(tester, onResult: (value) => result = value);

    // 卡片居中且窄，左上角一定在蒙层上。
    await tester.tapAt(const Offset(20, 40));
    await tester.pumpAndSettle();

    expect(find.text('删除这条记录？'), findsNothing);
    expect(result, false, reason: '点蒙层关闭不能返回 null，语义上必须等同取消');
  });

  testWidgets('破坏性操作的确认按钮取 danger，普通操作取 accent', (tester) async {
    Color? confirmColor() => tester.widget<Text>(find.text('删除')).style?.color;

    await openDialog(tester, onResult: (_) {}, destructive: true);
    expect(
      confirmColor(),
      AppTokens.light.danger,
      reason: '破坏性操作的确认按钮应取 tokens.danger',
    );
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    await openDialog(tester, onResult: (_) {}, destructive: false);
    expect(
      confirmColor(),
      AppTokens.light.accent,
      reason: '非破坏性操作的确认按钮应取 tokens.accent',
    );
  });

  testWidgets('取消在左、确认在右', (tester) async {
    await openDialog(tester, onResult: (_) {});

    final cancel = tester.getCenter(find.text('取消')).dx;
    final confirm = tester.getCenter(find.text('删除')).dx;

    expect(cancel, lessThan(confirm), reason: '按钮次序与原先两处弹窗相反了');
  });

  testWidgets('卡片圆角、底色与描边都取自设计令牌', (tester) async {
    await openDialog(tester, onResult: (_) {});

    // 圆角是卡片的身份标识，用它来定位；写死色值或圆角都会让这条断言变红。
    final card = find.ancestor(
      of: find.text('删除这条记录？'),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).borderRadius ==
                BorderRadius.circular(AppRadii.sheet),
      ),
    );
    expect(card, findsOneWidget, reason: '找不到 AppRadii.sheet 圆角的卡片');

    final decoration =
        tester.widget<DecoratedBox>(card).decoration as BoxDecoration;
    expect(decoration.color, AppTokens.light.bgCardSolid);
    expect(
      (decoration.border as Border?)?.top.color,
      AppTokens.light.glassBorder,
      reason: '卡片描边应取 tokens.glassBorder',
    );
  });
}
