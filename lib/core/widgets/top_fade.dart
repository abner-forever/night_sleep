import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// 规格 §2.2 的 320ms。`AppDurations.standard` 是 340ms 且被多处共用，
/// 改它会波及无关动效，所以这里另立常量。
const Duration _fadeDuration = Duration(milliseconds: 320);

/// `.ios-top-fade` —— 页面内容滚进状态栏时把它淡出的半透明带。
///
/// 只有当页面滚动超过 [revealAfter] 像素后才出现，用时为设计规定的 320ms
/// （[_fadeDuration]）。它是固定覆盖层而非滚动视图的一部分，所以不能接收点击。
class TopFade extends StatelessWidget {
  const TopFade({
    super.key,
    required this.visible,
    this.height = 144,
  });

  final bool visible;
  final double height;

  /// The design reveals it at `scrollTop > 12`.
  static const double revealAfter = 12;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    return IgnorePointer(
      child: AnimatedSlide(
        duration: _fadeDuration,
        curve: AppMotion.standardCurve,
        offset: visible ? Offset.zero : const Offset(0, -10 / 144),
        child: AnimatedOpacity(
          duration: _fadeDuration,
          curve: AppMotion.standardCurve,
          opacity: visible ? 1 : 0,
          child: SizedBox(
            height: height,
            width: double.infinity,
            // The mask wraps the blur, it does not sit inside it.
            //
            // `BackdropFilter` blurs what is painted *behind* it, outside its own
            // subtree — so a `ShaderMask` nested underneath only fades the tint
            // while the blur keeps a hard edge, which reads as a visible seam
            // across the page. Outside, the mask applies to the composited blur.
            //
            // `mask-image: linear-gradient(#000 0%, #000 34%, rgba(0,0,0,.52)
            // 68%, transparent 100%)`, mirroring the design.
            child: ShaderMask(
              shaderCallback: (rect) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black,
                  Colors.black,
                  Color(0x85000000),
                  Colors.transparent,
                ],
                stops: [0.0, 0.34, 0.68, 1.0],
              ).createShader(rect),
              blendMode: BlendMode.dstIn,
              child: ClipRect(
                child: Stack(
                  children: [
                    BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                      // `StackFit.loose` 下 `Stack` 按最大的非 position 子项定尺寸，
                      // 所以这里必须撑满，否则整条带会静缩到内容大小。
                      child: const SizedBox.expand(),
                    ),
                    // `saturate(125%)` 在 `ImageFilter` 里没有对应物，用一层极淡的
                    // accent 混合近似——`glass_surface.dart` 用的就是这个办法。
                    // 刻意很淡：要的是设计里那点色彩抬升，不是染色。
                    Positioned.fill(
                      child: IgnorePointer(
                        child: ColoredBox(
                          color: tokens.accent.withValues(alpha: 0.04),
                        ),
                      ),
                    ),
                    // 填充渐变原样保留，只是从 `BackdropFilter` 的 child 变成兄弟节点。
                    // 同样必须 `Positioned.fill` 撑满：无子节点的 `DecoratedBox` 在
                    // `StackFit.loose` 下会缩成 0×0，渐变会整条消失。
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              tokens.bgBase.withValues(alpha: 0.92),
                              tokens.bgBase.withValues(alpha: 0.72),
                              tokens.bgBase.withValues(alpha: 0.32),
                              tokens.bgBase.withValues(alpha: 0),
                            ],
                            stops: const [0.0, 0.38, 0.70, 1.0],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
