# 片段自动分析 + Android 整夜录音 实现计划

**Goal:** 让「夜深」在用户睡着之后自己把录到的声音判成**疑似打鼾 / 疑似人声 / 弃权**，
不再需要逐段听、逐段标；并且让 Android 上**整夜真的录得到**——否则自动分析只有开录前后
那几十秒的原料。

**设计依据：** [2026-10-14-night-clip-auto-analysis-design.md](../specs/2026-10-14-night-clip-auto-analysis-design.md)

**Tech Stack:** Dart（`dart:math` / `dart:typed_data`，**自写 FFT，不引依赖**）、
Drift（schema v7）、Kotlin（前台服务）、Riverpod。

## Global Constraints

- `kind` 列**仍然只能由人写**；机器判断另存 `auto_analysis`。
- `analysis` 列不许碰（它是 AI 洞察服务的地盘，`sound_event.dart:77`）；`transcript` 永不写。
- 界面文案、注释、文档一律中文；代码标识符英文。设计令牌只从 `AppTokens.of(context)` 取。
- 不改 `lib/**/*.g.dart`；不往 shell profile / gradle 常驻配置写东西。
- **不许把没做过的事写成已完成**：真机没跑的，一律留在 `docs/verification-log.md` 的「未验证」里。

---

## Task 1: Android 前台服务

**Files:**
- Create: `android/app/src/main/kotlin/com/example/night_sleep/NightRecordingService.kt`
- Create: `android/app/src/main/kotlin/com/example/night_sleep/NightAudioServiceHandler.kt`
- Modify: `android/app/src/main/AndroidManifest.xml`（补 `<service>`、重写那段过期注释）
- Modify: `android/app/src/main/kotlin/com/example/night_sleep/MainActivity.kt`
- Create: `lib/core/platform/night_audio_service.dart`
- Modify: `lib/features/sleep/data/night_recorder.dart`

- [ ] 服务本体 + 通知渠道（`IMPORTANCE_LOW`，渠道在第一次真要起服务时才建）
- [ ] 方法通道 `night_sleep/recording_service`，五个返回码
      `started` / `notForeground` / `missingPermission` / `unsupported` / `failed`
- [ ] handler 主动判一次「应用此刻可不可见」（白噪音倒计时会在后台到点的坑）
- [ ] `start()` 先起服务后开流；`stop()` 先停流后撤服务
- [ ] 撤服务挂在**引擎**生命周期（`onEngineWillDestroy`），不是 Activity 的 `onDestroy`
- [ ] 单测（注入假 `NightAudioService`，不碰真通道）：顺序、两种硬失败不开流、
      `unsupported`/`failed` 照旧开流、通道解码

**验收边界：** 编译通过 + 单测通过。**真机过夜验证由使用方配合，见「未验证」。**

---

## Task 2: 纯函数分析器

**Files:**
- Create: `lib/features/sleep/domain/clip_analysis.dart`
- Modify: `lib/features/sleep/data/wav_file.dart`（补读；原先只有写）
- Create: `test/clip_analysis_test.dart`、`test/wav_file_test.dart`（补 `parsePcm16Wav` 一组）

- [x] 自写 radix-2 迭代 FFT（N=1024，旋转因子表预计算）
- [x] `measureClip`：逐帧算频带占比 / 质心 / 平坦度，**再对帧取平均**
- [x] 逐帧**去直流**，低频带从 20 Hz 起算
- [x] `classifyClip`：两条正向规则 + `minMargin` 门槛，认不出返回 `null`
- [x] `AutoAnalysis` 的编解码（坏数据返回 null，不抛）
- [x] `parsePcm16Wav` 只接受 PCM16；读不出返回 null，不抛

**实跑过的：**
- `flutter test test/clip_analysis_test.dart` → 18/18
- `flutter test test/wav_file_test.dart` → 29/29
- `dart run tool/analyse_clips.dart` 在使用方 10 段真实录音上跑通（见 Task 5）

---

## Task 3: schema v7、落库与触发

**Files:**
- Modify: `lib/core/database/app_database.dart`、`test/schema_migration_test.dart`
- Modify: `lib/features/sleep/domain/sound_event.dart`、`lib/features/sleep/data/sleep_repository.dart`
- Modify: `lib/features/sleep/data/session_repository.dart`（`finish()` 改返回 id）
- Create: `lib/features/sleep/data/clip_analyzer.dart`
- Modify: `lib/features/session/presentation/sleep_session_page.dart`、`lib/app/app.dart`

- [x] `sound_clips.auto_analysis`（可空 text，JSON），schemaVersion → 7
- [x] 迁移 `if (from >= 2 && from < 7)`，下界理由写在注释里
- [x] `updateClipAutoAnalysis` / `clipsAwaitingAnalysis`（照 `updateClipLabel` 的形状）
- [x] `SoundClip.autoAnalysis` + 三态 `labelText`
- [x] 三个触发点：会话结束后（不 await）、详情页手动重跑、冷启动补跑
- [x] 分析跑在 `Isolate.run` 里
- [x] 迁移测试：v6→v7 三条 + 「旧库直升 v7」四条（v1/v3/v4/v5 各覆盖一个下界）

**踩到并修掉的坑（都写进了代码注释）：**
1. **闭包隐式捕获 `this`**：`Isolate.run(() => _compute(bytes, params))` 里的 `params`
   就是 `this.params`，于是数据库句柄被塞进 isolate 消息，`SendPort.send()` 报
   「object is unsendable」，整段分析无声退化成「失败」。改成先取局部变量。
2. **「读不出来」与「弃权」被混成一种结果**：前者该记 `failed`，后者该记 `analysed`。
   改成 `_compute` 读不出来就抛，弃权才返回 null。
3. **静默吞异常**：`catch (_)` 让现场只看得到「分析失败」而毫无线索。改成 `debugPrint`。

**实跑过的：** `flutter test` → **698/698 通过**。

---

## Task 4: 界面三态

**Files:**
- Modify: `lib/features/sleep/presentation/sheets/sound_card.dart`
- Modify: `lib/features/sleep/presentation/sheets/detail_sheet.dart`
- Modify: `test/sound_card_test.dart`

- [x] 卡片标题三态：人标过 > `自动 · 疑似打鼾` > `待标注`
- [x] 图标：没人判断过才用中性波形；机器判过的用对应图标，「自动」二字承担提醒
- [x] 展开区显示实测依据（`_AutoBasisRow`），**不给「置信度」**
- [x] 详情页「重新分析」入口（与 AI 的「重新生成」措辞分得开）
- [x] 演示数据**不需要改**：它们的 `labeledAtUtc` 非空，天然走「人标过」那支

**实跑过的：** `flutter test test/sound_card_test.dart` 全绿（含 6 条三态新用例）。

---

## Task 5: 验证工具与文档

**Files:**
- Create: `tool/analyse_clips.dart`
- Create: 本规格与计划
- Modify: 主规格 §M3 + 偏差表；`README.md`；`CHANGELOG.md`；`docs/verification-log.md`

- [x] `tool/analyse_clips.dart`：对一个目录的 WAV 打印特征表 + 判定
- [x] 规格：`2026-10-14-night-clip-auto-analysis-design.md`
- [ ] 主规格 §M3 第 3 条改写 + 新增偏差条目
- [ ] README「未实现」表
- [ ] CHANGELOG
- [ ] verification-log（含完整「未验证」清单）

---

## Verification

```bash
dart format . && flutter analyze && flutter test
```

真机（MI 9 / API 30，adb serial `e0e60672`）——**必须由使用方配合，本轮未做**：
前台服务存活（`dumpsys activity services` 的 `isForeground` /
`dumpsys media.audio_flinger` 的 `Sil = n`）、拉回 WAV 复算全零窗数、端到端看自动标注。
判据沿用 v3.19 那一套。详见 [验证记录](../../verification-log.md)。

---

## v3.27 修订（2026-10-15）：Task 2 与 Task 5 重做

使用方听完并标注了手机上全部 12 段真实录音（10 杂音 / 1 梦话 / 1 打鼾），提出两件事：
**「这一段里面可以有鼾声跟杂音是一起的，你把鼾声标记出来即可」**、
**「调一下阈值，和人工标注对比，看下正确率」**。两件都做了，Task 2 与 Task 5 因此重写。

**Task 2 的改动（判定方式换了，不是调参）：**

- 判定单元从「整段平均成一个特征向量」改成**滑动窗事件**：1200 ms 窗 / 300 ms 步进 →
  连续同标签并段 → 间隔 <1500 ms 再并 → **起止跨度 ≥2500 ms 才算事件**。
  理由两条都在真机上撞到过，见规格 §一 的 10-15 小节与偏差 #61。
- **撤掉 `syllableBandRatio` 与 `spectralFlatness` 判据**（前者实测在随机水平，
  后者骑在阈值上），**新增 `pitchStrength`**（功率谱逆变换求自相关，维纳–辛钦）。
- **新增 `AutoLabel.noise`**（偏差 #62）。它只在「扫过一遍确实没找到事件」时出现；
  「有东西但不够格」一律弃权——「没把握」与「没有」是两回事。
- `AutoVerdict` 带上 `startMs` / `durationMs`，`AutoAnalysis` 的 JSON 因此多了两个键
  （旧记录没有，读出来当 0，**不当坏数据**）。

**Task 5 的改动：** 新增 `tool/eval_clips.dart`。原计划的验收方式是「实现方跑
`analyse_clips.dart`、使用方听那几段」，那只回答「像不像」；使用方要的是**正确率**，
所以补一个能拿人工标注算覆盖率 / 准确率 / 逐类召回精确、并能扫单个阈值的工具。

**这一轮量出来的结论（含负面的）：**

1. 准确率 **75%（9/12）**、覆盖 **100%**；拖椅子那段 1.1 秒误报已被时长门槛挡掉。
2. **三处不符全部落在标注本身可疑的片段上**：全表最像的一对「标注不同」的片段
   （标打鼾 vs 标杂音，相隔 16 秒）特征距离 0.362，比好几对同标杂音的更近。
3. 因此**这 12 段不足以判定谁对，也不许用来调阈值**（正类各 1 个样本）。
   `voiceCentroid` 提到 ≥900 能到 83%，但那是**一个样本上的 8 个百分点**，不作为依据。
4. **使用方随后逐段澄清了那三段「实际是什么」**：被判鼾声的那段前一半是**他在哼歌**；
   标打鼾的那段是他**假装**的鼾声（气息声）；标杂音的那段是**起床翻身、没有人声**。
   据此再补第四条判据 **`spectralPeakShare < 0.30`**（「鼾声不是乐音」），
   把哼歌那条误报消掉（覆盖 100%→92%、开口内准确 75%→82%，保守口径仍 75%——
   因为那 7 个百分点来自「不再判错」，不是「判对了」）。
   **人声那一侧没有对称加上限**：翻身的吱呀 27–39% 与哼歌重叠，而人声零正样本，
   没有可供落阈值的空档。**结论升级为：整条鼾声规则至今没有一个真实正样本。**

未验证项原样留在 `docs/verification-log.md` 的 v3.27 那一条里。
