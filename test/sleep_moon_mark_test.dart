import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/core/widgets/app_icons.dart';
import 'package:night_sleep/features/session/presentation/widgets/sleep_moon_mark.dart';

void main() {
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
