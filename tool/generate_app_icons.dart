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
/// Two platform rules are handled here rather than left to chance:
///
///  * **No alpha.** Both platforms want an opaque icon; a transparent one is
///    rejected at App Store submission and renders as a dark square elsewhere.
///    Every tile is drawn onto an opaque canvas.
///  * **No corner radius.** The mask belongs to the OS. `assets/branding/
///    app-icon.svg` is therefore full-bleed; see the note in that file.
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

void main() {
  // The binding is needed for `Picture.toImage`. Deliberately *not* a
  // `testWidgets` body: that runs inside `FakeAsync`, where `flutter_svg`'s
  // asynchronous parse never completes and the test hangs instead of failing.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('regenerate app icons from the source SVG', () async {
    final root = Directory.current;
    final svgFile =
        File(p.join(root.path, 'assets', 'branding', 'app-icon.svg'));
    expect(svgFile.existsSync(), isTrue, reason: '找不到 ${svgFile.path}');

    final master = await _rasterise(svgFile.readAsStringSync(), masterSize);

    await _writeAll(
      p.join(
          root.path, 'ios', 'Runner', 'Assets.xcassets', 'AppIcon.appiconset'),
      iosIcons,
      master,
    );
    await _writeAll(
      p.join(root.path, 'macos', 'Runner', 'Assets.xcassets',
          'AppIcon.appiconset'),
      macosIcons,
      master,
    );

    master.dispose();
  });
}

/// Draws [svg] at [size]×[size] onto an opaque canvas.
///
/// Opaque because a decoded PNG carries whatever alpha the rasteriser produced,
/// and both platforms reject a translucent app icon.
Future<ui.Image> _rasterise(String svg, int size) async {
  final pictureInfo = await vg.loadPicture(SvgStringLoader(svg), null);
  try {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
      Paint()..color = const Color(0xFF000000),
    );
    canvas.scale(size / pictureInfo.size.width, size / pictureInfo.size.height);
    canvas.drawPicture(pictureInfo.picture);
    return await recorder.endRecording().toImage(size, size);
  } finally {
    pictureInfo.picture.dispose();
  }
}

Future<void> _writeAll(
  String directory,
  Map<String, int> icons,
  ui.Image master,
) async {
  final target = Directory(directory);
  expect(target.existsSync(), isTrue, reason: '找不到图标目录 $directory');

  for (final entry in icons.entries) {
    final scaled = await _resample(master, entry.value);
    final pixels = await scaled.toByteData(format: ui.ImageByteFormat.rawRgba);
    final size = entry.value;
    scaled.dispose();
    expect(pixels, isNotNull, reason: '${entry.key} 读取像素失败');
    File(p.join(directory, entry.key)).writeAsBytesSync(
      encodeOpaquePng(pixels!.buffer.asUint8List(), size, size),
    );
  }
}

// ── A minimal RGB PNG encoder ───────────────────────────────────────────────
//
// `ui.Image.toByteData(format: png)` always writes RGBA, and `sips` re-adds an
// alpha channel even after a round trip through a format that has none. The
// bytes are therefore assembled here, as colour type 2 (truecolour, no alpha).
//
// App Store validation rejects an app icon that carries an alpha channel. It
// would not break a local build, which is exactly the kind of thing that goes
// unnoticed until submission, so it is fixed at generation time.
Uint8List encodeOpaquePng(Uint8List rgba, int width, int height) {
  // One filter byte (0 = None) per scanline, then RGB triples. The image is
  // mostly large flat areas and long gradients, where filtering buys little.
  final raw = Uint8List(height * (1 + width * 3));
  var out = 0;
  for (var y = 0; y < height; y++) {
    raw[out++] = 0;
    var src = y * width * 4;
    for (var x = 0; x < width; x++) {
      raw[out++] = rgba[src];
      raw[out++] = rgba[src + 1];
      raw[out++] = rgba[src + 2];
      src += 4;
    }
  }

  final png = BytesBuilder();
  png.add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);

  final header = BytesBuilder()
    ..add(_u32(width))
    ..add(_u32(height))
    // 8-bit depth, colour type 2, deflate, adaptive filtering, no interlace.
    ..add(const [8, 2, 0, 0, 0]);
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

/// Resamples [source] to [size]×[size] on an opaque canvas.
///
/// `FilterQuality.high` matters at the small end: the 20px tile is a 51:1
/// reduction, and a nearest-neighbour or bilinear sample of that drops the
/// crescent entirely.
Future<ui.Image> _resample(ui.Image source, int size) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
    Paint()..color = const Color(0xFF000000),
  );
  canvas.drawImageRect(
    source,
    Rect.fromLTWH(
      0,
      0,
      source.width.toDouble(),
      source.height.toDouble(),
    ),
    Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
    Paint()..filterQuality = FilterQuality.high,
  );
  return recorder.endRecording().toImage(size, size);
}
