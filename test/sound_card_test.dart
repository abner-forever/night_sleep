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
import 'package:night_sleep/features/sleep/domain/clip_analysis.dart';
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
  AutoAnalysis? autoAnalysis,
  // 默认仍是 `pending`：不给 `autoAnalysis` 的 `_clip()` 要真的是一条
  // 「从没分析过」的记录，而不是一个「分析过却没留下 payload」的不可能状态。
  SoundAnalysisStatus analysisStatus = SoundAnalysisStatus.pending,
}) {
  return SoundClip(
    id: id,
    kind: kind,
    startedAtUtc: DateTime.utc(2026, 10, 4, 1),
    durationMs: durationMs,
    localUri: localUri,
    waveformEnvelope: envelope,
    labeledAtUtc: labeledAtUtc,
    analysisStatus: analysisStatus,
    autoAnalysis: autoAnalysis,
  );
}

/// 一条「机器判出来了」的记录。
///
/// 默认 `basis` 是**模型分**的写法（2026-10-16 起判定由 YAMNet 给出）。默认
/// `startMs` / `durationMs` 为 0——**新判定不带区间**；需要区间的用例显式传，
/// 那钉的是「旧记录还读得回来」。
AutoAnalysis _auto(
  AutoLabel? label, {
  String basis = 'YAMNet 鼾声分 0.85 · 人声分 0.02（整段 8 个窗口均分，判定线 0.40）',
  int startMs = 0,
  int durationMs = 0,
}) {
  return AutoAnalysis(
    verdict: label == null
        ? null
        : AutoVerdict(
            label: label,
            margin: 0.5,
            basis: basis,
            startMs: startMs,
            durationMs: durationMs,
          ),
    analyzedAtUtc: DateTime.utc(2026, 10, 14, 8),
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

  group('机器判断：三态', () {
    testWidgets('机器有把握时标题写「自动 · 疑似打鼾」，且不再说「待标注」', (tester) async {
      await pumpCard(tester, _clip(autoAnalysis: _auto(AutoLabel.snore)));

      expect(find.text('自动 · 疑似打鼾'), findsOneWidget);
      expect(find.text('待标注'), findsNothing);
      // 「打鼾」只能作为「自动 · 疑似打鼾」的一部分出现，**不能**单独出现——
      // 单独出现就等于把机器的猜测说成一个人的判断。三选一的 chip 上那个「打鼾」
      // 是选项文案，所以这里数的是标题那一处。
      expect(find.text('打鼾'), findsOneWidget);
    });

    testWidgets('机器弃权（看过但没把握）仍然显示「待标注」', (tester) async {
      // 变异：把 `labelText` 里「机器没把握」那一支改成回退到 kind.label，
      // 本用例变红——那一晚的片段会全部显示成「杂音」，一个没做过的判断。
      await pumpCard(tester, _clip(autoAnalysis: _auto(null)));

      expect(find.text('待标注'), findsOneWidget);
    });

    testWidgets('从没分析过也显示「待标注」——与机器弃权在界面上同样诚实', (tester) async {
      await pumpCard(tester, _clip());

      expect(find.text('待标注'), findsOneWidget);
    });

    testWidgets('人标的永远压过机器判断', (tester) async {
      await pumpCard(
        tester,
        _clip(
          kind: SoundEventKind.talk,
          labeledAtUtc: DateTime.utc(2026, 10, 4, 8),
          autoAnalysis: _auto(AutoLabel.snore),
        ),
      );

      expect(find.text('梦话'), findsWidgets);
      expect(find.textContaining('自动'), findsNothing);
    });

    testWidgets('展开后给出实测依据，而不是一个「把握」', (tester) async {
      await pumpCard(
        tester,
        _clip(
          autoAnalysis: _auto(AutoLabel.snore, basis: '低频能量 66% · 谱质心 390 Hz'),
        ),
      );

      expect(find.text('自动判断依据'), findsOneWidget);
      expect(find.text('低频能量 66% · 谱质心 390 Hz'), findsOneWidget);
      // 没有标注数据就估不出概率；界面上不许出现一个编出来的「置信度」。
      expect(find.textContaining('置信'), findsNothing);
      expect(find.textContaining('把握度'), findsNothing);
    });

    testWidgets('机器判「杂音」时说「自动 · 杂音」，不与「待标注」混为一谈', (tester) async {
      // 两者都是「没测到鼾声也没测到人声」，但一个是**搜过之后的结论**，
      // 一个是**没有结论**。混成一句话就把机器的搜索结果抹掉了。
      await pumpCard(tester, _clip(autoAnalysis: _auto(AutoLabel.noise)));

      expect(find.text('自动 · 杂音'), findsOneWidget);
      expect(find.text('待标注'), findsNothing);
    });

    testWidgets('旧记录带着起止时，那一对秒数照样摆出来', (tester) async {
      // 2026-10-16 之前那套判定确实找过事件，库里存着它的区间。换引擎不该让
      // 那些记录读不回来——所以这条钉的是**旧记录仍然显示得出来**，而不是新判定
      // 会产出区间（新判定恒为 0，见下一条）。
      await pumpCard(
        tester,
        _clip(
          durationMs: 11800,
          autoAnalysis: _auto(AutoLabel.snore, startMs: 300, durationMs: 6300),
        ),
      );

      expect(find.text('第 0.3–6.6 秒'), findsOneWidget);
    });

    testWidgets('新判定没有区间，**不许**画出「第 0.0–0.0 秒」', (tester) async {
      // YAMNet 按整段给结论，`durationMs` 恒为 0。少了这道守卫，每一段新判定都会
      // 多出一行「第 0.0–0.0 秒」——一个凭空画出来的、没有任何测量支撑的区间。
      await pumpCard(
        tester,
        _clip(durationMs: 11800, autoAnalysis: _auto(AutoLabel.snore)),
      );

      expect(find.text('自动 · 疑似打鼾'), findsOneWidget);
      expect(find.textContaining('YAMNet'), findsOneWidget,
          reason: '依据那一行还是要摆的，只是不带区间');
      expect(find.textContaining('秒', findRichText: false), findsNothing);
    });

    testWidgets('「杂音」没有事件可指，就不摆秒数', (tester) async {
      await pumpCard(
        tester,
        _clip(durationMs: 10300, autoAnalysis: _auto(AutoLabel.noise)),
      );

      expect(find.textContaining('秒', findRichText: false), findsNothing);
    });

    testWidgets('机器没有结论时，展开区明说看过、但没有读到可判定的声音', (tester) async {
      // 标题上「没有结论」与「从没分析过」都是「待标注」，展开区再不多说一句，
      // 用户点完「重新分析」看到的就是一个什么都没变的界面——2026-10-16 使用方
      // 报的正是这个。2026-10-18 起有声音的片段一定有结论，这一支只剩数字静音
      // 与空输入，但「别沉默」这条要求没变。
      await pumpCard(
        tester,
        _clip(
            autoAnalysis: _auto(null),
            analysisStatus: SoundAnalysisStatus.analysed),
      );

      expect(find.textContaining('机器看过这段'), findsOneWidget);
      expect(find.textContaining('没有读到可判定的声音'), findsOneWidget);
      // 没有结论时不许摆「自动判断依据」。
      expect(find.text('自动判断依据'), findsNothing);
      expect(find.text('待标注'), findsOneWidget);
    });

    testWidgets('分析失败与弃权分得开：失败说读不出来，且不假装机器看过', (tester) async {
      await pumpCard(
        tester,
        _clip(analysisStatus: SoundAnalysisStatus.failed),
      );

      expect(find.textContaining('没能分析这段'), findsOneWidget);
      expect(find.textContaining('机器看过这段'), findsNothing);
    });

    testWidgets('有判断时不摆那一行——上面已经有依据了', (tester) async {
      await pumpCard(tester, _clip(autoAnalysis: _auto(AutoLabel.snore)));

      expect(find.textContaining('机器看过这段'), findsNothing);
      expect(find.textContaining('没能分析这段'), findsNothing);
    });

    testWidgets('从没分析过时不摆那一行——展开区末尾本来就有一句', (tester) async {
      await pumpCard(tester, _clip());

      expect(find.textContaining('机器看过这段'), findsNothing);
      expect(find.text('尚未分析这段录音，因此没有转录或洞察。'), findsOneWidget);
    });

    testWidgets('用户改标之后，那一行也跟着退出显示', (tester) async {
      await pumpCard(
        tester,
        _clip(
          labeledAtUtc: DateTime.utc(2026, 10, 4, 8),
          analysisStatus: SoundAnalysisStatus.analysed,
          autoAnalysis: _auto(null),
        ),
      );

      expect(find.textContaining('机器看过这段'), findsNothing);
    });

    testWidgets('用户改标之后，机器判断退出显示但记录仍在库里', (tester) async {
      await seedClip('c-1', kind: 'noise');
      await database.updateClipAutoAnalysis(
        'c-1',
        payload: _auto(AutoLabel.snore).encode(),
        status: 'analysed',
      );

      await pumpCard(tester, _clip(autoAnalysis: _auto(AutoLabel.snore)));
      expect(find.text('自动 · 疑似打鼾'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('clip-label-noise')));
      await tester.pumpAndSettle();

      // 显示层让位于人：标题变成「杂音」，不再提「自动」。
      expect(find.textContaining('自动'), findsNothing);

      // 但机器当初那条判断仍留在库里——它是一条「机器看到的是这个」的记录，
      // 不该因为人改了口就被抹掉。
      final rows = await database.allRecordingClips();
      expect(rows.single.autoAnalysis, isNotNull);
      expect(rows.single.kind, 'noise');
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
