import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/core/theme/app_theme.dart';
import 'package:night_sleep/core/widgets/app_sheet.dart';
import 'package:night_sleep/features/sleep/data/noise_player.dart';
import 'package:night_sleep/features/sleep/data/noise_asset.dart';
import 'package:night_sleep/features/sleep/presentation/sheets/noise_sheet.dart';
import 'package:night_sleep/features/sleep/presentation/widgets/noise_controls.dart';

/// The sleep-sounds sheet's control over playback.
///
/// The audio itself cannot be heard here, so what these cover is the part that
/// would otherwise let the UI lie: that a sound is only shown as playing once
/// the platform accepted it, that a refusal is reported instead of leaving a
/// stop button over silence, and that the timer and the volume slider really
/// reach the player.
class _FakePlayer extends NoisePlayer {
  _FakePlayer({this.failWith});

  /// When set, [play] throws this message the way a real failure would.
  final String? failWith;

  final List<String> calls = [];

  @override
  Future<void> play(NoiseKind kind, {required double volume}) async {
    calls.add('play:${kind.id}:${volume.toStringAsFixed(2)}');
    if (failWith != null) {
      throw NoisePlaybackFailure(failWith!);
    }
  }

  @override
  Future<void> setVolume(double volume) async {
    calls.add('volume:${volume.toStringAsFixed(2)}');
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
  }

  @override
  Future<void> dispose() async {
    calls.add('dispose');
  }
}

void main() {
  Future<void> pumpSheet(WidgetTester tester, NoisePlayer player,
      {FakeViewPadding padding = const FakeViewPadding(),
      Size surface = const Size(430, 900)}) async {
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1.0;
    tester.view.padding = padding;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: NoiseSheet(player: player)),
      ),
    );
    // 显式推两帧即可：这一页没有循环动画，测试要的是确定性的布局结果。
    await tester.pump();
  }

  /// Lets the async tap handler finish and any animation advance.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
  }

  testWidgets('全屏音效弹层的关闭与标题位于状态栏下方', (tester) async {
    await pumpSheet(tester, _FakePlayer(),
        padding: const FakeViewPadding(top: 59, bottom: 34));
    expect(tester.getTopLeft(find.text('助眠音效')).dy, greaterThanOrEqualTo(59));
    final close = find.bySemanticsLabel('关闭助眠音效');
    expect(close, findsOneWidget);
    expect(tester.getTopLeft(close).dy, greaterThanOrEqualTo(59));
    expect(close.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('选中一个声音会把它交给播放器', (tester) async {
    final player = _FakePlayer();
    await pumpSheet(tester, player);

    await tester.tap(find.text('溪流'));
    await settle(tester);

    expect(player.calls.first, 'play:stream:0.50', reason: '应把溪流和当前音量交给播放器');
    expect(find.textContaining('正在播放 溪流'), findsOneWidget);
  });

  testWidgets('393×852 下五条音效和底部控制都落在一屏内', (tester) async {
    await pumpSheet(
      tester,
      _FakePlayer(),
      surface: const Size(393, 852),
      padding: const FakeViewPadding(top: 47, bottom: 34),
    );

    expect(find.text('溪流').hitTestable(), findsOneWidget);
    expect(find.text('选择喜欢的声音').hitTestable(), findsOneWidget);
    expect(
      tester.getRect(find.text('选择喜欢的声音')).bottom,
      lessThanOrEqualTo(852 - 34),
    );
    expect(
      tester.getRect(find.text('选择喜欢的声音')).bottom,
      greaterThanOrEqualTo(760),
      reason: '卡片或控制区仍然太小，底部空出了半屏',
    );
    expect(
      tester.getRect(find.byType(NoiseTile).first).width,
      greaterThanOrEqualTo(160),
      reason: '手机端应使用两列大卡片',
    );

    final scrollable = find
        .descendant(
          of: find.byType(SingleChildScrollView),
          matching: find.byType(Scrollable),
        )
        .first;
    expect(
      tester.state<ScrollableState>(scrollable).position.maxScrollExtent,
      0,
      reason: '内容超过一个屏幕，用户仍需滚动才能看到底部控制',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('再次点击同一个声音会停止播放', (tester) async {
    final player = _FakePlayer();
    await pumpSheet(tester, player);

    await tester.tap(find.text('溪流'));
    await settle(tester);
    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is NoiseTile && widget.option.id == 'stream',
      ),
    );
    await settle(tester);

    expect(player.calls, contains('stop'));
    expect(find.textContaining('正在播放'), findsNothing);
  });

  testWidgets('切换到另一个声音时不会重复 stop', (tester) async {
    final player = _FakePlayer();
    await pumpSheet(tester, player);

    await tester.tap(find.text('溪流'));
    await settle(tester);
    await tester.tap(find.text('篝火'));
    await settle(tester);

    expect(player.calls, contains('play:fire:0.50'));
    expect(player.calls, isNot(contains('stop')), reason: '换声音是替换，不是先停后放');
  });

  testWidgets('播放失败时如实报错，且不显示为正在播放', (tester) async {
    final player = _FakePlayer(failWith: '无法生成音频');
    await pumpSheet(tester, player);

    await tester.tap(find.text('溪流'));
    await settle(tester);

    expect(find.text('无法生成音频'), findsOneWidget);
    expect(
      find.textContaining('正在播放'),
      findsNothing,
      reason: '平台拒绝了就不能显示成正在播放',
    );
    expect(find.textContaining('正在播放「溪流」'), findsNothing);
  });

  testWidgets('拖动音量条会写回播放器', (tester) async {
    final player = _FakePlayer();
    await pumpSheet(tester, player);

    await tester.tap(find.text('溪流'));
    await settle(tester);
    player.calls.clear();

    final track = tester.getRect(find.byType(CupertinoSlider));

    await tester.dragFrom(track.center, Offset(-track.width / 4, 0));
    await settle(tester);

    expect(
      player.calls.where((call) => call.startsWith('volume:')),
      isNotEmpty,
      reason: '音量变化必须到达播放器',
    );
    // Dragging left of centre must lower it.
    final last = player.calls.lastWhere((call) => call.startsWith('volume:'));
    expect(
      double.parse(last.split(':')[1]),
      lessThan(0.5),
      reason: '向左拖动应降低音量',
    );
  });

  testWidgets('宽屏下面板限宽，照片网格保持三列且不溢出', (tester) async {
    tester.view.physicalSize = const Size(1194, 834);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showNoiseSheet(context),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('打开'));
    // 同样只推进到面板完全展开，避免把图片解码等间接异步算进布局断言。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final panel = tester.getRect(find.byType(AppSheet));
    final tiles = find.byType(NoiseTile);
    expect(tiles, findsNWidgets(kNoiseOptions.length));

    final rects = tester
        .widgetList<NoiseTile>(tiles)
        .map((tile) => tester.getRect(find.byWidget(tile)))
        .toList();
    expect(
      rects.map((rect) => rect.left).toSet().length,
      3,
      reason: '宽屏音效照片应排成三列',
    );
    expect(
      rects.map((rect) => rect.top).toSet().length,
      2,
      reason: '五条音效按三列排成两行',
    );
    for (final rect in rects) {
      expect(rect.left, greaterThanOrEqualTo(panel.left));
      expect(rect.right, lessThanOrEqualTo(panel.right));
      expect(rect.width, lessThanOrEqualTo(panel.width / 3));
    }
  });

  testWidgets('关闭面板会释放播放器', (tester) async {
    final player = _FakePlayer();
    await pumpSheet(tester, player);

    await tester.tap(find.text('溪流'));
    await settle(tester);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();

    expect(player.calls, contains('dispose'), reason: '面板关闭必须停掉声音');
  });
}
