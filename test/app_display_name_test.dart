import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 显示名是纯配置，没有 widget 能断言它。
///
/// 用纯 `test()` 直接读文件：这几份文件就是构建产物里那几个键的**唯一**来源，
/// 读它们与读 `flutter build` 出来的包等价，但不需要构建。
void main() {
  group('应用显示名', () {
    test('iOS 桌面显示「夜深」', () {
      final plist = File('ios/Runner/Info.plist').readAsStringSync();
      expect(
        plist,
        contains('<key>CFBundleDisplayName</key>\n\t<string>夜深</string>'),
      );
    });

    test('macOS 补上 CFBundleDisplayName', () {
      final plist = File('macos/Runner/Info.plist').readAsStringSync();
      expect(
        plist,
        contains('<key>CFBundleDisplayName</key>\n\t<string>夜深</string>'),
      );
    });

    test('web 的 title 与 apple 标题都是「夜深」', () {
      final html = File('web/index.html').readAsStringSync();
      expect(html, contains('<title>夜深</title>'));
      expect(
        html,
        contains('<meta name="apple-mobile-web-app-title" content="夜深">'),
      );
    });

    test('web manifest 的 name 与 short_name 都是「夜深」', () {
      final manifest = jsonDecode(File('web/manifest.json').readAsStringSync())
          as Map<String, dynamic>;
      expect(manifest['name'], '夜深');
      expect(manifest['short_name'], '夜深');
    });

    /// 反向护栏：这三处**必须**保持英文。
    ///
    /// `PRODUCT_NAME` 决定 macOS 的 `.app` 包名与可执行文件名，改成中文会让构建
    /// 产物路径变成中文，并顺着 `EXECUTABLE_NAME` 影响一串构建设置；`CFBundleName`
    /// 是对内的短名（15 字节上限）。改错了不会有任何功能报错，只会在构建时炸，
    /// 所以在这里钉住。
    test('构建路径相关的名字仍是 night_sleep', () {
      expect(
        File('macos/Runner/Configs/AppInfo.xcconfig').readAsStringSync(),
        contains('PRODUCT_NAME = night_sleep'),
      );
      expect(
        File('ios/Runner/Info.plist').readAsStringSync(),
        contains('<key>CFBundleName</key>\n\t<string>night_sleep</string>'),
      );
    });
  });
}
