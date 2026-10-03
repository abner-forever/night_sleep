import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/app/night_recording.dart';
import 'package:night_sleep/core/database/app_database.dart';
import 'package:night_sleep/features/sleep/data/clip_store.dart';
import 'package:night_sleep/features/sleep/data/night_recorder.dart';
import 'package:night_sleep/features/sleep/data/session_repository.dart';
import 'package:night_sleep/features/sleep/domain/clip_journal.dart';

/// 假录音服务：测试自己决定什么时候「录完一段」。
class _FakeNightRecorder implements NightRecorder {
  final _status = ValueNotifier(
    const NightRecordingStatus(NightRecordingState.idle),
  );
  final _clips = StreamController<ClipDraft>.broadcast(sync: true);

  int startCount = 0;
  int stopCount = 0;
  int permissionCalls = 0;
  bool permission = true;
  bool failStart = false;

  /// 记录调用次序，「白噪音优先」那一条是靠它断言的。
  final List<String> calls = [];

  @override
  ValueListenable<NightRecordingStatus> get status => _status;

  @override
  Stream<ClipDraft> get closedClips => _clips.stream;

  void emitClip(ClipDraft draft) => _clips.add(draft);

  @override
  Future<bool> ensurePermission() async {
    permissionCalls++;
    return permission;
  }

  @override
  Future<void> start() async {
    calls.add('start');
    startCount++;
    if (failStart) throw StateError('麦克风被占用');
    _status.value = const NightRecordingStatus(NightRecordingState.recording);
  }

  /// 让 `stop()` 在收尾时吐出最后一段——真实实现就是这么干的（`_flush()`）。
  /// 「丢弃那一晚」的用例靠它复现「收尾那一段赶不上被删」。
  ClipDraft? emitOnStop;

  @override
  Future<void> stop() async {
    calls.add('stop');
    stopCount++;
    if (emitOnStop case final draft?) {
      emitOnStop = null;
      _clips.add(draft);
    }
    _status.value = const NightRecordingStatus(NightRecordingState.idle);
  }

  @override
  Future<void> dispose() async {
    await _clips.close();
    _status.dispose();
  }
}

void main() {
  late AppDatabase database;
  late Directory tempDir;
  late ClipFileStore files;
  late _FakeNightRecorder recorder;
  late ValueNotifier<bool> noisePlaying;
  late bool recordingEnabled;
  late NightRecordingController controller;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    tempDir = await Directory.systemTemp.createTemp('session_recording');
    files = ClipFileStore(baseDirectory: () async => tempDir);
    recorder = _FakeNightRecorder();
    noisePlaying = ValueNotifier(false);
    recordingEnabled = true;
    controller = NightRecordingController(
      repository: SessionRepository(database),
      recorder: recorder,
      files: files,
      noisePlaying: noisePlaying,
      recordingEnabled: () async => recordingEnabled,
    );
  });

  tearDown(() async {
    controller.dispose();
    await recorder.dispose();
    noisePlaying.dispose();
    await database.close();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  /// 开一个会话，并给里面塞一条片段清单——模拟「录了一晚，App 被杀过」。
  Future<void> startSession({List<ClipDraft> journal = const []}) async {
    final repo = SessionRepository(database);
    await repo.start(now: DateTime.utc(2026, 10, 3, 22), wakeMinutes: 420);
    if (journal.isNotEmpty) await repo.update(clipJournal: journal);
  }

  ClipDraft draft(String id, {String? localUri}) => ClipDraft(
        id: id,
        startedAtUtc: DateTime.utc(2026, 10, 4, 1),
        durationMs: 4200,
        localUri: localUri,
        envelope: const [0.2, 0.8],
      );

  group('会话结束时把片段落成真正的行', () {
    test('清单里的片段写进 sound_clips，recordId 指向新记录', () async {
      await startSession(journal: [draft('clip-a'), draft('clip-b')]);

      await SessionRepository(database).finish(
        now: DateTime.utc(2026, 10, 4, 7),
        quality: null,
      );

      final records = await database.allRecords();
      expect(records, hasLength(1));
      final clips = await database.allClipsByRecord();

      // 变异验证：把 `finish()` 里读清单那一步挪到 `deleteActiveSession()` 之后，
      // 这里立刻变成空表——清单跟着会话行一起没了。
      expect(clips[records.single.id], hasLength(2));
      expect(
        clips[records.single.id]!.map((row) => row.id),
        containsAll(['clip-a', 'clip-b']),
      );
      // 初值是中性的占位 `noise`：这一段确实有声响，但还不能说是鼾声还是梦话。
      expect(clips[records.single.id]!.every((row) => row.kind == 'noise'),
          isTrue);
      expect(
        clips[records.single.id]!.first.waveformEnvelope,
        '[0.2,0.8]',
      );
    });

    test('清单为空时行为与从前一样：一条片段行都不写', () async {
      await startSession();

      await SessionRepository(database).finish(
        now: DateTime.utc(2026, 10, 4, 7),
        quality: null,
      );

      expect(await database.allClipsByRecord(), isEmpty);
    });
  });

  group('白噪音优先', () {
    test('白噪音在播时不开始录，停了才开始', () async {
      noisePlaying.value = true;
      await startSession();

      await controller.syncWithSession();
      expect(recorder.startCount, 0, reason: '白噪音在播时不该开麦克风');
      expect(controller.status.state, NightRecordingState.waitingForNoise);

      noisePlaying.value = false;
      await Future<void>.delayed(Duration.zero);

      expect(recorder.startCount, 1);
      expect(controller.status.isRecording, isTrue);
    });

    test('开关关着时不起录', () async {
      recordingEnabled = false;
      await startSession();

      await controller.syncWithSession();

      expect(recorder.startCount, 0);
    });

    test('没有麦克风权限时不去开一个注定失败的麦克风', () async {
      recorder.permission = false;
      await startSession();

      await controller.syncWithSession();

      // 变异验证：把 `_reconcile` 里那道 `ensurePermission()` 闸口去掉，
      // `startCount` 会变成 1——用户会拿到一条平台抛回来的原始报错。
      expect(recorder.permissionCalls, greaterThan(0));
      expect(recorder.startCount, 0, reason: '没权限就别去开麦');
      // 状态仍是「没在录」——界面据此如实显示，不许谎称在录。
      expect(controller.status.isRecording, isFalse);
    });

    test('没有会话时不起录', () async {
      await controller.syncWithSession();
      expect(recorder.startCount, 0);
    });
  });

  group('片段清单跟着会话行走', () {
    test('每录完一段就写回会话行', () async {
      await startSession();
      await controller.syncWithSession();

      recorder.emitClip(draft('clip-x'));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final session = await SessionRepository(database).load();
      expect(session!.clipJournal.map((d) => d.id), ['clip-x']);
    });

    test('进程被杀之后重启，清单仍在会话行里', () async {
      // 上一次人生里录到的一段。
      await startSession(journal: [draft('clip-before-kill')]);

      await controller.syncWithSession();

      expect(controller.clipCount, 1);
      final session = await SessionRepository(database).load();
      expect(session!.clipJournal.single.id, 'clip-before-kill');
    });

    test('收尾时最后一段必须已经落库——finish 读的就是它', () async {
      await startSession();
      await controller.syncWithSession();

      // 模拟「stop() 收尾时吐出最后一段」：先发片段，再调 stopForSessionEnd。
      recorder.emitClip(draft('clip-last'));
      await controller.stopForSessionEnd();

      final session = await SessionRepository(database).load();
      expect(
        session!.clipJournal.map((d) => d.id),
        contains('clip-last'),
        reason: '最后一段没赶上这趟车的话，一次会话只有一段时就等于全丢',
      );
      expect(recorder.stopCount, greaterThan(0));
    });
  });

  group('丢弃', () {
    test('丢掉这一晚时，已经录到的文件一并删掉', () async {
      final path = await files.pathFor('clip-gone');
      await File(path).writeAsBytes(List<int>.filled(128, 0));
      await startSession(journal: [draft('clip-gone', localUri: path)]);

      await controller.discardRecordings();

      expect(File(path).existsSync(), isFalse, reason: '丢弃的会话不该留下音频');
      expect(recorder.stopCount, greaterThan(0));
    });

    test('收尾那一刻才定案的片段，它的文件也要删掉', () async {
      // 真实形态：还在录的那一段是在 `stop()` 里才被收尾、才落盘的。
      await startSession();
      await controller.syncWithSession();

      final path = await files.pathFor('clip-last-moment');
      await File(path).writeAsBytes(List<int>.filled(128, 0));
      recorder.emitOnStop = draft('clip-last-moment', localUri: path);

      await controller.discardRecordings();

      // 变异验证：把 `discardRecordings` 改成「先取清单快照、再 stop」，
      // 这一条立刻变红——那一段的文件会留到下次启动的孤儿清理才被扫掉。
      expect(File(path).existsSync(), isFalse,
          reason: '收尾吐出来的那一段同样是这一晚的音频，丢掉就该一起删');
    });
  });

  group('删除全部录音', () {
    test('把当前会话清单里的文件指针一并清空，条目留着', () async {
      final path = await files.pathFor('clip-wiped');
      await startSession(journal: [draft('clip-wiped', localUri: path)]);
      await controller.syncWithSession();

      await controller.forgetRecordings();

      final session = await SessionRepository(database).load();
      expect(session!.clipJournal, hasLength(1), reason: '事件记录本身不该消失');
      expect(session.clipJournal.single.id, 'clip-wiped');
      // 变异验证：不清指针的话，这一晚结束时会写进一条声称「可回放」的片段行，
      // 而它的文件已经被用户删掉了。
      expect(session.clipJournal.single.localUri, isNull);
    });
  });

  group('删除全部本地数据', () {
    test('会话被从别处删掉之后，白噪音一停也不会把录音又启起来', () async {
      noisePlaying.value = true;
      await startSession();
      await controller.syncWithSession();
      expect(recorder.startCount, 0);

      // 设置页那条路径：删掉全部数据，然后 `teardownSession` 停白噪音。
      await database.deleteAllUserData();
      noisePlaying.value = false;
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // 变异验证：把 `_reconcile` 里那次 `_repository.load()` 换成信 `_sessionActive`
      // 这个内存标记，这里会变成 1——删完全部数据、白噪音一停，录音反而被启起来。
      expect(recorder.startCount, 0);
    });
  });
}
