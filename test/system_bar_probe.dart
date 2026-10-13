import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 量「框架此刻会发给平台的系统栏样式」——复刻的是框架自己那段代码。
///
/// `RenderView._updateSystemChrome` 就是这么取值的：状态栏取屏幕水平中线与**顶部**的
/// 交点、导航栏取与**底部**的交点，各取**覆盖该点的最上面一层**。探针点照抄它，
/// 于是断言的就是真机上会发生的事。
///
/// **别用 `tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>` 代替。** 那只能证明
/// 树上有个 region——挂在 `MaterialApp.builder` 上、挂进 `AppScaffold` 里、甚至挂在
/// 一个永远覆盖不到的角落，都能找出来；而「页面的覆写有没有压过外层」这个问题，
/// 它一个字都答不上来。
///
/// 走 `debugLayer` 而不是 `layer`：后者是 `@protected`，测试文件碰不到。
///
/// 这个文件**不以 `_test.dart` 结尾**，所以 `flutter test` 不会把它当用例跑。
SystemUiOverlayStyle? systemBarStyleAt(
  WidgetTester tester, {
  bool top = true,
}) {
  final size = tester.view.physicalSize / tester.view.devicePixelRatio;
  final probe = Offset(size.width / 2, top ? 1 : size.height - 1);
  return tester.binding.renderViews.first.debugLayer
      ?.find<SystemUiOverlayStyle>(probe);
}
