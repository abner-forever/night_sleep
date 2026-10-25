import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../domain/sleep_export.dart';

/// 当前导出与默认导入共用的目录。
class ExportLocation {
  const ExportLocation({
    required this.label,
    required this.custom,
    required this.canChoose,
  });

  final String label;
  final bool custom;

  /// 当前平台是否支持持久保存用户选择的目录。
  ///
  /// Android 通过 Storage Access Framework 支持；iOS 继续使用应用自己的
  /// Documents 目录，不显示一个点了也不会生效的“更换位置”入口。
  final bool canChoose;
}

/// 一次导出保存的结果。
///
/// CSV 是两个独立文件，第二个文件可能写入失败，因此这里保留 [savedCount]，
/// 界面才能如实说明「已保存一个、另一个没有保存」。
class ExportSaveResult {
  const ExportSaveResult({
    required this.savedCount,
    required this.fileCount,
    this.failed = false,
  })  : assert(savedCount >= 0),
        assert(fileCount >= savedCount);

  final int savedCount;
  final int fileCount;
  final bool failed;

  bool get complete => savedCount == fileCount;
}

/// 把导出文件写进当前目录，并从同一目录读取默认备份。
///
/// 做成接口是为了 Widget 测试不进入平台文件选择器。目录 URI 的持久授权与
/// 实际文件 I/O 留在原生层，Dart 只负责生成导出内容和识别结果。
abstract interface class ExportStorage {
  Future<ExportLocation> location();

  /// 返回 `null` 表示用户在目录选择器中取消。
  Future<ExportLocation?> chooseLocation();

  Future<ExportLocation> resetLocation();

  Future<ExportSaveResult> save(List<ExportFile> files);

  /// 没有可用备份时返回 `null`。
  Future<String?> latestBackupPath();
}

class SystemExportStorage implements ExportStorage {
  SystemExportStorage({
    MethodChannel? channel,
    Future<Directory> Function()? temporaryDirectory,
  })  : _channel = channel ?? const MethodChannel(channelName),
        _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory;

  static const channelName = 'night_sleep/export_storage';

  final MethodChannel _channel;
  final Future<Directory> Function() _temporaryDirectory;

  @override
  Future<ExportLocation> location() async {
    final value = await _channel.invokeMapMethod<String, Object?>('location');
    return _locationFrom(value);
  }

  @override
  Future<ExportLocation?> chooseLocation() async {
    final value =
        await _channel.invokeMapMethod<String, Object?>('chooseLocation');
    return value == null ? null : _locationFrom(value);
  }

  @override
  Future<ExportLocation> resetLocation() async {
    final value =
        await _channel.invokeMapMethod<String, Object?>('resetLocation');
    return _locationFrom(value);
  }

  @override
  Future<ExportSaveResult> save(List<ExportFile> files) async {
    try {
      final directory = Directory(
        path.join((await _temporaryDirectory()).path, 'export'),
      );
      await directory.create(recursive: true);

      final arguments = <Map<String, String>>[];
      for (final file in files) {
        final source = await _materialize(file, directory);
        arguments.add({
          'path': source.path,
          'fileName': file.fileName,
          'mimeType': file.mimeType,
        });
      }
      final result = await _channel.invokeMapMethod<String, Object?>(
        'save',
        {'files': arguments},
      );
      if (result == null) throw const FormatException('保存结果缺失');
      return ExportSaveResult(
        savedCount: (result['savedCount'] as num?)?.toInt() ?? 0,
        fileCount: (result['fileCount'] as num?)?.toInt() ?? files.length,
        failed: result['failed'] == true,
      );
    } catch (_) {
      return ExportSaveResult(
        savedCount: 0,
        fileCount: files.length,
        failed: true,
      );
    }
  }

  @override
  Future<String?> latestBackupPath() async {
    final value = await _channel.invokeMethod<String>('latestBackup');
    return value == null || value.isEmpty ? null : value;
  }

  ExportLocation _locationFrom(Map<String, Object?>? value) {
    if (value == null) throw const FormatException('导出位置缺失');
    final label = value['label'] as String?;
    if (label == null || label.isEmpty) {
      throw const FormatException('导出位置缺失');
    }
    return ExportLocation(
      label: label,
      custom: value['custom'] == true,
      canChoose: value['canChoose'] == true,
    );
  }

  Future<File> _materialize(ExportFile file, Directory directory) async {
    if (file.localPath != null) return File(file.localPath!);
    final target =
        File(path.join(directory.path, path.basename(file.fileName)));
    // 文件名带日期，同一天重复导出覆盖同一路径。临时目录由系统回收，不在
    // 这里主动删除：原生目录写入可能仍在读取刚生成的文件。
    await target.writeAsString(file.content, flush: true);
    return target;
  }
}

final exportStorageProvider = Provider<ExportStorage>((ref) {
  return SystemExportStorage();
});
