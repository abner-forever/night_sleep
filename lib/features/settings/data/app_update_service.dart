import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../domain/app_release.dart';

class AppUpdateException implements Exception {
  const AppUpdateException(this.message);

  final String message;
}

abstract interface class AppUpdateService {
  Future<AppRelease?> check(PackageInfo installed);
  Future<File> download(
      AppRelease release, void Function(int bytes) onProgress);
  void cancelDownload();
  void dispose();
}

class GithubAppUpdateService implements AppUpdateService {
  GithubAppUpdateService(
      {http.Client Function()? clientFactory, this.directory})
      : _clientFactory = clientFactory ?? http.Client.new;

  static const repository = 'abner-forever/night_sleep';
  static final releasesUri = Uri.https(
    'api.github.com',
    '/repos/$repository/releases',
    {'per_page': '100'},
  );
  static final latestStableUri =
      Uri.https('api.github.com', '/repos/$repository/releases/latest');
  final http.Client Function() _clientFactory;
  final Directory? directory;
  http.Client? _downloadClient;
  bool _cancelled = false;

  Uri? _assetUrl(Map<String, dynamic> release, String name) {
    final assets = release['assets'];
    if (assets is! List) return null;
    for (final asset in assets.whereType<Map<String, dynamic>>()) {
      if (asset['name'] != name ||
          asset['state'] != 'uploaded' ||
          asset['size'] is! int ||
          (asset['size'] as int) <= 0) {
        continue;
      }
      final url = Uri.tryParse(asset['browser_download_url']?.toString() ?? '');
      if (url != null &&
          url.scheme == 'https' &&
          url.host == 'github.com' &&
          url.port == 443 &&
          url.userInfo.isEmpty &&
          !url.hasQuery &&
          !url.hasFragment &&
          Uri.decodeComponent(url.path) ==
              '/$repository/releases/download/${release['tag_name']}/$name') {
        return url;
      }
    }
    return null;
  }

  Future<dynamic> _json(http.Client client, Uri url,
      {bool allowNotFound = false}) async {
    final response = await client.get(url, headers: {
      'Accept': url.host == 'api.github.com'
          ? 'application/vnd.github+json'
          : 'application/json',
    }).timeout(const Duration(seconds: 15));
    if (allowNotFound && response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw const AppUpdateException('暂时无法获取版本信息，请稍后重试。');
    }
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  @override
  Future<AppRelease?> check(PackageInfo installed) async {
    final current = AppVersion.parse(installed.version);
    final currentBuild = int.tryParse(installed.buildNumber);
    if (current == null || currentBuild == null) {
      throw const AppUpdateException('无法识别当前版本，请稍后重试。');
    }
    final client = _clientFactory();
    try {
      final payload = await _json(
          client, current.isPrerelease ? releasesUri : latestStableUri,
          allowNotFound: !current.isPrerelease);
      final response = current.isPrerelease
          ? payload
          : payload == null
              ? []
              : [payload];
      if (response is! List) {
        throw const AppUpdateException('版本信息不完整，请稍后重试。');
      }
      final candidates = response
          .whereType<Map<String, dynamic>>()
          .where((item) {
        final version = AppVersion.parse(item['tag_name']?.toString() ?? '');
        if (item['draft'] != false ||
            version == null ||
            DateTime.tryParse(item['published_at']?.toString() ?? '') == null ||
            (!current.isPrerelease && version.isPrerelease) ||
            version.compareTo(current) <= 0) {
          return false;
        }
        final name =
            item['tag_name'].toString().replaceFirst(RegExp(r'^v'), '');
        return _assetUrl(item, 'night-sleep-$name-android.apk') != null &&
            _assetUrl(item, 'release.json') != null;
      }).toList()
        ..sort((left, right) => AppVersion.parse(right['tag_name'])!
            .compareTo(AppVersion.parse(left['tag_name'])!));
      if (candidates.isEmpty) return null;
      final selected = candidates.first;
      final version =
          selected['tag_name'].toString().replaceFirst(RegExp(r'^v'), '');
      final filename = 'night-sleep-$version-android.apk';
      final asset = (selected['assets'] as List)
          .whereType<Map<String, dynamic>>()
          .firstWhere((item) => item['name'] == filename);
      final metadata =
          await _json(client, _assetUrl(selected, 'release.json')!);
      if (metadata is! Map<String, dynamic> ||
          metadata['version'] != version ||
          metadata['tag'] != selected['tag_name'] ||
          metadata['filename'] != filename ||
          metadata['signing'] != 'release' ||
          metadata['build_number'] is! int ||
          metadata['build_number'] <= 0 ||
          metadata['size'] != asset['size'] ||
          metadata['sha256'] is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(metadata['sha256']) ||
          asset['digest'] != 'sha256:${metadata['sha256']}') {
        throw const AppUpdateException('安装包信息校验失败，请稍后重试。');
      }
      if (metadata['build_number'] <= currentBuild) return null;
      return AppRelease(
        version: version,
        buildNumber: metadata['build_number'],
        url: _assetUrl(selected, filename)!,
        sha256: metadata['sha256'],
        size: metadata['size'],
        notes: selected['body'] is String
            ? (selected['body'] as String)
                .replaceAll(RegExp(r'<!-- night-sleep-release .*? -->'), '')
                .trim()
            : '',
      );
    } finally {
      client.close();
    }
  }

  @override
  Future<File> download(
      AppRelease release, void Function(int bytes) onProgress) async {
    if (_downloadClient != null) {
      throw const AppUpdateException('已有下载正在进行。');
    }
    _cancelled = false;
    final client = _clientFactory();
    _downloadClient = client;
    File? partial;
    IOSink? sink;
    try {
      final root = directory ?? await getTemporaryDirectory();
      final folder = Directory(path.join(root.path, 'updates'));
      await folder.create(recursive: true);
      await for (final entity in folder.list()) {
        if (entity is File) await entity.delete();
      }
      partial = File(path.join(folder.path, 'update.apk.part'));
      final response = await client
          .send(http.Request('GET', release.url))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200 ||
          (response.contentLength != null &&
              response.contentLength != release.size)) {
        throw const AppUpdateException('安装包下载失败，请重试。');
      }
      sink = partial.openWrite();
      var received = 0;
      await for (final chunk
          in response.stream.timeout(const Duration(seconds: 30))) {
        if (_cancelled) throw const AppUpdateException('下载已取消。');
        received += chunk.length;
        if (received > release.size) {
          throw const AppUpdateException('安装包大小不符，请重新下载。');
        }
        sink.add(chunk);
        await sink.flush();
        onProgress(received);
      }
      await sink.close();
      sink = null;
      if (_cancelled) throw const AppUpdateException('下载已取消。');
      final digest = await crypto.sha256.bind(partial.openRead()).first;
      if (_cancelled) throw const AppUpdateException('下载已取消。');
      if (received != release.size || digest.toString() != release.sha256) {
        throw const AppUpdateException('安装包校验失败，请重新下载。');
      }
      return await partial.rename(path.join(folder.path, 'update.apk'));
    } finally {
      try {
        await sink?.close();
      } finally {
        client.close();
        _downloadClient = null;
        if (partial != null && await partial.exists()) await partial.delete();
      }
    }
  }

  @override
  void cancelDownload() {
    _cancelled = true;
    _downloadClient?.close();
  }

  @override
  void dispose() => cancelDownload();
}
