# 安卓平台接入设计

日期：2026-10-12
档位：**spec + plan**（新平台、影响「已支持平台」这一产品语义、含权限与构建取舍）
配套计划：[2026-10-12-android-platform.md](../plans/2026-10-12-android-platform.md)

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
会在界面上留下什么。**没做的能力不得在文档或界面里被写成已完成**——这是总规格 §8 那 22 条偏差
立的规矩，这里照办。

## 二、非目标（本轮不做，且已逐条记进 README「未实现」）

| 不做的事 | 为什么这一轮不做 | 留在界面上的是什么 |
| --- | --- | --- |
| ~~**罗盘传感器**~~ **（v3.12 已做，见 §5.3）** | 当时的判断原文留档：「要新写一条 Kotlin `SensorManager` 通道，并把 iOS 侧那套算法（磁北参考系、重力投影去倾斜、按屏幕朝向折算「手机顶部方位」）在 Android 上重新推导一遍。这不叫「接线」，叫**新做一遍罗盘**，且必须真机校准验证」——**这个判断是对的**，v3.12 确实是新做了一遍（`CompassStreamHandler.kt`）。 | 罗盘页当时如实显示不可用，且文案写死成「请使用支持罗盘的 iPhone 打开此页面」——**在 Android 上那是一句错话**（把用户往另一台设备上赶）。**v3.12 已修**，见 §5.3 |
| **后台 / 锁屏录音的前台服务** | 需要 Kotlin 前台服务 + 通知渠道 + 与 `record` 插件的采集线程接线。整夜存活**只能真机验证**，本轮无设备 | 会话页录音指示的三种状态照旧。**退到后台或锁屏后录音停止**——与 iOS 侧「锁屏后 Dart isolate 是否持续收到 PCM」同属未验证项，Android 侧还要再多一个前台服务 |
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
| `<service android:foregroundServiceType="microphone">` | **不加** | 本轮没有这个服务的实现。**声明一个指向不存在类的 `<service>` 会直接编译失败**；声明一个空壳服务则是「界面上写着有、实际启动就崩」——总规格禁止的正是这种事 |
| `android:label` | **「夜深」** | 与 iOS `CFBundleDisplayName`、macOS `CFBundleDisplayName`、Web `manifest.json` 的 `name` 四端一致 |
| `android:enableOnBackInvokedCallback` | 模板默认 | 不主动改，避免引入未验证的返回手势行为变更 |

## 五、三处必须写清楚的偏差

### 5.1 声明了前台服务权限，但后台录音仍然不能用

`FOREGROUND_SERVICE` 与 `FOREGROUND_SERVICE_MICROPHONE` 是**为下一轮的前台服务预备的**。
本轮**声明了权限、没有服务**。因此：

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

## 六、测试与验证矩阵

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

## 七、回归方法

1. **清单没被改坏**：`flutter build apk --debug` 之后，
   在 `build/app/intermediates/merged_manifests/`（或 `packaged_manifests/`）下读合并后的
   `AndroidManifest.xml`，逐条比对 §4.3 的表。**这是唯一能同时证明「我们加对了」与
   「插件的确实合并进来了」的检查**。
2. **构建参数没被改坏**：改 `minSdk` 到 23 再构建，应在 `flutter_local_notifications` 处报错。
   报不出来说明 desugaring 或 `minSdk` 有一处已经和插件脱节。
3. **`.metadata` 有 `android` 条目**：没有它，下次 `flutter create` 会重新认领平台。
4. Dart 侧**一行都不改**——所以 `flutter test` 的条数应与本轮之前**完全相同**。
   条数变了就说明平台目录的接入意外碰了 Dart 代码。
