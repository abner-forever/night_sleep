import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// 二次确认弹窗，直接用 iOS 系统组件 [CupertinoAlertDialog]。
///
/// 应用内三处危险操作统一走它：删除单条记录、删除全部本地数据、清除演示数据。
/// 调用方只认返回值，不关心实现。
///
/// **历史**：本组件一度是「按令牌自绘的 iOS 风格盒子」（`showGeneralDialog` +
/// `DecoratedBox` 卡片 + 手画的两条发丝分隔线 + 手写转场）。那是为了守住「设计令牌
/// 只有一份」这条约定——`CupertinoAlertDialog` 自带的系统配色会绕过 [AppTokens]。
/// v3.6 起按用户要求改回**系统组件**：布局、模糊表面、圆角、分隔线、文字排版与
/// 弹簧转场全部交给 iOS 原实现，**代价是弹窗底色与分隔线色不再来自令牌**。
/// 取舍与理由记在规格偏差 #20。
///
/// **仍然接回令牌的部分**（能接的都接）：
///  * 亮度（[Theme.of] 的 brightness）——决定系统底色的深浅，深色模式下不会错成浅色；
///  * `primaryColor` → `tokens.accent`（非破坏性动作的默认色）；
///  * 两个动作的 `textStyle.color` → [AppTokens.accent] / [AppTokens.danger]。
///    `CupertinoDialogAction.textStyle` 在系统色**解析之后**才 merge，所以这里能盖掉
///    destructive 写死的 `CupertinoColors.systemRed`（已核对 SDK 源码：`textStyle` 的
///    merge 在颜色 copyWith 之后）。只传 `color`、不传 `fontSize`：SDK 文档要求
///    「非默认字号才传 `textStyle`」，传了会绕过它自带的缩放策略。
///
/// **返回值只有 `true` / `false`**：取消与点蒙层一律 `false`，调用方可以继续写
/// `if (confirmed != true) return;`。
///
/// **点蒙层可关闭是保留行为**：系统 alert 默认 `barrierDismissible: false`，但三处
/// 调用方与既有测试都依赖「点蒙层 = 取消」，这里显式传 `true` 维持原语义。
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = '取消',
  bool destructive = false,
}) async {
  final tokens = AppTokens.of(context);
  // 跟随应用主题、而不是 `MediaQuery.platformBrightness`：用户把外观设成「深色」时
  // 系统亮度可能仍是浅色，照抄会让弹窗底色与整个应用相反。
  final brightness = Theme.of(context).brightness;

  final confirmed = await showCupertinoDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭',
    // 蒙层色继续取令牌，与 `AppSheet` 同源。
    barrierColor: tokens.overlayScrim,
    builder: (context) => CupertinoTheme(
      data: CupertinoThemeData(
        brightness: brightness,
        primaryColor: tokens.accent,
      ),
      child: CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        // 顺序即左右次序：取消在左、确认在右，与它取代的两处弹窗一致，
        // 避免肌肉记忆错位。两个动作时系统会排成并排一行。
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            textStyle: TextStyle(color: tokens.accent),
            child: Text(cancelLabel),
          ),
          CupertinoDialogAction(
            // iOS 的「默认动作」：加粗，对应原先确认按钮的 w600。
            isDefaultAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            textStyle: TextStyle(
              color: destructive ? tokens.danger : tokens.accent,
            ),
            child: Text(confirmLabel),
          ),
        ],
      ),
    ),
  );

  return confirmed == true;
}
