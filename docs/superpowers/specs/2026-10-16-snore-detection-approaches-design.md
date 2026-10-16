# 鼾声 / 梦话检测：市面做法、开源方案与端侧可行性

日期：2026-10-16
状态：**调研，未定案。本文不含任何实现，也不改任何现有行为。**
上游规格：[2026-09-28-night-sleep-design.md](2026-09-28-night-sleep-design.md) §M3 第 3 条、
§8 偏差表 #57–#65；
[2026-10-14-night-clip-auto-analysis-design.md](2026-10-14-night-clip-auto-analysis-design.md) §七「未验证」；
[2026-10-03-night-audio-recording-design.md](2026-10-03-night-audio-recording-design.md)。

**本文的写法约定**（与总规格 §8 那条红线同源）：

- **每条结论后面跟出处链接。** 只认第一手来源——官方文档、模型卡、论文原文（arXiv / DOI /
  PubMed / Europe PMC 全文）、源码仓库、AudioSet 本体原文、许可证实文、官方 API 文档。
  技术博客、知乎 / CSDN、营销页**一律不作为结论依据**。
- 凡是我**没能抓到原文**、只有搜索摘要的，一律显式标为「**二手来源，未核到第一手**」。
- **「我的推断」单独成句并标记。** 不写「某 App 大概是用 XXX 做的」这种话——查不到就写
  「查不到公开依据」。

## 一、问题与现状

### 1.1 现在的判定是什么

会话期间按振幅把 16 kHz 单声道 PCM 切成片段（一条片段一个 WAV），然后在本机用**一组写死的
声学阈值**判每一段是不是「鼾声 / 梦话」。逐帧（1024 点、Hann 窗、hop 512）算四类特征——
20–300 Hz 低频能量占比 `lowRatio`、谱质心 `spectralCentroid`、40–320 Hz 归一化自相关的
周期性 `pitchStrength`、最强谱单音占比 `spectralPeakShare`——再用 1200 ms 窗口、300 ms 步进
滑动，找**持续 ≥ 2500 ms** 的同类窗口事件。参数与理由逐条写在
[`2026-10-14-night-clip-auto-analysis-design.md`](2026-10-14-night-clip-auto-analysis-design.md)
§三，源码在 `lib/features/sleep/domain/clip_analysis.dart`。

### 1.2 实测结果：它没用

| 量到的东西 | 读数 | 出处 |
| --- | --- | --- |
| 19 段带人工标注的真机片段上，鼾声召回 | **0%**（2 段被确认为鼾声的片段全被漏掉） | [自动分析规格](2026-10-14-night-clip-auto-analysis-design.md) §五、§七·1 |
| 同一批上的覆盖率 / 开口内准确率 | 覆盖 **5%** / 准确率 **0%** | 同上 §五 |
| 10-16 那一晚 27 段真实睡眠录音 | **27 段全部弃权**（`analysis_status` 全是 `analysed`，0 条 `pending` / 0 条 `failed`） | [验证记录 v3.35](../../verification-log.md) §一 |
| 其中**整段短于 2500 ms 时长门槛**的段 | **17 / 27**——这些段无论特征多像都拿不到标签 | 同上；自动分析规格 §七·11 |

四条互相独立的技术路线（频谱形状 / 背景前景分离 / 时间结构 / 起振快慢）都已经量过，
**全部不成立**；最刺眼的一条是使用方标为「打鼾」的那段与他 17 秒后标为「杂音」的
（划桌子 + 拍手）那段，在 11 个特征上几乎逐项重合
（[自动分析规格](2026-10-14-night-clip-auto-analysis-design.md) §七·1）。

用户的原话是：**「那你这识别算法有啥用呢 一晚上的真实睡眠数据一个识别不出来 你去看看市面上
那些睡眠软件都是怎么识别的 看看有啥通用的开源方案吗」**。本文就是回答这三个问题。

### 1.3 本项目自己的数据约束（后面每一节都要用到）

| 事实 | 数 |
| --- | --- |
| 真实可用的标注 | **只有一种**：用户听完整段之后给**整段**打一个标签（鼾声 / 梦话 / 杂音） |
| 标注粒度 | **clip 级**，**没有逐秒 / 逐帧标注** |
| 已有标注量 | 2026-10-15 那次评测用的是 **19 段**子集（其中确认的**鼾声 2 段**，且这 2 段声学特征互相打架）。**磁盘上现在那份标注已经扩到 47 段，其中鼾声 3 段**——逐段量过，见 §4.4 |
| 未标注 | 10-16 那一晚 **27 段从来没标注过** |
| 片段长度 | 一晚的声响被切成 1–3 秒的碎片（切片在跌到 −45 dBFS 后 2 秒收尾），**比 ESC-50 的标准输入 5 秒还短** |
| 采样率 | 16 kHz 单声道 |

**「没有逐秒标注」这件事的严重性，取决于下游用哪种做法**——第四节会给出第一手依据说明
为什么它把「训一个自己的模型」这条路基本堵死。

## 二、市面产品怎么做的

### 2.1 先说结论

三条：

1. **有三家的做法能查到第一手依据**，而且**走的是学习模型，不是手写阈值**：
   **Sleep as Android 的官方文档明确写了「用 CNN」**、**SnoreLab 的 BreathFlow 写了
   「acoustic imaging + machine learning，380 晚睡眠实验室数据」**、
   **Fitbit 在专利里写了「MFCC + 机器学习模型」**。
2. **端侧是主流，而且多数明说。** SnoreLab、Sleep Cycle、Sensory、Pillow 都在官方页面
   写了端侧或「录音不上传」。
3. **一个对本项目特别刺眼的对照**：**国产三家（蜗牛睡眠 / 小米 / 华为）能查到的中文专利，
   全是信号处理启发式，没有一家是深度学习**——**而蜗牛睡眠那条专利的路线
   （噪声估计 + 端点检测 + 时频能量欧氏距离比阈值）跟本项目现在这套写死阈值几乎是同源**。

本节把「声称」与「依据」分列，**没有依据的格子写「查不到公开依据」，不写猜测**：

> 本文不写「某 App 大概是用 XXX 做的」。查不到就写查不到。

### 2.2 一张表

| 产品 | 它**声称**什么（官方原文） | 有无公开技术依据 | 端侧还是云端 | 依据链接 |
| --- | --- | --- | --- | --- |
| **Sleep as Android**（Urbandroid） | 官方文档原文：**"Sleep as Android uses Convolutional Neural Networks (CNNs), a form of artificial intelligence trained on thousands of real-world sound samples."**；识别五类：**Snoring / Sleep Talk / Sickness（咳嗽喷嚏）/ Baby Crying / Laughter** | **有，而且最明确**（直接写了模型类型是 CNN、训练于数千条真实样本）；**但架构、数据、权重都不公开** | **官方未声明**（只说辨认 "on your phone"）。**App 与模型都不开源**：Urbandroid 的 GitHub 组织里**没有任何声音分类/神经网络仓库** | [Sound recognition 官方文档](https://sleep.urbandroid.org/docs/sleep/sound_recognition.html)、[GitHub 组织](https://github.com/urbandroid-team) |
| **SnoreLab** | 官方 FAQ 原文：**"The snoring detection happens on your device and does not require internet connection."**；**"audio recordings made by the app are saved locally on your device and are not uploaded to a server without your permission"**；官方自认 **"we cannot guarantee the accuracy of data"**。BreathFlow（新功能）= **"combines acoustic imaging with machine learning"**、**"developed using 380 nights of gold-standard sleep lab reference data"**、**"The model runs entirely on the user's device, without requiring an internet connection"** | **有，但只到方法层**：acoustic imaging + machine learning + 380 晚实验室数据。**没有架构、没有论文、没有数据集**。注意主打功能 Snore Score 本身仍只说 "measurement algorithms" | **端侧，官方明说**（"on your device"/"entirely on the user's device"）；云端只用于账号同步与可选备份 | [FAQ](https://www.snorelab.com/faq/)、[BreathFlow 页](https://www.snorelab.com/breathing) |
| **Sleep Cycle**（含对外授权的 Sleep SDK） | 官方帮助页原文：**"Any sounds recorded are stored locally on your device and are never uploaded externally."**；"Who's Snoring" 功能 **"With a bit of input from you as a user and a little bit of time for the machine learning algorithm"**（**用户手动打标「是我 / 不是我」后由 ML 学**）。SDK 页原文：输出 **"breathing, snoring, coughing and movements"**、**"AI-driven sleep analysis trained on millions of nights"** | **只有一句 "machine learning algorithm"**，之后无任何细节。**官网把技术依据指向专利 `US8493220`**，但那条专利（NORTHCUBE AB 名下，2008 年申请）讲的是**择时唤醒**，**不是鼾声分类** | **录音明确端侧、明确不上传**；**但「分析」在哪跑，官方从未声明**——这一点是空白，不是端侧 | [麦克风权限](https://support.sleepcycle.com/hc/en-us/articles/207392665)、[Who's Snoring](https://support.sleepcycle.com/hc/en-us/articles/9189599693074)、[How it works](https://www.sleepcycle.com/how-it-works/)、[Sleep SDK](https://sleepcycle.com/partnerships/sleep-sdk) |
| **Google Health / Fitbit** | 官方产品文档**只把 "Snoring and sound events" 列在 "Snore and noise detection" 下，没有任何原理解释**。Pixel 的帮助页写 **"The Digital Wellbeing app is not intended to be used for medical purposes."** | **产品文档里没有**。**唯一的技术依据是专利** `US20200383633A1`（授权号 `US11793453B2`，受让人 Fitbit LLC，优先权 2019-06-04）：音频切帧 → **"mel-frequency cepstral coefficients (MFCCs)"** → **"a machine learning model"**；把音频与 **PPG / 加速计 / BCG / ECG / ICG** 导出的**呼吸相位**做相关性匹配，**判断这个鼾声是不是佩戴者本人**的（解决「分不清是本人还是同床者/宠物」）；**"automatically discard audio data as soon as the audio data is categorized"** | **查不到产品层声明**；专利层面写的是**实时分析、分完即删**，并明说**可端侧也可服务器**（"can be implemented by the client device 214 and/or the server 216"） | [数据清单](https://support.google.com/product-documentation/answer/14811751?hl=en)、[专利](https://patents.google.com/patent/US20200383633A1/en)、[Pixel 帮助](https://support.google.com/android/answer/9887159?hl=en) |
| **Apple**（iPhone + Apple Watch） | **不用麦克风、不听声音**：官方支持文档写 **"uses the accelerometer to look for breathing disturbances while you sleep"**，结果分 "Elevated" / "Not Elevated"，需 30 天内至少 10 晚，**每 30 天评估一次**；免责 **"is not intended to diagnose, treat, or aid in the management of sleep apnea"**（该页为抓取转述） | **零公开**：没有模型、算法或训练数据的任何说明 | 与音频路线无关 | [Apple 支持文档 120031](https://support.apple.com/en-us/120031)、[Feature Availability](https://www.apple.com/watchos/feature-availability/) |
| **Withings**（Sleep / Sleep Analyzer / Sleep Rx） | 官方产品页：**"Sound sensor: identifies audio signals specific to snoring and breathing disturbances."**；官方 FAQ 原文：**"Sleep Analyzer has been clinically validated by the CE notified body and is considered as a medical device."**、**"Its algorithm is powerful and has been trained and validated on a large cohort of apneic patients at Hôpital Béclère (France)."** | **有产品级描述**（气动传感器 + 声学传感器 + ballistocardiography + 临床队列训练验证）；**没有模型架构、没有论文** | **未明说**；只说「同步前本地存、Withings 账号提供在线存储」 | [产品页](https://www.withings.com/us/en/sleep-analyzer)、[官方 FAQ](https://support.withings.com/hc/en-us/articles/360000038707) |
| **Sensory SoundID**（声音检测 SDK 供应商） | 16 种预置声音，**"Includes alarms, sirens, knocking, glass break, baby cry, coughing, snoring, doorbells, and more."** | **查不到**（无论文、无模型卡）；页面只写「多级检测 + 可选的神经二级校验」 | 声称**全端侧**：**"All detection and classification happen fully on-device, keeping audio private."**（平台列出 Linux/Android/Windows/embedded ARM，**未列 iOS**） | [Sensory SoundID](https://sensory.com/product/ai-sound-id/) |
| **Pillow**（Neybox） | 官网把 **"audio recordings and heart rate analysis"** 列为分析输入；**"Pillow uses on-device intelligence for its analysis and other personalised features."**；**注意：官网通篇没有提 snore detection** | **无** | 只说整体分析走端侧；**对音频文件没有专门的端侧 / 上传声明** | [pillow.app](https://pillow.app/) |
| **蜗牛睡眠**（赛博龙科技（北京）有限公司） | **没有可抓取的官方技术文档**（官网抓取失败）；App Store 文案自称「基于自主 AI 算法及多项国家发明专利」——**营销自述，不作为技术依据** | **有中文专利（一手）**：`CN106691382A`「一种基于时频相似性的鼾声检测方法及装置」——**"对鼾声音频信号进行噪声估计后利用端点检测技术进行有声片段提取"**、**"计算当前有声片段与上一个有声片段的时域能量或频域能量的欧式距离，将欧式距离与阈值进行比较"**。**这是信号处理启发式，不是神经网络**；专利还把「不依赖标注良好的鼾声数据」当优点写 | **查不到** | [CN106691382A](https://patents.google.com/patent/CN106691382A/zh)、[CN111166297A](https://patents.google.com/patent/CN111166297A/zh) |
| **小米健康 / 小米运动健康** | 官方隐私页原文：**"为了向您提供鼾声梦话检测的服务，我们需要向您申请开启录音权限，同意权限后收集您在睡眠期间产生的音频信息"**；**"我们不会读取您的音频内容，仅会帮您记录"** | **有中文专利**：`CN105708609A`——麦克风取鼾声强度等级 → 定振动等级 → 振动**抑制打鼾**。**这是干预专利，不是识别模型** | **查不到**（隐私页只说采集与权限，没说端侧还是上传） | [小米隐私](https://privacy.mi.com/MiHealth_SensiveInfo/zh_CN/)、[CN105708609A](https://patents.google.com/patent/CN105708609A/zh) |
| **华为运动健康** | 官方隐私声明原文：麦克风用于**"记录睡眠期间的梦话、鼾声、环境噪音数据"** | **有中文专利**：`CN113303758A`「鼾声信号处理方法及电子设备」——**自适应噪声滤波 + 参考信号**（用呼吸节奏特征 / 预设鼾声特征当参考信号做噪声过滤），再用**鼾声声纹**与**节奏**（鼾声周期、由小到大的变化速率等）做匹配，**用于多人场景下区分是谁在打鼾**。**信号处理，不是神经网络** | **查不到**（隐私声明未说是否上传） | [华为隐私声明](https://privacy-drcn.dbankcdn.cn/agreement/scope/huawei/health/privacy-statement/cn_b0_20260907_0/default/privacy-statement-zh-cn.htm)、[CN113303758A](https://patents.google.com/patent/CN113303758A/zh) |
| **SleepWatch**（Bodymatter, Inc） | 官方论文原文：算法 **"using a deep neural net model trained on over 60,000 individually validated, real-world snore and nonsnore sounds"** | **有同行评议论文**（JMIR Formative Research 2025）：sensitivity **86.3%**、specificity **99.5%**、accuracy **95.2%**。**但注意测试口径**：36 个**合成**文件 + 9 个非鼾声文件，是 bench study，不是整夜真实录音 | **查不到**：论文**没有说**推理在端侧还是云端 | [DOI 10.2196/67861](https://doi.org/10.2196/67861)、[PMC11970566](https://pmc.ncbi.nlm.nih.gov/articles/PMC11970566/) |
| **SnoreLab / Anti Snore Solution / Sleep Cycle Alarm 三款手机 App** | 不说技术；**但有人拿整夜 PSG 验过它们** | **有第三方同行评议验证**：60 名受试者整夜 PSG + 三部同款手机同时跑三个 App。原文结论：三款与 PSG 的鼾声计数**显著相关**，**ASS 一致性最好**（"with ASS showing good agreement with snore counts"）；SnoreLab 的 Snore Score 与 Sleep Cycle 的 Sleep Quality 与 PSG 的 lnAHI 显著相关 | — | [DOI 10.2147/nss.s433351](https://doi.org/10.2147/nss.s433351)、[PMC11127649](https://pmc.ncbi.nlm.nih.gov/articles/PMC11127649/) |

### 2.3 四条从这个表里读出来的东西

**一、有公开依据的三家，走的都是学习模型，不是手写阈值。**
**Sleep as Android 最干脆——官方文档直接写 "uses Convolutional Neural Networks (CNNs)"**；
SnoreLab 的 BreathFlow 是 "acoustic imaging + machine learning"；
Fitbit 在专利里写了 "MFCC + a machine learning model"。
**本项目现在这套「低频占比 + 谱质心 + 周期性 + 最强单音」的写死阈值，没有一家公开产品这么描述。**

**二、但「阈值法」并非没有先例——只是先例在国产厂商的专利里。**
**蜗牛睡眠的 `CN106691382A` 就是「噪声估计 + 端点检测 + 时频能量欧氏距离比阈值」**，
而且它把「不依赖人工标注数据」当优点写进摘要。**这与本项目的现状几乎是同一条路线。**
小米 `CN105708609A` 与华为 `CN113303758A` 同样是信号处理（滤波、参考信号、声纹与节奏匹配），
**没有一条是深度学习**。

> **这条对照的价值在于：它同时说明了两件事。**
> ① 阈值法**在工业界真的有人用**，本项目走到这一步不是荒唐；
> ② **但没有任何一家公开过召回率 / 准确率**——**从这些一手材料里借不到任何可复用的评估结论。**
> 本项目「用数字收账」的要求，在这些专利面前依然只能靠自己那 47 段来满足。

**三、端侧是主流，不是例外。** SnoreLab（"on your device"、"entirely on the user's device"）、
Sleep Cycle（"never uploaded externally"）、Sensory（"fully on-device"）、Pillow（"on-device
intelligence"）都在官方页面明说端侧。**这跟本项目「本地优先」的立场同向，不是负担。**

**四、训练数据的量级完全不在一个档上。** 两个可以引用的数字：
SleepWatch 论文说 **60,000+ 条**逐条人工确认的样本；Sleep as Android 说 **"thousands of
real-world sound samples"**。对照本项目手里的 **3 条鼾声**——这是 §四与 §六 的立论基础。

### 2.4 监管口径

依据是 FDA 的 **General Wellness: Policy for Low Risk Devices** 指导原则
（[指导原则页](https://www.fda.gov/regulatory-information/search-fda-guidance-documents/general-wellness-policy-low-risk-devices)、
[正文 PDF](https://www.fda.gov/media/90652/download)）。**睡眠被明确列进 wellness 用途**：

> "Claims to promote **sleep management**, such as to **track sleep trends**"

**边界原文**：一旦变成「用于医学或临床目的」就不是 wellness 了——

> "Products are not general wellness products when they are intended to **measure, estimate, or
> report physiologic values for medical or clinical purposes, including screening, diagnosis,
> monitoring, alerting, or management of a disease or condition.**"

**这条边界在现实中的落点**：靠**加速度计**的 Apple 与靠**气动 + 声学传感器**的 Withings
都去拿了许可——**走的是传统 510(k)，不是 De Novo**：

| 产品 | FDA 编号 | 产品代码 / 法规号 | 决定日 |
| --- | --- | --- | --- |
| Apple「Sleep Apnea Notification Feature」 | **K240929** | QZW / 868.2378 | 2024-09-13 |
| Withings「Sleep Rx」 | **K231667**（Substantially Equivalent） | MNR / 868.2375 | 2024-09-06 |
| （三星先拿到的 De Novo） | **DEN230041** | QZW / 868.2378 | 2024-02-06 |

出处：[K240929](https://www.accessdata.fda.gov/scripts/cdrh/cfdocs/cfpmn/pmn.cfm?ID=K240929)、
[K231667](https://www.accessdata.fda.gov/scripts/cdrh/cfdocs/cfpmn/pmn.cfm?ID=K231667)、
[DEN230041](https://www.accessdata.fda.gov/scripts/cdrh/cfdocs/cfPMN/denovo.cfm?ID=DEN230041)。

**顺带记一条与界面文案有关的**：2026 版指导原则对「通知类功能」给了明确的允许边界——
提示「可以找医生评估」**不必然**使它变成器械，前提是**不点名具体疾病、不说结果「异常/病理」、
不给临床阈值、不做持续告警**。

**对本项目的含义（推断）**：本应用只做「记录 + 回放 + 疑似判断」，**不宣称医学用途**，
位置与上面这些产品的 general wellness 一致，**不需要监管审批**。
**但要守住两条**：**不出现「睡眠呼吸暂停」这类病名**，**不给临床阈值或「临床级准确率」的说法**。

## 三、开源模型候选

### 3.1 一张表

| 模型 | 标签体系里有没有 snoring | 输入格式 | 体积（官方数字） | 许可证（代码 / 权重） | 商用允许？ | 依据 |
| --- | --- | --- | --- | --- | --- | --- |
| **YAMNet** | **有**。521 类，`Snoring` = **index 38**，mid `/m/01d3sd` | 16 kHz 单声道；STFT 25 ms 窗 / 10 ms hop；**64 mel（125–7500 Hz）**；log；0.96 s 一片 | `yamnet.h5` **15,296,092 B（≈14.6 MiB）**；MediaPipe 的 `yamnet.tflite` **4,126,810 B（≈3.9 MiB）** | 代码与权重均 **Apache-2.0** | **允许** | [官方 README](https://github.com/tensorflow/models/tree/master/research/audioset/yamnet)、[LICENSE](https://raw.githubusercontent.com/tensorflow/models/master/LICENSE) |
| **PANNs / CNN14** | **有**。AudioSet **527** 类 | 32 kHz（另有 **16 kHz 变体**），log-mel 1000×64，10 s 补齐 | `Cnn14_mAP=0.431.pth` **312 MiB**；`Cnn14_16k_mAP=0.438.pth` **≈342 MiB**；**80,753,615 参数** | 代码 **MIT**；权重 **CC-BY-4.0**（Zenodo record 3987831） | **允许**（需署名） | [仓库](https://github.com/qiuqiangkong/audioset_tagging_cnn)、[论文](https://arxiv.org/abs/1912.10211)、[Zenodo](https://zenodo.org/records/3987831) |
| **VGGish** | **不能直接判**：它只输出 **128 维 embedding，没有分类头** | 16 kHz，log-mel 96×64 | `vggish_model.ckpt` **291,108,469 B** | **Apache-2.0** | 允许 | [官方目录](https://github.com/tensorflow/models/tree/master/research/audioset/vggish) |
| **AST** | 有（527 类；HF 转换版 config 里 index **43** = `Snoring`） | 16 kHz，128 mel × 1024 帧 | `model.safetensors` **≈329 MiB**，86.3M 参数 | 代码 **BSD-3-Clause**；**原始权重许可未声明** | 代码允许；权重**未落第一手** | [仓库](https://github.com/YuanGongND/ast)、[HF 转换版](https://huggingface.co/MIT/ast-finetuned-audioset-12-12-0.447) |
| **BEATs** | 有 AudioSet 微调权重（527 类），**但文档未列出类名清单** | 16 kHz，128 维 mel，25 ms Povey 窗 / 10 ms hop | **文档未给** | 代码 **MIT**；**权重没有单独的许可声明** | 代码允许；**权重未落第一手** | [仓库](https://github.com/microsoft/unilm/tree/master/beats) |
| **CED** | 有（527 类，index **43** = `Snoring`） | 16 kHz，**64 维 mel** | **CED-Tiny 5.5M 参数**：`.pt` 22,132,196 B / **onnx 6,681,767 B**；CED-Base 86M ≈ 327 MiB | 代码 **GPL-3.0**；权重 **CC-BY-4.0**（Zenodo）/ HF 标 apache-2.0（**两处不一致**） | 权重允许；**代码是 GPL-3.0，传染性 copyleft** | [仓库](https://github.com/RicherMans/CED)、[HF](https://huggingface.co/mispeech/ced-tiny) |
| **MediaPipe AudioClassifier** | **是，它就是 YAMNet**。官方只列一个模型 **"Yamnet model (recommended)"**，输入 shape **1×15600**（≈0.975 s @16 kHz） | 同 YAMNet | `yamnet.tflite` **4,126,810 B** | 框架 **Apache-2.0**；**模型文件本身的许可官方未声明** | 框架允许；**模型文件许可未落第一手** | [官方任务页](https://developers.google.com/edge/mediapipe/solutions/audio/audio_classifier) |
| **Silero VAD** | **没有**。它只输出语音/非语音时间段，**不能判鼾声** | 8 kHz / 16 kHz | JIT 模型 **约 2 MB** | **MIT** | 允许（但用途不符） | [仓库](https://github.com/snakers4/silero-vad) |

### 3.2 AudioSet 本体里 snoring 的确切节点（本节最关键的一条）

这条是本文里**唯一一个「模型的分类体系里到底有没有鼾声」的确切答案**，
而且我是**直接解析官方 `ontology.json`** 得到的，不是转述：

```json
{ "id": "/m/0lyf6", "name": "Breathing",
  "child_ids": ["/m/07mzm6", "/m/01d3sd", "/m/07s0dtb", "/m/07pyy8b", "/m/07q0yl5"] }
```

| 项 | 值 |
| --- | --- |
| 显示名 | **`Snoring`** |
| 本体 id（mid） | **`/m/01d3sd`** |
| 定义（原文） | **"The sound resulting from obstructed respiratory airways during breathing while sleeping."** |
| 父节点链 | `Snoring` → **`Breathing` (`/m/0lyf6`)** → `Respiratory sounds` (`/m/09hlz4`) → `Human sounds` (`/m/0dgw9r`) |
| **同一父节点下的兄弟** | **`Wheeze` (`/m/07mzm6`)、`Gasp` (`/m/07s0dtb`)、`Pant` (`/m/07pyy8b`)、`Snort` (`/m/07q0yl5`)** |

出处：[ontology.json 原文](https://raw.githubusercontent.com/audioset/ontology/master/ontology.json)（本体共 **632** 个节点；
注意原文里**每个节点只有 `child_ids`，没有 `parent` 字段**——父子关系是单向声明的）。

**这两条推论直接决定模型会怎么错（推断，但依据在上表）**：

1. **模型最可能把鼾声与之混淆的，是同一父节点下的四个兄弟**——Wheeze / Gasp / Pant / Snort，
   它们全都是「呼吸类」。而 Cough / Sneeze / Sniff 在**上一层**（Respiratory sounds），相对更远。
2. **`Snoring` 是一个叶子节点、没有子类**——也就是说 AudioSet 对鼾声**不做任何细分**
   （不区分体位、不分软腭型/舌根型）。**这点对本项目是好消息**：我们只需要一个二元的
   「是/不是鼾声」，不需要 AudioSet 提供更细的标签。

### 3.3 YAMNet：一个 3.9 MiB 的模型，恰好吃 16 kHz

YAMNet 值得单独展开，因为它是**唯一一个「体积小 + 原生 16 kHz + 明确可商用」**的候选。
官方 README 原文：

> "All audio is resampled to **16 kHz mono**."；"a window size of **25 ms**, a window hop of
> **10 ms**, and a periodic Hann window"；"**64 mel bins covering the range 125-7500 Hz"；
> "log(mel-spectrum + 0.001)"；"framed into 50%-overlapping examples of **0.96 seconds**"。

- **每片输出 521 类分数 + 一个 1024 维 embedding。** 架构 MobileNetV1，
  **"3.7M weights"**、每 960 ms 帧 **"69.2M multiplies"**。
- **官方给出的精度**：AudioSet eval 集 20,366 段上，**balanced mAP 0.306**、d-prime 2.318、
  lwlrap 0.393（[README](https://github.com/tensorflow/models/tree/master/research/audioset/yamnet)）。
  **注意这是 521 类的平均数**——`Snoring` 作为长尾类，单类表现**官方没有给**。
- **一条对本项目很要命的硬约束（官方原文）**：
  **"you need at least 975 ms of input waveform to get the first frame of output scores."**
  —— **短于 0.975 秒的片段，YAMNet 一个分数都给不出来。**
  本项目本地那 47 段的**最短一条是 1.00 秒**，所以**全都勉强够**；但这条门槛意味着
  **不能把切片再调短**（而现在的切片正是 1–3 秒的碎片，见 §一）。
- **YAMNet 依赖 Keras 2，与 Keras 3 不兼容**（README 明说），这是工程上的一个已知摩擦。

**class map 里与鼾声相邻、对本项目有用的类**（我逐行解析
[`yamnet_class_map.csv`](https://raw.githubusercontent.com/tensorflow/models/master/research/audioset/yamnet/yamnet_class_map.csv)，共 521 类）：

| index | mid | 显示名 |
| --- | --- | --- |
| 0 | `/m/09x0r` | `Speech` |
| 24 | `/m/015lz1` | `Singing` |
| 32 | `/m/02fxyj` | `Humming` |
| 36 | `/m/0lyf6` | `Breathing` |
| 37 | `/m/07mzm6` | `Wheeze` |
| **38** | **`/m/01d3sd`** | **`Snoring`** |
| 39 | `/m/07s0dtb` | `Gasp` |
| 40 | `/m/07pyy8b` | `Pant` |
| 41 | `/m/07q0yl5` | `Snort` |

**这张表里藏着一条对本项目特别有价值的线索（推断）**：自动分析规格 §三·四记过，
用户的鼾声与**哼歌**在「低频 + 周期」上分不开，那是当时唯一想出来的补救方向；
而 YAMNet 的分类体系里 **`Singing`(24) / `Humming`(32) 与 `Snoring`(38) 是三个分开的类**。
「乐音 vs 粗糙声」这条本项目用 `spectralPeakShare` 手写阈值去逼近的区分，
在一个学过 521 类的模型里是**内建的**。**这是推断——它是否真的分得开，只有拿真实片段跑一次才知道。**

> 顺带记一条 527 → 521 的差异：AudioSet 本体是 **527** 类，YAMNet 只输出 **521** 类。
> 官方 README 说明是「按公平性审查的建议删掉了 6 个」，删的是
> **gendered Speech/Singing、Battle cry、Funny music**——**`Snoring` 不在被删之列**。
> 而 PANNs / AST / CED 用的是 **527** 类，所以它们在 CSV 里的 index 与 YAMNet 对不上
> （同一个 `Snoring`，YAMNet 是 38、AST/CED 是 43）。**按 mid（`/m/01d3sd`）查，不要按 index 查。**

### 3.4 一个必须说清楚的分野：能「打标签」不等于能「定位到第几秒」

上表里 **PANNs 有 `DecisionLevelMax/Avg/Att` 这几个逐帧输出的版本**（README：
"can be used for **frame-wise sound event detection**"），这是少数能给出时间边界的。
其余（YAMNet、CED）主要是**片级**输出。

而 §四会说明：**只用片级标签训出来的模型，定位能力差是公认的**。
**所以选型时要先定「要不要区间」**——本项目现在的界面是要区间的
（[自动分析规格](2026-10-14-night-clip-auto-analysis-design.md) §六）。

### 3.5 「直接输出鼾声」的现成权重：**基本不可用**

我按「有没有人已经微调好一个专门判鼾声的权重」逐个核过，结论是**几乎没有能用的**：

| 资源 | 许可证 | 判断 |
| --- | --- | --- |
| `HypermindLabs/SnoreNetV1`（HF） | **cc-by-nc-nd-4.0** | **禁商用 + 禁演绎**，且 README 为空 |
| `janong24/snoringDetectorAI`（HF） | **agpl-3.0** | 强传染 copyleft；权重 **≈3 GB**；README 只有 134 B |
| `CXDJY/snore_ai`（HF） | **未声明** | 无许可证 → **不能用** |

依据：[HF 模型页](https://huggingface.co/HypermindLabs/SnoreNetV1)、
[janong24/snoringDetectorAI](https://huggingface.co/janong24/snoringDetectorAI)、
[CXDJY/snore_ai](https://huggingface.co/CXDJY/snore_ai)。

**GitHub 上的鼾声项目同样如此**（按 star 数）：

| 仓库 | ★ | 许可证 | 能不能用 |
| --- | --- | --- | --- |
| `timqian/snoreman` | 77 | **CC BY-NC-SA 4.0** | ❌ 禁商用；而且它是**纯启发式 DSP**，不是 ML |
| `adrianagaler/Snoring-Detection` | 73 | **无** | ❌ 无许可证 |
| `mywang44/snoring_net` | 39 | **无** | ❌ |
| `elgrande73/FOSS-snore-detector-android-app` | 22 | Apache-2.0 | ⚠️ 有许可证，但**同样是手写 DSP 阈值**（RMS dB / ZCR / 频带能量），**没有模型** |
| `somnisense/audio-sleep-cnn-baselines` | 5 | MIT（"Patent rights are not granted"） | ⚠️ **只给方法、不分发权重与数据** |
| `rafazafar/flutter_snore_detection` | 3 | **MIT** | ⚠️ **唯一一个「Flutter 包 + 自带权重 + 明确 MIT」**，见 §五；但 3 star、数据溯源不清 |

出处：各仓库 GitHub 页面（上表逐条核过 license 字段）。

**结论**：**没有可以直接拿来用的、可商用的「鼾声专用」开源权重。**
能用的只有**通用 AudioSet 模型**（YAMNet / PANNs / CED / AST），它们把 `Snoring` 当成
521/527 类里的一类——**这一类的权重有多大、在真实鼾声上表现如何，是未知的**。

### 3.6 PanNs / AST / BEATs / VGGish 各自的问题

- **PANNs CNN14**：`mAP 0.431`（[论文](https://arxiv.org/abs/1912.10211)），
  但**浮点权重 312 MiB**，且它的 log-mel 是 **32 kHz**（有 16 kHz 变体但要另下）。
  **这是「精度换体积」那一端的极端**——见 §五 里它在手机上的实测数字。
- **AST**：`0.485 mAP`（[仓库](https://github.com/YuanGongND/ast)），
  但 **86.3M 参数 / ≈329 MiB**，且是 **16 kHz + 128 mel × 1024 帧**输入，
  **原始权重的许可没有声明**。
- **BEATs**：代码 MIT，但**权重没有任何许可声明**，**体积也没给**。
  **许可未落第一手的东西不许进发布版本**——这条按本仓的规矩直接排除。
- **VGGish**：**它不能直接判鼾声**——官方仓库只提供 **128 维 embedding**，
  分类器要自己训。**把它和 YAMNet 混为一谈是错的。**
  网上常见的「VGGish 有 527 类」是把 AudioSet 的标签体系错记到它头上。

## 四、数据集

### 4.1 「片段级弱标注」在学界是标准做法，名字叫 weak label

这不是本项目的土办法，DCASE（声学事件检测与分类的国际评测）有专门的任务定义。官方任务页原文：

> "detection of sound events using real data either **weakly labeled** or unlabeled and simulated
> data that is strongly labeled"
> …… "Audioset provides annotations at **clip level (without time boundaries for the events)**."
> → "the original annotations are considered as **weak labels**."
> —— [DCASE 2019 Task 4](https://dcase.community/challenge2019/task-sound-event-detection-in-domestic-environments)

**本仓的标注形态（整段一个标签、没有时间边界）正是 DCASE 意义上的 weak label。**
方向是对的，**差的只是量**——而量的差距是数量级级别的：

| 量级 | 数 | 出处 |
| --- | --- | --- |
| DCASE 官方弱标注训练集 | **1,578 条 / 10 类 ≈ 158 条/类**，另配 **14,412 条无标注**做半监督 | [DCASE 2019 Task 4](https://dcase.community/challenge2019/task-sound-event-detection-in-domestic-environments)、[DCASE 2020 baseline README](https://raw.githubusercontent.com/turpaultn/dcase20_task4/master/README.md) |
| 低资源弱标注 SED 的先例（NIPS4B 2013） | **687 条录音、87 类、每类 7–20 条正例、总训练时长不到 1 小时** | [arXiv:1807.06972](https://arxiv.org/abs/1807.06972) |
| **本仓** | **47 段**（34 杂音 / 10 梦话 / **3 鼾声**），**总时长 223.1 秒** | 本机实测，见 §4.4 |

DCASE 官方对弱标注的可靠性还有一句明说：

> "The weak annotations have been verified manually for a **small subset** of the training set."
> —— [DCASE 2020 baseline README](https://raw.githubusercontent.com/turpaultn/dcase20_task4/master/README.md)

**DCASE 的基线分数也值得对着看**：event-based F-score 2019 年是 **23.7%**，2020 年是
**Macro F 34.8% / PSDS 60.0%**（同上两处）。**这是一个有上万条标注、十类的标准任务上的分数。**
拿它当参照系，「换一个模型就能判准鼾声」这个预期本身就不成立。

### 4.2 「每类至少要多少条」——**没有任何第一手依据给出这个下限**

我把 DCASE 官方任务页、DCASE 基线 README、两篇弱标注 / 低资源论文都过了一遍，
**没有一处给出「每类至少 N 条」的硬下限**。这一条要如实写成**否定结论**：

- **最接近的一手依据**：小样本迁移学习那一支扫的是「**1 to 100 labeled examples per class**」，
  结论是 "transfer learning is a powerful strategy in such scenarios"
  —— [arXiv:1810.10274](https://arxiv.org/abs/1810.10274)（Pons, Serrà, Serra,
  *Training neural audio classifiers with few data*）。
  **注意它的前提**：有一个大规模预训练底座可以微调。它**没有**说低于多少条就训不动。
- **研究前沿的下限长什么样**：DCASE 2022 Task 5 是 **5-shot** 任务，官方基线
  **prototypical network 只有 29.59% F-measure**，template matching 4.28%
  —— [官方任务页](https://dcase.community/challenge2022/task-few-shot-bioacoustic-event-detection)。
  「每类 5 条」是**研究前沿**，跑出来的分数是 29.59%。

**我的推断（无第一手依据）**：上面这些数字方向一致地把「每类 2 条能训出可用模型」排除掉，
但「够不够」这个判断本身**没有一篇论文给过阈值**，所以它是推断，不是结论。

### 4.3 一个更硬的、可以查证的问题：模型体积与数据量

见 §3（开源模型候选）与 §6（可落地的路子）。这里只记一条口径问题：

**只用 clip 级标签训出来的模型，时间定位（哪一秒到哪一秒）能力差是公认的**，而且是 2025 年
仍在攻的活跃问题——FPSL 那篇的动机原文就是 "overcome the lack of temporal information in
WSSED by generating pseudo strong labels from frame-level predictions"，它相对 CRNN 基线的
PSDS1 提升是 4.9%（DCASE2017）/ 7.6%（DCASE2018）/ 1.8%（UrbanSED）
—— [arXiv:2501.03740](https://arxiv.org/abs/2501.03740)。

**对本项目的含义**：即使勉强训出「这一段是不是鼾声」，也**不能指望它给出「鼾声从第几秒到
第几秒」**。而现有界面（[自动分析规格](2026-10-14-night-clip-auto-analysis-design.md) §六）
恰恰把「事件区间」当成判定的一部分——**这两件事对不上**。

### 4.4 本机实测：这个仓库手上到底有多少原料

用 `.tmp-device/labels.txt`（从真机拉回的标注）与 `.tmp-device/clips/`（47 个 WAV）
逐段量，**采样率全是 16 kHz 单声道 16-bit**：

| 类别 | 段数 | 总时长 | 平均段长 |
| --- | --- | --- | --- |
| 杂音 | 34 | 117.1 s | 3.4 s |
| 梦话 | 10 | 62.3 s | 6.2 s |
| **鼾声** | **3** | **43.7 s** | 14.6 s |
| **合计** | **47** | **223.1 s（3.7 分钟）** | 4.75 s（中位数 2.80 s） |

三条鼾声片段的 id：`clip-1792068011616978` / `clip-1792070577154873` / `clip-1792072559442394`。

三条硬事实：

1. **正样本只有 3 条、43.7 秒。** 拿它做留一法，测试点最多 3 个——**任何在这个量级上报出来的
   准确率 / 召回率都不是证据**，置信区间比估计值还大。
2. **全部真实音频加起来 3.7 分钟。** 对照 §3：AudioSet 的 Snoring 类单类就是 **6.5 小时**。
3. **20 / 47 段短于 2500 ms**（本项目判定门槛）。而标准训练输入是
   **ESC-50 每条 5 秒**（[README](https://github.com/karolpiczak/ESC-50)）、
   **AudioSet 每条 10 秒**（[官方页](https://research.google.com/audioset/)）——
   **本仓的典型片段比这两个标准输入都短**。「短输入会掉多少点」这件事，
   **我没有找到第一手依据**。

### 4.5 可用的公开数据集与它们的许可证

| 数据集 | 规模（含 snoring） | 标注粒度 | 采样率 / 段长 | 许可证（**能否商用**） | 依据 |
| --- | --- | --- | --- | --- | --- |
| **ESC-50** | 2,000 clip / 50 类 × 40；**snoring 40 条**（同类还有 Breathing 40 条） | clip 级 | 44.1 kHz / **5 s** | **CC BY-NC 3.0 → 禁止商用**。ESC-10 子集是 CC BY 3.0（可商用）；逐条 clip 许可混杂 CC0 / CC-BY / CC-BY-NC / CC-Sampling+ | [README](https://github.com/karolpiczak/ESC-50)、[LICENSE 正文](https://raw.githubusercontent.com/karolpiczak/ESC-50/master/LICENSE) |
| **AudioSet** | 2,084,320 条 × 10 s / 527 类；**Snoring 2,334 视频 / 6.5 小时**（eval 60 / balanced train 60 / unbalanced train 2,214） | clip 级（10 秒内「存在」，**无时间边界**） | 16 kHz 特征 / 10 s | **labels: CC BY 4.0（可商用）**；**ontology: CC BY-SA 4.0**；**音频只有 YouTube ID，本身不在许可内** | [dataset 统计页](https://research.google.com/audioset/dataset/snoring.html)、[download 页](https://research.google.com/audioset/download.html) |
| **MPSSC**（Munich-Passau Snore Sound Corpus） | 828 段鼾声 / 219 人，4 类 VOTE | event 级（**段内无逐秒**） | 16 kHz / 平均约 1.5 s | **未核到许可证原文**；论文措辞是 "for scientific purposes" → **大概率仅限科研** | DOI [10.1016/j.compbiomed.2018.01.007](https://doi.org/10.1016/j.compbiomed.2018.01.007)（**正文未抓到，统计数字属二手**） |
| Kaggle「Snoring」 | 1,000 条 × 1 s（500/500） | clip 级二分类 | 未核到 | **页面标 "Unknown"** → 授权不明 | [Kaggle 页](https://www.kaggle.com/datasets/tareqkhanemu/snoring)（页面 JS 渲染，**正文未核到**） |

**对本项目最要紧的一条**：**ESC-50 是 BY-NC，不能商用**——它撞的正是本项目
「助眠音效素材可商用授权未落实」那同一个坑（`pubspec.yaml` 里那条注释、
[夜间音效规格](2026-10-03-noise-real-recordings-design.md) §3.1）。**要商用，ESC-50 这条路
只能取其中被标为 `[CC0]` / `[CC-BY]` 的那部分重新打包，或者干脆不用。**
AudioSet 的**标注**可商用，但**音频要自己去 YouTube 下**，且会随时间流失
（「大量视频已下架」这条**我没找到官方明文，属二手，未核到第一手**）。

**MPSSC 是唯一一个「专门为鼾声做的」公开语料**，但它的许可证我**没能核到原文**——
三个一手链接全部抓取失败（PDF 二进制 / 403 / Cookie 墙）。**「能不能商用」无法判定**，
**这一条不解决就不能用**。

## 五、端侧可行性

### 5.1 一条决定性的技术事实：Google 那个 `yamnet.tflite` 吃原始波形

这是本次调研**最有用的一条发现**，而且它是**直接从模型文件本身解出来的**，不是文档转述：

把 MediaPipe 官方发布的 `yamnet.tflite`（4,126,810 字节）下载下来、**用 flatbuffer 解码它的
`operator_codes` 与 `subgraph`**，得到的结构是：

| 项 | 值 |
| --- | --- |
| 输入张量 | 名字 **`waveform_binary`**，shape **`[15600]`**，float32（＝ **0.975 s @ 16 kHz 原始波形**） |
| 输出张量 | `tower0/network/layer32/final_output`，shape **`[1, 521]`** |
| 算子 | **16 个算子码全是 builtin，没有任何 `custom_code`** |
| 其中的关键算子 | **`RFFT2D`（131）、`COMPLEX_ABS`（135）**、`CONV_2D`、`DEPTHWISE_CONV_2D`、`FULLY_CONNECTED`、`LOG`(73) 等 |

**意味着什么**：**这个模型自己在图内算频谱**（RFFT2D + COMPLEX_ABS + LOG 就是 STFT 与 log）。
所以——

- **不需要 Flex delegate / Select TF ops**；
- **不需要 `AudioSpectrogram` / `Mfcc` 这两个自定义算子**；
- **不需要在 Dart 侧自己算 mel**——直接把 16 kHz 的 PCM 切成 15600 点喂进去就行。

（说明：`AudioSpectrogram` / `Mfcc` 这两个算子在官方 *schema* 的 `enum BuiltinOperator` 里
**根本不存在**（零命中），源码里它们位于 `namespace custom`、导出的是
`Register_MFCC()`——见 [`mfcc.cc`](https://raw.githubusercontent.com/tensorflow/tensorflow/master/tensorflow/lite/kernels/mfcc.cc)。
**但 Google 自己发布的这个 yamnet.tflite 不依赖它们**，所以这条路是通的。）

**这同时解释了一件事**：为什么 MediaPipe 的官方输入规格写的是 `1 x 15600`，
而不是「mel 谱图」——**它把预处理也装进模型里了**。

### 5.2 Flutter 侧的运行时选项

| 方案 | 当前版本 | 支持平台 | 维护状态 | 许可证 | 商用 | 依据 |
| --- | --- | --- | --- | --- | --- | --- |
| **`tflite_flutter`** | **0.12.1** | Android / iOS / Linux / macOS / Windows（**无 Web**） | 发布者 tensorflow.org（verified），但**最后一次发版是 11 个月前**，README 自称 **"work-in-progress"**；helper 库已弃用；minSdk **26** | Apache-2.0 | 允许 | [pub.dev](https://pub.dev/packages/tflite_flutter)、[仓库](https://github.com/tensorflow/flutter-tflite) |
| **`flutter_litert`**（社区） | **3.9.4** | Android / iOS / Linux / macOS / **web** / Windows | **活跃**（2026-10-12 发版，共 89 个版本），是 `tflite_flutter` 的 fork | Apache-2.0 | 允许 | [pub.dev](https://pub.dev/packages/flutter_litert) |
| `tflite_flutter_helper` | 0.3.1 | — | **pub.dev 页面直接标 `discontinued`** | Apache-2.0 | — | [pub.dev](https://pub.dev/packages/tflite_flutter_helper) |
| `mediapipe_task_audio`（Google 发布） | **0.0.1** | Android / iOS | **unlisted、3 年未更新、README 是占位符** | Apache-2.0 | 形同空壳 | [pub.dev](https://pub.dev/packages/mediapipe_task_audio) |
| ONNX Runtime Mobile | — | Android / iOS | 微软维护，活跃；**官方没有 Flutter/Dart 绑定** | **MIT** | 允许 | [官方移动端文档](https://onnxruntime.ai/docs/get-started/with-mobile.html) |
| Apple **SoundAnalysis**（系统内置） | 随 OS | iOS / iPadOS / macOS | Apple 维护 | 随系统 | 允许，**且不用自带模型文件** | [官方文档](https://developer.apple.com/documentation/soundanalysis/classifying-sounds-in-an-audio-stream) |

**一条必须先说清楚的事实**：**Google 在 Flutter 上没有发布端侧推理包。**
Google 自己的官方 Flutter LiteRT 示例用的是 `flutter_edge_ai` 与 `flutter_litert` 两个**社区包**，
它的 README 原文写着 **"Both are community packages, not Google SDKs."**
（[官方示例 README](https://github.com/google-ai-edge/litert-samples/tree/main/samples/litert/flutter)）。

> **这与本项目现在的情况对得上**：`pubspec.yaml` 里已经在用 `record: ^7.1.1`——
> 而那份官方 Flutter 示例用的也是 `record: ^7.1.1`。

### 5.3 体积

| 东西 | 体积 | 来源 |
| --- | --- | --- |
| **MediaPipe `yamnet.tflite`（float32）** | **4,126,810 B ≈ 3.94 MiB** | 官方 GCS 桶 HTTP 头（`Content-Length`） |
| YAMNet 标签表（521 行） | 6,230 B | 官方 GCS |
| YAMNet 完整 Keras 权重 `yamnet.h5` | 15,296,092 B ≈ 14.6 MiB | 官方 GCS |
| PANNs CNN14 第三方转 LiteRT（fp16） | **162 MB** | [HF 模型卡](https://huggingface.co/litert-community/PANNs-CNN14-AudioSet-LiteRT) |
| ONNX Runtime Android AAR | 预编译 **24.4 MB** → 自定义裁剪 **7.5 MB** | [官方文档](https://onnxruntime.ai/docs/tutorials/mobile/) |

**把 YAMNet 塞进 App 的代价，比一张启动图还小（3.94 MiB）。** 这一条否掉了「体积是障碍」
这个直觉——**真正的障碍不在体积，在样本量（§四）与判定正确率（§六）。**

**许可证的一处补充（比 §3.1 更进了一步）**：MediaPipe 官方*文档*里**没有**声明 `yamnet.tflite`
的许可（只声明页面 CC-BY-4.0、示例代码 Apache-2.0）；但把这个文件下载下来**扫它的内嵌元数据**，
里面写着 **"Apache License. Version 2.0"**、生产者字符串 `MediaPipe`、模型版本 `1.3.0`。
**即：模型文件自身携带 Apache-2.0 声明**，上游 YAMNet 也是 Apache-2.0。
**我在文档层面没有拿到 Google 对「模型文件许可」的正面声明**——这一条仍然算**未完全落定**，
但两条旁证都指向 Apache-2.0。

### 5.4 开销量级

**有第一手数字的，只有一条**——MediaPipe 官方 benchmark 表：

> `YamNet | CPU Latency **12.29ms** | GPU Latency -`
> 口径原文："The latency result is the average latency on **Pixel 6** using CPU / GPU."
> —— [官方任务页](https://developers.google.com/edge/mediapipe/solutions/audio/audio_classifier)

**这是「一次 15600 采样点（0.975 s）窗口」的一次分类**，不是逐秒流式吞吐，GPU 没有数据。

**把它换算到本项目（这是推断，不是官方数字）**：本机那 47 段合计 **223.1 秒**，
按 0.975 秒一窗、不重叠，约 **229 个窗口**，在 Pixel 6 上 **≈ 2.8 秒**跑完。
**一晚全部分析的算力成本可以忽略**——**瓶颈不在这里。**

**没有找到的**（这一条要如实写）：YAMNet / AudioSet 类模型在手机上**逐秒流式**推理的官方延迟
或吞吐；Google 官方的 LiteRT 性能排行榜里**根本没有任何音频事件分类模型**
（只有 Whisper / Moonshine 这类 ASR），所以拿不到「同任务」的对比数字。
排行榜 README 自己也写着口径限制：**"a comparison holds only within one platform, device,
accelerator and task."**

### 5.5 Flutter 侧的两个结构性约束

1. **后台 isolate 收不到平台主动推的消息。** Flutter 官方 isolates 文档原文：
   在后台 isolate 里用平台通道**"you can't receive unsolicited messages from the host platform."**
   （[官方文档](https://docs.flutter.dev/perf/isolates)）。
   **含义（推断）**：不能指望「原生持续推音频给 Dart」，要么反过来由 Dart 主动拉，
   要么把录音 + 推理整条链留在原生侧。
2. **官方那份额外参考的 Flutter LiteRT 示例，是「按住说话」的半双工**，不是连续后台录音
   （README 原文："Half-duplex audio by design: the microphone is closed while a reply plays.
   There is no echo cancellation."）。**它只能当「Flutter 侧能调通 LiteRT」的存在性证据，
   不能当后台录音推理的先例。**

### 5.6 平台侧的既有约束（与本仓已有的结论一致）

- **iOS / macOS**：要在后台继续录音，得往 `UIBackgroundModes` 加 `audio`
  （[AVAudioSession.Category.record 官方文档](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/record)）；
  而苹果在后台执行模式那页同时警告 **"The Background Modes capability isn't available for
  macOS apps."**——**macOS 上这条路不存在**，与本仓「macOS 已构建」的平台矩阵有关。
- **Android**：`microphone` 类型的前台服务是现成的机制（本仓 v3.26 已实现）；
  官方对后台启动的硬约束原文是 **"you cannot create a `microphone` foreground service while
  your app is in the background"**（[官方文档](https://developer.android.com/develop/background-work/services/fgs/service-types)）。
  另外 Android 15 起对前台服务加了 **6 小时 / 24 小时**的运行上限，但官方明说
  **"Currently, this restriction only applies to `dataSync` and `mediaProcessing`"**——
  **`microphone` 类型不在其列**（这是按「未列入即不适用」推的，**不是官方明说，建议实测**）。
- **iOS 还有一条可能省掉模型文件的路**：系统内置的声音分类器
  `SNClassifySoundRequest(classifierIdentifier: .version1)` + `SNAudioStreamAnalyzer`，
  官方有实时流的示例（[官方文档](https://developer.apple.com/documentation/soundanalysis/classifying-sounds-in-an-audio-stream)）。
  **它不用自带模型、因此不存在素材授权问题**——但**它的类别数与数据集官方没写**
  （符号页只有一句 "Version 1 of the sound classifier."），**能不能分出鼾声属于未查到**。

## 六、几种可落地的路子

每一条都写清四件事：**要做什么 / 需要什么原料 / 代价 / 怎么验证才算数**。
判定「算不算数」的口径沿用本仓现有的：**覆盖率与准确率必须一起报**
（`tool/eval_clips.dart` 的既有口径，见 [自动分析规格](2026-10-14-night-clip-auto-analysis-design.md) §五），
并且**样本不足时拒绝调参**——这条是本仓已经写死的规矩。

### 路子 A：拿现成的 AudioSet 模型做**零样本**判定（YAMNet）

| | |
| --- | --- |
| **要做什么** | 把每段 WAV 切成 0.975 s / 15600 点的窗口喂进 `yamnet.tflite`，取 **index 38（`Snoring`）** 的分数；给整段定一个分数（取最大或取平均），再看一个阈值能不能把鼾声与其余分开 |
| **需要什么原料** | **只需要模型文件（3.94 MiB，Apache-2.0 旁证齐全）**；不需要训练、不需要标注、不需要网络 |
| **代价** | **最小**。算力成本可忽略（§5.4：47 段 ≈ 2.8 秒）。工程上先在桌面跑一遍即可，**连 App 都不用改** |
| **怎么验证才算数** | 在 `.tmp-device` 那 **47 段**上跑，输出**两张东西**：① 3 段鼾声 / 10 段梦话 / 34 段杂音各自的 `Snoring` 分数分布（**先看分布，再看阈值**）；② 与现有阈值同一张表口径的**覆盖率 + 准确率 + 召回**。**判据是「3 段鼾声的分数是否真的高于 34 段杂音」**——如果分布重叠，这条路当场死掉，**不用等做完 App 才知道** |
| **已知的风险（有据可查）** | ① `Snoring` 在 AudioSet 的 **balanced train 只有 60 条视频 / 0.2 小时**（§4.5）；② 通用 AudioSet 嵌入在窄域迁移上被实测证明不如领域模型（§4.1 引 Ghani 2023）；③ 使用方的鼾声实测是**气声型（偏亮、宽带）**而非教科书低频型（[自动分析规格](2026-10-14-night-clip-auto-analysis-design.md) §二·补）——**域不匹配是真实风险** |
| **我的判断（推断）** | **这是唯一一条「便宜到可以在决定任何事之前先做掉」的路，而且它的结果直接决定其余几条要不要做。** 唯一的技术前提是本机要能装上一个 TFLite 解释器——**注意**：本机 Python 是 **3.14.5**，而 `tensorflow` 2.21.0 目前只发到 **cp313**（没有 cp314 轮子），`tflite-runtime` 停在 2.14.0（cp38–cp311）；**要离线跑这个实验得另建一个 Python ≤3.13 的环境，或者用 `onnxruntime`（有 cp314 轮子）** |

#### 路子 A · **实测结果（2026-10-16，本机已跑完）——分布不重叠，这条路活着**

> 这一节是**跑出来的数**，不是前面的推断。原始记录见[验证记录 v3.35](../../verification-log.md)。

**环境**：Windows 11 / Python 3.14.5（venv）/ **`ai-edge-litert` 2.3.0** /
MediaPipe `yamnet.tflite` **4,126,810 B** / 那 47 段真实录音（3 鼾声 / 10 梦话 / 34 杂音）。
窗口 15600 点（0.975 s）、步进 7800 点，逐窗取分数后**对整段求平均**。

**先确认了模型接口**（与 §5.1 从 flatbuffer 解出来的完全一致）：
输入 `waveform_binary [15600] float32`、输出 `tower0/network/layer32/final_output [1,521]`。

| 人标 | 段数 | `Snoring`(38) 均分 最大 / 中位 / 最小 |
| --- | --- | --- |
| **打鼾** | 3 | **0.850 / 0.742 / 0.708** |
| 梦话 | 10 | 0.013 / 0.000 / 0.000 |
| 杂音 | 34 | **0.305** / 0.005 / 0.000 |

**正类最小 0.708，全部负类最大 0.305——中间是一条 2.3 倍宽的空档。**

| `Snoring` 均分阈值 | 召回 | 精确 | TP | FP | FN |
| --- | --- | --- | --- | --- | --- |
| 0.3 | 100% | 75% | 3 | 1 | 0 |
| **0.4 – 0.7** | **100%** | **100%** | 3 | **0** | 0 |
| 0.9 | 0% | — | 0 | 0 | 3 |

对照本仓现在的启发式（同一批 47 段：**覆盖 2% / 准确 0% / 鼾声召回 0%**），
**零样本 YAMNet 在最宽的一段阈值区间上做到了 3/3 命中、0 误报。**

**梦话那一路（`Speech`(0) 均分）就没这么干净**：

| `Speech` 均分阈值 | 召回 | 精确 | TP | FP | FN |
| --- | --- | --- | --- | --- | --- |
| 0.3 | 90% | 69% | 9 | 4 | 1 |
| 0.4 | 90% | 75% | 9 | 3 | 1 |
| 0.5 | 80% | 80% | 8 | 2 | 2 |

**结论（如实）**：

1. **「换模型」这条路的第一道关过了**：零样本就能把他的鼾声与其余分开，**不需要训练、
   不需要标注、不需要网络**——而这三样正是本仓最缺的。
2. **但这是 3 条正样本**，阈值是看着这 3 条选的。**分布空档很宽（0.708 vs 0.305）是好迹象，
   不等于泛化**：同一个人、同一台手机、两晚的录音。**换个人、换个房间都没验过。**
3. **`Snoring` 与 `Breathing`(36) 的分数几乎一样高**（3 段鼾声的 `Breathing` 是 0.875/0.740/0.742）
   ——这符合 §3.2 的推断（两者是同一父节点下的兄弟）。**规则上必须明说「疑似」**，
   机器测到的是「像鼾声的呼吸声」。
4. **端侧一个字节都没跑**：这一轮全在桌面 CPU 上。3.94 MiB 的体积没问题，
   但**推理耗时、内存、耗电在这台 MI 9 上没有读数**。
5. **许可证仍然悬着**：`yamnet.tflite` 这个**转换件**官方未声明许可（§3.1）。
   YAMNet 的权重本身是 Apache-2.0，但**把哪个文件放进 App** 这件事必须先落实——
   与「助眠音效素材」同一类发布阻塞项，别当成已经解决。

> **对 §5.4 末尾那条预判的更正**：文档原先写「本机 Python 3.14 要跑这个实验得另建 ≤3.13 的
> 环境，或改用 onnxruntime」。**实测是错的**：**`ai-edge-litert`（`tflite-runtime` 的官方后继）
> 2.3.0 在 Python 3.14 上装得上、也跑得动这个模型**，不必另建环境、也不必转 ONNX。
> （`tensorflow` 确实只到 cp313——那是另一回事。）

#### 路子 A · **泛化验证：换成别人的鼾声，照样分得开**

上面那 3 条鼾声是使用方**一个人、一台手机**录的。**「模型只对他这 3 条有效」是这条路上最大的
风险**，所以紧接着做了第二遍：拿 **ESC-50** 的公开样本当正类——**40 条别人的鼾声**
（`category = snoring`，target 28），负类取 ESC-50 里最容易被错认的一批：
`breathing` / `coughing` / `laughing` / `rain` / `clock_tick` 各 40 条，共 **200 条**。
（ESC-50 是 44.1 kHz，用多相滤波重采样到 16 kHz；**240 条全部读得出来**。）

| 阈值（`Snoring` 均分） | 召回 | 精确 | TP | FP |
| --- | --- | --- | --- | --- |
| 0.1 | 98% | 81% | 39 | 9 |
| 0.2 | 95% | 95% | 38 | 2 |
| **0.3** | **90%** | **100%** | 36 | **0** |
| **0.4** | **82%** | **100%** | 33 | **0** |
| 0.5 | 68% | 100% | 27 | 0 |
| 0.9 | 5% | 100% | 2 | 0 |

**40 条别人的鼾声里，36 条过 0.3；200 条别的类里，一条都没过。**
漏掉的 4 条集中在 3 个源录音上（`2-114609-A-28` 0.054、`3-130998-A/B-28` 0.139/0.205、
`1-20545-A-28` 0.220）——**不是随机散布的漏检，是那几段录音本身不像**。

**把两组数据放在一起（同一个统计量：整段 `Snoring` 均分）**：

| 来源 | 正类 | 正类分数 | 负类 | 负类最高 |
| --- | --- | --- | --- | --- |
| **使用方本人**（47 段） | 3 | 0.708 – 0.850 | 44 | **0.305** |
| **ESC-50**（240 段） | 40 | 中位 **0.996**、最低 0.148 | 200 | **0.298** |

**阈值 0.3 – 0.4 在两组数据上给出同一个结论**：他自己的鼾声 **3/3**，别人的鼾声
**36/40（0.3）或 33/40（0.4）**，两批负样本加起来 **244 条里 0 条误报**（他自己的杂音里
有一条 0.305，正好压在 0.3 上——所以 0.3 那一档在他那批上其实是 1 条误报，0.4 才是 0）。

**结论**：**「只对 3 条样本有效」这个风险被证伪了**——换 33 个源录音、换别人录的鼾声，
模型照样分得开。**但这不是「阈值定稿」**，理由见下。

**这一节仍然不能推出的东西**：

1. **ESC-50 那 40 条来自 33 个源录音**（`src_file` 去重），不是 40 个人——多样性仍然有限。
2. **ESC-50 是 CC BY-NC 3.0（禁商用）**：**它只能用来做这次评估，绝不能进产品、不能进仓库**。
   这条评估结论可以写进文档（它是测量），但数据本身不许打包进 App。
3. **负样本是 ESC-50 的类别，不是使用方房间里的声音**。他房间的负样本只有他自己标的那
   44 段，而那批里正好有一条压在 0.3 上（0.305）。**真实的误报率要靠更多夜里的数据。**
4. **他的鼾声得分比 ESC-50 的鼾声低一截**（0.71–0.85 对中位 0.996）——§六 里那条
   「域不匹配」的风险**确实存在**，只是还没到分不开的程度。
5. **阈值一个都没定。** 两组数据加起来 43 条正样本，**说得出「这条路成立」，
   说不出「0.35 是对的」**——后者要等更多夜里的真实录音。

### 路子 B：在现有切片上做**迁移学习**（冻结 embedding + 线性探针）

| | |
| --- | --- |
| **要做什么** | 用 YAMNet 的 **1024 维 embedding**（倒数第二层）当特征，在上面训一个线性分类器（鼾声 / 梦话 / 杂音） |
| **需要什么原料** | 就是现在这 47 段 |
| **代价** | 中等；**但结论几乎注定是「无法收账」** |
| **怎么验证才算数** | 留一交叉验证 + 置信区间。**而正样本只有 3 条 → 测试点最多 3 个**，任何准确率都不构成证据（§4.4） |
| **有据可查的支持** | **有**：冻结 embedding + 线性探针在「每类 **4 条**起」就有可行性的先例（[Ghani et al. 2023, Sci Rep, PMC10739890](https://pmc.ncbi.nlm.nih.gov/articles/PMC10739890/)），而且该文明确说「线性探针 + 预训练 embedding 是 few-shot 的 surprisingly successful strategy」 |
| **有据可查的反对** | **同一篇论文也证明**：通用音频（AudioSet）嵌入在跨域任务上**一致地不如领域模型**，作者的原话是 **"the data effects dominate the architecture effects"**，并点名 PSLA 这类 AudioSet 模型 "performed poorly on our target tasks"。**注意这篇是生物声学（鸟/蝙蝠/鲸），不是鼾声——它是类比，不是直接证据** |
| **我的判断（推断）** | **3 条正样本连类内方差都估不出来**，而本仓已经观察到这 3 条的声学特征互相打架。**在 3 个测试点上调任何参数都是拟合。** 这一条**现在不该做**，但它**是「等标注攒到每类几十条」之后的正确做法**——所以它该进的是「以后」而不是「现在」 |

### 路子 C：**承认做不到**，把功能如实降级

| | |
| --- | --- |
| **要做什么** | 让自动判定**不再产出**「疑似打鼾 / 疑似人声」，或明确把它标成实验性；界面回到「回放 + 人工标注」，并把「机器判不出来」如实说出来 |
| **需要什么原料** | 无 |
| **代价** | **零**。而且它立刻消除一类具体的假话——现有规则在 19 段上的表现是**「要么不说话，要么说错」**，唯一开口的那 1 段还是错的（[自动分析规格](2026-10-14-night-clip-auto-analysis-design.md) §五） |
| **怎么验证才算数** | 这条**不需要指标**，需要的是**文案与状态不撒谎**：展开区能区分「机器看过没把握」「音频读不出来」「从没分析过」三种沉默（§六·补 已经做了），以及标题不把「弃权」写成「待标注」以外的任何东西 |
| **与本仓既有规矩的关系** | **这与偏差 #2 / #7 那一族是同一个套路**：「没有测量就不画」「没有的东西就显示为没有」。10-15 当晚拆掉「杂音」兜底（#65）已经是这条路的半步——**把剩下那半步走完** |
| **要小心的** | M3 第 3 条在 v3.26 已被改写成「基于实测声学特征的启发式判断」。**如果那条判据被证伪，就该按它的本意把这一支降级**，并同步更新规格与偏差表——**不是悄悄留着** |

### 路子 D：不做分类，做「帮你更快听完」（聚类 / 相似片段归组）

| | |
| --- | --- |
| **要做什么** | 不声称识别鼾声，而是把一晚的片段按声学相似度**分组**，让用户按组试听、按组标注 |
| **需要什么原料** | 现有的特征（或 YAMNet 的 embedding）当向量；**不需要任何标注** |
| **代价** | 中等偏低；**完全不碰「识别」这条红线** |
| **怎么验证才算数** | **聚类是可验证的，而且不需要人工标注**：用 silhouette / 组内距离等指标，判据是「同一次录制里相隔十几秒的两段是不是被分到一组」。**本仓已经量过一件直接相关的事**：使用方标为「打鼾」的那段与他 17 秒后标为「杂音」的那段，在 11 个特征上几乎逐项重合（§1.2）——**那正是聚类会犯的错，也正是一个可以在没有新样本的情况下量出来的错误** |
| **为什么值得考虑（推断）** | 它把人工成本从 **O(片段数)** 降到 **O(组数)**，而对「哪一组是鼾声」这个问题**依然由人来回答**——**功能价值是真的，且一句话都没有多声称** |

### 路子 E：先补**数据**，再谈模型

| | |
| --- | --- |
| **要做什么** | 让用户继续听过、标过；**同时把未标注的片段留着**当半监督池（DCASE 的标准配方就是「少量弱标注 + 大量无标注 + 合成强标注」） |
| **需要什么原料** | 时间。每晚都在产生新的切片段（10-16 那一晚 27 段全未标注） |
| **代价** | 慢，但是**唯一与第一手依据方向一致的路**（§4.1） |
| **怎么验证才算数** | 标注量本身要有个数：**每类到几十条**再回头看路子 B；在那之前，任何「训练」都只该报「样本不足」，不该报准确率 |
| **一条必须先解决的障碍** | **切片与判定的参数互相打架**：10-16 那晚 **17/27 段短于 2500 ms**，这些段无论特征多像都拿不到标签（§1.2、自动分析规格 §七·11）。**而这与换不换模型无关**——**换任何模型都绕不过「1 秒的片段能不能判」这个问题**（YAMNet 的硬门槛是 **≥975 ms**，§3.3） |

### 六·补：这几条之间的关系（我的判断，标记为推断）

- **A 应该先做**，因为它最便宜、最直接回答问题、且它的结果决定 B 是否还有意义。
- **C 与 A 不冲突**：不管 A 的结论是什么，「机器认不出就别声称认得出」这件事都成立。
  如果 A 失败，C 就是唯一诚实的选择。
- **D 与 A 完全独立**，可以并行——它不依赖任何模型，也不依赖任何标注。
- **B 现在做等于拟合**；**E 是 B 的前提**。

## 七、未查到 / 查不到的

**这一节是本文的重点之一。** 下面每一条都是「我去找了、没找到第一手依据」，
**不是「不存在」**——不要把它们读成否定结论。

### 7.1 市面产品

1. **除 Fitbit 之外，端侧还是云端**——**查不到的有**：Sleep as Android、Pillow（对音频文件
   无专门声明）、Withings、小米、华为、蜗牛睡眠、SleepWatch（论文没说）。
   **只有 SnoreLab 与 Sleep Cycle 有官方原文可依**（前者端侧、后者「录音本机且绝不上传」，
   但**分析在哪跑没说**）；Sleep Cycle 的 SDK 页自称 on-device。
2. **Sleep Cycle 的鼾声检测方法**——**查不到**。官网把技术依据指向专利 `US8493220`，
   但那条专利讲的是**择时唤醒**，不是鼾声分类；"machine learning algorithm" 之后再无细节。
3. **Sleep as Android 的 CNN 在哪里推理**——**官方文档没写**，端侧与云端都没有原文；
   模型与 App **都不开源**（该组织 GitHub 里没有声音分类仓库）。
4. **Fitbit / Google 官方从未说明鼾声音频在端侧还是云端分析**——产品文档里连原理页都没有，
   能拿到的只有专利文本里的 "privacy-by-design / 分完即删"，**那是专利申请，不是产品承诺**。
5. **Pillow 完全查不到鼾声检测方法**；官网通篇没提 snore detection。
6. **蜗牛睡眠没有可抓取的官方技术文档**（官网抓取失败），只有 App Store 营销文案；
   **专利 ≠ 产品实际实现**——这点要分清。
7. **小米与华为都没说这些音频是否上传**，隐私页面只讲采集与权限。
8. **Withings 的 CE notified body 编号与证书原件没核到**（只有厂商自述）；其鼾声识别用什么
   模型也**查不到**。
9. **国产厂商有没有用深度学习做鼾声检测**——**查不到第一手依据**。能查到的中文专利
   （赛博龙 `CN106691382A`、小米 `CN105708609A`、华为 `CN113303758A`）**全部是信号处理路线**。
10. **有没有「靠麦克风听鼾声」的功能拿到过 FDA 许可 / 510(k)**——**没找到**。找到的两个
    （Apple `K240929`、Withings `K231667`）一个靠加速度计、一个靠气动 + 声学传感器，
    **都不是「听鼾声做分类」这一件事**。
11. **Google 的 Pixel「咳嗽与鼾声检测」走端侧 Private Compute Core**——**只有二手报道，
    Google 官方页面没核到，不作为结论。**

### 7.2 模型

1. **YAMNet 在 `Snoring` 这一个类上的单类精度（AP / mAP）**——**没找到官方数字**。
   官方只给 521 类的**平均**（balanced mAP 0.306）。
2. **PANNs / AST / CED 在 `Snoring` 单类上的 AP**——**没找到**。PANNs 论文有 class-wise 图，
   但那是图；我没有拿到 snoring 的数值。
3. **MediaPipe `yamnet.tflite` 模型文件的许可**：官方**文档**没有正面声明。
   我找到的旁证是**模型文件内嵌的 "Apache License Version 2.0" 元数据** +
   上游 YAMNet 的 Apache-2.0。**文档层面的正面声明仍未落定。**
4. **BEATs 权重的许可与体积**——**文档都没给**。
5. **AST 原始（非 HF 转换）权重的许可**——**未声明**。
6. **CED 权重在两个来源上的许可不一致**（HF 标 apache-2.0、Zenodo 标 cc-by-4.0）——
   **哪个是正式的未确认**。
7. **Apple 内置 `SNClassifySoundRequest` `.version1` 的类别数与数据集**——**官方只写
   "Version 1 of the sound classifier."**，没有任何类别信息。**因此「它能不能分鼾声」未知。**

### 7.3 数据集

1. **MPSSC 的许可证 / EULA 原文**——**没找到**（三个一手链接抓取失败）。
   **「可商用与否」无法判定** → 这条不解决就不能用。
2. **MPSSC 的语料统计数字**（828 段 / 219 人 / VOTE 分布）——**未能核到论文原文**，属二手。
3. **AudioSet 官方关于「大量视频已下架」的明文**——**官方页面没找到**，只有二手来源。
4. **「每类至少需要多少条样本」的硬下限**——**没有任何第一手来源给出这个数字**（§4.2）。
5. **音频增强（mixup / SpecAugment 等）在 SED 任务上的第一手增益数字**——**没找到**；
   这两篇原文的评测集都不是 SED。
6. **「1–3 秒短片段 vs 标准 5 / 10 秒输入」会掉多少点**——**没找到**。

### 7.4 端侧

1. **YAMNet / AudioSet 类模型在手机上逐秒流式推理**的官方延迟或吞吐——**没找到**。
   只有「Pixel 6 上一次 0.975 s 窗口 12.29 ms」这一条。
2. **Google 官方的 LiteRT 性能排行榜里没有任何音频事件分类模型**——只有 ASR，
   所以拿不到同任务的对比。
3. **移动端 ONNX Runtime 的推理延迟**——官方只给体积。
4. **Core ML 的模型体积上限 / 上 ANE 的尺寸阈值**——**Apple 公开文档里没有这类数字**。
5. **`tflite_flutter` / `flutter_litert` 在音频流式场景下的官方示例或性能数据**——**都查不到**。
6. **Flutter 官方关于「App 被挂起时 isolate 能否继续跑」的说明**——**该文档未涉及**。
7. **Android `microphone` 类型前台服务是否受 6 小时上限约束**——官方只说该限制
   **"Currently … only applies to `dataSync` and `mediaProcessing`"**，
   **没有给豁免清单**。「microphone 不受限」是我按「未列入即不适用」推的，**不是官方明说**。

### 7.5 本文自身的边界

1. **本文没有跑过任何一个模型。** 所有结论要么是文档原文，要么是我对文件与数据库的静态测量
   （模型字节数、ontology 解析、class map 解析、47 段 WAV 的时长与标签统计）。
   **§六 路子 A 是「推断它便宜且决定性」，不是「我测过它有效」。**
2. **引文的两档可信度**：多数引文是抓取页面后得到的原文；**Apple 支持文档那一处是抓取工具
   的转述**，已在表内标注。
3. **本文没有改动任何现有行为**：`lib/` 下的判定逻辑、`README.md`、`CHANGELOG.md`、
   `docs/verification-log.md` 一个字都没动。本轮**不实现任何东西**。


---

## 八、路线 A 已落地（v3.37，2026-10-16）

**本节是事后补写的**：上面 §一–§七 是调研当天（2026-10-16 白天）的状态，当天晚上这条路就
落进了 App。**前面的内容一个字没改**——它是决策当时的依据，改掉就不再是依据了。

### 8.1 落了什么

| | |
| --- | --- |
| **判定引擎** | YAMNet（MediaPipe `yamnet.tflite`，4,126,810 B，**随包发布也进仓库**） |
| **统计量** | **整段均分**——正是 §六 那些数字被量出来的那个口径 |
| **判定线** | 鼾声 **0.40** / 人声 **0.70**（`YamnetParams`） |
| **事件区间** | **不产出**。§4.3 说片级标签训出来的模型定位差，画一对秒数就是画没量过的东西 |
| **弃权** | 两条线都没过 → 弃权（「待标注」）。**永不输出「杂音」**（偏差 #65 不变） |
| **依据串** | `YAMNet 鼾声分 0.85（整段 8 个窗口均分、最高 0.92，判定线 0.40）· 人声分 0.02` |
| **旧的启发式** | `classifyClip` / `detectEvents` / `ClipEvent` / 十条判定阈值参数**全部删除**；`measureClip` / `AudioFeatures` 留着当纯测量 |

代码分三层（判定 / 跑模型 / I/O），边界见
[architecture.md](../../architecture.md) 的「片段分析管线」一节。

### 8.2 两个阈值分别有多硬——**这是本节最要紧的一张表**

| | 鼾声 0.40 | 人声 0.70 |
| --- | --- | --- |
| 实测支撑 | **有**：他自己 3 段 0.708–0.850、44 段负样本最高 0.305；ESC-50 上 33/40 命中、200 条 0 误报 | **几乎没有**：文档只量过 0.3 / 0.4 / 0.5，最好的一档是 0.5 的 **80% 召回 / 80% 精确** |
| 0.70 这一档量过吗 | — | **没有。这一档是拍的** |
| 为什么取它 | 0.3–0.7 全都成立，取靠严的一头：宁可漏也不误报 | 使用方明确要求「收得更紧」，标准同上 |

**两条都不是定稿**：两组加起来只有 43 条正样本，说得出「这条路成立」，
说不出「0.40 是对的」。

### 8.3 一条**继承下来的**盲区，别当成换模型之后就没了

§六 量的那个统计量是**整段均分**，于是均分的老毛病原封不动地跟过来了：
**一段 11.8 秒的录音里只有前 3.5 秒是鼾声 → 均分被摊到 0.3 上下 → 弃权。**

这不是新引入的（旧规则在「整段平均」上栽过同一跤，见 `clip_analysis.dart` 当年的文件头），
但它**没有被这次换引擎解决**。补救只做了一半：依据串里**多摆一个最高分**，
好让 `均分 0.31、最高 0.91` 这种情形一眼看得出来。

**为什么不干脆改成按最高分判**：那要换一个**没有量过**的统计量。上面那些把阈值定到 0.40
的数字**全部是拿均分量出来的**——换成最高分等于把「实测支持的结论」换成「看起来更聪明的
猜测」。要改先重新量一遍，候选是「最高分」与「连续够长的窗口」两种。

### 8.4 端侧读数（第一次有）

MI 9 / Android 11 实测：模型加载 **36 ms**、逐窗推理 **≈11.5 ms**（**42.3 倍实时**）、
**一晚约 5.3 秒**、RSS **+25 MB**。这一条把 §5.4 末尾那个「算力成本可忽略」的推断
变成了实测。逐条读数与未验证项见
[验证记录 v3.37](../../verification-log.md)。

### 8.5 仍然没解决的（承接 §7，逐条不删）

1. **正确率一个数都没有。** 换引擎那一轮手机上一段真实录音都没有，端侧只量到耗时。
   旧规则在 47 段上是「覆盖 2% / 准确 0%」，**新引擎还没在同一批上量过**。
2. **§5.3 那条许可证仍然悬着**：`yamnet.tflite` 是 MediaPipe 的**转换件**，官方文档没有
   正面声明它的许可。README 的「未实现」表里已单列成发布阻塞项。
3. **iOS / macOS 一个字节都没跑**（macOS 的 `.dylib` 不随 podspec 安装）。
4. **§7.1 那些「查不到」一条都没变**——市面产品的端侧/云端、Sleep Cycle 的方法、
   YAMNet 单类精度……这次换引擎没有回答其中任何一条。
