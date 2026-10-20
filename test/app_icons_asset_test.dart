/// 校验 iOS / Android 已提交图标的尺寸、几何与透明通道。
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

const String _iosDir = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';

const String _ios1024 = '$_iosDir/Icon-App-1024x1024@1x.png';

void main() {
  // 用普通 test() 而非 testWidgets：FakeAsync 下引擎的异步解码不保证完成。
  TestWidgetsFlutterBinding.ensureInitialized();

  test('iOS 图标：满幅直角且无 alpha 通道（色型 2）', () async {
    final bytes = File(_ios1024).readAsBytesSync();
    expect(_colourType(bytes), 2, reason: 'App Store 拒收带 alpha 的应用图标');

    final decoded = await _decode(bytes, _ios1024);
    final img = _Geometry.of(decoded.rgba, decoded.width);
    expect(img.cornerAlpha, 255, reason: 'iOS 由系统套遮罩，文件本身必须满幅不透明');
    expect(img.bodyWidth, 1024);
    expect(img.padLeft, 0);
  });

  // ── Android ───────────────────────────────────────────────────────────────
  //
  // 自适应图标（API 26+）是**两层**：底铺满 108dp 画布、主体缩进中央 72dp，
  // 系统自己套遮罩（圆形 / 方圆形 / 圆角方形，由启动器决定）。下面这组钉的正是两处
  // 「产物看着有图、装到手机上才发现不对」的地方——**主体被遮罩切掉**、
  // **主体混进了底**。两者都不可能靠看文件名或尺寸发现。

  test('Android 传统位图：五档尺寸、满幅直角、无 alpha（色型 2）', () async {
    for (final entry in _androidLegacyDensities.entries) {
      final path = '$_androidRes/${entry.key}/ic_launcher.png';
      final bytes = File(path).readAsBytesSync();
      expect(_colourType(bytes), 2,
          reason: '$path 不该带 alpha：API < 26 的启动器不套遮罩，满幅不透明才对');

      final decoded = await _decode(bytes, path);
      expect(decoded.width, entry.value, reason: '$path 的边长应为 ${entry.value}');
      expect(decoded.height, entry.value);

      final img = _Geometry.of(decoded.rgba, decoded.width);
      expect(img.cornerAlpha, 255, reason: '$path 四角必须实心——它是满幅直角，倒角由系统决定');
      expect(img.padLeft, 0, reason: '$path 不该有留白');
      expect(img.padTop, 0);
    }
  });

  test('Android 自适应图标：声明文件指向两层，两层在每个密度都在', () async {
    const xmlPath = '$_androidRes/mipmap-anydpi-v26/ic_launcher.xml';
    final xml = File(xmlPath).readAsStringSync();
    // 资源名必须仍叫 `ic_launcher`（与 `mipmap-*/ic_launcher.png` 同名，靠限定符区分），
    // 改名就得同步改清单里的 `android:icon`。
    expect(xml, contains('@mipmap/ic_launcher_background'),
        reason: '$xmlPath 没指向背景层');
    expect(xml, contains('@mipmap/ic_launcher_foreground'),
        reason: '$xmlPath 没指向前景层');

    for (final entry in _androidAdaptiveDensities.entries) {
      for (final layer in const ['background', 'foreground']) {
        final path = '$_androidRes/${entry.key}/ic_launcher_$layer.png';
        expect(File(path).existsSync(), isTrue, reason: '缺 $path');
        final decoded = await _decode(File(path).readAsBytesSync(), path);
        expect(decoded.width, entry.value,
            reason: '$path 的画布应为 ${entry.value}（108dp，不是 48dp）');
        expect(decoded.height, entry.value);
      }
    }
  });

  test('Android 自适应前景：墨迹全部落在中央 72dp 圆内，且居中', () async {
    for (final entry in _androidAdaptiveDensities.entries) {
      final path = '$_androidRes/${entry.key}/ic_launcher_foreground.png';
      final bytes = File(path).readAsBytesSync();
      expect(_colourType(bytes), 6,
          reason: '$path 必须带 alpha——可见圆之外的部分要透明，才能透出背景层');

      final decoded = await _decode(bytes, path);
      final size = decoded.width;

      // 可见区是画布中央的 72/108；圆形遮罩下它就是一个直径 72dp 的圆。
      final radius = size * 72 / 108 / 2;
      final farthest = _farthestInkFromCentre(decoded.rgba, size);
      expect(farthest, lessThanOrEqualTo(radius),
          reason: '$path 有墨迹落在可见圆之外（最远 ${farthest.toStringAsFixed(1)} > '
              '半径 ${radius.toStringAsFixed(1)}）：圆形遮罩会把它切掉。'
              '实测 xxxhdpi 最远 115.7、半径 144。');

      final img = _Geometry.of(decoded.rgba, size);
      // 反向护栏：否则「主体整个画没了」也能让上面那条通过。
      expect(img.bodyWidth, greaterThan(size * 0.30),
          reason: '$path 的前景太小或整个是空的');
      expect(img.bodyWidth, lessThan(size * 0.60),
          reason: '$path 的前景撑满了画布，圆形遮罩一定会切到它');

      // **居中**这条单独钉住：源图是为 iOS 满幅方图构的，墨迹本身就不在
      // 画布中心（1024 单位里中心在 (642,584)，偏右下 130/72）。少了重新居中这一步，
      // 上面那条圆内断言也会红——但这条的失败信息直接指向原因。
      final centreTolerance = size * 0.02;
      expect(
          (img.left + img.right) / 2, closeTo((size - 1) / 2, centreTolerance),
          reason: '$path 的前景没有水平居中');
      expect(
          (img.top + img.bottom) / 2, closeTo((size - 1) / 2, centreTolerance),
          reason: '$path 的前景没有垂直居中');
    }
  });

  test('Android 自适应背景：纯渐变底，主体不许混进来', () async {
    for (final entry in _androidAdaptiveDensities.entries) {
      final path = '$_androidRes/${entry.key}/ic_launcher_background.png';
      final bytes = File(path).readAsBytesSync();
      expect(_colourType(bytes), 2, reason: '$path 是铺满画布的底，被前景盖住，不需要 alpha');

      final decoded = await _decode(bytes, path);
      // 渐变底的三个色标是 #75D8FF / #397BEA / #3F3CC6，**没有一个是近白的**，
      // 而月亮是 #FCFEFF。所以「近白像素数为 0」就是「主体没混进这一层」。
      // 实测同一口径下传统位图有 227~3602 个近白像素（月亮在那里），背景层是 0。
      expect(_nearWhiteCount(decoded.rgba, decoded.width), 0,
          reason: '$path 里出现了近白像素——主体混进了背景层，叠上前景会看到'
              '一大一小两个月亮，边缘还有一圈鬼影');
    }
  });
}

/// 各密度目录 → 自适应图标的画布边长（**108dp**，不是 48dp）。
///
/// 与生成器的 `androidAdaptiveLayers` 是同一份约定，故意**各写一遍**：这一组用例要钉的
/// 正是「文件名与真实像素尺寸绑定」这件事，从生成器 import 过来就等于共用同一个可能
/// 出错的定义，绑定被写错时两边一起错、用例照样绿。
const Map<String, int> _androidAdaptiveDensities = {
  'mipmap-mdpi': 108,
  'mipmap-hdpi': 162,
  'mipmap-xhdpi': 216,
  'mipmap-xxhdpi': 324,
  'mipmap-xxxhdpi': 432,
};

/// 各密度目录 → 传统位图的边长（48dp 一套，给 API < 26）。
const Map<String, int> _androidLegacyDensities = {
  'mipmap-mdpi': 48,
  'mipmap-hdpi': 72,
  'mipmap-xhdpi': 96,
  'mipmap-xxhdpi': 144,
  'mipmap-xxxhdpi': 192,
};

const String _androidRes = 'android/app/src/main/res';

/// [rgba] 里 alpha > 8 的像素中，离画布中心最远的那个的距离。
///
/// 阈值 8 与生成器量墨迹（`_inkBounds`）用的是同一个：抗锯齿的极淡边缘不算墨迹，
/// 否则最远距离会被一圈几乎看不见的像素撑开，这条断言就变得没有意义。
double _farthestInkFromCentre(Uint8List rgba, int size) {
  final centre = size / 2;
  var farthest = 0.0;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      if (rgba[(y * size + x) * 4 + 3] > 8) {
        final dx = x + 0.5 - centre;
        final dy = y + 0.5 - centre;
        final distance = math.sqrt(dx * dx + dy * dy);
        if (distance > farthest) farthest = distance;
      }
    }
  }
  return farthest;
}

/// 三个通道都 > 200 的像素个数，即「近白」。
///
/// 用来判定主体（月亮 #FCFEFF）在不在某一层里——渐变底的三个色标都不近白。
int _nearWhiteCount(Uint8List rgba, int size) {
  var count = 0;
  for (var i = 0; i < size * size; i++) {
    if (rgba[i * 4] > 200 && rgba[i * 4 + 1] > 200 && rgba[i * 4 + 2] > 200) {
      count++;
    }
  }
  return count;
}

/// PNG 的 IHDR 里，颜色类型在第 25 个字节（8 签名 + 4 长度 + 4 `IHDR` + 4 宽 + 4 高 + 1 位深）。
int _colourType(Uint8List png) => png[25];

/// 解码一张 PNG，返回**直乘**（非关联）alpha 的 RGBA 字节与像素尺寸。
///
/// 取 `rawStraightRgba` 而非 `rawRgba`：后者是**预乘** alpha（SDK 文档明写，实测也如此）。
/// 本组用例只读 alpha 通道，两种格式在那里等价；但生成器写色型 6 时必须给直乘字节
/// （`rawRgba` 会让半透明像素变暗），测试与产物走同一格式，注释才对得上实物。
Future<({Uint8List rgba, int width, int height})> _decode(
    Uint8List bytes, String path) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final data =
      await frame.image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
  final width = frame.image.width;
  final height = frame.image.height;
  frame.image.dispose();
  codec.dispose();
  expect(data, isNotNull, reason: '$path 解码失败');
  return (
    rgba: data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    width: width,
    height: height,
  );
}

/// 按 `alpha > 128` 量实体（与量系统图标时同一口径，投影的软边因此不参与）。
///
/// 它同时持有解码后的 RGBA，因为上面那组包围盒数字**钉不住圆角**：实体是被
/// `translate`/`scale` 内缩到 824×824 的，画布角 `(0,0)` 量到的其实是留白；而
/// 包围盒由最宽的那一行决定，圆角削掉的是四角、不改变包围盒。要区分「有圆角 /
/// 无圆角」必须能点到实体**自己**的角，所以这里给出按坐标取的 `alphaAt`。
class _Geometry {
  const _Geometry(
      this._rgba, this.size, this.left, this.top, this.right, this.bottom);

  final Uint8List _rgba;
  final int size;
  final int left, top, right, bottom;

  int get bodyWidth => right - left + 1;
  int get bodyHeight => bottom - top + 1;
  int get padLeft => left;
  int get padTop => top;
  int get padRight => size - 1 - right;
  int get padBottom => size - 1 - bottom;

  /// 画布左上角、画布正中的 alpha。
  int get cornerAlpha => alphaAt(0, 0);
  int get centreAlpha => alphaAt(size ~/ 2, size ~/ 2);

  /// (x, y) 处的 alpha。与量包围盒走同一份 RGBA、同一套坐标，口径一致。
  int alphaAt(int x, int y) => _alphaAt(_rgba, size, x, y);

  static int _alphaAt(Uint8List rgba, int size, int x, int y) =>
      rgba[(y * size + x) * 4 + 3];

  static _Geometry of(Uint8List rgba, int size) {
    var left = size, right = -1, top = size, bottom = -1;
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        if (_alphaAt(rgba, size, x, y) > 128) {
          if (x < left) left = x;
          if (x > right) right = x;
          if (y < top) top = y;
          if (y > bottom) bottom = y;
        }
      }
    }
    return _Geometry(rgba, size, left, top, right, bottom);
  }
}
