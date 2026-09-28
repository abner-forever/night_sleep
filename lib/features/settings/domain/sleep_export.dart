import '../../../core/config/app_config.dart';
import '../../sleep/domain/sleep_entry.dart';
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

/// 把用户自己的记录变成导出内容。
///
/// **纯函数**：没有数据库、没有插件、也没有自己的时钟（`now` 由调用方传入）。
/// 因此下面每一条格式规则都能在单元测试里逐字节断言，格式的知识也就只有这一处。
abstract final class SleepExporter {
  static const csvMime = 'text/csv';
  static const jsonMime = 'application/json';

  /// Excel 只在文件开头见到 BOM 时才按 UTF-8 解码；没有它就是乱码，
  /// 用户看到的是「导出坏了」。
  static const _bom = '﻿';

  /// RFC 4180 的行结束符。Excel 是这里最严格的消费方。
  static const _eol = '\r\n';

  static const _recordHeader = [
    '日期', '入睡时刻', '醒来时刻', '时区', '时长(小时)', '时长(分钟)', //
    '质量', '打鼾', '梦话', '辗转', '噩梦', '备注', '来源', '记录ID', //
    '最初记录时间', '最后修改时间',
  ];

  static const _stageHeader = ['记录ID', '阶段', '开始时间', '结束时间', '时长(分钟)', '来源'];

  /// 允许离开应用的那部分记录：除演示数据之外的全部。
  ///
  /// 演示之夜从阶段到转写全是合成的，写进用户的备份就是把伪造数据掺进真实数据——
  /// 与「演示数据不可编辑」「演示数据只在 DEMO_DATA 下安装」是同一条原则。
  static List<SleepEntry> exportableOf(List<SleepEntry> entries) =>
      entries.where((e) => e.source != AppConfig.demoSource).toList();

  /// 两张表：记录一行一晚，阶段一行一段。
  ///
  /// 阶段不压成「深睡/浅睡/REM 分钟」三列：分段的时间戳是阶段图的唯一来源，
  /// 压成合计就回不来了。
  static List<ExportFile> csv(
    List<SleepEntry> entries, {
    required DateTime now,
  }) {
    final exportable = exportableOf(entries);
    final stamp = _dateStamp(now);

    return [
      ExportFile(
        fileName: '夜深-睡眠记录-$stamp.csv',
        mimeType: csvMime,
        content: _table(_recordHeader, [
          for (final entry in exportable) _recordRow(entry),
        ]),
      ),
      ExportFile(
        fileName: '夜深-睡眠阶段-$stamp.csv',
        mimeType: csvMime,
        content: _table(_stageHeader, [
          for (final entry in exportable)
            for (final segment in entry.stages) _stageRow(entry.id, segment),
        ]),
      ),
    ];
  }

  // ── 行 ──────────────────────────────────────────────────────────────────

  static List<String> _recordRow(SleepEntry entry) => [
        entry.dateLabel,
        entry.bedtimeLabel,
        entry.wakeLabel,
        entry.timeZoneId,
        (entry.durationMinutes / 60).toStringAsFixed(2),
        entry.durationMinutes.toString(),
        entry.quality.value.toString(),
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
