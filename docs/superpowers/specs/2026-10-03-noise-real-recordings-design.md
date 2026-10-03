# 助眠音效改用真实录音素材（设计规格）

**日期：** 2026-10-03
**状态：** 已实现（待目视/听感核对）
**取代：** `2026-09-28-night-sleep-design.md` §8 偏差 #5、#17 的裁定；§10 第 3 条待办部分落实
**相关：** `docs/superpowers/plans/2026-10-03-noise-real-recordings.md`

## 1. 背景与动机

此前八种助眠音效是**设备内实时合成**的（`noise_synth.dart`：白/棕/粉噪、雨、海浪、篝火、
森林、风扇），裁定见 `2026-09-28-night-sleep-design.md` §8 偏差 #5。当时选合成的理由是
「与原型最接近，且没有素材授权与署名负担」。

该规格 §10「尚需用户提供的外部资料」第 3 条一直挂着：

> 助眠音效的可商用素材及授权信息（或确认采用程序合成）。

使用方于 2026-10-03 提供了 7 个实景录制素材文件，本规格记录据此做出的替换设计。

## 2. 使用方裁定（2026-10-03）

| # | 问题 | 裁定 |
| --- | --- | --- |
| 1 | 替换范围 | **改成与素材一致的条目**——音效列表重建为素材真正覆盖的 5 类，不做名不副实的硬套 |
| 2 | 素材授权 | **尚未确认，仅供个人试用**。代码与文档必须如实标注「授权待确认，发布前必须落实」，**不得声称可商用** |
| 3 | 打包方式 | **重编码为单声道并裁成循环段** |

## 3. 素材

来源目录：`~/Downloads/白噪音素材`（7 个 MP3，44.1 kHz 立体声 320 kbps，合计约 48 MB）。
文件名带 `爱给网_aigei_com` 后缀。

| 素材文件 | 时长 | 归入条目 |
| --- | --- | --- |
| `1、《霖落林海听声》…森林鸟…mp3` | 302.0 s | 森林 `forest` |
| `篝火噼啪声-环境音-冬季…mp3` | 75.1 s | 篝火 `fire` |
| `海风海浪声；海浪拍打礁石…mp3` | 156.9 s | 海浪 `ocean` |
| `溪水声；河水声…mp3` | 211.8 s | 溪流 `stream` |
| `大自然风声；田野风声…mp3` | 48.6 s | 风 `wind` |

**未采用的 2 个文件**：`7、《暝溪高枝遥唳》…森林鸟…`（与已采用的森林素材同类，取其一即可）、
`溪流声；泉水叮咚响…`（与已采用的溪流素材同类，取其一即可）。取用时优先选**时长更长**的
那一份，好让裁出的循环段有挑选余地。

### 3.1 授权状态（红线）

**这批素材的可商用授权尚未落实。** 这是规格 §10 第 3 条的待办，不是「已解决」。因此：

- 代码注释、`pubspec.yaml` 邻近说明、README 与本节都必须写明来源与「授权待确认」；
- **不得**在应用界面里放「素材来源 / 致谢」——那会读作「授权已确认」；
- 发布前必须回到使用方确认授权，或换素材，或退回合成。

## 4. 音效目录（5 条）

`kNoiseOptions` 由 8 条改为 5 条，顺序沿用原型中仍然存在者的原有次序，新的两条追加在后：

| id | 标签 | 图标 | 颜色 | 素材 |
| --- | --- | --- | --- | --- |
| `ocean` | 海浪 | `AppIcons.ocean` | `0xFF7AB8C4` | `assets/noise/ocean.m4a` |
| `fire` | 篝火 | `AppIcons.fire` | `0xFFD4A060` | `assets/noise/fire.m4a` |
| `forest` | 森林 | `AppIcons.forest` | `0xFF90B890` | `assets/noise/forest.m4a` |
| `stream` | 溪流 | `AppIcons.stream`（新增） | `0xFF5AC8FA` | `assets/noise/stream.m4a` |
| `wind` | 风 | `AppIcons.wind`（新增） | `0xFFA0B8C4` | `assets/noise/wind.m4a` |

- **颜色全部取自原型既有调色板**，没有新造颜色：`ocean` / `fire` / `forest` 保持原值，
  `stream` 沿用原「雨声」的 `0xFF5AC8FA`，`wind` 沿用原「风扇」的 `0xFFA0B8C4`。
- **新增两个图标**（`app_icons.dart`，feather 风格 24×24 描边，与既有图标同一套几何）：
  `_stream` 取水滴形，`_wind` 取三道风线。`_rain` 与 `_fan` 不再被音效列表引用，但
  `AppIcons.rain` / `AppIcons.fan` **保留**——它们是通用图标，删除会让图标集残缺。

**被删掉的条目**：白噪音、棕噪音、粉噪音、雨声、风扇。前三个是纯噪音（素材里没有对应
内容），后两个素材也未覆盖。**不做「用溪流顶上雨声」这类替代**：标签与内容不符正是偏差
#3 / #7 / #33 那条「没有的东西就显示为没有」红线要挡的事。

### 4.1 常用白噪音四格

`session_setup.dart` 的 `_quickIds` 原为原型的 `['rain','ocean','brown','fan']`，其中三个 id
已不存在。改为 `['ocean','fire','forest','wind']`：四条覆盖水 / 火 / 林 / 空气四类，且把与
「海浪」同属水系的「溪流」让出来。**这是对本条原注「顺序照抄原型」的推翻**，原因是没有
可抄的对象了。

## 5. 音频管线

### 5.1 产物

`assets/noise/{forest,fire,ocean,stream,wind}.m4a`，AAC-LC、单声道、22.05 kHz、80 kbps，
**合计 3.40 MB**。

| 文件 | 循环长度 | 响度 | 真峰 |
| --- | --- | --- | --- |
| `forest.m4a` | 75.0 s | −22.1 LUFS | −3.0 dBFS |
| `fire.m4a` | 71.0 s | −23.0 LUFS | −1.9 dBFS |
| `ocean.m4a` | 75.0 s | −22.2 LUFS | −2.8 dBFS |
| `stream.m4a` | 75.0 s | −22.1 LUFS | −3.0 dBFS |
| `wind.m4a` | 44.0 s | −22.3 LUFS | −5.2 dBFS |

响度跨度 **0.9 LU**（原素材跨度是 14 LU，−20.6 ~ −34.4）。真峰全部 ≤ −1.9 dBFS，无削波。

### 5.2 生成配方（`tool/generate_noise_assets.dart`）

每条素材走同一条 ffmpeg 滤镜链，**全是已实测跑通的命令**，不是纸面设计：

```
atrim=0:{L+2}, asetpts=N/SR/TB, aformat=channel_layouts=mono, aresample=22050,
loudnorm=I={目标}:TP=-3:LRA=11, asplit=3[m1][m2][m3];
  [m1]atrim=0:2,  asetpts=N/SR/TB, afade=t=out:st=0:d=2:curve=qsin [head];
  [m2]atrim={L}:{L+2}, asetpts=N/SR/TB, afade=t=in:st=0:d=2:curve=qsin [cont];
  [head][cont] amix=inputs=2:duration=longest:normalize=0 [blend];
  [m3]atrim=2:{L}, asetpts=N/SR/TB [body];
  [blend][body] concat=n=2:v=0:a=1 [out]
→ -c:a aac -b:a 80k -ar 22050 -ac 1
```

三处**必须照做、写错就静默出错的**细节，逐条记下：

1. **扇出必须显式 `asplit=3`。** 把 `loudnorm` 的输出直接写成三条分支（`[mono]atrim=…`）
   时，ffmpeg **不报错**，但响度归一**静默失效**——实测输出停在输入的 −35.6 LUFS。
   这是本次唯一一处「看起来对、听不出错、量一下才知道」的坑。
2. **接缝是「把循环点之后的延续折回开头」，不是「把尾巴淡入开头」。** 直接淡入头会把一个
   天然前驱是 `L−1` 的样本接到 `L+fade` 之后，要消除的那个阶跃仍在。滤镜链取自
   `_foldSeam` 的同一条思路：`cont` 段取的是 `[L, L+2)`，即循环点**之后**的延续。
3. **`loudnorm` 的 `TP` 要留 2 dB 余量给交叉淡化。** 等功率淡化叠加两路信号时峰值会抬升约
   1–2 dB。归一取 `TP=-3`，成品真峰才落在 −1.9 ~ −3.0；取 `TP=-1.5` 时成品会顶到 0 dBFS。

**循环长度** `L = min(75, floor(源时长) − 4)`，保证 `L+2 ≤ 源时长`（`wind` 只有 48.6 s，
故 L=44；`fire` 75.1 s，故 L=71）。75 s 是上限，不是硬需求。

**响度目标**：全局 `I=-22`；**`fire` 单独用 `I=-19`**。篝火的源里有一段近乎静音加一声
0 dBFS 的爆裂（峰均比 38.6 dB），动态归一对它**稳定欠冲约 2.9 LU**；按文件预补偿后落到
−23.0，与其他四条同量级。这是**按文件校准过的常数**，不是猜的。

**已知取舍（如实记）**：五条的峰均比天生不同（`wind` 17.6 dB、`ocean` 20.8、
`stream` 19.5、`forest` 25.4、`fire` 38.6），所以「响度完全相同」做不到。要把 `fire` 拉到
−22 需要约 20 dB 限幅，会把爆裂声压扁。现行做法取的是「响度差 ≤1 LU、动态保持原样」。

### 5.3 已核验的接缝连续性

成品解码后，循环点的样本阶跃全部落在该文件自身步进分布的 **p99 以内**——即听不出接缝：

| 文件 | 接缝阶跃 | 平均步进 | p99 步进 |
| --- | --- | --- | --- |
| `forest` | 2470 | — | 4031 |
| `fire` | 1632 | — | 5828 |
| `ocean` | 789 | — | 4208 |
| `stream` | 1532 | — | 4190 |
| `wind` | 122 | — | 1071 |

解码长度精确等于标称时长（75.000 / 71.000 / 44.000 s），说明 **AAC 的编码器 priming 被
`m4a` 的 edit list 正确裁掉了**，循环不会在接缝处多出一小段静音。`just_audio` 在 darwin 侧
用「预排下一个 item」实现 `LoopMode.one`（`AudioPlayer.m` 的 `lmLoopOne` 分支），是 AVQueuePlayer
的无缝衔接路径。

## 6. 实现改动

| 文件 | 动作 |
| --- | --- |
| `assets/noise/*.m4a`（5 个） | **新增**（3.40 MB） |
| `tool/generate_noise_assets.dart` | **新增**，按 §5.2 配方重新生成素材；`flutter test tool/…` 手动跑，不参与 `flutter test` |
| `pubspec.yaml` | 声明 `assets: - assets/noise/` |
| `lib/features/sleep/data/noise_synth.dart` | **删除**（整个 DSP 合成器） |
| `lib/features/sleep/data/noise_asset.dart` | **新增**：`enum NoiseKind` 5 条，带 `id` 与 `assetPath` |
| `lib/features/sleep/data/noise_player.dart` | **重写**：`setAsset()` 取代「合成 → 写临时文件 → 播放」；删掉 `_ensureFile` / `clearCache` / `compute` / `dart:io` |
| `lib/features/sleep/presentation/widgets/noise_controls.dart` | `kNoiseOptions` 重建为 5 条 |
| `lib/core/widgets/app_icons.dart` | 新增 `stream` / `wind` 两个图标 |
| `lib/features/sleep/presentation/sheets/noise_sheet.dart` | 改引用；格子宽度按 5 条分 |
| `lib/features/session/presentation/widgets/session_setup.dart` | `_quickIds` 改为新 id |
| `lib/features/settings/data/app_cache.dart` | 文档：临时目录里不再有白噪音 WAV，只剩导出副本 |
| `lib/app/noise_session.dart` | 仅换 import |

### 6.1 「清除缓存」的语义变化

偏差 #43 把「清除缓存」定义为「只删 `getTemporaryDirectory()` 下**可再生成的临时文件**」，
当时的具体内容是 8 个白噪音 WAV + 导出副本。换素材后**白噪音不再进临时目录**（它是打包资源，
删不掉也不该删），临时目录里只剩导出副本。

- `AppCache` 的实现**不变**（仍是「把临时目录清空」）——它删的仍然是「临时目录里的东西」，
  这条语义没变；
- 变的是**文档与用户可见的读数**：全新安装、没导出过时，占用读数为 0 B，这是**如实**的，
  不是 bug。README 与偏差 #43 的措辞要同步。

## 7. 不做的事

- **不给素材加署名页/来源页**（授权未确认，见 §3.1）。
- **不改数据库 schema**。`noiseId` 存的是字符串 id，旧会话里可能留着 `white` / `rain` 等
  已不存在的 id：`noise_session.dart` 冷启动对账**本就会清空** `noiseId`（它的语义是
  「选中**并正在播放**」，进程一重启就成了假值），而 `activeOption` 对未知 id 返回 `null`。
  两处都已有正确行为，无需迁移。
- **不改夜景场景表**（`night_scene.dart` 的 `NightScene` 与音效 id 无关，`ocean`/`rain`
  只是字符串巧合）。
- **不删 `noise_synth.dart` 之外的能力**；`AppIcons.rain` / `AppIcons.fan` 保留。

## 8. 对既有规格的推翻

| 既有条目 | 原裁定 | 现裁定 |
| --- | --- | --- |
| `2026-09-28-night-sleep-design.md` §8 偏差 #5 | 设备内实时合成 8 种噪音，**不打包任何第三方音频** | 打包 5 条实景录音，**删除合成器** |
| 同上 §8 偏差 #17 | 每条循环 20 秒，等功率交叉淡化 | 每条 44–75 秒，接缝同样是等功率交叉淡化（生成时烘焙进素材，不再运行时合成） |
| 同上 §8 偏差 #43 | 「清除缓存」删 8 个白噪音 WAV + 导出副本 | 「清除缓存」的语义不变，但临时目录里**只剩导出副本**；白噪音不再进临时目录 |
| 同上 §10 第 3 条 | 待用户提供素材或确认合成 | **部分落实**：素材已提供并使用；**授权仍待确认**，本条不关闭 |
| 同上 §9 测试矩阵「合成波形」一行 | 合成波形的 8 组断言 | **作废**（合成器已删），改为素材资产的静态断言 |

## 9. 测试矩阵

| 层 | 内容 | 状态 |
| --- | --- | --- |
| 单元 | 素材目录：5 条 `NoiseKind` 与 `kNoiseOptions` **一一对应**；每条 `assetPath` 指向仓库里**真实存在的文件**；文件头是合法 MPEG-4（`ftyp`），不是空壳；总占用落在合理区间 | 待写 |
| Widget | 音效面板：5 格、播放交接、停止、切换、失败如实报错、关闭释放；**宽屏下 5 格一行且不溢出**（同款变异验证：换回屏幕宽度必红） | 待改 |
| Widget | 常用白噪音四格是 `ocean/fire/forest/wind`，窄屏竖排 | 待改 |
| 集成（真机/真平台） | **打包的素材真的能被解码并起播**——widget 测试用假播放器，一步都走不到；这条是唯一覆盖 `setAsset` 的平台路径 | 待改 |
| 听感 | 五条素材的主观可用性、切换时响度是否可接受、循环点是否可闻 | **待人工核对** |

## 10. 尚待人工核对的项

1. **听感**：接缝是否真的听不出来（本规格只量了样本阶跃）、响度差 0.9 LU 在实机上是否可接受。
2. **授权**：发布前必须落实，见 §3.1。
3. **目视**：5 格新布局在 390 px 与 iPad 横屏下是否溢出（有几何断言，无截图）。
