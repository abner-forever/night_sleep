import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:night_sleep/core/platform/app_installer.dart';
import 'package:night_sleep/features/settings/data/app_update_controller.dart';
import 'package:night_sleep/features/settings/data/app_update_service.dart';
import 'package:night_sleep/features/settings/domain/app_release.dart';
import 'package:package_info_plus/package_info_plus.dart';

PackageInfo installed({String version = '0.49.0-beta.2', String build = '3'}) =>
    PackageInfo(
        appName: '夜深',
        packageName: 'com.abner.night_sleep',
        version: version,
        buildNumber: build);

Map<String, dynamic> metadata(String version, int build, List<int> bytes) => {
      'version': version,
      'tag': 'v$version',
      'build_number': build,
      'filename': 'night-sleep-$version-android.apk',
      'sha256': sha256.convert(bytes).toString(),
      'size': bytes.length,
      'signing': 'release',
    };

Map<String, dynamic> releaseData(String version, List<int> bytes) => {
      'tag_name': 'v$version',
      'draft': false,
      'published_at': '2026-10-20T00:00:00Z',
      'body': '改善睡眠记录体验',
      'assets': [
        for (final name in ['night-sleep-$version-android.apk', 'release.json'])
          {
            'name': name,
            'state': 'uploaded',
            'size': bytes.length,
            'digest': 'sha256:${sha256.convert(bytes)}',
            'browser_download_url':
                'https://github.com/abner-forever/night_sleep/releases/download/v$version/$name',
          },
      ],
    };

final testRelease = AppRelease(
  version: '0.49.0-beta.3',
  buildNumber: 4,
  url: Uri.parse(
      'https://github.com/abner-forever/night_sleep/releases/download/v0.49.0-beta.3/night-sleep-0.49.0-beta.3-android.apk'),
  sha256: sha256.convert([1, 2, 3]).toString(),
  size: 3,
  notes: '改善睡眠记录体验',
);

class FakeUpdates implements AppUpdateService {
  AppRelease? available = testRelease;
  int checks = 0;
  int downloads = 0;
  Object? failure;
  Completer<File>? pendingDownload;
  void Function(int)? progress;
  final file = File('${Directory.systemTemp.path}/night-sleep-test.apk');

  @override
  Future<AppRelease?> check(PackageInfo installed) async {
    checks++;
    if (failure != null) throw failure!;
    return available;
  }

  @override
  Future<File> download(
      AppRelease release, void Function(int) onProgress) async {
    downloads++;
    progress = onProgress;
    onProgress(1);
    if (pendingDownload != null) return pendingDownload!.future;
    await file.writeAsBytes([1, 2, 3]);
    return file;
  }

  @override
  void cancelDownload() =>
      pendingDownload?.completeError(const AppUpdateException('下载已取消。'));

  @override
  void dispose() {}
}

class FakeInstaller implements AppInstaller {
  bool allowed = true;
  int calls = 0;

  @override
  Future<bool> install(String path, AppRelease release) async {
    calls++;
    return allowed;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('version labels separate prerelease sequence and hide build numbers',
      () {
    expect(formatAppVersion('0.49.0-beta.2'), '0.49.0（Beta 2）');
    expect(formatAppVersion('0.49.0-beta.2+3'), '0.49.0（Beta 2）');
    expect(formatAppVersion('0.49.0'), '0.49.0');
    expect(formatAppVersion('0.49.0-rc.1'), '0.49.0（RC 1）');
    expect(formatAppVersion('0.49.0-preview.1'), '0.49.0（Preview 1）');
  });

  test('semantic ordering includes prerelease numbers and stable releases', () {
    final versions = [
      '0.49.0-rc.1',
      '0.49.0-beta.10',
      '0.49.0-beta.2',
      '0.49.0',
      '0.50.0-beta.1'
    ];
    versions.sort((left, right) =>
        AppVersion.parse(left)!.compareTo(AppVersion.parse(right)!));
    expect(versions, [
      '0.49.0-beta.2',
      '0.49.0-beta.10',
      '0.49.0-rc.1',
      '0.49.0',
      '0.50.0-beta.1'
    ]);
    expect(AppVersion.parse('bad-version'), isNull);
  });

  group('GitHub release discovery', () {
    final bytes = [1, 2, 3];
    GithubAppUpdateService service(
      List<Map<String, dynamic>> releases, {
      int build = 4,
      Map<String, dynamic> Function(String version)? manifest,
    }) =>
        GithubAppUpdateService(
            clientFactory: () => MockClient((request) async {
                  if (request.url.host == 'api.github.com') {
                    if (request.url.path.endsWith('/latest')) {
                      final stable = releases
                          .where((item) =>
                              AppVersion.parse(item['tag_name'])
                                  ?.isPrerelease ==
                              false)
                          .toList()
                        ..sort((left, right) =>
                            AppVersion.parse(right['tag_name'])!.compareTo(
                                AppVersion.parse(left['tag_name'])!));
                      return stable.isEmpty
                          ? http.Response('Not Found', 404)
                          : http.Response.bytes(
                              utf8.encode(jsonEncode(stable.first)), 200);
                    }
                    return http.Response.bytes(
                        utf8.encode(jsonEncode(releases)), 200);
                  }
                  final tag = request.url.pathSegments[4].substring(1);
                  return http.Response(
                      jsonEncode(
                          manifest?.call(tag) ?? metadata(tag, build, bytes)),
                      200);
                }));

    test('selects newest Beta by semantic version and checks metadata',
        () async {
      final updater = service([
        releaseData('0.49.0-beta.3', bytes),
        releaseData('0.49.0-beta.10', bytes)
      ]);
      addTearDown(updater.dispose);
      final result = await updater.check(installed());
      expect(result?.version, '0.49.0-beta.10');
      expect(result?.buildNumber, 4);
      expect(result?.sha256, sha256.convert(bytes).toString());
      expect(result?.notes, '改善睡眠记录体验');
    });

    test('stable installs ignore Betas while Betas can graduate to stable',
        () async {
      final updater = service(
          [releaseData('0.50.0-beta.1', bytes), releaseData('0.49.0', bytes)]);
      addTearDown(updater.dispose);
      expect((await updater.check(installed(version: '0.48.0')))?.version,
          '0.49.0');
      final stable = service([releaseData('0.49.0', bytes)]);
      addTearDown(stable.dispose);
      expect((await stable.check(installed()))?.version, '0.49.0');
    });

    test('release automation metadata is hidden from update notes', () async {
      final release = releaseData('0.49.0-beta.3', bytes);
      release['body'] = '${release['body']}\n\n'
          '<!-- night-sleep-release {"version":"0.49.0-beta.3"} -->';
      final updater = service([release]);
      addTearDown(updater.dispose);
      expect((await updater.check(installed()))?.notes, '改善睡眠记录体验');
    });

    test('stable checks use latest endpoint independent of Beta list size',
        () async {
      final requests = <Uri>[];
      final updater = GithubAppUpdateService(
          clientFactory: () => MockClient((request) async {
                requests.add(request.url);
                return http.Response.bytes(
                    utf8.encode(jsonEncode(request.url.host == 'api.github.com'
                        ? releaseData('0.49.0', bytes)
                        : metadata('0.49.0', 4, bytes))),
                    200);
              }));
      addTearDown(updater.dispose);
      expect((await updater.check(installed(version: '0.48.0')))?.version,
          '0.49.0');
      expect(requests.first, GithubAppUpdateService.latestStableUri);
    });

    test('missing first stable release is treated as no available update',
        () async {
      final updater = service([releaseData('0.49.0-beta.3', bytes)]);
      addTearDown(updater.dispose);
      expect(await updater.check(installed(version: '0.48.0')), isNull);
    });

    test('never offers downgrade, same version or nonincreasing build',
        () async {
      for (final version in ['0.48.0', '0.49.0-beta.2', '0.49.0-beta.3']) {
        final updater = service([releaseData(version, bytes)], build: 3);
        addTearDown(updater.dispose);
        expect(await updater.check(installed()), isNull);
      }
    });

    test('rejects drafts, incomplete assets and foreign download URLs',
        () async {
      final draft = releaseData('0.49.0-beta.4', bytes)..['draft'] = true;
      final incomplete = releaseData('0.49.0-beta.5', bytes);
      incomplete['assets'][0]['state'] = 'new';
      final foreign = releaseData('0.49.0-beta.6', bytes);
      foreign['assets'][0]['browser_download_url'] =
          'https://example.com/app.apk';
      final updater = service([draft, incomplete, foreign]);
      addTearDown(updater.dispose);
      expect(await updater.check(installed()), isNull);
    });

    test('rejects mismatched metadata or SHA-256 digest', () async {
      for (final field in [
        'sha256',
        'filename',
        'version',
        'size',
        'signing'
      ]) {
        final updater =
            service([releaseData('0.49.0-beta.3', bytes)], manifest: (version) {
          final value = metadata(version, 4, bytes);
          value[field] = field == 'size' ? 99 : 'incorrect';
          return value;
        });
        addTearDown(updater.dispose);
        await expectLater(
            updater.check(installed()), throwsA(isA<AppUpdateException>()));
      }
    });

    test('API errors remain failures instead of claiming current version',
        () async {
      final updater = GithubAppUpdateService(
          clientFactory: () =>
              MockClient((_) async => http.Response('limited', 403)));
      addTearDown(updater.dispose);
      await expectLater(
          updater.check(installed()), throwsA(isA<AppUpdateException>()));
    });
  });

  group('download integrity and cancellation', () {
    late Directory folder;
    setUp(() async =>
        folder = await Directory.systemTemp.createTemp('night-update-'));
    tearDown(() async => folder.delete(recursive: true));

    test('writes verified APK and reports progress', () async {
      final updater = GithubAppUpdateService(
          directory: folder,
          clientFactory: () =>
              MockClient((_) async => http.Response.bytes([1, 2, 3], 200)));
      addTearDown(updater.dispose);
      final progress = <int>[];
      final file = await updater.download(testRelease, progress.add);
      expect(await file.readAsBytes(), [1, 2, 3]);
      expect(progress.last, 3);
      expect(await File('${folder.path}/updates/update.apk.part').exists(),
          isFalse);
    });

    test('corruption and truncation leave no installable file', () async {
      for (final bytes in [
        [3, 2, 1],
        [1, 2]
      ]) {
        final updater = GithubAppUpdateService(
            directory: folder,
            clientFactory: () =>
                MockClient((_) async => http.Response.bytes(bytes, 200)));
        addTearDown(updater.dispose);
        await expectLater(updater.download(testRelease, (_) {}),
            throwsA(isA<AppUpdateException>()));
        expect(
            await Directory('${folder.path}/updates').list().toList(), isEmpty);
      }
    });

    test('cancel cleans partial APK and permits retry', () async {
      final updater = GithubAppUpdateService(
          directory: folder,
          clientFactory: () =>
              MockClient((_) async => http.Response.bytes([1, 2, 3], 200)));
      addTearDown(updater.dispose);
      await expectLater(
          updater.download(testRelease, (_) => updater.cancelDownload()),
          throwsA(isA<AppUpdateException>()));
      expect(
          await Directory('${folder.path}/updates').list().toList(), isEmpty);
      expect(
          await (await updater.download(testRelease, (_) {})).exists(), isTrue);
    });
  });

  group('manual update state', () {
    late FakeUpdates service;
    late FakeInstaller installer;
    late AppUpdateController controller;
    setUp(() {
      service = FakeUpdates();
      installer = FakeInstaller();
      controller = AppUpdateController(
          service: service,
          installer: installer,
          packageInfo: () async => installed(),
          platform: TargetPlatform.android);
    });
    tearDown(() async {
      controller.dispose();
      if (await service.file.exists()) await service.file.delete();
    });

    test('automatic check runs once and manual check refreshes', () async {
      await controller.check();
      await controller.check();
      expect(service.checks, 1);
      await controller.check(force: true);
      expect(service.checks, 2);
      expect(controller.state.phase, UpdatePhase.available);
    });

    test('permission return and installer cancellation reuse verified download',
        () async {
      installer.allowed = false;
      await controller.check();
      await controller.update();
      expect(controller.state.phase, UpdatePhase.permission);
      installer.allowed = true;
      await controller.update();
      expect(controller.state.phase, UpdatePhase.ready);
      await controller.update();
      expect(service.downloads, 1);
      expect(installer.calls, 3);
    });

    test('download cancellation never invokes installer', () async {
      await controller.check();
      service.pendingDownload = Completer<File>();
      final updating = controller.update();
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.phase, UpdatePhase.downloading);
      service.progress!(2);
      expect(controller.state.received, 2);
      controller.cancel();
      await updating;
      expect(controller.state.phase, UpdatePhase.available);
      expect(installer.calls, 0);
    });

    test('duplicate update taps do not start a second download', () async {
      await controller.check();
      service.pendingDownload = Completer<File>();
      final updating = controller.update();
      await Future<void>.delayed(Duration.zero);
      await controller.update();
      expect(service.downloads, 1);
      controller.cancel();
      await updating;
    });

    test('check errors expose retry instead of latest-version state', () async {
      service.failure = const AppUpdateException('检查失败');
      await controller.check();
      expect(controller.state.phase, UpdatePhase.failed);
      expect(controller.state.message, '检查失败');
      service.failure = null;
      service.available = null;
      await controller.check(force: true);
      expect(controller.state.phase, UpdatePhase.current);
    });

    test('iOS does not request Android releases', () async {
      final ios = AppUpdateController(
          service: service,
          installer: installer,
          packageInfo: () async => installed(),
          platform: TargetPlatform.iOS);
      addTearDown(ios.dispose);
      await ios.check(force: true);
      await ios.update();
      expect(service.checks, 0);
      expect(installer.calls, 0);
    });
  });

  test('Android installation channel carries version and digest', () async {
    MethodCall? recorded;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AndroidAppInstaller.channel, (call) async {
      recorded = call;
      return false;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AndroidAppInstaller.channel, null));
    expect(
        await AndroidAppInstaller()
            .install('/cache/updates/update.apk', testRelease),
        isFalse);
    expect(recorded?.method, 'install');
    expect(recorded?.arguments['buildNumber'], 4);
    expect(recorded?.arguments['sha256'], testRelease.sha256);
  });
}
