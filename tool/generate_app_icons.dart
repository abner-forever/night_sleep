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
import 'dart:math' as math;
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

/// Android **传统**启动图标（API < 26 用）的五个密度：文件名 → 像素边长。
///
/// 与 iOS 同一条渲染路径（满幅直角、不透明）。API < 26 的启动器**不套遮罩**，
/// 所以这里也不倒角——倒了就是「方角套圆角」的又一个版本。
const Map<String, int> androidLegacyIcons = {
  'mipmap-mdpi/ic_launcher.png': 48,
  'mipmap-hdpi/ic_launcher.png': 72,
  'mipmap-xhdpi/ic_launcher.png': 96,
  'mipmap-xxhdpi/ic_launcher.png': 144,
  'mipmap-xxxhdpi/ic_launcher.png': 192,
};

/// Android **自适应**图标（API 26+）两层各自的分辨率：密度目录 → 画布边长。
///
/// **画布是 108dp，不是 48dp**——系统会把 108dp 裁到中央 72dp（遮罩形状由启动器定：
/// 圆形、方圆形、圆角方形…），所以两层都按 108dp 出图，多出来的边是留给裁切的。
const Map<String, int> androidAdaptiveLayers = {
  'mipmap-mdpi': 108,
  'mipmap-hdpi': 162,
  'mipmap-xhdpi': 216,
  'mipmap-xxhdpi': 324,
  'mipmap-xxxhdpi': 432,
};

/// 自适应图标前景里「可见区」占画布的比例：72/108。
///
/// 108dp 是画布，系统把它裁到中央 72dp。这 72dp 就是缩放的目标尺寸，
/// 但**怎么缩**另有一条规则，见 [_rasteriseAdaptiveForeground]。
const double androidAdaptiveVisibleFraction = 72 / 108;

/// 源 SVG 里那句满幅渐变底，**逐字**抄下来。
///
/// Android 的自适应图标要把它与主体拆成两层（底铺满 108dp、主体缩进中央 72dp），
/// 所以这里必须能把它单独认出来。认不出来时**报错退出**，而不是产出一个错图标：
/// 源图改了而这里没跟着改，是本文件唯一会静默出错的路径。
const String _svgBackgroundRect =
    '<rect width="1024" height="1024" fill="url(#night)"/>';

/// 自适应图标的声明文件，写进 `mipmap-anydpi-v26/ic_launcher.xml`。
///
/// 同一个资源名 `ic_launcher` 在两处存在：`mipmap-*/ic_launcher.png`（传统位图，
/// 给 API < 26）与 `mipmap-anydpi-v26/ic_launcher.xml`（自适应，给 API ≥ 26）。
/// 系统按版本自己挑，清单里的 `android:icon="@mipmap/ic_launcher"` 一个字都不用改。
const String androidAdaptiveXml = '''
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
''';

/// Side of the canvas the SVG is rasterised onto before any downscaling.
const int masterSize = 1024;

/// macOS 图标的 Apple 网格：1024 画布上实体占 824×824 居中。
///
/// 实体比例与四边留白**实测自系统 app 的 `.icns`**（Calculator / Notes 结果一致）：
/// `alpha>128` 的实体恰为 206/256 = 824/1024，四边留白全等。
const double macosBodyFraction = 824 / 1024;

/// 圆角半径 = 实体宽的 22.5%（0.225 × 824 = 185.4），这是**比例**来源，不是量出来的
/// 像素值——早先的注释写「半径量得 44/256」，但 44/256 × 1024 = 176，与 185.4 对不上，
/// 那句话是错的。
///
/// 系统图标只作**交叉验证**：同一套量法（顶行 `alpha>128` 收敛量）下系统图标量得
/// 44/256，本图标量得 176/1024 = 44×(1024/256)，两者一致，说明比例选得对。
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

    // 矢量解析成三份，各画各的：
    //  * 整幅——iOS、macOS、Android 传统位图；
    //  * 只有主体（月亮与两道声波）——Android 自适应图标的**前景**；
    //  * 只有渐变底——Android 自适应图标的**背景**。
    // 后两份是同一个源图切出来的，切法见 `_withoutBackground` / `_backgroundOnly`。
    final svgSource = svgFile.readAsStringSync();
    final pictureInfo = await vg.loadPicture(SvgStringLoader(svgSource), null);
    final foregroundInfo = await vg.loadPicture(
        SvgStringLoader(_withoutBackground(svgSource)), null);
    final backgroundInfo =
        await vg.loadPicture(SvgStringLoader(_backgroundOnly(svgSource)), null);
    try {
      // 三份的 viewBox 相同，尺寸必须一致；不一致说明切图切坏了。
      expect(foregroundInfo.size, pictureInfo.size,
          reason: '前景的 viewBox 与整幅不一致，切图出错了');
      expect(backgroundInfo.size, pictureInfo.size,
          reason: '背景的 viewBox 与整幅不一致，切图出错了');

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

      await _writeAndroidIcons(
        resDir: Directory(
            p.join(root.path, 'android', 'app', 'src', 'main', 'res')),
        full: pictureInfo.picture,
        foreground: foregroundInfo.picture,
        background: backgroundInfo.picture,
        srcSize: pictureInfo.size,
      );
    } finally {
      pictureInfo.picture.dispose();
      foregroundInfo.picture.dispose();
      backgroundInfo.picture.dispose();
    }
  });
}

/// 源 SVG 去掉那句满幅渐变底，只剩主体（月亮 + 两道声波）。
///
/// 认不出那句话就**直接失败**——见 [_svgBackgroundRect] 的注释。
String _withoutBackground(String svg) {
  if (!svg.contains(_svgBackgroundRect)) {
    fail('源 SVG 变了：找不到那句满幅渐变底 `$_svgBackgroundRect`。\n'
        'Android 的自适应图标靠把它与主体拆成两层，找不到就必须先修这个工具，\n'
        '不能让它悄悄产出一个主体与底重叠的错图标。');
  }
  return svg.replaceFirst(_svgBackgroundRect, '');
}

/// 源 SVG 只保留那句满幅渐变底（与 `<defs>` 里的渐变定义），去掉主体。
///
/// 背景层必须是**纯底**：如果连主体一起画上去，前景又画一遍缩小的主体，
/// 同一个月亮会出现大小两个，边缘还有一圈鬼影。
String _backgroundOnly(String svg) {
  // 不用正则：这里只要**第一对** `<defs>` 标签之间的内容，indexOf/substring 足够了，
  // 而且读的人不必在脑子里跑一遍 `[\s\S]*?` 的懒惰匹配。
  const open = '<defs>';
  const close = '</defs>';
  final start = svg.indexOf(open);
  final end = svg.indexOf(close);
  if (start < 0 || end < 0 || end < start) {
    fail('源 SVG 变了：找不到 <defs>。渐变的定义在那里，背景层就画不出颜色。');
  }
  final defs = svg.substring(start, end + close.length);
  return '<svg xmlns="http://www.w3.org/2000/svg" '
      'viewBox="0 0 1024 1024">$defs$_svgBackgroundRect</svg>';
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
    await _writeOne(target, entry.key, entry.value, master, opaque: opaque);
  }
}

/// 从 [master] 下采一张 [size]×[size] 的 PNG，写到 [resDir] 下的 [relativePath]。
///
/// [relativePath] 可以带目录（Android 按密度分目录），父目录不存在就建。
Future<void> _writeOne(
  Directory resDir,
  String relativePath,
  int size,
  ui.Image master, {
  required bool opaque,
}) async {
  final file = File(p.joinAll([resDir.path, ...p.split(relativePath)]));
  file.parent.createSync(recursive: true);

  final scaled = await _resample(master, size, opaque: opaque);
  // 必须取**直乘** alpha 的字节：PNG 色型 6 的规定如此。`rawRgba` 是**预乘**的
  // （SDK 文档与实测均如此），写进色型 6 后渲染时 alpha 会被乘第二次——每个半透明
  // 像素（烘焙的圆角轮廓、投影软边）都变暗，alpha 越低越暗（50% 处约暗一半）。
  // iOS 那条路整幅 alpha=255，两种格式在那里等价，所以三个平台共用这一行。
  final pixels =
      await scaled.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
  scaled.dispose();
  expect(pixels, isNotNull, reason: '$relativePath 读取像素失败');

  file.writeAsBytesSync(
    // 显式带上 offset/length：`asUint8List()` 不带参数时从 ByteData 的**缓冲区**起点读，
    // 引擎把像素放进带偏移的视图里时会多读到前面的字节。
    encodePng(
      pixels!.buffer.asUint8List(pixels.offsetInBytes, pixels.lengthInBytes),
      size,
      size,
      alpha: !opaque,
    ),
  );
}

/// Android 的两套启动图标：传统位图（API < 26）+ 自适应图标（API ≥ 26）。
///
/// 两套共用**同一个资源名** `ic_launcher`，靠资源限定符区分（`mipmap-*/ic_launcher.png`
/// 与 `mipmap-anydpi-v26/ic_launcher.xml`），所以清单里的 `android:icon` 一个字都不用改。
Future<void> _writeAndroidIcons({
  required Directory resDir,
  required ui.Picture full,
  required ui.Picture foreground,
  required ui.Picture background,
  required Size srcSize,
}) async {
  expect(resDir.existsSync(), isTrue,
      reason: '找不到 Android 资源目录 ${resDir.path}');

  // 传统位图：满幅直角、不透明，与 iOS 同一条路。
  final legacyMaster = await _rasteriseOpaque(full, srcSize, masterSize);
  for (final entry in androidLegacyIcons.entries) {
    await _writeOne(resDir, entry.key, entry.value, legacyMaster, opaque: true);
  }
  legacyMaster.dispose();

  // 自适应图标的两层。母版都栅格到 1024——**它不是 108dp 的整数倍**（1024×72/108
  // = 682.67）也无所谓：下采时引擎会重采样，边缘的软硬由最终尺寸决定。
  final ink = await _inkBounds(foreground, srcSize);
  final fgMaster = await _rasteriseAdaptiveForeground(foreground, srcSize, ink);
  final bgMaster = await _rasteriseOpaque(background, srcSize, masterSize);
  for (final entry in androidAdaptiveLayers.entries) {
    await _writeOne(resDir, '${entry.key}/ic_launcher_foreground.png',
        entry.value, fgMaster,
        opaque: false);
    await _writeOne(resDir, '${entry.key}/ic_launcher_background.png',
        entry.value, bgMaster,
        opaque: true);
  }
  fgMaster.dispose();
  bgMaster.dispose();

  final anydpi = Directory(p.join(resDir.path, 'mipmap-anydpi-v26'));
  anydpi.createSync(recursive: true);
  File(p.join(anydpi.path, 'ic_launcher.xml'))
      .writeAsStringSync(androidAdaptiveXml);
}

/// 量出 [picture] 的**墨迹包围盒**（alpha > 8 的范围），单位与 [srcSize] 一致。
///
/// 不去信源图的构图是居中的：实测 `app-icon.svg` 的墨迹在 1024 画布里是
/// x∈[356,928]、y∈[212,956]，中心 (642,584)——**比画布中心偏右下 130/72**。
/// 那是给满幅方图（iOS / macOS）做的构图，直接套进自适应图标的圆形遮罩里会明显偏，
/// 第二道声波的尾端还会顶到遮罩边缘。
Future<Rect> _inkBounds(ui.Picture picture, Size srcSize) async {
  final width = srcSize.width.ceil();
  final height = srcSize.height.ceil();

  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawPicture(picture);
  final image = await recorder.endRecording().toImage(width, height);
  final data =
      await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
  image.dispose();
  expect(data, isNotNull, reason: '量墨迹时读像素失败');
  final rgba = data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

  var minX = width, minY = height, maxX = -1, maxY = -1;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      // 阈值 8 与测试里量 macOS 留白用的是同一个：抗锯齿的极淡边缘不算墨迹，
      // 否则包围盒会被一圈几乎看不见的像素撑开。
      if (rgba[(y * width + x) * 4 + 3] > 8) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  if (maxX < 0) fail('前景是空的：源图切掉背景之后一点墨迹都不剩。');
  return Rect.fromLTRB(
      minX.toDouble(), minY.toDouble(), maxX + 1.0, maxY + 1.0);
}

/// 把 [picture]（只有主体的那份）缩进 108dp 画布的中央 72dp，
/// **按墨迹 [ink] 的外接圆定标，并把墨迹中心对到画布中心**，四周留透明。
///
/// **为什么按外接圆定标，而不是按「1024 → 72dp」的固定比例**：源图的墨迹几乎铺满
/// 整个 1024 画布，按固定比例缩进来，外接圆是 691.5 > 可见区 682.7——圆形遮罩会把
/// 第二道声波的尾端切掉。按外接圆定标则是「在遮罩允许的范围内尽可能大」，
/// 结果是只比 iOS 那张满幅图的构图小 1.3%，肉眼看不出来，而且**再换构图也不会被切**。
/// （这条规则是被那次断言失败逼出来的，不是一开始就想清楚的。）
///
/// 透明是必须的：这层叠在背景层之上，四周的透明正是让渐变底透出来的地方。
/// 铺了底会把四周填成黑，圆形遮罩外出现一个黑方框。
Future<ui.Image> _rasteriseAdaptiveForeground(
    ui.Picture picture, Size srcSize, Rect ink) async {
  const visible = masterSize * androidAdaptiveVisibleFraction;
  final diagonal = math.sqrt(ink.width * ink.width + ink.height * ink.height);
  final scale = visible / diagonal;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  // 先 translate 再 scale：变换复合后，源图坐标 (x,y) 落到
  // (tx + x·scale, ty + y·scale)，把 tx/ty 解出来就是下面两行。
  canvas.translate(
    masterSize / 2 - ink.center.dx * scale,
    masterSize / 2 - ink.center.dy * scale,
  );
  canvas.scale(scale, scale);
  canvas.drawPicture(picture);
  return recorder.endRecording().toImage(masterSize, masterSize);
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
//
// 色型 6 存的是**直乘**（非关联）alpha，所以调用方传进来的 RGBA 也必须是直乘的
// （见 `_writeAll` 用 `rawStraightRgba` 而非 `rawRgba` 的理由）。

/// 把 [rgba]（每像素 4 字节、RGBA 顺序、**直乘** alpha）编码成 [width]×[height] 的 PNG。
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
