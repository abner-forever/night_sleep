import 'package:flutter/material.dart';

/// 会话页（「正在睡眠」）自己的材质与调色板。
///
/// **为什么不吃 `AppTokens`**：新原型的最终生效层把全站换成了扁平原生风
/// （`.glass` 不再模糊/描边/投影、底色改 `#f4f5f8`、主按钮改纯色），而这一轮的范围
/// **只到会话页**——把那些值塞进 `AppTokens` 会连带改掉首页/回顾/统计/设置四页
/// （见规格 §16.7 与偏差 #32）。约定不破：一个概念仍只有一处，只是这一处落在这一页。
///
/// 值逐条取自原型 `index.css` 的 `.sleep-mode` / `.sleep-events` /
/// `.sleep-option-card` / `.sleep-event-*` / `.sleep-hold-button` /
/// `.sleep-navigation-back` / `.sleep-settings-sheet` 等规则，注释里标出原始字面量。
abstract final class NightStyle {
  // ── 卡片 ────────────────────────────────────────────────────────────────
  /// `.sleep-events`（激活态）：`linear-gradient(145deg, .075, .035)`。
  static const eventsFillTop = Color(0x13FFFFFF); // rgba(255,255,255,.075)
  static const eventsFillBottom = Color(0x09FFFFFF); // rgba(255,255,255,.035)
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
  static const iconInk = Color(0xFFAEBDFF);
  static const iconFill = Color(0x1F7E91E9); // rgba(126,145,233,.12)
  /// `.sleep-event-state`（「记录中」「已设置」）。
  static const stateInk = Color(0xFF9FAFEF);

  /// `.sleep-scene-choice.is-selected` 的文字色。
  static const selectedInk = Color(0xFFC4D0FF);

  /// `.sleep-scene-choice.is-selected .sleep-scene-preview` 的描边与外圈。
  static const selectedStroke = Color(0xB8AEBEFF); // rgba(174,190,255,.72)
  static const selectedGlow = Color(0x2E7A8FEB); // rgba(122,143,235,.18)

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
  static const sheetFillTop = Color(0xF7232A44); // rgba(35,42,68,.97)
  static const sheetFillBottom = Color(0xFA0D111F); // rgba(13,17,31,.98)
  static const sheetStroke = Color(0x1FFFFFFF); // rgba(255,255,255,.12)
  static const scrim = Color(0x9402050C); // rgba(2,5,12,.58)
  static const handle = Color(0x33E1E5F4); // rgba(225,229,244,.20)
  /// 弹窗里「音量」「播放时长」两块的内底色：`rgba(255,255,255,.035)`。
  static const fieldFill = Color(0x09FFFFFF);

  // ── 尺寸 ────────────────────────────────────────────────────────────────
  static const cardRadius = 22.0; // .sleep-option-card / .sleep-events
  static const sheetRadius = 30.0; // .sleep-settings-sheet
  static const pickerRadius = 20.0; // 激活态的场景选择器
  static const previewRadius = 13.0; // .sleep-scene-preview
  static const eventIconSize = 34.0; // .sleep-event-icon
  static const eventIconRadius = 12.0;
  static const eventRowMinHeight = 61.0; // .sleep-event-row
  static const holdButtonMinHeight = 56.0;
  static const holdButtonRadius = 18.0;
  static const scenePreviewWidth = 64.0;
  static const scenePreviewHeight = 42.0;

  /// 系统开了「减弱动态效果」没有。对应原型 CSS 里的
  /// `@media (prefers-reduced-motion: reduce)`。
  static bool reduceMotion(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context);
}
