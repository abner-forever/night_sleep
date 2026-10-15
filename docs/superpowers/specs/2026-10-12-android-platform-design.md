# 安卓平台接入设计

日期：2026-10-12（§六 为 v3.13 / 2026-10-13 原地新增）
档位：**spec + plan**（新平台、影响「已支持平台」这一产品语义、含权限与构建取舍）
配套计划：[2026-10-12-android-platform.md](../plans/2026-10-12-android-platform.md)、
[2026-10-13-android-system-bars.md](../plans/2026-10-13-android-system-bars.md)

上游规格：

- 总规格 `2026-09-28-night-sleep-design.md` §4 M0 第 1 条（目标平台含 Android）、
  §10 第 1 条（applicationId 用占位配置）与第 6 条（麦克风用途文案）；
- `2026-09-28-export-and-reminders-design.md` §「平台接线」的 Android 行；
- `2026-10-03-night-audio-recording-design.md` §七 的 Android 行。

这三处都写着同一句话：**「本轮无法执行：仓库里没有 `android/` 目录」**。本文就是把那三笔欠账，
加上总规格 §4 里一直没兑现的「目标平台含 Android」，一次结清——**并且只结清清单与构建配置这一层**。

## 一、目标

让「夜深」在 Android 上**能编译、能装、能起**，并把 Dart 侧**早已写好**的 Android 分支
（通知权限查询、`requestNotificationsPermission`、`inexactAllowWhileIdle`、
`AndroidNotificationDetails`）接到真实的平台配置上。

一句话验收：`flutter build apk --debug` 产出安装包，且装出来的包**通知能响、重启后提醒会重排**。

**明确不追求**「Android 上所有能力与 iOS 持平」。第五节逐条列出本轮不做的事，以及每一件做不了
会在界面上留下什么。**没做的能力不得在文档或界面里被写成已完成**——这是总规格 §8 那张有意偏差表
立的规矩（写本节时是 22 条，**v3.18 时点已到 52 条**），这里照办。

## 二、非目标（本轮不做，且已逐条记进 README「未实现」）

| 不做的事 | 为什么这一轮不做 | 留在界面上的是什么 |
| --- | --- | --- |
| ~~**罗盘传感器**~~ **（v3.12 已做，见 §5.3）** | 当时的判断原文留档：「要新写一条 Kotlin `SensorManager` 通道，并把 iOS 侧那套算法（磁北参考系、重力投影去倾斜、按屏幕朝向折算「手机顶部方位」）在 Android 上重新推导一遍。这不叫「接线」，叫**新做一遍罗盘**，且必须真机校准验证」——**这个判断是对的**，v3.12 确实是新做了一遍（`CompassStreamHandler.kt`）。 | 罗盘页当时如实显示不可用，且文案写死成「请使用支持罗盘的 iPhone 打开此页面」——**在 Android 上那是一句错话**（把用户往另一台设备上赶）。**v3.12 已修**，见 §5.3 |
| ~~**后台 / 锁屏录音的前台服务**~~ **（v3.26 已做，见 §5.1）** | 需要 Kotlin 前台服务 + 通知渠道 + 与 `record` 插件的采集线程接线。当时的判断原文留档：「整夜存活**只能真机验证**，本轮无设备」。**v3.26 做了服务本身**——接线用的是依赖注入的 `NightAudioService` 接缝，采集线程一行没动（PCM 仍由 `record` 插件交给 Dart isolate）；**整夜存活仍然只能真机验证** | 会话页录音指示的三种状态照旧。**退到后台或锁屏后录音停止**——**v3.26 起代码上应该不成立了，但真机未验证**（见 §5.1） |
| **「去系统设置」在 Android 上真正跳转** | 现有实现走 `url_launcher` 的 URL scheme（`app-settings:` / `x-apple.systempreferences:`），**Android 没有等价的 scheme**，要跳到「应用详情页」得新写平台通道或引入依赖 | 麦克风权限被拒时那一行「去系统设置」**在 Android 上点了没反应**。见 §5.2 |
| **真机 / 模拟器验收** | 本机没有 Android 设备，也没有跑起来的模拟器；本轮只做**构建 + 静态分析 + 测试** | 一切「装上去之后会怎样」的结论都标注为未验证 |

## 三、环境事实（本轮实测，含对 README 的订正）

接入前先量了一遍本机，**README「环境要求」里有两句已经不成立**：

| 项 | README 原本写的 | 本轮实测 | 处置 |
| --- | --- | --- | --- |
| Android SDK | 「本工作区尚未安装 Android SDK」 | **已装**：`%LOCALAPPDATA%\Android\Sdk` 下有 platforms 31/33/34、build-tools 34.0.0 与 35.0.0-rc3、cmdline-tools、platform-tools、emulator、`licenses/` | 订正 README |
| JDK | 未提 | Temurin **17.0.15**（满足 AGP 8.x 与 `flutter_local_notifications` 要求的 Java 17） | 补进 README |
| Flutter SDK | 基线 3.47.5 | 本机 PATH 上是 **3.16.7 / Dart 3.2.4**，**解析不了本工程**：`Because night_sleep requires SDK version >=3.3.0 <4.0.0, version solving failed` | 见下 |
| pub 缓存 | 未提 | `~/.pub-cache` **不存在**，依赖一个都没落地 | — |

第三条是本轮真正的前置障碍：**3.16.7 连 `flutter create` 都跑不了**（工程 `pubspec.lock` 要求
`dart >=3.13.0`、`flutter >=3.44.0`）。因此本轮**先装了 Flutter 3.47.5（Dart 3.13.4）**，
与 README 记录的基线对齐，**与已有的 3.16.7 并存**（装在 `C:\src\flutter-3.47.5`，
**不改 PATH、不动 `C:\src\flutter`**）。

> **这是本机环境改动，不是仓库改动。** 记在这里是因为「本机 Flutter 是 3.16.7」这条事实
> 会让下一个在这个工作区动手的人一头雾水。换机器时按 README 装 3.47.5 即可。

## 四、平台配置

### 4.1 生成方式：用 `flutter create`，不手写

总规格 §4 M0 第 1 条与 README「环境要求」都写明「接入 Android 时先
`flutter create --platforms=android .` 生成平台目录」。**照办**，理由是版本对齐：
Android 模板里的 AGP / Gradle / Kotlin 版本、`build.gradle.kts` 的写法、`.gitignore` 条目
都跟着 SDK 版本走，手写的模板**下一次升 SDK 就会脱节**，而且没人会记得去对。

生成前 `.metadata` 只登记了 root / ios / macos / web 四个平台，生成后多一条 `android`。

### 4.2 构建参数

Flutter 3.47.5 的模板带来的是 **AGP 9.1.0 / Kotlin 2.4.0 / Gradle 9.3.1 / Java 17**
（`android/settings.gradle.kts`、`gradle-wrapper.properties` 与 `app/build.gradle.kts`），
以及 `flutter.compileSdkVersion` / `minSdkVersion` / `targetSdkVersion` / `ndkVersion`
四个**跟着 SDK 走的变量**，不写死数字。本轮**只按插件的真实下界上调**——
下界不是猜的，是挨个读插件源码里 `android/build.gradle` 得到的：

| 参数 | 取值 | 依据 |
| --- | --- | --- |
| `compileSdk` | 模板默认 = **36** | 逐个读了本工程全部带 Android 实现的插件，最高的是 `flutter_local_notifications` 22.3.1 与 `record_android` 2.2.0，都写死 **compileSdk 36**（其余如 `just_audio`、`sqlite3_flutter_libs`、`audio_session`、`flutter_timezone` 是 35 或更低）。`FlutterExtension.kt` 里的默认值正是 36，**恰好相等**，故不上调 |
| `minSdk` | 模板默认 = **24** | 同上，最高的是 `flutter_local_notifications`、`record_android`、`audio_session`、`flutter_secure_storage`、`url_launcher_android` 五者，都要求 **24**；`FlutterExtension.kt` 默认正是 24 |
| `targetSdk` | 模板默认 | 不主动加高：`targetSdk` 抬升会带来新的运行时行为变更（前台服务类型、精确闹钟、通知权限），**本轮不引入未验证的行为变更** |
| Java / Kotlin | **17** | `flutter_local_notifications` 22.3.1 写死 `sourceCompatibility/targetCompatibility = VERSION_17`；本机 JDK 也是 17 |
| **core library desugaring** | **必须开** | `flutter_local_notifications` 22.3.1 直接 `coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'`。**不开则编译期就报错**（用到 `java.time` 等 API）。这条最容易被漏掉，且漏了会以「插件与工程 Java 版本对不上」的形式报出来，看上去像 SDK 装错了 |

### 4.3 清单：每一条的来源都核过

**没有一条是照抄文档的**——包括本文上游那三处规格里已经写好的条目。核对方式是直接读插件包里的
`android/src/main/AndroidManifest.xml` 与 `android/build.gradle`。

| 条目 | 加不加 | 依据（实测） |
| --- | --- | --- |
| `RECEIVE_BOOT_COMPLETED` | **加** | `flutter_local_notifications` 的 manifest **没有**它。不加则设备重启后 `ScheduledNotificationBootReceiver` 收不到 `BOOT_COMPLETED`，**提醒再也不会重排**——「重启后仍在」这句承诺就是靠它成立的 |
| `ScheduledNotificationReceiver` | **加** | 插件 manifest 里**没有**，必须由应用声明（`android:exported="false"`） |
| `ScheduledNotificationBootReceiver` | **加** | 同上，并挂**四个** action：`BOOT_COMPLETED` / `MY_PACKAGE_REPLACED` / `QUICKBOOT_POWERON` / `com.htc.intent.action.QUICKBOOT_POWERON`（凭记忆写会漏掉最后那个 HTC 的，片段照抄插件 22.3.1 的 README） |
| `POST_NOTIFICATIONS` | **不加** | 已核对：`flutter_local_notifications` 22.3.1 的 manifest 里**有** `POST_NOTIFICATIONS` 与 `VIBRATE`，构建时合并进来。重复声明无害但无用，上游规格也正是这么写的（「由插件自己的 manifest 合并进来，不必重复声明」）——**这条是核对通过的，不是照抄的** |
| `VIBRATE` | **不加** | 同上 |
| `RECORD_AUDIO` | **不加** | 已核对：`record_android` 2.2.0 的 manifest 里**有** `RECORD_AUDIO`。**上游规格与 README 都写着「要补 `RECORD_AUDIO`」——那是平台目录还不存在时写的，没人核过插件。本轮实测后订正**：它由插件合并，应用侧不必重复声明 |
| `INTERNET` | **加——而且是差点漏掉的一条** | **Flutter 模板只在 `src/debug/` 与 `src/profile/` 两个变体清单里带它**（注释写明是给 hot reload 用的），**main 里没有**。所以「拿模板逐行比对」这种查法**发现不了**它。而本应用真的联网：洞察服务的获取可用模型 / 连通性测试 / 查询余额 / 生成洞察（`insight_service.dart`、`model_catalog.dart` 的 `package:http`）。也**没有任何插件会合并它**——本工程全部带 Android 实现的插件的 manifest 都读过，无一含 INTERNET。**漏掉的后果只在 release 包里发作**：debug 因为变体清单里有这条而一切正常，release 里所有洞察请求都以 `SocketException` 失败，开发期完全看不出来。这一条是独立审查提出的，本轮已核并落地 |
| `FOREGROUND_SERVICE`<br>`FOREGROUND_SERVICE_MICROPHONE` | **加** | 插件都不带。**但这一条要单独说清楚**，见 §5.1——**声明了不等于后台录音能用** |
| `<service android:foregroundServiceType="microphone">` | **不加**（**v3.26 已改**：加了，见 §5.1） | 本轮没有这个服务的实现。**声明一个指向不存在类的 `<service>` 会直接编译失败**；声明一个空壳服务则是「界面上写着有、实际启动就崩」——总规格禁止的正是这种事 |
| `android:label` | **「夜深」** | 与 iOS `CFBundleDisplayName`、macOS `CFBundleDisplayName`、Web `manifest.json` 的 `name` 四端一致 |
| `android:enableOnBackInvokedCallback` | 模板默认 | 不主动改，避免引入未验证的返回手势行为变更 |

## 五、三处必须写清楚的偏差

### 5.1 声明了前台服务权限，但后台录音仍然不能用

> **v3.26（2026-10-14）更新：服务已实现**，本节的原判已不成立的部分一律以这段为准。
>
> 落地的四个文件：`NightRecordingService.kt`（服务本体）、`NightAudioServiceHandler.kt`
> （`night_sleep/recording_service` 通道 + `AppVisibility`）、`MainActivity.kt`（接线、
> 引擎销毁时撤服务）、`lib/core/platform/night_audio_service.dart`（Dart 封装），
> 采集端 `RecordNightRecorder` 按依赖注入接上。
>
> 三个刻意的取舍：**起服务必须在应用可见时**（targetSdk ≥ 31 后台起会抛
> `ForegroundServiceStartNotAllowedException`；≥ 34 还在创建服务那一刻校验
> `RECORD_AUDIO`），所以 handler 里先判 `AppVisibility`，不可见就回 `notForeground`，
> 让界面如实说「应用不在前台 · 暂时无法开始录音」，而不是先写「录音中」再等 60 秒翻成
> 「被系统静音」；**`START_NOT_STICKY`**（进程被杀后系统拉起来的空壳没有任何东西在录音，
> 通知栏不该出现一条「正在录制」）；**通知渠道第一次真要起服务时才建**
> （没录过音的用户不该看见一条他还没用过的功能），`IMPORTANCE_LOW`。
>
> ⚠️ **真机未验证**：服务在场是否真能挡住 `AudioFlinger` 的 `setRecordSilenced`，
> 只有装到机器上跑一整夜才知道——机制的两头（官方文档、v3.19 实测）都有证据，中间那一步
> 从没在设备上跑过。**发布前**：`FOREGROUND_SERVICE_MICROPHONE` 现在真要用了，
> 上架时必须连同服务的**用途申报**一起提交（Google Play 单独审核项）。

`FOREGROUND_SERVICE` 与 `FOREGROUND_SERVICE_MICROPHONE` 当时是**为下一轮的前台服务预备的**。
本轮（2026-10-12）**声明了权限、没有服务**。因此：

- **前台录音可用**（会话页开着时录得下来），这靠 `RECORD_AUDIO` + 运行时授权，与前台服务无关；
- **退到后台 / 锁屏后录音停止**——与 iOS 侧那个未验证项同类，且 Android 侧还多欠一个前台服务；
- 权限声明本身**不向用户弹任何框**（`FOREGROUND_SERVICE*` 不是运行时权限），所以这不违反
  总规格 §7「未接入的能力不得申请权限」——那条红线针对的是**向用户索要**（麦克风、通知、定位）。
  这一条在此记明，免得以后有人看到「声明了却没实现」以为是无意为之。

顺带一笔：Google Play 对 `FOREGROUND_SERVICE_MICROPHONE` 有单独的用途申报与审核要求。
**发布前**若仍无对应服务，应把这两条权限一并删掉，而不是留着一个通不过审核的声明。

### 5.2 「去系统设置」在 Android 上点了没反应

`lib/core/platform/app_settings.dart` 的 `uriFor()` 对非 iOS / macOS **退回 `app-settings:`**，
注释里当时就写着「Android 平台目录尚未生成，这里给不出一个验证过的地址；退回 iOS 的写法只是
不崩，不代表在别处能用」。

Android 没有等价 scheme，要跳到「应用详情页」得写一条平台通道（或引入 `android_intent_plus`）。
**本轮按「不新增 Android 独有能力」的约定不做**，把这笔账记在 README「未实现」表里。

**影响面**：麦克风权限被拒时那一行入口，在 Android 上是个死按钮。
**这不会因为本轮改动而产生**（它一直是死按钮），但**从本轮起 Android 是「已支持平台」**，
所以它从「未生成平台的代码路径」升级成了一条真实的界面缺陷。

### 5.3 罗盘页在 Android 上会说错话

`CompassSource.readings()` 对非 iOS 返回
`CompassUnavailable('请使用支持罗盘的 iPhone 打开此页面')`。这句话在 macOS / Web 上只是别扭，
**在 Android 上是一句错话**——它在劝一个拿着 Android 手机的用户换台手机，而正确说法是
「这个平台还没接罗盘」。

**当时本轮不改**（属罗盘能力，不属平台配置），记进 README「未实现」表。

**v3.12（2026-10-13）已修。** 处置如下：

- `lib/core/platform/compass.dart` 的判定放行 `TargetPlatform.android`（**`kIsWeb` 仍留在平台判断之前**——
  Web 上 `defaultTargetPlatform` 报的是宿主机系统）；`CompassUnavailable` 的文案改为
  「**当前平台暂不支持罗盘**」，不再提任何具体平台、也不谎称设备不行。
- **页面一行未改**：`compass_page.dart` 早就分好了两支——`CompassUnavailable` 用它的 `.message`
  （平台未实现），`PlatformException(code: 'unavailable')` 映射成「此设备没有可用的罗盘传感器」
  （设备没有传感器）。Android 侧照 iOS 发 `error(code: "unavailable")` 就落进后者，
  **那句「设备没有传感器」是白拿的**。
- 于是「不可用」按原因分成了两种说法，这正是这条缺口当初点的题。

### 5.4 `android:allowBackup` 保持 Android 默认（= 允许），这是一个**需要你确认**的取舍

`flutter_secure_storage` 11.2.0 的 README 明确建议应用设 `android:allowBackup="false"`：
Android 默认会把应用数据备份到用户的 Google Drive，**换机恢复后**读那个加密条目会抛
`java.security.InvalidKeyException: Failed to unwrap key`（Keystore 的密钥不跟着备份走）。

本轮**没有改**，理由三条，都写在这里而不是埋在 diff 里：

1. **它已被代码兜住**：`insight_credentials.dart:38-46` 的 `read()` 是
   `try { ... } on Object { return null; }`，异常在「读不到」与「没配置」之间被归一化，
   **不会把启动带下水**——那正是这段注释写明了的意图。所以这条不构成缺陷。
2. **改了会静默改变产品语义**：`allowBackup="false"` 意味着用户换新手机后**没有数据可恢复**。
   这是使用方的决定，不是实现细节。
3. **iOS 侧一直没做对应的排除**（iCloud 备份默认也包含应用数据），单改 Android 会造成
   一个没有解释的不对称。

**但有一条必须在这里说清楚**：备份开着意味着**睡眠数据库与录音片段可能被上传到用户自己的
Google Drive**，而应用对自己的承诺是「录音片段仅保存在本机，**不会上传**」
（`Info.plist` / 设置页文案）。Android 的自动备份有 25 MB/应用的配额，整夜 WAV 未必装得下，
但**数据库装得下**。**「不会上传」这句话在 Android 上因此并不严格成立。**

**建议使用方裁定**（三选一）：① 设 `allowBackup="false"`（放弃换机恢复，彻底对齐承诺）；
② 用 `dataExtractionRules` 只排除录音与数据库、保留其余偏好；③ 保持现状，
把「不会上传」的措辞改成「不主动上传」。

**本轮三个都没执行**：代码停在 Android 默认值上（清单里不写 `allowBackup`），
界面文案也一字未动。这是一条**已识别、已记录、待裁定**的取舍，不是遗留的疏忽。

## 六、系统栏与安全区（v3.13，2026-10-13）

**这一节回答「Android 上顶部一条灰带、底部一条黑带把页面截断」**——它是装到真机上
第一眼就看得见的东西，也是「安全区适配不像 iOS」这句话的全部内容。

### 6.1 两个来源，都不是渲染问题

| 现象 | 根因（真机实测，MI 9 / Android 11 / 1080×2340 @ 440dpi） |
| --- | --- |
| 顶部一条灰带。浅色主题下量到 `(181,181,186)` | 引擎默认只申请到 `LAYOUT_FULLSCREEN`（`PlatformPlugin` 的 `mEnabledOverlays = 0x500` = `LAYOUT_STABLE \| LAYOUT_FULLSCREEN`）：状态栏盖在内容**之上**，内容确实画到了顶，但系统在**透明**状态栏背后自动加了一层对比度蒙层（Android 10+ 的 `enforceStatusBarContrast`）。那层蒙层把状态栏那一条压成了 `(181,181,186)`，而紧挨着它的页面像素是 `(240,242,248)`——**比值约 0.75，即蒙层约 25% 黑**（`(240,242,248) × 0.75 = (180,182,186)`，与实测差 1 级）。**这两个都是真机采样读数，不是令牌值**：浅色 `bgBase` 是 `0xFFF2F2F7`、`Atmosphere` 顶色是 `0xFFF6F8FF`，都对不上——拿令牌去复算这条会算不出来 |
| 底部一条**不透明黑**带，把页面截断在导航栏上沿 | `mEnabledOverlays` 里**没有** `LAYOUT_HIDE_NAVIGATION`，导航栏那块被排除在内容区之外。实测 Flutter 内容区止于 `y=2296`，黑带从 `y=2296` 起（屏高 2340）——也就是说 `MediaQuery.padding.bottom` 是 **0**，而顶部的 `padding.top` 是 75px |

**两条都别去渲染层找原因**。它们各自对应一个没声明出去的字段，跟 widget 树无关。

### 6.2 做了什么

新增 `lib/core/platform/system_bars.dart`（两个函数 + 一个 `builder`，外加会话页那一层覆写）：

- `enableEdgeToEdge()`：`SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge)`，
  在 `main()` 里**第一帧之前** `await`。Android 专属（`kIsWeb` 排在平台判断之前，
  与 `compass.dart` 同源）。
- `appSystemUiOverlayStyle(Brightness)` + `appSystemUiOverlayRegion`，后者挂在
  `MaterialApp.builder` 上。**必须挂在 `builder`**：那里在主题之内、路由之上下，
  `Theme.of(context)` 拿到的才是应用当前生效的明暗；各页自己的 `AnnotatedRegion`
  又压在它上面（`AnnotatedRegion` 取覆盖该区域的最上面一层），常暗的会话页因此仍然说话算数。

四条要点，每条都对着 §6.1 那个表：

1. **两条栏透明**——页面自己的背景（`Atmosphere` / `NightBackdrop`）铺到物理边缘。
2. **`systemStatusBarContrastEnforced: false` / `systemNavigationBarContrastEnforced: false`**。
   这是顶部那条灰带的**唯一**解法；只把颜色设成透明是不够的，蒙层照加。这也是引擎
   `setSystemChromeSystemUIOverlayStyle` 里为数不多会一路传到 `Window` 的字段（已读字节码核对）。
3. **不得用 `SystemUiOverlayStyle.light` / `.dark` 这两个预设**：它们把
   `systemNavigationBarColor` 写死成不透明黑（`0xFF000000`），导航栏会重新变回一条黑带。
   两个预设都长得像为此准备的，所以 `test/system_bars_test.dart` 专门钉了一条断言把
   **上游这个坑**记在案。
4. **图标明暗跟的是应用主题，不是系统设置**：应用内可以单独切浅色 / 深色。真机验证了
   「系统浅色 + 应用深色」这一组（状态栏图标如期变白）。

**API 29 以下 `edgeToEdge` 是空操作**：引擎的 `PlatformPlugin.setSystemChromeEnabledSystemUIMode`
里有 `SDK_INT >= 29` 的门槛（读字节码确认），那些设备维持旧行为。**这是引擎的限制，不是遗漏**，
不要试图在应用侧补。

### 6.3 标签条的浮起量按平台分叉（全工程唯一一处）

`app_shell.dart` 的 `tabBarFloat` 由「安全区底部 − 回收量」算出，**回收量按平台分叉**。
理由是一条实测几何：

- iOS 的 home indicator 5pt 高、贴底 8pt，34pt 的安全区里**空着 21pt**，
  所以借得起那 14pt（总规格偏差 #21 的由来）；
- Android 的手势条贴在安全区**下沿**：安全区 44px（16dp），手势条画在离底 20–29px
  （约 7–11dp）那一段。照搬 iOS 的 14 之后，**胶囊底边落在 `y≈2307`、手势条上沿在
  `y≈2312`**——只差 5px，截图里看着就是压在一起，像胶囊被截断。

所以 Android 上 `relief = 0`：整个让开安全区，一点都不借。

### 6.4 真机验证（Xiaomi MI 9 / Android 11 / MIUI 12.5.6，`e0e60672`）

**已验证**（方法是 `adb` 抓设备帧缓冲、逐像素采样；改前与改后是同一台机器上的同一个页面。
**截图本身没有入库**——`screenshots/` 在 `.gitignore` 里、本轮的临时图也没留，所以下面
记的是**读数**而不是图。要复核得重跑一遍：见 §8 回归方法第 5 条）：

> **本节是「改前」那个读数的唯一出处。** 谁要是想复核它，只能把 `lib/core/platform/system_bars.dart`
> 那两处调用临时摘掉、重新构建再看一次——原始截图已经没有了。

- **顶部**：取 `x=30` 一列在屏幕上部逐点采样，`y<75` 由 `(181,181,186)` 变成页面自己
  的背景色——**关键在于跨过 `y=75` 没有台阶**，而不是某个具体值（那取决于当前是哪一页：
  设置页量到 `(241,241,248)`，首页量到 `(246,248,255)`，正是 `Atmosphere` 的顶色
  `0xFFF6F8FF`）。状态栏图标仍是深色（浅色主题）。
- **底部**：黑带消失，页面背景一直铺到 `y=2339`；胶囊底边落在 `y=2296`（离底 44px，
  2.75 倍下正好 16dp，正是 `tabBarFloat` 算出来的），手势条画在 `y=2310–2319`
  （按「三通道均值 < 90」判为暗像素量出的范围），两者之间留出 14px。
- **推入页**：`外观`（走 `Subpage` 的 `SafeArea`）在同一台机器上同样两条栏透明。
- **模态底部弹层**：睡眠详情的声音记录弹层同样两条栏透明——状态栏那一段与紧邻的
  蒙层像素连续、没有色阶；手势条画在弹层之上（与上一段同一位置，不另记读数——
  同一件系统部件在两个界面上是同一个东西，记两个数只会自找对不上），弹层自己的
  底部留白读的就是 `MediaQuery.padding.bottom`，跟着一起对了。
- **常暗的会话页**：浅色应用主题下进「睡眠模式」，状态栏图标如期变白、页面背景铺到
  导航栏后面——这一条正面验证了「页面自己的 `AnnotatedRegion` 压过 `builder` 那一层」。
- **深色主题**：应用内切成深色（系统仍是浅色），状态栏图标变白、手势条变白。
- `flutter test` → **609/609 通过**（v3.12 是 592，净增 17）；`flutter analyze` 零问题。
  新增的网见 §7 矩阵：`system_bars_test.dart` 10 条（含两条**起真实 `NightSleepApp`** 的
  挂载点断言——审查发现删掉 `app.dart` 那一行原先一条都不会红）、`tab_bar_inset_test.dart`
  由 4 条变 10 条、`sleep_session_page_test.dart` 补了「页面自己那一层压过外层」一条。

**未验证**：

- **API 29 以下的设备**（本机只有 API 30 一台）——按 §6.2 末段的引擎门槛，那些设备应维持旧样子。
- **API 35 及以上的设备**：`targetSdk` 是 **36**（`FlutterExtension.targetSdkVersion`），
  而 `Window.setStatusBarColor` / `setNavigationBarColor` / `setStatusBarContrastEnforced`
  在 API 35 起是 deprecated no-op——引擎字节码里也有 `SDK_INT < 35` 的门槛，本轮的样式
  有几个字段在那条线以上根本发不出去。**预期结果一样**（系统从那一条起自己强制
  edge-to-edge，两条栏本来就是透明的），但那是**另一套系统行为**，与「API 29 以下是空操作」
  同属一类，本机没验过。
- **三键导航**：真机常年是手势导航。三键导航下安全区是 48dp 左右，按本轮的规则胶囊会
  整个让开它（浮起 48dp）；**这是推断，没有实测**。
- **横屏**：本轮只测了竖屏。

### 6.5 顺带改了 iOS / macOS 的系统栏样式来源（原计划的硬约束没做到，如实记）

计划的硬约束原文是「**iOS / macOS 的行为一个字都不许变**」。**这条没做到**，原因是
`appSystemUiOverlayRegion` 挂在 `MaterialApp.builder` 上，是**无条件**的：

- **改之前**：整个 `lib/` 里只有会话页一处 `AnnotatedRegion`（v3.10 加的），
  其余页面的系统栏样式**由系统定**——iOS 上就是跟随**系统外观**。
- **改之后**：跟随**应用主题**（`Theme.of(context).brightness`）。iOS 读的是
  `statusBarBrightness`（SDK 注明 "Only honored in iOS"），它现在被显式设上了。

于是「应用主题 ≠ 系统外观」的场合（应用内把外观切成深色、系统仍是浅色，或反过来），
**iOS 的状态栏前景色会跟着应用走**——这与 Android 侧同一条规则，也正是本意：
应用有自己独立的外观开关，若系统栏跟随系统，深色的页面上就会压出一排看不见的黑字。
**会话页不受影响**：两版算出的 `statusBarBrightness` 都是 `dark`，iOS 视角等价。

**但这一条没有在 iOS / macOS 上验过**——本轮全程在 Windows 上，只有一台 Android 真机，
没有 iOS 设备也没有跑模拟器。**按本仓库的规矩，未验证就是未验证**，不许写成「已适配
iOS」。要在 iOS 上确认，看两件事：系统浅色 + 应用深色时状态栏是不是浅色内容；以及
应用内切主题时它跟不跟着变。

macOS 没有系统状态栏，`statusBarBrightness` 在那边无人读取；这条改动对 macOS
**预期**无影响，同样**未验证**。

## 七、测试与验证矩阵

| 类型 | 重点场景 | 预期状态 |
| --- | --- | --- |
| 构建 | `flutter build apk --debug` 通过 | 本轮验证 |
| 构建 | **核对打包产物**而不只是源码：合并后的 `AndroidManifest.xml` 里确有 `RECEIVE_BOOT_COMPLETED`、两个 receiver、`POST_NOTIFICATIONS`（来自插件合并）、`android:label` 是「夜深」 | 本轮验证。**`build/` 下的合并清单是唯一能证明「合并真的发生了」的东西** |
| 静态 | `flutter analyze` 零问题；`dart format .` 无多余改动 | 本轮验证 |
| 回归 | `flutter test` 全绿（Android 平台目录**不应改变任何 Dart 行为**，所以数字应与本轮之前一致） | 本轮验证 |
| 未验证 | 真机 / 模拟器安装启动 | **未做**。本机无设备 |
| 未验证 | 通知真的会响、重启后真的会重排 | **未做**。Dart 侧调度契约有测试钉着，清单有构建产物为证，但「到点投递」仍需人工 |
| 未验证 | 前台录音在 Android 上录得下来 | **未做** |
| 未验证 | 后台 / 锁屏录音 | **未做**，且缺实现（§5.1） |
| 系统栏（v3.13） | 两条系统栏透明、页面背景铺到物理边缘；浅色主题下状态栏图标为深色、深色主题下为浅色；常暗的会话页覆写生效 | **本轮真机验证**（逐条与判据见 §6.4） |
| 系统栏（v3.13） | 标签条不压在手势条上 | **本轮真机验证**：胶囊底边 `y=2296`、手势条上沿 `y=2310`，中间 14px |
| 系统栏（v3.13） | 样式声明的回归：两条栏透明、蒙层关闭、图标明暗跟随**应用主题** | `test/system_bars_test.dart` 10 条（含「跟应用主题而不是系统」一组） |
| 系统栏（v3.13） | **两个挂载点真的挂上了**：`main()` 里调了 `enableEdgeToEdge()`、`app.dart` 的 `builder` 挂了 region。另有「常暗的会话页自己那一层压过外层」 | 同上 + `test/sleep_session_page_test.dart` 一条。用 `test/system_bar_probe.dart` 复刻 `RenderView._updateSystemChrome` 的取值路径，量**框架真会发给平台的样式**；已变异验证：删掉 `app.dart` 那一行、或把会话页换回预设，对应用例变红 |
| 系统栏（v3.13） | 标签条浮起量的平台分叉 | `test/tab_bar_inset_test.dart` 10 条，每条用 `TargetPlatformVariant` 写明平台 |
| 未验证 | **API 29 以下的设备**上的系统栏 | **未做**。按 §6.2 第 5 条，那些设备应维持旧样子（引擎门槛），本机只有 API 30 |
| 未验证 | **三键导航**下的标签条浮起量 | **未做**。手势导航实测通过；三键导航安全区约 48dp，胶囊会整个让开它——**推断，未实测** |
| 未验证 | 横屏下的系统栏 | **未做**，本轮只测竖屏 |

## 八、回归方法

1. **清单没被改坏**：`flutter build apk --debug` 之后，
   在 `build/app/intermediates/merged_manifests/`（或 `packaged_manifests/`）下读合并后的
   `AndroidManifest.xml`，逐条比对 §4.3 的表。**这是唯一能同时证明「我们加对了」与
   「插件的确实合并进来了」的检查**。
2. **构建参数没被改坏**：改 `minSdk` 到 23 再构建，应在 `flutter_local_notifications` 处报错。
   报不出来说明 desugaring 或 `minSdk` 有一处已经和插件脱节。
3. **`.metadata` 有 `android` 条目**：没有它，下次 `flutter create` 会重新认领平台。
4. Dart 侧**一行都不改**——所以 `flutter test` 的条数应与本轮之前**完全相同**。
   条数变了就说明平台目录的接入意外碰了 Dart 代码。
5. **系统栏没被改回去**（v3.13）：`test/system_bars_test.dart` 六条。三个最容易犯的——
   把 `appSystemUiOverlayStyle` 换成 `SystemUiOverlayStyle.dark` / `.light` 预设（导航栏
   变回不透明黑）、删掉两个 `*ContrastEnforced: false`（顶部灰带回来）、把 `AnnotatedRegion`
   从 `MaterialApp.builder` 挪进 `AppScaffold`（弹层与推入页就覆盖不到了）。
   **真机上一眼可判**：浅色主题下，状态栏那一条与页面背景之间不该有任何色阶；
   屏幕最底下不该出现一条与页面背景不同的实心带。
