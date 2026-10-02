import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 会话页的夜景氛围。id 与中文标签逐字取自原型的 `SLEEP_SCENES`。
enum NightScene {
  meteor('meteor', '流星夜'),
  aurora('aurora', '极光'),
  ocean('ocean', '深海'),
  moon('moon', '月海'),
  cloud('cloud', '云上'),
  firefly('firefly', '萤火'),
  galaxy('galaxy', '银河'),
  rain('rain', '雨夜');

  const NightScene(this.id, this.label);

  final String id;
  final String label;

  /// 原型 `useState<SleepScene>('meteor')` 的初值。
  static const fallback = NightScene.meteor;

  /// 按 id 解析。**读不到认识的 id 时回落默认**——与 `noiseId` 同一条既有做法：
  /// 一行坏数据不该让整个会话读不出来。
  static NightScene fromId(String? id) {
    for (final scene in values) {
      if (scene.id == id) return scene;
    }
    return fallback;
  }

  /// 整页底色，逐字取自 `.sleep-scene-*`。
  Gradient get background => switch (this) {
        NightScene.meteor => _css(
            165, [const Color(0xFF11162A), const Color(0xFF080B16)], [0, .72]),
        NightScene.aurora => _css(165, [
            const Color(0xFF071D29),
            const Color(0xFF0A1224),
            const Color(0xFF090C18)
          ], [
            0,
            .58,
            1
          ]),
        NightScene.ocean => _css(180, [
            const Color(0xFF071827),
            const Color(0xFF06111C),
            const Color(0xFF030810)
          ], [
            0,
            .55,
            1
          ]),
        NightScene.moon => _css(160, [
            const Color(0xFF17182D),
            const Color(0xFF0D1020),
            const Color(0xFF080A13)
          ], [
            0,
            .60,
            1
          ]),
        NightScene.cloud => _css(165, [
            const Color(0xFF20283C),
            const Color(0xFF111827),
            const Color(0xFF0B101C)
          ], [
            0,
            .60,
            1
          ]),
        NightScene.firefly => _css(165, [
            const Color(0xFF0E211D),
            const Color(0xFF071510),
            const Color(0xFF050B09)
          ], [
            0,
            .60,
            1
          ]),
        NightScene.galaxy => _css(155, [
            const Color(0xFF1C1236),
            const Color(0xFF0D1028),
            const Color(0xFF070916)
          ], [
            0,
            .55,
            1
          ]),
        NightScene.rain => _css(165, [
            const Color(0xFF17212C),
            const Color(0xFF0B121C),
            const Color(0xFF070B11)
          ], [
            0,
            .58,
            1
          ]),
      };

  /// 预览小卡的底色，逐字取自 `.sleep-scene-preview-*`。
  ///
  /// 雨夜那条原型用的是 `repeating-linear-gradient` 画斜纹，Flutter 的渐变不能重复，
  /// 这里用一串交替的 `stops` 近似出同样的斜纹观感（64×42 的缩略图上看不出差别）。
  Gradient get previewGradient => switch (this) {
        NightScene.meteor => const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1B2340), Color(0xFF11162A)]),
        NightScene.aurora => _css(145, [
            const Color(0xFF0B3A3A),
            const Color(0xFF172850),
            const Color(0xFF09111F)
          ], [
            0,
            .56,
            1
          ]),
        NightScene.ocean => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0B3047), Color(0xFF06101B)]),
        NightScene.moon =>
          _css(145, [const Color(0xFF262844), const Color(0xFF0C1020)]),
        NightScene.cloud =>
          _css(145, [const Color(0xFF465269), const Color(0xFF151E2D)]),
        NightScene.firefly => const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0C2A20), Color(0xFF092018)]),
        NightScene.galaxy => _css(145, [
            const Color(0xFF3A205D),
            const Color(0xFF101839),
            const Color(0xFF090D1B)
          ], [
            0,
            .55,
            1
          ]),
        NightScene.rain => _css(105, const [
            Color(0x00000000),
            Color(0x00000000),
            Color(0x24BED5EB),
            Color(0x24BED5EB),
            Color(0x00000000),
            Color(0x00000000),
            Color(0x24BED5EB),
            Color(0x24BED5EB),
            Color(0x00000000),
            Color(0x00000000),
            Color(0x24BED5EB),
            Color(0x24BED5EB),
            Color(0x00000000),
            Color(0x00000000),
          ], const [
            0,
            .14,
            .15,
            .28,
            .29,
            .43,
            .44,
            .57,
            .58,
            .72,
            .73,
            .86,
            .87,
            1,
          ]),
      };

  /// 预览卡上那几个光点。流星夜 / 极光 / 深海 / 云上 / 银河 用三颗默认星，
  /// 月海与萤火各有自己的点，雨夜没有。
  List<Alignment> get previewDots => switch (this) {
        NightScene.rain => const [],
        NightScene.moon => const [Alignment(0.44, -0.4)],
        NightScene.firefly => const [
            Alignment(-0.5, 0.2),
            Alignment(0.44, -0.3),
          ],
        _ => const [
            Alignment(-0.72, -0.52),
            Alignment(-0.28, 0.38),
            Alignment(0.56, -0.14),
          ],
      };

  /// CSS 的 `linear-gradient(<deg>, …)` 用「0° 朝上、顺时针」；这里换算成 Flutter
  /// 的两个 `Alignment`。非正方形容器上角度会有轻微偏差（Flutter 按盒子比例归一化
  /// 控点），对这八条差不到 10° 的暗色渐变来说看不出来。
  static LinearGradient _css(
    double deg,
    List<Color> colors, [
    List<double>? stops,
  ]) {
    final rad = deg * math.pi / 180;
    final dx = math.sin(rad);
    final dy = -math.cos(rad);
    return LinearGradient(
      begin: Alignment(-dx, -dy),
      end: Alignment(dx, dy),
      colors: colors,
      stops: stops,
    );
  }
}
