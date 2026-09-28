import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/config/app_config.dart';
import 'core/database/app_database.dart';
import 'features/sleep/data/demo_seed.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final database = await AppDatabase.open();

  // Demo rows are installed once, and only in builds where the flag is on.
  //
  // The condition is "no demo rows yet" rather than "the table is empty", so
  // turning the flag on later actually takes effect. Existing real records are
  // never touched: demo rows carry `source = 'demo'`, the UI badges them, and
  // `deleteDemoData` removes only those rows.
  if (AppConfig.demoDataEnabled) {
    final existing = await database.allRecords();
    final hasDemo = existing.any((row) => row.source == AppConfig.demoSource);
    if (!hasDemo) {
      await DemoSeed.install(database);
    }
  }

  runApp(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database)],
      child: const NightSleepApp(),
    ),
  );
}
