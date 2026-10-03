import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/core/database/app_database.dart'
    show
        AppDatabase,
        databaseProvider,
        SleepRecordsCompanion,
        SoundClipsCompanion;
import 'package:night_sleep/core/theme/app_theme.dart';
import 'package:night_sleep/features/sleep/data/sleep_repository.dart';
import 'package:night_sleep/features/sleep/domain/sleep_entry.dart';
import 'package:night_sleep/features/sleep/domain/sound_event.dart';
import 'package:night_sleep/features/sleep/presentation/sheets/sound_card.dart';

/// 假播放器。
///
/// `play()` 忠实模仿 `just_audio`：它返回的 Future 要等播放结束或被停止才完成。
/// 若照普通假实现那样立刻返回，控制器会在起播的同一帧把播放态收回，
/// 测出来的就只是一条「永远没在播」的假象。
class _FakeClipAudioPlayer implements ClipAudioPlayer {
  final _positions = StreamController<Duration>.broadcast(sync: true);

  final List<String> loaded = [];
  Object? loadError;
  int playCalls = 0;
  int stopCalls = 0;
  Duration? lastSeek;

  Completer<void>? _playCompleter;

  @override
  Stream<Duration> get positionStream => _positions.stream;

  @override
  Future<Duration?> setFilePath(String path) async {
    loaded.add(path);
    final error = loadError;
    if (error != null) throw error;
    return const Duration(seconds: 3);
  }

  @override
  Future<void> play() {
    playCalls++;
    return (_playCompleter ??= Completer<void>()).future;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    _playCompleter?.complete();
    _playCompleter = null;
  }

  @override
  Future<void> seek(Duration position) async {
    lastSeek = position;
  }

  @override
  Future<void> dispose() async {
    await _positions.close();
  }

  void emitPosition(Duration position) => _positions.add(position);

  /// 模拟这一段自然播完。
  void finish() {
    _playCompleter?.complete();
    _playCompleter = null;
  }
}

SoundClip _clip({
  String id = 'c-1',
  SoundEventKind kind = SoundEventKind.noise,
  String? localUri,
  List<double>? envelope,
  DateTime? labeledAtUtc,
  int durationMs = 3000,
}) {
  return SoundClip(
    id: id,
    kind: kind,
    startedAtUtc: DateTime.utc(2026, 10, 4, 1),
    durationMs: durationMs,
    localUri: localUri,
    waveformEnvelope: envelope,
    labeledAtUtc: labeledAtUtc,
  );
}

void main() {
  late AppDatabase database;

  setUp(() => database = AppDatabase(NativeDatabase.memory()));
  tearDown(() => database.close());

  Future<void> seedClip(
    String id, {
    required String kind,
    String? localUri,
  }) async {
    await database.saveRecord(
      SleepRecordsCompanion.insert(
        id: 'rec-1',
        startAtUtc: DateTime.utc(2026, 10, 3, 22),
        endAtUtc: DateTime.utc(2026, 10, 4, 6),
        createdAt: DateTime.utc(2026, 10, 3, 22),
        updatedAt: DateTime.utc(2026, 10, 3, 22),
      ),
    );
    await database.insertClips([
      SoundClipsCompanion.insert(
        id: id,
        recordId: 'rec-1',
        kind: kind,
        startedAtUtc: DateTime.utc(2026, 10, 4, 1),
        durationMs: 3000,
        localUri: Value(localUri),
      ),
    ]);
  }

  Future<void> pumpCard(
    WidgetTester tester,
    SoundClip clip, {
    bool expanded = true,
    _FakeClipAudioPlayer? player,
    VoidCallback? onToggle,
  }) async {
    tester.view.physicalSize = const Size(430, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          // 用一个常量覆盖，别让 invalidate 去订阅 drift 的 watch 流——
          // 那会留下 pending timer。
          sleepEntriesProvider.overrideWith((ref) => const <SleepEntry>[]),
          clipAudioPlayerProvider
              .overrideWithValue(player ?? _FakeClipAudioPlayer()),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: SoundCard(
                clip: clip,
                expanded: expanded,
                onToggle: onToggle ?? () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  List<double> heights(WidgetTester tester) => tester
      .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
      .map((widget) => tester.getSize(find.byWidget(widget)).height)
      .toList();

  group('标注', () {
    testWidgets('未标注显示「待标注」，标成「梦话」后显示「梦话」而不是退回「待标注」', (tester) async {
      await seedClip('c-1', kind: 'noise');
      // 库里 kind 是 noise（未标注的占位值），labeledAtUtc 为空。
      await pumpCard(tester, _clip());

      expect(find.text('待标注'), findsOneWidget);
      // 「杂音」只出现在三选一的 chip 上（那一项是选项，不是结论）；
      // 标题说的是「待标注」。
      expect(find.text('杂音'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('clip-label-talk')));
      await tester.pumpAndSettle();

      // 标题与选中的 chip 都变成「梦话」——两处。
      expect(find.text('梦话'), findsNWidgets(2));
      expect(find.text('待标注'), findsNothing);

      // kind 与 labeledAtUtc 必须一起写进库——只改 kind 就再也分不开
      // 「标成了梦话」与「还没标过」。
      final rows = await database.allRecordingClips();
      expect(rows, hasLength(1));
      expect(rows.single.kind, 'talk');
      expect(rows.single.labeledAtUtc, isNotNull);
    });

    testWidgets('已标注的片段选中当前项', (tester) async {
      await pumpCard(
        tester,
        _clip(
            kind: SoundEventKind.snore,
            labeledAtUtc: DateTime.utc(2026, 10, 4, 8)),
      );

      expect(find.text('打鼾'), findsWidgets);
      expect(find.text('待标注'), findsNothing);
    });
  });

  group('回放', () {
    testWidgets('有文件时起播，并把播放进度回传到时间标签', (tester) async {
      final fake = _FakeClipAudioPlayer();
      await pumpCard(tester, _clip(localUri: 'c-1.wav'), player: fake);

      expect(find.text('0:00 / 0:03'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('clip-play-c-1')));
      await tester.pumpAndSettle();

      expect(fake.loaded, ['c-1.wav']);
      expect(fake.playCalls, 1);

      fake.emitPosition(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(find.text('0:01 / 0:03'), findsOneWidget);
    });

    testWidgets('localUri 为空：点播放键不出声、不切播放态，且波形照旧画得出', (tester) async {
      final fake = _FakeClipAudioPlayer();
      await pumpCard(
        tester,
        _clip(localUri: null, envelope: List<double>.filled(38, 0.6)),
        player: fake,
      );

      expect(find.text('这段录音未保留在本地，无法回放'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('clip-play-c-1')));
      await tester.pumpAndSettle();

      expect(fake.loaded, isEmpty);
      expect(fake.playCalls, 0);
      // 没有切到播放态：标签还是时长（时长胶囊与轨道标签各一处），
      // 而不是「位置 / 总时长」的进度。
      expect(find.text('3s'), findsWidgets);
      expect(find.text('0:00 / 0:03'), findsNothing);

      // 包络来自列，与文件在不在无关——形状仍然是真的。
      expect(heights(tester), hasLength(SoundClip.waveformBarCount));
    });

    testWidgets('点播放键只起播，不连带切换展开状态', (tester) async {
      final fake = _FakeClipAudioPlayer();
      var toggles = 0;
      await pumpCard(
        tester,
        _clip(localUri: 'c-1.wav'),
        player: fake,
        onToggle: () => toggles++,
      );

      await tester.tap(find.byKey(const ValueKey('clip-play-c-1')));
      await tester.pumpAndSettle();

      expect(fake.playCalls, 1);
      expect(toggles, 0, reason: '播放键嵌在标题行里，点子控件不该触发父级点击');
    });

    testWidgets('文件读不出时停在非播放态并显示一行说明', (tester) async {
      final fake = _FakeClipAudioPlayer()..loadError = Exception('missing');
      await pumpCard(tester, _clip(localUri: 'c-1.wav'), player: fake);

      await tester.tap(find.byKey(const ValueKey('clip-play-c-1')));
      await tester.pumpAndSettle();

      expect(fake.playCalls, 0);
      expect(find.text('这段录音无法播放，文件可能已损坏或不可读。'), findsOneWidget);
      // 没有停在「正在播放」：起点时间标签还在。
      expect(find.text('0:00 / 0:03'), findsOneWidget);
    });
  });

  group('波形', () {
    testWidgets('有包络时按包络画高度', (tester) async {
      final envelope = List<double>.generate(
        SoundClip.waveformBarCount,
        (i) => i.isEven ? 0.95 : 0.1,
      );
      await pumpCard(tester, _clip(envelope: envelope), expanded: false);

      final bars = heights(tester);
      expect(bars, hasLength(SoundClip.waveformBarCount));
      expect(bars.reduce((a, b) => a > b ? a : b),
          greaterThan(bars.reduce((a, b) => a < b ? a : b)),
          reason: '包络有起伏时不应画成等高');
    });

    testWidgets('没有包络时画等高轨道', (tester) async {
      await pumpCard(tester, _clip(envelope: null), expanded: false);

      final bars = heights(tester);
      expect(bars, hasLength(SoundClip.waveformBarCount));
      expect(bars.toSet(), hasLength(1), reason: '没有测量就不该编一个形状');
    });
  });

  group('控制器', () {
    test('localUri 为空时 toggle 什么都不做', () async {
      final fake = _FakeClipAudioPlayer();
      final controller = ClipPlaybackController(fake);
      addTearDown(controller.dispose);

      await controller.toggle(_clip(localUri: null));

      expect(controller.playingClipId, isNull);
      expect(fake.loaded, isEmpty);
      expect(fake.playCalls, 0);
    });

    test('换一个片段播放会先停掉上一个', () async {
      final fake = _FakeClipAudioPlayer();
      final controller = ClipPlaybackController(fake);
      addTearDown(controller.dispose);

      await controller.toggle(_clip(id: 'a', localUri: 'a.wav'));
      expect(controller.playingClipId, 'a');

      await controller.toggle(_clip(id: 'b', localUri: 'b.wav'));
      expect(controller.playingClipId, 'b');
      expect(fake.loaded, ['a.wav', 'b.wav']);
      // 起播 a 前停一次、换台停 b 前再停一次。
      expect(fake.stopCalls, 2);
    });

    test('起播失败不会停在播放态，也不抛给调用方', () async {
      final fake = _FakeClipAudioPlayer()
        ..loadError = Exception('decode failed');
      final controller = ClipPlaybackController(fake);
      addTearDown(controller.dispose);

      await controller.toggle(_clip(localUri: 'bad.wav'));

      expect(controller.playingClipId, isNull);
      expect(controller.failed('c-1'), isTrue);
      expect(fake.playCalls, 0);
    });

    test('自然播完后回到未播放态', () async {
      final fake = _FakeClipAudioPlayer();
      final controller = ClipPlaybackController(fake);
      addTearDown(controller.dispose);

      await controller.toggle(_clip(localUri: 'c-1.wav'));
      expect(controller.playingClipId, 'c-1');

      fake.finish();
      await Future<void>.delayed(Duration.zero);

      expect(controller.playingClipId, isNull);
    });
  });
}
