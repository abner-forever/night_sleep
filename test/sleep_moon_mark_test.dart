import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/core/widgets/app_icons.dart';
import 'package:night_sleep/features/session/presentation/widgets/sleep_moon_mark.dart';

void main() {
  /// 月亮当前的纵向偏移。`SleepMoonOrbit` 用 `Transform.translate` 包住月亮，
  /// 直接把它读回来——比截图比对便宜，也比「有没有排帧」这种代理指标准。
  double moonOffset(WidgetTester tester) {
    final transform = tester.widget<Transform>(
      find
          .ancestor(
            of: find.byType(SleepMoonMark),
            matching: find.byType(Transform),
          )
          .first,
    );
    return transform.transform.getTranslation().y;
  }

  testWidgets('月亮标记能渲染且不抛异常', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Center(child: SleepMoonMark())),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(SvgPicture), findsOneWidget);
  });

  test('交给 flutter_svg 的文档里没有 <filter>', () {
    // 实测：flutter_svg 2.3 会静默丢弃 <filter> 并在控制台打一行
    // `unhandled element <filter/>`。发光改用轨道光晕近似，所以源串里不该再有它，
    // 否则每帧一行警告，而且会让人误以为发光是滤镜画出来的。
    expect(sleepMoonSvg.contains('<filter'), isFalse);
    // 渐变与裁剪必须留着——月亮本体的质感全靠它们。
    expect(sleepMoonSvg.contains('linearGradient'), isTrue);
    expect(sleepMoonSvg.contains('radialGradient'), isTrue);
    expect(sleepMoonSvg.contains('clipPath'), isTrue);
  });

  testWidgets('长按图标与静音图标都能渲染', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcons.holdEnd(size: 20, color: const Color(0xFFFFFFFF)),
              AppIcons.soundOff(size: 21, color: const Color(0xFFFFFFFF)),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // 两个都是真的画出来了，而不是返回了一个空盒子。
    expect(find.byType(SvgPicture), findsNWidgets(2));
  });

  testWidgets('live 由 false 翻成 true 之后月亮真的动起来', (tester) async {
    // **不使用 pumpAndSettle**：live 之后是循环表，永远不 settle（见计划头部
    // Global Constraints）。全程显式 pump()，跑完由测试框架拆掉树。
    Widget tree({required bool live}) => MaterialApp(
          home: Center(child: SleepMoonOrbit(live: live)),
        );

    await tester.pumpWidget(tree(live: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(moonOffset(tester), 0, reason: '未激活时不该浮动');

    // 同一个元素位置重建，只把 live 翻成 true：State 被复用，
    // `didChangeDependencies` 不会再跑，必须靠 `didUpdateWidget` 接住。
    await tester.pumpWidget(tree(live: true));
    await tester.pump(); // 先跑一帧让 ticker 记下起始时间戳
    await tester.pump(const Duration(milliseconds: 1250));
    expect(moonOffset(tester), isNot(0), reason: 'live 翻真后月亮该动起来');
  });

  testWidgets('升降一整轮是 5 秒', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Center(child: SleepMoonOrbit(live: true))),
    );
    await tester.pump(); // 先跑一帧让 ticker 记下起始时间戳

    await tester.pump(const Duration(milliseconds: 2500));
    expect(moonOffset(tester), lessThanOrEqualTo(-6), reason: '2.5 秒升到顶（-7）');

    await tester.pump(const Duration(milliseconds: 2500));
    expect(moonOffset(tester), greaterThanOrEqualTo(-0.5),
        reason: '再 2.5 秒落回原点');
  });

  test('svgFor 把 currentColor 换成了给定颜色', () {
    // `AppIcons.glyph` 的取色走的就是这条替换；两个新图标与其余 29 个共用它。
    final resolved = AppIcons.svgFor(
      '<path d="M1 1" stroke="currentColor"/>',
      color: const Color(0xFFAEBDFF),
    );
    expect(resolved, contains('#aebdff'));
    expect(resolved, isNot(contains('currentColor')));
  });
}
