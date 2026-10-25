import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_basics.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/glass_surface.dart';
import '../../../core/widgets/ios_controls.dart';
import '../../../core/widgets/subpage.dart';
import '../../sleep/data/sleep_repository.dart';
import '../../sleep/domain/sleep_entry.dart';
import '../domain/sleep_export.dart';

/// 导出表格预览：在按下导出之前，逐格看到将写进 CSV 文件的内容。
///
/// 表格由 [SleepExporter.tables] 产出——与导出文件是**同一次生成**，所以这一页
/// 看到的表头、列序与每一格就是文件里的那一格，不存在两套格式知识各自漂移的可能。
///
/// **这一页只读**：它回答的是「文件里有什么」。能改的话它就不再是文件的样子了，
/// 要改记录走详情页或回顾页。
class ExportPreviewPage extends ConsumerStatefulWidget {
  const ExportPreviewPage({super.key});

  @override
  ConsumerState<ExportPreviewPage> createState() => _ExportPreviewPageState();
}

class _ExportPreviewPageState extends ConsumerState<ExportPreviewPage> {
  ExportTableKind _kind = ExportTableKind.records;

  /// 预览最多渲染这么多行。
  ///
  /// 这一页的意义是**抽查**而不是通读：把几千行一次性建成 widget，是拿打开速度
  /// 换一个没人会读完的完整性。少显示的那部分在页面上如实写出来。
  static const rowLimit = 50;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final entries = ref.watch(sleepEntriesProvider);

    // 数据还没读到时不要下结论：空状态里那句「暂无可预览的记录」是**结论**，
    // 在加载中把它说出来就是说了句没根据的话。加载与出错各有一支。
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
          body: '本地数据库打开失败：$error',
        ),
      ]),
      data: (records) => _content(context, records),
    );
  }

  /// 加载 / 出错 / 有数据三态共用同一副外壳与标题。
  Widget _shell(List<Widget> children) => Subpage(
        title: '表格预览',
        children: children,
      );

  Widget _content(BuildContext context, List<SleepEntry> all) {
    final tokens = AppTokens.of(context);
    final exportable = SleepExporter.exportableOf(all);
    final excluded = all.length - exportable.length;
    final tables = SleepExporter.tables(all, now: DateTime.now());
    final table = tables.firstWhere((item) => item.kind == _kind);

    if (exportable.isEmpty) {
      return _shell([
        EmptyState(
          icon: AppIcons.moon(size: 30, color: tokens.accent, strokeWidth: 1.6),
          title: '暂无可预览的记录',
          // 演示数据是唯一会被排除的来源，所以有它的时候就说明白：
          // 「没有可看的行」不等于「你的数据丢了」。
          body: excluded > 0
              ? '导出只含真实记录：库里这 $excluded 条都是演示记录，'
                  '它们既不进文件，也不在这里的预览里。'
              : '记录第一晚之后，就能在这里看到将写进文件的两张表。',
        ),
      ]);
    }

    return _shell(
      [
        Align(
          alignment: Alignment.centerLeft,
          child: SegmentedControl<ExportTableKind>(
            segments: [
              for (final kind in ExportTableKind.values)
                SegmentOption(value: kind, label: kind.label),
            ],
            selected: _kind,
            onChanged: (kind) => setState(() => _kind = kind),
          ),
        ),
        const SizedBox(height: 14),
        // 事实块排在表格**之前**：这张表可以长到几千像素，说明写在它后面等于
        // 要用户先滚过 50 行才知道自己看的是节选。先说清楚，再给数据。
        Text(
          '${table.fileName} · 共 ${table.rowCount} 行',
          style: TextStyle(fontSize: 12, height: 1.5, color: tokens.textMuted),
        ),
        if (table.rowCount > rowLimit) ...[
          const SizedBox(height: 6),
          Text(
            '预览只显示前 $rowLimit 行，文件包含全部 ${table.rowCount} 行。',
            style:
                TextStyle(fontSize: 12, height: 1.5, color: tokens.textMuted),
          ),
        ],
        if (excluded > 0) ...[
          const SizedBox(height: 6),
          Text(
            '已排除 $excluded 条演示记录',
            style:
                TextStyle(fontSize: 12, height: 1.5, color: tokens.textMuted),
          ),
        ],
        const SizedBox(height: 10),
        _TablePreview(table: table, limit: rowLimit),
        const SizedBox(height: 16),
        Text(
          '表头、列序与每一格的文字都与导出的文件相同——预览读的就是生成文件的'
          '那一份数据。导出后会直接写入睡眠数据管理页设置的目录。',
          style: TextStyle(fontSize: 12, height: 1.5, color: tokens.textMuted),
        ),
      ],
    );
  }
}

/// 一张表：表头一行 + 数据行，横向滚动。
class _TablePreview extends StatelessWidget {
  const _TablePreview({required this.table, required this.limit});

  final ExportTable table;
  final int limit;

  /// 列宽。定宽是为了让上下行对齐成一张表；没列出的列用 [_defaultWidth]，
  /// 于是将来给导出加一列也不会把它挤没。
  ///
  /// 数值按**实际最长内容**给足：窄一格，那一列就会折成两行，整张表的行高
  /// 跟着参差。`YYYY-MM-DD HH:mm` 那两个时间戳列是这里最长的一档。
  ///
  /// 宽度是**呈现**的选择，不进导出格式：文件里没有宽度这回事。
  static const _widths = <String, double>{
    '日期': 100,
    '入睡时刻': 80,
    '醒来时刻': 80,
    '时区': 120,
    '时长(小时)': 100,
    '时长(分钟)': 100,
    '备注': 200,
    '记录ID': 150,
    '最初记录时间': 150,
    '最后修改时间': 150,
    '开始时间': 150,
    '结束时间': 150,
  };
  static const _defaultWidth = 72.0;

  @override
  Widget build(BuildContext context) {
    final rows = table.rows.take(limit).toList();
    final widths = [
      for (final cell in table.header) _widths[cell] ?? _defaultWidth
    ];

    return GlassSurface(
      borderRadius: BorderRadius.circular(AppRadii.card),
      padding: EdgeInsets.zero,
      expandWidth: false,
      // 卡片本身占满内容列的宽度，表格在**卡片里面**横向滚动——16 列放不进
      // 390px，但它不该把整页撑宽、也不该把每一列压到看不清。
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Row(cells: table.header, widths: widths, header: true),
            for (final row in rows) _Row(cells: row, widths: widths),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.cells, required this.widths, this.header = false});

  final List<String> cells;
  final List<double> widths;
  final bool header;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: tokens.border)),
        color: header ? tokens.bgMuted : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < cells.length; i++)
            _Cell(
              value: cells[i],
              width: widths[i],
              header: header,
              last: i == cells.length - 1,
            ),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.value,
    required this.width,
    required this.header,
    required this.last,
  });

  final String value;
  final double width;
  final bool header;

  /// 最后一列不画右边线，否则表格右缘会多一道贴着外框的竖线。
  final bool last;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(
                right: BorderSide(
                  color: tokens.border.withValues(alpha: 0.6),
                ),
              ),
      ),
      // 不截断、不省略：这一页的意义就是看清每一格写了什么，备注长了就换行。
      child: Text(
        value,
        style: header
            ? TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                height: 1.4,
                color: tokens.textMuted,
              )
            : TextStyle(
                fontSize: 12,
                height: 1.4,
                color: tokens.textSecondary,
                // 表格里的数字要对齐成列，所以整表都用等宽数字。
                fontFeatures: AppTheme.tabular,
              ),
      ),
    );
  }
}
