import 'package:flutter/material.dart';

import '../../../../core/platform/haptics.dart';
import '../../../../core/theme/app_tokens.dart';
import '../night_style.dart';

/// 左上角的「收起」胶囊。
///
/// 两态共用同一颗胶囊（原型 setup 态的 `.sleep-navigation-back`，激活态沿用它）：
/// 形态一个字不改，差的是**收起之后发生什么**——进行中态收起只是离开页面、会话继续跑
/// （偏差 #28），入睡前态收起则要顺带把试听停掉，且什么都不写库。
///
/// min 56×34、圆角 999、`1px rgba(255,255,255,.11)`、`rgba(255,255,255,.065)` 底、
/// 文字 13/w600。
class CollapsePill extends StatelessWidget {
  const CollapsePill({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        AppHaptics.tap();
        onTap();
      },
      child: Container(
        constraints: const BoxConstraints(minWidth: 56, minHeight: 34),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: NightStyle.glassFill,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          border: Border.all(color: NightStyle.glassStroke),
        ),
        alignment: Alignment.center,
        child: const Text(
          '收起',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: NightStyle.glassInk,
          ),
        ),
      ),
    );
  }
}
