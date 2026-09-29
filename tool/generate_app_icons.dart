/// Regenerates the iOS and macOS app icon sets from `assets/branding/app-icon.svg`.
///
/// Run it after changing the icon:
///
/// ```bash
/// flutter test tool/generate_app_icons.dart
/// ```
///
/// It lives under `tool/` rather than `test/` so it does not run as part of
/// `flutter test` — it rewrites files, and a test run should not.
///
/// **Why this exists instead of a design tool export.** The icon is one 1024px
/// vector; the platforms need 22 raster sizes between them, and each has to be
/// resampled from the vector rather than from a previously rasterised copy.
/// Rendering every size straight from the SVG with `FilterQuality.high` avoids
/// the compounding softness of downscaling a downscale.
///
/// 三个平台规则在这里被显式处理，而不是听天由命：
///
///  * **iOS 不要 alpha。** App Store 校验拒收带 alpha 通道的应用图标，
///    所以 iOS 那套每一块都画在不透明底上，并用色型 2 编码。
///    （注：透明图标在别处会被画成黑方块，这是同一条规则的另一种表现。）
///  * **iOS 不要圆角。** iOS 会给应用图标套遮罩，文件里再烘焙一层圆角，
///    结果就是「圆角套圆角」。`assets/branding/app-icon.svg` 因此是满幅的。
///  * **macOS 两条都要反过来。** macOS **不套遮罩**——实测系统 app 的 `.icns`，
///    圆角与留白是烘焙在文件里的。所以 macOS 这套按 Apple 图标网格自己画圆角
///    （实体 824/1024、半径 185.4、四边留白 100）、加投影，并**保留 alpha**。
///    历史注释曾写「iOS 和 macOS 都会套遮罩」，据此后两个平台共用满幅直角像素，
///    结果 macOS 的 Dock 图标被撑成一个方块。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Every raster the two asset catalogues reference, deduplicated: several
/// entries share one file (an iPad 20pt@1x and an iPhone 20pt@1x are the same
/// 20 pixels), and writing it twice would be wasted work with a chance of the
/// two copies differing.
const Map<String, int> iosIcons = {
  'Icon-App-20x20@1x.png': 20,
  'Icon-App-20x20@2x.png': 40,
  'Icon-App-20x20@3x.png': 60,
  'Icon-App-29x29@1x.png': 29,
  'Icon-App-29x29@2x.png': 58,
  'Icon-App-29x29@3x.png': 87,
  'Icon-App-40x40@1x.png': 40,
  'Icon-App-40x40@2x.png': 80,
  'Icon-App-40x40@3x.png': 120,
  'Icon-App-60x60@2x.png': 120,
  'Icon-App-60x60@3x.png': 180,
  'Icon-App-76x76@1x.png': 76,
  'Icon-App-76x76@2x.png': 152,
  'Icon-App-83.5x83.5@2x.png': 167,
  'Icon-App-1024x1024@1x.png': 1024,
};

const Map<String, int> macosIcons = {
  'app_icon_16.png': 16,
  'app_icon_32.png': 32,
  'app_icon_64.png': 64,
  'app_icon_128.png': 128,
  'app_icon_256.png': 256,
  'app_icon_512.png': 512,
  'app_icon_1024.png': 1024,
};

/// Side of the canvas the SVG is rasterised onto before any downscaling.
const int masterSize = 1024;

/// macOS 图标的 Apple 网格：1024 画布上实体占 824×824 居中，圆角半径 185.4。
///
/// 实测自系统 app 的 `.icns`（Calculator / Notes 结果一致）：`alpha>128` 的实体恰为
/// 206/256 = 824/1024，四边留白全等，圆角半径量得 44/256。
const double macosBodyFraction = 824 / 1024;
const double macosCornerRadius = 185.4;

/// macOS 图标的投影。三个值由系统图标的 `alpha>8` 包络反推后扫参逼近得到：
/// 目标包络 L84 T96 R84 B72，本组得 L85 T99 R85 B71（1024 基准，最大差 3px）。
const Offset macosShadowOffset = Offset(0, 14);
const double macosShadowSigma = 10;
const Color macosShadowColor = Color(0x80000000);

/// macOS 实体矩形（1024 画布，居中）。
///
/// `masterSize * (1 - macosBodyFraction)` 是 `int * double`，但除法与乘法在
/// 常量求值里都成立，所以整条表达式是编译期常量，这里可以是 `const`。
const Rect macosBodyRect = Rect.fromLTWH(
  masterSize * (1 - macosBodyFraction) / 2,
  masterSize * (1 - macosBodyFraction) / 2,
  masterSize * macosBodyFraction,
  masterSize * macosBodyFraction,
);

void main() {
  // 需要 binding 才能用 `Picture.toImage`。**故意不用 `testWidgets`**：那会跑在
  // FakeAsync 里，`flutter_svg` 的异步解析永不完成，症状是挂死而不是失败。
  TestWidgetsFlutterBinding.ensureInitialized();

  test('regenerate app icons from the source SVG', () async {
    final root = Directory.current;
    final svgFile =
        File(p.join(root.path, 'assets', 'branding', 'app-icon.svg'));
    expect(svgFile.existsSync(), isTrue, reason: '找不到 ${svgFile.path}');

    // 矢量只解析一次，两个平台各画各的。
    final pictureInfo =
        await vg.loadPicture(SvgStringLoader(svgFile.readAsStringSync()), null);
    try {
      final iosMaster = await _rasteriseOpaque(
          pictureInfo.picture, pictureInfo.size, masterSize);
      await _writeAll(
        p.join(root.path, 'ios', 'Runner', 'Assets.xcassets',
            'AppIcon.appiconset'),
        iosIcons,
        iosMaster,
        opaque: true,
      );
      iosMaster.dispose();

      final macosMaster =
          await _rasteriseMacos(pictureInfo.picture, pictureInfo.size);
      await _writeAll(
        p.join(root.path, 'macos', 'Runner', 'Assets.xcassets',
            'AppIcon.appiconset'),
        macosIcons,
        macosMaster,
        opaque: false,
      );
      macosMaster.dispose();
    } finally {
      pictureInfo.picture.dispose();
    }
  });
}

/// 把 [picture] 满幅画到 [size]×[size] 的**不透明**画布上（iOS 用）。
///
/// 不透明是必须的：解码出来的 PNG 会带着光栅器产生的任意 alpha，而 iOS 拒收半透明图标。
Future<ui.Image> _rasteriseOpaque(
    ui.Picture picture, Size srcSize, int size) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
    Paint()..color = const Color(0xFF000000),
  );
  canvas.scale(size / srcSize.width, size / srcSize.height);
  canvas.drawPicture(picture);
  return recorder.endRecording().toImage(size, size);
}

/// 把 [picture] 画进 Apple 网格的圆角实体里，并在下方垫一层投影（macOS 用）。
///
/// 画布**保持透明**——四角的透明正是圆角本身。
///
/// 顺序不能颠倒：先画投影（它在实体之外、不会被裁），再 `clipRRect` 裁住实体。
/// 反过来的话投影会被裁没。
Future<ui.Image> _rasteriseMacos(ui.Picture picture, Size srcSize) async {
  const body = macosBodyRect;
  final rrect =
      RRect.fromRectAndRadius(body, const Radius.circular(macosCornerRadius));

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);

  canvas.drawRRect(
    rrect.shift(macosShadowOffset),
    Paint()
      ..color = macosShadowColor
      ..maskFilter =
          const ui.MaskFilter.blur(ui.BlurStyle.normal, macosShadowSigma),
  );

  canvas.save();
  canvas.clipRRect(rrect);
  canvas.translate(body.left, body.top);
  canvas.scale(body.width / srcSize.width, body.height / srcSize.height);
  canvas.drawPicture(picture);
  canvas.restore();

  return recorder.endRecording().toImage(masterSize, masterSize);
}

Future<void> _writeAll(
  String directory,
  Map<String, int> icons,
  ui.Image master, {
  required bool opaque,
}) async {
  final target = Directory(directory);
  expect(target.existsSync(), isTrue, reason: '找不到图标目录 $directory');

  for (final entry in icons.entries) {
    final scaled = await _resample(master, entry.value, opaque: opaque);
    final pixels = await scaled.toByteData(format: ui.ImageByteFormat.rawRgba);
    final size = entry.value;
    scaled.dispose();
    expect(pixels, isNotNull, reason: '${entry.key} 读取像素失败');
    File(p.join(directory, entry.key)).writeAsBytesSync(
      encodePng(pixels!.buffer.asUint8List(), size, size, alpha: !opaque),
    );
  }
}

// ── 一个最小的 PNG 编码器 ───────────────────────────────────────────────────
//
// `ui.Image.toByteData(format: png)` 只会输出带 alpha 的 PNG，而 `sips` 在格式往返后
// 也会把 alpha 通道加回来。两个平台的要求正好相反，所以通道数在这里显式决定：
//
//  * iOS 走 `alpha: false`，写颜色类型 2（真彩、无 alpha）。App Store 校验拒收带
//    alpha 的应用图标；本地构建不会因此报错，正是那种「不到提交那天发现不了」的问题，
//    所以在生成期就钉死。
//  * macOS 走 `alpha: true`，写颜色类型 6（真彩 + alpha）。圆角外的透明必须有 alpha
//    才存得下——这正是 macOS 这条路存在的理由。

/// 把 [rgba]（每像素 4 字节，RGBA 顺序）编码成 [width]×[height] 的 PNG。
///
/// [alpha] 为 false 时丢弃第 4 个通道、写颜色类型 2；为 true 时保留、写颜色类型 6。
Uint8List encodePng(Uint8List rgba, int width, int height,
    {required bool alpha}) {
  final channels = alpha ? 4 : 3;
  // 每条扫描线一个滤波字节（0 = None），随后是像素。画面以大片平色与长渐变为主，
  // 滤波收益很小。
  final raw = Uint8List(height * (1 + width * channels));
  var out = 0;
  for (var y = 0; y < height; y++) {
    raw[out++] = 0;
    var src = y * width * 4;
    for (var x = 0; x < width; x++) {
      raw[out++] = rgba[src];
      raw[out++] = rgba[src + 1];
      raw[out++] = rgba[src + 2];
      if (alpha) raw[out++] = rgba[src + 3];
      src += 4;
    }
  }

  final png = BytesBuilder();
  png.add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);

  final header = BytesBuilder()
    ..add(_u32(width))
    ..add(_u32(height))
    // 8 位深，颜色类型 2 或 6，deflate，自适应滤波，不隔行。
    ..add([8, alpha ? 6 : 2, 0, 0, 0]);
  _chunk(png, 'IHDR', header.toBytes());

  _chunk(png, 'IDAT', ZLibCodec(level: 9).encode(raw));
  _chunk(png, 'IEND', const []);

  return png.toBytes();
}

void _chunk(BytesBuilder out, String type, List<int> data) {
  final payload = <int>[...ascii.encode(type), ...data];
  out.add(_u32(data.length));
  out.add(payload);
  out.add(_u32(_crc32(payload)));
}

List<int> _u32(int value) => [
      (value >> 24) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 8) & 0xFF,
      value & 0xFF
    ];

final List<int> _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(List<int> bytes) {
  var c = 0xFFFFFFFF;
  for (final byte in bytes) {
    c = _crcTable[(c ^ byte) & 0xFF] ^ (c >> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

/// 把 [source] 缩放到 [size]×[size]。
///
/// [opaque] 为 true 时先铺不透明底（iOS）；为 false 时**不铺**（macOS）——
/// 铺了会把圆角外的透明填成黑，四角变成黑方块。
///
/// `FilterQuality.high` 在小尺寸上很关键：20px 那块是 51:1 的缩小，
/// 最近邻或双线性采样会把月牙整个丢掉。
Future<ui.Image> _resample(ui.Image source, int size,
    {required bool opaque}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  if (opaque) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
      Paint()..color = const Color(0xFF000000),
    );
  }
  canvas.drawImageRect(
    source,
    Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
    Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
    Paint()..filterQuality = FilterQuality.high,
  );
  return recorder.endRecording().toImage(size, size);
}
