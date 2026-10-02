import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/features/session/presentation/night_scene.dart';

void main() {
  test('八种场景的 id 与标签与原型一致', () {
    expect(NightScene.values.map((s) => s.id).toList(), [
      'meteor',
      'aurora',
      'ocean',
      'moon',
      'cloud',
      'firefly',
      'galaxy',
      'rain',
    ]);
    expect(NightScene.meteor.label, '流星夜');
    expect(NightScene.rain.label, '雨夜');
  });

  test('每个场景都有底色与预览底色', () {
    for (final scene in NightScene.values) {
      expect(scene.background.colors.length, greaterThanOrEqualTo(2),
          reason: '${scene.id} 的整页底色缺失');
      expect(scene.previewGradient.colors.length, greaterThanOrEqualTo(2),
          reason: '${scene.id} 的预览底色缺失');
    }
  });

  test('认不出的 id 回落默认场景，不抛', () {
    expect(NightScene.fromId('galaxy'), NightScene.galaxy);
    // 库里可能存着上一个版本写下的 id，或干脆是坏数据。
    expect(NightScene.fromId('nebula-2077'), NightScene.fallback);
    expect(NightScene.fromId(null), NightScene.fallback);
    expect(NightScene.fromId(''), NightScene.fallback);
  });
}
