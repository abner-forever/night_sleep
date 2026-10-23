import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_basics.dart';
import '../../../core/widgets/glass_surface.dart';
import '../../../core/widgets/subpage.dart';
import '../../sleep/data/sleep_repository.dart';
import '../data/sleep_backup_service.dart';

class BackupRestorePage extends ConsumerStatefulWidget {
  const BackupRestorePage({super.key});

  @override
  ConsumerState<BackupRestorePage> createState() => _BackupRestorePageState();
}

class _BackupRestorePageState extends ConsumerState<BackupRestorePage> {
  PreparedSleepBackup? _prepared;
  bool _busy = false;
  bool _restoring = false;
  String? _error;
  String? _result;

  @override
  void dispose() {
    if (!_restoring) _prepared?.dispose();
    super.dispose();
  }

  Future<void> _choose() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final file = await ref.read(backupFilePickerProvider).pick();
      if (file == null || !mounted) return;
      final previous = _prepared;
      setState(() => _prepared = null);
      await previous?.dispose();
      if (!mounted) return;
      final prepared = await ref.read(sleepBackupServiceProvider).prepare(file);
      if (!mounted) {
        await prepared.dispose();
        return;
      }
      setState(() => _prepared = prepared);
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = '无法读取备份，请重新选择文件。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final prepared = _prepared;
    if (_busy || prepared == null) return;
    _restoring = true;
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final service = ref.read(sleepBackupServiceProvider);
      final result = await service.restore(prepared);
      if (!mounted) return;
      ref.invalidate(sleepEntriesProvider);
      setState(() {
        _prepared = null;
        _result = '已恢复 ${result.imported} 条记录、${result.audioCount} 段录音，'
            '跳过 ${result.skipped} 条已有记录。';
      });
    } on StateError catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = '恢复失败，本机记录未改动，请重试。');
    } finally {
      if (!mounted || _prepared != prepared) await prepared.dispose();
      _restoring = false;
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final backup = _prepared?.backup;
    final missing =
        backup == null ? 0 : backup.clipCount - backup.audioPaths.length;
    return PopScope(
      canPop: !_busy,
      child: Subpage(
        title: '从备份恢复',
        children: [
          GlassSurface(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('导入夜深备份',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: tokens.textPrimary)),
                const SizedBox(height: 12),
                Text(
                  '支持含录音的 ZIP 完整备份，以及以前导出的 JSON 存档。'
                  'CSV 用于表格查看，不支持恢复。',
                  style: TextStyle(
                      fontSize: 13, height: 1.6, color: tokens.textSecondary),
                ),
                const SizedBox(height: 12),
                Text(
                  '恢复会按记录 ID 合并，已有记录保留本机版本并跳过。'
                  '不恢复设置与密钥。录音恢复后仍按最近 7 晚的保留规则管理。',
                  style: TextStyle(
                      fontSize: 12, height: 1.6, color: tokens.textMuted),
                ),
                const SizedBox(height: 20),
                PrimaryAction(
                    label: _busy ? '正在处理…' : '选择备份文件',
                    onTap: _busy ? null : _choose),
              ],
            ),
          ),
          if (backup != null) ...[
            const SizedBox(height: 16),
            GlassSurface(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('备份内容',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: tokens.textPrimary)),
                  const SizedBox(height: 10),
                  Text(
                      '${backup.entries.length} 条记录 · ${backup.clipCount} 个声音事件 · '
                      '${backup.audioPaths.length} 段录音',
                      style:
                          TextStyle(fontSize: 13, color: tokens.textSecondary)),
                  if (missing > 0) ...[
                    const SizedBox(height: 10),
                    Text('$missing 个声音事件没有录音文件，恢复后无法回放。旧 JSON 存档不含音频。',
                        style: TextStyle(
                            fontSize: 12, height: 1.5, color: tokens.caution)),
                  ],
                  const SizedBox(height: 20),
                  PrimaryAction(
                    label: '确认恢复',
                    onTap: _busy || backup.entries.isEmpty ? null : _restore,
                  ),
                ],
              ),
            ),
          ],
          if (_error != null || _result != null) ...[
            const SizedBox(height: 16),
            Text(_error ?? _result!,
                style: TextStyle(
                    fontSize: 13,
                    height: 1.6,
                    color:
                        _error == null ? tokens.textSecondary : tokens.danger)),
          ],
        ],
      ),
    );
  }
}
