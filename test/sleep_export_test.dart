import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/features/settings/domain/sleep_export.dart';
import 'package:night_sleep/features/sleep/domain/sleep_entry.dart';
import 'package:night_sleep/features/sleep/domain/sleep_quality.dart';
import 'package:night_sleep/features/sleep/domain/sleep_score.dart';
import 'package:night_sleep/features/sleep/domain/sleep_stage.dart';

/// 导出格式的单元测试。
///
/// 断言**不写死本地时刻**：`SleepEntry` 的墙钟标签由 `endAtUtc.toLocal()` 派生，
/// 结果随跑测试的机器时区变化。所以凡是由领域对象派生的值，这里都用对象自己的
/// getter 拼出期望值——测的是**列映射**，不是时区换算（后者由
/// `sleep_window_test.dart` 覆盖）。
void main() {
  final now = DateTime(2026, 9, 28, 12);

  SleepEntry entry({
    String id = 'r1',
    String source = 'manual',
    String notes = '',
    String timeZoneId = 'UTC',
    LoggedEvents events = LoggedEvents.none,
    List<SleepStageSegment> stages = const [],
  }) =>
      SleepEntry(
        id: id,
        startAtUtc: DateTime.utc(2026, 9, 26, 23),
        endAtUtc: DateTime.utc(2026, 9, 27, 7),
        timeZoneId: timeZoneId,
        quality: SleepQuality.good,
        notes: notes,
        source: source,
        loggedEvents: events,
        stages: stages,
        createdAtUtc: DateTime.utc(2026, 9, 27, 8),
        updatedAtUtc: DateTime.utc(2026, 9, 27, 8),
      );

  SleepStageSegment segment(SleepStageType stage, {int minutes = 60}) =>
      SleepStageSegment(
        stage: stage,
        startAtUtc: DateTime.utc(2026, 9, 26, 23),
        endAtUtc: DateTime.utc(2026, 9, 26, 23).add(Duration(minutes: minutes)),
        source: 'import',
      );

  /// 取第 [index] 行的原文（0 是表头）。
  ///
  /// **先去掉开头的 BOM**：它是给 Excel 看的文件头，不是第一列内容的一部分。
  /// 不剥掉的话，第一列会变成 `'﻿日期'`。
  String rowOf(String content, int index) =>
      content.replaceFirst('﻿', '').split('\r\n')[index];

  /// 按 RFC 4180 拆列。
  ///
  /// 不能裸用 `split(',')`：备注里就有一个逗号，那样切出来的列数会比真实列数多，
  /// 于是「转义之后仍是 16 列」这类断言**反而测不出任何东西**。
  List<String> cells(String row) {
    final result = <String>[];
    final buffer = StringBuffer();
    var quoted = false;
    for (var i = 0; i < row.length; i++) {
      final char = row[i];
      if (quoted) {
        if (char == '"') {
          if (i + 1 < row.length && row[i + 1] == '"') {
            buffer.write('"');
            i++;
          } else {
            quoted = false;
          }
        } else {
          buffer.write(char);
        }
      } else if (char == '"') {
        quoted = true;
      } else if (char == ',') {
        result.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }
    result.add(buffer.toString());
    return result;
  }

  test('记录表表头列序固定', () {
    final file = SleepExporter.csv([entry()], now: now).first;

    expect(cells(rowOf(file.content, 0)), [
      '日期', '入睡时刻', '醒来时刻', '时区', '时长(小时)', '时长(分钟)', //
      '质量', '打鼾', '梦话', '辗转', '噩梦', '备注', '来源', '记录ID', //
      '最初记录时间', '最后修改时间',
    ]);
  });

  test('文件带 UTF-8 BOM 且用 CRLF 分行', () {
    final file = SleepExporter.csv([entry()], now: now).first;

    // Excel 只在开头见到 BOM 时才按 UTF-8 解码，否则中文备注是乱码。
    expect(file.content.codeUnitAt(0), 0xFEFF);
    expect(file.content, contains('\r\n'));
    expect(file.content, isNot(contains('\n\n')));
  });

  test('记录行取领域对象的派生值', () {
    final only = entry(
      timeZoneId: 'Asia/Shanghai',
      events: const LoggedEvents(snore: true),
    );
    final file = SleepExporter.csv([only], now: now).first;
    final row = cells(rowOf(file.content, 1));

    expect(row[0], only.dateLabel);
    expect(row[1], only.bedtimeLabel);
    expect(row[2], only.wakeLabel);
    expect(row[3], 'Asia/Shanghai');
    expect(row[4], (only.durationMinutes / 60).toStringAsFixed(2));
    expect(row[5], only.durationMinutes.toString());
    expect(row[6], '4');
    expect(row[7], '是', reason: '打了勾的事件写「是」');
    expect(row[8], '否');
    expect(row[11], '');
    expect(row[12], 'manual');
    expect(row[13], 'r1');
    // 两个时间戳是本地墙钟，时区随机器变，只校验形状。
    expect(row[14], matches(RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$')));
    expect(row[15], matches(RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$')));
  });

  test('备注里的逗号、引号与换行会被转义', () {
    const note = '吃了药, 有点"闷"\n醒了两次';
    final file = SleepExporter.csv([entry(notes: note)], now: now).first;

    // 字面量：整段被双引号包裹，内部的引号双写。
    expect(file.content, contains('"吃了药, 有点""闷""\n醒了两次"'));

    // 而且拆得回来：转义之后仍是 16 列，备注能原样还原。
    final row = cells(rowOf(file.content, 1));
    expect(row, hasLength(16), reason: '引号内的逗号不是分隔符');
    expect(row[11], note, reason: '备注原文必须能无损还原');
  });

  test('阶段表一行一段，阶段写中文标签', () {
    final withStages = entry(
      stages: [
        segment(SleepStageType.deep, minutes: 60),
        segment(SleepStageType.rem, minutes: 30),
      ],
    );
    final file = SleepExporter.csv([withStages], now: now).last;

    expect(cells(rowOf(file.content, 0)),
        ['记录ID', '阶段', '开始时间', '结束时间', '时长(分钟)', '来源']);
    expect(cells(rowOf(file.content, 1)),
        ['r1', '深睡', anything, anything, '60', 'import']);
    expect(cells(rowOf(file.content, 2)),
        ['r1', 'REM', anything, anything, '30', 'import']);
  });

  test('演示记录不进文件，两张 CSV 都不进', () {
    final files = SleepExporter.csv(
      [
        entry(id: 'real', stages: [segment(SleepStageType.deep)]),
        entry(
            id: 'demo', source: 'demo', stages: [segment(SleepStageType.rem)]),
      ],
      now: now,
    );

    // 两条记录都带阶段，否则阶段表只有表头，`contains('real')` 这一断言
    // 就成了空转——它在空文件上必然失败，而失败原因与演示数据无关。
    for (final file in files) {
      expect(file.content, contains('real'));
      expect(file.content, isNot(contains('demo')));
    }
  });

  test('没有记录时仍然产出结构完整的两个文件', () {
    final files = SleepExporter.csv(const [], now: now);

    expect(files, hasLength(2));
    expect(files.first.fileName, '夜深-睡眠记录-20260928.csv');
    expect(files.last.fileName, '夜深-睡眠阶段-20260928.csv');
    expect(files.first.content, isNotEmpty, reason: '表头仍然要写');
    expect(cells(rowOf(files.first.content, 0)), hasLength(16));
  });

  test('文件名与类型随格式而定', () {
    final files = SleepExporter.csv([entry()], now: DateTime(2025, 1, 2));
    expect(files.first.fileName, '夜深-睡眠记录-20250102.csv');
    expect(files.first.mimeType, SleepExporter.csvMime);
  });

  test('exportableOf 只留下非演示记录', () {
    final all = [entry(id: 'a'), entry(id: 'b', source: 'demo')];
    expect(SleepExporter.exportableOf(all).map((e) => e.id), ['a']);
  });
}
