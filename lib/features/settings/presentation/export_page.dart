import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/session_teardown.dart';
import '../../../core/config/app_config.dart';
import '../../../core/database/app_database.dart' show databaseProvider;
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_basics.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/glass_surface.dart';
import '../../../core/widgets/ios_controls.dart';
import '../../../core/widgets/subpage.dart';
import '../../sleep/data/clip_pruning.dart';
import '../../sleep/data/clip_store.dart';
import '../../sleep/data/sleep_repository.dart';
import '../../sleep/domain/sleep_entry.dart';
import '../data/export_storage.dart';
import '../data/sleep_backup_service.dart';
import '../domain/sleep_export.dart';

/// 睡眠数据管理。
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

  /// 最近一次导出失败的原因，显示在页内。全局 toast 挂在 `AppScaffold`，而这一页
  /// push 在它之上，提示条会被整个盖住；失败反馈必须留在本页，否则界面只会表现
  /// 为「点了没反应」。
  String? _error;
  String? _notice;
  ExportLocation? _location;
  String? _locationError;

  @override
  void initState() {
    super.initState();
    _loadLocation();
  }

  Future<void> _loadLocation() async {
    try {
      final location = await ref.read(exportStorageProvider).location();
      if (mounted) {
        setState(() {
          _location = location;
          _locationError = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _locationError = '无法读取导出位置。');
      }
    }
  }

  Future<void> _chooseLocation() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
      _locationError = null;
    });
    try {
      final location = await ref.read(exportStorageProvider).chooseLocation();
      if (!mounted) return;
      if (location != null) {
        setState(() {
          _location = location;
          _notice = '导出位置已更新。';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _locationError = '无法打开目录选择器，请稍后再试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetLocation() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
      _locationError = null;
    });
    try {
      final location = await ref.read(exportStorageProvider).resetLocation();
      if (!mounted) return;
      setState(() {
        _location = location;
        _notice = '已恢复默认导出位置。';
      });
    } catch (_) {
      if (mounted) setState(() => _locationError = '无法恢复默认导出位置。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmDeleteAll() async {
    if (_busy) return;
    final confirmed = await showConfirmDialog(
      context,
      title: '删除全部本地数据？',
      message: '所有睡眠记录、睡眠阶段、声音事件与洞察都会被永久删除，此操作无法撤销。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (confirmed != true || !mounted || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await deleteAllUserDataWithRecordings(
        database: ref.read(databaseProvider),
        files: ref.read(clipFileStoreProvider),
      );
      await teardownSession(ref);
      if (!mounted) return;
      ref.invalidate(sleepEntriesProvider);
      setState(() => _notice = '本地数据已全部删除。');
    } catch (_) {
      if (mounted) setState(() => _error = '删除失败，请稍后再试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// [all] 是**未过滤**的全部记录。
  ///
  /// 过滤交给 `SleepExporter` 自己做：JSON 里的 `excludedDemoCount` 要靠
  /// 「过滤前有几条」才能算出来，这里先滤一遍它就只能恒为 0。
  Future<void> _export({
    required bool asJson,
    required List<SleepEntry> all,
    bool asBackup = false,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final List<ExportFile> files;
      var missing = 0;
      if (asBackup) {
        final result = await ref.read(sleepBackupServiceProvider).export(
              all,
              now: DateTime.now(),
            );
        files = [result.file];
        missing = result.missingAudioCount;
      } else {
        files = asJson
            ? SleepExporter.json(all, now: DateTime.now())
            : SleepExporter.csv(all, now: DateTime.now());
      }
      if (!mounted) return;
      final outcome = await ref.read(exportStorageProvider).save(files);
      if (!mounted) return;
      setState(() {
        final notices = <String>[];
        if (outcome.failed) {
          _error = outcome.savedCount == 0
              ? '导出失败，文件没有保存。'
              : '已保存 ${outcome.savedCount} 个文件，其余文件保存失败。';
        } else {
          _error = null;
          if (outcome.complete) {
            notices.add(outcome.fileCount == 1
                ? '已保存到${_location?.label ?? '应用文件目录'}。'
                : '已保存 ${outcome.fileCount} 个文件到'
                    '${_location?.label ?? '应用文件目录'}。');
          } else if (outcome.savedCount > 0) {
            notices.add(
              '已保存 ${outcome.savedCount} 个文件，其余文件未保存。',
            );
          }
        }
        if (asBackup && outcome.savedCount > 0 && missing > 0) {
          notices.add('$missing 段音频文件已缺失，备份中保留了对应的声音事件。');
        }
        _notice = notices.isEmpty ? null : notices.join(' ');
      });
    } catch (_) {
      if (mounted) setState(() => _error = '导出失败，无法生成备份文件。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final entries = ref.watch(sleepEntriesProvider);

    // **读不到不等于没有。** 此前这里只取 `valueOrNull`，于是加载中和读失败都退化成
    // 空列表，页面照着一句「暂无可导出的记录」把三个动作一起置灰——把「读不到」说成了
    // 「没有」，而它自己推入的表格预览页对同一个状态是分开说的。三态各有各的说法。
    return entries.when(
      loading: () => _shell(const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(child: CircularProgressIndicator()),
        ),
      ]),
      error: (error, stack) => _shell([
        EmptyState(
          icon: AppIcons.wave(size: 30, color: tokens.danger, strokeWidth: 1.6),
          title: '无法读取记录',
          body: '本地数据库打开失败，因此现在读不出有几条可导出的记录：$error',
        ),
      ]),
      data: (all) => _content(context, all),
    );
  }

  /// 加载 / 出错 / 有数据三态共用同一副外壳与标题。
  Widget _shell(List<Widget> children) {
    final tokens = AppTokens.of(context);
    final entries = ref.watch(sleepEntriesProvider).valueOrNull ?? const [];
    final demoCount =
        entries.where((entry) => entry.source == AppConfig.demoSource).length;
    return Subpage(
      title: '睡眠数据管理',
      children: [
        ...children,
        const SizedBox(height: 22),
        const SectionHeader('导入数据'),
        IosListGroup(children: [
          IosListItem(
            onTap: _busy ? null : () => context.push('/settings/restore'),
            child: _Action(
              enabled: !_busy,
              title: '从备份恢复',
              subtitle: '导入 ZIP 完整备份或以前导出的 JSON',
            ),
          ),
        ]),
        const SizedBox(height: 22),
        const SectionHeader('本地数据'),
        IosListGroup(children: [
          if (AppConfig.demoDataEnabled)
            IosListItem(
              onTap: _busy ? null : () => context.push('/settings/demo'),
              child: _Action(
                enabled: !_busy,
                title: '演示数据',
                subtitle: demoCount == 0 ? '仅调试构建可见' : '$demoCount 条示例记录',
              ),
            ),
          IosListItem(
            onTap: _busy ? null : _confirmDeleteAll,
            child: Row(
              children: [
                ListIconBadge(
                  background: tokens.danger.withValues(alpha: 0.12),
                  size: 36,
                  child: AppIcons.trash(
                      size: 17, color: tokens.danger, strokeWidth: 1.8),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '删除全部本地数据',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: _busy ? tokens.textMuted : tokens.danger,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ]),
      ],
    );
  }

  Widget _content(BuildContext context, List<SleepEntry> all) {
    final tokens = AppTokens.of(context);
    final exportable = SleepExporter.exportableOf(all);
    final excluded = all.length - exportable.length;

    final stageCount =
        exportable.fold(0, (sum, entry) => sum + entry.stages.length);
    final clipCount =
        exportable.fold(0, (sum, entry) => sum + entry.soundClips.length);
    final insightCount =
        exportable.where((entry) => entry.insight != null).length;

    final hasData = exportable.isNotEmpty;

    return _shell(
      [
        const SectionHeader('导出位置'),
        IosListGroup(children: [
          IosListItem(
            onTap:
                _location?.canChoose == true && !_busy ? _chooseLocation : null,
            child: _Action(
              enabled: _location?.canChoose == true && !_busy,
              title: '默认目录',
              subtitle: _location?.label ?? _locationError ?? '正在读取…',
              showChevron: _location?.canChoose == true,
            ),
          ),
          if (_location?.custom == true)
            IosListItem(
              onTap: _busy ? null : _resetLocation,
              child: _Action(
                enabled: !_busy,
                title: '恢复默认位置',
                subtitle: '改回下载/夜深或当前平台默认目录',
              ),
            ),
        ]),
        const SizedBox(height: 22),
        const SectionHeader('导出数据'),
        const SizedBox(height: 12),
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
                hasData ? '完整备份包含本机仍保留的录音，不含设置与密钥。' : '暂无可导出的记录',
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
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: TextStyle(fontSize: 12, height: 1.5, color: tokens.danger),
          ),
        ],
        if (_notice != null) ...[
          const SizedBox(height: 12),
          Text(_notice!, style: TextStyle(fontSize: 12, color: tokens.caution)),
        ],
        if (_busy) ...[
          const SizedBox(height: 12),
          Text('正在处理数据…',
              style: TextStyle(fontSize: 12, color: tokens.textMuted)),
        ],
        const SizedBox(height: 22),
        IosListGroup(
          children: [
            IosListItem(
              onTap: hasData && !_busy
                  ? () => _export(asJson: false, asBackup: true, all: all)
                  : null,
              child: _Action(
                enabled: hasData && !_busy,
                title: '导出完整备份（含录音）',
                subtitle: 'ZIP 备份包，用于换机或重新安装后恢复',
              ),
            ),
            IosListItem(
              onTap: hasData
                  ? () => context.push('/settings/export/preview')
                  : null,
              child: _Action(
                enabled: hasData,
                title: '预览表格',
                subtitle: '先看一眼将写进文件的两张表',
              ),
            ),
            IosListItem(
              onTap: hasData && !_busy
                  ? () => _export(asJson: false, all: all)
                  : null,
              child: _Action(
                enabled: hasData && !_busy,
                title: '导出 CSV',
                subtitle: '记录与阶段两张表，可用表格软件打开',
              ),
            ),
            IosListItem(
              onTap: hasData && !_busy
                  ? () => _export(asJson: true, all: all)
                  : null,
              child: _Action(
                enabled: hasData && !_busy,
                title: '导出 JSON',
                subtitle: '结构化数据，含声音事件与洞察，不含录音文件',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          '导出与默认导入共用上面的目录；每次导出会直接写入该目录，应用不会自行上传。'
          '完整备份含私人录音，请妥善保管。已清理的录音无法补回；进行中的睡眠请先结束再备份。',
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
/// 没有图标：现有图标集里没有表达「导出」的那一个，自绘一个就是引入一套应用其余
/// 部分没有的图标语言。
class _Action extends StatelessWidget {
  const _Action({
    required this.enabled,
    required this.title,
    required this.subtitle,
    this.showChevron = true,
  });

  final bool enabled;
  final String title;
  final String subtitle;
  final bool showChevron;

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
        if (showChevron)
          AppIcons.chevronRight(
            size: 18,
            color: enabled ? tokens.textMuted : tokens.borderStrong,
            strokeWidth: 2,
          ),
      ],
    );
  }
}
