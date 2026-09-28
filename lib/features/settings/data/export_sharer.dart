import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../domain/sleep_export.dart';

/// 一次分享的结果。
enum ShareOutcome {
  /// 文件交给了某个分享目标。
  shared,

  /// 用户在面板上什么都没选就关掉了。**不是错误**。
  dismissed,

  /// 文件写不出来，或平台拒绝分享。
  failed,
}

/// 把导出文件交给系统。
///
/// 做成接口而不是直接调用，是为了让 widget 测试能换成假实现：`share_plus` 走平台通道，
/// 而平台通道的 Future 在 widget tester 的 FakeAsync 下**永不完成**——与
/// `await HapticFeedback.*` 会挂死测试是同一个坑。
abstract interface class ExportSharer {
  Future<ShareOutcome> share({
    required List<ExportFile> files,
    required String subject,
  });
}

class SystemExportSharer implements ExportSharer {
  const SystemExportSharer();

  @override
  Future<ShareOutcome> share({
    required List<ExportFile> files,
    required String subject,
  }) async {
    try {
      final directory = Directory(
        path.join((await getTemporaryDirectory()).path, 'export'),
      );
      await directory.create(recursive: true);

      final attachments = <XFile>[];
      for (final file in files) {
        final target = File(path.join(directory.path, file.fileName));
        // 文件名带日期，同一天重复导出覆盖同一路径。不做主动清理：
        // 临时目录由系统回收，自己扫一遍删旧文件既多一份代码，
        // 也多一种「分享面板还开着、文件已被删掉」的边界情况。
        await target.writeAsString(file.content, flush: true);
        // **带上 mimeType**：不传时 `XFile` 的 mimeType 是 `null`，由 share_plus
        // 按扩展名兜底推断。显式传值不依赖那一层推断——类型只由 `SleepExporter`
        // 生成，这里原样透传，不再猜一遍；文件名不带扩展名时也仍然正确。
        attachments.add(XFile(target.path, mimeType: file.mimeType));
      }

      final result = await SharePlus.instance.share(
        ShareParams(files: attachments, subject: subject),
      );

      return switch (result.status) {
        ShareResultStatus.success => ShareOutcome.shared,
        ShareResultStatus.dismissed => ShareOutcome.dismissed,
        _ => ShareOutcome.failed,
      };
    } catch (_) {
      return ShareOutcome.failed;
    }
  }
}

final exportSharerProvider = Provider<ExportSharer>((ref) {
  return const SystemExportSharer();
});
