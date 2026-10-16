# 判定换成 YAMNet 实现计划

**Goal:** 让「夜深」真的能认出鼾声。v3.26 那套手写声学阈值在 47 段人工标注上
**覆盖 2% / 准确 0% / 鼾声召回 0%**，把时长门槛从 2500 ms 拆到 500 ms 也救不回来——
使用方的原话是「一晚上的真实睡眠数据一个识别不出来」。换成一个**被测过的模型**。

**设计依据：** [2026-10-16-snore-detection-approaches-design.md](../specs/2026-10-16-snore-detection-approaches-design.md)
（选型、市面做法、两轮实测）与它的 §八（落地记录）；
[2026-10-14-night-clip-auto-analysis-design.md](../specs/2026-10-14-night-clip-auto-analysis-design.md)
（旧引擎的完整设计与它的判决书 §五·补）。

**Tech Stack:** Dart + `tflite_flutter: ^0.12.1`（FFI 插件，Android/iOS/macOS 原生库）、
MediaPipe 的 `yamnet.tflite`（4,126,810 B，随包发布也进仓库）、Drift（schema **v7 → v8**）。

## Global Constraints

- `kind` 列**仍然只能由人写**；机器判断另存 `auto_analysis`。`transcript` 永不写，
  `analysis` 不许碰（AI 洞察服务的地盘）。
- **永不输出 `AutoLabel.noise`**（偏差 #65 不许放回来）；**只说「疑似」**；**不给概率**。
- **判定规则必须能在 `flutter test` 里被完整钉死**——所以它单独一层，
  不 import `tflite_flutter`、不碰 `dart:io`。
- `lib/` 里不许写死色值；注释文档一律中文。
- 不改 `lib/**/*.g.dart`；不往 shell profile / gradle 常驻配置写东西。
- **不许把没做过的事写成已完成**：没跑的一律留在 `docs/verification-log.md` 的未验证里。

---

## Task 1: 判定规则（纯函数层）

**Files:** Create `lib/features/sleep/domain/clip_yamnet.dart`

常量（`kYamnetWindowSamples = 15600` / `kYamnetHopSamples = 7800` / `kSnoringIndex = 38` /
`kSpeechIndex = 0` / `kSilenceDbfs = -60`）、`YamnetParams`（鼾声 0.40 / 人声 0.70）、
`ClipScores`、`yamnetWindowStarts()`、`meanScore()` / `maxScore()`、
`verdictFromScores(scores, dbfs:, params:)`。

**决定用整段均分**：那正是文档里那些数字被量出来的口径。取最高分要先重新量一遍。

**不产出事件区间**：模型按整段给结论；画一对秒数就是画没量过的东西。

- [x] 窗口切法：≤1 窗给 `[0]`（补零），否则按半步进走满窗
- [x] 判定：均分 ≥ 阈值 → 该标签；鼾声优先；都没过 → `null`
- [x] 静音闸在模型之前（全零对模型是分布外输入，没有测量）
- [x] 依据串：赢的类的均分 + **最高分**（让均分的盲区可见）+ 窗口数 + 判定线 + 输的类的均分

## Task 2: 跑模型（I/O 层）

**Files:** Create `lib/features/sleep/data/yamnet_scorer.dart`

`ClipScorer` 接缝 + `ClipScorerFactory` + `loadYamnetModelBytes()` + `YamnetScorer`。

- [x] 输入 rank-1 `[15600]` 喂扁平 `Float32List`；输出 `[1,521]` **必须嵌套 `List<double>`**
      （给 `Float32List(521)` 会在回填那步抛类型错——2026-10-16 真机实测撞到的）
- [x] 每窗先 `fillRange(0, …)` 清零，否则短片段会拿上一段的尾巴去算
- [x] 采样率不是 16 kHz 就抛（模型只吃 16 kHz，喂错是整段频率错位，不是分低一点）

## Task 3: 接线（批处理 isolate）

**Files:** Modify `lib/features/sleep/data/clip_analyzer.dart`

- [x] **整批一次 `Isolate.run`**：模型 4 MB 只加载一次、isolate 只起一次
- [x] 模型字节在主 isolate 读（`rootBundle` 要平台通道），再跟着批处理送进去
- [x] **闭包先取局部变量**：写 `_scorerFactory` 就是捕获 `this` → 数据库句柄一起进消息
      → `object is unsendable`
- [x] 空批次在加载模型之前返回
- [x] 逐段 try/catch 保持「一段读不动不连累别的段」
- [x] 整批失败 → 抛 `ClipModelUnavailable`，**一行状态都不写**（不伪装成「看过没把握」）
- [x] `_serialised`：同一时刻只跑一批（撞车时两份 4 MB 模型是新的代价）

## Task 4: 删掉旧判定

**Files:** Modify `lib/features/sleep/domain/clip_analysis.dart`

- [x] 删 `classifyClip` / `detectEvents` / `_detect` / `_mergeWindows` / `_strongestRule` /
      `_snoreMargin` / `_voiceMargin` / `_WindowVerdict` 与十条判定阈值参数
- [x] 留 `measureClip` / `AudioFeatures` / `rmsDbfs`（真测量，`tool/analyse_clips.dart` 用）
- [x] 留 `AutoLabel` / `AutoVerdict` / `AutoAnalysis` / `ClipEvent`（**读旧记录用**）
- [x] `AutoVerdict.event` 加守卫：`durationMs <= 0` 就没有事件（否则新判定画出「第 0.0–0.0 秒」）

## Task 5: 界面

**Files:** Modify `presentation/sheets/sound_card.dart`

- [x] 「自动判断依据」的收尾句改成「模型对整段声音测出来的分」
- [x] 三态与「自动」二字一个字不改

## Task 6: 迁移 v7 → v8

**Files:** Modify `lib/core/database/app_database.dart`

- [x] `UPDATE sound_clips SET analysis_status='pending', auto_analysis=NULL
      WHERE source='recording' AND analysis_status='analysed'`
- [x] **只动机器那一列**；`failed` 与演示数据不动

**决定做这条迁移**：`analysePending` 只捡 `pending`，不迁移的话那 3 段真鼾声会永远停在
「待标注」——正是这一版要修的事。清完之后冷启动自动重算，用户不需要做任何动作。

## Task 7: 工具

**Files:** Modify `tool/analyse_clips.dart`、重写 `tool/eval_clips.dart`

- [x] `analyse_clips` 删掉「判定」列，只打特征表
- [x] `eval_clips` 改成读**设备产出的分档表**（`dart run` 起不了 tflite），
      扫 `--sweep=snore|voice` 两条判定线

## Task 8: 端侧测量

**Files:** Create `integration_test/yamnet_eval_test.dart`（删掉旧的 `yamnet_probe_test.dart`）

- [x] 用**生产用的那个 `YamnetScorer`** 跑，不另写一套窗口逻辑（否则两边的数没法比）
- [x] 落两份：人读的报告 + `tool/eval_clips.dart` 读的分档表
- [x] 一段真实录音都没有时退到合成信号量耗时，**并明说分无意义、不写分档表**

## Task 9: 单测与变异验证

- [x] 新 `test/clip_yamnet_test.dart`（29 条）
- [x] 重写 `test/clip_analyzer_test.dart`（16 条，注入假打分器但走真 isolate）
- [x] 裁 `test/clip_analysis_test.dart`（只留测量）
- [x] `test/sound_card_test.dart` 加「新判定不摆秒数」
- [x] `test/schema_migration_test.dart` 加 `v7 → v8` 组（7 条，含冻结的 `_V7Database` DDL）
- [x] 变异验证六处，全部应变红：阈值 0.99 / 弃权改返回「杂音」/ 拆区间守卫 /
      拆静音闸 / 迁移不清 / 补跑不只看 `pending`

---

## 落地与未验证

落地在 **v3.37**。逐条读数与未验证项见
[`docs/verification-log.md`](../../verification-log.md) 的 v3.37 条目，其中最大的两条：

1. **判定准不准没量到**——那一轮手机上一段真实录音都没有（应用被卸过，上轮那 47 段
   连同标注一起没了），端侧只量到耗时。
2. **均分的盲区继承下来了**——一段 11.8 秒里只有 3.5 秒是鼾声时会被摊薄成弃权。
