import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import 'app_basics.dart';

/// 按项目令牌自绘的 iOS 风格确认弹窗，居中显示。
///
/// 应用内原有的两处二次确认走的是 `showDialog` + Material `AlertDialog`，于是
/// 整个 iOS 玻璃 / 令牌体系里唯独确认弹窗是 Material 的 Android 默认外观。改用
/// [showGeneralDialog] 自绘之后，颜色、圆角、动效都回到 `AppTokens` / `AppRadii` /
/// `AppMotion` 这一份来源上。
///
/// **不引入 `flutter/cupertino.dart`**：`CupertinoAlertDialog` 自带系统配色与圆角，
/// 会绕过 `AppTokens`，与「设计令牌只有一份」这条硬约定冲突。
///
/// **也不用 `AppSheet`**：它永远是底部贴边面板，没有居中变体。
///
/// 返回值只有 `true` / `false` 两种：**取消与点蒙层关闭一律返回 `false`**，因此调用方
/// 可以继续写 `if (confirmed != true) return;`。
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = '取消',
  bool destructive = false,
}) async {
  final tokens = AppTokens.of(context);

  final confirmed = await showGeneralDialog<bool>(
    context: context,
    // 蒙层可点走，且语义上等同取消 —— 下面把 `null` 折成 `false`。
    barrierDismissible: true,
    barrierLabel: '关闭',
    barrierColor: tokens.overlayScrim,
    transitionDuration: AppDurations.standard,
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curve = CurvedAnimation(
        parent: animation,
        curve: AppMotion.standardCurve,
      );
      // iOS 的 alert 是「微微收紧 + 淡入」，而不是从屏幕底部推上来。
      return FadeTransition(
        opacity: curve,
        child: ScaleTransition(
          scale: Tween<double>(begin: 1.06, end: 1).animate(curve),
          child: child,
        ),
      );
    },
    pageBuilder: (context, animation, secondaryAnimation) => _ConfirmDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      destructive: destructive,
    ),
  );

  return confirmed == true;
}

class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.destructive,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    // 阴影画在这个盒子上、而不是一个被自己裁掉的盒子里的那个盒子上：这里刻意不用
    // `ClipRRect`（卡片底色不透明，本来也没有要裁的东西），否则阴影会被静默丢弃。
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: tokens.bgCardSolid,
              borderRadius: BorderRadius.circular(AppRadii.sheet),
              border: Border.all(color: tokens.glassBorder),
              boxShadow: tokens.surfaceShadow,
            ),
            // `showGeneralDialog` 不像 `showDialog` 那样替路由包一层 `Material`，
            // 缺了它这里每个 `Text` 都会落到 Flutter 的错误样式——黄色双下划线。
            // `AppSheet` 与 `Subpage` 都补过同一层。
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.4,
                            color: tokens.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          message,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.45,
                            color: tokens.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 动作区分左右两半，取消在左、确认在右，与它替换掉的那两处弹窗一致。
                  // `IntrinsicHeight` 让中间那条 1px 分隔线跟着最高的按钮走，而不是
                  // 写死一个高度——写死的值会在字号或行高一变时露出破绽。
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _Action(
                            label: cancelLabel,
                            color: tokens.accent,
                            onTap: () => Navigator.of(context).pop(false),
                          ),
                        ),
                        // 1px 分隔线。用 `SizedBox` + `ColoredBox` 而不是
                        // `VerticalDivider`：这一行是拉伸的，要的是「跟两边按钮一样高」，
                        // 而 `VerticalDivider` 的高度由它自己的 `height`/`indent` 决定。
                        SizedBox(
                          width: 1,
                          child: ColoredBox(color: tokens.border),
                        ),
                        Expanded(
                          child: _Action(
                            label: confirmLabel,
                            color: destructive ? tokens.danger : tokens.accent,
                            onTap: () => Navigator.of(context).pop(true),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.96,
      semanticLabel: label,
      child: Container(
        alignment: Alignment.center,
        constraints: const BoxConstraints(minHeight: 50),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.3,
            color: color,
          ),
        ),
      ),
    );
  }
}
