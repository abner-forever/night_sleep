import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';

/// `settings-footnote` —— 列表组下面那行小字说明。
///
/// 左右各 12px 而不是 4px：它要跟组内**文字列**的左边缘对齐，而不是跟整组的
/// 圆角外沿对齐（原型的 `margin: 8px 12px 0` 就是这个意思）。
class SettingsFootnote extends StatelessWidget {
  const SettingsFootnote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          height: 1.45,
          color: tokens.textMuted,
        ),
      ),
    );
  }
}
