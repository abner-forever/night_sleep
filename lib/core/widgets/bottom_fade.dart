import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// 屏幕底部的模糊带：把滚到浮动标签条附近的内容糊掉、淡出。
///
/// 是 `top_fade.dart` 的镜像，但**常驻**——没有 `visible` 参数，也没有淡入淡出，
/// 因此不需要动效常量。高度由调用方按标签条的实际预留量推导后传入
/// （`app_shell.dart` 里是 `tabBarReserve(context) + 20`），这里不写死：
/// 标签条的浮起量一变，带子必须跟着走，否则两者在别的机型上会脱节。
///
/// 方向与顶部带**完全相反**：遮罩与填充两重衰减都朝上（越靠近屏幕底边越实）。
/// 直接抄顶部带的参数会得到「上重下轻」的逆向观感，而且不会报任何错。
class BottomFade extends StatelessWidget {
  const BottomFade({super.key, required this.height});

  final double height;

  /// 遮罩渐变的色标（上→下）与停点。
  ///
  /// 公开只为让测试钉住**方向**：`ShaderMask.shaderCallback` 返回的是 `Shader`，
  /// 测试拿不到原始渐变。组件内部用的就是这两个常量，不是另抄的一份。
  @visibleForTesting
  static const List<Color> maskColors = [
    Colors.transparent,
    Color(0x85000000),
    Colors.black,
    Colors.black,
  ];

  @visibleForTesting
  static const List<double> maskStops = [0.0, 0.32, 0.66, 1.0];

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    return IgnorePointer(
      child: SizedBox(
        height: height,
        width: double.infinity,
        // 遮罩套在 BackdropFilter **外面**。
        //
        // `BackdropFilter` 模糊的是它子树**之外**、身后已经画好的画面，套在里面的
        // ShaderMask 只管得到填充，模糊会留一条硬边，读起来像页面上的一道接缝。
        // `mask-image: linear-gradient(transparent 0%, rgba(0,0,0,.52) 32%, #000 66%, #000 100%)`。
        child: ShaderMask(
          shaderCallback: (rect) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: maskColors,
            stops: maskStops,
          ).createShader(rect),
          blendMode: BlendMode.dstIn,
          child: ClipRect(
            child: Stack(
              children: [
                BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                  // `StackFit.loose` 下 Stack 按最大的非 position 子项定尺寸，
                  // 这里必须撑满，否则整条带会静缩到内容大小。
                  child: const SizedBox.expand(),
                ),
                // `saturate(125%)` 的近似，与顶部带同一个手法、同一个浓度：
                // `ImageFilter` 没有内置的 saturate 构造器。
                Positioned.fill(
                  child: ColoredBox(
                    color: tokens.accent.withValues(alpha: 0.04),
                  ),
                ),
                // 填充从顶部 0 升到底边 78%，是顶部带那条曲线按 0.78/0.92 缩放后的镜像。
                // 同样必须 `Positioned.fill`：无子节点的 DecoratedBox 在 loose 下会
                // 缩成 0×0，渐变整条消失。
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          tokens.bgBase.withValues(alpha: 0),
                          tokens.bgBase.withValues(alpha: 0.27),
                          tokens.bgBase.withValues(alpha: 0.61),
                          tokens.bgBase.withValues(alpha: 0.78),
                        ],
                        stops: const [0.0, 0.30, 0.62, 1.0],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
