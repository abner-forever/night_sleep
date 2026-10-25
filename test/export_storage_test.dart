import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/features/settings/data/export_storage.dart';
import 'package:night_sleep/features/settings/domain/sleep_export.dart';

/// 导出目录层的回归测试。
///
/// 这里驱动的是真实 `SystemExportStorage`，只把平台通道换成一个可观察的假实现。
/// 它因此能覆盖目录读取、自动保存、默认导入和部分失败，而不进入真实文件选择器。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(SystemExportStorage.channelName);
  late Directory temporary;
  late List<MethodCall> calls;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('export-saver-test-');
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'location' || 'resetLocation' => {
            'label': '下载/夜深',
            'custom': false,
            'canChoose': true,
          },
        'chooseLocation' => {
            'label': '自选文件夹：备份',
            'custom': true,
            'canChoose': true,
          },
        'save' => {
            'savedCount': (call.arguments as Map)['files'].length,
            'fileCount': (call.arguments as Map)['files'].length,
            'failed': false,
          },
        'latestBackup' => '/cache/latest.zip',
        _ => throw PlatformException(code: 'unexpected_method'),
      };
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  SystemExportStorage storage() => SystemExportStorage(
        channel: channel,
        temporaryDirectory: () async => temporary,
      );

  test('读取默认目录与自定义目录信息', () async {
    final defaultLocation = await storage().location();
    expect(defaultLocation.label, '下载/夜深');
    expect(defaultLocation.custom, isFalse);
    expect(defaultLocation.canChoose, isTrue);

    final custom = await storage().chooseLocation();
    expect(custom!.label, '自选文件夹：备份');
    expect(custom.custom, isTrue);

    final reset = await storage().resetLocation();
    expect(reset.custom, isFalse);
    expect(calls.map((call) => call.method), [
      'location',
      'chooseLocation',
      'resetLocation',
    ]);
  });

  test('内容文件先落到缓存，再整批交给当前目录', () async {
    final result = await storage().save([
      const ExportFile(
        fileName: '夜深-睡眠数据-20261025.json',
        content: '{"format":"night-sleep-export"}',
        mimeType: SleepExporter.jsonMime,
      ),
    ]);

    expect(result.complete, isTrue);
    expect(result.savedCount, 1);
    expect(calls.single.method, 'save');

    final arguments = Map<String, Object?>.from(
      calls.single.arguments as Map,
    );
    final files = (arguments['files']! as List).cast<Map>();
    expect(files.single['fileName'], '夜深-睡眠数据-20261025.json');
    expect(files.single['mimeType'], SleepExporter.jsonMime);
    final source = File(files.single['path']! as String);
    expect(source.path, startsWith(temporary.path));
    expect(
      await source.readAsString(),
      '{"format":"night-sleep-export"}',
    );
  });

  test('原生返回部分失败时保留已保存数量', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return {
        'savedCount': 1,
        'fileCount': 2,
        'failed': true,
      };
    });

    final result = await storage().save(const [
      ExportFile(
        fileName: '记录.csv',
        content: '记录',
        mimeType: SleepExporter.csvMime,
      ),
      ExportFile(
        fileName: '阶段.csv',
        content: '阶段',
        mimeType: SleepExporter.csvMime,
      ),
    ]);

    expect(calls, hasLength(1));
    expect(result.savedCount, 1);
    expect(result.fileCount, 2);
    expect(result.failed, isTrue);
  });

  test('平台写入失败时保留已保存数量并标记失败', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      throw PlatformException(code: 'save_failed');
    });

    final result = await storage().save(const [
      ExportFile(
        fileName: '记录.csv',
        content: '记录',
        mimeType: SleepExporter.csvMime,
      ),
      ExportFile(
        fileName: '阶段.csv',
        content: '阶段',
        mimeType: SleepExporter.csvMime,
      ),
    ]);

    expect(result.savedCount, 0);
    expect(result.fileCount, 2);
    expect(result.failed, isTrue);
  });

  test('从默认目录读取最新备份路径', () async {
    final path = await storage().latestBackupPath();
    expect(path, '/cache/latest.zip');
    expect(calls.single.method, 'latestBackup');
  });
}
