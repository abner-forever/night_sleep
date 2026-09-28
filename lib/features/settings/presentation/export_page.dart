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
                // 短状态句不加句号（首页「还没有睡眠记录」、统计页「暂无统计数据」
                // 同口径）；这一页只有「文件不含音频…」那句完整说明句带句号。
                hasData ? '文件不含音频本身，也不含设置与密钥。' : '暂无可导出的记录',
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
              onTap: hasData ? () => _export(asJson: false, all: all) : null,
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
