import 'package:flutter/foundation.dart';

/// Build-time switches.
abstract final class AppConfig {
  /// Whether the bundled demo dataset is offered.
  ///
  /// The spec requires demo data to be isolated from real data and off in
  /// release builds, so this defaults to [kDebugMode] — on for debug and
  /// profile runs, off for release — and can be forced either way:
  ///
  /// ```
  /// flutter run --dart-define=DEMO_DATA=true
  /// flutter build apk --dart-define=DEMO_DATA=false
  /// ```
  ///
  /// Even when enabled, demo rows are tagged `source == 'demo'` and can be
  /// cleared from Settings, so they never mix silently with real entries.
  static const bool demoDataEnabled = bool.fromEnvironment(
    'DEMO_DATA',
    defaultValue: kDebugMode,
  );

  /// `source` value marking bundled sample rows.
  static const String demoSource = 'demo';
}
