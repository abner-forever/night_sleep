import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_tokens.dart';

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
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.pill),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: tokens.bgCardSolid,
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                      border: Border.all(color: tokens.glassBorder),
                      boxShadow: [
                        BoxShadow(
                          color:
                              const Color(0xFF16285B).withValues(alpha: 0.18),
                          blurRadius: 30,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
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
      ),
    );
  }
}
