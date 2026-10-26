import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/core/telemetry/event_log.dart';

/// FileEventLog 的数据层测试：真文件、真 I/O，只用临时目录绕开平台通道。
void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('event_log_test');
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  FileEventLog makeLog({int maxEntries = 500}) => FileEventLog(
        directory: () async => temp,
        maxEntries: maxEntries,
      );

  File logFile() => File(
        '${temp.path}${Platform.pathSeparator}telemetry'
        '${Platform.pathSeparator}events.jsonl',
      );

  test('track 之后 readAll 按从旧到新的顺序读回', () async {
    final log = makeLog();
    log.track('app_start');
    log.track('tab_select', {'to': 'stats'});
    await log.flush();

    final entries = await log.readAll();
    expect(entries, hasLength(2));
    expect(entries[0].event, 'app_start');
    expect(entries[0].data, isEmpty);
    expect(entries[1].event, 'tab_select');
    expect(entries[1].data, {'to': 'stats'});
  });

  test('记录跨实例留存（重启后还能读到）', () async {
    final first = makeLog();
    first.track('app_start');
    await first.flush();

    // 新实例内存里没有缓存，只能从磁盘读——等价于进程重启后的读取路径。
    final second = makeLog();
    expect((await second.readAll()).single.event, 'app_start');
  });

  test('超过上限时丢最旧的，保留最新的 maxEntries 条', () async {
    final log = makeLog(maxEntries: 3);
    for (var i = 0; i < 5; i++) {
      log.track('e$i');
    }
    await log.flush();

    final events = (await log.readAll()).map((entry) => entry.event).toList();
    expect(events, ['e2', 'e3', 'e4']);
  });

  test('clear 之后再读是空的，新实例也读不到', () async {
    final log = makeLog();
    log.track('app_start');
    await log.flush();

    await log.clear();
    expect(await log.readAll(), isEmpty);

    final reopened = makeLog();
    expect(await reopened.readAll(), isEmpty);
  });

  test('导出内容是带 count 与 entries 的 JSON', () async {
    final log = makeLog();
    log.track('app_start');
    log.track('session_start', {'scene': 'rain'});
    await log.flush();

    final decoded =
        jsonDecode(await log.exportContent()) as Map<String, Object?>;
    expect(decoded['count'], 2);
    final entries = decoded['entries'] as List<Object?>;
    expect((entries[1] as Map<String, Object?>)['event'], 'session_start');
    expect(
      (entries[1] as Map<String, Object?>)['data'],
      {'scene': 'rain'},
    );
  });

  test('文件里的半行坏记录被跳过，不连坐整份日志', () async {
    final good = EventLogEntry(
      time: DateTime.utc(2026, 10, 25, 8),
      event: 'app_start',
    );
    await logFile().parent.create(recursive: true);
    await logFile().writeAsString(
      '{"time":"2026-10-25T08:00:00.000Z","event":"app_start"}\n'
      '{"time":"2026-10-25T0\n',
    );

    final log = makeLog();
    final entries = await log.readAll();
    expect(entries, hasLength(1));
    expect(entries.single.time, good.time);
    expect(entries.single.event, 'app_start');
  });
}
