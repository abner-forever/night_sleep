import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/core/theme/app_theme.dart';
import 'package:night_sleep/core/widgets/ios_controls.dart';

/// Regression tests for the segmented control's sliding capsule.
///
/// The bug this guards against: the capsule was positioned from the *parent's*
/// max width divided by the segment count, while the segments themselves were
/// content-sized. On Statistics the control hugs its content, so the capsule
/// landed at a width and offset no segment occupied. The capsule must now be
/// derived from the same segment width the labels are laid out with.
void main() {
  const segments = [
    SegmentOption(value: 7, label: '7天'),
    SegmentOption(value: 14, label: '14天'),
    SegmentOption(value: 30, label: '30天'),
  ];

  Future<void> pump(
    WidgetTester tester, {
    required bool expand,
    int selected = 7,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              child: Align(
                alignment: Alignment.centerLeft,
                child: SegmentedControl<int>(
                  segments: segments,
                  selected: selected,
                  expand: expand,
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Rect capsuleRect(WidgetTester tester) {
    final positioned = tester.widget<AnimatedPositioned>(
      find.byType(AnimatedPositioned),
    );
    final control = tester.getRect(find.byType(SegmentedControl<int>));
    // AnimatedPositioned is relative to the padded track, 3px inside.
    return Rect.fromLTWH(
      control.left + 3 + (positioned.left ?? 0),
      control.top + 3,
      positioned.width ?? 0,
      control.height - 6,
    );
  }

  testWidgets('内容自适应时刻意窄于父容器，但胶囊与分段同宽', (tester) async {
    await pump(tester, expand: false);

    final controlWidth =
        tester.getSize(find.byType(SegmentedControl<int>)).width;
    expect(
      controlWidth,
      lessThan(400),
      reason: '未展开时段段控件应包裹内容，而不是占满父容器',
    );

    final widthPerSegment = (controlWidth - 6) / segments.length;
    expect(capsuleRect(tester).width, closeTo(widthPerSegment, 0.5));
  });

  testWidgets('选中项靠后时胶囊位移与段宽成整数倍', (tester) async {
    await pump(tester, expand: false, selected: 30);

    final controlWidth =
        tester.getSize(find.byType(SegmentedControl<int>)).width;
    final widthPerSegment = (controlWidth - 6) / segments.length;
    final capsule = capsuleRect(tester);
    final controlLeft = tester.getRect(find.byType(SegmentedControl<int>)).left;

    expect(capsule.width, closeTo(widthPerSegment, 0.5));
    expect(
      capsule.left - controlLeft - 3,
      closeTo(2 * widthPerSegment, 0.5),
      reason: '第三个分段应位移两个段宽',
    );
  });

  testWidgets('展开时占满父容器且每段等宽', (tester) async {
    await pump(tester, expand: true);

    final controlWidth =
        tester.getSize(find.byType(SegmentedControl<int>)).width;
    expect(controlWidth, closeTo(400, 0.5));

    final widthPerSegment = (controlWidth - 6) / segments.length;
    expect(capsuleRect(tester).width, closeTo(widthPerSegment, 0.5));
  });

  testWidgets('每个分段都渲染出来', (tester) async {
    await pump(tester, expand: false);
    for (final segment in segments) {
      expect(find.text(segment.label), findsOneWidget);
    }
  });
}
