import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sleep/core/theme/app_tokens.dart';

/// `colorMix` 对应 CSS 的 `color-mix(in srgb, a p%, b)`。
///
/// 这一组的存在理由是 2026-10-16 真机上抓到的一个 bug：**`Color.alphaBlend`
/// 不是它的替身**。原型里带 `accent-soft` 的几处底纹被照 `alphaBlend` 写成了
/// 「把 accent-soft 当成不透明色盖上去」，混出来的是一块饱和天蓝，而不是设计里
/// 那层几乎看不见的雾。两者的差别只在**第一个颜色是否不透明**——而
/// `--accent-soft` 恰恰自带 α（浅色 .12 / 深色 .20），于是每处带它的底纹都浓了约 8 倍。
void main() {
  const soft = Color(0x1F007AFF); // 浅色 accent-soft：α = 31/255 ≈ .12
  const base = Color(0xDBFAFAFC); // 浅色 material-strong：α = 219/255 ≈ .86

  test('p = 1 得到 a，p = 0 得到 b', () {
    expect(colorMix(soft, 1, base).toARGB32(), soft.toARGB32());
    expect(colorMix(soft, 0, base).toARGB32(), base.toARGB32());
  });

  test('color-mix(X p%, transparent) 是**把 alpha 乘上 p**，不是把 alpha 设成 p', () {
    final mixed = colorMix(soft, 0.30, Colors.transparent);
    expect(mixed.a, closeTo(soft.a * 0.30, 1e-9));
    // 色相不变，只是更淡。
    expect(mixed.r, closeTo(soft.r, 1e-9));
    expect(mixed.b, closeTo(soft.b, 1e-9));
  });

  test('accent-soft 混 material-strong：得到的是一层淡蓝白', () {
    final mixed = colorMix(soft, 0.42, base);
    // 手算：α = .42×.12 + .58×.86 ≈ .549，rgb ≈ (227, 238, 252)。
    expect(mixed.a, closeTo(0.549, 0.005));
    expect(mixed.r, closeTo(227 / 255, 0.01));
    expect(mixed.g, closeTo(238 / 255, 0.01));
    expect(mixed.b, closeTo(252 / 255, 0.01));
  });

  test('用 alphaBlend 顶替会明显更蓝更实——这就是当初在真机上看到的那一块', () {
    final right = colorMix(soft, 0.42, base);
    final wrong = Color.alphaBlend(soft.withValues(alpha: 0.42), base);

    // 红通道：淡蓝白 ≈ .89，饱和蓝 ≈ .53。
    expect(wrong.r, lessThan(right.r - 0.3), reason: '替身版本明显更蓝');
    expect(wrong.a, greaterThan(right.a + 0.3), reason: '替身版本明显更实');
  });

  test('第一个颜色不透明时，两者才等价（prototype 的描边就是这种）', () {
    const opaque = Color(0xFF007AFF);
    expect(
      colorMix(opaque, 0.12, base).toARGB32(),
      Color.alphaBlend(opaque.withValues(alpha: 0.12), base).toARGB32(),
    );
  });

  test('权重超出 0–1 会被夹住，不会算出越界的通道值', () {
    for (final p in [-1.0, 2.0]) {
      final mixed = colorMix(soft, p, base);
      expect(mixed.a, inInclusiveRange(0, 1));
      expect(mixed.r, inInclusiveRange(0, 1));
      expect(mixed.g, inInclusiveRange(0, 1));
      expect(mixed.b, inInclusiveRange(0, 1));
    }
  });
}
