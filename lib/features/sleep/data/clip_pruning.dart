import '../../../core/database/app_database.dart';
import '../domain/clip_journal.dart';
import '../domain/clip_retention.dart';
import 'clip_store.dart';
import 'session_repository.dart';

/// 默认保留最近 7 晚。按每晚安分大小约 15MB 估，量级在 100MB。
const kClipRetentionNights = 7;

/// 清理超出保留期限的录音文件。
///
/// **删文件、`localUri` 置空、行本身保留。** 这正是 `SoundClips.localUri` 列注释
/// 早就写好的语义：音频被裁掉之后事件记录还在，详情页如实显示「这段录音未保留在
/// 本地」，而不是那个片段凭空消失。波形也照旧画得出来——包络存在列里，不依赖文件。
///
/// 只动 `source = 'recording'` 的行；演示片段随演示数据一起清，不在这里管。
///
/// 返回清理掉的片段条数。
Future<int> pruneExpiredRecordings({
  required AppDatabase database,
  required ClipFileStore files,
  int keepNights = kClipRetentionNights,
}) async {
  final clips = await database.allRecordingClips();
  if (clips.isEmpty) return 0;

  final records = {
    for (final record in await database.allRecords()) record.id: record,
  };

  final ages = <ClipAge>[];
  for (final clip in clips) {
    // 已经没有文件的不用再裁一次——它上一次就被裁过了。
    if (clip.localUri == null) continue;
    final record = records[clip.recordId];
    // 记录不在了就交给孤儿清理，不从保留期限这边猜。
    if (record == null) continue;
    // 与记录归档同一口径：**用户醒来**那天的本地日历日。另起一套算法只会让
    // 「记录列表里还在、录音却按另一个夜晚被清了」这种自相矛盾有地方藏。
    ages.add(
      ClipAge(clipId: clip.id, archiveDay: record.endAtUtc.toLocal()),
    );
  }

  final expired = expiredClipIds(ages, keepNights: keepNights);
  if (expired.isEmpty) return 0;

  final expiredSet = expired.toSet();
  for (final clip in clips) {
    if (expiredSet.contains(clip.id)) {
      await files.deleteClip(clip.localUri);
    }
  }
  await database.clearClipLocalUris(expired);
  return expired.length;
}

/// 删掉既不在库里、也不在当前会话清单里的片段文件。
///
/// 库（连同会话行里的 `clipJournal`）是唯一真相来源。被杀之后重启、用户又把那次
/// 会话丢弃了，那些已经落盘但永远不会入库的文件就走这条路。
Future<void> deleteOrphanRecordings({
  required AppDatabase database,
  required ClipFileStore files,
}) async {
  final known = {
    for (final clip in await database.allRecordingClips()) clip.id,
  };
  final session = await SessionRepository(database).load();
  final pending = {
    for (final draft in session?.clipJournal ?? const <ClipDraft>[]) draft.id,
  };
  await files.deleteOrphans(knownIds: known, pendingIds: pending);
}

/// 删掉一条睡眠记录，**连同它名下的录音文件**。
///
/// 光删行是不够的：`sound_clips` 会跟着外键级联消失，而磁盘上的 WAV 一行代码都不碰。
/// 于是用户点完那个写着「声音事件都会被永久删除，此操作无法撤销」的确认框之后，
/// 音频还在盘上躺着，要等到**下一次冷启动**的 [deleteOrphanRecordings] 才被扫掉——
/// 在这中间它既不属于任何记录，也没人删得掉它。真机上实测到了这一串（见
/// `docs/verification-log.md` v3.19：9 条片段行全没了，9 个 WAV 一个不少）。
///
/// **顺序不能反**：文件路径要在 `deleteRecord` 之前读，级联一跑就再也问不出来了。
Future<void> deleteRecordWithRecordings({
  required AppDatabase database,
  required ClipFileStore files,
  required String recordId,
}) async {
  final uris = [
    for (final clip in await database.clipsFor(recordId)) clip.localUri,
  ];
  await database.deleteRecord(recordId);
  for (final uri in uris) {
    await files.deleteClip(uri);
  }
}

/// 「删除全部本地数据」：记录、阶段、片段行、洞察，**以及磁盘上的每一个录音文件**。
///
/// 比 [deleteRecordWithRecordings] 多一类要收拾的东西：**当前会话清单里那些还没入库
/// 的片段**。会话行会被 `deleteAllUserData` 删掉，清单随之消失，可那几段音频已经落盘
/// 了——不在这里一起删，它们就正好落进「谁也不认识」的缝里。
///
/// 先删库再删文件：文件删失败（[ClipFileStore.deleteClip] 会吞掉 `FileSystemException`）
/// 留下的是一个孤儿，下次冷启动会清掉；反过来先删文件，中途失败就会留下一行指着不存在
/// 文件的记录，那才是详情页会当场露馅的那种。
Future<void> deleteAllUserDataWithRecordings({
  required AppDatabase database,
  required ClipFileStore files,
}) async {
  final uris = <String?>[
    for (final clip in await database.allRecordingClips()) clip.localUri,
    for (final draft
        in (await SessionRepository(database).load())?.clipJournal ??
            const <ClipDraft>[])
      draft.localUri,
  ];
  await database.deleteAllUserData();
  for (final uri in uris) {
    await files.deleteClip(uri);
  }
}
