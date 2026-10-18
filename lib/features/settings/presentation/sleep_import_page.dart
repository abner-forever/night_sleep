import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_basics.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/glass_surface.dart';
import '../../../core/widgets/ios_controls.dart';
import '../../../core/widgets/subpage.dart';

/// Xiaomi band sleep-data import.
///
/// The layout matches the design, but importing is **not** implemented: the
/// spec forbids guessing a vendor's file format, and no real export sample has
/// been supplied yet, so there is no adapter to run. The screen therefore
/// explains what it will import and what is still missing instead of showing a
/// file picker that ends in a fabricated success message.
class SleepImportPage extends StatefulWidget {
  const SleepImportPage({super.key});

  @override
  State<SleepImportPage> createState() => _SleepImportPageState();
}

class _SleepImportPageState extends State<SleepImportPage> {
  static const _willImport = [
    ('睡眠时长', '总睡眠与入睡/起床时间'),
    ('深睡眠', '深睡时长与占比'),
    ('浅睡眠', '浅睡时长与占比'),
    ('快速眼动', 'REM 时长与占比'),
  ];

  /// 按钮是禁用的，但点得动：点过之后在**本页**给一句解释。
  ///
  /// 之所以不走 `toastProvider`：它挂在 `AppScaffold` 里，而这一页 push 在外壳
  /// 之上，提示条会被整个盖住，等于没提示。
  bool _blockedNotice = false;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    return Subpage(
      title: '睡眠数据导入',
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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '小米手环',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.96,
                            color: tokens.textMuted,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '导入睡眠数据',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: tokens.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Tag(
                    label: '仅睡眠阶段',
                    background: tokens.accentSoft,
                    foreground: tokens.accent,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Status panel replacing the prototype's "choose a file" flow.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: tokens.bgMuted,
                  borderRadius: BorderRadius.circular(AppRadii.panel),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListIconBadge(
                      background: tokens.bgCard,
                      size: 40,
                      child: AppIcons.wave(
                          size: 21, color: tokens.warn, strokeWidth: 1.7),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '适配器待接入',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: tokens.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '导入需要小米运动/小米手环的真实导出文件样本（或官方授权接口的字段说明）才能实现。'
                            '在拿到样本之前不会解析文件，也不会写入任何记录。',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.5,
                              color: tokens.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              Text(
                '将导入',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.96,
                  color: tokens.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < _willImport.length; i += 2) ...[
                if (i > 0) const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _ImportField(data: _willImport[i])),
                    const SizedBox(width: 8),
                    Expanded(
                      child: i + 1 < _willImport.length
                          ? _ImportField(data: _willImport[i + 1])
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),

              // The design is explicit that audio events never come from the
              // band; keep that boundary visible.
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: tokens.bgMuted,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppIcons.snore(
                      size: 17,
                      color: tokens.accentViolet,
                      strokeWidth: 1.7,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '鼾声与梦话不从手环导入。',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: tokens.textPrimary,
                              ),
                            ),
                            const TextSpan(
                              text: '这些事件继续由手机夜间录音检测并生成睡眠洞察。',
                            ),
                          ],
                        ),
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: tokens.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              PrimaryAction(
                label: '导入睡眠记录',
                // Disabled rather than wired to a fake adapter.
                onTap: null,
                // 仍然禁用——拿到小米的导出样本或官方字段说明之前没有适配器可跑。
                // 区别只是：这一按现在会**在按钮下面**说明原因，而不是毫无反应。
                onBlockedTap: () => setState(() => _blockedNotice = true),
                trailing: AppIcons.chevronRight(
                  size: 18,
                  color: Colors.white,
                  strokeWidth: 2.2,
                ),
              ),
              const SizedBox(height: 8),
              // 两句话说的是同一件事，共用一个槽位：第一眼是那句常驻说明，点过按钮之后
              // 整句换成「还没有接入导入……」。并列成两行只会让人怀疑它们在说不同的
              // 事——也正因为如此，常驻那行不能删：它是从不点按钮的人唯一的解释来源。
              Text(
                _blockedNotice
                    ? '还没有接入导入：需要小米的导出样本或官方字段说明。'
                    : '需要你提供小米的导出样本后，这里才会启用。',
                style: _blockedNotice
                    ? TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: tokens.caution,
                      )
                    : TextStyle(fontSize: 12, color: tokens.textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ImportField extends StatelessWidget {
  const _ImportField({required this.data});

  final (String, String) data;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: tokens.bgMuted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            data.$1,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: tokens.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            data.$2,
            style: TextStyle(fontSize: 10, color: tokens.textMuted),
          ),
        ],
      ),
    );
  }
}
