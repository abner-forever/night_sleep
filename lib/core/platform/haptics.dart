import 'package:flutter/services.dart';

/// Lightweight tactile feedback for touch interactions.
///
/// The prototype calls `navigator.vibrate(...)` with raw millisecond patterns.
/// Flutter exposes no pattern API, so each call site maps to the closest
/// semantic haptic instead of a duration — which is also what iOS does
/// natively, since the platform ignores custom vibration lengths.
///
/// Every method is a no-op on platforms without a haptic engine (macOS
/// desktop, web), matching the prototype's guarded `try/catch`.
abstract final class AppHaptics {
  /// Tab switches and committing a picker value. Prototype: `haptic(8)`.
  static Future<void> select() => HapticFeedback.selectionClick();

  /// Confirming a toggle or starting an action. Prototype: `haptic(12)`.
  static Future<void> tap() => HapticFeedback.lightImpact();

  /// Saving a record. Prototype: `haptic([12, 40, 12])`.
  static Future<void> success() => HapticFeedback.mediumImpact();
}
