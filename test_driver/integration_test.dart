import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Screenshot sink for the tour in `integration_test/app_screens_test.dart`.
///
/// Run with:
/// ```bash
/// flutter drive \
///   --driver=test_driver/integration_test.dart \
///   --target=integration_test/app_screens_test.dart \
///   -d <simulator-id>
/// ```
/// Images land in `screenshots/`, which is git-ignored: they are a review aid,
/// not an artefact of the app.
Future<void> main() async {
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      final file = File('screenshots/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes);
      return true;
    },
  );
}
