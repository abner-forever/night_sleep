import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart' as db;
import '../domain/clip_journal.dart';
import '../domain/sleep_quality.dart';
import '../domain/sleep_session.dart';
import '../domain/sound_event.dart';

/// 活跃睡眠会话的读写。
///
/// 会话只活一行（主键固定 `'active'`，见 `ActiveSessions` 的注释），所以这里的
/// 每一个动作都是「最多一行」的语义，不需要任何判重。
class SessionRepository {
  SessionRepository(this._db);

  final db.AppDatabase _db;

  /// 默认起床时间 07:00。用户没设过起床提醒时用它。
  ///
  /// 设置页显示的是同一个默认值（`SettingsPage.defaultWakeMinutes`）。数据层不能
  /// 反向依赖界面层，所以这里只能各留一份常量——**改一处必须同步另一处**，否则
  /// 会出现「界面显示 07:00、库里是 06:00」这种只在特定操作后才显形的问题。
  static const defaultWakeMinutes = 7 * 60;

  static const sessionId = 'active';

  Future<SleepSession?> load() async {
    final row = await _db.activeSession();
    return row == null ? null : _toSession(row);
  }

  /// 开始一个会话。已有一个在跑时**直接覆盖**它——那意味着用户又按了一次
  /// 「开始睡眠」，按新的开始时刻重新计时才是他的意思。
  ///
  /// 场景 / 白噪音 / 音量 / 闹钟这几项是 setup 态攒下的草稿，**一次写全**。不这么写就得
  /// `start()` 之后再补几笔 `update()`，中间那一瞬库里写着「没在放音」而播放器已经在响
  /// ——那是个假值（`NoiseSessionController` 的冷启动对账清的就是这一类）。
  Future<SleepSession> start({
    DateTime? now,
    int? wakeMinutes,
    bool alarmEnabled = false,
    String? sceneId,
    String? noiseId,
    double? noiseVolume,
  }) async {
    final at = (now ?? DateTime.now()).toUtc();
    final resolvedWake = wakeMinutes ?? await _defaultWakeMinutes();

    await _db.saveActiveSession(
      db.ActiveSessionsCompanion.insert(
        id: sessionId,
        startAtUtc: at,
        timeZoneId: Value((now ?? DateTime.now()).timeZoneName),
        wakeMinutes: resolvedWake,
        alarmEnabled: Value(alarmEnabled),
        noiseId: Value(noiseId),
        // 与列默认值一致：不传音量时写 0.5，不留给列默认去补——一次 insert 里
        // 显式给出全部字段，读回来才不会有一半是「没写」。
        noiseVolume: Value(noiseVolume ?? 0.5),
        sceneId: Value(sceneId),
        createdAt: at,
      ),
    );

    return (await load())!;
  }

  Future<int> _defaultWakeMinutes() async {
    final stored = await _db.getSettings();
    return stored.wakeReminderMinutes ?? defaultWakeMinutes;
  }

  /// 只改传入的字段。`noiseId` 与 `sceneId` 显式传 `null` 表示清成默认/取消选择。
  Future<void> update({
    int? wakeMinutes,
    bool? alarmEnabled,
    Object? noiseId = _unset,
    double? noiseVolume,
    Object? sceneId = _unset,
    List<ClipDraft>? clipJournal,
  }) async {
    await _db.updateActiveSession(
      db.ActiveSessionsCompanion(
        wakeMinutes:
            wakeMinutes == null ? const Value.absent() : Value(wakeMinutes),
        alarmEnabled:
            alarmEnabled == null ? const Value.absent() : Value(alarmEnabled),
        noiseId: identical(noiseId, _unset)
            ? const Value.absent()
            : Value(noiseId as String?),
        noiseVolume:
            noiseVolume == null ? const Value.absent() : Value(noiseVolume),
        sceneId: identical(sceneId, _unset)
            ? const Value.absent()
            : Value(sceneId as String?),
        clipJournal: clipJournal == null
            ? const Value.absent()
            : Value(encodeClipJournal(clipJournal)),
      ),
    );
  }

  /// 结束会话：**一个事务**里写记录 + 删会话行。
  ///
  /// 会话**不产生阶段**。`sleep_stage_segments` 里每一行都必须来自一次真实测量
  /// （设备导入），这张表本来就没有任何阶段可写——不是「这次先空着」，而是
  /// 「凭空造一条阶段曲线」这件事本身就不允许。所以这里直接插记录行，不绕道
  /// `SleepRepository.save()`（那条路子上的 `stages` 参数在这里没有意义）。
  ///
  /// 调用方必须先过 [validateSessionDuration]。这里再挡一道，因为「静默写出
  /// 一条 71 小时的睡眠记录」是这个功能最坏的失败形态。
  /// 返回新记录行的 id。
  ///
  /// **返回它而不是让调用方自己算**：id 是 `endAt.microsecondsSinceEpoch`，调用方
  /// 重算一次就多一处会对不上的地方——而结束会话之后紧接着就要拿这个 id 去触发
  /// 那一晚的片段分析（见 `sleep_session_page._finish`）。
  Future<String> finish(
      {required DateTime now, required SleepQuality? quality}) async {
    final session = await load();
    if (session == null) {
      throw StateError('没有正在进行的会话，无法结束');
    }

    final endAt = now.toUtc();
    final rejection =
        validateSessionDuration(endAt.difference(session.startAtUtc));
    if (rejection != SessionFinishRejection.none) {
      throw StateError('会话时长不合法：$rejection');
    }

    final id = endAt.microsecondsSinceEpoch.toString();
    final stamp = DateTime.now().toUtc();

    // 整晚录到的片段就在会话行里躺着（`clipJournal`），这里把它们落成真正的
    // `SoundClips` 行——**必须和记录行在同一个事务里**，也必须**在删会话行之前**
    // 读出来，否则清单随那一行一起消失，整晚录音白录。
    final clips = [
      for (final draft in session.clipJournal)
        db.SoundClipsCompanion.insert(
          id: draft.id,
          recordId: id,
          // 中性的占位值：这一段确实有声响，但还不能说是鼾声还是梦话。
          // 界面据此把未标注的显示成「待标注」，而不是「杂音」。
          kind: SoundEventKind.noise.id,
          startedAtUtc: draft.startedAtUtc,
          durationMs: draft.durationMs,
          localUri: Value(draft.localUri),
          waveformEnvelope: Value(
            draft.envelope == null ? null : jsonEncode(draft.envelope),
          ),
          source: const Value('recording'),
        ),
    ];

    await _db.transaction(() async {
      await _db.saveRecord(
        db.SleepRecordsCompanion.insert(
          id: id,
          startAtUtc: session.startAtUtc,
          endAtUtc: endAt,
          timeZoneId: Value(session.timeZoneId),
          quality: Value(quality?.value),
          source: const Value('session'),
          createdAt: stamp,
          updatedAt: stamp,
        ),
      );
      await _db.insertClips(clips);
      await _db.deleteActiveSession();
    });
    return id;
  }

  /// 丢弃这次会话。不写任何记录——「忘了结束、放了三天」的会话走这里。
  Future<void> discard() => _db.deleteActiveSession();

  /// drift 在原生执行器上按 unix 秒存 DateTime，读回来的是**标记为本地时区**的
  /// `DateTime`（`test/schema_migration_test.dart` 里记过同一个坑）。`SleepSession`
  /// 的字段叫 `startAtUtc` / `createdAtUtc`，所以这里把标记摆正——瞬时值不变，
  /// 变的只是 `DateTime.==` 会一并比较的那个标记。不做这一步的话，同一个时刻
  /// 「从库里读出来」与「刚构造出来」会不相等。
  SleepSession _toSession(db.ActiveSession row) => SleepSession(
        startAtUtc: row.startAtUtc.toUtc(),
        timeZoneId: row.timeZoneId,
        wakeMinutes: row.wakeMinutes,
        alarmEnabled: row.alarmEnabled,
        sceneId: row.sceneId,
        noiseId: row.noiseId,
        noiseVolume: row.noiseVolume,
        clipJournal: decodeClipJournal(row.clipJournal),
        createdAtUtc: row.createdAt.toUtc(),
      );

  static const _unset = Object();
}

final sessionRepositoryProvider = Provider<SessionRepository>((ref) {
  return SessionRepository(ref.watch(db.databaseProvider));
});

/// 当前会话，没有则为 `null`。UI 读它来决定首页显示「开始睡眠」还是「正在睡眠」。
final activeSessionProvider = FutureProvider<SleepSession?>((ref) async {
  // 会话表一变就重读，与 `sleepEntriesProvider` 同一手法。
  ref.watch(db.activeSessionWatchProvider);
  return ref.watch(sessionRepositoryProvider).load();
});
