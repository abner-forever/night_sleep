import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/app/noise_session.dart';
import 'package:night_sleep/core/database/app_database.dart';
import 'package:night_sleep/core/theme/app_theme.dart';
import 'package:night_sleep/features/session/presentation/night_scene.dart';
import 'package:night_sleep/features/session/presentation/sheets/night_noise_sheet.dart';
import 'package:night_sleep/features/session/presentation/widgets/night_scene_picker.dart';
import 'package:night_sleep/features/sleep/data/noise_player.dart';
import 'package:night_sleep/features/sleep/data/noise_synth.dart';
import 'package:night_sleep/features/sleep/data/session_repository.dart';
import 'package:night_sleep/features/sleep/presentation/widgets/noise_controls.dart';

/// 记下每一次播放器调用的假实现（与 `sleep_session_page_test.dart` 里那份同款）。
class _SheetFakeNoisePlayer extends NoisePlayer {
  final List<String> calls = [];

  @override
  Future<void> play(NoiseKind kind, {required double volume}) async {
    calls.add('play:${kind.id}:${volume.toStringAsFixed(2)}');
  }

  @override
  Future<void> setVolume(double volume) async {
    calls.add('volume:${volume.toStringAsFixed(2)}');
  }

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Future<void> dispose() async => calls.add('dispose');
}

/// 把弹窗推起来。走真实数据库 + 真实 ProviderScope，只是时钟冻住。
///
/// [appTheme] 默认深色（会话页实际情形）；传 `AppTheme.light()` 用来验「弹窗
/// 走到 root navigator、继承不到会话页那层 Theme」时的令牌归属。
Future<void> pumpNoiseSheet(
  WidgetTester tester, {
  NoisePlayer? player,
  ThemeData? appTheme,
}) async {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final database = AppDatabase(NativeDatabase.memory());
  addTearDown(database.close);
  await database.saveActiveSession(
    ActiveSessionsCompanion.insert(
      id: SessionRepository.sessionId,
      startAtUtc: DateTime.utc(2026, 8, 30, 23, 14),
      wakeMinutes: 7 * 60,
      createdAt: DateTime.utc(2026, 8, 30, 23, 14),
    ),
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(database),
        noisePlayerProvider
            .overrideWithValue(player ?? _SheetFakeNoisePlayer()),
      ],
      child: MaterialApp(
        theme: appTheme ?? AppTheme.dark(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showNightNoiseSheet(context),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
}

void main() {
  Future<void> pumpPicker(
    WidgetTester tester, {
    required NightScene scene,
    required ValueChanged<NightScene> onChanged,
  }) async {
    // 取一块足够宽的画布：八张卡 8×68 + 7×10 + 24 ≈ 638px，手机宽（430）下
    // 第七张「银河」会落在视口外——懒加载的 `ListView` 不会把它摆上台面，
    // `find.text` 又会跳过台面外的子节点，于是「列出全部八种」与「点银河」
    // 两条断言都够不着它。本仓库既有的做法正是给测试一块超尺寸画布
    // （如 `Size(430, 2600)`）让全部内容一次摊开，这里同理把宽放开。
    tester.view.physicalSize = const Size(900, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NightScenePicker(scene: scene, onChanged: onChanged),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('列出全部八种场景，一个不多一个不少', (tester) async {
    await pumpPicker(tester, scene: NightScene.meteor, onChanged: (_) {});

    for (final option in NightScene.values) {
      expect(find.text(option.label), findsOneWidget,
          reason: '漏了「${option.label}」');
    }
    // 反向护栏：搬错枚举（例如把原型的九宫格搬过来）时这条必须红。
    expect(
        find.byType(NightSceneChoice), findsNWidgets(NightScene.values.length));
  });

  testWidgets('点一种场景回调的是那一种', (tester) async {
    final picked = <NightScene>[];
    await pumpPicker(tester, scene: NightScene.meteor, onChanged: picked.add);

    await tester.tap(find.text('银河'));
    await tester.pumpAndSettle();

    expect(picked, [NightScene.galaxy]);
  });

  testWidgets('选中的那一张有标记', (tester) async {
    await pumpPicker(tester, scene: NightScene.ocean, onChanged: (_) {});

    final selected = tester.widget<NightSceneChoice>(
      find.byWidgetPredicate(
        (w) => w is NightSceneChoice && w.selected,
      ),
    );
    expect(selected.scene, NightScene.ocean);
  });

  testWidgets('430 宽真机上横向滚动后也能点到末尾的雨夜', (tester) async {
    // 上面那个 helper 为了让「八张卡都在」可测把画布放到了 900 宽，代价是真机
    // 宽度下「滚到末尾才够得着最后一张」这条路径没了覆盖。这条用例把它补回来：
    // 就用 430 宽，横向滚到末尾，再点最后一张。
    final picked = <NightScene>[];
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NightScenePicker(
            scene: NightScene.meteor,
            onChanged: picked.add,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 选中的是「流星夜」（第一张），末尾的「雨夜」一开始在视口外，得先滚进来。
    await tester.scrollUntilVisible(
      find.text('雨夜'),
      120,
      scrollable: find.byType(Scrollable),
    );
    await tester.tap(find.text('雨夜'));
    await tester.pumpAndSettle();

    expect(picked, [NightScene.rain]);
  });

  testWidgets('弹窗里有九宫格、音量、四个时长档，没有「整晚」', (tester) async {
    await pumpNoiseSheet(tester);

    expect(find.text('白噪音设置'), findsOneWidget);
    expect(find.text('关闭'), findsOneWidget);
    for (final option in kNoiseOptions) {
      expect(find.text(option.label), findsOneWidget);
    }
    // 产品红线：会话里的白噪音必须有上限，列表里不存在「整晚」。
    expect(find.textContaining('整晚'), findsNothing);
    expect(find.textContaining('不限'), findsNothing);
    for (final minutes in NoiseSessionController.timerChoices) {
      expect(find.text('${minutes}m'), findsOneWidget);
    }
    // 后台播放的如实标注要跟到弹窗里（规格 §十）。
    expect(find.textContaining('退到后台或锁屏后声音会停'), findsOneWidget);
  });

  testWidgets('点「完成」关掉弹窗，白噪音继续响', (tester) async {
    final player = _SheetFakeNoisePlayer();
    await pumpNoiseSheet(tester, player: player);

    await tester.tap(find.text('雨声'));
    await tester.pumpAndSettle();
    expect(player.calls, contains('play:rain:0.50'));

    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    expect(find.text('白噪音设置'), findsNothing);
    // 关掉弹窗**不**停声音——播放器挂在 app 级的控制器上，生命周期比这层弹窗长。
    expect(player.calls.where((c) => c == 'stop'), isEmpty);
  });

  testWidgets('浅色应用主题下，弹窗内的共享控件仍是深色令牌', (tester) async {
    // 回归：`showGeneralDialog` 默认 `useRootNavigator: true`，弹窗路由挂在 root
    // navigator 下，**继承不到会话页那层 `Theme(AppTheme.dark())`**。外框走
    // `NightStyle` 是深的，但宫格 / 音量 / 时长 chip 这些共享控件从应用主题令牌取色
    // ——不显式再包一层深色 Theme，浅色主题下它们会变浅，深浅拼在一张面板上。
    // 既有用例把 `MaterialApp.theme` 直接设成 `AppTheme.dark()`，正好盖不出这条。
    await pumpNoiseSheet(tester, appTheme: AppTheme.light());

    final context = tester.element(find.text('白噪音设置'));
    expect(Theme.of(context).brightness, Brightness.dark);
  });
}
