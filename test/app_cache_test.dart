import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/features/settings/data/app_cache.dart';
import 'package:path/path.dart' as p;

/// 「清除缓存」这条动作的边界。
///
/// 用真实文件系统跑真实实现（只把目录换成测试自己建的临时目录）：这个功能的全部
/// 意义就是**删对文件、算对大小**，塞一个假实现进来等于什么都没测。
void main() {
  late Directory root;
  late FileAppCache cache;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('cache-test');
    cache = FileAppCache(directory: root);
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  Future<void> writeFile(String relative, int bytes) async {
    final file = File(p.join(root.path, relative));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(List<int>.filled(bytes, 0));
  }

  test('占用统计递归进子目录，不只是顶层', () async {
    await writeFile('export-sleep.csv', 2048);
    await writeFile('export/night.csv', 1024);
    await writeFile('export/night.json', 512);

    expect(await cache.size(), 2048 + 1024 + 512);
  });

  test('空目录算 0，不炸', () async {
    expect(await cache.size(), 0);
  });

  test('清除把文件与子目录一起删掉，并报出释放的字节数', () async {
    await writeFile('export-sleep.csv', 2048);
    await writeFile('export/night.csv', 1024);

    final freed = await cache.clear();

    expect(freed, 3072, reason: '先量后删，用户才看得到清掉了多少');
    expect(root.listSync(), isEmpty, reason: '子目录也要带走');
    expect(await cache.size(), 0);
  });

  test('清两次不会第二次报出一个假的数字', () async {
    await writeFile('export-sleep.csv', 2048);
    expect(await cache.clear(), 2048);
    expect(await cache.clear(), 0);
  });

  test('目录不存在时读作 0、清除是空操作', () async {
    final missing = Directory(p.join(root.path, 'never-created'));
    final other = FileAppCache(directory: missing);

    expect(await other.size(), 0);
    expect(await other.clear(), 0);
  });

  test('留着不认识的目录也不怕——临时目录里的一切本来就可以丢', () async {
    // 写入方以后多写一种文件时，「按名字匹配」的清单会漏掉它；全删不会。
    await writeFile('something-new.bin', 100);
    await writeFile('nested/deep/thing.tmp', 50);

    expect(await cache.clear(), 150);
    expect(root.listSync(), isEmpty);
  });

  group('formatCacheSize', () {
    test('按二进制单位分档，与系统「存储空间」口径一致', () {
      expect(formatCacheSize(0), '0 B');
      expect(formatCacheSize(512), '512 B');
      expect(formatCacheSize(2048), '2.0 KB');
      expect(formatCacheSize(1024 * 1024 * 7 + 400000), '7.4 MB');
    });
  });
}
