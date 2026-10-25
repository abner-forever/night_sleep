import 'package:flutter/material.dart';

import '../platform/haptics.dart';
import '../theme/app_tokens.dart';
import 'glass_surface.dart';

/// Wraps any tappable child in the prototype's `tap-scale` press animation.
///
/// The design applies this to nearly every interactive element, including bare
/// text buttons and list rows that are not [GlassSurface]s.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    required this.onTap,
    this.scale = 0.972,
    this.haptic = true,
    this.semanticLabel,
    this.isButton = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final bool haptic;
  final String? semanticLabel;
  final bool isButton;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return Semantics(
      label: widget.semanticLabel,
      button: widget.isButton,
      enabled: enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTap: enabled
            ? () {
                if (widget.haptic) AppHaptics.tap();
                widget.onTap!();
              }
            : null,
        child: AnimatedScale(
          scale: _pressed ? widget.scale : 1,
          duration: const Duration(milliseconds: 180),
          curve: AppMotion.standardCurve,
          child: widget.child,
        ),
      ),
    );
  }
}

/// 新版分区标题。
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.label, {super.key, this.padding});

  final String label;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Padding(
      padding: padding ?? const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          color: tokens.textPrimary,
        ),
      ),
    );
  }
}

/// 页面标题与可选的辅助说明。
class PageHeading extends StatelessWidget {
  const PageHeading({super.key, this.eyebrow, required this.title});

  final String? eyebrow;
  final String title;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (eyebrow != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              eyebrow!,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.96,
                color: tokens.textMuted,
              ),
            ),
          ),
        Text(
          title,
          style: TextStyle(
            fontSize: 29,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.8,
            height: 1.2,
            color: tokens.textPrimary,
          ),
        ),
      ],
    );
  }
}

/// `empty-state` — a glass card with an accent orb, title, body and optional
/// call to action. Used by Home and Statistics when nothing is recorded yet.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  final Widget icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return GlassSurface(
      borderRadius: BorderRadius.circular(AppRadii.card),
      padding: const EdgeInsets.fromLTRB(24, 44, 24, 44),
      // **`SizedBox(width: double.infinity)` 是必须的。** `GlassSurface` 把子项画在
      // `Stack` 里，而非定位子项拿到的是**宽松**约束——`Column` 于是在那种约束下缩到
      // 最宽子项的宽度（这里就是标题那一行的宽度）并被左锚定，`crossAxisAlignment`
      // 的中心只在那一小段里生效，整块看着就是「贴着左边、没居中」。
      // `GlassSurface.expandWidth` 撑的是**卡**，不是卡里的内容，两者不是一件事。
      // 2026-10-16 使用方在真机上看出「兜底组件没居中」就是这一处；它影响的是
      // 全应用每个空状态（首页 / 统计 / 全部数据页 / 导出预览 / 详情弹层都在用）。
      child: SizedBox(
        width: double.infinity,
        child: Column(
          children: [
            Container(
              width: 68,
              height: 68,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: tokens.accentSoft,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: icon,
            ),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: tokens.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Text(
                body,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: tokens.textMuted,
                ),
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              Pressable(
                onTap: onAction,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: tokens.accent,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    actionLabel!,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 新版实色主操作按钮。
///
/// The prototype composes these from a label block plus a trailing icon, laid
/// out with `space-between`; [subtitle] and [trailing] reproduce that.
class PrimaryAction extends StatelessWidget {
  const PrimaryAction({
    super.key,
    required this.label,
    this.subtitle,
    this.trailing,
    this.onTrailingTap,
    this.trailingSemanticLabel,
    this.onTap,
    this.onBlockedTap,
    this.leading,
    this.semanticLabel,
  });

  final String label;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTrailingTap;
  final String? trailingSemanticLabel;
  final Widget? leading;

  /// 启用态：点击就执行它。
  final VoidCallback? onTap;

  /// 禁用态仍然接住点击时回调这里——按钮外观保持禁用，但不再是「点了没反应」。
  ///
  /// `onTap` 为空时才生效：能力还没实现（例如导入适配器未接入）的按钮既要如实
  /// 显示成不可用，又要在用户按下去时说明原因。`onTap` 非空时本回调完全不参与。
  final VoidCallback? onBlockedTap;

  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final enabled = onTap != null;

    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: Pressable(
        // 禁用态也接住手势，好把「为什么不能用」讲给用户。
        onTap: onTap ?? onBlockedTap,
        // 触觉反馈只属于启用态：禁用态给提示时不该有「按下了」的手感。
        haptic: enabled,
        semanticLabel: semanticLabel ?? label,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: tokens.primaryActionFill,
            borderRadius: BorderRadius.circular(17),
          ),
          child: Stack(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 19, vertical: 16),
                child: Row(
                  children: [
                    if (leading != null) ...[
                      leading!,
                      const SizedBox(width: 12)
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            label,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: -0.3,
                            ),
                          ),
                          if (subtitle != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                subtitle!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withValues(alpha: 0.8),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (trailing != null)
                      Semantics(
                        button: onTrailingTap != null,
                        label: trailingSemanticLabel,
                        child: GestureDetector(
                          behavior: onTrailingTap == null
                              ? HitTestBehavior.deferToChild
                              : HitTestBehavior.opaque,
                          onTap: enabled ? onTrailingTap : null,
                          child: trailing!,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small rounded label, e.g. the quality tag on a record card.
class Tag extends StatelessWidget {
  const Tag({
    super.key,
    required this.label,
    this.background,
    this.foreground,
    this.fontSize = 12,
    this.padding = const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
  });

  final String label;
  final Color? background;
  final Color? foreground;
  final double fontSize;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: background ?? tokens.bgMuted,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w500,
          color: foreground ?? tokens.textMuted,
        ),
      ),
    );
  }
}

/// `--bg-muted` inset block: used for stat tiles, transcripts and notes.
class InsetPanel extends StatelessWidget {
  const InsetPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius,
    this.color,
    this.border,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius? borderRadius;
  final Color? color;
  final BoxBorder? border;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? tokens.bgMuted,
        borderRadius: borderRadius ?? BorderRadius.circular(AppRadii.panel),
        border: border,
      ),
      child: child,
    );
  }
}
