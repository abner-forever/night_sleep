# macOS 应用图标圆角实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 macOS 的 Dock 图标带上原生圆角与留白，与系统 app 摆在并排时不再显得「撑满」。

**Architecture:** 把 `tool/generate_app_icons.dart` 从「一份像素喂两个平台」拆成**两条渲染路径**。
iOS 沿用满幅直角 + RGB（颜色类型 2，App Store 拒收带 alpha 的图标）；macOS 新增一条：先按 Apple
图标网格算出实体矩形（1024 画布上 824×824、居中、四边留白 100、圆角半径 185.4），在它下方画投影，
再 `clipRRect` + `translate` + `scale` 把 SVG 画进去，最后用新的 RGBA（颜色类型 6）分支落盘。
回归断言放在 `test/app_icons_asset_test.dart`，直接解码**已提交的**图标产物——这样它跑在普通
`flutter test` 里，而不是只在手动重生成时才执行（规格 §9 原写「断言随生成器放 `tool/`」，
本计划把它挪到 `test/`，理由见 Task 3）。

**Tech Stack:** Dart / `dart:ui`（`PictureRecorder`、`Canvas`、`MaskFilter`）、`flutter_svg`、`flutter_test`。
**不新增任何依赖。**

**设计依据:** [规格 §8 偏差 #16](../specs/2026-09-28-night-sleep-design.md)（v2.9）、
[CHANGELOG 2.9](../../../CHANGELOG.md)

---

## Global Constraints

- 界面文案、注释、文档一律**中文**；代码标识符英文。**历史英文注释不要顺手翻译**，但本次改到
  哪一句，那一句就按事实重写——**不许留与代码不符的注释**（本次的首要动因正是一条错注释）。
- **不改 `lib/**/*.g.dart`**；本轮不碰数据库，**不需要** `build_runner`。
- **不要设 `PUB_HOSTED_URL` / `FLUTTER_STORAGE_BASE_URL`**（会把 `pubspec.lock` 的镜像地址改写成
  巨型无关 diff）。生成图标**不需要网络**。
- **不要动 `ios/Runner/Assets.xcassets/**` 的任何字节**。iOS 图标必须与开工前**逐字节相同**，
  这是本轮最重要的不回归约束（用户没要求改 iOS，且 iOS 遮罩行为本来就正确）。
- **不要引入新的 dart 包**。遮罩与投影只用 `dart:ui`。
- 生成器在 `tool/` 下、**不参与 `flutter test`**（它会改写仓库文件，测试运行不该有副作用）。
  运行方式是 `flutter test tool/generate_app_icons.dart` 或
  `dart test tool/generate_app_icons.dart`——**按仓库 README 的既有写法**。
- 每个任务结束跑 `dart format .`、`flutter analyze`、`flutter test`，**全绿才算完成**。
- **基线：本轮开工前 `flutter test` 为 233/233 通过**，`flutter analyze` 无 issue。
- **每个任务结束都要提交**（SDD 的审查包按 commit 区间生成），在 `master` 上直接提交、
  **不要 push**。提交信息用中文、`type(scope): 摘要` 格式（仓库既有风格），正文写「为什么」，
  不要逐条罗列改了什么。
- 每个任务结束把改了哪些文件、跑了什么、结果如何**如实**报回，包括没跑成的部分。

---

## 文件结构

| 文件 | 职责 | 动作 |
| --- | --- | --- |
| `test/app_icons_asset_test.dart` | **新增**。解码已提交的图标产物，断言两个平台的几何与色型 | 新建 |
| `tool/generate_app_icons.dart` | 生成器：拆成 iOS / macOS 两条渲染路径，编码器加 alpha 分支 | 修改 |
| `assets/branding/app-icon.svg` | 订正顶部那条「iOS 和 macOS 都会套遮罩」的错注释 | 改注释 |
| `macos/Runner/Assets.xcassets/AppIcon.appiconset/*.png` | 重新生成的产物 | 覆盖 |
| `docs/superpowers/specs/2026-09-28-night-sleep-design.md` | 偏差 #16 的投影参数按实测定稿；§9 状态转 ✅ 并订正断言位置 | 修改 |
| `CHANGELOG.md` | 2.9 段补上变异验证结果 | 修改 |

---

## 已核实的事实（动手前不要重新猜）

以下数字全部是**实测**的，不是估算：

**Apple 图标网格（1024 基准）**——把系统 app 的 `.icns` 抠出来量，Calculator 与 Notes 结果完全一致：

| 量 | 阈值 | 结果 |
| --- | --- | --- |
| 实体尺寸 | `alpha>128` | 206/256 = **824/1024**，四边留白**全等** |
| 圆角半径 | `alpha>128` | 取实体宽的 22.5%（0.225 × 824 = **185.4**，这是一个**比例**，不是量出来的像素值）。系统图标同法量得 44/256 = 176/1024，与本品 1024 上量得的 176 一致——这是**交叉验证**，不是 185.4 的来源（早先这里写「44/256 → 185.4」是错的：44/256 × 1024 = 176 ≠ 185.4） |
| 投影包络 | `alpha>8` | 比实体左右各外溢 4px/256、下方多 7px/256 |

**投影参数**——用同一套反推模型扫参逼近系统包络，最优组合（1024 基准）：

| 参数 | 取值 | 扫参实测包络 |
| --- | --- | --- |
| 偏移 | `Offset(0, 14)` | 本组得 `L85 T99 R85 B71` |
| 模糊 | `MaskFilter.blur(BlurStyle.normal, 10)` | 目标（系统）`L84 T96 R84 B72` |
| 颜色 | `Color(0x80000000)` | 最大偏差 3px @1024 = 画布 0.3% |

**渲染与编码路径**——一个临时 spike（已删）实跑验证过，输出经像素级测量确认：

- `ui.PictureRecorder` + `Canvas` + `clipRRect` + `translate`/`scale` + `drawPicture` 可正确产出圆角图标
- `MaskFilter.blur` 画在 `drawRRect` 上可产出投影
- 缩放用 `Canvas.drawImageRect(..., Paint()..filterQuality = FilterQuality.high)`，**不能先铺不透明底**，
  否则四角被填黑
- 解码断言可用 `ui.instantiateImageCodec` → `toByteData(format: rawRgba)`，在普通 `test()` 里可用

**两个本计划里踩过的编译错误**（照抄即可避免）：

1. `const s = masterSize.toDouble();` — `toDouble()` 不是常量表达式，用 `final`。
2. `List<num>`（混写 `10.0` 与 `0x80`）取出的元素不能直接赋给 `double` 形参，要 `.toDouble()`。

---

## Task 1：用回归断言钉住两个平台的图标几何（先红）

先写会失败的测试。此刻 `macos/.../app_icon_1024.png` 是**满幅直角、色型 2**，所以断言必然红——
这正是「改之前先看见红」的意义。

**Files:**
- Create: `test/app_icons_asset_test.dart`

**Interfaces:**
- Consumes: 无
- Produces: 无（纯断言文件）。后续任务靠它判断成败。

- [ ] **Step 1: 写失败测试**

新建 `test/app_icons_asset_test.dart`：

```dart
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
```

> **订正（终审后）**：上面 `_decode` 的注释「解码成未预乘的 RGBA 字节」与代码相反——`rawRgba`
> 是**预乘**的。本用例只读 alpha 通道，两种格式在那里等价，所以断言本身没错；但注释与事实相反
> 正是这一轮要消灭的毛病，最终实现改成了 `rawStraightRgba`，注释也跟着改成真话。

- [ ] **Step 2: 跑测试，确认它失败**

```bash
flutter test test/app_icons_asset_test.dart
```

Expected: **FAIL**。`macOS 1024 图标：圆角烘焙 + 四边留白 100` 应当在
`cornerAlpha` 上报 `Expected: a value less than <8> Actual: <255>`，
`bodyWidth` 报 `Expected: <824> Actual: <1024>`；
`macOS 图标必须带 alpha 通道（色型 6）` 报 `Expected: <6> Actual: <2>`。
**iOS 那一条此时应当已经通过**——它是防误伤的护栏，不是待修的目标。

如果 macOS 那三条**没有红**，说明断言写错了，先修断言再往下走。

- [ ] **Step 3: 提交**

```bash
git add test/app_icons_asset_test.dart
git commit -m "test(icon): 先钉住两个平台的图标几何，macOS 圆角待实现

断言直接解码已提交的 PNG，跑在普通 flutter test 里——规格原先写的
「断言随生成器放 tool/」只会在手动重生成时执行，守不住仓库状态。
此刻 macOS 三条必然红，iOS 一条已绿。"
```

---

## Task 2：生成器拆成两条渲染路径

**Files:**
- Modify: `tool/generate_app_icons.dart`
- Test: `test/app_icons_asset_test.dart`（Task 1 已建）
- 产物：`macos/Runner/Assets.xcassets/AppIcon.appiconset/*.png` 被覆盖

**Interfaces:**
- Consumes: Task 1 的测试（作为绿灯判据）
- Produces: 生成器内部的 `_rasteriseOpaque(ui.Picture, Size, int)`、
  `_rasteriseMacos(ui.Picture, Size)`、`_resample(ui.Image, int, {required bool opaque})`、
  `_writeAll(String, Map<String,int>, ui.Image, {required bool opaque})`、
  `encodePng(Uint8List, int, int, {required bool alpha})`。均为文件私有，除 `encodePng` 外不导出。

- [ ] **Step 1: 改顶部文档注释（那条错的前提就在这里）**

把 `tool/generate_app_icons.dart:18-24` 的这段：

```dart
/// Two platform rules are handled here rather than left to chance:
///
///  * **No alpha.** Both platforms want an opaque icon; a transparent one is
///    rejected at App Store submission and renders as a dark square elsewhere.
///    Every tile is drawn onto an opaque canvas.
///  * **No corner radius.** The mask belongs to the OS. `assets/branding/
///    app-icon.svg` is therefore full-bleed; see the note in that file.
```

整段换成（**中文、且按事实**）：

```dart
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
```

- [ ] **Step 2: 加几何与投影常量**

在 `const int masterSize = 1024;` 之后追加：

```dart
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
final Rect macosBodyRect = Rect.fromLTWH(
  masterSize * (1 - macosBodyFraction) / 2,
  masterSize * (1 - macosBodyFraction) / 2,
  masterSize * macosBodyFraction,
  masterSize * macosBodyFraction,
);
```

> **注意**：`masterSize * (1 - macosBodyFraction)` 是 `int * double`，结果是 `double`，
> 且除法与乘法在常量求值里都成立，`Rect.fromLTWH` 又是 const 构造器，所以整条表达式是编译期
> 常量，**这里可以是 `const`**（实现即用 `const`，Task 2 已由分析器实测确认）。
> 本计划初稿曾断言它「不能是 `const`」，那是错的——但下面那条 `const s = masterSize.toDouble();`
> 是真错：`toDouble()` 不是常量表达式。

- [ ] **Step 3: 编码器加 alpha 分支**

把 `encodeOpaquePng`（含它上面那段 `// ── A minimal RGB PNG encoder ──` 说明）整体换成：

```dart
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
```

`_chunk` / `_u32` / `_crcTable` / `_crc32` **原样保留**，不动。

- [ ] **Step 4: 拆渲染与写盘**

把 `main()`、`_rasterise`、`_writeAll`、`_resample` 换成下面这组（`_chunk` 之后的编码器辅助
函数不动）：

```dart
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
      final iosMaster =
          await _rasteriseOpaque(pictureInfo.picture, pictureInfo.size, masterSize);
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
  final body = macosBodyRect;
  final rrect =
      RRect.fromRectAndRadius(body, const Radius.circular(macosCornerRadius));

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);

  canvas.drawRRect(
    rrect.shift(macosShadowOffset),
    Paint()
      ..color = macosShadowColor
      ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, macosShadowSigma),
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
```

> **`_rasterise` 的旧签名是 `(String svg, int size)`，自己 `vg.loadPicture`。** 新结构在 `main()`
> 里只解析一次矢量，所以 `_rasteriseOpaque` 收的是 `ui.Picture` + `Size`。`import 'package:flutter_svg/flutter_svg.dart';`
> 与 `dart:ui as ui` 都已在文件顶部，不需要新增 import。

> **订正（终审后）**：上面 `_writeAll` 片段里的 `rawRgba` 是**错的**——它是**预乘** alpha，而 PNG
> 色型 6 规范要求**直乘**；写进去后渲染时 alpha 被乘第二次，所有半透明像素（烘焙的圆角轮廓、
> 投影软边）都变暗，alpha 越低越暗。最终实现改成了 `rawStraightRgba`（iOS 那条路整幅 alpha=255，
> 两种格式在那里等价），并给 `asUint8List()` 补上了 offset/length。

- [ ] **Step 5: 重生成产物**

```bash
flutter test tool/generate_app_icons.dart
```

Expected: `All tests passed!`，且 `git status` 显示 macOS 那 7 个 PNG 被修改。

- [ ] **Step 6: 确认 iOS 逐字节未变（最重要的不回归检查）**

```bash
git status --short ios/
```

Expected: **空输出**。只要有任何一个 iOS 文件出现在这里，就停下——说明 iOS 那条路径被改动了，
回去查 `_rasteriseOpaque` 与 `opaque: true` 是否真的还在用。

- [ ] **Step 7: 跑 Task 1 的测试，确认转绿**

```bash
flutter test test/app_icons_asset_test.dart
```

Expected: `All tests passed!`（4 条）。

- [ ] **Step 8: 变异验证——把遮罩摘掉，必须变红**

临时把 `_rasteriseMacos` 里的 `canvas.clipRRect(rrect);` 一行注释掉，然后：

```bash
flutter test tool/generate_app_icons.dart && flutter test test/app_icons_asset_test.dart
```

Expected: 第二条**必须红**（`cornerAlpha` 变回 255、`bodyWidth` 变回 1024）。
如果它仍是绿的，说明断言没有真正吃到遮罩，**先修断言**。

> **订正（终审后）**：上面那句对变异后表现的预测是**错的**。摘掉 `clipRRect` 后 `bodyWidth`
> **仍是 824**——实体是被 `translate`/`scale` 内缩到 824×824 的，clip 只削四角、不改变包围盒；
> 真正会动的只有实体**自身四角**的 alpha（由 0 变实心）。`CHANGELOG` 已按实际写，这里把坏预测
> 一并订正。此外该变异在 16px 上**逐字节无差别**（实体在这个尺寸已被重采样糊平），只有
> 32/64/128/256/512/1024 六个尺寸会变，所以「清理干净」不能靠 `app_icon_16.png` 的哈希。

验证完**恢复 `clipRRect` 那一行、重新生成产物**：

```bash
flutter test tool/generate_app_icons.dart
git status --short   # 应只剩 macos/ 的 7 个 PNG 与 tool/generate_app_icons.dart
```

- [ ] **Step 9: 全量校验**

```bash
dart format . && flutter analyze && flutter test
```

Expected: 格式化无改动（或只有本次改的文件）、analyze 无 issue、**237/237 通过**
（基线 233 + Task 1 的 4 条）。

- [ ] **Step 10: 提交**

```bash
git add tool/generate_app_icons.dart macos/Runner/Assets.xcassets test/app_icons_asset_test.dart
git commit -m "fix(icon): macOS 图标按 Apple 网格烘焙圆角与留白

两条渲染路径分开：iOS 仍是满幅直角 + 色型 2（App Store 拒收带 alpha
的图标），macOS 改为实体 824/1024、半径 185.4、四边留白 100，加投影
并保留 alpha（色型 6）——因为 macOS 不套遮罩，圆角得自己画。

几何与投影参数实测自系统 app 的 .icns（Calculator / Notes 的实体同为
206/256 = 824/1024）。iOS 产物逐字节未变。

「不套遮罩」这条此前写在 SVG 注释与偏差 #16 里且是反的，一并订正。"
```

---

## Task 3：同步文档，并做一次真机目视复核

**Files:**
- Modify: `assets/branding/app-icon.svg`（顶部注释）
- Modify: `docs/superpowers/specs/2026-09-28-night-sleep-design.md`（偏差 #16、§9）
- Modify: `CHANGELOG.md`（2.9 段）

**Interfaces:**
- Consumes: Task 2 的实测结果与变异验证结论
- Produces: 无

- [ ] **Step 1: 订正 SVG 里的错注释**

`assets/branding/app-icon.svg` 第 15–20 行现在是：

```xml
  <!--
    Full-bleed square. The delivered icon carries rx="236" on this rect for use
    as a web favicon and apple-touch-icon; that radius is removed here because
    iOS and macOS apply their own mask to an app icon, and a pre-rounded icon
    ends up with rounded corners inside a rounded mask.
  -->
```

换成（中文、按事实、并说明为什么现在两个平台分开了）：

```xml
  <!--
    满幅直角。交付的原图在 rect 上带 rx="236"，是给 web favicon 与
    apple-touch-icon 用的；这里去掉它是因为 **iOS** 会给应用图标套遮罩，
    预先倒过角的图标会变成「圆角套圆角」。

    注意 macOS **不套遮罩**——它的圆角是烘焙在图标文件里的。所以 macOS 那套
    不是直接用这份满幅图，而是由 tool/generate_app_icons.dart 按 Apple 图标网格
    重新裁出圆角与留白。历史注释把两个平台混为一谈，导致 macOS 的 Dock 图标
    被撑成方块，别再改回去。
  -->
```

- [ ] **Step 2: 把偏差 #16 的投影参数换成实测值**

规格里这一句现在是估算：

> 加一层向下偏移的投影（1024 基准：偏移 (0, 12)、模糊 σ≈8——由系统图标的 `alpha>8` 包络反推，属估算，实现时对照系统图标复核）

换成实测定稿：

> 加一层向下偏移的投影（1024 基准：偏移 `(0, 14)`、模糊 σ=10、颜色 `0x80000000`——由系统图标的 `alpha>8` 包络反推后扫参逼近，目标包络 `L84 T96 R84 B72`，本组得 `L85 T99 R85 B71`）

- [ ] **Step 3: 订正 §9 的断言位置与状态**

§9 里那一行现在写着「待实现（断言随生成器放 `tool/generate_app_icons.dart`，并做变异验证：
去掉遮罩必红）」。两处都要改：**位置**和**状态**。

「断言随生成器放 `tool/`」是错的——生成器不参与 `flutter test`，放那儿等于只在手动重生成时
才执行，守不住仓库状态。改成：

```
| 单元测试 | 应用图标几何（分平台）：macOS 图标角像素**透明**、中心**不透明**、`alpha>128` 的实体包围盒 = 824×824 且四边留白各 100；iOS 图标仍是 1024 满幅**且 PNG 无 alpha 通道**（色型 2，防误伤） | ✅ `test/app_icons_asset_test.dart`（4 条，跑在普通 `flutter test` 里；含变异验证：摘掉 `clipRRect` 必红） |
```

- [ ] **Step 4: 补 CHANGELOG 的验证结果**

2.9 段末尾的回归方法那句之后，补一段（**只写实际发生的事**）：

```
**已验证（2026-09-29）**：`test/app_icons_asset_test.dart` 4 条全绿，跑在普通
`flutter test` 里（规格原写「断言随生成器放 `tool/`」——生成器不参与 `flutter test`，
那样只在手动重生成时才执行，已改为独立的资产断言）。变异验证：注释掉
`_rasteriseMacos` 的 `clipRRect` 后重新生成，`cornerAlpha` 与 `bodyWidth` 两条立刻变红。
iOS 产物经 `git status --short ios/` 确认**逐字节未变**。
```

如果 Task 2 的变异验证结果与上面写得不一样，**按实际结果改写这段**，不要照抄。

- [ ] **Step 5: 重建 macOS 产物并做目视复核**

```bash
flutter build macos --debug
```

然后**退出并重新启动** `night_sleep.app`（运行中的实例不会中途更换 Dock 图标），看 Dock：

- 图标应当是**圆角方块**、四角有留白，和旁边的系统 app 并排不突兀
- 若是**直角**，说明产物没被重建——先确认 `build/macos/Build/Products/Debug/night_sleep.app/Contents/Resources/AppIcon.icns`
  的时间戳是刚才的

Dock 图标缓存可能仍显示旧图。必要时按 CHANGELOG 2.9 记的顺序清一遍：注销 LaunchServices
里的旧注册、删 `com.apple.iconservices` 缓存、重新登记、`killall Dock`。

> 这一步**必须人眼看**，断言只能保证文件的几何正确，保证不了 Dock 画出来的样子。
> 结果如实记进 README 的验证记录。

- [ ] **Step 6: 更新 README 的验证记录**

README「实现范围 / 验证记录」一节补一行：macOS Dock 图标已于 2026-09-29 目视确认圆角与留白
（附是否一次通过、或用了几次清缓存）。

> **订正（终审后）**：README **没有**记「已目视确认」，记的是**未验证**——实现者看不到屏幕，
> 断言只能保证文件的几何正确，保证不了 Dock 实际画出来的样子。这是对的：不得声称看过 Dock。
> 上面那句「补一行：已目视确认」作废，以 README 的实际记录为准。

- [ ] **Step 7: 全量校验并提交**

```bash
dart format . && flutter analyze && flutter test
```

Expected: 全绿（237/237）。

```bash
git add -A
git commit -m "docs(icon): 同步 v2.9 的实测投影参数、断言位置与验证结果

偏差 #16 的投影从估算值换成扫参实测值；§9 把断言位置从生成器改到
test/app_icons_asset_test.dart 并转 ✅；SVG 顶部那条「iOS 和 macOS 都会
套遮罩」的错注释订正——它是本次问题的源头。"
```

---

## 收尾

三个任务做完后：

- `git log --oneline -4` 应看到 Task 1/2/3 三次提交
- `flutter test` 237/237、`flutter analyze` 无 issue
- **不要 push**，等主会话决定
