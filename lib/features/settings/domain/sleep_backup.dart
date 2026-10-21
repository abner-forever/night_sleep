import 'dart:convert';

import '../../sleep/domain/clip_analysis.dart';
import '../../sleep/domain/sleep_entry.dart';
import '../../sleep/domain/sleep_insight.dart';
import '../../sleep/domain/sleep_quality.dart';
import '../../sleep/domain/sleep_score.dart';
import '../../sleep/domain/sleep_stage.dart';
import '../../sleep/domain/sound_event.dart';

class SleepBackup {
  const SleepBackup({required this.entries, required this.audioPaths});

  final List<SleepEntry> entries;
  final Map<String, String> audioPaths;

  int get clipCount =>
      entries.fold(0, (count, entry) => count + entry.soundClips.length);

  static SleepBackup parse(String content, {required bool withAudio}) {
    try {
      final document = _map(jsonDecode(content));
      final expectedFormat =
          withAudio ? 'night-sleep-backup' : 'night-sleep-export';
      if (document['format'] != expectedFormat || document['version'] != 1) {
        throw const FormatException('不支持的备份格式或版本');
      }
      final schema = document['schemaVersion'];
      if (schema is! int || schema < 2 || schema > 10) {
        throw const FormatException('备份数据版本不受支持，请使用兼容版本的夜深');
      }
      final records = _list(document['records']);
      if (document['recordCount'] != records.length) {
        throw const FormatException('备份记录数不一致');
      }
      final recordIds = <String>{};
      final clipIds = <String>{};
      final paths = <String, String>{};
      final entries = <SleepEntry>[];
      for (final rawRecord in records) {
        final record = _map(rawRecord);
        final id = _text(record, 'id');
        if (!recordIds.add(id)) {
          throw const FormatException('备份中存在重复记录');
        }
        final start = _time(record, 'startAtUtc');
        final end = _time(record, 'endAtUtc');
        _interval(start, end);
        final source = _text(record, 'source');
        if (!['manual', 'session', 'import'].contains(source)) {
          throw const FormatException('备份包含不支持的记录来源');
        }
        final quality = record['quality'];
        if (quality != null &&
            (quality is! int || quality < 1 || quality > 5)) {
          throw const FormatException('睡眠质量不合法');
        }
        final events = _map(record['loggedEvents']);
        final stages = <SleepStageSegment>[];
        for (final rawStage in _list(record['stages'])) {
          final stage = _map(rawStage);
          final type = SleepStageType.fromId(_text(stage, 'stage'));
          if (type == null) throw const FormatException('睡眠阶段不合法');
          final stageStart = _time(stage, 'startAtUtc');
          final stageEnd = _time(stage, 'endAtUtc');
          _interval(stageStart, stageEnd);
          if (stageStart.isBefore(start) || stageEnd.isAfter(end)) {
            throw const FormatException('睡眠阶段超出记录时间');
          }
          stages.add(SleepStageSegment(
            stage: type,
            startAtUtc: stageStart,
            endAtUtc: stageEnd,
            source: _text(stage, 'source'),
          ));
        }
        final clips = <SoundClip>[];
        for (final rawClip in _list(record['soundClips'])) {
          final clip = _map(rawClip);
          final clipId = _text(clip, 'id');
          final kind = SoundEventKind.fromId(_text(clip, 'kind'));
          if (!clipIds.add(clipId) || kind == null) {
            throw const FormatException('声音片段重复或类型不合法');
          }
          final duration = clip['durationMs'];
          if (duration is! int || duration <= 0) {
            throw const FormatException('声音片段时长不合法');
          }
          final status = _text(clip, 'analysisStatus');
          if (!SoundAnalysisStatus.values.any((value) => value.id == status)) {
            throw const FormatException('声音分析状态不合法');
          }
          final audioPath = clip['audioPath'];
          if (audioPath != null) {
            if (!withAudio ||
                audioPath is! String ||
                !RegExp(r'^audio/[0-9]+\.wav$').hasMatch(audioPath) ||
                paths.containsValue(audioPath)) {
              throw const FormatException('备份音频路径不合法');
            }
            paths[clipId] = audioPath;
          }
          final rawEnvelope = clip['waveformEnvelope'];
          List<double>? envelope;
          if (rawEnvelope != null) {
            envelope = [];
            for (final value in _list(rawEnvelope)) {
              if (value is! num || !value.isFinite || value < 0 || value > 1) {
                throw const FormatException('声音波形不合法');
              }
              envelope.add(value.toDouble());
            }
          }
          final rawAuto = clip['autoAnalysis'];
          final auto = rawAuto == null
              ? null
              : AutoAnalysis.decode(jsonEncode(_map(rawAuto)));
          if (rawAuto != null && auto == null) {
            throw const FormatException('声音自动分析数据不合法');
          }
          clips.add(SoundClip(
            id: clipId,
            kind: kind,
            startedAtUtc: _time(clip, 'startedAtUtc'),
            durationMs: duration,
            transcript: _nullableText(clip, 'transcript'),
            analysis: _nullableText(clip, 'analysis'),
            analysisStatus: SoundAnalysisStatus.fromId(status),
            source: 'recording',
            waveformEnvelope: envelope,
            labeledAtUtc: clip['labeledAtUtc'] == null
                ? null
                : _time(clip, 'labeledAtUtc'),
            autoAnalysis: auto,
          ));
        }
        Insight? insight;
        if (record['insight'] != null) {
          final rawInsight = _map(record['insight']);
          final status = _text(rawInsight, 'status');
          final score = rawInsight['score'];
          if (!InsightStatus.values.any((value) => value.id == status) ||
              (score != null && (score is! int || score < 0 || score > 100))) {
            throw const FormatException('洞察数据不合法');
          }
          insight = Insight(
            id: _text(rawInsight, 'id'),
            recordId: id,
            kind: _text(rawInsight, 'kind'),
            content: _nullableText(rawInsight, 'content'),
            provider: _nullableText(rawInsight, 'provider'),
            model: _nullableText(rawInsight, 'model'),
            score: score as int?,
            generatedAtUtc: _time(rawInsight, 'generatedAtUtc'),
            status: InsightStatus.fromId(status),
          );
        }
        entries.add(SleepEntry(
          id: id,
          startAtUtc: start,
          endAtUtc: end,
          timeZoneId: _text(record, 'timeZoneId'),
          quality:
              quality == null ? null : SleepQuality.fromValue(quality as int),
          notes: _text(record, 'notes', allowEmpty: true),
          tags: [
            for (final tag in _list(record['tags']))
              if (tag is String) tag else throw const FormatException('标签不合法'),
          ],
          source: source,
          loggedEvents: LoggedEvents(
            snore: _flag(events, 'snore'),
            talk: _flag(events, 'talk'),
            restless: _flag(events, 'restless'),
            nightmare: _flag(events, 'nightmare'),
          ),
          stages: stages,
          soundClips: clips,
          insight: insight,
          createdAtUtc: _time(record, 'createdAtUtc'),
          updatedAtUtc: _time(record, 'updatedAtUtc'),
        ));
      }
      return SleepBackup(entries: entries, audioPaths: paths);
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('备份内容损坏或字段类型不正确');
    }
  }

  static Map<String, dynamic> _map(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('备份字段应为对象');
    }
    return value;
  }

  static List<dynamic> _list(Object? value) {
    if (value is! List) throw const FormatException('备份字段应为数组');
    return value;
  }

  static String _text(Map<String, dynamic> data, String key,
      {bool allowEmpty = false}) {
    final value = data[key];
    if (value is! String || (!allowEmpty && value.trim().isEmpty)) {
      throw FormatException('备份字段 $key 不合法');
    }
    return value;
  }

  static String? _nullableText(Map<String, dynamic> data, String key) =>
      data[key] == null ? null : _text(data, key, allowEmpty: true);

  static DateTime _time(Map<String, dynamic> data, String key) {
    final text = _text(data, key);
    final value = DateTime.tryParse(text);
    if (value == null || !value.isUtc) {
      throw FormatException('备份字段 $key 应为带时区的时间');
    }
    return value.toUtc();
  }

  static bool _flag(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is! bool) throw FormatException('备份字段 $key 应为布尔值');
    return value;
  }

  static void _interval(DateTime start, DateTime end) {
    if (!end.isAfter(start)) throw const FormatException('备份起止时间不合法');
  }
}
