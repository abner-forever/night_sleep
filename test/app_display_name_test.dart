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

    test('iOS 对内短名仍是 night_sleep', () {
      expect(
        File('ios/Runner/Info.plist').readAsStringSync(),
        contains('<key>CFBundleName</key>\n\t<string>night_sleep</string>'),
      );
    });
  });
}
