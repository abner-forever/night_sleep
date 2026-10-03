import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// 应用自己产生的**临时文件**：删掉不丢任何用户数据，下次用到时再生成。
///
/// 具体是两样东西，都在 `getTemporaryDirectory()` 下面（macOS 上就是
/// `~/Library/Caches/<bundle id>`，这一层由 `noise_player.dart` 的注释核实过）：
///
///  * 白噪音的 8 个 WAV 循环，各约 860 KB，首次播放时合成（`noise_player.dart`）；
///  * 导出时写给系统分享面板的那份 CSV / JSON 副本（`export_sharer.dart`）。
///
/// **刻意不含三样东西**，每一样都有自己的去处：
///
///  * 睡眠记录与数据库——那是用户数据，走「删除全部本地数据」；
///  * 录音片段——同上，且按规格只保留最近 7 晚；
///  * 钥匙串里的 API Key——走设置页的「清除密钥」。
///
/// 「清除缓存」这个动作只有一种语义，否则用户点下去时会以为自己的记录没了。
abstract interface class AppCache {
  /// 当前占用字节数。
  Future<int> size();

  /// 全部删掉，返回释放的字节数。
  Future<int> clear();
}

/// 真实实现：把临时目录下的东西全删掉。
///
/// 「全删」而不是按文件名匹配：临时目录存在的前提就是里面的东西都可以丢，
/// 而那两处写入方以后多写一个文件时，按前缀匹配的清单会悄悄漏掉它。
class FileAppCache implements AppCache {
  /// [directory] 只给测试用，用来绕开 `getTemporaryDirectory()`（它要平台通道）。
  /// 生产路径永远是 null，走真实临时目录。
  ///
  /// 有这条缝才测得到真东西：这个功能的意义就是**删对文件、算对大小**，
  /// 拿个假实现去测等于什么都没测。
  FileAppCache({this.directory});

  final Directory? directory;

  Future<Directory> _resolve() async =>
      directory ?? await getTemporaryDirectory();

  @override
  Future<int> size() async {
    final resolved = await _resolve();
    if (!await resolved.exists()) return 0;
    var total = 0;
    await for (final entity
        in resolved.list(recursive: true, followLinks: false)) {
      if (entity is File) total += await _sizeOf(entity);
    }
    return total;
  }

  @override
  Future<int> clear() async {
    final directory = await _resolve();
    if (!await directory.exists()) return 0;

    var freed = 0;
    // 先量后删：删完再统计就只会得到 0，用户就看不到「清掉了多少」。
    await for (final entity in directory.list(followLinks: false)) {
      freed += entity is Directory
          ? await _directorySize(entity)
          : await _sizeOf(entity);
      await _delete(entity);
    }
    return freed;
  }

  Future<int> _directorySize(Directory directory) async {
    var total = 0;
    try {
      await for (final entity
          in directory.list(recursive: true, followLinks: false)) {
        if (entity is File) total += await _sizeOf(entity);
      }
    } on FileSystemException {
      // 读不动就当它不占地方：报错没有意义，用户要的是「清掉」。
    }
    return total;
  }

  Future<int> _sizeOf(FileSystemEntity entity) async {
    try {
      return await entity.stat().then((stat) => stat.size);
    } on FileSystemException {
      return 0;
    }
  }

  Future<void> _delete(FileSystemEntity entity) async {
    try {
      await entity.delete(recursive: true);
    } on FileSystemException {
      // 被占用或已经不在了。与 `noise_player.dart` 的 `clearCache` 同一口径：
      // 这不是值得打断用户的错误——播放中的那个文件本来就删不掉，而它下次
      // 被选中时会重新生成。
    }
  }
}

final appCacheProvider = Provider<AppCache>((ref) => FileAppCache());

/// 人类可读的占用大小。二进制单位（1024），与系统「存储空间」的口径一致。
String formatCacheSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
  return '${(kb / 1024).toStringAsFixed(1)} MB';
}
