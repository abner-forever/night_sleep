import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/platform/app_installer.dart';
import '../domain/app_release.dart';
import 'app_update_service.dart';

final appPackageInfoProvider = FutureProvider<PackageInfo>(
  (ref) => PackageInfo.fromPlatform(),
);

final appUpdateServiceProvider = Provider<AppUpdateService>((ref) {
  final service = GithubAppUpdateService();
  ref.onDispose(service.dispose);
  return service;
});

final appInstallerProvider =
    Provider<AppInstaller>((ref) => AndroidAppInstaller());

final appUpdatePlatformProvider = Provider<TargetPlatform?>((ref) {
  if (kIsWeb) return null;
  if (Platform.isAndroid) return TargetPlatform.android;
  if (Platform.isIOS) return TargetPlatform.iOS;
  return null;
});

enum UpdatePhase {
  idle,
  checking,
  current,
  available,
  downloading,
  installing,
  ready,
  permission,
  failed
}

class AppUpdateState {
  const AppUpdateState({
    this.phase = UpdatePhase.idle,
    this.release,
    this.received = 0,
    this.message,
  });

  final UpdatePhase phase;
  final AppRelease? release;
  final int received;
  final String? message;

  bool get busy =>
      phase == UpdatePhase.checking ||
      phase == UpdatePhase.downloading ||
      phase == UpdatePhase.installing;
}

final appUpdateProvider =
    StateNotifierProvider<AppUpdateController, AppUpdateState>(
  (ref) => AppUpdateController(
    service: ref.watch(appUpdateServiceProvider),
    installer: ref.watch(appInstallerProvider),
    packageInfo: () => ref.read(appPackageInfoProvider.future),
    platform: ref.watch(appUpdatePlatformProvider),
  ),
);

class AppUpdateController extends StateNotifier<AppUpdateState> {
  AppUpdateController({
    required this.service,
    required this.installer,
    required this.packageInfo,
    required this.platform,
  }) : super(const AppUpdateState());

  final AppUpdateService service;
  final AppInstaller installer;
  final Future<PackageInfo> Function() packageInfo;
  final TargetPlatform? platform;
  File? _apk;
  bool _installing = false;
  bool _cancelling = false;

  Future<void> check({bool force = false}) async {
    if (platform != TargetPlatform.android ||
        state.busy ||
        _installing ||
        (!force && state.phase != UpdatePhase.idle)) {
      return;
    }
    state = AppUpdateState(phase: UpdatePhase.checking, release: state.release);
    try {
      final release = await service.check(await packageInfo());
      if (!mounted) return;
      _apk = null;
      state = AppUpdateState(
        phase: release == null ? UpdatePhase.current : UpdatePhase.available,
        release: release,
      );
    } catch (error) {
      if (!mounted) return;
      state = AppUpdateState(
        phase: UpdatePhase.failed,
        release: state.release,
        message: _message(error, '检查失败，请检查网络后重试。'),
      );
    }
  }

  Future<void> update() async {
    final release = state.release;
    if (platform != TargetPlatform.android ||
        release == null ||
        state.busy ||
        _installing) {
      return;
    }
    _installing = true;
    try {
      if (_apk == null || !await _apk!.exists()) {
        state =
            AppUpdateState(phase: UpdatePhase.downloading, release: release);
        _apk = await service.download(release, (bytes) {
          if (mounted) {
            state = AppUpdateState(
              phase: UpdatePhase.downloading,
              release: release,
              received: bytes,
            );
          }
        });
      }
      if (!mounted) return;
      if (_cancelling) {
        _apk = null;
        state = AppUpdateState(
            phase: UpdatePhase.available, release: release, message: '下载已取消。');
        return;
      }
      state = AppUpdateState(phase: UpdatePhase.installing, release: release);
      final opened = await installer.install(_apk!.path, release);
      if (!mounted) return;
      state = AppUpdateState(
        phase: opened ? UpdatePhase.ready : UpdatePhase.permission,
        release: release,
        message: opened
            ? '已打开系统安装界面。如果尚未完成，可再次点击安装。'
            : '请在系统设置中允许安装此来源的应用，返回后点击「继续安装」。',
      );
    } catch (error) {
      if (!mounted) return;
      state = AppUpdateState(
        phase: _cancelling ? UpdatePhase.available : UpdatePhase.failed,
        release: release,
        message:
            _cancelling ? '下载已取消。' : _message(error, '更新失败，请检查网络或存储空间后重试。'),
      );
    } finally {
      _installing = false;
      _cancelling = false;
    }
  }

  void cancel() {
    if (state.phase != UpdatePhase.downloading) return;
    _cancelling = true;
    service.cancelDownload();
  }

  String _message(Object error, String fallback) => switch (error) {
        AppUpdateException() => error.message,
        PlatformException() => error.message ?? fallback,
        _ => fallback,
      };
}
