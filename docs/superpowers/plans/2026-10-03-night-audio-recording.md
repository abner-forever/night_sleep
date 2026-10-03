# 夜间录音（plan B）实现计划

日期：2026-10-03
规格：[2026-10-03-night-audio-recording-design.md](../specs/2026-10-03-night-audio-recording-design.md)
档位：**spec + plan**（新能力、新依赖、平台权限、影响产品语义）

## 目标

会话期间真实采集环境声音，按振幅切成「有声响的片段」，一段一个 WAV 文件落进
`SoundClips`，详情页可回放、可手动标注。**不做任何自动分类、转写或结论。**

## 交付顺序

Task 1 → 2 → 3 → 4 → 5 → 6 是数据与采集链路，7 → 8 是界面，9 是文档，10 是真机验收。
每一轮结束都跑 `dart format .` / `flutter analyze` / `flutter test`。

---

## Task 1：依赖与平台配置

**交付物**

- `pubspec.yaml` 加 `record: ^7.1.1`。
- `ios/Runner/Info.plist`：加 `NSMicrophoneUsageDescription`（文案见规格 §七）
  与 `UIBackgroundModes` = `[audio]`。
- `macos/Runner/Info.plist`：加同样的 `NSMicrophoneUsageDescription`。
- `macos/Runner/DebugProfile.entitlements` 与 `Release.entitlements`：都加
  `com.apple.security.device.audio-input = true`。
- `README.md` 的「未实现」表补 Android 的 `RECORD_AUDIO` /
  `FOREGROUND_SERVICE_MICROPHONE` / 前台服务一行（平台目录仍不存在）。

**约束**

- 跑 `flutter pub get` **不要设 pub 镜像**（`pub.dev` 直连可用）。设了会把
  `pubspec.lock` 里上百条 `url` 改写成镜像地址，制造一个与依赖无关的巨型 diff。
- macOS 两个 entitlements 文件**都要改**——只改 Debug 会让 release 包静默录不了音。

**验收**：`flutter pub get` 成功；`flutter analyze` 干净；
`flutter build macos --debug` 通过（证明 entitlements 与插件接得上）。

---

## Task 2：schema v6 与数据库方法

**交付物**

三列可空列，**不重建任何表**（`m.addColumn` 即可，与 v5 那次同类）：

| 表 | 新列 | 定义 |
| --- | --- | --- |
| `ActiveSessions` | `clipJournal` | `text().nullable()` |
| `SoundClips` | `waveformEnvelope` | `text().nullable()` |
| `SoundClips` | `labeledAtUtc` | `dateTime().nullable()` |

`onUpgrade` 加：

```dart
if (from >= 5 && from < 6) { ... addColumn × 3 ... }
```

**下界必须写 `from >= 5`**，不能写成 `from < 6`：与 v5 那次同一个理由——
低版本升上来的库是用**当前**表定义建的表，列早就在了，再加一次就是
`duplicate column name`。

`AppDatabase` 新增：

- `Future<void> insertClips(List<SoundClipsCompanion> rows)`——供 `finish()` 的事务调用。
- `Future<void> updateClipLabel(String clipId, String kind, DateTime labeledAtUtc)`。
- `Future<void> deleteAllClips()` 与 `Future<List<SoundClip>> allRecordingClips()`。
- `Stream<List<SoundClip>> watchAllClips()`（生成的 row 类型），并加
  `allClipsProvider` / `clipsProvider`，供 `sleepEntriesProvider` 订阅。

**改动既有代码**

- `SleepRepository._toEntry` 的 `waveformEnvelope`：demo 行照旧走
  `demoWaveformEnvelope`，真实行改为**读 `waveformEnvelope` 列**（JSON 解码），
  读不到或坏了为 `null`（画等高轨道，不猜形状）。
- `SoundClip` 领域模型加 `bool get isLabeled => labeledAtUtc != null` 与
  `String get labelText => isLabeled ? kind.label : '待标注'`。
- `demo_seed.dart`：演示片段补 `labeledAtUtc`（否则整套演示数据显示成「待标注」）。
- `SessionRepository` 的 `_toSession` / `start()` / `update()` 带上 `clipJournal`。
- `SleepSession` 领域模型加 `List<ClipDraft> clipJournal`。

**测试**

- `test/schema_migration_test.dart` 追加 v5→v6：三列出现、既有行数据不变、
  级联删除仍生效。**沿用该文件冻结裸 DDL 的既有做法**，不要引用当前表定义。
- `test/sleep_data_test.dart`：真实片段从 `waveformEnvelope` 列读回包络；
  列是坏 JSON 时为 `null` 而不是抛异常。
- `test/demo_seed_startup_test.dart`：演示片段带 `labeledAtUtc`，显示为「打鼾」而非「待标注」。

---

## Task 3：切片与包络（纯函数）

**交付物**：`lib/features/sleep/domain/clip_segmentation.dart`

```dart
class AmplitudeSample { final Duration offset; final double dbfs; }
class ClipRange { final Duration start; final Duration end; }
class ClipParams { /* 规格 §三 那七个参数，全部带默认值 */ }

List<ClipRange> segmentClips(List<AmplitudeSample> samples, ClipParams params);
List<double> envelopeFor(List<AmplitudeSample> samples, ClipRange range, {int bars});
```

**约束**

- **纯函数**：不 import `dart:io`、不碰任何插件。这是整条链路里唯一能被完整单测的部分，
  必须保持这一点。
- 滞回、静音时长、前置 padding、最短 / 最长片段、合并间隔——七条规则各写一条测试。
- 空输入、全静音、全有声、单点输入都要有定义明确的结果（不是恰好不崩）。

**测试**：`test/clip_segmentation_test.dart`

- 七条参数各一条：关掉某一条规则会让对应断言变红（变异验证）。
- 一段 60 秒的合成鼾声（每秒一次起伏）切成多段而不是一段，也不被换气停顿切碎。
- `envelopeFor` 长度恒为 `bars`，值域 0–1，单调映射；全静音片段不产生 NaN。

---

## Task 4：WAV 写入与环形缓冲

**交付物**

- `lib/features/sleep/data/wav_file.dart`：
  `Uint8List pcm16WavHeader({required int sampleRate, required int channels, required int dataBytes})`
  与 `class WavWriter { Future<void> open(String path); void append(Uint8List pcm); Future<void> close(); }`。
- `lib/features/sleep/data/pcm_ring.dart`：固定时长的环形缓冲，用于前置 padding。

**约束**

- 插件吐的是**裸小端 PCM16、无容器头**，WAV 头必须我们自己写：44 字节、
  `RIFF`/`WAVE`/`fmt `/`data` 四段，`data` 长度先用占位值，`close()` 时
  `setPosition` 回填两处长度（偏移 4 与 40）。
- 环形缓冲按**字节**而不是按样本数记账，因为分片边界不保证按样本对齐。

**测试**：`test/wav_file_test.dart`（纯字节，用内存缓冲，不落盘）

- 头部逐字节断言；`data` 长度与实际写入字节数一致。
- 回填之后 `RIFF` 长度 = 文件长度 − 8。
- 环形缓冲：写入超过容量后，取出的正好是**最后** N 毫秒，顺序正确。

---

## Task 5：录音服务

**交付物**：`lib/features/sleep/data/night_recorder.dart`

```dart
abstract class NightRecorder {
  Stream<NightRecordingStatus> get status;
  Future<bool> ensurePermission();
  Future<void> start();
  Future<void> stop();
}

class RecordNightRecorder implements NightRecorder { /* 包 record 插件 */ }
```

**约束**

- **必须可注入假实现**：widget / 单元测试不能碰真实平台通道。
  既有范式见 `test/primary_action_test.dart:73-86`
  （`tester.binding.defaultBinaryMessenger.setMockMethodCallHandler`），
  但这一层更适合直接在 `Provider` 上 `overrideWithValue` 一个假 `NightRecorder`。
- `RecordConfig` 按规格 §二精确写死（pcm16bits / 16000 / 1 声道 / 三个开关全 false）。
- 每收到一片 PCM：推环形缓冲 → 每 100ms 聚合一格 RMS → 喂 `segmentClips` 的增量状态机
  → 片段开始/结束时开关 WAV 文件。
- `onStateChanged()` 的 `pause` / `stop`（来电、被其他应用抢麦）→ 收尾当前片段、
  状态转「已停止」并带上原因。**已录到的片段不丢。**
- 每关闭一段就回调一次 `onClipClosed(ClipDraft)`，由上层写进会话行的 `clipJournal`
  （Task 6）——**这一步不能攒到会话结束**，否则被杀就全丢。
- 录不了的任何一步失败都**不切到录音态**，如实报错。

**测试**：`test/night_recorder_test.dart`

用假 `AudioInput`（喂合成 PCM 序列）+ 假 `ClipFileStore`：

- 一段超过阈值的 PCM 产生一条片段，文件内容 = 前置 padding + 该段。
- 全静音输入不产生任何片段、不创建任何文件。
- 被中断后状态为「已停止」，已关闭的片段仍在。
- `start()` 抛错时状态不是「录音中」。

---

## Task 6：会话生命周期接线

**交付物**

- `lib/features/sleep/data/clip_store.dart`：片段目录解析
  （`getApplicationSupportDirectory()/clips/`）、文件命名、占用统计、按 id 删除、
  「删除全部录音」、启动时的孤儿文件清理。
- `lib/app/night_recording.dart`：app 级的 `nightRecordingControllerProvider`
  （与 `noiseSessionControllerProvider` 同一手法——**比会话页长命**，收起页面后继续录）。
- `SessionRepository.finish()`：在一个事务里，先按会话行的 `clipJournal`
  插入全部片段行，再 `saveRecord`，最后 `deleteActiveSession()`。
- 与白噪音的协调：订阅 `noiseSessionControllerProvider` 的 `isPlaying`，
  **播放中不录、停掉即开始**（规格 §六）。

**约束**

- **顺序不能反**：`clipJournal` 必须在删会话行**之前**读出来，否则清单随行一起消失。
- `discard()` 要顺手删掉这次的片段文件——用户丢掉这一晚，音频没有理由留着。
- 会话页 `pop`（「收起」）**不停止录音**，与白噪音同一套生命周期。
- 启动时不留下「正在录音」的假状态：进程重启后录音必然没在跑，
  状态一律以「未在录」初始化，界面据实显示。

**测试**：`test/session_recording_test.dart`

- `finish()` 把清单里的片段全部写进 `sound_clips`，且 `recordId` 等于新记录 id。
- 清单为空时 `finish()` 行为与现在完全一样（回归）。
- `discard()` 删掉片段文件。
- 白噪音在播时不调 `start()`；停掉后调（用假 `NightRecorder` 断言调用次序）。

---

## Task 7：保留期限与占用

**交付物**

- `lib/features/sleep/domain/clip_retention.dart`：纯函数
  `List<String> expiredClipIds(List<ClipAged> clips, {required DateTime now, int keepNights = 7})`
  ——按**记录日期**（不是片段时刻）取最近 7 晚，返回要清理的片段 id。
- 清理动作：删文件 + `localUri` 置空，**行保留**，`source = 'recording'` 才算。
- 触发点：App 启动、以及每次会话结束时。
- 设置页的占用读数走与 `FileAppCache` 同一条路线（读不到就如实说读不到）。

**测试**

- `test/clip_retention_test.dart`：7 晚边界（第 7 晚保留、第 8 晚清）、
  同一天多个片段一起处理、demo 片段不在清理范围。
- 清理后详情页那条片段仍在、显示「这段录音未保留在本地，无法回放」，
  且**波形照旧画得出来**（包络来自列，不依赖文件）。

---

## Task 8：界面

**交付物**

1. **会话页录音指示**（`session_events_card.dart` / `sleep_session_page.dart`）：
   三态文案按规格 §六 那张表，状态取自 `NightRecorder.status`，**不是偏好值**。
   鼾声行副标题不再是「尚未接入录音，开关只保存偏好」。
2. **会话页 / 入睡前态 / 设置页三处旧文案**：按真实能力改写。三处的回归测试
   （`test/sleep_session_page_test.dart`、`test/session_setup_page_test.dart`、
   `test/pages_widget_test.dart`）要同步改——**旧断言必须变红再改**，别直接删。
3. **开关打开时申请权限**：被拒则回弹、不写偏好、给「去系统设置」。
   **不能复用 `reminders.dart` 的通知入口**，另做通用的应用设置跳转。
4. **`SoundCard` 接真实回放**：现在的 `_togglePlayback` 只翻转一个局部布尔、
   不产生任何声音。接上 `just_audio`（`setFilePath` + `play` + 进度回传），
   注意 `AudioPlayer.play()` **不能 await**（`noise_player.dart` 里已记了这条实测）。
5. **标注**：展开区加「打鼾 / 梦话 / 杂音」三选，写回 `kind` 与 `labeledAtUtc`，
   然后 `ref.invalidate(sleepEntriesProvider)`——`sleepEntriesProvider` 目前只
   watch 记录表，写完片段不会自动重读。
6. **详情页空状态分两句话**：
   - 有会话但一段没录到 →「这一晚没有录到声响」
   - 开关没开 / 麦克风被拒 / 白噪音占着全程 →「这一晚没有录音」
7. **设置页 · 声音检测**：占用 + 「删除全部录音」（走 `showConfirmDialog`）。

**测试**：`test/sound_card_test.dart`（新）、既有三个页面测试的同步修改。

- 未标注片段显示「待标注」；标注成「杂音」后仍显示「杂音」而不是退回「待标注」。
- `localUri` 为空时播放按钮不可用、显示「未保留在本地」，且**波形仍在**。
- 两种空状态各自的文案逐字断言。

---

## Task 9：文档同步

- 主规格 `2026-09-28-night-sleep-design.md`：§8 偏差 #7 改写为「已实现，见 #27」，
  #27 落地，#2 兑现，#31 / #35 / #44 作废并链接到本规格；M3 的「仍未开始」清单勾掉；
  §7 隐私段落去掉「当前尚未接入」；§10 第 6 条麦克风文案标记为已确认并落地。
- 会话规格 `2026-09-30-sleep-session-design.md` §六：把「二选一」改为实测结论与第三条路，
  并订正 §二「录音不需要改表」。
- `README.md`：实现范围、未实现表、验证记录。
- `CHANGELOG.md`：记一条版本变更。

---

## Task 10：真机验收（单独一批，不塞进上面任何任务）

规格 §十二 那五条**必须在真机上跑**，任何一条没过就不能对外说这个功能可用：

1. 整夜后台存活（锁屏后仍在录）
2. 阈值实测调参（安静房间不误触发、鼾声不被换气停顿切碎）
3. 白噪音倒计时到点后录音接上
4. 来电 / 抢麦中断后已录片段仍在、界面如实报停
5. 整夜耗电

这一批按既有做法攒到最后一起做（模拟器 / 真机截图与实机跑测），
**不要塞进实现任务里**——跑一次真机会把单个任务卡死很久。

## 明确不做

- 自动鼾声 / 梦话识别、语音转写、AI 分析结论（M3 第 3 条）。
- 白噪音的后台播放（与录音正好相反，那一条仍未做）。
- Android 平台落地（目录尚未生成）。
- 片段编辑、拼接、导出。
