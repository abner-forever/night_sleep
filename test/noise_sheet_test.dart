import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/core/theme/app_theme.dart';
import 'package:night_sleep/core/widgets/app_sheet.dart';
import 'package:night_sleep/features/sleep/data/noise_player.dart';
import 'package:night_sleep/features/sleep/data/noise_synth.dart';
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
  Future<void> pumpSheet(WidgetTester tester, NoisePlayer player) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: NoiseSheet(player: player)),
      ),
    );
    // Deliberately not `pumpAndSettle`: the sheet's waveform indicator repeats
    // forever, so the tree never reaches a settled state and pumpAndSettle times
    // out rather than failing on anything real.
    await tester.pump();
  }

  /// Lets the async tap handler finish and any animation advance.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
  }

  testWidgets('选中一个声音会把它交给播放器', (tester) async {
    final player = _FakePlayer();
    await pumpSheet(tester, player);

    await tester.tap(find.text('雨声'));
    await settle(tester);

    expect(player.calls.first, 'play:rain:0.50', reason: '应把雨声和当前音量交给播放器');
    expect(find.textContaining('正在播放「雨声」'), findsOneWidget);
  });

  testWidgets('再次点击同一个声音会停止播放', (tester) async {
    final player = _FakePlayer();
    await pumpSheet(tester, player);

    await tester.tap(find.text('雨声'));
    await settle(tester);
    await tester.tap(find.text('雨声'));
    await settle(tester);

    expect(player.calls, contains('stop'));
    expect(find.textContaining('正在播放'), findsNothing);
  });

  testWidgets('切换到另一个声音时不会重复 stop', (tester) async {
    final player = _FakePlayer();
    await pumpSheet(tester, player);

    await tester.tap(find.text('雨声'));
    await settle(tester);
    await tester.tap(find.text('篝火'));
    await settle(tester);

    expect(player.calls, contains('play:fire:0.50'));
    expect(player.calls, isNot(contains('stop')), reason: '换声音是替换，不是先停后放');
  });

  testWidgets('播放失败时如实报错，且不显示为正在播放', (tester) async {
    final player = _FakePlayer(failWith: '无法生成音频');
    await pumpSheet(tester, player);

    await tester.tap(find.text('雨声'));
    await settle(tester);

    expect(find.text('无法生成音频'), findsOneWidget);
    expect(
      find.textContaining('正在播放'),
      findsNothing,
      reason: '平台拒绝了就不能显示成正在播放',
    );
    expect(find.textContaining('正在播放「雨声」'), findsNothing);
  });

  testWidgets('拖动音量条会写回播放器', (tester) async {
    final player = _FakePlayer();
    await pumpSheet(tester, player);

    await tester.tap(find.text('雨声'));
    await settle(tester);
    player.calls.clear();

    // Candidates are 28px tall and wide. The sheet's drag handle matches too —
    // it is the same height and spans the sheet — so take the lowest one, which
    // is the slider.
    final candidates = tester
        .widgetList<GestureDetector>(find.byType(GestureDetector))
        .map((widget) => tester.getRect(find.byWidget(widget)))
        .where((rect) => rect.height == 28 && rect.width > 120)
        .toList();
    expect(candidates, isNotEmpty, reason: '找不到音量条');
    final track = candidates.reduce((a, b) => a.top > b.top ? a : b);

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

  testWidgets('宽屏下面板限宽，八格仍是四列两行且不溢出', (tester) async {
    // iPad 横屏。格子宽度曾经按**屏幕**宽度算，而面板在 ≥640px 时被
    // `_SheetHost` 限到 560px：每格被算成 271px，`Wrap` 一行只放得下一个，
    // 内容整体溢出 217px 并被裁掉（音量条与定时 chips 从此够不着）。
    // 这个尺寸下 `NoiseSheet` 不能直接摆进 `Scaffold`——那样没有限宽，
    // 复现不出这条。必须走真实的 `showNoiseSheet`。
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
    // 弹窗里挂着永不停止的波形动画，`pumpAndSettle` 收敛不了。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final panel = tester.getRect(find.byType(AppSheet));
    final tiles = find.byType(NoiseTile);
    expect(tiles, findsNWidgets(8));

    final rects = tester
        .widgetList<NoiseTile>(tiles)
        .map((tile) => tester.getRect(find.byWidget(tile)))
        .toList();
    expect(
      rects.map((rect) => rect.left).toSet().length,
      4,
      reason: '八个音效格应排成四列',
    );
    expect(
      rects.map((rect) => rect.top).toSet().length,
      2,
      reason: '八个音效格应排成两行',
    );
    for (final rect in rects) {
      expect(rect.left, greaterThanOrEqualTo(panel.left));
      expect(rect.right, lessThanOrEqualTo(panel.right));
      expect(rect.bottom, lessThanOrEqualTo(panel.bottom));
    }
  });

  testWidgets('关闭面板会释放播放器', (tester) async {
    final player = _FakePlayer();
    await pumpSheet(tester, player);

    await tester.tap(find.text('雨声'));
    await settle(tester);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();

    expect(player.calls, contains('dispose'), reason: '面板关闭必须停掉声音');
  });
}
