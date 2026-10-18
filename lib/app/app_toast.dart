import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_tokens.dart';
import '../core/widgets/liquid_glass.dart';

/// The most recent transient message, or null. Set it from anywhere with
/// `ref.read(toastProvider.notifier).show('...')`.
final toastProvider =
    NotifierProvider<ToastController, String?>(ToastController.new);

class ToastController extends Notifier<String?> {
  @override
  String? build() => null;

  /// Shows [message] for 3.6s, matching the prototype's dismissal timer.
  void show(String message) {
    state = message;
  }

  void clear() {
    if (state != null) state = null;
  }
}

/// `app-toast` — a floating pill above the tab bar that fades and lifts in.
class ToastOverlay extends ConsumerStatefulWidget {
  const ToastOverlay({super.key});

  @override
  ConsumerState<ToastOverlay> createState() => _ToastOverlayState();
}

class _ToastOverlayState extends ConsumerState<ToastOverlay> {
  static const _visibleFor = Duration(milliseconds: 3600);

  @override
  Widget build(BuildContext context) {
    final message = ref.watch(toastProvider);

    ref.listen<String?>(toastProvider, (previous, next) {
      if (next != null) {
        // Restart the timer for each new message.
        Future<void>.delayed(_visibleFor).then((_) {
          if (mounted && ref.read(toastProvider) == next) {
            ref.read(toastProvider.notifier).clear();
          }
        });
      }
    });

    final tokens = AppTokens.of(context);
    final isWide = MediaQuery.sizeOf(context).width >= 768;
    final visible = message != null;

    return Positioned(
      // Sits clear of the floating tab bar on phones, and closer to the edge on
      // wide layouts where there is no bar.
      //
      // 手机上的 100 是按**旧**胶囊顶边（99.5pt）算出来的，只留 0.5pt 间隙；
      // v2.7 之后胶囊顶边是 85pt，间隙变成 15pt。这是第二个写死的镜像值（第一个
      // 是标签条浮起量），**谁改浮起量就该顺手看这里**——否则它会跟着一起漂。
      // 见 `docs/superpowers/specs/2026-09-29-bottom-fade-design.md`「待核实事项」第 3 条。
      left: 16,
      right: 16,
      bottom: isWide ? 32 : 100,
      child: IgnorePointer(
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          offset: visible ? Offset.zero : const Offset(0, 0.75),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 180),
            opacity: visible ? 1 : 0,
            // 从下方顶上来时顺带「长开」一点：只有位移与淡入的话，
            // 一颗胶囊看起来像被搬进来，而不是弹出来。
            child: AnimatedScale(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              scale: visible ? 1 : 0.94,
              child: Center(
                child: LiquidGlass(
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                  blur: 28,
                  saturation: 1.5,
                  // 旧实现是「模糊 + 不透明底」，模糊其实被底盖住了；
                  // 换成半透明的强材质，背景才真的透得进来。
                  tint: tokens.materialStrong,
                  expandWidth: false,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shadow: [
                    BoxShadow(
                      color: const Color(0xFF16285B).withValues(alpha: 0.18),
                      blurRadius: 30,
                      offset: const Offset(0, 12),
                    ),
                  ],
                  child: Text(
                    message ?? '',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: tokens.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
