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
