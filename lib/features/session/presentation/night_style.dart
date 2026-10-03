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

  /// `.sleep-alarm-time`（可点的起床时刻胶囊）的文字色：`color: #bdc9ff`。
  static const alarmTimeInk = Color(0xFFBDC9FF);

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

  /// `.sleep-full-noise-grid button.is-selected` 的
  /// `background: rgba(126,145,233,.16)`。
  static const noiseTileFill = Color(0x297E91E9);

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
  // 值取自原型最终生效层那段 `/* ── Immersive sleep controls ── */`
  // （index.css:1730–1960），它覆盖了前面第 1557 行起的同名规则。
  /// `.sleep-control-deck`：`linear-gradient(145deg, .09, .04)` + 描边 + 外阴影。
  static const deckFillTop = Color(0x17FFFFFF); // rgba(255,255,255,.09)
  static const deckFillBottom = Color(0x0AFFFFFF); // rgba(255,255,255,.04)
  static const deckStroke = Color(0x1AFFFFFF); // rgba(255,255,255,.10)
  static const deckShadow = Color(0x29000000); // rgba(0,0,0,.16)

  /// `.sleep-mode-kicker`（「睡眠模式」）。
  static const kickerInk = Color(0x80E1E5F4); // rgba(225,229,244,.50)
  /// `.sleep-greeting`（「晚安」）。
  static const greetingInk = Color(0xFF9EAFF3);

  /// `.sleep-setup-hero > p:last-child`（「放下今天…」）。
  static const heroBodyInk = Color(0x8FE1E5F4); // rgba(225,229,244,.56)
  /// `.sleep-start-note`（「屏幕将保持暗色…」）。
  static const startNoteInk = Color(0x5CE1E5F4); // rgba(225,229,244,.36)

  /// `.sleep-scene-picker-title > span` / `small`。
  static const pickerTitleInk = Color(0xB8E1E5F4); // rgba(225,229,244,.72)
  static const pickerHintInk = Color(0x52E1E5F4); // rgba(225,229,244,.32)

  /// `.sleep-control-label > span`（「常用白噪音」）与右侧「完整设置」。
  static const controlLabelInk = Color(0x7AE1E5F4); // rgba(225,229,244,.48)
  static const controlActionInk = Color(0xFFAEBDFF);

  /// `.sleep-control-copy small`（控制行副标题）。
  static const controlMutedInk = Color(0x6BE1E5F4); // rgba(225,229,244,.42)
  /// `.sleep-control-row` 的分隔线。
  static const controlRowDivider = Color(0x12FFFFFF); // rgba(255,255,255,.07)

  /// `.sleep-quick-sound-list button` 的三态。
  static const quickSoundInk = Color(0x7AE1E5F4); // rgba(225,229,244,.48)
  static const quickSoundFill = Color(0x09FFFFFF); // rgba(255,255,255,.035)
  static const quickSoundStroke = Color(0x0FFFFFFF); // rgba(255,255,255,.06)
  static const quickSoundSelectedInk = Color(0xFFC3CEFF);
  static const quickSoundSelectedFill =
      Color(0x267E91E9); // rgba(126,145,233,.15)
  static const quickSoundSelectedStroke =
      Color(0x47ACBCFF); // rgba(172,188,255,.28)

  /// `.sleep-start-button`：`linear-gradient(135deg, #687fe2, #6962c7)` + 外阴影 + 内高光。
  static const startGradient = [Color(0xFF687FE2), Color(0xFF6962C7)];
  static const startInk = Color(0xFFFFFFFF); // color: #fff
  static const startShadow = Color(0x524450A4); // rgba(68,80,164,.32)
  static const startInnerHighlight =
      Color(0x33FFFFFF); // inset 0 1px rgba(255,255,255,.20)

  // ── 尺寸 ────────────────────────────────────────────────────────────────
  static const cardRadius = 22.0; // .sleep-option-card / .sleep-events
  static const sheetRadius = 30.0; // .sleep-settings-sheet
  static const pickerRadius = 20.0; // 激活态的场景选择器
  static const previewRadius = 13.0; // .sleep-scene-preview
  static const eventIconSize = 34.0; // .sleep-event-icon
  static const eventIconRadius = 12.0;
  static const eventRowMinHeight = 61.0; // .sleep-event-row
  /// setup 的控制行图标底板：`.sleep-control-row .sleep-option-icon` 是 35，
  /// 比事件行的 34 大一格——原型里这两条规则各写各的，故不合并。
  static const setupIconSize = 35.0; // .sleep-control-row .sleep-option-icon
  static const deckRadius = 28.0; // .sleep-control-deck
  static const quickSoundMinHeight = 47.0; // .sleep-quick-sound-list button
  static const quickSoundRadius = 14.0;
  static const setupStartMinHeight = 58.0; // .sleep-start-button
  static const setupStartRadius = 18.0;
  static const holdButtonMinHeight = 56.0;
  static const holdButtonRadius = 18.0;
  static const scenePreviewWidth = 64.0;
  static const scenePreviewHeight = 42.0;

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

  /// `@media (min-height: 860px)`：入睡前态 hero 从 230 撑到 **285**。
  static bool tallHero(BuildContext context) =>
      MediaQuery.sizeOf(context).height >= 860;

  /// deck 里各段的行内边距：常规 16，窄屏 13。
  static const deckGutter = 16.0;
  static const narrowGutter = 13.0;
}
