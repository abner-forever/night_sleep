import 'dart:ui' as ui;

import 'package:flutter/material.dart';

abstract final class NightStyle {
  // ── 卡片 ────────────────────────────────────────────────────────────────
  /// Version 19 的深蓝实体事件面板。
  static const eventsFillTop = Color(0xD9102640);
  static const eventsFillBottom = Color(0xD9102640);

  /// `.sleep-option-card`：`1px rgba(255,255,255,.09)` 描边。
  static const cardStroke = Color(0x17FFFFFF); // rgba(255,255,255,.09)
  /// `.sleep-event-row` 的分隔线。
  static const rowDivider = Color(0x11FFFFFF); // rgba(255,255,255,.065)

  // ── 文字 ────────────────────────────────────────────────────────────────
  /// `.sleep-mode` 的前景色。
  static const textPrimary = Color(0xF5F4F7FF); // rgba(244,247,255,.96)
  /// `.sleep-control-copy strong` 一档。
  static const textStrong = Color(0xE6F4F7FF); // rgba(244,247,255,.90)
  /// `.sleep-events-title > span:first-child`。
  static const textHeading = Color(0xC2E1E5F4); // rgba(225,229,244,.76)
  /// `.sleep-event-row small`。
  static const textMuted = Color(0x7AE1E5F4); // rgba(225,229,244,.48)
  /// `.sleep-hold-wrap > p` / `.sleep-elapsed-label`。
  static const textFaint = Color(0x57E1E5F4); // rgba(225,229,244,.34)

  /// `.sleep-live-status`。
  static const statusText = Color(0x9ED6DEFF); // rgba(214,222,255,.62)
  static const statusDot = Color(0xFF8299FF);

  /// `.sleep-time-now`。
  static const clockText = Color(0x94E1E5F4); // rgba(225,229,244,.58)

  // ── 强调 ────────────────────────────────────────────────────────────────
  /// `.sleep-event-icon` 的图标色与底色。
  /// 「录音中」那颗小灯。只在录音服务确实在录时出现。
  static const liveDot = Color(0xFFFF6B6B);

  static const iconInk = Color(0xFFA9CBFF);
  static const iconFill = Color(0x1F7E91E9); // rgba(126,145,233,.12)
  /// `.sleep-event-state`（「记录中」「已设置」）。
  static const stateInk = Color(0xFFA9CBFF);

  /// `.sleep-alarm-time`（可点的起床时刻胶囊）的文字色：`color: #bdc9ff`。
  static const alarmTimeInk = Color(0xFFC9DEFF);

  /// `.sleep-scene-choice.is-selected` 的文字色。
  static const selectedInk = Color(0xFFE9F3FF);

  /// `.sleep-scene-choice.is-selected .sleep-scene-preview` 的描边与外圈。
  static const selectedStroke = Color(0xFF74A5FF);
  static const selectedGlow = Color(0x00000000);

  // ── 场景选择器 ──────────────────────────────────────────────────────────
  /// 激活态场景选择器的外框：`.sleep-active .sleep-scene-picker-compact`
  /// 的 `border: 1px solid rgba(255,255,255,.08)`。
  static const pickerStroke = Color(0x14FFFFFF); // rgba(255,255,255,.08)
  /// 未选中的预览卡描边：`.sleep-scene-preview` 的
  /// `border: 1px solid rgba(255,255,255,.09)`。
  ///
  /// 与 `cardStroke`（`.sleep-option-card`）**同值但不同规则**——原型里这两条
  /// 各写各的，将来谁改了卡片描边不该带着预览卡一起漂，故不合并。
  static const previewStroke = Color(0x17FFFFFF); // rgba(255,255,255,.09)
  /// 预览卡上的光点：`.sleep-scene-preview i` 的
  /// `background: rgba(255,255,255,.75)`。
  static const previewDot = Color(0xBFFFFFFF); // rgba(255,255,255,.75)

  // ── 顶部胶囊与结束按钮 ───────────────────────────────────────────────────
  static const glassStroke = Color(0x1CFFFFFF); // rgba(255,255,255,.11)
  static const glassFill = Color(0x11FFFFFF); // rgba(255,255,255,.065)
  static const glassInk = Color(0xD1E1E8FF); // rgba(225,232,255,.82)
  static const holdInk = Color(0xD1F2F4FC); // rgba(242,244,252,.82)
  /// `.sleep-hold-fill`。
  static const holdFill = Color(0x57707ECA); // rgba(112,126,202,.34)

  // ── 白噪音弹窗 ──────────────────────────────────────────────────────────
  static const sheetFillTop = Color(0xFF11243D);
  static const sheetFillBottom = Color(0xFF11243D);
  static const sheetStroke = Color(0x1FFFFFFF); // rgba(255,255,255,.12)
  static const scrim = Color(0x9402050C); // rgba(2,5,12,.58)
  static const handle = Color(0x33E1E5F4); // rgba(225,229,244,.20)
  /// 弹窗里「音量」「播放时长」两块的内底色：`rgba(255,255,255,.035)`。
  static const fieldFill = Color(0x14183458);

  /// `.sleep-settings-sheet` 的 `box-shadow: 0 -22px 70px rgba(0,0,0,.38)`。
  static const sheetShadow = Color(0x61000000); // rgba(0,0,0,.38)

  /// `.sleep-full-noise-grid button`：未选中格的
  /// `background: rgba(255,255,255,.04)`。
  static const noiseTileIdleFill = Color(0x0AFFFFFF);

  /// `.sleep-full-noise-grid button`：未选中格的
  /// `border: 1px solid rgba(255,255,255,.07)`。
  ///
  /// 与 [sheetFieldStroke]（`.sleep-setting-block`）**同值但不同规则**——原型里这两条
  /// 各写各的，将来谁改了音效格的描边不该带着设置块一起漂。与 [previewStroke] vs
  /// [cardStroke] 是同一个口径。
  static const noiseTileIdleStroke = Color(0x12FFFFFF);

  /// 音效选中态沿用新版蓝色强调底。
  static const noiseTileFill = Color(0xC73478F6);

  /// 同上选中态格的 `border-color: rgba(172,188,255,.34)`（文字色即 [selectedInk]）。
  static const noiseTileStroke = Color(0x57ACBCFF);

  /// `.sleep-setting-block`（「音量」「播放时长」两块外框）的
  /// `border: 1px solid rgba(255,255,255,.07)`。
  ///
  /// 见 [noiseTileIdleStroke] 的说明：同值，但那是另一条规则。
  static const sheetFieldStroke = Color(0x12FFFFFF);

  /// `.sleep-setting-title strong`（「音量 35%」那个读数）的 `color: #b9c6ff`。
  static const fieldValueInk = Color(0xFFB9C6FF);

  // ── 入睡前（setup）态 ───────────────────────────────────────────────────
  //
  // 取自 Version 19 最终生效的照片场景与实体面板规则。
  static const deckFillTop = Color(0xBF102640);
  static const deckFillBottom = Color(0xBF102640);
  static const deckStroke = Color(0x0AB8D6FF);
  static const deckShadow = Color(0x00000000);

  /// `.sleep-mode-kicker`（「睡眠模式」）。
  static const kickerInk = Color(0x80E1E5F4); // rgba(225,229,244,.50)
  /// `.sleep-greeting`（「晚安」）。
  static const greetingInk = Color(0xFFDCEAFF);

  /// `.sleep-setup-hero > p:last-child`（「放下今天…」）。
  static const heroBodyInk = Color(0xFFC4D4EE);

  /// `.sleep-start-note`（「屏幕将保持暗色…」）。
  static const startNoteInk = Color(0x5CE1E5F4); // rgba(225,229,244,.36)

  /// `.sleep-scene-picker-title > span` / `small`。
  static const pickerTitleInk = Color(0xB8E1E5F4); // rgba(225,229,244,.72)
  static const pickerHintInk = Color(0x52E1E5F4); // rgba(225,229,244,.32)

  /// `.sleep-control-label > span`（「常用白噪音」）与右侧「完整设置」。
  static const controlLabelInk = Color(0x7AE1E5F4); // rgba(225,229,244,.48)
  static const controlActionInk = Color(0xFFA9CBFF);

  /// `.sleep-control-copy small`（控制行副标题）。
  static const controlMutedInk = Color(0x6BE1E5F4); // rgba(225,229,244,.42)
  /// `.sleep-control-row` 的分隔线。
  static const controlRowDivider = Color(0x12FFFFFF); // rgba(255,255,255,.07)

  /// `.sleep-quick-sound-list button` 的三态。
  static const quickSoundInk = Color(0x7AE1E5F4); // rgba(225,229,244,.48)
  static const quickSoundFill = Color(0x14183458);
  static const quickSoundStroke = Color(0x0FFFFFFF); // rgba(255,255,255,.06)
  static const quickSoundSelectedInk = Color(0xFFE9F3FF);
  static const quickSoundSelectedFill = Color(0xC73478F6);
  static const quickSoundSelectedStroke =
      Color(0x47ACBCFF); // rgba(172,188,255,.28)

  /// 新版开始按钮采用纯蓝色、无阴影的胶囊。
  static const startGradient = [Color(0xFF4B7DF8), Color(0xFF4B7DF8)];
  static const startInk = Color(0xFFFFFFFF); // color: #fff
  static const startShadow = Color(0x00000000);
  static const startInnerHighlight = Color(0x00000000);

  // ── 尺寸 ────────────────────────────────────────────────────────────────
  static const cardRadius = 22.0; // .sleep-option-card / .sleep-events
  static const sheetRadius = 24.0; // .sleep-settings-sheet
  static const pickerRadius = 20.0; // 激活态的场景选择器
  static const previewRadius = 9.0; // .sleep-scene-preview
  static const eventIconSize = 34.0; // .sleep-event-icon
  static const eventIconRadius = 12.0;
  static const eventRowMinHeight = 61.0; // .sleep-event-row
  /// setup 的控制行图标底板：`.sleep-control-row .sleep-option-icon` 是 35，
  /// 比事件行的 34 大一格——原型里这两条规则各写各的，故不合并。
  static const setupIconSize = 35.0; // .sleep-control-row .sleep-option-icon
  static const deckRadius = 20.0; // .sleep-control-deck
  static const quickSoundMinHeight = 47.0; // .sleep-quick-sound-list button
  static const quickSoundRadius = 14.0;
  static const setupStartMinHeight = 55.0; // .sleep-start-button
  static const setupStartRadius = 27.0;
  static const holdButtonMinHeight = 56.0;
  static const holdButtonRadius = 18.0;
  static const scenePreviewWidth = 53.0;
  static const scenePreviewHeight = 34.0;

  /// 系统开了「减弱动态效果」没有。对应原型 CSS 里的
  /// `@media (prefers-reduced-motion: reduce)`。
  static bool reduceMotion(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context);

  // ── 最终生效层里的两条媒体查询 ──────────────────────────────────────────
  //
  // 它们与上面那些规则同在「Immersive sleep controls」那一层里，同样属于**最终
  // 生效层**（index.css:1937 与 1937 之后那两条），不能因为「是媒体查询」就跳过。
  /// `@media (max-width: 390px)`：deck 的内边距 16 → 13，常用白噪音四格改**竖排**
  /// （`flex-direction: column`，图标在上、标签在下，间距 3）。
  static bool narrowDeck(BuildContext context) =>
      MediaQuery.sizeOf(context).width <= 390;

  /// 两种会话状态共用的滤镜入口；新版面板使用实底，不再叠加毛玻璃。
  static ui.ImageFilter deckFilter() =>
      ui.ImageFilter.blur(sigmaX: 0, sigmaY: 0);

  /// `@media (min-height: 860px)`：入睡前态 hero 从 230 撑到 **285**。
  ///
  /// **2026-10-03 起不再是布尔判断**：原型那条媒体查询量的是浏览器视口，而我们能用的
  /// 高度是**扣掉上下安全区之后**的（874 高的机型只剩 781，却仍满足 `>= 860`，于是白拿
  /// 285，把下面那颗按钮顶出屏幕）。现在只留下这个上限值，由 `session_setup.dart`
  /// 按「上半区剩下的高度」连续取值；下限是 hero 自己的内容高度（三段文案约 210）。
  static const heroTallHeight = 285.0;

  /// deck 里各段的行内边距：常规 16，窄屏 13。
  static const deckGutter = 16.0;
  static const narrowGutter = 13.0;
}
