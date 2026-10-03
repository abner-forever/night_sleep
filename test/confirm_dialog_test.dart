import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/core/theme/app_theme.dart';
import 'package:night_sleep/core/theme/app_tokens.dart';
import 'package:night_sleep/core/widgets/confirm_dialog.dart';

/// 确认弹窗的护栏。
///
/// v3.6 之前这里钉的是「自绘 iOS 风格盒子」的特征——`Material` 祖先、两条
/// `ColoredBox` 发丝线、`AppRadii.sheet` 圆角卡片。**那些断言随实现一起作废了**：
/// 现在弹窗是 iOS **系统组件** [CupertinoAlertDialog]，布局、分隔线、底色、圆角
/// 全在 SDK 里，断言它们等于在测 Flutter 自己。
///
/// 留在这里的是「换组件时最容易被顺手改坏、而调用方看不见」的四件事：
///
///  * **用的确实是系统组件。**这是主回归锚：退回任何自绘实现，第一条就红。
///  * **返回值语义不变。**三处调用方都写 `if (confirmed != true) return;`：取消与
///    点蒙层必须返回 `false`、不能是 `null`，否则「取消」会变成「照删不误」。
///  * **按钮左右次序不变**：取消在左、确认在右，避免肌肉记忆错位。
///  * **动作配色仍接令牌。**系统组件默认给 destructive 写死 `systemRed`，我们靠
///    `CupertinoDialogAction.textStyle` 盖回 `tokens.danger` / `tokens.accent`
///    ——这个覆盖一旦被人删掉，界面上不会有任何报错，只有颜色悄悄变成系统红。
void main() {
  const message = '这一晚的睡眠记录、睡眠阶段与声音事件都会被永久删除，此操作无法撤销。';

  /// 弹窗的宿主页面：一个普通页面上的按钮，点它打开确认弹窗。
  Future<void> pumpHost(
    WidgetTester tester, {
    required ValueChanged<bool> onResult,
    bool destructive = true,
    ThemeData? theme,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.light(),
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
    ThemeData? theme,
  }) async {
    await pumpHost(
      tester,
      onResult: onResult,
      destructive: destructive,
      theme: theme,
    );
    await tester.tap(find.text('触发'));
    await tester.pumpAndSettle();
  }

  /// 动作按钮渲染出来的文字色。样式经 `DefaultTextStyle` 落地，读的就是屏幕上那一层。
  Color? actionColor(WidgetTester tester, String label) =>
      DefaultTextStyle.of(tester.element(find.text(label))).style.color;

  testWidgets('用的是 iOS 系统组件，四条文案原样渲染', (tester) async {
    await openDialog(tester, onResult: (_) {});

    expect(
      find.byType(CupertinoAlertDialog),
      findsOneWidget,
      reason: '确认弹窗必须是 CupertinoAlertDialog。退回自绘实现会让这条变红',
    );

    expect(find.text('删除这条记录？'), findsOneWidget, reason: '标题');
    expect(find.text(message), findsOneWidget, reason: '正文');
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
  });

  testWidgets('取消返回 false', (tester) async {
    var result = true;
    await openDialog(tester, onResult: (value) => result = value);

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

    // 弹窗定宽 270 且居中，左上角一定落在蒙层上。
    await tester.tapAt(const Offset(20, 40));
    await tester.pumpAndSettle();

    expect(find.text('删除这条记录？'), findsNothing);
    expect(result, false, reason: '点蒙层关闭不能返回 null，语义上必须等同取消');
  });

  testWidgets('取消在左、确认在右', (tester) async {
    await openDialog(tester, onResult: (_) {});

    final cancel = tester.getCenter(find.text('取消')).dx;
    final confirm = tester.getCenter(find.text('删除')).dx;

    expect(cancel, lessThan(confirm), reason: '按钮次序与原先两处弹窗相反了');
  });

  testWidgets('破坏性操作取 danger，普通操作取 accent', (tester) async {
    await openDialog(tester, onResult: (_) {}, destructive: true);
    expect(
      actionColor(tester, '删除'),
      AppTokens.light.danger,
      reason: '破坏性操作的确认按钮应盖回 tokens.danger（系统默认是 systemRed）',
    );
    expect(actionColor(tester, '取消'), AppTokens.light.accent);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    await openDialog(tester, onResult: (_) {}, destructive: false);
    expect(
      actionColor(tester, '删除'),
      AppTokens.light.accent,
      reason: '非破坏性操作的确认按钮应取 tokens.accent',
    );
  });

  testWidgets('深色主题下弹窗亮度跟随应用，而不是系统', (tester) async {
    await openDialog(tester, onResult: (_) {}, theme: AppTheme.dark());

    final theme = CupertinoTheme.of(
      tester.element(find.byType(CupertinoAlertDialog)),
    );
    expect(
      theme.brightness,
      Brightness.dark,
      reason: '亮度没跟上的话，系统弹窗在深色应用里会是浅底',
    );
    expect(theme.primaryColor, AppTokens.dark.accent,
        reason: 'primaryColor 应取暗色令牌');
  });
}
