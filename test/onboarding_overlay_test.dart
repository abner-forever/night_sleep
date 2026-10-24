import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/core/theme/app_theme.dart';
import 'package:night_sleep/features/onboarding/presentation/onboarding_overlay.dart';

void main() {
  testWidgets('三张引导页按设计顺序展示并可完成', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var done = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Stack(
            children: [
              OnboardingOverlay(onDone: () => done++),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('记录你的每一夜'), findsOneWidget);
    expect(find.byType(OnboardingArtwork), findsOneWidget);

    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(find.text('聆听夜间的声音'), findsOneWidget);

    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(find.text('看见长期的趋势'), findsOneWidget);

    await tester.tap(find.text('开始使用'));
    await tester.pumpAndSettle();
    expect(done, 1);
  });
}
