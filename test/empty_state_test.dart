import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/core/theme/app_theme.dart';
import 'package:night_sleep/core/widgets/app_basics.dart';
import 'package:night_sleep/core/widgets/glass_surface.dart';

/// `EmptyState` 的几何。
///
/// 2026-10-16 使用方在真机上看出「所有睡眠数据页当前周期没数据时，兜底组件没居中」：
/// 内容是**贴着左边**的。根因是 `GlassSurface` 把子项画在 `Stack` 里，非定位子项
/// 拿到的是**宽松**约束——`Column` 于是在那种约束下缩到最宽子项的宽度（这里就是
/// 标题那一行）并被左锚定，`crossAxisAlignment` 的中心只在那一段里生效。
///
/// 这一条不只影响那一页：首页 / 统计 / 导出预览 / 详情弹层的空状态都在用同一个组件。
void main() {
  Future<void> pumpEmptyState(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(16),
            child: EmptyState(
              icon: SizedBox(width: 30, height: 30),
              title: '这个周期还没有睡眠记录',
              body: '可切换其他周期查看历史数据',
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('卡是满宽的', (tester) async {
    await pumpEmptyState(tester);
    final card = tester.getRect(find.byType(GlassSurface).first);
    // 视口 800 宽，两边各 16 的内边距。
    expect(card.width, moreOrLessEquals(800 - 32, epsilon: 1));
  });

  testWidgets('标题与正文都在卡内水平居中，不是缩在左边', (tester) async {
    await pumpEmptyState(tester);
    final card = tester.getRect(find.byType(GlassSurface).first);
    final title = tester.getRect(find.text('这个周期还没有睡眠记录'));
    final body = tester.getRect(find.text('可切换其他周期查看历史数据'));

    expect(
      title.center.dx,
      moreOrLessEquals(card.center.dx, epsilon: 1),
      reason: '标题没有在卡内居中——Column 在 Stack 的宽松约束下缩窄并被左锚定',
    );
    expect(
      body.center.dx,
      moreOrLessEquals(card.center.dx, epsilon: 1),
      reason: '正文没有在卡内居中',
    );
  });

  testWidgets('圆形图标也在卡内居中', (tester) async {
    await pumpEmptyState(tester);
    final card = tester.getRect(find.byType(GlassSurface).first);
    // 68×68 的 accent-soft 圆底就是 icon 外面那个 Container。
    final orb = tester.getRect(
      find
          .ancestor(
            of: find.byType(SizedBox),
            matching: find.byWidgetPredicate(
              (w) => w is Container && w.constraints?.maxWidth == 68,
            ),
          )
          .first,
    );
    expect(orb.center.dx, moreOrLessEquals(card.center.dx, epsilon: 1),
        reason: '图标没有在卡内居中');
  });
}
