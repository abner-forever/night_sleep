import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// 一条埋点记录。
///
/// [data] 只放**结构化、非敏感**的字段（开关状态、场景 id、条数这类）。
/// 自由文本备注、录音内容与 API Key 永远不进这里——埋点只在本机留存、
/// 由用户主动导出，但既然会离开进程，就要按「会被看见」的标准写。
class EventLogEntry {
  const EventLogEntry({
    required this.time,
    required this.event,
    this.data = const {},
  });

  factory EventLogEntry.fromJson(Map<String, Object?> json) {
    final time = DateTime.tryParse(json['time'] as String? ?? '');
    final event = json['event'] as String?;
    if (time == null || event == null || event.isEmpty) {
      throw const FormatException('埋点记录字段缺失');
    }
    final data = json['data'];
    return EventLogEntry(
      time: time,
      event: event,
      data: data is Map<String, Object?> ? data : const {},
    );
  }

  final DateTime time;
  final String event;
  final Map<String, Object?> data;

  Map<String, Object?> toJson() => {
        'time': time.toIso8601String(),
        'event': event,
        if (data.isNotEmpty) 'data': data,
      };
}

/// 本地埋点日志。
///
/// **只记、不上传。** 记录写在应用支持目录的一个 JSONL 文件里，超出
/// [FileEventLog.maxEntries] 后丢最旧的；查看、导出与清空都由用户在
/// 设置页的「运行日志」里主动发起。
abstract interface class EventLog {
  /// 记一条埋点。**fire-and-forget**：写盘失败只打一行调试日志，
  /// 绝不打断调用方的业务流程。
  void track(String event, [Map<String, Object?> data]);

  /// 全部留存记录，按时间**从旧到新**排序。
  Future<List<EventLogEntry>> readAll();

  /// 导出用的 JSON 文本（带缩进，人能直接读）。
  Future<String> exportContent();

  /// 清空全部记录。
  Future<void> clear();
}

class FileEventLog implements EventLog {
  /// [directory] 只给测试用，用来绕开 `getApplicationSupportDirectory()`
  /// （它要平台通道）。生产路径永远是 null。
  ///
  /// 有这条缝才测得到真东西：这个功能的意义就是**写对文件、读回记录**，
  /// 拿个假实现去测等于什么都没测。
  FileEventLog({
    Future<Directory> Function()? directory,
    this.maxEntries = 500,
  }) : _resolveDirectory = directory ?? _defaultDirectory;

  /// 应用支持目录（不是临时目录）：埋点要跨启动留存，不该被「清除缓存」清掉。
  static Future<Directory> _defaultDirectory() =>
      getApplicationSupportDirectory();

  final Future<Directory> Function() _resolveDirectory;
  final int maxEntries;

  File? _file;
  List<EventLogEntry>? _cache;

  /// 串行化全部写操作：并发 `track` / `clear` 时按发起顺序落盘，
  /// 不会把两份内容交错写进同一个文件。
  Future<void>? _pending;

  Future<File> _resolveFile() async {
    final existing = _file;
    if (existing != null) return existing;
    final directory = Directory(
      path.join((await _resolveDirectory()).path, 'telemetry'),
    );
    await directory.create(recursive: true);
    return _file = File(path.join(directory.path, 'events.jsonl'));
  }

  /// 首次访问时把文件读进内存；此后内存里的列表就是唯一真源，
  /// 每次追加都整份重写文件（记录最多几百条，重写比行级追加简单可靠）。
  Future<List<EventLogEntry>> _load() async {
    final cached = _cache;
    if (cached != null) return cached;
    final entries = <EventLogEntry>[];
    try {
      final file = await _resolveFile();
      if (await file.exists()) {
        for (final line in await file.readAsLines()) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) continue;
          try {
            entries.add(
              EventLogEntry.fromJson(
                jsonDecode(trimmed) as Map<String, Object?>,
              ),
            );
          } on FormatException {
            // 进程在写到一半时被杀会留下半行。坏行跳过，不连坐整个文件。
          }
        }
      }
    } on FileSystemException {
      // 读不到就从空开始记：埋点是旁路信息，不值得让应用为它失败。
    }
    return _cache = entries;
  }

  @override
  void track(String event, [Map<String, Object?> data = const {}]) {
    final entry = EventLogEntry(
      time: DateTime.now(),
      event: event,
      data: Map.of(data),
    );
    unawaited(_enqueue(() => _doAppend(entry)));
  }

  @override
  Future<List<EventLogEntry>> readAll() async => List.of(await _load());

  @override
  Future<String> exportContent() async {
    final entries = await readAll();
    return const JsonEncoder.withIndent('  ').convert({
      'app': 'night_sleep',
      'exportedAt': DateTime.now().toIso8601String(),
      'count': entries.length,
      'entries': [for (final entry in entries) entry.toJson()],
    });
  }

  @override
  Future<void> clear() => _enqueue(() async {
        _cache = <EventLogEntry>[];
        try {
          final file = await _resolveFile();
          if (await file.exists()) {
            await file.writeAsString('', flush: true);
          }
        } on FileSystemException catch (error) {
          // 内存里已经清了；文件删不掉的情况如实往上抛，让界面说失败。
          debugPrint('埋点日志清空失败：$error');
          rethrow;
        }
      });

  /// 等待所有在途写操作完成。**只给测试用**：`track` 是 fire-and-forget，
  /// 测试要在断言（或开新实例）之前确认写盘已经结束。
  @visibleForTesting
  Future<void> flush() async {
    await _pending;
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final previous = _pending;
    final task = () async {
      try {
        await previous;
      } on Object {
        // 前一个写操作失败不该连坐后一个。
      }
      await action();
    }();
    _pending = task;
    return task;
  }

  Future<void> _doAppend(EventLogEntry entry) async {
    try {
      final entries = await _load();
      entries.add(entry);
      while (entries.length > maxEntries) {
        entries.removeAt(0);
      }
      final file = await _resolveFile();
      final content =
          '${entries.map((entry) => jsonEncode(entry.toJson())).join('\n')}\n';
      await file.writeAsString(content, flush: true);
    } on Object catch (error) {
      debugPrint('埋点日志写入失败：$error');
    }
  }
}

final eventLogProvider = Provider<EventLog>((ref) => FileEventLog());
