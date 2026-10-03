import 'dart:convert';

/// 会话进行中已经录完、但**还不能入库**的一段。
///
/// 入不了库的原因是结构性的：`SoundClips.recordId` 是指向 `SleepRecords` 的外键，
/// 而记录行要等用户按住「结束睡眠」才写。所以这些东西先以 JSON 待在会话行的
/// `clipJournal` 列里，结束时在同一个事务里落成真正的片段行。
///
/// 之所以不攒在内存里：`ActiveSessions` 那一行是**跨重启存活**的。攒内存的话，
/// App 被杀就等于整晚录音全丢，而用户重启之后照常能结束这一晚——那是最坏的一种
/// 失败形态：应用手里有过数据，却把它扔了。
class ClipDraft {
  const ClipDraft({
    required this.id,
    required this.startedAtUtc,
    required this.durationMs,
    required this.localUri,
    this.envelope,
  });

  final String id;
  final DateTime startedAtUtc;
  final int durationMs;

  /// 片段文件路径。写失败时为 `null`——那就只留事件行，不留音频。
  final String? localUri;

  /// 实测包络，长度恒为 `SoundClip.waveformBarCount`，元素在 0–1。
  final List<double>? envelope;

  Map<String, Object?> toJson() => {
        'id': id,
        'startedAtUtc': startedAtUtc.toUtc().toIso8601String(),
        'durationMs': durationMs,
        'localUri': localUri,
        if (envelope != null) 'envelope': envelope,
      };

  /// 读不出必须得到 `null` 而不是抛异常。
  ///
  /// 这一列是**进程被杀那一刻**的现场，写它的时候可能正写到一半；一行坏 JSON
  /// 不该让整个会话读不出来——那会连带把这一晚的睡眠记录一起弄丢。
  static ClipDraft? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final started = value['startedAtUtc'];
    final duration = value['durationMs'];
    if (id is! String || started is! String || duration is! int) return null;
    final parsed = DateTime.tryParse(started);
    if (parsed == null) return null;
    // **不能写成 `as String?`。** 那一句在遇到非字符串（半截写入、手工改坏）时会抛
    // `TypeError`，而那个异常**不在**下面 `jsonDecode` 的 try 里——它会一路穿过
    // `decodeClipJournal`、穿过 `SessionRepository.load()` 抛到调用方。冷启动那条
    // 路径是 `unawaited` 调的，于是当晚的会话直接读不出来，正是这个类开头承诺
    // 「一行坏数据不该让整个会话读不出来」要挡的事。
    final localUri = value['localUri'];
    final envelope = value['envelope'];
    return ClipDraft(
      id: id,
      startedAtUtc: parsed.toUtc(),
      durationMs: duration,
      localUri: localUri is String ? localUri : null,
      envelope: envelope is List
          ? [
              for (final bar in envelope)
                if (bar is num) bar.toDouble(),
            ]
          : null,
    );
  }
}

/// 把片段清单编成 `clipJournal` 列里的那种字符串。
String encodeClipJournal(List<ClipDraft> drafts) =>
    jsonEncode([for (final draft in drafts) draft.toJson()]);

/// 解回来。整段读不出来就得到空清单；单条读不出来就跳过那一条。
List<ClipDraft> decodeClipJournal(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return const [];
  }
  if (decoded is! List) return const [];
  return [
    for (final entry in decoded)
      if (ClipDraft.fromJson(entry) case final draft?) draft,
  ];
}
