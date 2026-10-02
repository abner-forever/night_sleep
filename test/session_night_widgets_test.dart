import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/features/session/presentation/night_scene.dart';
import 'package:night_sleep/features/session/presentation/widgets/night_scene_picker.dart';

void main() {
  Future<void> pumpPicker(
    WidgetTester tester, {
    required NightScene scene,
    required ValueChanged<NightScene> onChanged,
  }) async {
    // 取一块足够宽的画布：八张卡 8×68 + 7×10 + 24 ≈ 638px，手机宽（430）下
    // 第七章「银河」会落在视口外——懒加载的 `ListView` 不会把它摆上台面，
    // `find.text` 又会跳过台面外的子节点，于是「列出全部八种」与「点银河」
    // 两条断言都够不着它。本仓库既有的做法正是给测试一块超尺寸画布
    // （如 `Size(430, 2600)`）让全部内容一次摊开，这里同理把宽放开。
    tester.view.physicalSize = const Size(900, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NightScenePicker(scene: scene, onChanged: onChanged),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('列出全部八种场景，一个不多一个不少', (tester) async {
    await pumpPicker(tester, scene: NightScene.meteor, onChanged: (_) {});

    for (final option in NightScene.values) {
      expect(find.text(option.label), findsOneWidget,
          reason: '漏了「${option.label}」');
    }
    // 反向护栏：搬错枚举（例如把原型的九宫格搬过来）时这条必须红。
    expect(
        find.byType(NightSceneChoice), findsNWidgets(NightScene.values.length));
  });

  testWidgets('点一种场景回调的是那一种', (tester) async {
    final picked = <NightScene>[];
    await pumpPicker(tester, scene: NightScene.meteor, onChanged: picked.add);

    await tester.tap(find.text('银河'));
    await tester.pumpAndSettle();

    expect(picked, [NightScene.galaxy]);
  });

  testWidgets('选中的那一张有标记', (tester) async {
    await pumpPicker(tester, scene: NightScene.ocean, onChanged: (_) {});

    final selected = tester.widget<NightSceneChoice>(
      find.byWidgetPredicate(
        (w) => w is NightSceneChoice && w.selected,
      ),
    );
    expect(selected.scene, NightScene.ocean);
  });
}
