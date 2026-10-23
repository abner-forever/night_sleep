import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_tokens.dart';
import '../core/widgets/liquid_glass.dart';
import 'app_shell.dart';

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
    final padding = MediaQuery.paddingOf(context);
    final visible = message != null;

    return Positioned(
      left: padding.left + 16,
      right: padding.right + 16,
      bottom: pageBottomInset(context),
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
