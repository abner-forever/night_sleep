import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/liquid_glass.dart';
import '../night_style.dart';

/// 左上角的「收起」胶囊。
///
/// 两态共用同一颗胶囊（原型 setup 态的 `.sleep-navigation-back`，激活态沿用它）：
/// 形态一个字不改，差的是**收起之后发生什么**——进行中态收起只是离开页面、会话继续跑
/// （偏差 #28），入睡前态收起则要顺带把试听停掉，且什么都不写库。
///
/// min 56×34、圆角 999、`1px rgba(255,255,255,.11)`、`rgba(255,255,255,.065)` 底、
/// 文字 13/w600。底色仍是原型那一层，外面换成液态玻璃的模糊与内缘高光——它浮在
/// 整屏夜景上，模糊能让人一眼看出这是「玻璃」而不是一块半透明填充。
class CollapsePill extends StatelessWidget {
  const CollapsePill({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 56, minHeight: 34),
      child: LiquidGlass(
        borderRadius: BorderRadius.circular(AppRadii.pill),
        blur: 16,
        saturation: 1.3,
        tint: NightStyle.glassFill,
        expandWidth: false,
        // 原型这颗胶囊没有投影；夜景里也不需要再压暗一层。
        shadow: const [],
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
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
