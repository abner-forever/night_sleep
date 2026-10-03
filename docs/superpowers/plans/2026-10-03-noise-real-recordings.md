# 助眠音效改用真实录音素材（实现计划）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把八种**设备内实时合成**的助眠音效，换成五条**打包的实景录音**；删掉整个 DSP 合成器，音效列表重建为素材真正覆盖的五类。

**Architecture:** 音频来源从「运行时 `compute` 合成 WAV → 写临时目录 → `setFilePath`」变成「`setAsset` 直接播打包的 `.m4a`」。数据层的 `NoiseKind` 从「合成种类 + 种子」变成「条目 id + 资源路径」；`NoisePlayer` 因此少掉渲染、落盘、缓存清理三段，失败语义（`NoisePlaybackFailure`）保持不变。表现层的 `kNoiseOptions` 由 8 条改 5 条，弹窗网格宽度随之从「按 4 分」改成「按条数分」。

**Tech Stack:** Flutter 3.47.5 / Dart、`just_audio` 0.10.6（`setAsset`）、ffmpeg 9.0（仅在生成素材时用）

**设计依据:** [docs/superpowers/specs/2026-10-03-noise-real-recordings-design.md](../specs/2026-10-03-noise-real-recordings-design.md)

## Global Constraints

- 界面文案、注释、文档一律**中文**；代码标识符英文。
- **不改 `lib/**/*.g.dart`**。本计划不动表结构，**不需要** `build_runner`。
- **不要设 `PUB_HOSTED_URL` / `FLUTTER_STORAGE_BASE_URL`**（会污染 `pubspec.lock` 的 129 条 url）。
- **授权是红线**：素材「仅供个人试用、授权未确认」。文档必须如实标注，**界面里不得出现致谢/来源页**。
- **不得**用「溪流顶雨声」这类改名不改内容的做法补齐条数（规格偏差 #3/#7/#33）。
- 每个任务结束时跑 `dart format .`、`flutter analyze`、`flutter test`，**全绿才提交**。
- 基线：本轮开工前 `flutter test` 全绿。

## 已核实的事实（跑过，不是纸面推演）

| 事实 | 怎么核实的 |
| --- | --- |
| `loudnorm` 的输出被多条分支消费时**必须显式 `asplit`**，否则静默失效 | 不加 asplit 时成品停在 −35.6 LUFS；加 `asplit=3` 后为 −20.1 LUFS |
| 接缝须「把循环点之后的延续折回开头」，不能「把尾巴淡入开头」 | 沿用 `_foldSeam` 的思路；实测接缝阶跃 ≤ 各文件步进 p99 |
| `loudnorm` 的 `TP` 要留 2 dB 给交叉淡化 | `TP=-1.5` 时成品真峰顶到 0 dBFS；`TP=-3` 时落在 −1.9 ~ −3.0 |
| 篝火对动态归一**稳定欠冲 2.9 LU** | 目标 −22 落到 −24.9；单独给 −19 后落到 −23.0 |
| 五条成品：I=−22.1 ~ −23.0、TP ≤ −1.9 dBFS、合 3.40 MB | 逐条 `ebur128=peak=true` 量过 |
| `m4a` 的 edit list 裁掉了 AAC priming | 解码长度精确 = 标称时长（75.000 / 71.000 / 44.000 s） |
| `just_audio` 有 `setAsset` | `just_audio-0.10.6/lib/just_audio.dart:821` |
| darwin 侧 `LoopMode.one` 走「预排下一个 item」（无缝路径） | `just_audio-0.10.6/darwin/…/AudioPlayer.m` 的 `lmLoopOne` 分支 |

## 文件结构

| 文件 | 职责 | 动作 |
| --- | --- | --- |
| `assets/noise/{forest,fire,ocean,stream,wind}.m4a` | 打包的循环素材 | **新增** |
| `tool/generate_noise_assets.dart` | 由源素材重新生成上面 5 个文件 | **新增** |
| `pubspec.yaml` | 声明资源目录 | 改 |
| `lib/features/sleep/data/noise_asset.dart` | `enum NoiseKind`（id + assetPath） | **新增** |
| `lib/features/sleep/data/noise_synth.dart` | — | **删除** |
| `lib/features/sleep/data/noise_player.dart` | 播放打包资源 | **重写** |
| `lib/core/widgets/app_icons.dart` | 加 `stream` / `wind` 图标 | 改 |
| `lib/features/sleep/presentation/widgets/noise_controls.dart` | `kNoiseOptions` 5 条 | 改 |
| `lib/features/sleep/presentation/sheets/noise_sheet.dart` | 引用与网格宽度 | 改 |
| `lib/features/session/presentation/widgets/session_setup.dart` | `_quickIds` | 改 |
| `lib/features/settings/data/app_cache.dart` | 文档 | 改 |
| `lib/app/noise_session.dart` | 换 import | 改 |
| `test/noise_asset_test.dart` | 素材资产护栏 | **新增** |
| `test/noise_synth_test.dart` | — | **删除** |
| `test/noise_sheet_test.dart` | 5 格与新契约 | 改 |
| `test/{reminder_settings,sleep_session_page,session_setup_page,hold_to_finish_button,primary_action,schema_migration,session_night_widgets}_test.dart` | 多数只换 import | 改 |
| `integration_test/noise_playback_test.dart` | 改成钉「打包资源真能起播」 | **重写** |
| 规格 / README / CHANGELOG / architecture.md | 同步 | 改 |

---

## 任务 1：生成素材并声明资源

**Files:** `tool/generate_noise_assets.dart`、`assets/noise/*.m4a`、`pubspec.yaml`

- [x] **1.1** 写 `tool/generate_noise_assets.dart`：Dart 脚本，`Process.run` 调 ffmpeg，按规格 §5.2
      的滤镜链逐条生成到 `assets/noise/`。源目录与文件映射、每条的目标响度与循环长度写成
      **显式常量表**（不要按目录扫描猜映射）。脚本头注释写清：为什么存在、怎么跑
      （`dart run tool/generate_noise_assets.dart`）、源素材出处、**授权待确认**。
- [x] **1.2** 跑它，产出 5 个 `.m4a`；核对字节数与规格 §5.1 的表一致（允许 ±2 %）。
- [x] **1.3** `pubspec.yaml` 的 `flutter:` 下加 `assets: - assets/noise/`。
- [x] **1.4** 逐条复量 `ebur128=peak=true`，确认响度 −22.1 ~ −23.0、真峰 ≤ −1.9 dBFS；
      写进 README「验证记录」。

**验收：** `assets/noise/` 有 5 个文件、合 3.40 MB；`flutter pub get` 通过。

## 任务 2：数据层换成资源目录

**Files:** `lib/features/sleep/data/noise_asset.dart`（新）、`noise_synth.dart`（删）、`noise_player.dart`（重写）、`lib/app/noise_session.dart`

- [x] **2.1** 新增 `noise_asset.dart`：`enum NoiseKind { ocean, fire, forest, stream, wind }`，
      每项带 `id` 与 `assetPath`（`assets/noise/<id>.m4a`），保留 `fromId`。
      **id 沿用旧值** `ocean` / `fire` / `forest`，旧会话里这几个 id 继续有效。
- [x] **2.2** 删除 `noise_synth.dart`（整个 DSP 合成器、WAV 编码、`_Rng`）。
- [x] **2.3** 重写 `noise_player.dart`：`play()` 改 `setAsset(kind.assetPath)`；删掉
      `_generateLoop`、`_ensureFile`、`clearCache`、`_files`、`compute` 与
      `dart:io` / `path` / `path_provider` / `noise_synth` 的 import。
      **保留**：`unawaited(_audio.play())` 那条注释与做法（起播 Future 永不完成，已实测）、
      `NoisePlaybackFailure`、`current`、`stateStream`、`setVolume`、`stop`、`dispose`。
      失败文案从「无法生成音频」改成说清是**资源加载**失败。
- [x] **2.4** `noise_session.dart` 的 import 由 `noise_synth.dart` 换成 `noise_asset.dart`。

**验收：** `flutter analyze` 无告警；`grep -rn "noise_synth\|buildNoiseWav\|clearCache" lib/` 无命中。

## 任务 3：表现层五条目录与新图标

**Files:** `lib/core/widgets/app_icons.dart`、`noise_controls.dart`、`noise_sheet.dart`、`session_setup.dart`

- [x] **3.1** `app_icons.dart` 加 `_stream`（水滴）与 `_wind`（三道风线）两个 24×24 描边路径
      + 两个静态方法，几何风格与既有图标一致。**保留** `rain` / `fan`。
- [x] **3.2** `kNoiseOptions` 重建为规格 §4 的五条（id、标签、图标、颜色逐条照抄表格）。
- [x] **3.3** `noise_sheet.dart`：换 import；格子宽度由「按 4 分」改成**按 `kNoiseOptions.length` 分**，
      使五格在窄屏与宽屏各占一行；注释同步（原来那句「四格一行」的理由要改写，不是删）。
- [x] **3.4** `session_setup.dart`：`_quickIds` 改 `['ocean','fire','forest','wind']`，
      原注「顺序照抄原型」改写成「原型那四条里三个 id 已不存在，改为覆盖水/火/林/空气」。

**验收：** `flutter analyze` 通过；`flutter test test/session_setup_page_test.dart` 全绿。

## 任务 4：测试

- [x] **4.1** 删 `test/noise_synth_test.dart`（合成器已不存在）。
- [x] **4.2** 新增 `test/noise_asset_test.dart`：
      (a) `NoiseKind.values` 与 `kNoiseOptions` **一一对应**（数量、id 集合双向相等）；
      (b) 每条 `assetPath` 指向**仓库里真实存在**的文件，且 > 100 KB；
      (c) 文件头 4 字节是 `ftyp` 之前的 box 长度 + 类型（即确为 MPEG-4，不是空壳）；
      (d) 5 个文件合计落在 3.0–3.8 MB。
- [x] **4.3** 改 `test/noise_sheet_test.dart`：条数 8 → 5；把「八格仍是四列两行」改成
      「五格仍是一行且不溢出」，**保留变异验证**（格子宽度换回屏幕宽度必红）。
- [x] **4.4** 其余 widget 测试只换 import（`noise_synth` → `noise_asset`）与假播放器签名。
- [x] **4.5** 重写 `integration_test/noise_playback_test.dart`：改成断言**打包资源真的能解码并起播**
      （音量 0），并说明为什么这条只能跑在真平台——widget 测试用假播放器，`setAsset` 一步都走不到。
- [x] **4.6** `flutter test` 全绿。

**验收：** 全量测试通过；变异验证按 4.3 重跑变红。

## 任务 5：缓存语义与文档同步

- [x] **5.1** `app_cache.dart` 的类注释：临时目录里**不再有白噪音 WAV**，只剩导出副本；
      说明「全新安装未导出时读数为 0 B 是如实的」。实现不动。
- [x] **5.2** `2026-09-28-night-sleep-design.md`：偏差 #5 / #17 重写、#43 加注、§10 第 3 条
      标注「部分落实，授权待确认」、§9 测试矩阵的「合成波形」行改为素材资产断言。
- [x] **5.3** `docs/architecture.md:72` 的「实时合成」一句改写并指向新规格。
- [x] **5.4** `README.md`：实现范围（8 种合成 → 5 条录音）、「未实现」表若涉及音效授权要加行、
      验证记录写本次实测数字、**运行与生成**处补 `tool/generate_noise_assets.dart` 的跑法。
- [x] **5.5** `CHANGELOG.md` 记一条。

**验收：** `grep -rn "实时合成\|合成 8 种\|8 个 WAV" README.md docs/` 不再有描述现状的命中。

## 任务 6：终审

- [x] **6.1** `dart format .` / `flutter analyze` / `flutter test` 全绿。
- [x] **6.2** 核对没有残留的「合成」措辞与实际不符之处。
- [x] **6.3** 记录待人工核对项（听感、授权、目视）到 README 与规格 §10。

---

## 执行结果（2026-10-03）

全部任务完成。`dart format .` / `flutter analyze`（No issues found）/ `flutter test`
（469/469）/ `flutter drive -d macos`（All tests passed）**四项全绿**。

与计划的两处偏离，如实记：

1. **任务 1.2 的目标值在实跑中调过两次。** 计划写「全局 `I=-22`、`fire` 单独 `-19`」，
   实际跑出来 `wind` 会**过冲**到 `-21.3`（它峰均比最低），于是 `wind` 单独改成 `-23`。
   最终五条落在 −22.1 ~ −23.0，跨度 **0.9 LU**。
2. **任务 5 多改了三处用户可见文案**，计划里没列——它们是在收尾扫描时才浮出来的，
   但都属于「界面在说假话」，必须当轮修掉：
   - `noise_sheet.dart` 底部说明「声音由应用实时合成，不占用存储、不需要下载」；
   - `noise_sheet.dart` 播放中文案「音频由应用实时合成，循环无缝」；
   - `settings_page.dart` 清除缓存副标题「白噪音音频等可再生成的临时文件」。
   三处都改成与「打包实景录音」一致的说法。
3. **任务 6.3 的待办**（听感 / 授权 / 5 格布局目视）已记入 README「验证记录」、
   README「未实现」表与新规格 §10。
