# 导出与提醒实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让设置页的「就寝/起床提醒」真的会响，并让用户能把自己的睡眠记录导出成 CSV 与 JSON。

**Architecture:** 两块都按现有分层切开——**能纯算的进 domain（无 IO、无插件、可逐字节断言），碰平台的进 data / core（薄封装 + provider 注入）**。导出内容由纯函数生成，交付交给 `ExportSharer` 接口，widget 测试喂假实现以绕开平台通道在 FakeAsync 下挂死的坑。提醒把「幂等全量重排」这个算法放在 `ReminderScheduler` 基类里，子类只提供 `cancel` / `schedule` 两个原子动作，因此调度契约可以在纯 Dart 测试里断言。

**Tech Stack:** Flutter / Dart、Riverpod、Drift、`flutter_local_notifications` 22.3.1、`timezone` 0.11.1、`flutter_timezone` 5.1.0、`share_plus` 13.3.0

**设计依据:** [docs/superpowers/specs/2026-09-28-export-and-reminders-design.md](../specs/2026-09-28-export-and-reminders-design.md)

## Global Constraints

- 界面文案、注释、文档一律**中文**；代码标识符英文。
- 依赖版本锁死在上面列出的四个，不额外引入（**特别是不加 `url_launcher`**：插件的 `openAppNotificationSettings()` 已覆盖「去系统设置」）。
- 只取**真实记录**导出：`source == AppConfig.demoSource` 的行一律不进导出文件。
- 导出内容里**不得出现任何本地绝对路径**（`localUri` 等），也不得出现 `AppSettings` 的字段。
- 权限不是 `granted` 时**不得写入** `bedtimeReminderEnabled` / `wakeReminderEnabled`。
- Android 平台目录**不存在**（`.metadata` 只有 `ios` / `macos` / `web`），本轮**不生成 `android/`**：Dart 侧保留 Android 分支，manifest 配置记入 README 未实现表。
- 不改 `lib/**/*.g.dart`；不往 shell profile 写环境变量。
- 测试里**不要 `await HapticFeedback.*`**（FakeAsync 下永不完成），也**不要订阅 drift 的 `watch*` 流**（假时钟不推进，拆解时留 pending timer）。
- 推入的二级页测试**不要套 `Scaffold`**——套了就等于把背景和 `Material` 白送给它，测试全绿而真机是黑底加黄色下划线。
- **不要设 `PUB_HOSTED_URL` / `FLUTTER_STORAGE_BASE_URL`。** 四个新依赖已经装好并进了
  `pubspec.lock`，`flutter pub get` 现在完全走本地缓存。带上镜像变量会把锁文件里
  129 条 `url: "https://pub.dev"` 全部改写成镜像地址，制造一整屏无意义的提交噪声。
  需要联网的只剩 `flutter build`（见 Task 6），那里的代理变量按 README 单独设置。
- 若 `flutter pub get` 因为网络失败，报告 BLOCKED，**不要手改 `pubspec.yaml`**。
- **`pubspec.yaml` 变更后的提交必须一并带上 `macos/Flutter/GeneratedPluginRegistrant.swift`**
  ——它是 `pub get` 重写的插件注册表，漏掉会让 macOS 构建找不到新插件的原生实现。
- 测试里取 CSV 内容时**不要裸用 `split(',')`**：备注里就含逗号，裸切出来的列数比真实列数多，
  「转义之后仍是 16 列」这类断言会变成空转。用 brief 里给的 `cells()` 解析器。

---

### Task 1: 导出内容生成器（CSV）

**Files:**
- Create: `lib/features/settings/domain/sleep_export.dart`
- Create: `test/sleep_export_test.dart`
- Modify: `pubspec.yaml`（新增四个依赖）

**Interfaces:**
- Consumes: `SleepEntry`、`SleepStageSegment`（`features/sleep/domain/`）、`AppConfig.demoSource`（`core/config/app_config.dart`）
- Produces:
  - `class ExportFile { final String fileName; final String content; final String mimeType; }`
  - `abstract final class SleepExporter` 的 `static const csvMime` / `static const jsonMime` / `static List<SleepEntry> exportableOf(List<SleepEntry>)` / `static List<ExportFile> csv(List<SleepEntry> entries, {required DateTime now})`

- [ ] **Step 1: 先把依赖装上**

四个包在这一步一次装齐：`flutter pub get` 与原生依赖解析是最慢的一步，分三次做没有收益。

```bash
flutter pub add flutter_local_notifications timezone flutter_timezone share_plus
```

**不要加 `PUB_HOSTED_URL` / `FLUTTER_STORAGE_BASE_URL`**：包已在本地 pub 缓存中，带上镜像
会把 `pubspec.lock` 里 129 条 `url: "https://pub.dev"` 全部改写成镜像地址。

预期：`pubspec.yaml` 的 dependencies 里出现四个包，版本为 22.3.1 / 0.11.1 / 5.1.0 / 13.3.0（或更高但不跨大版本）。

- [ ] **Step 2: 写失败的测试**

创建 `test/sleep_export_test.dart`：

```dart
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

  test('记录表表头列序固定', () {
    final file = SleepExporter.csv([entry()], now: now).first;

    expect(cells(rowOf(file.content, 0)), [
      '日期', '入睡时刻', '醒来时刻', '时区', '时长(小时)', '时长(分钟)', //
      '质量', '打鼾', '梦话', '辗转', '噩梦', '备注', '来源', '记录ID', //
      '最初记录时间', '最后修改时间',
    ]);
  });

  test('文件带 UTF-8 BOM 且每行用 CRLF 分隔', () {
    final file =
        SleepExporter.csv([entry(), entry(id: 'r2')], now: now).first;

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

    final file =
        SleepExporter.csv([later, earlier], now: now).first; // 故意倒着传

    expect(cells(rowOf(file.content, 1))[13], 'earlier');
    expect(cells(rowOf(file.content, 2))[13], 'later');
  });

  test('备注里的回车也会被转义', () {
    final file =
        SleepExporter.csv([entry(notes: '断在\r这里')], now: now).first;

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
        entry(id: 'demo', source: 'demo', stages: [segment(SleepStageType.rem)]),
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
```

- [ ] **Step 3: 跑测试，确认失败**

```bash
flutter test test/sleep_export_test.dart
```

预期：编译失败，`Error: Couldn't resolve the package 'night_sleep' ... sleep_export.dart`——文件还不存在。

- [ ] **Step 4: 写实现**

创建 `lib/features/settings/domain/sleep_export.dart`：

```dart
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
  /// 耦合，也让表格软件里按时间轴自然展开。
  static List<SleepEntry> exportableOf(List<SleepEntry> entries) {
    final exportable =
        entries.where((e) => e.source != AppConfig.demoSource).toList();
    exportable.sort((a, b) => a.startAtUtc.compareTo(b.startAtUtc));
    return exportable;
  }

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
```

- [ ] **Step 5: 跑测试，确认通过**

```bash
flutter test test/sleep_export_test.dart
```

预期：全部通过（11 个用例）。

- [ ] **Step 6: 提交**

```bash
git add pubspec.yaml pubspec.lock \
        macos/Flutter/GeneratedPluginRegistrant.swift \
        lib/features/settings/domain/sleep_export.dart test/sleep_export_test.dart
git commit -m "feat: 导出内容生成器（CSV 两张表）与四个新依赖"
```

`macos/Flutter/GeneratedPluginRegistrant.swift` 是 `pub get` 加完新插件后重写的注册表，
**不能漏**：漏掉它 macOS 构建就找不到新插件的原生实现。`ios/` 下没有对应文件要改。

---

### Task 2: 导出内容生成器（JSON）

**Files:**
- Modify: `lib/features/settings/domain/sleep_export.dart`
- Modify: `test/sleep_export_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `ExportFile`、`SleepExporter.exportableOf`、`_dateStamp`
- Produces: `static List<ExportFile> json(List<SleepEntry> entries, {required DateTime now})`，返回**恰好一个**文件

- [ ] **Step 1: 写失败的测试**

在 `test/sleep_export_test.dart` 的文件末尾、`main()` 的收尾 `}` 之前追加。同时把顶部导入补上 `dart:convert` 与声音/洞察两个领域文件：

```dart
import 'dart:convert';

import 'package:night_sleep/features/sleep/domain/sleep_insight.dart';
import 'package:night_sleep/features/sleep/domain/sound_event.dart';
```

追加的用例：

```dart
  test('JSON 表头字段齐全，数组恒为数组', () {
    final file = SleepExporter.json([entry()], now: now).single;
    final doc = jsonDecode(file.content) as Map<String, dynamic>;

    expect(file.fileName, '夜深-睡眠数据-20260928.json');
    expect(file.mimeType, SleepExporter.jsonMime);
    expect(doc['format'], 'night-sleep-export');
    expect(doc['version'], 1);
    expect(doc['schemaVersion'], 2);
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
  });

  test('JSON 阶段写稳定 id 而不是中文标签', () {
    final withStages = entry(stages: [
      SleepStageSegment(
        stage: SleepStageType.light,
        startAtUtc: DateTime.utc(2026, 9, 26, 23),
        endAtUtc: DateTime.utc(2026, 9, 27),
      ),
    ]);
    final doc = jsonDecode(SleepExporter.json([withStages], now: now).single.content)
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

    // 音频文件本身不进导出，路径留着只会悬空；而导出是要分享出去的。
    expect(content, isNot(contains('localUri')));
    expect(content, isNot(contains('/var/mobile')));
    expect(content, contains('"hasLocalAudio": true'));
  });

  test('JSON 不含任何 AppSettings 字段', () {
    final content = SleepExporter.json([entry()], now: now).single.content;

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
      SleepExporter.json([withInsight, entry(id: 'd', source: 'demo')], now: now)
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
```

- [ ] **Step 2: 跑测试，确认失败**

```bash
flutter test test/sleep_export_test.dart
```

预期：编译失败，`The method 'json' isn't defined for the type 'SleepExporter'`。

- [ ] **Step 3: 写实现**

在 `lib/features/settings/domain/sleep_export.dart` 的 `SleepExporter` 里追加（同时补上顶部两行导入）：

```dart
import 'dart:convert';

import '../../sleep/domain/sleep_insight.dart';
```

**不要导入 `sound_event.dart`**：实现里只做 `clip.kind.id` 这类成员访问，靠类型推断即可，
不出现 `SoundClip` 这个名字，导入它会被分析器报 `unused_import`，破坏「analyze 零问题」。
（测试文件里倒是要导入——那边显式构造 `SoundClip(...)`。）

```dart
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
        'quality': entry.quality.value,
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
```

- [ ] **Step 4: 跑测试，确认通过**

```bash
flutter test test/sleep_export_test.dart
```

预期：17 个用例全部通过（Task 1 的 11 个 + 本任务的 6 个）。

- [ ] **Step 5: 提交**

```bash
git add lib/features/settings/domain/sleep_export.dart test/sleep_export_test.dart
git commit -m "feat: 导出的 JSON 存档格式"
```

---

### Task 3: 导出页、分享层与设置页入口

**Files:**
- Create: `lib/features/settings/data/export_sharer.dart`
- Create: `lib/features/settings/presentation/export_page.dart`
- Create: `test/export_page_test.dart`
- Modify: `lib/app/app.dart`（`_router` 的 `routes` 里加一条）
- Modify: `lib/features/settings/presentation/settings_page.dart`（新增一个 section）
- Modify: `test/pages_widget_test.dart`（把新二级页并入既有的渲染守卫）

**Interfaces:**
- Consumes: `SleepExporter.json` / `.csv` / `.exportableOf`、`ExportFile`
- Produces:
  - `enum ShareOutcome { shared, dismissed, failed }`
  - `abstract interface class ExportSharer { Future<ShareOutcome> share({required List<ExportFile> files, required String subject}); }`
  - `final exportSharerProvider`（`Provider<ExportSharer>`）
  - `class ExportPage extends ConsumerWidget`

- [ ] **Step 1: 写分享层**

创建 `lib/features/settings/data/export_sharer.dart`：

```dart
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../domain/sleep_export.dart';

/// 一次分享的结果。
enum ShareOutcome {
  /// 文件交给了某个分享目标。
  shared,

  /// 用户在面板上什么都没选就关掉了。**不是错误**。
  dismissed,

  /// 文件写不出来，或平台拒绝分享。
  failed,
}

/// 把导出文件交给系统。
///
/// 做成接口而不是直接调用，是为了让 widget 测试能换成假实现：`share_plus` 走平台通道，
/// 而平台通道的 Future 在 widget tester 的 FakeAsync 下**永不完成**——与
/// `await HapticFeedback.*` 会挂死测试是同一个坑。
abstract interface class ExportSharer {
  Future<ShareOutcome> share({
    required List<ExportFile> files,
    required String subject,
  });
}

class SystemExportSharer implements ExportSharer {
  const SystemExportSharer();

  @override
  Future<ShareOutcome> share({
    required List<ExportFile> files,
    required String subject,
  }) async {
    try {
      final directory = Directory(
        path.join((await getTemporaryDirectory()).path, 'export'),
      );
      await directory.create(recursive: true);

      final paths = <String>[];
      for (final file in files) {
        final target = File(path.join(directory.path, file.fileName));
        // 文件名带日期，同一天重复导出覆盖同一路径。不做主动清理：
        // 临时目录由系统回收，自己扫一遍删旧文件既多一份代码，
        // 也多一种「分享面板还开着、文件已被删掉」的边界情况。
        await target.writeAsString(file.content, flush: true);
        paths.add(target.path);
      }

      final result = await SharePlus.instance.share(
        ShareParams(
          files: [for (final file in paths) XFile(file)],
          subject: subject,
        ),
      );

      return switch (result.status) {
        ShareResultStatus.success => ShareOutcome.shared,
        ShareResultStatus.dismissed => ShareOutcome.dismissed,
        _ => ShareOutcome.failed,
      };
    } catch (_) {
      return ShareOutcome.failed;
    }
  }
}

final exportSharerProvider = Provider<ExportSharer>((ref) {
  return const SystemExportSharer();
});
```

- [ ] **Step 2: 写失败的 widget 测试**

创建 `test/export_page_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/app/app_toast.dart';
import 'package:night_sleep/core/theme/app_theme.dart';
import 'package:night_sleep/features/settings/data/export_sharer.dart';
import 'package:night_sleep/features/settings/domain/sleep_export.dart';
import 'package:night_sleep/features/settings/presentation/export_page.dart';
import 'package:night_sleep/features/sleep/data/sleep_repository.dart';
import 'package:night_sleep/features/sleep/domain/sleep_entry.dart';
import 'package:night_sleep/features/sleep/domain/sleep_quality.dart';
import 'package:night_sleep/features/sleep/domain/sleep_stage.dart';

/// 导出页的 widget 测试。
///
/// 分享走的是平台通道，在 FakeAsync 下会挂死，所以这里喂一个假的 [ExportSharer]，
/// 只断言「交出去的内容对不对」。
class _FakeSharer implements ExportSharer {
  _FakeSharer({this.outcome = ShareOutcome.shared});

  final ShareOutcome outcome;
  List<ExportFile>? received;
  String? subject;

  @override
  Future<ShareOutcome> share({
    required List<ExportFile> files,
    required String subject,
  }) async {
    received = files;
    this.subject = subject;
    return outcome;
  }
}

void main() {
  SleepEntry entry({required String id, String source = 'manual', int stages = 0}) =>
      SleepEntry(
        id: id,
        startAtUtc: DateTime.utc(2026, 9, 26, 23),
        endAtUtc: DateTime.utc(2026, 9, 27, 7),
        timeZoneId: 'UTC',
        quality: SleepQuality.good,
        source: source,
        createdAtUtc: DateTime.utc(2026, 9, 27, 8),
        updatedAtUtc: DateTime.utc(2026, 9, 27, 8),
        stages: [
          for (var i = 0; i < stages; i++)
            SleepStageSegment(
              stage: SleepStageType.deep,
              startAtUtc: DateTime.utc(2026, 9, 26, 23 + i),
              endAtUtc: DateTime.utc(2026, 9, 27, i),
            ),
        ],
      );

  /// 二级页由路由器推入：**没有 Scaffold**，页面自己带。
  /// 这里补 Scaffold 就等于把背景和 Material 白送给它，测试会全绿而真机是黑底。
  Future<void> pumpRoute(
    WidgetTester tester, {
    required ExportSharer sharer,
    List<SleepEntry> entries = const [],
  }) async {
    tester.view.physicalSize = const Size(430, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sleepEntriesProvider.overrideWith((ref) => entries),
          exportSharerProvider.overrideWithValue(sharer),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ExportPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('没有真实记录时两个动作禁用并说明原因', (tester) async {
    final sharer = _FakeSharer();
    await pumpRoute(tester, sharer: sharer, entries: [
      entry(id: 'd1', source: 'demo'),
      entry(id: 'd2', source: 'demo'),
    ]);

    expect(find.text('暂无可导出的记录'), findsOneWidget);
    expect(find.textContaining('已排除 2 条演示记录'), findsOneWidget);

    await tester.tap(find.text('导出 CSV'));
    await tester.pumpAndSettle();
    expect(sharer.received, isNull, reason: '禁用的动作不该调用分享层');
  });

  testWidgets('条数统计只数真实记录', (tester) async {
    await pumpRoute(
      tester,
      sharer: _FakeSharer(),
      entries: [
        entry(id: 'a', stages: 3),
        entry(id: 'b', stages: 1),
        entry(id: 'd', source: 'demo', stages: 9),
      ],
    );

    expect(find.text('2'), findsWidgets, reason: '记录数');
    expect(find.text('4'), findsWidgets, reason: '阶段段数');
    expect(find.textContaining('已排除 1 条演示记录'), findsOneWidget);
    expect(find.text('暂无可导出的记录'), findsNothing);
  });

  testWidgets('点导出 CSV 交出两张表', (tester) async {
    final sharer = _FakeSharer();
    await pumpRoute(tester, sharer: sharer, entries: [entry(id: 'a', stages: 2)]);

    await tester.tap(find.text('导出 CSV'));
    await tester.pumpAndSettle();

    expect(sharer.received, hasLength(2));
    expect(sharer.received!.first.fileName, startsWith('夜深-睡眠记录-'));
    expect(sharer.received!.last.fileName, startsWith('夜深-睡眠阶段-'));
    expect(sharer.received!.first.content, contains('a'));
  });

  testWidgets('点导出 JSON 交出一份完整存档', (tester) async {
    final sharer = _FakeSharer();
    await pumpRoute(tester, sharer: sharer, entries: [entry(id: 'a')]);

    await tester.tap(find.text('导出 JSON'));
    await tester.pumpAndSettle();

    expect(sharer.received, hasLength(1));
    expect(sharer.received!.single.fileName, startsWith('夜深-睡眠数据-'));
    expect(sharer.received!.single.content, contains('night-sleep-export'));
  });

  testWidgets('分享失败如实报错', (tester) async {
    final sharer = _FakeSharer(outcome: ShareOutcome.failed);
    await pumpRoute(tester, sharer: sharer, entries: [entry(id: 'a')]);

    await tester.tap(find.text('导出 JSON'));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ExportPage)),
    );
    expect(container.read(toastProvider), isNotNull, reason: '失败必须有反馈');
  });

  testWidgets('用户取消分享面板不算失败，不弹提示', (tester) async {
    final sharer = _FakeSharer(outcome: ShareOutcome.dismissed);
    await pumpRoute(tester, sharer: sharer, entries: [entry(id: 'a')]);

    await tester.tap(find.text('导出 JSON'));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ExportPage)),
    );
    expect(container.read(toastProvider), isNull);
  });
}
```

- [ ] **Step 3: 跑测试，确认失败**

```bash
flutter test test/export_page_test.dart
```

预期：编译失败，找不到 `export_page.dart`。

- [ ] **Step 4: 写导出页**

创建 `lib/features/settings/presentation/export_page.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_toast.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/glass_surface.dart';
import '../../../core/widgets/ios_controls.dart';
import '../../../core/widgets/subpage.dart';
import '../../sleep/data/sleep_repository.dart';
import '../../sleep/domain/sleep_entry.dart';
import '../data/export_sharer.dart';
import '../domain/sleep_export.dart';

/// 睡眠数据导出。
///
/// 只导出**真实**记录：演示之夜是合成的，写进用户的备份就是把伪造数据掺进真实数据。
/// 没有可导出的记录时如实说明并禁用动作，不生成空文件、也不谎报成功。
class ExportPage extends ConsumerStatefulWidget {
  const ExportPage({super.key});

  @override
  ConsumerState<ExportPage> createState() => _ExportPageState();
}

class _ExportPageState extends ConsumerState<ExportPage> {
  /// 防止一次导出未完成时重复触发。
  bool _busy = false;

  /// [all] 是**未过滤**的全部记录。
  ///
  /// 过滤交给 `SleepExporter` 自己做：JSON 里的 `excludedDemoCount` 要靠
  /// 「过滤前有几条」才能算出来，这里先滤一遍它就只能恒为 0。
  Future<void> _export({
    required bool asJson,
    required List<SleepEntry> all,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);

    final files = asJson
        ? SleepExporter.json(all, now: DateTime.now())
        : SleepExporter.csv(all, now: DateTime.now());

    final outcome = await ref.read(exportSharerProvider).share(
          files: files,
          subject: '夜深睡眠数据导出',
        );

    if (!mounted) return;
    setState(() => _busy = false);

    if (outcome == ShareOutcome.failed) {
      ref.read(toastProvider.notifier).show('导出失败，文件没有交出去。');
    }
    // dismissed 是正常操作，不报。
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final all = ref.watch(sleepEntriesProvider).valueOrNull ?? const [];
    final exportable = SleepExporter.exportableOf(all);
    final excluded = all.length - exportable.length;

    final stageCount =
        exportable.fold(0, (sum, entry) => sum + entry.stages.length);
    final clipCount =
        exportable.fold(0, (sum, entry) => sum + entry.soundClips.length);
    final insightCount =
        exportable.where((entry) => entry.insight != null).length;

    final hasData = exportable.isNotEmpty;

    return Subpage(
      backLabel: '设置',
      title: '睡眠数据导出',
      children: [
        GlassSurface(
          borderRadius: BorderRadius.circular(AppRadii.card),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '将导出',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.96,
                  color: tokens.textMuted,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _Count(label: '记录', value: exportable.length),
                  _Count(label: '阶段段', value: stageCount),
                  _Count(label: '声音片段', value: clipCount),
                  _Count(label: '洞察', value: insightCount),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                hasData
                    ? '文件不含音频本身，也不含设置与密钥。'
                    : '暂无可导出的记录',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: tokens.textMuted,
                ),
              ),
              if (excluded > 0) ...[
                const SizedBox(height: 6),
                Text(
                  '已排除 $excluded 条演示记录',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: tokens.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 22),
        IosListGroup(
          children: [
            IosListItem(
              onTap: hasData
                  ? () => _export(asJson: false, all: all)
                  : null,
              child: _Action(
                enabled: hasData,
                title: '导出 CSV',
                subtitle: '记录与阶段两张表，可用表格软件打开',
              ),
            ),
            IosListItem(
              onTap: hasData ? () => _export(asJson: true, all: all) : null,
              child: _Action(
                enabled: hasData,
                title: '导出 JSON',
                subtitle: '完整数据，含阶段、声音事件与洞察',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          '文件通过系统分享面板交出，存到哪里、发给谁由你决定。'
          '音频文件本身不在导出范围内。',
          style: TextStyle(fontSize: 12, height: 1.5, color: tokens.textMuted),
        ),
      ],
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$value',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: tokens.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: tokens.textMuted),
          ),
        ],
      ),
    );
  }
}

/// 一个导出动作行。
///
/// 没有图标：设计的 24 个图标里没有表达「导出」的那一个，自绘一个就是引入一套
/// 应用其余部分没有的图标语言——与「不补垃圾桶图标」同源。
class _Action extends StatelessWidget {
  const _Action({
    required this.enabled,
    required this.title,
    required this.subtitle,
  });

  final bool enabled;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: enabled ? tokens.textPrimary : tokens.textMuted,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(fontSize: 12, color: tokens.textMuted),
              ),
            ],
          ),
        ),
        AppIcons.chevronRight(
          size: 18,
          color: enabled ? tokens.textMuted : tokens.borderStrong,
          strokeWidth: 2,
        ),
      ],
    );
  }
}
```

用到的既有 API 都已核对过，可直接照抄：`AppRadii.card`（=24）、`AppRadii.panel`（=16）、
`AppTokens.of(context)` 的 `textPrimary` / `textMuted` / `borderStrong`、
`AppIcons.chevronRight({size, color, strokeWidth})`（见 `settings_page.dart` 的现有用法）。

- [ ] **Step 5: 注册路由与设置页入口**

在 `lib/app/app.dart` 的 `_router` 里，紧跟 `settings/import` 那条之后插入：

```dart
        GoRoute(
          path: 'settings/export',
          builder: (context, state) => const ExportPage(),
        ),
```

并补导入：`import '../features/settings/presentation/export_page.dart';`

在 `lib/features/settings/presentation/settings_page.dart` 里，**「睡眠数据导入」那个
`IosListGroup` 的 `const SizedBox(height: 22)` 之后**（也就是「提醒」section 之前）插入：

```dart
        // ── Data export ────────────────────────────────────────────────────
        // 与导入分开一个 section：导入那一组用的是 group 级 onTap，
        // 把导出行塞进同一个 group 会让整组都跳去导入页。
        const SectionHeader('睡眠数据导出'),
        IosListGroup(
          onTap: () => context.go('/settings/export'),
          semanticLabel: '睡眠数据导出',
          children: [
            IosListItem(
              haptic: false,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '导出睡眠数据',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: tokens.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'CSV（记录与阶段）或 JSON（完整存档）',
                          style:
                              TextStyle(fontSize: 12, color: tokens.textMuted),
                        ),
                      ],
                    ),
                  ),
                  AppIcons.chevronRight(
                      size: 18, color: tokens.textMuted, strokeWidth: 2),
                ],
              ),
            ),
          ],
        ),
```

- [ ] **Step 6: 补上审查指出的覆盖缺口与文案一致性**

审查发现六处，都落在本任务自己的文件里。逐条：

**(a) 「已排除 N 条演示记录」多了一个句号。** `export_page.dart` 里写的是
`'已排除 $excluded 条演示记录。'`，而设计规格引的是无句号的版本，同一页另一句
「暂无可导出的记录」也**没有**句号（首页「还没有睡眠记录」、统计页「暂无统计数据」同口径）。
去掉这个句号。

**(b) 「已排除」的隐藏分支没有断言。** 用例 3–6 都用了不含演示记录的数据，但从没断言
「已排除」**不出现**——所以一个「永远渲染『已排除 0 条演示记录』」的实现能通过全部 6 条。
在用例 3 或 4 里补：`expect(find.textContaining('已排除'), findsNothing);`

**(c) 禁用态的文字降级颜色没有任何断言。** 规格明写「两个动作禁用并置灰」，而用例 1 只证明了
禁用行不会调用分享层。补一条比对颜色的断言（与启用态的颜色不同即可，不要写死具体色值）：

```dart
      // 禁用态的文字必须降级，规格明写「置灰」。
      final emptyColor = tester
          .widget<Text>(find.text('导出 CSV'))
          .style
          ?.color;
      expect(emptyColor, AppTokens.of(tester.element(find.text('导出 CSV'))).textMuted);
```

**(d) `_FakeSharer.subject` 被记录却从未被断言**——一个只写不读的死字段，
是典型的「本来打算断言却忘了」。它由设计规格钉死为 `夜深睡眠数据导出`。
在用例 4 里补：`expect(sharer.subject, '夜深睡眠数据导出');`

**(e) 用例 6（取消分享面板不弹提示）单独看可能是空转的**：它只断言「没有提示」，
如果那一次点击根本没落到按钮上（行被禁用、`onTap` 没接上），它照样通过。
补一条正向锚点让它自足：`expect(sharer.received, isNotNull);`

**(f) 用例 2 里 `findsWidgets` 比 `findsOneWidget` 松。** 给定数据下记录数 `2` 与阶段段数 `4`
各只出现一次，用严格匹配即可；宽松匹配会掩盖「页面上意外多出一个 2」这类问题。改成
`findsOneWidget`。

- [ ] **Step 7: 把新二级页并入既有的渲染守卫**

打开 `test/pages_widget_test.dart`，在它的「二级页」用例组里（与 `SleepImportPage`、
`InsightConfigPage`、`DemoDataPage` 那三处并列）加一条：

```dart
    testWidgets('导出页自己带背景与 Material 祖先', (tester) async {
      // 推入的二级页什么都继承不到。这一页也必须自己带 `Subpage`——
      // 没有它，文字会落到 Flutter 的错误样式（黄色双下划线），背景会是黑的。
      // 这个 bug 在本项目真出现过一次，所以每个二级页都要接上这条守卫。
      await pumpRoute(tester, const ExportPage());
      expectProperlyRendered(tester, '睡眠数据导出');
    });
```

补导入：`import 'package:night_sleep/features/settings/presentation/export_page.dart';`

**守在这里，不要在 `test/export_page_test.dart` 里复制一份 `expectProperlyRendered`**：
那是一段逻辑块的逐字复制，而 `pages_widget_test.dart` 已经是这条约定的家。
（该文件的 `pumpRoute` 已经不套 `Scaffold`，且它会注入 provider override；
`exportSharerProvider` 用默认实现即可——这条用例不点任何按钮，不会碰平台通道。）

- [ ] **Step 8: 跑测试，确认通过**

```bash
flutter analyze
flutter test test/export_page_test.dart
```

预期：analyze 无问题；6 个 widget 用例全部通过。

- [ ] **Step 9: 提交**

```bash
git add lib/features/settings/data/export_sharer.dart \
        lib/features/settings/presentation/export_page.dart \
        lib/app/app.dart lib/features/settings/presentation/settings_page.dart \
        test/export_page_test.dart test/pages_widget_test.dart
git commit -m "feat: 导出页、系统分享层与设置页入口"
```

**`test/pages_widget_test.dart` 不能漏**——Step 7 把新二级页并进了那个文件里的渲染守卫，
漏掉它等于新守卫没提交，而工作树看起来是干净的。

Step 6 的 (c) 要在 `test/export_page_test.dart` 顶部补一行导入：

```dart
import 'package:night_sleep/core/theme/app_tokens.dart';
```

---

### Task 4: 提醒调度器

**Files:**
- Create: `lib/core/platform/reminders.dart`
- Create: `test/reminder_scheduler_test.dart`

**Interfaces:**
- Produces:
  - `enum ReminderPermission { granted, denied, unsupported }`
  - `class ReminderPlan { const ReminderPlan({int? bedtimeMinutes, int? wakeMinutes}); }`
  - `class ReminderRequest { final int id; final int minutesOfDay; final String title; final String body; int get hour; int get minute; }`
  - `abstract interface class TimezoneResolver { Future<String> identifier(); }`、`class SystemTimezone implements TimezoneResolver`
  - `abstract class ReminderScheduler`，静态成员 `bedtimeId = 9001` / `wakeId = 9002` / `requestsFor(ReminderPlan)`，实例方法 `initialize` / `permission` / `requestPermission` / `openSystemSettings` / `sync(ReminderPlan)`，受保护方法 `cancel(int)` / `schedule(ReminderRequest)`
  - `class NoopReminderScheduler extends ReminderScheduler`
  - `class LocalReminderScheduler extends ReminderScheduler`
  - `final reminderSchedulerProvider`

- [ ] **Step 1: 写失败的测试**

创建 `test/reminder_scheduler_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/core/platform/reminders.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// 调度契约的单元测试。
///
/// `sync` 的算法放在基类里，子类只提供 `cancel` / `schedule` 两个原子动作，
/// 所以这里能用一个记录调用序列的假子类**测到真代码**，而不必碰平台通道。
class _RecordingScheduler extends ReminderScheduler {
  final calls = <String>[];

  @override
  Future<void> initialize() async {}

  @override
  Future<ReminderPermission> permission() async => ReminderPermission.granted;

  @override
  Future<ReminderPermission> requestPermission() async =>
      ReminderPermission.granted;

  @override
  Future<void> openSystemSettings() async {}

  @override
  Future<void> cancel(int id) async => calls.add('cancel:$id');

  @override
  Future<void> schedule(ReminderRequest request) async =>
      calls.add('schedule:${request.id}@${request.minutesOfDay}');
}

void main() {
  // **必须放在 `main()` 顶部，不能塞进 `setUpAll`。**
  // `group` 的回调体在**收集阶段**就执行了（`main()` 运行的时候），早于任何
  // `setUpAll`；而下面那个 group 的体内就要 `tz.getLocation(...)`。
  // 放进 `setUpAll` 会让 group 体先抛出「Tried to get location before initializing
  // timezone database」，结果是**一个用例都跑不起来**。
  tzdata.initializeTimeZones();

  test('两个通知 id 固定，便于整组替换', () {
    expect(ReminderScheduler.bedtimeId, 9001);
    expect(ReminderScheduler.wakeId, 9002);
  });

  test('requestsFor 只把开着的提醒变成请求', () {
    expect(ReminderScheduler.requestsFor(const ReminderPlan()), isEmpty);

    final bedtime = ReminderScheduler.requestsFor(
      const ReminderPlan(bedtimeMinutes: 22 * 60 + 30),
    );
    expect(bedtime, hasLength(1));
    expect(bedtime.single.id, ReminderScheduler.bedtimeId);
    expect(bedtime.single.hour, 22);
    expect(bedtime.single.minute, 30);
  });

  test('sync 先取消两个固定 id 再按计划排入', () async {
    final scheduler = _RecordingScheduler();
    await scheduler.sync(const ReminderPlan(bedtimeMinutes: 22 * 60 + 30));

    // 即使只开了一个提醒，两个 id 都要取消——否则关掉的那一个会留在系统里。
    expect(scheduler.calls, ['cancel:9001', 'cancel:9002', 'schedule:9001@1350']);
  });

  test('sync 是幂等的：连跑两次产生相同的序列', () async {
    final scheduler = _RecordingScheduler();
    const plan = ReminderPlan(bedtimeMinutes: 1350, wakeMinutes: 420);

    await scheduler.sync(plan);
    final first = List.of(scheduler.calls);
    await scheduler.sync(plan);

    expect(scheduler.calls.sublist(first.length), first,
        reason: '第二次调用必须与第一次完全一致');
    expect(first, [
      'cancel:9001',
      'cancel:9002',
      'schedule:9001@1350',
      'schedule:9002@420',
    ]);
  });

  test('空计划只取消，不排任何东西', () async {
    final scheduler = _RecordingScheduler();
    await scheduler.sync(const ReminderPlan());

    expect(scheduler.calls, ['cancel:9001', 'cancel:9002']);
  });

  test('NoopReminderScheduler 如实报告不支持', () async {
    final scheduler = NoopReminderScheduler();
    await scheduler.initialize();

    expect(await scheduler.permission(), ReminderPermission.unsupported);
    expect(
      await scheduler.requestPermission(),
      ReminderPermission.unsupported,
      reason: '不能假装权限拿到了',
    );
  });

  test('通知文案是规格钉死的那四句', () {
    final requests = ReminderScheduler.requestsFor(
      const ReminderPlan(bedtimeMinutes: 22 * 60 + 30, wakeMinutes: 7 * 60),
    );

    expect(requests.map((request) => request.title).toList(),
        ['到就寝时间了', '早上好']);
    expect(requests.map((request) => request.body).toList(),
        ['该休息了，晚安。', '记录一下昨晚睡得怎么样。']);
  });

  group('nextOccurrence', () {
    final ny = tz.getLocation('America/New_York');
    final shanghai = tz.getLocation('Asia/Shanghai');

    final wake = ReminderScheduler.requestsFor(
      const ReminderPlan(wakeMinutes: 7 * 60),
    ).single;

    test('当天该时刻还没到时，就排在当天', () {
      final next = LocalReminderScheduler.nextOccurrence(
        wake,
        now: tz.TZDateTime(shanghai, 2026, 9, 28, 3),
      );

      expect(next, tz.TZDateTime(shanghai, 2026, 9, 28, 7));
    });

    test('当天该时刻已过时，排到第二天', () {
      final next = LocalReminderScheduler.nextOccurrence(
        wake,
        now: tz.TZDateTime(shanghai, 2026, 9, 28, 9),
      );

      expect(next, tz.TZDateTime(shanghai, 2026, 9, 29, 7));
    });

    test('跨夏令时切换日，仍落在同一墙上时刻而不是绝对时刻加 24 小时', () {
      // 美国 2026 年春季切换在 3 月 8 日 02:00 → 03:00。
      // 3 月 7 日 23:00 已过 07:00，所以下一次是 3 月 8 日。
      //
      // 若把「重建墙钟时刻」错写成「today.add(Duration(days: 1))」，
      // 结果会是 3 月 8 日 08:00（EST 07:00 的绝对时刻 +24h 落在 EDT 上），
      // 这条断言会红——这正是它是可证伪的、而不是在复述实现的原因。
      final next = LocalReminderScheduler.nextOccurrence(
        wake,
        now: tz.TZDateTime(ny, 2026, 3, 7, 23),
      );

      expect(next.year, 2026);
      expect(next.month, 3);
      expect(next.day, 8);
      expect(next.hour, 7, reason: '墙上时刻必须还是 07:00');
    });
  });
}
```

- [ ] **Step 2: 跑测试，确认失败**

```bash
flutter test test/reminder_scheduler_test.dart
```

预期：编译失败，找不到 `reminders.dart`。

- [ ] **Step 3: 写实现**

创建 `lib/core/platform/reminders.dart`：

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// 系统是否真的会投递通知。
enum ReminderPermission { granted, denied, unsupported }

/// 用户当前想要的提醒。`null` 表示该项关闭。
class ReminderPlan {
  const ReminderPlan({this.bedtimeMinutes, this.wakeMinutes});

  /// 距本地午夜的分钟数。
  final int? bedtimeMinutes;
  final int? wakeMinutes;

  bool get isEmpty => bedtimeMinutes == null && wakeMinutes == null;
}

/// 调度器当前应当持有的一条通知。
class ReminderRequest {
  const ReminderRequest({
    required this.id,
    required this.minutesOfDay,
    required this.title,
    required this.body,
  });

  final int id;

  /// 距本地午夜的分钟数。
  final int minutesOfDay;
  final String title;
  final String body;

  int get hour => minutesOfDay ~/ 60;
  int get minute => minutesOfDay % 60;
}

/// 设备 IANA 时区名的来源。
///
/// 留一个接缝：`flutter_timezone` 是插件，而 `tz.local` 必须设对，
/// 否则每天重复的提醒会在夏令时切换后整体漂一小时。
abstract interface class TimezoneResolver {
  Future<String> identifier();
}

class SystemTimezone implements TimezoneResolver {
  const SystemTimezone();

  @override
  Future<String> identifier() async =>
      (await FlutterTimezone.getLocalTimezone()).identifier;
}

/// 就寝/起床提醒的调度。
///
/// `sync` 的**幂等全量重排**算法写在基类里，子类只提供 [cancel] 与 [schedule]
/// 两个原子动作——这样调度契约能在纯 Dart 测试里断言，不必碰平台通道。
abstract class ReminderScheduler {
  /// 固定的通知 id。[sync] 靠它们整组替换，陈旧调度因此活不过一次设置变更。
  static const bedtimeId = 9001;
  static const wakeId = 9002;

  static const bedtimeTitle = '到就寝时间了';
  static const bedtimeBody = '该休息了，晚安。';
  static const wakeTitle = '早上好';
  static const wakeBody = '记录一下昨晚睡得怎么样。';

  /// [plan] 要求存在的那组通知。纯函数，因此调度契约可单测。
  static List<ReminderRequest> requestsFor(ReminderPlan plan) => [
        if (plan.bedtimeMinutes != null)
          ReminderRequest(
            id: bedtimeId,
            minutesOfDay: plan.bedtimeMinutes!,
            title: bedtimeTitle,
            body: bedtimeBody,
          ),
        if (plan.wakeMinutes != null)
          ReminderRequest(
            id: wakeId,
            minutesOfDay: plan.wakeMinutes!,
            title: wakeTitle,
            body: wakeBody,
          ),
      ];

  Future<void> initialize();
  Future<ReminderPermission> permission();
  Future<ReminderPermission> requestPermission();
  Future<void> openSystemSettings();

  @protected
  Future<void> cancel(int id);

  @protected
  Future<void> schedule(ReminderRequest request);

  /// 幂等的全量重排：先取消两个固定 id，再按计划排入。
  ///
  /// 用「先取消再新建」而不是「算差异」：否则调度器的内容与数据库里的偏好会各自
  /// 拥有独立生命周期——改时区、重启、系统清理、重装都能让两者脱节——而
  /// 「开关开着却什么都不会响」是这一块最难查的 bug。少一个生命周期，
  /// 就少一整类 bug。
  Future<void> sync(ReminderPlan plan) async {
    await cancel(bedtimeId);
    await cancel(wakeId);
    for (final request in requestsFor(plan)) {
      await schedule(request);
    }
  }
}

/// 没有通知能力的平台（Web）与测试用的空实现。
class NoopReminderScheduler extends ReminderScheduler {
  @override
  Future<void> initialize() async {}

  @override
  Future<ReminderPermission> permission() async =>
      ReminderPermission.unsupported;

  @override
  Future<ReminderPermission> requestPermission() async =>
      ReminderPermission.unsupported;

  @override
  Future<void> openSystemSettings() async {}

  @override
  Future<void> cancel(int id) async {}

  @override
  Future<void> schedule(ReminderRequest request) async {}
}

/// 包 `flutter_local_notifications` 的实现。
class LocalReminderScheduler extends ReminderScheduler {
  LocalReminderScheduler({
    FlutterLocalNotificationsPlugin? plugin,
    TimezoneResolver timezone = const SystemTimezone(),
  })  : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
        _timezone = timezone;

  static const _channelId = 'night_sleep_reminders';
  static const _channelName = '睡眠提醒';
  static const _channelDescription = '就寝与起床提醒';

  final FlutterLocalNotificationsPlugin _plugin;
  final TimezoneResolver _timezone;

  bool _ready = false;

  /// **可重入，且只有成功才算初始化过。**
  ///
  /// 失败时保留未初始化状态，下一次调用会重试。反过来的写法（进函数先置
  /// 「已初始化」）会把一次**偶发**的时区查询失败变成整个进程生命周期的静默失效——
  /// 用户打开提醒开关，什么都不会响，而且没有任何办法在这一进程里恢复。
  @override
  Future<void> initialize() async {
    if (_ready) return;

    try {
      // 必须两步：initializeTimeZones() 之后 tz.local 默认是 UTC，
      // 不设成设备时区的话，提醒会在错误的时刻响。
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation(await _timezone.identifier()));

      // v20 起这个插件的 `initialize` 改成了具名参数，别写回位置参数。
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            // 权限留到用户真的打开提醒开关时再申请，不在首次启动时弹。
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
          macOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );
      _ready = true;
    } catch (_) {
      // 取不到可用时区就无从按墙上时间调度。如实降级，不猜一个时区。
      _ready = false;
    }
  }

  @override
  Future<ReminderPermission> permission() async {
    if (!_ready) return ReminderPermission.unsupported;

    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return _fromDarwin(
          await _plugin
              .resolvePlatformSpecificImplementation<
                  IOSFlutterLocalNotificationsPlugin>()
              ?.checkPermissions(),
        );
      case TargetPlatform.macOS:
        return _fromDarwin(
          await _plugin
              .resolvePlatformSpecificImplementation<
                  MacOSFlutterLocalNotificationsPlugin>()
              ?.checkPermissions(),
        );
      case TargetPlatform.android:
        return _fromBool(
          await _plugin
              .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin>()
              ?.areNotificationsEnabled(),
        );
      default:
        return ReminderPermission.unsupported;
    }
  }

  @override
  Future<ReminderPermission> requestPermission() async {
    if (!_ready) return ReminderPermission.unsupported;

    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return _fromBool(
          await _plugin
              .resolvePlatformSpecificImplementation<
                  IOSFlutterLocalNotificationsPlugin>()
              ?.requestPermissions(alert: true, sound: true),
        );
      case TargetPlatform.macOS:
        return _fromBool(
          await _plugin
              .resolvePlatformSpecificImplementation<
                  MacOSFlutterLocalNotificationsPlugin>()
              ?.requestPermissions(alert: true, sound: true),
        );
      case TargetPlatform.android:
        return _fromBool(
          await _plugin
              .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin>()
              ?.requestNotificationsPermission(),
        );
      default:
        return ReminderPermission.unsupported;
    }
  }

  @override
  Future<void> openSystemSettings() async {
    if (!_ready) return;
    try {
      switch (defaultTargetPlatform) {
        case TargetPlatform.iOS:
          await _plugin
              .resolvePlatformSpecificImplementation<
                  IOSFlutterLocalNotificationsPlugin>()
              ?.openAppNotificationSettings();
        case TargetPlatform.macOS:
          await _plugin
              .resolvePlatformSpecificImplementation<
                  MacOSFlutterLocalNotificationsPlugin>()
              ?.openAppNotificationSettings();
        default:
          return;
      }
    } catch (_) {
      // 某些系统版本上跳转可能失败；界面上那行说明已经告诉用户去哪里了。
    }
  }

  @override
  Future<void> cancel(int id) async {
    if (!_ready) return;
    await _plugin.cancel(id: id);
  }

  @override
  Future<void> schedule(ReminderRequest request) async {
    if (!_ready) return;

    await _plugin.zonedSchedule(
      id: request.id,
      title: request.title,
      body: request.body,
      // 按**墙上时间**重复，因此夏令时切换后提醒跟着走，而不是漂一小时。
      matchDateTimeComponents: DateTimeComponents.time,
      scheduledDate: nextOccurrence(
        request,
        now: tz.TZDateTime.now(tz.local),
      ),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          // 前台也要展示，否则应用开着时什么都看不到。
          presentAlert: true,
          presentBanner: true,
          presentList: true,
          presentSound: true,
        ),
        macOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBanner: true,
          presentList: true,
          presentSound: true,
        ),
      ),
      // 刻意用非精确闹钟：Android 14+ 的精确闹钟要么多一个
      // SCHEDULE_EXACT_ALARM 申请流程，要么用需要上架审核的 USE_EXACT_ALARM，
      // 而「该睡了」差几分钟完全无所谓。
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  /// 从 [now] 起，下一次该时刻落在哪。
  ///
  /// 做成**纯函数**：`now` 由调用方给，时区取自 `now.location` 而不是全局的
  /// `tz.local`。除了让依赖显式化，更要紧的是这样测试才能钉住**夏令时**那条规则——
  /// 跨切换日时提醒必须仍在同样的**墙上时刻**响，而不是「前一次的绝对时刻 + 24 小时」。
  /// 那是这段代码里唯一一处不写测试就只能靠读注释相信的地方。
  @visibleForTesting
  static tz.TZDateTime nextOccurrence(
    ReminderRequest request, {
    required tz.TZDateTime now,
  }) {
    final location = now.location;
    final today = tz.TZDateTime(
      location,
      now.year,
      now.month,
      now.day,
      request.hour,
      request.minute,
    );
    if (today.isAfter(now)) return today;

    // 用「下一天 + 同一墙钟时刻」重建，而不是加 24 小时——后者跨夏令时会落到
    // 另一个钟点上（美国 2026-03-08 那次切换会让 07:00 变成 08:00）。
    return tz.TZDateTime(
      location,
      now.year,
      now.month,
      now.day + 1,
      request.hour,
      request.minute,
    );
  }

  static ReminderPermission _fromDarwin(NotificationsEnabledOptions? options) =>
      options == null
          ? ReminderPermission.unsupported
          : (options.isEnabled
              ? ReminderPermission.granted
              : ReminderPermission.denied);

  static ReminderPermission _fromBool(bool? enabled) => enabled == null
      ? ReminderPermission.unsupported
      : (enabled ? ReminderPermission.granted : ReminderPermission.denied);
}

/// 按平台选择实现。
///
/// Web 必须**显式排除**：`defaultTargetPlatform` 在 Web 上报告的是宿主操作系统，
/// 靠它判断会让 Web 走进 iOS/macOS 的分支。
final reminderSchedulerProvider = Provider<ReminderScheduler>((ref) {
  if (kIsWeb) return NoopReminderScheduler();
  return LocalReminderScheduler();
});
```

- [ ] **Step 4: 跑测试与静态检查**

```bash
flutter analyze
flutter test test/reminder_scheduler_test.dart
```

预期：analyze 无问题；10 个用例通过（6 个调度契约 + 1 个文案 + 3 个 nextOccurrence）。

- [ ] **Step 5: 提交**

```bash
git add lib/core/platform/reminders.dart test/reminder_scheduler_test.dart
git commit -m "feat: 提醒调度器与幂等全量重排"
```

---

### Task 5: 设置页的提醒接线

**Files:**
- Modify: `lib/features/settings/presentation/settings_page.dart`
- Create: `test/reminder_settings_test.dart`

**Interfaces:**
- Consumes: `ReminderScheduler`、`ReminderPlan`、`ReminderPermission`、`reminderSchedulerProvider`（Task 4）
- Produces: `final reminderPermissionProvider`（`FutureProvider<ReminderPermission>`，定义在 `settings_page.dart`）

- [ ] **Step 1: 写失败的测试**

创建 `test/reminder_settings_test.dart`：

```dart
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/app/app.dart';
import 'package:night_sleep/app/app_toast.dart';
import 'package:night_sleep/core/database/app_database.dart';
import 'package:night_sleep/core/platform/reminders.dart';
import 'package:night_sleep/core/theme/app_theme.dart';
import 'package:night_sleep/core/widgets/ios_controls.dart';
import 'package:night_sleep/features/settings/presentation/settings_page.dart';
import 'package:night_sleep/features/sleep/data/sleep_repository.dart';

class _FakeScheduler extends ReminderScheduler {
  _FakeScheduler({
    this.grants = false,
    ReminderPermission current = ReminderPermission.denied,
  }) : _current = current;

  final bool grants;
  ReminderPermission _current;
  int settingsOpened = 0;
  ReminderPlan? lastSynced;

  @override
  Future<void> initialize() async {}

  @override
  Future<ReminderPermission> permission() async => _current;

  @override
  Future<ReminderPermission> requestPermission() async {
    _current = grants ? ReminderPermission.granted : ReminderPermission.denied;
    return _current;
  }

  @override
  Future<void> openSystemSettings() async => settingsOpened++;

  @override
  Future<void> cancel(int id) async {}

  @override
  Future<void> schedule(ReminderRequest request) async {}

  @override
  Future<void> sync(ReminderPlan plan) async => lastSynced = plan;
}

void main() {
  late AppDatabase database;

  setUp(() => database = AppDatabase(NativeDatabase.memory()));
  tearDown(() => database.close());

  AppSetting settings() => AppSetting(
        id: 'default',
        themeMode: 'system',
        sleepGoalMinutes: 480,
        bedtimeReminderEnabled: false,
        bedtimeReminderMinutes: 22 * 60 + 30,
        wakeReminderEnabled: false,
        wakeReminderMinutes: 7 * 60,
        soundRecordingEnabled: false,
        onboarded: true,
        insightProvider: null,
        insightModel: null,
      );

  /// [SettingsPage] 是标签页，真机上确实活在壳的 Scaffold 里，所以这里给一个。
  Future<void> pumpSettings(WidgetTester tester, ReminderScheduler scheduler) async {
    tester.view.physicalSize = const Size(430, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          sleepEntriesProvider.overrideWith((ref) => const []),
          settingsProvider.overrideWith((ref) => Stream.value(settings())),
          reminderSchedulerProvider.overrideWithValue(scheduler),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: SettingsPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 设置页里前两个开关依次是就寝提醒与起床提醒，第三个是夜间声音录制。
  Finder reminderToggle(int index) => find.byType(IosToggle).at(index);

  /// 提示条的文字。
  ///
  /// 测试树里**没有** `ToastOverlay`——它活在应用外壳 `AppScaffold` 里，而这个
  /// 测试只挂了 `SettingsPage`。所以不能用 `find.text`，只能直接读 provider。
  String? toastOf(WidgetTester tester) => ProviderScope.containerOf(
        tester.element(find.byType(SettingsPage)),
      ).read(toastProvider);

  testWidgets('权限被拒时开关回弹且不写库', (tester) async {
    final scheduler = _FakeScheduler(grants: false);
    await pumpSettings(tester, scheduler);

    await tester.tap(reminderToggle(0));
    await tester.pumpAndSettle();

    final row = await database.getSettings();
    expect(row.bedtimeReminderEnabled, isFalse,
        reason: '被拒时不得写入一个开了却不会响的偏好');
    expect(scheduler.lastSynced, isNull, reason: '没开成就不必重排');
    expect(toastOf(tester), contains('没有获得通知权限'));
  });

  testWidgets('权限被授予时写入偏好并按计划重排', (tester) async {
    final scheduler = _FakeScheduler(grants: true);
    await pumpSettings(tester, scheduler);

    await tester.tap(reminderToggle(0));
    await tester.pumpAndSettle();

    final row = await database.getSettings();
    expect(row.bedtimeReminderEnabled, isTrue);
    expect(scheduler.lastSynced?.bedtimeMinutes, 22 * 60 + 30);
    expect(scheduler.lastSynced?.wakeMinutes, isNull, reason: '起床提醒还关着');
  });

  testWidgets('权限不是 granted 时给出「去系统设置」入口', (tester) async {
    final scheduler = _FakeScheduler(current: ReminderPermission.denied);
    await pumpSettings(tester, scheduler);

    expect(find.textContaining('未获得通知权限'), findsOneWidget);

    await tester.tap(find.textContaining('未获得通知权限'));
    await tester.pumpAndSettle();
    expect(scheduler.settingsOpened, 1);
  });

  testWidgets('权限已授予时不显示「去系统设置」入口', (tester) async {
    final scheduler = _FakeScheduler(current: ReminderPermission.granted);
    await pumpSettings(tester, scheduler);

    expect(find.textContaining('未获得通知权限'), findsNothing);
  });

  testWidgets('平台不支持时如实说明，不假装已开启', (tester) async {
    final scheduler = _FakeScheduler(current: ReminderPermission.unsupported);
    await pumpSettings(tester, scheduler);

    await tester.tap(reminderToggle(0));
    await tester.pumpAndSettle();

    final row = await database.getSettings();
    expect(row.bedtimeReminderEnabled, isFalse);
    expect(toastOf(tester), contains('无法安排本地通知'));
  });
}
```

- [ ] **Step 2: 跑测试，确认失败**

```bash
flutter test test/reminder_settings_test.dart
```

预期：失败——开关点了以后没有任何权限流程，`bedtimeReminderEnabled` 直接变成 `true`
（第一个用例的 `isFalse` 断言不成立），且找不到「没有获得通知权限」文案。

- [ ] **Step 3: 写实现**

在 `lib/features/settings/presentation/settings_page.dart` 里：

顶部补导入：

```dart
import '../../../core/platform/reminders.dart';
```

在文件里、`SettingsPage` 类之外定义权限 provider：

```dart
/// 系统通知权限的最近一次观测结果。
///
/// 插件分不清「从未询问」与「已被拒绝」——两者都返回 `isEnabled: false`——
/// 所以界面也不去分。只要不是 granted，就说明提醒此刻响不了。
final reminderPermissionProvider = FutureProvider<ReminderPermission>((ref) {
  return ref.watch(reminderSchedulerProvider).permission();
});
```

在 `SettingsPage` 里新增两个方法：

```dart
  /// 切换一个提醒开关。
  ///
  /// 开启前先向系统申请权限。被拒（或平台根本不支持）时**不改动已存的偏好**，
  /// 让开关自己弹回去：一个写着「开」却什么都不会响的偏好，正是规格书要消灭的
  /// 那类假状态。
  Future<void> _setReminder(
    BuildContext context,
    WidgetRef ref, {
    required bool bedtime,
    required bool value,
  }) async {
    final scheduler = ref.read(reminderSchedulerProvider);

    if (value) {
      final permission = await scheduler.requestPermission();
      if (permission != ReminderPermission.granted) {
        if (!context.mounted) return;
        // 这里不说「这个平台不支持」：走到这一步也可能是**这台设备上**取不到可用
        // 时区导致的初始化失败，那是应用侧的问题，不是平台的限制。两种情况都成立的
        // 实话是「当前设备无法安排本地通知」。
        ref.read(toastProvider.notifier).show(
              permission == ReminderPermission.unsupported
                  ? '当前设备无法安排本地通知，提醒未开启。'
                  : '没有获得通知权限，提醒未开启。可在系统设置中允许「夜深」发送通知。',
            );
        ref.invalidate(reminderPermissionProvider);
        return;
      }
    }

    await _update(
      ref,
      bedtime
          ? AppSettingsCompanion(bedtimeReminderEnabled: Value(value))
          : AppSettingsCompanion(wakeReminderEnabled: Value(value)),
    );
    ref.invalidate(reminderPermissionProvider);
    await _syncReminders(ref);
  }

  /// 把已调度的通知重排成与数据库里的偏好一致。
  Future<void> _syncReminders(WidgetRef ref) async {
    final stored = await ref.read(databaseProvider).getSettings();
    await ref.read(reminderSchedulerProvider).sync(
          ReminderPlan(
            bedtimeMinutes: stored.bedtimeReminderEnabled
                ? stored.bedtimeReminderMinutes
                : null,
            wakeMinutes: stored.wakeReminderEnabled
                ? stored.wakeReminderMinutes
                : null,
          ),
        );
  }
```

把两个 `IosToggle` 的 `onChanged` 改成走新方法：

```dart
                  IosToggle(
                    value: bedtimeEnabled,
                    semanticLabel: '就寝提醒',
                    onChanged: (value) => _setReminder(
                      context,
                      ref,
                      bedtime: true,
                      value: value,
                    ),
                  ),
```

```dart
                  IosToggle(
                    value: wakeEnabled,
                    semanticLabel: '起床提醒',
                    onChanged: (value) => _setReminder(
                      context,
                      ref,
                      bedtime: false,
                      value: value,
                    ),
                  ),
```

在 `_pickReminderTime` 的末尾（写完时间之后）补一行 `await _syncReminders(ref);`，
这样改时间也会立刻重排。

在 `build` 里读权限：

```dart
    final permission = ref.watch(reminderPermissionProvider).valueOrNull;
```

并在「提醒」那个 `IosListGroup` 之后（下一个 `const SizedBox(height: 22)` 之前）插入：

```dart
        // 权限不是 granted 就说明提醒此刻响不了。文案中性、不预设历史：
        // 插件不区分「从未询问」与「已被拒绝」，编一个状态反而会说谎。
        if (permission != null && permission != ReminderPermission.granted) ...[
          const SizedBox(height: 10),
          IosListGroup(
            onTap: () => ref.read(reminderSchedulerProvider).openSystemSettings(),
            semanticLabel: '去系统设置开启通知权限',
            children: [
              IosListItem(
                haptic: false,
                child: Row(
                  children: [
                    AppIcons.bed(
                        size: 16, color: tokens.textMuted, strokeWidth: 1.8),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '未获得通知权限。提醒开关打开后若收不到通知，'
                        '请到这里允许「夜深」发送通知。',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: tokens.textMuted,
                        ),
                      ),
                    ),
                    AppIcons.chevronRight(
                        size: 16, color: tokens.borderStrong, strokeWidth: 2),
                  ],
                ),
              ),
            ],
          ),
        ],
```

- [ ] **Step 4: 跑测试，确认通过**

```bash
flutter analyze
flutter test test/reminder_settings_test.dart
```

预期：analyze 无问题；5 个用例通过。

- [ ] **Step 5: 提交**

```bash
git add lib/features/settings/presentation/settings_page.dart test/reminder_settings_test.dart
git commit -m "feat: 设置页提醒开关接真实通知权限，拒绝时不写库"
```

---

### Task 6: 启动接线与平台配置

**Files:**
- Modify: `lib/main.dart`
- Modify: `ios/Runner/AppDelegate.swift`
- Modify: `macos/Runner/AppDelegate.swift`

**Interfaces:**
- Consumes: `LocalReminderScheduler`、`ReminderScheduler.sync`、`ReminderPlan`、`reminderSchedulerProvider`、`AppDatabase.getSettings` / `updateSettings`

- [ ] **Step 1: 写启动接线**

把 `lib/main.dart` 整体改成：

```dart
import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/config/app_config.dart';
import 'core/database/app_database.dart';
import 'core/platform/reminders.dart';
import 'features/sleep/data/demo_seed.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final database = await AppDatabase.open();
  final scheduler = LocalReminderScheduler();
  await scheduler.initialize();

  // Demo rows are installed once, and only in builds where the flag is on.
  //
  // The condition is "no demo rows yet" rather than "the table is empty", so
  // turning the flag on later actually takes effect. Existing real records are
  // never touched: demo rows carry `source = 'demo'`, the UI badges them, and
  // `deleteDemoData` removes only those rows.
  if (AppConfig.demoDataEnabled) {
    final existing = await database.allRecords();
    final hasDemo = existing.any((row) => row.source == AppConfig.demoSource);
    if (!hasDemo) {
      await DemoSeed.install(database);
    }
  }

  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(database),
        reminderSchedulerProvider.overrideWithValue(scheduler),
      ],
      child: const NightSleepApp(),
    ),
  );

  // 排通知不该挡着启动，失败也不该让应用起不来。
  unawaited(_reconcileReminders(database, scheduler));
}

/// 让已调度的通知与数据库里的偏好保持一致。每次启动都跑。
///
/// 有两件事会脱节：改时区或系统清理会让已排的调度悄悄消失；而用户在系统设置里
/// 撤销授权后，偏好仍然写着「开」却再也响不了。后一种在这里被**修好**而不是仅仅
/// 显示出来——设置页因此永远不会出现一个说谎的开关。
Future<void> _reconcileReminders(
  AppDatabase database,
  ReminderScheduler scheduler,
) async {
  try {
    final stored = await database.getSettings();
    final wantsBedtime = stored.bedtimeReminderEnabled;
    final wantsWake = stored.wakeReminderEnabled;
    final permission = await scheduler.permission();

    if (permission != ReminderPermission.granted &&
        (wantsBedtime || wantsWake)) {
      // 偏好为真只可能来自一次成功授权，所以走到这里基本只有一种可能：
      // 用户在应用之外撤销了授权。
      await database.updateSettings(
        const AppSettingsCompanion(
          bedtimeReminderEnabled: Value(false),
          wakeReminderEnabled: Value(false),
        ),
      );
      await scheduler.sync(const ReminderPlan());
      return;
    }

    await scheduler.sync(
      ReminderPlan(
        bedtimeMinutes: wantsBedtime ? stored.bedtimeReminderMinutes : null,
        wakeMinutes: wantsWake ? stored.wakeReminderMinutes : null,
      ),
    );
  } catch (_) {
    // 调度是尽力而为：排不上提醒不该影响任何别的功能。
  }
}
```

- [ ] **Step 2: 改 iOS 与 macOS 的 AppDelegate**

`ios/Runner/AppDelegate.swift` 整体改成：

```swift
import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 没有 delegate 时，应用在前台收到的本地通知会被系统压掉——
    // 表现为「提醒到点了却什么都没出现」。
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
```

`macos/Runner/AppDelegate.swift` 整体改成：

```swift
import Cocoa
import FlutterMacOS
import UserNotifications

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func application(
    _ application: NSApplication,
    didFinishLaunchingWithOptions launchOptions: [String: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
```

- [ ] **Step 3: 验证构建与测试**

```bash
export PUB_HOSTED_URL=https://pub.flutter-io.cn FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
export HTTPS_PROXY=http://127.0.0.1:7890 HTTP_PROXY=http://127.0.0.1:7890

dart format .
flutter analyze
flutter test
flutter build macos --debug
flutter build ios --simulator --no-codesign
```

预期：analyze 无问题；测试全部通过；两个构建成功产出。
**若 `flutter build ios --simulator --no-codesign` 因网络失败**，记下失败原因并在
「风险与已知问题」里如实记录，不要声称 iOS 构建已验证。

- [ ] **Step 4: 提交**

```bash
git add lib/main.dart ios/Runner/AppDelegate.swift macos/Runner/AppDelegate.swift
git commit -m "feat: 启动时重排提醒，iOS/macOS 设通知 delegate"
```

---

### Task 7: 文档同步与终验

**Files:**
- Modify: `docs/superpowers/specs/2026-09-28-night-sleep-design.md`
- Modify: `README.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: 更新规格书**

`docs/superpowers/specs/2026-09-28-night-sleep-design.md`：

1. 头部版本 `2.4` → `2.5`。
2. §2.4 页面清单加「导出页（`/settings/export`）」。
3. §3 路由映射表加 `/settings/export`。
4. §4 M2 的第 1、2 条改为已完成，并补一句实现口径（导出只含真实记录、JSON 不写
   `localUri` 与设置；提醒权限被拒时不写偏好、启动时回收被撤销的授权）。
5. §6 技术方案的「网络」那条补一句：新增的四个依赖都不发起网络请求，
   **应用对外的请求仍然只有「获取可用模型」一处**。
6. §8 偏差表追加两条：
   - **#18** 原型没有导出功能 | 本实现新增导出（CSV 两张表 + JSON 完整存档），
     经系统分享面板交付 | 规格 M2 要求本地导出，而原型是纯前端演示。
     回归方法：确认设置页有「睡眠数据导出」section、导出的 CSV 带 BOM。
   - **#19** 原型的提醒开关是纯装饰 | 本实现接真实本地通知，权限被拒时不写入偏好，
     并在权限不为 granted 时给出「去系统设置」入口 | 一个写着「开」却不会响的开关
     正是规格书说的「设置状态与实际能力不一致」。回归方法：拒绝通知权限后确认
     `bedtimeReminderEnabled` 仍为 false。
7. §9 测试矩阵追加三行（`test/sleep_export_test.dart`、`test/export_page_test.dart`、
   `test/reminder_scheduler_test.dart` + `test/reminder_settings_test.dart`），
   并在「集成/真机」一行补「通知投递与分享面板**未验证**」。
8. §10 外部资料清单里，通知权限的用途说明文案改为「已接入通知，文案见 `reminders.dart`；
   麦克风用途文案仍待提供」。

- [ ] **Step 2: 更新 README**

`README.md`：

1. 「当前实现范围」加两条：**数据导出**（CSV 两张表 / JSON 完整存档，经系统分享面板交付，
   只含真实记录）、**提醒**（就寝/起床本地通知、权限被拒时不写偏好）。
2. 「未实现」表删掉「导出 CSV / JSON」与「通知提醒」两行；「夜间录音」一行的说明补一句
   录音仍未接入；**新增一行**：

   | 能力 | 现状 |
   | --- | --- |
   | Android 平台 | 平台目录未生成（`.metadata` 只有 ios / macos / web）。接入时需补 `RECEIVE_BOOT_COMPLETED` 权限与 `ScheduledNotificationReceiver` / `ScheduledNotificationBootReceiver` 两个 receiver，否则重启后提醒不再重排 |

3. 「验证记录」按实际跑出来的结果更新，并明确列出**未验证**项：
   真实通知投递（需真机/模拟器人工确认）、系统分享面板实测、macOS 上未签名调试构建的
   通知授权行为。
4. 若 Android 那一行写进 README，同时修正原文「Android/Web 骨架在但未构建」的措辞——
   Web 有骨架，Android 没有。

- [ ] **Step 3: 更新 CHANGELOG**

在 `CHANGELOG.md` 顶部插入新版本（版本号与规格头部一致）：

```markdown
## 2.5（2026-09-28）

M2 剩下的两块落地，只剩小米导入仍被外部资料阻塞。

① **导出**：新增 `/settings/export`。CSV 两张表（记录 + 阶段，UTF-8 BOM、CRLF、
备注转义），JSON 为完整嵌套存档。字段名与 schema 对齐，为将来回灌留路；**不写
`localUri`**（改写成 `hasLocalAudio`，因为音频本身不进导出、路径只会悬空，
而导出是要分享出去的），**不导出 `AppSettings`**（设备偏好，且顺带把 API Key
从结构上排除）。演示记录一律不进文件并计数说明。经系统分享面板交付。

② **提醒**：就寝/起床接真实本地通知。`sync` 是**幂等全量重排**（固定 id 先取消再排），
并在每次启动重排，因此调度与偏好没有各自独立的生命周期。权限被拒时**不写入偏好**、
开关回弹；启动时若发现偏好为真而权限已不是 granted（用户在系统设置里撤销过），
把偏好写回 false 而不是留一个说谎的开关。

新增依赖 `flutter_local_notifications` / `timezone` / `flutter_timezone` / `share_plus`，
均不发起网络请求。新增偏差 #18、#19。
```

- [ ] **Step 4: 终验**

```bash
dart format --set-exit-if-changed .
flutter analyze
flutter test
```

预期：format 无改动；analyze 无问题；测试全部通过。

再手工核对一次：

```bash
# 生成的 CSV 头部确实带 BOM（EF BB BF）
grep -c $'\xEF\xBB\xBF' /tmp/导出核对.csv

# 导出内容里不应出现任何本地路径字段
grep -o 'localUri\|/var/mobile\|/Users/' /tmp/导出核对.json || echo "干净：没有本地路径"
```

（`/tmp/导出核对.*` 由模拟器/桌面运行一次导出后取回；取不到就跳过，
并在 README 验证记录里如实标注该步未执行。）

- [ ] **Step 5: 提交**

```bash
git add docs/superpowers/specs/2026-09-28-night-sleep-design.md README.md CHANGELOG.md
git commit -m "docs: 同步规格、README 与变更史至 2.5"
```

---

## 风险与已知问题

- **macOS 通知需要应用被签名或位于 `/Applications` 才能稳定授权。** 本机调试构建未签名，
  权限可能拿不到或不持久。实现上按 `permission()` 的真实返回降级（界面照实显示），
  但这一项**只能人工验证**，不得写成已完成。
- **Android 无法验证**：平台目录不存在，本机也没有 Android SDK。Dart 侧的 Android 分支
  按插件文档写就，但没有构建过。
- **`test/sleep_export_test.dart` 不写死本地时刻**：`SleepEntry` 的墙钟标签由
  `toLocal()` 派生，随跑测试的机器时区变化，所以断言一律用领域对象自己的 getter 拼期望值。
  若日后有人改成写死字符串，测试会在别的时区上假失败。
- **应用版本号没有单一来源**（`pubspec.yaml` 是 `0.1.0+1`，设置页硬编码 `v2.0.0`），
  因此导出文件的表头不写 `appVersion`。这是本轮**发现但未修**的问题。
