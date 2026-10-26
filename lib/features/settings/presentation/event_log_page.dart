import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/telemetry/event_log.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/glass_surface.dart';
import '../../../core/widgets/ios_controls.dart';
import '../../../core/widgets/subpage.dart';
import '../data/export_storage.dart';
import '../domain/sleep_export.dart';

/// 运行日志 — 埋点数据的查看、导出与清空。
///
/// 埋点只在本机留存（见 `event_log.dart`），这一页是它唯一的出口：
/// 列表给「应用都记了些什么」一个能亲眼确认的地方，导出把记录交给
/// 系统保存（与睡眠数据导出同一个通道），清空过二次确认。
class EventLogPage extends ConsumerStatefulWidget {
  const EventLogPage({super.key});

  @override
  ConsumerState<EventLogPage> createState() => _EventLogPageState();
}

class _EventLogPageState extends ConsumerState<EventLogPage> {
  late Future<List<EventLogEntry>> _entries;

  /// 导出/清空进行中，挡住重复点击。
  bool _busy = false;

  /// 与演示数据页同一套页内反馈：二级页 push 在 AppScaffold 之上，
  /// 全局 toast 会被盖住，成功与失败都必须留在本页。
  String? _error;
  String? _success;

  @override
  void initState() {
    super.initState();
    _entries = ref.read(eventLogProvider).readAll();
  }

  void _reload() {
    setState(() => _entries = ref.read(eventLogProvider).readAll());
  }

  Future<void> _export() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _success = null;
    });
    try {
      final log = ref.read(eventLogProvider);
      final entries = await log.readAll();
      if (!mounted) return;
      // 没有的东西就导不出来：空记录时如实说，不生成一个空 JSON。
      if (entries.isEmpty) {
        setState(() => _success = '还没有可导出的记录。');
        return;
      }
      final content = await log.exportContent();
      if (!mounted) return;
      final stamped = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final result = await ref.read(exportStorageProvider).save([
        ExportFile(
          fileName: 'night_sleep_events_$stamped.json',
          content: content,
          mimeType: 'application/json',
        ),
      ]);
      if (!mounted) return;
      if (result.failed || result.savedCount == 0) {
        setState(() => _error = '导出失败，请稍后再试。');
        return;
      }
      log.track('event_log_export', {'count': entries.length});
      setState(() => _success = '已导出 ${entries.length} 条记录。');
    } on Object {
      if (!mounted) return;
      setState(() => _error = '导出失败，请稍后再试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    if (_busy) return;
    // 删除不可撤销，与另外几处删除一样过二次确认。
    final confirmed = await showConfirmDialog(
      context,
      title: '清空运行日志？',
      message: '全部埋点记录会被永久删除，删除后无法恢复。睡眠记录与录音不受影响。',
      confirmLabel: '清空',
      destructive: true,
    );
    if (confirmed != true) return;
    if (!mounted) return;

    setState(() {
      _busy = true;
      _error = null;
      _success = null;
    });
    try {
      await ref.read(eventLogProvider).clear();
      ref.read(eventLogProvider).track('event_log_clear');
      if (!mounted) return;
      setState(() => _success = '运行日志已清空。');
    } on Object {
      if (!mounted) return;
      setState(() => _error = '清空失败，请稍后再试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Subpage(
      title: '运行日志',
      children: [
        FutureBuilder<List<EventLogEntry>>(
          future: _entries,
          builder: (context, snapshot) {
            final entries = snapshot.data;
            if (entries == null) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _IntroCard(count: entries.length, tokens: tokens),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(
                        fontSize: 12, height: 1.5, color: tokens.danger),
                  ),
                ],
                if (_success != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _success!,
                    style: TextStyle(
                        fontSize: 12, height: 1.5, color: tokens.accent),
                  ),
                ],
                const SizedBox(height: 18),
                IosListGroup(
                  children: [
                    IosListItem(
                      onTap: _busy ? null : _export,
                      child: _ActionRow(
                        label: '导出日志数据',
                        muted: entries.isEmpty,
                        tokens: tokens,
                      ),
                    ),
                    IosListItem(
                      onTap: _busy || entries.isEmpty ? null : _clear,
                      child: _ActionRow(
                        label: '清空日志',
                        danger: entries.isNotEmpty,
                        muted: entries.isEmpty,
                        tokens: tokens,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                if (entries.isEmpty)
                  _EmptyState(tokens: tokens)
                else ...[
                  for (final entry in entries.reversed)
                    _EntryTile(entry: entry, tokens: tokens),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard({required this.count, required this.tokens});

  final int count;
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      borderRadius: BorderRadius.circular(AppRadii.card),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListIconBadge(
                background: tokens.accentSoft,
                size: 40,
                child: AppIcons.clock(
                    size: 20, color: tokens.accent, strokeWidth: 1.8),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '埋点记录',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: tokens.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      count == 0 ? '当前没有记录' : '当前有 $count 条记录',
                      style: TextStyle(fontSize: 12, color: tokens.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '这里记录应用内的关键操作（启动、切页、开始与结束睡眠等），'
            '用来排查问题。记录只保存在这台设备上，不上传任何服务器，'
            '最多保留 500 条，超出的会自动丢弃最旧的。',
            style: TextStyle(
              fontSize: 12,
              height: 1.55,
              color: tokens.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.label,
    required this.tokens,
    this.danger = false,
    this.muted = false,
  });

  final String label;
  final AppTokens tokens;
  final bool danger;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final color = danger
        ? tokens.danger
        : muted
            ? tokens.textMuted
            : tokens.textPrimary;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ),
        AppIcons.chevronRight(
          size: 15,
          color: tokens.textMuted,
          strokeWidth: 2,
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.tokens});

  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Text(
          '还没有记录。使用应用之后，关键操作会出现在这里。',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: tokens.textMuted),
        ),
      ),
    );
  }
}

/// 一条记录：事件名 + 时间，附带的结构化字段拼在第二行。
///
/// 列表按时间**从新到旧**排——看日志的人关心的是「刚刚发生了什么」。
class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, required this.tokens});

  final EventLogEntry entry;
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    final time = DateFormat('MM-dd HH:mm:ss').format(entry.time);
    final details = entry.data.isEmpty
        ? null
        : entry.data.entries.map((e) => '${e.key}=${e.value}').join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassSurface(
        borderRadius: BorderRadius.circular(AppRadii.card),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    entry.event,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: tokens.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  time,
                  style:
                      AppTheme.num(context, size: 11, color: tokens.textMuted),
                ),
              ],
            ),
            if (details != null) ...[
              const SizedBox(height: 3),
              Text(
                details,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: tokens.textMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
