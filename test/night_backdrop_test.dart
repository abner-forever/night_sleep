import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/features/session/presentation/night_scene.dart';
import 'package:night_sleep/features/session/presentation/widgets/night_backdrop.dart';

/// 逐边比矩形，带一点容差（期望值是用十进制字面量写的，避免二进制小数末位较劲）。
void expectRect(Rect actual, Rect expected, {String? label}) {
  final name = label ?? '矩形';
  expect(actual.left, moreOrLessEquals(expected.left), reason: '$name left');
  expect(actual.top, moreOrLessEquals(expected.top), reason: '$name top');
  expect(actual.width, moreOrLessEquals(expected.width), reason: '$name width');
  expect(actual.height, moreOrLessEquals(expected.height),
      reason: '$name height');
}

/// 把背景当前这一帧真的光栅化出来。
///
/// 这是这一份测试唯一能钉住「动画到底动没动」的办法：pixel 比较不会因为
/// `CustomPaint` 的画笔是私有的就变成一句空断言。
///
/// 取的是 `NightBackdrop` **自己**那层 `RepaintBoundary`（它在 `build` 里的根就是），
/// 而不是 `find.byType(RepaintBoundary).first`——后者会落到路由
/// `_ModalScope` 那个祖先边界上，框进来的是整屏，不是被测组件。
Future<Uint8List> snapshot(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find
        .descendant(
          of: find.byType(NightBackdrop),
          matching: find.byType(RepaintBoundary),
        )
        .first,
  );
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  });
  return bytes!;
}

void main() {
  Future<void> pumpBackdrop(
    WidgetTester tester, {
    required NightScene scene,
    bool reduceMotion = true,
  }) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: reduceMotion);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: NightBackdrop(scene: scene))),
    );
    await tester.runAsync(() => precacheImage(
          AssetImage(scene.photoAsset),
          tester.element(find.byType(NightBackdrop)),
        ));
    // 这里**不能**用 pumpAndSettle：开了动画时它会 `timed out`。
    await tester.pump();
  }

  testWidgets('八种场景都能渲染，不抛异常', (tester) async {
    for (final scene in NightScene.values) {
      await pumpBackdrop(tester, scene: scene);
      expect(tester.takeException(), isNull, reason: '${scene.id} 画崩了');
      expect(find.byType(NightBackdrop), findsOneWidget);
    }
  });

  testWidgets('减弱动态效果时停表：隔两秒的画面一模一样', (tester) async {
    // 用雨夜：它的周期最短（2.8 秒），两秒内一定有肉眼可见的位移。
    // 用流星夜的话这条会变成空断言——流星那三条在前两秒还没进入可见窗口
    // （`p < .82` 直接跳过），画面本来就一模一样，停没停表都测不出来。
    await pumpBackdrop(tester, scene: NightScene.rain);
    final before = await snapshot(tester);

    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }

    expect(await snapshot(tester), before, reason: '开了「减弱动态效果」还在动 = 无障碍要求没落实');

    // 画面没变还不够：表本身也得停。`repeat()` 会让每一帧都再排一帧，
    // 时钟还在转就该有排队的帧；两秒推完仍没有，才算真的停表。
    expect(tester.binding.hasScheduledFrame, isFalse,
        reason: '视觉上静止但时钟还在转 = 白烧电池，不是「停表」');
  });

  testWidgets('没开减弱动态效果时相位真的在走：画面会变', (tester) async {
    await pumpBackdrop(tester, scene: NightScene.rain, reduceMotion: false);
    final before = await snapshot(tester);

    // 显式推帧而不是 pumpAndSettle——60 秒的循环表永远不会「settle」。
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }

    // **这条断言只能证明「时钟在走」，证明不了别的。**
    //
    // 它盖不住任何**单场景的几何/位移**：34 颗星点那层 `sleepTwinkle` 对每套场景都画，
    // 两帧之间必然不同，于是「画面变了」永远成立。
    //
    // 实测（把场景专属层与流星**全部跳过**，只留网点 + 光晕 + 星点）：
    // 八套场景逐个跑，`framesDiffer` 一律为 true —— 可见差完全来自星点那一层，
    // 跟被测场景画了什么无关。也正因为如此，把「极光盒高」「流星位移分母」同时改回
    // 错的值，aurora / meteor / moon 的「两帧不同」照样是 true。
    //
    // 单场景几何改由下面那组 `NightSceneGeometry` 的纯函数断言来守——那些值直接
    // 取自原型 `/tmp/figma-make/index.css`，不是照抄本仓库的实现。
    expect(await snapshot(tester), isNot(before),
        reason: '动画根本没跑起来（变异验证：把重复控制器摘掉，这条必须变红）');
  });

  testWidgets('换场景后重绘不抛异常', (tester) async {
    await pumpBackdrop(tester, scene: NightScene.meteor);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: NightBackdrop(scene: NightScene.galaxy)),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 单场景几何。上面那些像素断言盖不住这一层（星点层总会让两帧不同），
  // 所以这里直接钉 `NightSceneGeometry` 里的算式。
  //
  // **期望值一律由原型 `/tmp/figma-make/index.css` 与 `App.tsx` 的字面量算出**，
  // 不是照抄本仓库实现——否则这组断言只会把已有的错再确认一遍。
  // 每条注释里给出它所依据的那条 CSS 规则。
  // ─────────────────────────────────────────────────────────────────────────
  group('夜景几何', () {
    // 画布特意取宽高不等：能同时暴露「把 vw 当 vh」这类错。
    const w = 1000.0;
    const h = 2000.0;
    const size = Size(w, h);

    test('光晕盒与整层透明度', () {
      // .sleep-scene-glow-one { width:70vw; height:42vw; top:-12vw; right:-10vw }
      // ⇒ left = 100vw - 10vw - 70vw = 40vw
      expectRect(NightSceneGeometry.glowOneRect(size),
          const Rect.fromLTWH(400, -120, 700, 420),
          label: 'glow-one');

      // .sleep-scene-moon .sleep-scene-glow-one { 48vw 见方; top:8%; right:7% }
      // right:7% 相对**宽** ⇒ left = (100% - 7% - 48%) = 45% 宽；top:8% 相对**高**。
      expectRect(NightSceneGeometry.moonGlowRect(size),
          const Rect.fromLTWH(450, 160, 480, 480),
          label: '月华');

      // .sleep-scene-glow-two { 62vw × 48vw; bottom:-20vw; left:-18vw }
      // bottom 是 vw 单位 ⇒ top = H + 20vw - 48vw。
      expectRect(NightSceneGeometry.glowTwoRect(size),
          const Rect.fromLTWH(-180, 1720, 620, 480),
          label: 'glow-two');

      // .sleep-scene-glow { opacity: .55 }
      expect(NightSceneGeometry.glowOpacity, moreOrLessEquals(.55));
    });

    test('网点：67px 一格，alpha 是 .7 × .13', () {
      // .sleep-mode::before { background-size: 67px 67px; opacity: .13 }
      //   background-image: radial-gradient(circle, rgba(255,255,255,.7) 0 1px, transparent 1.5px)
      expect(NightSceneGeometry.textureStep, moreOrLessEquals(67));
      expect(NightSceneGeometry.textureAlpha, moreOrLessEquals(.7 * .13));
    });

    test('animation-delay 的符号约定：正数 = 晚开始（相位落后）', () {
      // CSS 的本地时间是 `t - delay`。流星与星点的 delay 都是**正**数，
      // 所以它们此刻应当「还没跑那么远」。
      expect(NightSceneGeometry.loopProgress(t: 10, duration: 8.5, delay: 3.8),
          moreOrLessEquals(6.2 / 8.5));
      // 负延迟则相反（极光 i2 / 海浪 / 云 / 萤火 / 雨丝用的是这一档）。
      expect(NightSceneGeometry.loopProgress(t: 10, duration: 9, delay: -4),
          moreOrLessEquals(14 / 9 - 1));
      // 没有延迟就是 t 本身。
      expect(NightSceneGeometry.loopProgress(t: 10, duration: 8.5),
          moreOrLessEquals(10 / 8.5 - 1));
    });

    test('星点：数量 / 位置 / 直径 / 正延迟 / 闪烁曲线', () {
      // SLEEP_STARS = Array.from({ length: 34 })；left=(i*37+11)%97、top=(i*53+7)%82
      expect(NightSceneGeometry.starCount, 34);
      expect(NightSceneGeometry.starLeft(0), moreOrLessEquals(.11));
      expect(NightSceneGeometry.starTop(0), moreOrLessEquals(.07));
      expect(NightSceneGeometry.starLeft(1), moreOrLessEquals(.48));
      expect(NightSceneGeometry.starTop(1), moreOrLessEquals(.60));

      // size: index % 6 === 0 ? 2 : 1 —— 是直径，半径减半。
      expect(NightSceneGeometry.starRadius(0), 1.0);
      expect(NightSceneGeometry.starRadius(1), .5);
      expect(NightSceneGeometry.starRadius(6), 1.0);

      // animationDelay: (index % 9) * 0.43 —— **正数**（晚一点才开始）。
      expect(NightSceneGeometry.starDelay(0), 0);
      expect(NightSceneGeometry.starDelay(1), moreOrLessEquals(.43));
      expect(NightSceneGeometry.starDelay(8), moreOrLessEquals(3.44));
      expect(NightSceneGeometry.starDelay(9), 0);

      // sleepTwinkle { 50% { opacity:.25; scale:.65 } }，没有 alternate：
      // 起点与终点都是原样，中点最暗最小。
      expect(NightSceneGeometry.starTwinkleAt(0), moreOrLessEquals(0));
      expect(NightSceneGeometry.starTwinkleAt(.5), moreOrLessEquals(1));
      expect(NightSceneGeometry.starTwinkleAt(1), moreOrLessEquals(0));
    });

    test('流星：可见窗口 / 位移分母 / 透明度峰值 / 正延迟', () {
      // sleepMeteor { 0%,82% { opacity:0 } ... 91%,100% { opacity:0 } }
      expect(NightSceneGeometry.meteorVisibleAt(.819), isFalse);
      expect(NightSceneGeometry.meteorVisibleAt(.82), isTrue);
      expect(NightSceneGeometry.meteorVisibleAt(.91), isTrue);
      expect(NightSceneGeometry.meteorVisibleAt(.911), isFalse);

      // transform 只声明在 82% 与 91% 两处 ⇒ 位移在 9% 内走完。
      expect(NightSceneGeometry.meteorTravelAt(.82), moreOrLessEquals(0));
      expect(NightSceneGeometry.meteorTravelAt(.865), moreOrLessEquals(.5));
      expect(NightSceneGeometry.meteorTravelAt(.91), moreOrLessEquals(1));

      // opacity：82%→0、84%→.9、91%→0。
      expect(NightSceneGeometry.meteorOpacityAt(.82), moreOrLessEquals(0));
      expect(NightSceneGeometry.meteorOpacityAt(.84), moreOrLessEquals(.9));
      expect(NightSceneGeometry.meteorOpacityAt(.91), moreOrLessEquals(0));

      // 三条的 animation-delay 是**正**数（晚开始），不是负的。
      expect(NightSceneGeometry.meteorDelay, [0.0, 3.8, 7.1]);
      // 拖尾色 rgba(230,237,255,.85)。
      expect(NightSceneGeometry.meteorTrailAlpha, moreOrLessEquals(.85));
    });

    test('极光：两层的盒**不同**，高按 inset 的 A/C 算', () {
      // i1 inset:-8% -20% 42% ⇒ 高 = H(1 - (-8%) - 42%) = 66%H；left=-20%W、宽 140%W。
      expectRect(NightSceneGeometry.auroraBandRect(size, 0),
          const Rect.fromLTWH(-200, -160, 1400, 1320),
          label: '极光 i1');
      // i2 inset:18% -8% -22% ⇒ 高 = H(1 - 18% - (-22%)) = 104%H；left=-8%W、宽 116%W。
      expectRect(NightSceneGeometry.auroraBandRect(size, 1),
          const Rect.fromLTWH(-80, 360, 1160, 2080),
          label: '极光 i2');

      // 两层左右内缩不同 ⇒ 左偏移与宽都不能共用 i1 的值。
      final one = NightSceneGeometry.auroraBandRect(size, 0);
      final two = NightSceneGeometry.auroraBandRect(size, 1);
      expect(two.left, isNot(moreOrLessEquals(one.left)));
      expect(two.width, isNot(moreOrLessEquals(one.width)));

      expect(NightSceneGeometry.auroraDuration, [9.0, 12.0]);
      expect(NightSceneGeometry.auroraDelay, [0.0, -4.0]);
      expect(NightSceneGeometry.auroraLayerOpacity, [.5, .65]);
    });

    test('海浪：容器 inset / 子元素嵌套百分比 / 三者相乘的描边透明度', () {
      // .sleep-ocean-waves { inset:auto -12% -4%; height:42% }
      // ⇒ 左右各外扩 12% ⇒ 宽 124%W；top = H + 4%H - 42%H = 62%H。
      expectRect(NightSceneGeometry.oceanWaveContainerRect(size),
          const Rect.fromLTWH(-120, 1240, 1240, 840),
          label: '海浪容器');

      // .sleep-ocean-waves i { left:-8%; width:116%; height:52% } —— 相对**父盒**解析。
      // 子盒：left = -120 + 1240×(-8%) = -219.2、宽 = 1240×1.16 = 1438.4、
      //       高 = 840×52% = 436.8；顶边 = 容器顶 1240（i1 无 top）。
      expectRect(
          NightSceneGeometry.oceanWaveRect(size, 0, 0),
          Rect.fromCenter(
              center: const Offset(500, 1458.4), width: 1438.4, height: 436.8),
          label: '海浪 i1');
      // i2 top:20% ⇒ 1240 + 840×.20 = 1408；i3 top:42% ⇒ 1240 + 840×.42 = 1592.8。
      expect(NightSceneGeometry.oceanWaveRect(size, 1, 0).top,
          moreOrLessEquals(1408));
      expect(NightSceneGeometry.oceanWaveRect(size, 2, 0).top,
          moreOrLessEquals(1592.8));

      // sleepWaveDrift { to { translateX(4%) translateY(-10px) scaleX(1.06) } }
      // 缩放不动中心、平移加在中心上：中心 x += 1438.4×4%、y -= 10；宽 ×1.06。
      expectRect(
          NightSceneGeometry.oceanWaveRect(size, 0, 1),
          Rect.fromCenter(
              center: const Offset(557.536, 1448.4),
              width: 1524.704,
              height: 436.8),
          label: '海浪 i1 漂移到底');

      // border 色 rgba(81,168,202,.15) × 容器 opacity .42 —— 两者都要在。
      expect(
          NightSceneGeometry.oceanWaveStrokeAlpha, moreOrLessEquals(.15 * .42));
      expect(NightSceneGeometry.oceanWaveChildOpacity, [1.0, .7, .45]);
    });

    test('云：横向 -55vw → 115vw', () {
      // .sleep-clouds i { left:-55vw; width:50vw; height:15vw }
      // + sleepCloud { to { translateX(170vw) } }
      expect(NightSceneGeometry.cloudLeftAt(size, 0), moreOrLessEquals(-550));
      expect(NightSceneGeometry.cloudLeftAt(size, 0.5), moreOrLessEquals(300));
      expect(NightSceneGeometry.cloudLeftAt(size, 1), moreOrLessEquals(1150));
      expect(NightSceneGeometry.cloudTop, [.18, .55, .76]);
      expect(NightSceneGeometry.cloudWidth, [.50, .68, .44]);
      expect(NightSceneGeometry.cloudHeight, moreOrLessEquals(.15));
    });

    test('哪些场景有流星：meteor / moon / galaxy，其余五个没有', () {
      // 原型是**反着**列的：只写了
      //   .sleep-scene-{aurora,ocean,cloud,firefly,rain} .sleep-meteors { display:none }
      // 所以另外三个场景（含月海与银河）都有流星。
      expect(NightScene.values.where(NightSceneGeometry.hasMeteors).toSet(),
          {NightScene.meteor, NightScene.moon, NightScene.galaxy});

      // 正面把「那五个不能有」也钉住，防止以后顺手加回来。
      for (final s in [
        NightScene.aurora,
        NightScene.ocean,
        NightScene.cloud,
        NightScene.firefly,
        NightScene.rain,
      ]) {
        expect(NightSceneGeometry.hasMeteors(s), isFalse,
            reason: '${s.id} 不该有流星');
      }
    });

    test('萤火：逐条列举的位置/延迟，后四只重叠', () {
      // :nth-child(1..10) 逐条；:nth-child(n+11) 共用 52% / 54% / -3.5s。
      expect(NightSceneGeometry.fireflyLeft.length, 14);
      expect(NightSceneGeometry.fireflyLeft.take(10).toList(),
          [8.0, 18.0, 28.0, 38.0, 48.0, 58.0, 68.0, 78.0, 88.0, 93.0]);
      expect(NightSceneGeometry.fireflyLeft.skip(10).toSet(), {52.0});
      expect(NightSceneGeometry.fireflyTop.skip(10).toSet(), {54.0});
      expect(NightSceneGeometry.fireflyDelay.skip(10).toSet(), {-3.5});
      // width:3px ⇒ 半径 1.5。
      expect(NightSceneGeometry.fireflyRadius, moreOrLessEquals(1.5));

      // sleepFirefly 三段：0%/100% .15、45% 1、70% .4。
      expect(NightSceneGeometry.fireflyOpacityAt(0), moreOrLessEquals(.15));
      expect(NightSceneGeometry.fireflyOpacityAt(.45), moreOrLessEquals(1));
      expect(NightSceneGeometry.fireflyOpacityAt(.70), moreOrLessEquals(.4));
      expect(NightSceneGeometry.fireflyOpacityAt(1), moreOrLessEquals(.15));
      expect(NightSceneGeometry.fireflyShiftAt(.45).dx, moreOrLessEquals(14));
      expect(NightSceneGeometry.fireflyShiftAt(.45).dy, moreOrLessEquals(-24));
      expect(NightSceneGeometry.fireflyShiftAt(.70).dx, moreOrLessEquals(-9));
      expect(NightSceneGeometry.fireflyShiftAt(.70).dy, moreOrLessEquals(-12));

      // `animation: sleepFirefly 7s ease-in-out infinite` 的 `ease-in-out` 对
      // **每一段**都生效，中间 45%→70% 那段也不例外。
      // 取段内 t=.25 处：线性会给出 1 - .6×.25 = .85，套了 ease-in-out 则不是。
      final easedQuarter = Curves.easeInOut.transform(.25);
      expect(easedQuarter, lessThan(.25), reason: 'ease-in-out 起步慢于线性');
      expect(NightSceneGeometry.fireflyOpacityAt(.45 + .25 * .25),
          moreOrLessEquals(1 - .6 * easedQuarter));
      expect(NightSceneGeometry.fireflyShiftAt(.45 + .25 * .25).dy,
          moreOrLessEquals(-24 + 12 * easedQuarter));
    });

    test('银河：盒按 inset -22% -45% / 往返的角度·缩放·透明度', () {
      // inset:-22% -45% ⇒ 宽 = W(1+90%) = 190%W、高 = H(1+44%) = 144%H。
      expectRect(NightSceneGeometry.galaxyBandRect(size),
          const Rect.fromLTWH(-450, -440, 1900, 2880),
          label: '银河带');

      // 起点是基线的 rotate(-24deg)/scale(1)/opacity 1，终点 -19deg/1.08/.7。
      expect(NightSceneGeometry.galaxyAngleAt(0),
          moreOrLessEquals(-24 * math.pi / 180));
      expect(NightSceneGeometry.galaxyScaleAt(0), moreOrLessEquals(1));
      expect(NightSceneGeometry.galaxyFadeAt(0), moreOrLessEquals(1));
      expect(NightSceneGeometry.galaxyAngleAt(1),
          moreOrLessEquals(-19 * math.pi / 180));
      expect(NightSceneGeometry.galaxyScaleAt(1), moreOrLessEquals(1.08));
      expect(NightSceneGeometry.galaxyFadeAt(1), moreOrLessEquals(.7));
    });

    test('雨丝：18 条、逐条列举的 left/延迟、纵向 -12vh → 103vh', () {
      // Array.from({ length: 18 })；:nth-child(1..14) 逐条、:nth-child(n+15) 共用 50%。
      expect(NightSceneGeometry.rainLeft.length, 18);
      expect(NightSceneGeometry.rainLeft.take(14).toList(), [
        .04,
        .11,
        .18,
        .25,
        .32,
        .39,
        .46,
        .53,
        .60,
        .67,
        .74,
        .81,
        .88,
        .95
      ]);
      expect(NightSceneGeometry.rainLeft.skip(14).toSet(), {.50});

      expect(NightSceneGeometry.rainDelay[0], 0);
      expect(NightSceneGeometry.rainDelay[1], moreOrLessEquals(-.8));
      expect(NightSceneGeometry.rainDelay[13], moreOrLessEquals(-1.3));
      expect(NightSceneGeometry.rainDelay.skip(14).toSet(), {-2.0});

      // top:-12% + sleepRain { to { translateY(115vh) } } ⇒ -12vh → 103vh。
      expect(NightSceneGeometry.rainTopAt(size, 0), moreOrLessEquals(-240));
      expect(NightSceneGeometry.rainTopAt(size, 1), moreOrLessEquals(2060));
      expect(NightSceneGeometry.rainHeight, moreOrLessEquals(38));
      // 整层 opacity .18 × 线色 .8。
      expect(NightSceneGeometry.rainAlpha, moreOrLessEquals(.8 * .18));
    });
  });
}
