/// 钉住两个平台**已提交**的图标产物的几何与色型。
///
/// 断言对象是仓库里的 PNG 本身，不是生成器的中间结果——这样任何人手改产物、
/// 或改坏生成器后重跑，都会在这里变红，而不是在用户戴上 Dock 才发现。
///
/// 为什么 macOS 要圆角：`iOS 和 macOS 都会自己套遮罩` 是错的，macOS 不会。
/// 实测系统 app（Calculator / Notes）的 `.icns`，`alpha>128` 的实体恰为
/// 206/256 = 824/1024，四边留白全等——圆角与留白是**烘焙在文件里**的。
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

const String _macos1024 =
    'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png';
const String _macos256 =
    'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_256.png';
const String _ios1024 =
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png';

void main() {
  // 用普通 test() 而非 testWidgets：FakeAsync 下引擎的异步解码不保证完成。
  TestWidgetsFlutterBinding.ensureInitialized();

  test('macOS 1024 图标：圆角烘焙 + 四边留白 100', () async {
    final bytes = File(_macos1024).readAsBytesSync();
    final rgba = await _decode(bytes, _macos1024);
    final img = _Geometry.of(rgba, 1024);

    expect(img.cornerAlpha, lessThan(8), reason: '左上角应当是透明的（圆角在文件里）');
    expect(img.centreAlpha, 255, reason: '中心必须不透明');
    expect(img.bodyWidth, 824, reason: '实体宽应为 Apple 网格的 824/1024');
    expect(img.bodyHeight, 824);
    expect(img.padLeft, 100);
    expect(img.padTop, 100);
    expect(img.padRight, 100);
    expect(img.padBottom, 100);
  });

  test('macOS 256 图标：同一套比例缩下来', () async {
    final rgba = await _decode(File(_macos256).readAsBytesSync(), _macos256);
    final img = _Geometry.of(rgba, 256);

    // 824/1024×256 = 206；留白 (256−206)/2 = 25。
    expect(img.bodyWidth, closeTo(206, 1));
    expect(img.padLeft, closeTo(25, 1));
    expect(img.padTop, closeTo(25, 1));
    expect(img.cornerAlpha, lessThan(8));
  });

  test('macOS 图标必须带 alpha 通道（色型 6）', () {
    expect(_colourType(File(_macos1024).readAsBytesSync()), 6,
        reason: '四角的透明必须有 alpha 通道才存得下');
  });

  test('iOS 图标不受影响：满幅直角且无 alpha 通道（色型 2）', () async {
    final bytes = File(_ios1024).readAsBytesSync();
    expect(_colourType(bytes), 2, reason: 'App Store 拒收带 alpha 的应用图标');

    final rgba = await _decode(bytes, _ios1024);
    final img = _Geometry.of(rgba, 1024);
    expect(img.cornerAlpha, 255, reason: 'iOS 由系统套遮罩，文件本身必须满幅不透明');
    expect(img.bodyWidth, 1024);
    expect(img.padLeft, 0);
  });
}

/// PNG 的 IHDR 里，颜色类型在第 25 个字节（8 签名 + 4 长度 + 4 `IHDR` + 4 宽 + 4 高 + 1 位深）。
int _colourType(Uint8List png) => png[25];

/// 解码成未预乘的 RGBA 字节。
Future<Uint8List> _decode(Uint8List bytes, String path) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
  frame.image.dispose();
  codec.dispose();
  expect(data, isNotNull, reason: '$path 解码失败');
  return data!.buffer.asUint8List();
}

/// 按 `alpha > 128` 量实体（与量系统图标时同一口径，投影的软边因此不参与）。
class _Geometry {
  const _Geometry(this.cornerAlpha, this.centreAlpha, this.left, this.top,
      this.right, this.bottom, this.size);

  final int cornerAlpha;
  final int centreAlpha;
  final int left, top, right, bottom, size;

  int get bodyWidth => right - left + 1;
  int get bodyHeight => bottom - top + 1;
  int get padLeft => left;
  int get padTop => top;
  int get padRight => size - 1 - right;
  int get padBottom => size - 1 - bottom;

  static _Geometry of(Uint8List rgba, int size) {
    int alphaAt(int x, int y) => rgba[(y * size + x) * 4 + 3];

    var left = size, right = -1, top = size, bottom = -1;
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        if (alphaAt(x, y) > 128) {
          if (x < left) left = x;
          if (x > right) right = x;
          if (y < top) top = y;
          if (y > bottom) bottom = y;
        }
      }
    }
    return _Geometry(alphaAt(0, 0), alphaAt(size ~/ 2, size ~/ 2), left, top,
        right, bottom, size);
  }
}
