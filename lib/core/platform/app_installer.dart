import 'package:flutter/services.dart';

import '../../features/settings/domain/app_release.dart';

abstract interface class AppInstaller {
  Future<bool> install(String path, AppRelease release);
}

class AndroidAppInstaller implements AppInstaller {
  static const channel = MethodChannel('night_sleep/app_update');

  @override
  Future<bool> install(String path, AppRelease release) async {
    return await channel.invokeMethod<bool>('install', {
          'path': path,
          'version': release.version,
          'buildNumber': release.buildNumber,
          'sha256': release.sha256,
        }) ??
        false;
  }
}
