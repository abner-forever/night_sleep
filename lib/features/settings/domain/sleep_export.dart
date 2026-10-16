import 'dart:convert';

import '../../../core/config/app_config.dart';
import '../../sleep/domain/sleep_entry.dart';
import '../../sleep/domain/sleep_insight.dart';
import '../../sleep/domain/sleep_stage.dart';

/// 一份交给分享面板的文件。
class ExportFile {
  const ExportFile({
    required this.fileName,
    required this.content,
    required this.mimeType,
  });

  final String fileName;
  final String content;
  final String mimeType;
}

/// CSV 的两张表。界面上的分段控件按它分栏。
enum ExportTableKind {
  records('记录'),
  stages('阶段');

  const ExportTableKind(this.label);

  final String label;
}

/// 一张导出表：文件名、表头，以及**已按 CSV 规则渲染成字符串**的行。
///
/// 导出页的表格预览读的就是它，而 `csv()` 只是它的序列化。单元格的生成因此只有
/// `SleepExporter.tables()` 这一处——预览里看到的每一格与文件里的那一格必然相同，
/// 不会出现「照着 CSV 的规则又渲染了一遍」那种两份格式知识各自漂移的局面。
class ExportTable {
  const ExportTable({
    required this.kind,
    required this.fileName,
    required this.header,
    required this.rows,
  });

  final ExportTableKind kind;
  final String fileName;
  final List<String> header;

  /// 与表头等长的行；每格是最终写进文件的文本（引号由序列化那一步加）。
  final List<List<String>> rows;

  int get rowCount => rows.length;
}

/// 把用户自己的记录变成导出内容。
///
/// **纯函数**：没有数据库、没有插件、也没有自己的时钟（`now` 由调用方传入）。
/// 因此下面每一条格式规则都能在单元测试里逐字节断言，格式的知识也就只有这一处。
abstract final class SleepExporter {
  static const csvMime = 'text/csv';
  static const jsonMime = 'application/json';

  /// Excel 只在文件开头见到 BOM 时才按 UTF-8 解码；没有它就是乱码，
  /// 用户看到的是「导出坏了」。
  ///
  /// 写成转义而不是直接嵌一个字面量：U+FEFF 在 diff 里是不可见的，
  /// 而它一旦丢失，失败方式正是「中文静默变成乱码」这种最难发现的一种。
  static const _bom = '\uFEFF';

  /// RFC 4180 的行结束符。Excel 是这里最严格的消费方。
  static const _eol = '\r\n';

  static const _recordHeader = [
    '日期', '入睡时刻', '醒来时刻', '时区', '时长(小时)', '时长(分钟)', //
    '质量', '打鼾', '梦话', '辗转', '噩梦', '备注', '来源', '记录ID', //
    '最初记录时间', '最后修改时间',
  ];

  static const _stageHeader = ['记录ID', '阶段', '开始时间', '结束时间', '时长(分钟)', '来源'];

  /// 允许离开应用的那部分记录：除演示数据之外的全部，按入睡时刻**升序**。
  ///
  /// 演示之夜从阶段到转写全是合成的，写进用户的备份就是把伪造数据掺进真实数据——
  /// 与「演示数据不可编辑」「演示数据只在 DEMO_DATA 下安装」是同一条原则。
  ///
  /// 排序放在这里，而不是沿用调用方给的顺序：`sleepEntriesProvider` 给的是**倒序**
  /// （界面要最新在前）。让导出格式继承它，等于把导出和界面隐式绑在一起——将来
  /// `SleepRepository.loadAll()` 一改排序，导出的文件会静默跟着变。显式排序断开这个
  /// 耦合，也让表格软件里按时间轴自然展开。排序是**全序**（同一时刻按 id 兜底），
  /// 因此同一份数据无论排几次都得到同一个文件。
  static List<SleepEntry> exportableOf(List<SleepEntry> entries) {
    final exportable =
        entries.where((e) => e.source != AppConfig.demoSource).toList();
    exportable.sort((a, b) {
      final byStart = a.startAtUtc.compareTo(b.startAtUtc);
      // 入睡时刻相同的两条（同一早上补录两次就会这样）用 id 兜底定序。
      // 只按时间排时它们的先后是**未定义**的，而预览页与文件是两次独立的排序调用
      // ——未定义就意味着两者可能不一致，正好破坏「预览与文件逐格相同」这条承诺。
      return byStart != 0 ? byStart : a.id.compareTo(b.id);
    });
    return exportable;
  }

  /// 两张表：记录一行一晚，阶段一行一段。
  ///
  /// 阶段不压成「深睡/浅睡/REM 分钟」三列：分段的时间戳是阶段图的唯一来源，
  /// 压成合计就回不来了。
  ///
  /// 它是导出内容的**唯一**产地：文件名、表头、每一格都在这里定下来，
  /// `csv()` 与界面上的表格预览都只是读它。
  static List<ExportTable> tables(
    List<SleepEntry> entries, {
    required DateTime now,
  }) {
    final exportable = exportableOf(entries);
    final stamp = _dateStamp(now);

    return [
      ExportTable(
        kind: ExportTableKind.records,
        fileName: '夜深-睡眠记录-$stamp.csv',
        header: _recordHeader,
        rows: [
          for (final entry in exportable) _recordRow(entry),
        ],
      ),
      ExportTable(
        kind: ExportTableKind.stages,
        fileName: '夜深-睡眠阶段-$stamp.csv',
        header: _stageHeader,
        rows: [
          for (final entry in exportable)
            for (final segment in entry.stages) _stageRow(entry.id, segment),
        ],
      ),
    ];
  }

  /// 把 [tables] 序列化成两份 CSV 文件。
  static List<ExportFile> csv(
    List<SleepEntry> entries, {
    required DateTime now,
  }) =>
      [
        for (final table in tables(entries, now: now))
          ExportFile(
            fileName: table.fileName,
            mimeType: csvMime,
            content: _table(table.header, table.rows),
          ),
      ];

  /// 完整嵌套的一份存档。
  ///
  /// 字段名与 schema 对齐、时间戳写 ISO-8601 UTC，为将来做回灌留路。
  /// **不写派生值**（时长、阶段合计、占比）：规格已定「时长派生不存储」，
  /// 存档里塞一份派生快照只会多一个会过期的事实。
  static List<ExportFile> json(
    List<SleepEntry> entries, {
    required DateTime now,
  }) {
    final exportable = exportableOf(entries);
    final document = <String, Object?>{
      'format': 'night-sleep-export',
      'version': 1,
      'exportedAtUtc': now.toUtc().toIso8601String(),
      'schemaVersion': 2,
      'recordCount': exportable.length,
      'excludedDemoCount': entries.length - exportable.length,
      'records': [for (final entry in exportable) _record(entry)],
    };

    return [
      ExportFile(
        fileName: '夜深-睡眠数据-${_dateStamp(now)}.json',
        mimeType: jsonMime,
        content: const JsonEncoder.withIndent('  ').convert(document),
      ),
    ];
  }

  static Map<String, Object?> _record(SleepEntry entry) => {
        'id': entry.id,
        'startAtUtc': _iso(entry.startAtUtc),
        'endAtUtc': _iso(entry.endAtUtc),
        'timeZoneId': entry.timeZoneId,
        'quality': entry.quality?.value, // JSON：未评分写 null，不写占位值
        'notes': entry.notes,
        'tags': entry.tags,
        'source': entry.source,
        'loggedEvents': {
          'snore': entry.loggedEvents.snore,
          'talk': entry.loggedEvents.talk,
          'restless': entry.loggedEvents.restless,
          'nightmare': entry.loggedEvents.nightmare,
        },
        'createdAtUtc': _iso(entry.createdAtUtc),
        'updatedAtUtc': _iso(entry.updatedAtUtc),
        'stages': [
          for (final segment in entry.stages)
            {
              'stage': segment.stage.id,
              'startAtUtc': _iso(segment.startAtUtc),
              'endAtUtc': _iso(segment.endAtUtc),
              'source': segment.source,
            },
        ],
        'soundClips': [
          for (final clip in entry.soundClips)
            {
              'id': clip.id,
              'kind': clip.kind.id,
              'startedAtUtc': _iso(clip.startedAtUtc),
              'durationMs': clip.durationMs,
              // 只留布尔量。绝对路径含设备容器的 UUID，而音频本身不进导出，
              // 留着既悬空、又把设备本地细节捎了出去。
              'hasLocalAudio': clip.localUri != null,
              'transcript': clip.transcript,
              'analysis': clip.analysis,
              'analysisStatus': clip.analysisStatus.id,
              'source': clip.source,
            },
        ],
        'insight': entry.insight == null ? null : _insight(entry.insight!),
      };

  static Map<String, Object?> _insight(Insight insight) => {
        'id': insight.id,
        'recordId': insight.recordId,
        'kind': insight.kind,
        'content': insight.content,
        'provider': insight.provider,
        'model': insight.model,
        'score': insight.score,
        'generatedAtUtc': _iso(insight.generatedAtUtc),
        'status': insight.status.id,
      };

  static String _iso(DateTime utc) => utc.toUtc().toIso8601String();

  // ── 行 ──────────────────────────────────────────────────────────────────

  static List<String> _recordRow(SleepEntry entry) => [
        entry.dateLabel,
        entry.bedtimeLabel,
        entry.wakeLabel,
        entry.timeZoneId,
        (entry.durationMinutes / 60).toStringAsFixed(2),
        entry.durationMinutes.toString(),
        entry.quality?.value.toString() ?? '', // CSV：空单元格
        _yesNo(entry.loggedEvents.snore),
        _yesNo(entry.loggedEvents.talk),
        _yesNo(entry.loggedEvents.restless),
        _yesNo(entry.loggedEvents.nightmare),
        entry.notes,
        entry.source,
        entry.id,
        _localStamp(entry.createdAtUtc),
        _localStamp(entry.updatedAtUtc),
      ];

  static List<String> _stageRow(String recordId, SleepStageSegment segment) => [
        recordId,
        segment.stage.label,
        _localStamp(segment.startAtUtc),
        _localStamp(segment.endAtUtc),
        segment.minutes.toString(),
        segment.source,
      ];

  // ── 单元 ────────────────────────────────────────────────────────────────

  static String _table(List<String> header, List<List<String>> rows) {
    final buffer = StringBuffer(_bom)
      ..write(header.map(_cell).join(','))
      ..write(_eol);
    for (final row in rows) {
      buffer
        ..write(row.map(_cell).join(','))
        ..write(_eol);
    }
    return buffer.toString();
  }

  /// 按需加引号。备注是自由文本，是唯一真会走到这个分支的列。
  static String _cell(String value) {
    final mustQuote = value.contains(',') ||
        value.contains('"') ||
        value.contains('\r') ||
        value.contains('\n');
    if (!mustQuote) return value;
    return '"${value.replaceAll('"', '""')}"';
  }

  static String _yesNo(bool value) => value ? '是' : '否';

  static String _two(int value) => value.toString().padLeft(2, '0');

  /// 本地日历日 `YYYY-MM-DD`。
  static String _day(DateTime local) =>
      '${local.year.toString().padLeft(4, '0')}-'
      '${_two(local.month)}-${_two(local.day)}';

  /// 本地墙钟 `YYYY-MM-DD HH:mm`。
  ///
  /// 时间存的是 UTC 瞬时值，换算在**这里**发生——与界面显示同一口径，
  /// 导出的表因此直接可读，而时间轴仍然可复原（时区另有一列）。
  static String _localStamp(DateTime utc) {
    final local = utc.toLocal();
    return '${_day(local)} ${_two(local.hour)}:${_two(local.minute)}';
  }

  /// 文件名里的 `YYYYMMDD`。
  static String _dateStamp(DateTime local) =>
      '${local.year.toString().padLeft(4, '0')}'
      '${_two(local.month)}${_two(local.day)}';
}
