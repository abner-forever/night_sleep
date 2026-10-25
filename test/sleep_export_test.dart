import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/features/settings/domain/sleep_export.dart';
import 'package:night_sleep/features/sleep/domain/sleep_entry.dart';
import 'package:night_sleep/features/sleep/domain/sleep_insight.dart';
import 'package:night_sleep/features/sleep/domain/sleep_quality.dart';
import 'package:night_sleep/features/sleep/domain/sleep_score.dart';
import 'package:night_sleep/features/sleep/domain/sleep_stage.dart';
import 'package:night_sleep/features/sleep/domain/sound_event.dart';

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

    /// 默认有质量；显式传 `null` 构造一条**未评分**的记录。
    SleepQuality? quality = SleepQuality.good,
  }) =>
      SleepEntry(
        id: id,
        startAtUtc: DateTime.utc(2026, 9, 26, 23),
        endAtUtc: DateTime.utc(2026, 9, 27, 7),
        timeZoneId: timeZoneId,
        quality: quality,
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
  /// 不剥掉的话，第一列会变成 `'\uFEFF日期'`。
  String rowOf(String content, int index) =>
      content.replaceFirst('\uFEFF', '').split('\r\n')[index];

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

  /// 按 RFC 4180 把整份内容拆回二维表（会正确处理引号里的逗号与换行）。
  ///
  /// 与 [cells] 的区别是它作用于**整份文件**：引号里那个裸换行会把按行切分的
  /// [rowOf] 拆散，所以「预览与文件逐格相同」这条只能用整份解析来断。
  List<List<String>> parseTable(String content) {
    final rows = <List<String>>[];
    var row = <String>[];
    final buffer = StringBuffer();
    var quoted = false;
    final text = content.replaceFirst('\uFEFF', '');

    void endRow() {
      row.add(buffer.toString());
      buffer.clear();
      rows.add(row);
      row = <String>[];
    }

    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (quoted) {
        if (char != '"') {
          buffer.write(char);
        } else if (i + 1 < text.length && text[i + 1] == '"') {
          buffer.write('"');
          i++;
        } else {
          quoted = false;
        }
        continue;
      }
      switch (char) {
        case '"':
          quoted = true;
        case ',':
          row.add(buffer.toString());
          buffer.clear();
        case '\r':
          if (i + 1 < text.length && text[i + 1] == '\n') i++;
          endRow();
        case '\n':
          endRow();
        default:
          buffer.write(char);
      }
    }
    // 文件以 CRLF 结尾，所以走到这里 buffer 与 row 都是空的，不会再补一行。
    expect(buffer.isEmpty && row.isEmpty, isTrue, reason: '解析完还剩着内容，说明行结构被破坏了');
    return rows;
  }

  test('记录表表头列序固定', () {
    final file = SleepExporter.csv([entry()], now: now).first;

    expect(cells(rowOf(file.content, 0)), [
      '日期', '入睡时刻', '醒来时刻', '时区', '时长(小时)', '时长(分钟)', //
      '质量', '打鼾', '梦话', '辗转', '噩梦', '备注', '来源', '记录ID', //
      '最初记录时间', '最后修改时间',
    ]);
  });

  test('文件带 UTF-8 BOM 且每行用 CRLF 分隔', () {
    final file = SleepExporter.csv([entry(), entry(id: 'r2')], now: now).first;

    // Excel 只在开头见到 BOM 时才按 UTF-8 解码，否则中文备注是乱码。
    expect(file.content.codeUnitAt(0), 0xFEFF);

    // 4 段 = 表头 + 两条记录 + 结尾 CRLF 之后的空串。
    //
    // 断言**段数**而不是「含有 CRLF」：后者被上一行的 BOM 断言蕴含，永远不可能
    // 失败。段数会真的变——少一段说明漏了记录，多一段说明某条记录被值里的裸换行
    // 拆成了两行。
    expect(file.content.substring(1).split('\r\n'), hasLength(4));
  });

  test('记录按入睡时刻升序，不看调用方给的顺序', () {
    // `sleepEntriesProvider` 给的是**倒序**（界面最新在前）。导出若继承它，
    // 将来界面一改排序，文件就会静默跟着变。
    final earlier = entry(id: 'earlier');
    final later = SleepEntry(
      id: 'later',
      startAtUtc: DateTime.utc(2026, 9, 27, 23),
      endAtUtc: DateTime.utc(2026, 9, 28, 7),
      timeZoneId: 'UTC',
      quality: SleepQuality.good,
      createdAtUtc: DateTime.utc(2026, 9, 28, 8),
      updatedAtUtc: DateTime.utc(2026, 9, 28, 8),
    );

    final file = SleepExporter.csv([later, earlier], now: now).first; // 故意倒着传

    expect(cells(rowOf(file.content, 1))[13], 'earlier');
    expect(cells(rowOf(file.content, 2))[13], 'later');
  });

  test('备注里的回车也会被转义', () {
    final file = SleepExporter.csv([entry(notes: '断在\r这里')], now: now).first;

    // `_cell` 的 `\r` 分支：回车与换行一样会破坏行结构，必须一起引起来。
    expect(file.content, contains('"断在\r这里"'));
    final row = cells(rowOf(file.content, 1));
    expect(row, hasLength(16));
    expect(row[11], '断在\r这里');
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

  test('入睡时刻相同的两条按 id 定序，两次排序结果一致', () {
    // `entry()` 造出来的两条时间完全一样。只按时间排时它们的先后未定义，
    // 而导出文件与预览页是两次独立的排序调用——未定义就等于两者可以不一致。
    final a = entry(id: 'aaa');
    final b = entry(id: 'bbb');

    expect(SleepExporter.exportableOf([b, a]).map((e) => e.id), ['aaa', 'bbb']);
    expect(SleepExporter.exportableOf([a, b]).map((e) => e.id), ['aaa', 'bbb'],
        reason: '与调用方给的顺序无关');
  });

  test('预览读的表与 CSV 文件逐格相同', () {
    final entries = [
      entry(
        id: 'a',
        notes: '吃了药, 有点"闷"\n醒了两次',
        stages: [
          segment(SleepStageType.deep, minutes: 60),
          segment(SleepStageType.rem, minutes: 30),
        ],
      ),
      entry(id: 'b', source: 'demo', stages: [segment(SleepStageType.deep)]),
      entry(id: 'c', quality: null),
    ];

    final tables = SleepExporter.tables(entries, now: now);
    final files = SleepExporter.csv(entries, now: now);

    expect(tables, hasLength(files.length));
    for (var i = 0; i < tables.length; i++) {
      final parsed = parseTable(files[i].content);
      expect(tables[i].fileName, files[i].fileName);
      expect(parsed.first, tables[i].header,
          reason: '表头：${tables[i].kind.label}表');
      expect(parsed.sublist(1), tables[i].rows,
          reason: '数据行：${tables[i].kind.label}表。预览页显示的就是这些行，'
              '与文件不一致就等于预览在说谎');
    }
  });

  test('两张表的身份、列数与行数', () {
    final tables = SleepExporter.tables([
      entry(id: 'a', stages: [
        segment(SleepStageType.deep, minutes: 60),
        segment(SleepStageType.light, minutes: 30),
      ]),
    ], now: now);

    expect(tables.map((table) => table.kind),
        [ExportTableKind.records, ExportTableKind.stages]);
    expect(tables.map((table) => table.kind.label), ['记录', '阶段']);
    expect(tables.first.fileName, '夜深-睡眠记录-20260928.csv');
    expect(tables.last.fileName, '夜深-睡眠阶段-20260928.csv');
    expect(tables.first.header, hasLength(16));
    expect(tables.last.header, hasLength(6));
    expect(tables.first.rowCount, 1);
    expect(tables.last.rowCount, 2, reason: '阶段表一行一段');
  });

  test('没有记录时两张表都只剩表头', () {
    final tables = SleepExporter.tables(const [], now: now);

    expect(tables, hasLength(2));
    expect(tables.every((table) => table.rowCount == 0), isTrue);
  });

  test('JSON 表头字段齐全，数组恒为数组', () {
    final file = SleepExporter.json([entry()], now: now).single;
    final doc = jsonDecode(file.content) as Map<String, dynamic>;

    expect(file.fileName, '夜深-睡眠数据-20260928.json');
    expect(file.mimeType, SleepExporter.jsonMime);
    expect(doc['format'], 'night-sleep-export');
    expect(doc['version'], 1);
    expect(doc['schemaVersion'], 10);
    expect(doc['recordCount'], 1);
    expect(doc['excludedDemoCount'], 0);
    expect(doc['exportedAtUtc'], now.toUtc().toIso8601String());

    final record = (doc['records'] as List).single as Map<String, dynamic>;
    expect(record['tags'], isEmpty);
    expect(record['stages'], isEmpty);
    expect(record['soundClips'], isEmpty);
    expect(record['insight'], isNull);
  });

  test('JSON 记录里写的是 schema 字段名与 UTC 时间戳', () {
    final only = entry(events: const LoggedEvents(restless: true));
    final doc = jsonDecode(SleepExporter.json([only], now: now).single.content)
        as Map<String, dynamic>;
    final record = (doc['records'] as List).single as Map<String, dynamic>;

    expect(record['id'], 'r1');
    expect(record['startAtUtc'], only.startAtUtc.toUtc().toIso8601String());
    expect(record['endAtUtc'], only.endAtUtc.toUtc().toIso8601String());
    expect(record['timeZoneId'], 'UTC');
    expect(record['quality'], 4);
    expect(record['source'], 'manual');
    expect(record['loggedEvents'], {
      'snore': false,
      'talk': false,
      'restless': true,
      'nightmare': false,
    });

    // 钉住「存档不写派生值」。时长、阶段合计与占比都由起止时间派生，
    // 规格已定「时长派生不存储」，存档里塞一份只会多一个会过期的事实。
    // 没有这条断言时，往 `_record` 里加一个 `durationMinutes` 不会让任何用例变红。
    expect(record.keys, isNot(contains('durationMinutes')),
        reason: '规格明写不写派生值：时长由起止时间派生，不进存档');
  });

  test('JSON 阶段写稳定 id 而不是中文标签', () {
    final withStages = entry(stages: [
      SleepStageSegment(
        stage: SleepStageType.light,
        startAtUtc: DateTime.utc(2026, 9, 26, 23),
        endAtUtc: DateTime.utc(2026, 9, 27),
      ),
    ]);
    final doc =
        jsonDecode(SleepExporter.json([withStages], now: now).single.content)
            as Map<String, dynamic>;
    final record = (doc['records'] as List).single as Map<String, dynamic>;
    final stage = (record['stages'] as List).single as Map<String, dynamic>;

    expect(stage['stage'], 'light', reason: '存档字段用稳定 id，中文标签留给 CSV');
    expect(stage['source'], 'import');
    expect(stage['startAtUtc'], '2026-09-26T23:00:00.000Z');
  });

  test('JSON 不写出任何本地文件路径', () {
    const localPath =
        '/var/mobile/Containers/Data/Application/ABC/Documents/clips/c1.wav';
    final withClip = entry();
    final withAudio = SleepEntry(
      id: withClip.id,
      startAtUtc: withClip.startAtUtc,
      endAtUtc: withClip.endAtUtc,
      timeZoneId: withClip.timeZoneId,
      quality: withClip.quality,
      createdAtUtc: withClip.createdAtUtc,
      updatedAtUtc: withClip.updatedAtUtc,
      soundClips: [
        SoundClip(
          id: 'c1',
          kind: SoundEventKind.snore,
          startedAtUtc: DateTime.utc(2026, 9, 27, 2),
          durationMs: 4200,
          localUri: localPath,
        ),
      ],
    );

    final content = SleepExporter.json([withAudio], now: now).single.content;

    // 音频文件本身不进导出，路径留着只会悬空；而导出文件会离开应用。
    expect(content, isNot(contains('localUri')));
    expect(content, isNot(contains('/var/mobile')));
    expect(content, contains('"hasLocalAudio": true'));
  });

  test('JSON 不含任何 AppSettings 字段', () {
    final content = SleepExporter.json([entry()], now: now).single.content;

    // 正向锚点：三条断言全是否定的，空串会让它们一起通过。
    // 先钉住「这确实是那份存档」，否定断言才说明得了问题。
    expect(content, contains('night-sleep-export'));

    // 设置是设备偏好，跨设备回灌只会污染；顺带把 API Key 从结构上排除掉。
    expect(content, isNot(contains('themeMode')));
    expect(content, isNot(contains('sleepGoalMinutes')));
    expect(content, isNot(contains('insightProvider')));
  });

  test('JSON 写洞察全文，演示计数如实', () {
    final withInsight = SleepEntry(
      id: 'r1',
      startAtUtc: DateTime.utc(2026, 9, 26, 23),
      endAtUtc: DateTime.utc(2026, 9, 27, 7),
      timeZoneId: 'UTC',
      quality: SleepQuality.good,
      createdAtUtc: DateTime.utc(2026, 9, 27, 8),
      updatedAtUtc: DateTime.utc(2026, 9, 27, 8),
      insight: Insight(
        id: 'i1',
        recordId: 'r1',
        content: '本周入睡时间比上周晚。',
        provider: 'deepseek',
        model: 'deepseek-chat',
        score: 82,
        generatedAtUtc: DateTime.utc(2026, 9, 27, 9),
        status: InsightStatus.ok,
      ),
    );
    final doc = jsonDecode(
      SleepExporter.json([withInsight, entry(id: 'd', source: 'demo')],
              now: now)
          .single
          .content,
    ) as Map<String, dynamic>;

    expect(doc['recordCount'], 1);
    expect(doc['excludedDemoCount'], 1);
    final record = (doc['records'] as List).single as Map<String, dynamic>;
    final insight = record['insight'] as Map<String, dynamic>;
    expect(insight['status'], 'ok');
    expect(insight['score'], 82);
    expect(insight['content'], '本周入睡时间比上周晚。');
  });

  test('未评分记录的 JSON 里 quality 是 null', () {
    final doc = jsonDecode(
      SleepExporter.json([entry(quality: null)], now: now).single.content,
    ) as Map<String, dynamic>;

    final record = (doc['records'] as List).single as Map<String, dynamic>;
    // 未评分就写 null，**不写占位值**：回灌时 null 与「用户填了 3 分」是两件事，
    // 塞个默认档进来等于替用户说了一句他没说过的话。
    expect(record['quality'], isNull);
    expect(record.containsKey('quality'), isTrue, reason: '字段要在，值为空');
  });

  test('未评分记录的 CSV 质量列是空单元格', () {
    final file = SleepExporter.csv([entry(quality: null)], now: now).first;
    final row = cells(rowOf(file.content, 1));

    // 列序不变，第 6 列留空——不是 0、也不是某一档的编号。
    expect(row, hasLength(16));
    expect(row[6], isEmpty);
  });
}
