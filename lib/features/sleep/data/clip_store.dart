import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// 录音片段在磁盘上的家。
///
/// **目录选 `getApplicationSupportDirectory()`，两个更显眼的选项都是坑**：
/// `getTemporaryDirectory()` 是「清除缓存」的地盘（偏差 #43 明写它只删可再生成的
/// 临时文件），录音放进去会被用户一次「清除缓存」清掉；`getApplicationDocumentsDirectory()`
/// 在 iOS 上会进「文件」App 并被 iCloud 备份，一段段卧室录音没有理由出现在那里。
///
/// 基目录可注入，单元测试不必碰 `path_provider` 的平台通道。
class ClipFileStore {
  ClipFileStore({required Future<Directory> Function() baseDirectory})
      : _baseDirectory = baseDirectory;

  /// 交给 `path_provider` 的版本，应用里用这个。
  factory ClipFileStore.platform() =>
      ClipFileStore(baseDirectory: getApplicationSupportDirectory);

  final Future<Directory> Function() _baseDirectory;

  Directory? _cached;

  Future<Directory> _directory() async {
    final cached = _cached;
    if (cached != null) return cached;
    final base = await _baseDirectory();
    final dir = Directory(path.join(base.path, 'clips'));
    if (!dir.existsSync()) await dir.create(recursive: true);
    return _cached = dir;
  }

  /// 一个片段文件的完整路径。`clipId` 由片段起始时刻生成，天然有序。
  Future<String> pathFor(String clipId) async {
    final dir = await _directory();
    return path.join(dir.path, '$clipId.wav');
  }

  /// 删掉一条片段的文件。文件已经不在（被裁过、或从来没写成功）时**不算失败**。
  Future<void> deleteClip(String? localUri) async {
    if (localUri == null) return;
    final file = File(localUri);
    if (file.existsSync()) {
      try {
        await file.delete();
      } on FileSystemException {
        // 删不掉就留着：这是个清理动作，不该把调用方的流程打断。
      }
    }
  }

  /// 目录里**全部**录音文件的大小之和（含还没入库的）。
  ///
  /// 这是设置页那个占用读数要的数。读不到就抛出去，让界面如实说「读不到」——
  /// 显示一个编出来的 `0 B` 比不显示更坏（偏差 #43 同一条规则）。
  Future<int> totalBytes() async {
    final dir = await _directory();
    var total = 0;
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is File) {
        total += await entity.length();
      }
    }
    return total;
  }

  /// 删掉全部片段文件。
  Future<void> deleteAll() async {
    final dir = await _directory();
    if (!dir.existsSync()) return;
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is File) {
        try {
          await entity.delete();
        } on FileSystemException {
          // 同上：清理动作不因为一个删不掉的文件整个失败。
        }
      }
    }
  }

  /// 启动时的孤儿清理：文件名不在 [knownIds] 里、也不在 [pendingIds] 里的一律删掉。
  ///
  /// 库（以及会话行里的片段清单）是唯一真相来源。被杀之后重启、用户又把那次会话
  /// 丢弃了，那些已经落盘但永远不会入库的文件就走这条路。
  Future<void> deleteOrphans({
    required Set<String> knownIds,
    Set<String> pendingIds = const {},
  }) async {
    final dir = await _directory();
    if (!dir.existsSync()) return;
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final id = path.basenameWithoutExtension(entity.path);
      if (knownIds.contains(id) || pendingIds.contains(id)) continue;
      try {
        await entity.delete();
      } on FileSystemException {
        // 同上。
      }
    }
  }
}

final clipFileStoreProvider = Provider<ClipFileStore>((ref) {
  return ClipFileStore.platform();
});
