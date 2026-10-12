# 安卓平台接入实现计划

日期：2026-10-12
规格：[2026-10-12-android-platform-design.md](../specs/2026-10-12-android-platform-design.md)
档位：**spec + plan**（新平台、影响「已支持平台」这一产品语义、含权限与构建取舍）

## 目标

`flutter build apk --debug` 出得来包，且装出来的包**通知能响、重启后提醒会重排**。
Dart 侧**一行都不改**。

## 编排说明（为什么这轮不按任务派 subagent）

本档位通常走「每个任务派实现者 + 审查者」。**这轮不那样做**，理由：

- Task 2→5 是同一条**紧耦合**的配置链（生成目录 → 改 gradle → 改清单 → 构建验证），
  拆开派给不同 subagent 意味着每个都要从头读一遍 CLAUDE.md / 规格 / 四份插件源码，
  而它们改的是同一批文件——拆开只有开销，没有隔离收益。
- 真正的风险不在「写得对不对」，而在**「照抄了文档里那句没核过的话」**。
  所以审查集中在末尾做一次：派**一个独立审查者**，只拿着规格与产物去核
  「清单里每一条是不是真的需要 / 真的合并进来了」，**不许看我的实现理由**。

## 交付顺序

Task 1 是环境前置（不入库），2→5 是本体，6 是文档，7 是独立审查。
每一轮结束都跑 `dart format .` / `flutter analyze` / `flutter test`。

---

## Task 1：本机装 Flutter 3.47.5（环境改动，不入库）

**交付物**

- `C:\src\flutter-3.47.5`（Flutter 3.47.5 / Dart 3.13.4）。
- **与已有的 `C:\src\flutter`（3.16.7）并存**，不改 PATH、不动旧 SDK。

**约束**

- 装 3.47.5 而不是 latest（3.47.7）：README 记录的基线是 3.47.5，
  `pubspec.lock` 要求 `dart >=3.13.0`——3.47.5 带 Dart 3.13.4，**与锁文件同源**。
- **不要设 `PUB_HOSTED_URL`**（README 已警告）：会把 `pubspec.lock` 里上百条
  `url: "https://pub.dev"` 改写成镜像地址，制造一个与依赖无关的巨型 diff。

**验收**：`C:\src\flutter-3.47.5\bin\flutter.bat --version` 报 3.47.5；
`C:\src\flutter\bin\flutter.bat --version` 仍报 3.16.7（旧 SDK 没被动过）。

---

## Task 2：生成 `android/` 平台目录

**交付物**

- `flutter create --platforms=android .` 生成的 `android/` 目录。
- `.metadata` 的 `migration.platforms` 多一条 `android`。

**约束**

- **必须用 `flutter create`**，不手写（理由见规格 §4.1）。
- 生成**只增不改**：跑完 `git status` 应只有 `android/` 新增与 `.metadata` 一处改动。
  若 `flutter create` 动了 `ios/` / `macos/` / `web/` / `lib/`，**先查再决定**，不许直接接受。

**验收**：`git status --short` 里没有期望之外的路径。

---

## Task 3：构建参数（gradle）

**交付物**

- `android/app/build.gradle.kts`：`minSdk` ≥ 24、Java/Kotlin 目标 17、
  **`isCoreLibraryDesugaringEnabled = true` + `coreLibraryDesugaring(...desugar_jdk_libs...)`**。
- `android/gradle.properties`：如需，加 `android.useAndroidX=true` 等模板之外的项。

**约束**

- 下界**只按插件的真实要求上调**，依据是规格 §4.2 那张表（读的是插件源码，不是文档）。
- **desugaring 那两条必须成对**：只开开关不加依赖，或只加依赖不开开关，都会在编译期炸，
  且报错长得像「SDK 版本不对」。

**验收**：`flutter build apk --debug` 通过。

---

## Task 4：清单（`android/app/src/main/AndroidManifest.xml`）

**交付物**（逐条依据见规格 §4.3）

- `android:label` = 「夜深」。
- `<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>`。
- `RECEIVE_BOOT_COMPLETED` 之外再补 `FOREGROUND_SERVICE` 与
  `FOREGROUND_SERVICE_MICROPHONE`（**声明了不等于能用**，见规格 §5.1）。
- `<receiver>` 两个：`ScheduledNotificationReceiver`（`exported="false"`）、
  `ScheduledNotificationBootReceiver`（`exported="false"` + **四个** action：
  `BOOT_COMPLETED` / `MY_PACKAGE_REPLACED` / `QUICKBOOT_POWERON` /
  `com.htc.intent.action.QUICKBOOT_POWERON`——最后那个 HTC 的别漏，片段照抄插件 22.3.1 的 README）。
- **不加** `POST_NOTIFICATIONS` / `VIBRATE`（插件 manifest 已合并）、
  **不加** `RECORD_AUDIO`（`record_android` 已合并）、**不加** `<service>`（无实现）。

**约束**

- 每条都要**留一行注释说明「为什么加 / 为什么不加」**，风格照 `reminders.dart` 里那些注释。
  这个仓库的规矩是：**不写理由的配置，下一个人会当成遗漏补上**。
- `flutter_local_notifications` 的 receiver 类名若在不同大版本间变过，以**本轮装的版本**为准。

**验收**：见 Task 5 的合并清单核对。

---

## Task 5：验证

**交付物**：一串真实跑过的命令与结果。

1. `flutter pub get`（**不设镜像**）
2. `dart format .` → 无多余改动
3. `flutter analyze` → No issues found
4. `flutter test` → 全绿，**条数与本轮之前一致**（Dart 侧没改，条数变了就是碰了代码）
5. `flutter build apk --debug`
6. **读合并后的清单**：`build/app/intermediates/merged_manifests/debug/.../AndroidManifest.xml`，
   逐条比对规格 §4.3 的表

**约束**

- 第 6 步**不能省**。构建通过只证明「合并没报错」，证明不了「该合并的真的合并了」——
  而这个包里正好有一半的权限（`POST_NOTIFICATIONS` / `VIBRATE` / `RECORD_AUDIO`）
  **我们没写、全靠合并**。
- 环境/网络导致的偶发失败（Gradle 拉依赖超时）**原样重跑**，别改配置绕过去。

**验收**：6 条全过，且第 6 步的输出贴进 README「验证记录」。

### 网络：这一轮真正的拦路虎（`flutter build apk` 卡死）

第 5 步在本机**第一次没有跑通**，卡在 Gradle 而不是配置。两个独立的坑，都记进
README「构建 Android 的网络前提」：

1. **Gradle 发行包**：`services.gradle.org` 实测 177 KB/s 且会断，`.part` 停在 4 MB。
   不改仓库里的 `distributionUrl`（模板文件，改成镜像会污染仓库），手工下好放进
   wrapper 缓存目录（腾讯镜像 4 MB/s）。
2. **Maven 依赖**：`dl.google.com` / `repo.maven.apache.org` 长时间停滞，
   daemon 挂着一批 established 连接收不到数据，**10 分钟 Maven 缓存零写入**。
   诊断信号：

   ```bash
   find ~/.gradle/caches/modules-2/files-2.1 -type f -newermt "-5 minutes" | wc -l
   ```

**解法是内联的，不是常驻的**——CLAUDE.md 明写「不要往 shell profile 里写环境变量」，
`~/.gradle/init.d/` 属于同一类常驻配置，会改到本机所有 Gradle 工程。所以脚本放临时目录、
用 `-I` 只作用于这一次构建（脚本原文见下）：

```powershell
& "D:\backup\code\flutter\night_sleep\android\gradlew.bat" `
  -p "D:\backup\code\flutter\night_sleep\android" `
  -I "$env:TEMP\night_sleep_cn_mirrors.gradle" assembleDebug --console=plain
```

```groovy
// $env:TEMP\night_sleep_cn_mirrors.gradle —— 只改地址、不改仓库顺序，镜像缺什么回落到原仓库
def rewrite = { repo ->
    if (repo instanceof org.gradle.api.artifacts.repositories.MavenArtifactRepository) {
        def url = repo.url.toString()
        if (url.startsWith('https://dl.google.com/dl/android/maven2')) {
            repo.url = 'https://maven.aliyun.com/repository/google'
        } else if (url.startsWith('https://repo.maven.apache.org/maven2') ||
                   url.startsWith('https://repo1.maven.org/maven2')) {
            repo.url = 'https://maven.aliyun.com/repository/public'
        } else if (url.startsWith('https://plugins.gradle.org/m2')) {
            repo.url = 'https://maven.aliyun.com/repository/gradle-plugin'
        }
    }
}
settingsEvaluated { settings -> settings.pluginManagement.repositories.all(rewrite) }
allprojects { p ->
    p.buildscript.repositories.all(rewrite)
    p.repositories.all(rewrite)
}
```

**这条要用「缓存计数」来验，不能靠命令退出码**：编辑器的 Gradle 同步会静默吃掉这些
下载失败，只在角落转圈。

---

## Task 6：文档同步

**交付物**

- `README.md`：
  - 「环境要求」订正两句（Android SDK **已装**、补 JDK 17）与 Flutter 版本说明；
  - 「未实现」表：Android 行重写（平台目录已生成），并按需拆出「Android 上已知的界面缺陷」。
    （**订正**：交付时实际列了**五笔**——后台录音 / 去系统设置 / 罗盘 / `allowBackup` /
    发布阻塞，不是这里写的三笔；其中**罗盘一笔已于 v3.12（2026-10-13）关闭**。）
  - 「平台配置」补 Android 段；
  - 「验证记录」加本轮一段（跑过的、**没跑过的**分别写）。
- `CHANGELOG.md`：新版本号一段（`3.11`），记本轮改了什么、**以及刻意没做什么**。
- 总规格 `2026-09-28-night-sleep-design.md` §10 第 6 条：订正「Android 的 `RECORD_AUDIO`
  用途串随平台目录生成时一并补」——**Android 没有用途串这回事**（那是 `Info.plist` 的机制），
  且 `RECORD_AUDIO` 由插件合并，应用侧不声明。
- 上游两处规格里「**本轮无法执行**：仓库里没有 `android/` 目录」的回填：
  - `2026-09-28-export-and-reminders-design.md` §「平台接线」Android 行；
  - `2026-10-03-night-audio-recording-design.md` §七 Android 行。
- `docs/architecture.md`：若「平台服务」一节提到了平台目录的存在与否，一并订正。

**约束**

- 规格是活文档，**原地更新，不新开文件**（CLAUDE.md 明写）。
- 「未验证」必须写「未验证」，不许因为构建通过就写成已验证。
  **构建通过 ≠ 通知会响 ≠ 录音能用** —— v3.9 那一段已经立过这个规矩。

**验收**：`git diff --stat` 里没有 `lib/` 与 `test/`。

---

## Task 7：独立审查（一个 subagent，集中在末尾做一次）

**交付物**：一份审查结论。

**派发内容**：**只给规格 §4.2 / §4.3 与最终的 `android/` 目录**，要求审查者：

1. 读**真实的插件源码**（`~/.pub-cache/hosted/pub.dev/<plugin>/android/...`），
   独立核一遍「哪条权限/receiver 是插件已经合并的、哪条必须应用自己声明」；
2. 核 `minSdk` / `compileSdk` / Java 版本 / desugaring 是否覆盖**全部**插件的下界
   （不只 `flutter_local_notifications`）；
3. 核 `android:label` 是否与另外三端一致；
4. **逐条指出规格 §4.3 表里写错的地方**。

**约束**：审查者**不看**我的实现理由与本文档，只拿规格与产物对照。
「规格说的」不算依据——**依据只有插件源码本身**。

**验收**：审查结论逐条落地（改掉或写明为什么不改）。
