import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/app/app_toast.dart';
import 'package:night_sleep/core/theme/app_theme.dart';
import 'package:night_sleep/core/theme/app_tokens.dart';
import 'package:night_sleep/core/widgets/app_basics.dart';
import 'package:night_sleep/core/widgets/subpage.dart';
import 'package:night_sleep/features/settings/presentation/sleep_import_page.dart';

/// `PrimaryAction` 禁用态的护栏。
///
/// 导入页那颗「导入睡眠记录」按钮是全项目唯一一颗禁用态的 `PrimaryAction`，它同时
/// 犯了两个毛病（用户报的「按钮上方有根白线」和「点了没反应」）：
///
///  * **顶边高光成了一根多余的白线。** `inset 0 1px rgba(255,255,255,.25)` 那条镜面
///    高光是给启用态走的（同一类的还有那圈蓝色投影），落到一颗 60% 不透明的禁用
///    按钮上，就成了它身上最跳的元素。位置本身没错，错在用了不该用的状态。
///  * **手势被整个吞掉。** `onTap: null` 时 `Pressable` 把四个手势回调全部置空，
///    手指按下去连一点回应都没有；用户的补充是「没有实现可以给一个相关反馈提示」。
///
/// 于是新增了 `onBlockedTap`：外观仍是禁用，但手势接得住。下面这些用例钉的是
/// 「启用态一个字节都没变、禁用态既不亮也没有按下的手感」——启用态的另两个调用点
/// （首页、引导页）就靠启用态那几条守着。
void main() {
  /// 按钮的宿主。`PrimaryAction` 读设计令牌，所以要有主题；它自己不带 `Scaffold`，
  /// 这里也不需要外壳。
  Widget host(Widget child) => MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: Center(child: child)),
      );

  /// 顶边那条 1px 镜面高光。颜色就是设计里写死的 `rgba(255,255,255,.25)`。
  ///
  /// 每次现构造 finder 而不是复用同一个对象，免得碰上 finder 的求值缓存。
  Finder litHighlight() => find.descendant(
        of: find.byType(PrimaryAction),
        matching: find.byWidgetPredicate(
          (w) =>
              w is DecoratedBox &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).color ==
                  Colors.white.withValues(alpha: 0.25),
        ),
      );

  /// 按钮本体的装饰（渐变 + 圆角 + 可能有的投影）。
  BoxDecoration buttonDecoration(WidgetTester tester) {
    final container = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(PrimaryAction),
            matching: find.byType(Container),
          )
          .first,
    );
    return container.decoration! as BoxDecoration;
  }

  /// 按钮的不透明度。禁用态是 0.6，启用态是 1。
  double opacityOf(WidgetTester tester) => tester
      .widget<Opacity>(
        find
            .ancestor(of: find.text('导入'), matching: find.byType(Opacity))
            .first,
      )
      .opacity;

  /// 拦截 `HapticFeedback.vibrate`，把「按下去有没有手感」变成可断言的事实。
  ///
  /// 测试环境没有触觉引擎，`setMockMethodCallHandler` 既拦下调用也记录了次数。
  List<MethodCall> recordHaptics(WidgetTester tester) {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') calls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    return calls;
  }

  group('禁用态', () {
    testWidgets('不画顶边高光', (tester) async {
      await tester.pumpWidget(
        host(const PrimaryAction(label: '导入', onTap: null)),
      );

      expect(litHighlight(), findsNothing, reason: '禁用态不该有顶边高光');
    });

    testWidgets('不画蓝色投影', (tester) async {
      await tester.pumpWidget(
        host(const PrimaryAction(label: '导入', onTap: null)),
      );

      final decoration = buttonDecoration(tester);
      expect(decoration.boxShadow, isNull, reason: '禁用态不该有那圈蓝色投影');
      expect(decoration.gradient, isNotNull, reason: '按钮本身的渐变必须还在');
    });
  });

  group('禁用但可点击', () {
    testWidgets('接住点击，外观保持禁用', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(
        host(
          PrimaryAction(
            label: '导入',
            onTap: null,
            onBlockedTap: () => tapped++,
          ),
        ),
      );

      await tester.tap(find.text('导入'));
      await tester.pump();

      expect(tapped, 1, reason: '点击必须被接住，否则用户看到的就是「点了没反应」');
      expect(opacityOf(tester), 0.6, reason: '不能因为接了回调就把按钮显示成可用');
    });

    testWidgets('仍不画高光与投影', (tester) async {
      await tester.pumpWidget(
        host(
          PrimaryAction(label: '导入', onTap: null, onBlockedTap: () {}),
        ),
      );

      expect(litHighlight(), findsNothing, reason: '接了回调也不该亮起顶边高光');
      expect(
        buttonDecoration(tester).boxShadow,
        isNull,
        reason: '接了回调也不该有那圈蓝色投影',
      );
    });

    testWidgets('不触发触觉反馈', (tester) async {
      final haptics = recordHaptics(tester);
      await tester.pumpWidget(
        host(
          PrimaryAction(label: '导入', onTap: null, onBlockedTap: () {}),
        ),
      );

      await tester.tap(find.text('导入'));
      await tester.pump();

      expect(haptics, isEmpty, reason: '禁用态给提示不该有「按下了」的手感');
    });
  });

  group('启用态', () {
    testWidgets('onTap 非空时 onBlockedTap 让位', (tester) async {
      var taps = 0;
      var blocked = 0;
      await tester.pumpWidget(
        host(
          PrimaryAction(
            label: '导入',
            onTap: () => taps++,
            onBlockedTap: () => blocked++,
          ),
        ),
      );

      await tester.tap(find.text('导入'));
      await tester.pump();

      expect(taps, 1);
      expect(blocked, 0, reason: '两个回调都给了也必须走 onTap');
    });

    testWidgets('高光、投影与不透明度都还在', (tester) async {
      await tester.pumpWidget(host(PrimaryAction(label: '导入', onTap: () {})));

      expect(litHighlight(), findsOneWidget, reason: '启用态必须有顶边高光');
      final shadow = buttonDecoration(tester).boxShadow;
      expect(shadow, isNotNull, reason: '启用态必须有那圈蓝色投影');
      expect(shadow!.single.color,
          const Color(0xFF007AFF).withValues(alpha: 0.24));
      expect(shadow.single.blurRadius, 22);
      expect(shadow.single.offset, const Offset(0, 10));
      expect(opacityOf(tester), 1, reason: '启用态不能被调成半透明');
    });

    testWidgets('顶边高光被裁进圆角，不从左右上角溢出', (tester) async {
      await tester.pumpWidget(host(PrimaryAction(label: '导入', onTap: () {})));

      // 高光是一条 1px 高的直条，装不下 16px 的圆角——Flutter 会把它的圆角压到
      // 0.5px（等于直角），两端于是横着伸出按钮轮廓，深色主题下就是那两根白刺。
      final clip = find.descendant(
        of: find.byType(PrimaryAction),
        matching: find.byType(ClipPath),
      );
      expect(clip, findsOneWidget, reason: '按钮必须把子层裁进圆角');
      expect(
        find.descendant(of: clip, matching: litHighlight()),
        findsOneWidget,
        reason: '高光必须落在裁剪层之内，不能被留在轮廓外面',
      );

      final size = tester.getSize(clip);
      final path = tester.widget<ClipPath>(clip).clipper!.getClip(size);
      expect(
        path.contains(const Offset(1, 0.5)),
        isFalse,
        reason: '左上圆角之外的像素必须被裁掉',
      );
      expect(
        path.contains(Offset(size.width - 1, 0.5)),
        isFalse,
        reason: '右上圆角之外的像素必须被裁掉',
      );
      expect(
        path.contains(Offset(size.width / 2, 0.5)),
        isTrue,
        reason: '顶边正中那截高光必须留着，别把整条都裁没了',
      );
    });

    testWidgets('点击调用 onTap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        host(PrimaryAction(label: '导入', onTap: () => taps++)),
      );

      await tester.tap(find.text('导入'));
      await tester.pump();

      expect(taps, 1);
    });

    testWidgets('按压触发一次触觉反馈', (tester) async {
      final haptics = recordHaptics(tester);
      await tester.pumpWidget(host(PrimaryAction(label: '导入', onTap: () {})));

      await tester.tap(find.text('导入'));
      await tester.pump();

      expect(haptics, hasLength(1), reason: '启用态的「按下了」手感不能丢');
    });
  });

  group('导入页', () {
    testWidgets('点按禁用按钮给出页内提示，且不走全局 toast', (tester) async {
      tester.view.physicalSize = const Size(430, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const SleepImportPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final tokens = AppTokens.of(tester.element(find.byType(SleepImportPage)));
      const resident = '需要你提供小米的导出样本后，这里才会启用。';
      const blockedNotice = '还没有接入导入：需要小米的导出样本或官方字段说明。';

      // 未点按：常驻那行是人人第一眼就能看到的解释，必须在。
      expect(find.text(resident), findsOneWidget);
      expect(
        find.text(blockedNotice),
        findsNothing,
        reason: '提示只该在点过之后出现',
      );

      await tester.ensureVisible(find.text('导入睡眠记录'));
      await tester.tap(find.text('导入睡眠记录'));
      await tester.pumpAndSettle();

      // 点按后：同一个槽位**换成**新提示——是替换，不是并列成两句说同一件事的话。
      expect(
        find.descendant(
          of: find.byType(Subpage),
          matching: find.text(blockedNotice),
        ),
        findsOneWidget,
        reason: '点了必须给一句解释，而不是毫无反应',
      );
      expect(
        find.text(resident),
        findsNothing,
        reason: '常驻那行必须被替换掉，不能与新提示并列',
      );
      expect(
        tester.widget<Text>(find.text(blockedNotice)).style?.color,
        tokens.caution,
        reason: '替换后要用 caution 色，与常驻那行的 muted 区分开',
      );

      // 再点一次不叠加、不新增第二行。
      await tester.tap(find.text('导入睡眠记录'));
      await tester.pumpAndSettle();
      expect(find.text(blockedNotice), findsOneWidget);
      expect(find.text(resident), findsNothing);

      // 提示必须是页内的：`ToastOverlay` 挂在 `AppScaffold` 里，而导入页 push 在外壳
      // 之上，全局提示条会被整个盖住。这里确认 tap 没有去动那个 provider。
      expect(
        ProviderScope.containerOf(tester.element(find.byType(SleepImportPage)))
            .read(toastProvider),
        isNull,
        reason: '提示不该走全局 toast（会被二级页盖住）',
      );
    });
  });
}
