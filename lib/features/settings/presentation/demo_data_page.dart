import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/glass_surface.dart';
import '../../../core/widgets/ios_controls.dart';
import '../../../core/widgets/subpage.dart';
import '../../sleep/data/sleep_repository.dart';

/// Sample nights, kept out of the Settings root.
///
/// This is a development affordance, not a user feature: it exists so the charts
/// and the detail sheet can be looked at with real-looking data before there is
/// any. It lives on its own page because a control that wipes and re-seeds the
/// database has no business sitting one row away from 「就寝提醒」, where it
/// invites a mis-tap.
class DemoDataPage extends ConsumerStatefulWidget {
  const DemoDataPage({super.key});

  @override
  ConsumerState<DemoDataPage> createState() => _DemoDataPageState();
}

class _DemoDataPageState extends ConsumerState<DemoDataPage> {
  /// 安装/清除正在进行时置为 true，用来挡住重复点击。
  bool _busy = false;

  /// 最近一次失败的原因，显示在页内。全局 toast 挂在 AppScaffold，二级页 push
  /// 在它之上，会把提示条整个盖住，所以失败反馈必须留在本页。
  String? _error;

  /// 最近一次成功的文案，同样显示在页内（原因见 [_error]）。
  ///
  /// 与 [_error] 互斥：两个动作开始时都先把两者清空，且每次只设置其中一个，
  /// 因此页面上最多只出现一条提示。
  String? _success;

  Future<void> _install() async {
    setState(() {
      _busy = true;
      _error = null;
      _success = null;
    });
    try {
      await ref.read(sleepRepositoryProvider).installDemoData();
      if (!mounted) return;
      setState(() => _success = '演示数据已安装。');
    } catch (error) {
      // 失败必须看得见。此前异常直接逃出去，界面只会表现为「点了没反应」。
      if (!mounted) return;
      setState(() => _error = '安装失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    // 清除是不可撤销的删除，与另外两处删除一样要过二次确认——此前这里点一下就删，
    // 是应用内唯一的例外。
    final confirmed = await showConfirmDialog(
      context,
      title: '清除演示数据？',
      message: '所有演示记录及其睡眠阶段、声音事件都会被永久删除，你自己的记录不受影响。',
      confirmLabel: '清除',
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
      await ref.read(sleepRepositoryProvider).deleteDemoData();
      if (!mounted) return;
      setState(() => _success = '演示数据已清除。');
    } catch (error) {
      // 同 _install：清除失败同样要在页内可见，不能静默。
      if (!mounted) return;
      setState(() => _error = '清除失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final entries = ref.watch(sleepEntriesProvider).valueOrNull ?? const [];
    final demoCount =
        entries.where((entry) => entry.source == AppConfig.demoSource).length;
    final realCount = entries.length - demoCount;

    return Subpage(
      backLabel: '设置',
      title: '演示数据',
      children: [
        GlassSurface(
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
                    child: AppIcons.sparkle(
                        size: 20, color: tokens.accent, strokeWidth: 1.8),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '示例睡眠记录',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: tokens.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          demoCount == 0 ? '当前没有演示记录' : '当前有 $demoCount 条演示记录',
                          style:
                              TextStyle(fontSize: 12, color: tokens.textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                '演示记录是随应用附带的样例，用来预览图表和详情页的外观。'
                '它们带有完整的睡眠阶段和声音事件，因此看起来比手写记录丰富——'
                '那是示例效果，不是对真人睡眠的测量。',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.55,
                  color: tokens.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                realCount == 0
                    ? '当前没有你自己的记录。'
                    : '你自己的记录有 $realCount 条，演示数据不会影响它们。',
                style: TextStyle(fontSize: 12, color: tokens.textMuted),
              ),
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
        if (_success != null) ...[
          const SizedBox(height: 12),
          Text(
            _success!,
            style: TextStyle(fontSize: 12, height: 1.5, color: tokens.accent),
          ),
        ],
        const SizedBox(height: 18),
        IosListGroup(
          children: [
            IosListItem(
              onTap: _busy || demoCount != 0 ? null : _install,
              child: _Row(
                label: '重新安装演示数据',
                muted: demoCount > 0,
                trailing: demoCount > 0 ? '已存在' : null,
                tokens: tokens,
              ),
            ),
            IosListItem(
              onTap: _busy || demoCount == 0 ? null : _clear,
              child: _Row(
                label: '清除演示数据',
                danger: demoCount > 0,
                muted: demoCount == 0,
                tokens: tokens,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppIcons.moon(size: 14, color: tokens.textMuted, strokeWidth: 1.6),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '发布构建里这个页面不会出现：演示数据由 DEMO_DATA 编译开关控制，'
                '默认只在调试构建中启用。',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: tokens.textMuted,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.tokens,
    this.trailing,
    this.danger = false,
    this.muted = false,
  });

  final String label;
  final AppTokens tokens;
  final String? trailing;
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
        if (trailing != null)
          Text(
            trailing!,
            style: TextStyle(fontSize: 12, color: tokens.textMuted),
          )
        else
          AppIcons.chevronRight(
            size: 15,
            color: tokens.textMuted,
            strokeWidth: 2,
          ),
      ],
    );
  }
}
