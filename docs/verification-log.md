# 验证记录

**这份文档记录「某一次验收在什么环境下跑出了什么结果」，以及每一次**没能**验证的东西。**
按时间**倒序**，最新在最上面。

它是从 `README.md` 的「验证记录」一节拆出来的（v3.14，2026-10-13）：那一节到拆之前已经
**584 行、占 README 的 51%**，而且只增不减——README 是「怎么跑、能干什么」，不该兼做流水账。

**v3.17（2026-10-13）起，README 里不再保留任何一版。** v3.14 拆出本文时留了一条尾巴——
「最近一版仍留在 README」；使用方随后明确要求**全部搬走**，README 里连指针式的一段都不留。
所以**逐版记录的唯一位置就是本文**，按时间倒序，最新在最上面。
（README 里仍有若干「见验证记录」的行内链接指向本文，那是描述具体能力时指路用的，不是记录本身。）

三处分工是刻意划的，别混（沿自[文档重组设计](superpowers/specs/2026-09-28-docs-reorganization-design.md)）：

| 想知道 | 去哪 |
| --- | --- |
| 怎么跑起来、现在能干什么 | [`README.md`](../README.md) |
| **哪些场景被覆盖** | [总规格 §9 测试矩阵](superpowers/specs/2026-09-28-night-sleep-design.md) |
| **某一次验收跑出了什么**（含未验证项） | 本文 |

**「未验证」那一半是本文的重点。** 规格书禁止把没做过的事写成已完成（总规格 §8 立的规矩），
那些红线的凭据就在这里——所以这里的每一条「已验证」都必须带着判据（命令与输出、测试用例名、
真机读数），每一条没做的都必须留在「未验证」里，不许悄悄消失。

本机环境：macOS 14.8.9（23J631，Intel），Flutter 3.47.5 stable。

**补录（v3.18，2026-10-13：罗盘的两条历史验收记录，从 README 移入）：**

下面两条原先写在 `README.md`「罗盘」一节的末尾。README 的职责是「怎么跑、能干什么」，
不该留验收记录（v3.17 立的规矩），而这两条**在全仓库只此一份**（`347` / `43 项` /
`罗盘独立` 都只出现在那里），所以按「搬位置、内容一份不删」的原则移入本文：
**原文照录，日期保持原样**。

- 罗盘独立开发验证：43 项相关单元/组件测试通过，Dart 静态分析无问题，iOS 模拟器构建成功；
  模拟器原生通道已确认返回不可用而非假方位。
- 合入最新 master 后复验（2026-10-02）：完整测试集 347/347 通过，Dart 静态分析无问题；
  罗盘入口测试已适配共享路由和睡眠会话状态。

**移入的只是记录，别当成当前状态**：那之后罗盘又接过 Android（v3.12，见下），并且留下一条
**尚未定案**的未验证项——我们的读数与系统自带 `com.miui.compass` 差 **43°**。当前的罗盘状态
以 v3.12 条目为准，上面两条只是 2026-10-02 那个时点的历史。

**v3.24（2026-10-14：Android 构建的跨盘 Kotlin 缓存失败——定位并固化绕行）——Windows 11 / Flutter 3.47.5 / Android SDK 36：**

使用方报「启动报错」。失败在 `flutter run -d e0e60672` 的 `assembleDebug` 阶段：
`FAILURE: Build completed with 6 failures.`，每个 Kotlin 插件各一条

```
Could not close incremental caches in …/build/<plugin>/kotlin/compileDebugKotlin/cacheable/caches-jvm/jvm/kotlin: …tab
```

**成因是跨盘，不是旧文猜的「杀软占句柄」。** 本机 pub 缓存在 `C:`、工程在 `D:`，而增量编译缓存存的是
源码根的**绝对路径**，两个盘建不出公共根。判据是紧跟在报错下面、**最容易被截断掉的那几层**：

```
Suppressed: java.lang.IllegalArgumentException: this and base files have different roots:
  C:\Users\…\Pub\Cache\…\flutter_timezone-…\android\src\main\kotlin\… and D:\…\night_sleep\android
```

改了什么、为什么这次进了仓库，见 [`CHANGELOG.md`](../CHANGELOG.md) 3.24 与 README「构建 Android 的
网络前提」（那一节同时订正了两处错说法）。

- **跑过的（本机构建 + 真机，判据都是命令行）**：
  - **先清场**：失败构建留下的三个进程（gradle daemon / kotlin daemon / wrapper 客户端）会攥着
    工程锁让新构建干等，`android/gradlew.bat --stop` —— `--stop` 之后三个都退干净了。
  - `flutter build apk --debug -P kotlin.incremental=false -P kotlin.compiler.execution.strategy=in-process`
    —— **51.7s 成功**（此前 6 failures）。
  - `flutter clean` 之后 `flutter build apk --debug`（**不带任何参数**）—— **57.1s 成功**。
    **必须 clean 才作数**：前一次构建用的就是这两个值，不 clean 的话 Gradle 会判成 UP-TO-DATE，
    等于什么都没验证。
  - `flutter run -d e0e60672`（**不带任何参数**）—— 32s 内 `Syncing files to device MI 9` +
    `A Dart VM Service on MI 9 is available at: http://127.0.0.1:7089/…`。
  - **真机**：`adb install -r -g` 后进程正常、logcat 无 `FATAL` / `AndroidRuntime`；截图确认首页
    渲染正常（演示数据横幅、7h26m、三个阶段显示 `—` 并注明「没有睡眠阶段数据」）。
  - 顺带确认 **3.47.5 的 `flutter build` / `flutter run` 确实有 `-P, --android-project-arg`**，
    旧文「`flutter build apk` 传不了 `-P`」不成立（`--help` 与实跑各验一次）。

- **未验证的（不许当成验过）**：
  - **`kotlin.incremental=false` 单独一条够不够**——实测的是它与 `in-process` 的组合，没拆开试。
  - **单盘机器与 CI 上的表现**：按推断那两行可以整体删掉（已注在文件里），但**没有那样的机器可试**，
    所以 README 里也没写成「一定可删」。
  - `dart format` / `flutter analyze` / `flutter test` **一律没跑**：本轮不含任何 Dart 代码改动，
    跑了也证明不了这个改动。上一次全量仍是 v3.23 的 628 通过 / 1 失败（失败的是未跟踪的模板桩）。
  - **热重载没试**：验证用的那个 `flutter run` 是后台跑起来看日志的，没有 stdin 可敲 `r`，确认启动
    后即停掉。所以「能跑起来」验过了，「改一行能不能热重载」没验。

**真机上被动过的东西**：重装过一次 debug APK（`adb install -r -g` —— 这台 MIUI 的运行时权限只能靠
`-g`，`pm grant` 无效）。设备侧设置（`stay_on_while_plugged_in` 等）**没有改动**。

**v3.23（2026-10-14：滚轮照 iOS 闹钟重做交互——循环 / 行距 36 / 选中底色）——Windows 11 / Flutter 3.47.5：**

使用方提的三件事：**时刻能循环**（「到底了就无法滚动了，体验不好」）、**行距小一点**、
**给当前值一个底色**（参考 iOS 闹钟）。改了什么、为什么这么改，见 [`CHANGELOG.md`](../CHANGELOG.md)
3.23 与规格 §8 偏差 #53 / #54 / #55，本文只记跑了什么、没跑什么。

- **跑过的（本机离线，没有上真机、没有真手指）**：
  - `dart format`、`flutter analyze` —— 只有 1 条**既有**问题（未跟踪的模板桩
    `test/widget_test.dart` 引用不存在的 `MyApp`，**没有动它**）。
  - `flutter test` —— **628 通过 / 1 失败**；失败的就是那个模板桩。基线 624，本轮 +4 条。
  - **新增 4 条**（`test/wheel_picker_test.dart`）：小时滚过 23 绕回 00 且分钟列不被冲掉、
    从 00 往回滚绕到 23:59 一侧、选中底色的几何与颜色、日期列不循环。
  - **变异验证（两次，都是拿真东西换，不是编一个假的）**：
    ① 把循环列的 `childCount: null` 报成有限的 `_length` → **两条绕回用例变红**，症状正是
    「滚到底就停住」（`23:50` / `00:00` 原样不动）；
    ② 换回 HEAD 的原实现 → 三条多列一致性用例变红（沿用 v3.22 那次的做法）。
  - **离屏渲染目视检查**：写了一个临时 golden 测试（`flutter test --update-goldens`）把弹层
    渲染成 PNG 再肉眼看——浅色主题的时间选择器、深色主题的日期选择器各一张。看完即删
    （临时测试与 `test/goldens/` 都不留在仓库里）。看到的三件事：底色压在正中间那一行、
    宽度贴合数字（没有横贯整个弹层）、三列对齐。**测试环境用的是方块占位字体**，所以那两张图
    只能验几何、验不了字形与真实字宽（见「未验证」）。
  - **甩动行程实测**（循环列特有的风险：有界时末端会夹住，无限行程下没人夹）：一个 400px 的
    一划，在 600 / 1000 / 2500 / 6000 px·s⁻¹ 下分别停在第 **13 / 17 / 38 / 60** 格
    （起点 12:00，含拖动本身的 11 格）。读数与「Flutter 那套 physics 一行没改、只是末端不再
    截断」对得上——**没有出现「甩一下就飞很远」的新病**。
  - **顺手订正一条自己的错误假设**：第一版测试辅助函数按「起手会有 20px 被吃掉」给位移补了
    半格，结果落点全偏——实测 `tester.drag` 的整段位移都会进到滚动里（44px 行距拖 88px 恰好
    落在第 2 格；补半格变成 154px 则停在 3.5 格）。已改成整数倍行距，并把这条写进用例注释。

- **未验证的（不许当成验过）**：
  - **真手指没碰过。** 全部用例走的是 `tester.drag` / `tester.fling` 合成手势。真机上「循环列
    连着甩好几圈」的观感、以及**触感反馈**（每过一格一次 `AppHaptics.select()`）在连续循环时
    会不会密到发麻，**没测**。
  - **行距 36 是拍的值，没在真机上标定。** 依据只有两条：使用方要「小一点」，以及 iOS 系统
    闹钟自己约 43pt（所以 36 比 iOS 更紧）。滚起来累不累、字会不会显得挤，得真机上看。
  - **底色的对比度没量过。** 用的是令牌里的 `accentSoft`（浅色 `rgba(0,122,255,.12)`、深色
    `.20`），与标签条选中态同一支；在浅色玻璃面板与**会话页那个不走 `AppTokens` 的夜间弹层**
    上各自是什么观感，**只有浅色 + 深色两张离屏图**，而且那两张图里的字是方块（上面那条）。
  - **循环列的读屏语义没查。** 无限行程意味着内部下标会一直增长/变负，`ListWheelChildLoopingListDelegate`
    与 `childCount: null` 会给 `IndexedSemantics` 一个越界/负的下标；屏幕阅读器把小时念成什么
    **没人听过**。
  - **日期选择器的 `now` 注入只在测试里用过**；跨年运行、或系统时间被改到五年窗口之外时三个列
    的表现仍然**没测**（沿用 v3.22 那条）。
  - `integration_test/` 没跑（要 `flutter drive`）；README 说的「界面截图巡检」也没跑——本轮
    的图是离屏渲染的，不是真机截图。

**v3.22（2026-10-14：修滚轮选择器「选完分钟把小时弹回去」）——Windows 11 / Flutter 3.47.5：**

使用方报的缺陷：**先滚小时、再滚分钟，点「完成」小时回到原值；只滚小时是对的**。改了什么、
为什么这么改，见 [`CHANGELOG.md`](../CHANGELOG.md) 3.22，本文只记跑了什么、没跑什么。

- **跑过的（本机离线，没有上真机、没有真手指）**：
  - `dart format lib/core/widgets/wheel_picker.dart test/wheel_picker_test.dart` —— 1 个文件有改动。
  - `flutter analyze` —— **只有 1 条，且是既有问题**：未跟踪的模板桩 `test/widget_test.dart`
    引用不存在的 `MyApp`（`flutter create` 留下的，与本次改动无关，**没有动它**）。
  - `flutter test` —— **624 通过 / 1 失败**；失败的那一条就是上面那个模板桩（加载期编译失败）。
    其余用例全绿，含 `reminder_settings_test.dart` 里那条靠拖滚轮 + 点「取消」的既有用例。
  - **新增 4 条**（`test/wheel_picker_test.dart`）：先滚小时再滚分钟、先滚分钟再滚小时、
    只滚小时、先滚年再滚月（含日列行数断言）。搭台刻意照着真实调用点的形状——`value` 是局部
    变量、靠 `onChanged` 回写；把 picker 包进会重建的宿主会把病灶遮掉，用例就成了空跑。
  - **变异验证（用的是 HEAD 的原实现，不是随手编的「假变异」）**：`git show HEAD:` 把原
    `wheel_picker.dart` 换回来跑同一套用例 —— **三条核心用例全红，症状与使用方所报逐字一致**
    （`23:03` / `21:00` / `2026-02-28`），而「只滚小时」那条**仍然绿**，正好对上「只选小时是对的」。
    这一步筛掉了一个自欺的中间版本：第一版变异是「在原实现里保留 build 时常量」，它**没有变红**——
    因为 `_select` 自己 `setState` 会重建 widget、闭包随之刷新，而原实现的病根恰恰是
    「picker 是 `StatelessWidget`、父层送不进新值、永不重建」。**假变异比没有变异更危险**：
    它会让一条空跑的用例看起来被验证过。
  - **修日期选择器时浮出来的第二个问题**：日列随月份收窄（31 行 → 28 行）会让
    `WheelColumn.didUpdateWidget` 里的 `jumpToItem` **同步**回调 `onSelectedItemChanged`，
    于是在 build 期间又喊一次 `onChanged` → `setState() called during build`，用例当场炸。
    处理办法是「值没变就不回调」（见 CHANGELOG 3.22 取舍 2），不是把断言绕开。

- **未验证的（不许当成验过）**：
  - **真手指没碰过。** 四条用例走的都是 `tester.drag`（合成手势、松手速度为零）。真机上
    **带惯性的甩动**之后再点「完成」会走到哪一格、松手那一瞬的吸附与 `jumpToItem` 会不会互相
    较劲，**没测**。
  - **弹层打开期间父层 `setState` 的那些组合没覆盖。** 回顾页补录那一处 `onChanged` 里是
    `setState`（会顺带重算 `_window` 与「睡眠时长是否合理」的提示），会话页那处是普通局部变量。
    两条形态各写了一条用例，但**真机上整条链路（含时长提示实时变化）没人走过**。
  - **日期轮盘「日列收窄」在真机上没人肉眼看过。** 断言的是 `ListWheelChildBuilderDelegate`
    的行数，不是渲染结果；滚动位置在收窄之后落得对不对（会不会视觉上跳一下）只能靠肉眼，
    而这一步没做。
  - **`AppDatePicker` 的五年窗口（今天 ±2 年）没验**：跨年运行、或系统时间被改到窗口外时
    三个列各自是什么表现，**没测**（`_adopt` 用今天补缺项的那条分支只有单测覆盖）。
  - `integration_test/` 没跑（要 `flutter drive`），真机上的截图巡检也没有。

**v3.20–v3.21（2026-10-14：把 v3.19 那两条查出来的问题修掉）——Windows 11 / Flutter 3.47.5：**

承接 v3.19 的实测，这一轮改了两处代码：**平台静音时不再谎报「录音中」**（v3.20）、
**删记录 / 删全部数据时把音频文件一起删掉**（v3.21）。改了什么、为什么这么改，见
[`CHANGELOG.md`](../CHANGELOG.md) 这两条，本文只记跑了什么、没跑什么。

- **跑过的（都是本机离线，没有上真机）**：
  - `dart format .` —— 160 个文件，0 改动。
  - `flutter analyze` —— **No issues found**。
  - `flutter test` —— **620/620 通过**（基线 609；v3.20 加 7 条、v3.21 加 4 条）。
    新增的用例点名：`test/night_recorder_test.dart` 的「平台静音」组 5 条；
    `test/sleep_session_page_test.dart` 的「真在录的时候…灯亮着」与「平台把麦克风静音时
    如实说出来，并且那盏灯不许亮」；`test/clip_pruning_test.dart` 的「删记录 / 删全部数据
    都带走音频」3 条；`test/record_edit_delete_test.dart` 的「确认后记录被删除，并且真的
    走到了删录音文件那一步」。
  - **顺手修掉一个自己踩的坑**：最后那条 UI 用例第一版在 `testWidgets` 的测试体里直接做真实
    文件 I/O（`Directory.createTemp` + `File.writeAsBytes`），**不报错、挂满 10 分钟**才吐一行
    `TimeoutException`。判据是**进程 CPU 而不是等待时长**（`flutter_tester` 活着但 CPU 几乎
    不动）。已写进 `.claude/skills/flutter-pitfalls/SKILL.md`——那份 skill 此前只记了
    「平台通道的 Future 永不完成」，现在把 `dart:io` 这一类一起补上了。

- **未验证的（这一轮一条都没上真机，不许当成验过）**：
  - **`kSilentMicRun = 60 秒` 这个阈值没有在真机上标定过。** 它按 §三 那七个参数同一口径
    先拍一个值：唯一有依据的是「这台机器上这间房的本底约 −55 dBFS，逐样本全零与安静是
    两回事」，60 秒够不够短、会不会该触发时没触发，**没测**。
  - **`silenced` 这一态在真机上长什么样，没人看过。** v3.19 那次对照实验里灭屏 ~70 秒后
    平台才静音端口，也就是说**用户会先看到大约一分多钟的「录音中」**才等到那句话——这段
    延迟在真机上是什么观感，未知。
  - **`silenced` 与白噪音、与开关、与中断的交互只有单测覆盖**（`session_events_card.dart`
    那一行是 switch 的穷尽分支，编译器盯着；但没有一条用例在真机上跑过整条链路）。
  - **不是所有 Android 机器都这样。** 「离开前台 → 平台静音端口并交付零样本」这条在
    MI 9 / Android 11 / MIUI 12.5.6 上是实测的；别的厂商、别的版本是不是同样行为、会不会
    干脆把录音轨拆掉（那样 `record` 插件就会报中断、走 `stopped` 而不是 `silenced`），
    **未知**。
  - **前台服务仍然没做**，所以整夜录音在 Android 上仍然录不到声音——v3.20 只是让界面说了
    实话，**没有让功能变得可用**。这条和 v3.19 一样，一个字都没变。
  - **删记录那条路径也没上真机。** 单测里验的是「走到了文件仓库」与「文件真的被删」两件事
    （后者在普通 `test()` 里用真文件系统跑的），但**真机上删一晚带 4 段录音的记录**这个
    动作没人做过。

**v3.19（2026-10-13：真机跑了一整晚的夜间录音——链路完好，但那 7 小时是平台交上来的数字静音；已用对照实验定案）——Windows 11 / Flutter 3.47.5 / Android SDK 36：**

真机同上：Xiaomi MI 9（`cepheus`，adb serial `e0e60672`），**Android 11（API 30）/ MIUI 12.5.6 / arm64-v8a**。

**这一晚是使用方自己开着的真实会话，不是复现**：2026-10-13 01:22:49 → 08:30:21（7h07m），
库里落成 `source = 'session'` 的一条记录（quality 4）与 4 条 `source = 'recording'` 片段。
**Dart 代码一行未改**，因此**没有复跑** `flutter analyze` / `flutter test`（上一次是 v3.13 的 609/609）。
判据全部是 `adb exec-out run-as … cat` 拉下来的库与 WAV、离线按源码逐字复算，
以及 `dumpsys appops` / `dumpsys batterystats --history` / `dumpsys package` 的原始输出。
**踩过一个坑记在这里**：`adb shell "run-as … cat 库文件"` 会把二进制写坏（61440 → 61466 字节，
`sqlite3` 直接报 `database disk image is malformed`）；**必须用 `adb exec-out`**。

**真机上被改动过的东西记一笔**（使用方在收尾前明确选了「全清」那一项才做）：对照实验用
`adb shell input` 新起过一个会话（23:43:55 → 23:55:13），结束后把这个实验记录删掉、
再冷启动了一次——因此本文提到的 12 个孤儿 WAV（3 个旧孤儿 + 9 段实验片段）
**已经从设备上消失**，昨晚那 4 段与那条 7h07m 的记录原样保留。

- **跑过的（真机拉数据 + 离线复算）**：
  - **WAV 容器与格式逐条正确**：4 条片段都是 44 字节标准头、`PCM=1 / 1 声道 / 16000 Hz / 16 bit`、
    `byte_rate=32000`、`block_align=2`，`data` 块长度与库里的 `duration_ms` **逐条相等**
    （1.4s→44800B、1.0s→32000B、3.5s→112000B、10.8s→345600B），无尾部多余字节。
  - **波形包络是真的，且能由音频复现**：用源码里同一个 `_rmsDbfs`（逐 100 ms 一格 RMS→dBFS）
    与 `envelopeFor` 从 WAV 反算，库里的 `waveform_envelope` 是它的**严格仿射像**——
    落在文件内的 36–38 格**逐格误差 ≤ 5.5e-16**（解出的归一化上下界就等于该片段的窗口极值）。
    也就是说采集 → 聚合 → 切片 → 落盘 → 包络这条链**自洽**，没有编出来的柱子。
  - **采集端整夜只起过一次**：4 条片段 id 的微秒尾数全是 `00532`，而
    `id = _sessionStartUtc + 切片偏移`（偏移恒为 100 ms 的整数倍）——`_reset()` 只在 `start()`
    里调，所以这四条**共用同一个 `_sessionStartUtc`**，即麦克风从 01:22 到 08:30 **一次起、
    中途没有重启过**（重启会换掉那 5 位尾数，概率 1e-5）。
  - 音频内容也是真的：前三条的底噪在 −55…−63 dBFS，峰值 −7.6 dBFS，无逐样本全零的窗。
  - 界面侧对得上：首页「昨夜睡眠 7h 7m，01:22 → 08:30」，深睡/浅睡/REM 三格显示「—」并写明
    「这一晚没有睡眠阶段数据」——**没有伪造阶段**，符合 §8 的红线。

- **跑过的（判定性对照实验，2026-10-13 23:43–23:53，同一台机器）**：
  这一轮把「平台在应用离开前台之后静音它的录音端口」从推断做成了实测。做法是在真机上
  **用 `adb shell input tap` 新起一个会话**（只点了「开始入睡 → 开始睡眠」，没碰任何删除类按钮），
  然后反复读 `dumpsys media.audio_flinger` 里那条轨道的 `Sil` 列：

  ```
  Active  Id Client Session Port Id  S  Flags   Format Chn mask  SRate Source   Server FrmCnt FrmRdy Sil Latency
     yes 132  22550     977     135  A  0x000 00000001 00000010  16000      0 00696540   1280    320   n   22.03 t
  ```

  `Client = 22550` **就是本应用的 pid**、`Port Id = 135`——所以日志里那些
  `setRecordSilenced(general), portId:135, appType:0, silenced 1` **静音的正是我们的端口**，
  不是别的应用。三次读数：

  | 时刻 | 应用状态 | `Sil` 列 | 同一时刻的 appops |
  | --- | --- | --- | --- |
  | 会话进行中 | 前台、亮屏 | `n`（未静音） | `allow … (running)` |
  | 灭屏 100 s 后 | 后台 | **`s`（已静音）**，同时打出 `setRecordSilenced… silenced 1` | `allow … (running)` |
  | 唤醒 8 s 后 | 回到前台 | `n`（恢复） | `allow … (running)` |

  **`(running)` 一栏全程没变过**——平台按下了静音键，却没有告诉应用，也没让 `record`
  插件收到任何中断。

  同一会话里还量到两个旁证：

  - **前台那 2.5 分钟录到 7 段，全部是真实音频**：底噪 −52.8…−56.6 dBFS、峰值最高 21714，
    **全零格 0 个**。同一台机器、同一段时间，前台就有本底噪声、后台就只有零样本。
  - **静音窗口里一段都没录到**。灭屏后到唤醒之间那 39 秒（23:45:14 → 23:45:53）落在已静音的
    区间里，文件目录**一个新增都没有**；而它前后的每分钟都在产出片段。
  - `dumpsys media.audio_flinger` 还带一张录音端口的**实时电平表**，前台时读数是
    −54.8…−57.9 dBFS——与拉下来的片段底噪（−55 上下）是同一个量级，
    说明"房间本底约 −55 dBFS、触发阈值 −38 dBFS"这件事也是真的。

- **跑过的（孤儿清理，`deleteOrphanRecordings`——这条路此前一次都没被验证过）**：
  上面那条删除路径留下了 9 个孤儿，加上更早的 3 个，盘上共 16 个 WAV。把应用
  `am force-stop` 后重新拉起，冷启动的 `_pruneRecordings` 跑完再看：

  ```
  冷启动前 16 个 → 冷启动后 4 个
  被扫掉的 12 个 = clip-1791895950756773 / …7901271770 / …7945210484（3 个旧孤儿）
                 + clip-1791906238483497 … …1791906590683497（本次实验那 9 段）
  留下的 4 个   = 昨晚那四条，与 `sound_clips` 里的 4 行一一对应
  ```

  **留下的刚好是"库里有行的那 4 个"，多一个没留、少一个没删**，`adb logcat` 里也没有
  `清理录音失败`。这条路本身是好的——它只是**只在冷启动跑**，所以删除与清空之后到下次
  冷启动之间，文件会一直占着空间。

- **查出来的问题（按严重度）**：
  1. **那 7 小时录到的是数字静音，而应用一直显示「录音中」。** 第 3 条片段在 01:23:35.8 结束，
     下一条要等到 08:30:01；而 08:30 那条的**前 3 格（300 ms）是逐样本全零**——1600 个样本
     **无一非零**，第 4 格起才是有本底噪声的真实音频。真实麦克风不会给出整格的全零，
     所以那是平台"交上来的静音"，不是安静的房间。旁证：灭屏历史
     `01:23:43.777 screen_off → 08:30:11.492 screen_on`（中间 07:53:35–08:03:41 亮过 10 分钟），
     以及 `dumpsys appops` 里 RECORD_AUDIO 的 Access 片段是 `cch`（01:23:33.75，+2.3 s）与
     `bg`（08:03:40.962，+26m37s），**没有一个 `top`**。真实音频只出现在屏幕亮着的那 ~30 秒里。
     **机制已由下面的对照实验定案**（原先只是推断）：平台在应用离开前台后静音它的录音端口。
     诡异之处在于 `record` 插件全程没报中断（流一直在吐零），所以 `NightRecordingController`
     没有理由转成 `stopped`：**应用手里拿到的状态是"正在录"，它说的是实话，只是那句话描述
     不了现实**——与偏差 #7「不让控件声称一个它并不具备的状态」是同一类失败，
     但这次骗过应用的是平台。
  2. **删除记录不清音频——已端到端复现。** `SleepRepository.delete()` / `deleteAllUserData()`
     只删行（`sound_clips` 靠 `onDelete: cascade` 一起没），**磁盘上的 WAV 一个都不删**。
     复现路径与读数：先看到 3 个"来历不明"的孤儿（`clip-1791895950756773` 20:52:30、
     `clip-1791897901271770` 21:25:01、`clip-1791897945210484` 21:26，共 1.5 MB，库里没有
     对应行、也没有活动会话）；随后在对照实验里把这条路径完整走了一遍——
     结束会话（写记录 + 9 条片段行）→ 在睡眠详情里点「删除记录」→ 确认框上写着
     **「声音事件都会被永久删除，此操作无法撤销」** → 点删除。
     **结果：9 条 `sound_clips` 行全没了，9 个 WAV 一个不少地留在盘上。**
     也就是说那句确认文案承诺的事只做到了一半。这些文件要等到**下次冷启动**的孤儿清理
     （`app.dart` 的 `_pruneRecordings` → `deleteOrphanRecordings`）才被扫掉。
  3. **包络尾格越界（小）**：短片段最后 1–2 格的柱高取自 `range.end` 那一格 100 ms，
     而那一格**不在 WAV 里**。1.4 s 的片段越界 1 格（第 37 格）、1.0 s 的越界 2 格（36–37），
     10.8 s 那条恰好没越界。柱子本身是实测的，只是画的是片段之外的一格。
  4. **今晚那三条孤儿 WAV 里有一条长度不对齐**：`clip-1791895950756773` 的 `data` 是 215040 字节
     = 67.2 格，不是 100 ms 的整数倍，而正常路径**只可能**产出整数格（切片两端都是 100 ms 的倍数）。
     其余两条（7.7 s = 77 格、35.6 s = 356 格）是对齐的。最可能是 `_writeClip` 里
     `to` 被 `clamp(from, ring.length)` 夹短了（在 flush 收尾、最后一个窗口还没收满的时候），
     但**没有复现，判不了案**。

- **未验证的（这一轮没做，不许当成做过）**：
  - **回放只沾到一半**。整理详情页时误触到一次播放，`SoundCard` 的走带确实起来了
    （按钮变成停止、读数走到 `0:02 / 0:11`，与那个片段的 10.8 s 吻合），
    但**没有验证过扬声器真的出声**——我这边听不到。WAV 本身只验到"是合法的 44 字节头
    PCM、长度与库里一致"。标注（`updateClipLabel`）这条路这一轮没碰。
  - **前台服务方案本身没做**，所以「加了前台服务就能整夜录到真声音」**仍然只是推断**——
    静音的**原因**已经查清（离开前台），但「前台服务挡得住它」没验：
    `FOREGROUND_SERVICE` / `FOREGROUND_SERVICE_MICROPHONE` 至今只在 manifest 里声明着，
    `dumpsys activity services` 是空的，一个服务都没在跑。
  - **静音的触发条件只定到「离开前台」这一层**：灭屏之后**不是立刻**静音（本次实测里
    灭屏到 `Sil=s` 之间隔了几十秒），是 MIUI 的哪一条规则、延迟多长，没定。
  - **对照实验里「唤醒后再敲一次」那半没有确认到**：计划是灭屏中敲一次、唤醒后敲一次做对照，
    但唤醒后那 30 秒窗口里没有产出新片段，**分不清「没敲」还是「敲了但没触发」**。
    后台那一半有硬读数（静音窗口零新增文件）；前台那一半靠的是同期那 7 段真实音频佐证。
  - **那 3 个旧孤儿具体是哪一次操作留下的，没有定论**。机制查清了（删除路径不删文件，
    已端到端复现），但它们落在 20:52–21:26 那段里，那时应用被重装过（20:55:37）、
    会话行也早已不在，**中间的操作序列无法还原**。
  - **只在 MI 9 / Android 11 / MIUI 12.5.6 上验过**。换机器、换系统版本是否同样静音，未知。
  - **iOS / macOS 没验**——那两个平台的 `getApplicationSupportDirectory()` 与后台录音行为
    与 Android 完全不同，本文一个字都不适用。

**v3.16（2026-10-13：小米手环 9 接上 Gadgetbridge——连接与认证打通，阶段待验）——Windows 11 / Flutter 3.47.5 / Android SDK 36：**

真机同上：Xiaomi MI 9（`cepheus`，adb serial `e0e60672`），**Android 11（API 30）/ MIUI 12.5.6 / arm64-v8a**。
设备：小米手环 9 NFC。

**本轮仍是调研 + 真机实测，Dart 代码一行未改**，因此**没有复跑** `flutter analyze` / `flutter test`
（上一次是 v3.13 的 609/609）。判据全部是 `adb shell` 与 logcat 的原始输出。

- **跑过的（真机）**：
  - **Gadgetbridge 0.95.1 装上了**：从 Codeberg 官方 release 直链下载（21 MB，中途断过一次、断点续传补齐），
    验签通过（`CN=APKSignKey, OU=Gadgetbridge, O=Freeyourgadget`，SHA-256
    `01cce9316fcb77ea02c6dea81fde9f3176469202c0cea0514c0e03cb969bc7be`），zip 完整性 OK。
  - **配对 → RFCOMM 连接 → 认证，全部成功**：
    `BOND_BONDING → BOND_BONDED`；`BtBRQueue(0): Connected to RFCOMM socket for Xiaomi Smart Band 9 9EEF`；
    `XiaomiAuthService: Authenticated, further communications are encrypted`；`XiaomiSupport: onAuthSuccess`。
    **密钥取对了，而且「手环 9 走经典蓝牙」这条现在有三条独立证据**（SDP 记录、官方 App 只发
    `CLASSICAL-CONNECTED`、Gadgetbridge 自己的 `BtBRQueue`）。Gadgetbridge 用的是
    `XiaomiSupport` + `MiBand9Coordinator`，不是老款 Mi Band 那套。
  - **四个坑，判据与处置见规格 §3.3**：① MIUI 的 `force-stop` 压不住小米运动健康——
    它有个 `com.mi.health:device` 子进程会被反复拉起，最终用 `pm disable-user` 停用（`enabled=3`、进程归零）；
    ② **手环不与手机配对时不广播**，从系统蓝牙删掉它之后 Gadgetbridge 就再也扫不到，
    **必须在手环上主动进「连接新手机」模式**（设置 → 系统操作）才会重新广播；
    ③ **扫描列表里混着家电极易选错**——`midea`（美的，广播厂商 ID `1704` = `0x06A8`）被当成手环长按后，
    Gadgetbridge 拿老款 `MiBandSupport` 去连，`NullPointerException: DeviceInfo.isMili1()`、
    派发线程死亡、`GATT_VALUE_NOT_ALLOWED` 断开（**是选错设备，不是缺陷**）；
    ④ 密钥用 `adb shell input text` 从文件直输，避免手抄 32 位出错。
  - **Health Connect 这条对本机是死的**：GMS / Play 商店 / GSF **全部被禁用**
    （`enabled=2`，GMS 零进程），而 Android 11 上的 HC 依赖 Google Play 服务，装上也跑不起来。
- **没跑过的**：
  - **Gadgetbridge 解不解得出睡眠阶段——最要紧的一条，仍未验证。** 连接与认证已通，
    但**它解不解得出深睡/REM、解出来准不准，一概未知**。数据库在 `/data/data/…`
    （无 root 读不了，`Permission denied`），要等它导出到外部目录；
    而且手环里**此刻有没有睡眠数据本身也不确定**（这台手环今晚才与手机配对）。
    **这一条直接决定这条路走不走得下去。**
  - **小米云 API 未实测**；**官方开放平台未申请**；**打开 GMS 再试 Health Connect 没做**；
    **手环数据与手机录音的时钟对齐没碰**。
  - 完整清单见[可行性设计](docs/superpowers/specs/2026-10-13-xiaomi-band-sleep-integration-design.md) §九。
- **本轮新增的结论（写进规格 §6.1）**：「自己用」与「给别人用」是**两个卡点完全不同的问题**。
  ② Gadgetbridge 只可能是「自己用」的方案；要能分发，只剩 ③ 云端登录（有合规风险）
  或 ⑤ Health Connect（覆盖不了国行用户）——**没有第三条**。
  好消息是两条路在应用里长得一样（都是「导入睡眠数据」那一屏），**领域侧共用，先做自己用不白做**。
  另外 Health Connect 的可行性有一条**代码级证据**：小米运动健康的 dex 里有
  `HealthConnectApi` / `HealthConnectSyncDao` / `PLATFORM_TO_SDK_SLEEP_STAGE_TYPE` / `STAGE_TYPE_AWAKE`
  ——**有一张阶段映射表，说明它在写阶段**（但这是代码证据，不是实测）。

**v3.15（2026-10-13：小米手环睡眠数据接入可行性判定）——Windows 11 / Flutter 3.47.5 / Android SDK 36：**

真机同上：Xiaomi MI 9（`cepheus`，adb serial `e0e60672`），**Android 11（API 30）/ MIUI 12.5.6 / arm64-v8a**。
设备：小米手环 9 NFC（本轮首次与这台手机配对）。

**本轮是调研 + 真机实测，Dart 代码一行未改**，因此**没有复跑** `flutter analyze` / `flutter test`
（上一次是 v3.13 的 609/609）。判据全部是 `adb shell` 的原始输出。

- **跑过的（真机）**：
  - **国行版小米运动健康的包名是 `com.mi.health`（v3.59.1），不是 `com.xiaomi.wearable`。**
    后者是国际版；Gadgetbridge 官方文档与中文社区所有取密钥教程都写它，**在国行机器上照抄必失败**。
    本机该目录下确有 `XiaomiFit.device.log` / `XiaomiFit.main.log` / `Transfer.device.log`。
  - **设备广播名是 `Xiaomi Smart Band 9 9EEF`，不带 "NFC"**——据此**推翻了本轮调研阶段
    自己的一个推测**（原以为 NFC 版匹配不上 Gadgetbridge 的 `^Xiaomi Smart Band 9 [0-9A-F]{4}$`）。
  - **手环是双模（`[ DUAL ]`），SDP 暴露 `00001101`（Serial Port Profile）、`00001124`（HID）
    与小米自定义 `cc353442-be58-4ea2-876e-11d8d6976366`。**
  - **小米运动健康在 Android 上走经典蓝牙传数据**：`Connection Events` 里只有一条
    `21:57:12 CLASSICAL-CONNECTED … status = Success`，**没有任何 `LE-CONNECTED`**；
    `GATT Client Map` 的 `Entries for mApps: 0`。BLE 侧只用于**扫描发现**
    （9 次 LE 扫描 / 7244 条结果）。**这条把「用 Flutter 的 BLE 插件直连手环」判定为不通。**
  - 配对过程不顺：21:54 连挂两次（`BONDING → NONE`），21:57:10 第三次才 `BONDED`。
  - **BLE 侧探测跑了三轮，都没成功**（自写一次性探针 APK，手搓 `aapt2`+`javac`+`d8`+`apksigner`，不走 gradle、不进仓库）：
    手环在**与手机保持经典连接时不在 BLE 侧广播**——同一抓取窗口里协议栈收到 3 台其他 BLE
    设备的广播（`54:48:e6:ec:60:03` / `7c:c2:94:17:79:db` / `ac:8c:46:26:a3:00`），
    而手环地址 `08:16:d5:73:9e:ef` 出现 **0 次**；按 MAC 直连（协议栈确实受理：
    `clientConnect … isDirect=true, phy=1`）20 秒超时、`onConnectionStateChange` 完全没触发。
    另外 **MIUI 会把 BLE 扫描结果对第三方 App 屏蔽**（协议栈统计 `Total number of results: 0`，
    而同一时间它在处理别人的广播包；`install -g` / `pm grant` / `cmd appops set --uid` 都解不开，
    `COARSE_LOCATION` 的 Uid mode 始终是 `ignore`）。
- **没跑过的**：
  - **GATT 枚举没做成**——上面三轮都失败了，所以手环 BLE 侧**是否开放 miwear 协议通道仍然未知**；
    要把这问题问到底得先解绑手环**并且**绕过 MIUI 的扫描屏蔽，而「解绑后手环是否就会在
    BLE 侧广播」本身也没验证过——**代价超过问题本身的价值，建议搁置**；
  - **没有提取手环配对密钥**（本轮使用方裁定暂不提取，理由与拦截记录见规格 §七），
    因此**没有任何一条路径被真机跑通过**；
  - **Gadgetbridge 未安装、未试连**；**小米云 API 未实测**；**官方开放平台未申请**；
  - **手环数据与手机录音的时钟对齐没碰**。
  - 完整清单见[可行性设计](docs/superpowers/specs/2026-10-13-xiaomi-band-sleep-integration-design.md) §九。
- **判定结论**：自写 Dart 协议栈**不值得**（传输层要先写 platform channel，iOS 直接封死，
  Dart 生态零先例）；推荐 **Gadgetbridge 转发**，其次申请**官方开放平台**，
  私有云 API **仅个人自用、不得随应用分发**。见规格 §四–§六。
**v3.13（2026-10-13：Android 系统栏与安全区）——Windows 11 / Flutter 3.47.5 / Android SDK 36：**

真机同上：Xiaomi MI 9（`cepheus`，adb serial `e0e60672`），**Android 11（API 30）/ MIUI 12.5.6 / arm64-v8a**。

- `flutter analyze` 无问题；`flutter test` **609/609 通过**（v3.12 是 592，净增 17）。
- **跑过的（真机，改前 / 改后是同一台机器、同一个页面）**：
  - 顶部：`x=30` 一列逐像素采样，`y<75` 由 `(181,181,186)` 变成 `(241,241,248)` 一类的
    页面背景——**灰带整条消失**；浅色主题下状态栏图标仍是深色。
  - 底部：黑带消失，页面背景铺到 `y=2339`；胶囊底边 `y=2296`、手势条上沿 `y=2310`。
  - 推入页（`外观`，走 `Subpage` 的 `SafeArea`）同样两条栏透明。
  - **浅色应用主题下进常暗的会话页**：状态栏图标如期变白、背景铺到导航栏后面。
  - **应用内切深色而系统仍是浅色**：状态栏与手势条图标双双变白。
- **没跑过的**：**API 29 以下的设备**（引擎 `SDK_INT >= 29` 的门槛让 `edgeToEdge` 成为
  空操作，应维持旧样子）；**API 35 及以上**（本轮用的几个字段在那条线以上是 deprecated
  no-op，系统自己强制 edge-to-edge，预期一样但那是另一套行为）；**iOS / macOS**
  （**状态栏样式的来源被改了**——从跟随系统外观改成跟随应用主题，是本意但没跑过）；
  **三键导航**（安全区约 48dp，胶囊会整个让开——推断，未实测）；**横屏**。
  判据与逐条截图对照见[安卓平台接入设计](superpowers/specs/2026-10-12-android-platform-design.md) §6.4–6.5。
- **本机构建**：`flutter build apk` 撞上 Kotlin 增量缓存时，异常里那句
  `Could not close incremental caches … different roots` 就是根因——**pub 缓存在 `C:`、
  工程在 `D:`**，增量缓存存的是绝对路径，跨盘建不起来（此前记的「疑为杀软占住 `.tab`」
  只是同一现象的另一种猜测）。**绕开 CLI、`cd android` 后直接跑 `gradlew assembleDebug`**，
  带 `-Pkotlin.incremental=false` 与 `-Pkotlin.compiler.execution.strategy=in-process`，
  48 秒完成。**`gradlew` 的 `APP_HOME` 取的是当前目录**（不是脚本所在目录），
  从仓库根跑 `./android/gradlew` 会报 `ClassNotFoundException: GradleWrapperMain`——
  而 wrapper jar 其实好好地在 `android/gradle/wrapper/`。详见「构建 Android 的网络前提」。

**v3.12（2026-10-13：Android 罗盘 + `.metadata` 修复）——Windows 11 / Flutter 3.47.5 / Android SDK 36：**

真机：Xiaomi MI 9（`cepheus`，adb serial `e0e60672`），**Android 11（API 30）/ MIUI 12.5.6 / arm64-v8a**。

- `flutter analyze` 无问题；`flutter test` **592/592 通过**（v3.11 是 588，本轮新增 **4** 例，
  全在 `test/compass_test.dart`——其中一例走 `TargetPlatformVariant`）。
- **跑过的（真机）**：`gradlew assembleDebug` 与 `assembleRelease` 均 BUILD SUCCESSFUL；
  release 包 `app-release.apk` 71 MB，aapt2 核过 `application-label:'夜深'`、targetSdk 36、
  `native-code: arm64-v8a`（含 armeabi-v7a / x86_64），签名是 **Android Debug 证书**（能侧载、不能上架）。
- **罗盘的真机行为**：通道 ~30 Hz 出数；页面从「请使用支持罗盘的 iPhone…」变为实时读数
  （`51°` / `东北 · 艮山` / `手机倾斜 5°`）；平放时 `tilt ≈ 5°`，**正面验证了重力矢量的符号修正**；
  磁场被污染时（实测 259 µT，地磁只有 25–65 µT）**正确地拒绝发布方位**并显示校准提示，
  挪开后降到 62–64 µT、方位随即出现。与系统自带 `com.miui.compass` 的对照**只做到一半**。
- **没跑过的**：上面那条 **43° 的差异未定案**（手机证明过静止）；**横屏 90°/270° 折算未验证**
  （本机自动旋转是关的）；**macOS / Web / 无磁力计设备一律没测**；**Kotlin 侧零单测**。
- **本机的构建坑（三条，都已写进「构建 Android 的网络前提」与记忆）**：绕过 Flutter CLI 直接
  `gradlew assembleRelease` 会因 `integration_test` 是 dev 依赖而报「找不到符号」；
  `flutter build apk` 传不了 `-Pkotlin.incremental=false`，会撞 Kotlin 增量缓存故障；
  **引擎的 ABI jar 来自 `storage.googleapis.com/download.flutter.io`，不在镜像改写范围内**，
  缺 `FLUTTER_STORAGE_BASE_URL` 时 `:app:compileDebugKotlin` 会**挂十几分钟且不报错**——
  诊断靠 `--offline`，它会把「挂住」变成「明确说你缺哪个包」。

**v3.11（2026-10-12：Android 平台接入 + Android 启动图标）——在另一台机器上做的：**

> 本轮是在一台 **Windows 11** 机器上做的（不是上面那台 macOS）。那边的 Flutter 基线一开始
> 根本跑不起来——PATH 上的是 3.16.7 / Dart 3.2.4，解析不了本工程
> （`Because night_sleep requires SDK version >=3.3.0 <4.0.0, version solving failed`）。
> 装了 **3.47.5 / Dart 3.13.4** 到 `C:\src\flutter-3.47.5`，**与旧 SDK 并存、未改 PATH**。
> 因此本节所有命令都是用**绝对路径**调那个 3.47.5 跑的。

- `flutter pub get --enforce-lockfile` → 成功，且 **`pubspec.lock` 零改动**。
  （第一次不加 `--enforce-lockfile` 时 pub 顺手把 `analyzer` 14.4→14.5、`build_runner`
  2.16.1→2.16.2 等一串 dev/传递依赖升了级——与本次改动无关的 diff，已还原并用
  `--enforce-lockfile` 顶住。）**没有设 `PUB_HOSTED_URL`**，锁文件里 129 条
  `url: "https://pub.dev"` 一条没动。
- `dart run build_runner build` → 生成 299 个产物。**这一步是前置**：`app_database.g.dart`
  已 gitignore，新检出里没有它，不生成会得到几百条 `Undefined name 'ActiveSessionsCompanion'`。
- `dart format .` → **无额外改动**；`flutter analyze` → **No issues found**。
- `flutter test` → **588/588 通过**（v3.10 的 584 + 本轮新增 4 条 Android 图标断言）。
  **条数只增不减，且新增的全在图标那一个文件里**——Dart 侧一行未改，这一点由
  `git diff --stat` 里没有 `lib/` 交叉验证。
- `flutter test tool/generate_app_icons.dart` → 通过，**iOS 与 macOS 的图标产物一个字节都没变**
  （`git status` 里没有 `ios/` `macos/` 下的图标文件）——证明重构 `_writeAll` 时没有碰坏
  原有两条渲染路径。
- **Android 图标目视核对（部分）**：`mipmap-xxxhdpi/ic_launcher.png`（满幅渐变 + 月牙 + 声波）
  与 `ic_launcher_foreground.png`（主体居中、四周透明）都**逐张看过**。
  **没有在真机或模拟器的启动器里看过**——那需要设备。
- **Android 图标像素级独立核对**：用 **Python + Pillow**（**不是** Dart 那套代码）重读了产物——
  五个密度下前景 `alpha>8` 的像素**没有一个**落在中央 72dp 圆之外（`pixelsOut=0`）、
  背景与传统位图都是色型 2 且四角不透明、背景层近白像素数为 0、角像素正是渐变起点 `#75D8FF`。
  用另一套工具量同一件事，比让生成器和测试互相印证更有说服力。
- **Android 构建**：`gradlew assembleDebug`（带下面的镜像 `-I`）**成功**（3m19s，452 个任务）。
  产物 `build/app/outputs/flutter-apk/app-debug.apk`（170 MB，debug 含全部 ABI）。
  ⚠️ **但文档里那条 `flutter build apk --debug` 在本机跑不通**——它**不接受 `-I`**，
  拿不到镜像脚本，于是直连 `dl.google.com`，报错却是：

  ```
  > 'kotlin-android' plugin requires one of the Android Gradle plugins.
    Please apply one of the following plugins to ':just_audio' project: …
  [!] Gradle threw an error while downloading artifacts from the network.
  ```

  **别被那句「kotlin-android 插件需要 Android 插件」带偏去查 gradle 配置**——真实原因是 AGP
  压根没拉下来（同一个网络问题）。在这台机器上要让**这条命令**可用，只有两条路：
  ① 配一个**机器级**的 Gradle 镜像（`~/.gradle/init.d/cn-mirrors.gradle`，会影响本机所有
  Gradle 工程）；② 把网络修好（让 `dl.google.com` / `repo.maven.apache.org` 可靠可达）。
  需要时用 ① 的内容见计划文档 Task 5。**本轮走的是「命令行内联」这条路，没有动机器级配置。**
- **合并清单核对（本轮最要紧的一条）**：读的是
  `build/app/intermediates/merged_manifests/debug/processDebugManifest/AndroidManifest.xml`
  ——**不是源码**，只有它同时能证明「我们加对了」与「插件确实合并进来了」：

  | 权限 | 来源 |
  | --- | --- |
  | `RECEIVE_BOOT_COMPLETED`、`FOREGROUND_SERVICE`、`FOREGROUND_SERVICE_MICROPHONE`、`INTERNET` | **应用自己声明**（其中 `INTERNET` 是差点漏掉的那条） |
  | `POST_NOTIFICATIONS`、`VIBRATE` | **`flutter_local_notifications` 22.3.1 合并进来**——证明「不重复声明」的决定成立 |
  | `RECORD_AUDIO` | **`record_android` 2.2.0 合并进来**——订正了上游文档那句「要补 RECORD_AUDIO」 |
  | `ACCESS_NETWORK_STATE`、`DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` | 插件 / AGP 生成 |

  **确实没有** `SCHEDULE_EXACT_ALARM` / `USE_EXACT_ALARM`（刻意的非精确闹钟）；
  `<service>` **零个**（没有声明空壳前台服务）；两个 FLN receiver 的**四个 action** 齐全；
  `label=夜深`、`icon=@mipmap/ic_launcher`。
- **APK 侧复核**（`aapt2 dump badging`）：`minSdkVersion 24` / `targetSdkVersion 36` /
  `compileSdkVersion 36`、`application-label:'夜深'`，且 **`application-icon-<每个密度>`
  都解析到 `res/mipmap-anydpi-v26/ic_launcher.xml`**——系统在全部密度上取的都是**自适应图标**
  而不是传统位图，这正是想要的。
- **模拟器实跑（Pixel 6 Pro / API 34 / Android 14，`emulator-5554`）**：`adb install` 成功 →
  `am start` 成功（焦点 `com.example.night_sleep/.MainActivity`）→ **首页完整渲染**
  （讲解卡、圆环、最近记录、玻璃胶囊标签条、中文全部正常），**logcat 里该应用无任何
  error / exception / fatal**。证据图：`screenshots/v3.11-android-app.png`（应用内）、
  `v3.11-android-launcher.png`（桌面）、`v3.11-android-icon-zoom.png`（图标放大）、
  `v3.11-android-icons-compare.png`（与同屏其它图标并排）。
- **Android 图标在真实启动器里的目视核对**：Pixel 桌面用**圆形遮罩**，我们的图标被正确套成
  圆形、**月牙与两道声波完整可见、没有被切、构图居中**——这正是「墨迹必须落在中央 72dp 圆内」
  那条断言要保证的效果，现在有了真机（模拟器）层面的证据。同一屏上相册 / YouTube 显示的是
  **旧式处理（缩小放在白色圆盘上）**，只有我们的图标铺满整个遮罩，说明自适应图标这条路真的生效了。
  **一处未解释的观感**：我们的图标在最外圈约 1/4 半径处有一圈**淡淡的浅蓝亮环**，
  而同屏 Chrome 的图标没有。已核实**这不是我们产物的问题**——用两层位图自己做合成 + 圆形遮罩，
  扫描线上没有亮环（`screenshots/v3.11-android-icon-composite.png`）。成因未定，
  怀疑与启动器对**位图背景层**的处理或模拟器 GPU 渲染有关，**留作待查**，
  下一步可试「把背景层换成纯色 `@color` 看亮环是否消失」。

**Android 构建踩到的四个环境坑，都不报错，比报错难查**（判定与解法都记在
「构建 Android 的网络前提」一节）：

| 坑 | 现象 | 判据 |
| --- | --- | --- |
| Gradle 发行包 | `.part` 停在 4 MB 不动 | `$SDK` 下 `gradle-9.3.1-all/*.part` 不再增长 |
| Maven 依赖 | 挂在 `assembleDebug`，daemon 十几条 established 连接收不到数据 | `find ~/.gradle/caches/modules-2/files-2.1 -type f -newermt "-5 minutes" \| wc -l` **持续为 0** |
| NDK / Platform 35、36 | 卡在 `Preparing "Install ..."`；或解压报 `ZipException: Archive is not a ZIP archive`（包被**截断**：`.temp` 下只有 500 KB，完整包 62 MB） | 目标目录下只有一个空 `.installer` |
| **Kotlin 增量编译缓存** | `:flutter_timezone` 与 `:audio_session` 的 `compileDebugKotlin` 报 `Could not close incremental caches … .tab`，连报两次 | 本轮用 `-Pkotlin.incremental=false` **命令行属性**绕过（**没有改仓库里任何文件**；写进 `gradle.properties` 就等于要求所有开发者关掉增量编译）。**疑为杀软实时扫描占住刚写完的 `.tab`**，根治要给项目 `build/` 与 `~/.gradle` 加排除项 |

另外两个只影响诊断、不影响结论的发现：**被停掉的构建留下的 Gradle daemon 仍会攥着工程锁**，
表现为新构建「1 busy Daemon could not be reused」后干等（要单独停那个旧 daemon）；
`Get-Process java | Stop-Process` **不能用来停 Gradle**——本机 `java` 是 Android Studio 自带的
JBR，那样会连 IDE 一起杀掉，必须按 PID 精确停。

**v3.10（2026-10-03：主按钮高光裁进圆角 + 会话页状态栏 + 入睡前页一屏放下 + 清除缓存二次确认）
最近一次复跑：**

- `dart format .` → 无额外改动；`flutter analyze` → **No issues found**。
  （跑的过程中出现过一条 `integration_test/app_screens_test.dart` 的 `main` 未定义，来自
  `lib/main.dart` 被整段注释掉的**本地临时改动**（不是本轮改的），已单独报给使用方，
  当场还原后复跑即无。）
- `flutter test` → **584/584 通过**（v3.9 的 578 之后净增 6 条）：
  - `test/primary_action_test.dart` 的「顶边高光被裁进圆角，不从左右上角溢出」——**含变异验证**
    （摘掉 `clipBehavior` 该条立刻变红）；
  - `test/session_setup_page_test.dart` 新增「底部安全区与一屏放下」组 4 条：三档机型
    （393×852 / 402×874 / 430×932）各自钉「上半区滚动上限 == 0」与「按钮完整落在底部安全区
    之上」，另有一条 SE（375×667）的「确实放不下、但按钮照样不被切」；
  - `test/pages_widget_test.dart` 的「清除缓存：取消（或点蒙层）之后一个文件都不删」。
  「宽屏下两态内容居中限宽 680」与「hero 的高度按可用高度连续取值」两条随实现改写
  （前者不能再拿 `ListView.first` 量——入睡前态已经不是 `ListView` 了）。
- **目视**：
  - 主按钮在黑底 1x / 3x 快照上**逐像素核对**过——修前左右上角**外侧**（y = 顶边 +1）是
    `(48,48,48)` 的白灰条，修后归零，而顶边正中那截 `(58,153,253)` 两版一致。
  - 入睡前那一屏拍了**整页黑底快照**（402×874 / 393×852 / 390×844 / 430×932）：三行卡片与
    按钮都完整，按钮下方还有那行「屏幕将保持暗色…」与 34pt 的 home indicator 区。
  - 两份快照都是**一次性**用例拍完即删，没进版本库。**仍未在模拟器 / 真机上目视过**；
    会话页状态栏只有结构改动、**未截图**。
- **构建**：本轮**没有重跑任何构建**，只跑了 `flutter test` 与 `flutter analyze`。

**上一版（v3.9，2026-10-03：夜间录音接入 / plan B）复跑：**

- `dart format .` → 无额外改动；`flutter analyze` → **No issues found**
- `flutter test` → **578/578 通过**（v3.8 的 469 之后净增 109 条）。本轮新增的测试文件：
  `test/night_recorder_test.dart`（8）、`test/session_recording_test.dart`（13）、
  `test/clip_pruning_test.dart`（5）、`test/clip_segmentation_test.dart`（25）、
  `test/wav_file_test.dart`（22）、`test/sound_card_test.dart`（12）、
  `test/recording_settings_test.dart`（8）；`test/schema_migration_test.dart` 另加 v5 → v6 五条与
  「旧库直升 v6」三条。既有三处页面测试（`pages_widget_test.dart`、`sleep_session_page_test.dart`、
  `session_setup_page_test.dart`）随文案改写同步更新。
  **其中 5 条是审查后补的**：`stop()` 返回时最后一段已送达订阅方、丢弃时收尾那一刻才定案的
  片段文件也要删掉、删掉全部录音时清单指针一并清空、用出厂默认参数也能把换气停顿并起来、
  `PcmRing.slice` 与整段读出的子区间一致。前四条各自做过变异验证（把修复改回去就变红）。
- `flutter build macos --debug` → **通过**（证明 `record` 插件与 macOS 的麦克风 entitlement 接得上）。
- `flutter build ios --simulator --debug` → **通过**。并已核对**打包产物**而不只是源码：
  `Runner.app/Info.plist` 里确有已确认的那句麦克风用途串与 `UIBackgroundModes = ["audio"]`，
  `ios/Runner/GeneratedPluginRegistrant.m` 里确有 `RecordIosPlugin`。
  **构建通过不等于录音可用。**
- **本轮没有跑过什么（不得当成已完成）**：
  - **真机整夜后台录音**：锁屏后 Dart isolate 是否持续收到 PCM、片段是否持续落盘——这是整条路
    的**前提**，而**测试钉不住它**；本轮只跑了单测与构建。必须在真机上插着电源睡一晚，第二天看
    片段的时间分布是否覆盖整夜。
  - **切片阈值调参**：`ClipParams` 那七个默认值（触发 −38 dBFS、结束 −45 dBFS、静音 2s、
    前置 padding 500ms、最短 1s、最长 60s、合并间隔 3s）**全部是拍的**，没有在真机上用真实
    打鼾 / 梦话样本调过。
  - **界面目视核对**：会话页录音指示、设置页新增两行（占用 / 删除全部录音）、声音卡标注三选
    **只有几何与结构断言**，没有截图核对。
  - 顺带：白噪音与录音的切换（倒计时到点后是否真的接上）、来电 / 抢麦中断后的行为、整夜耗电，
    均未在真机验证。
- **重复强调**：切片纯函数、WAV 写入、采集端、会话接线、保留期限这些是**单测**，不是真机验证；
  「跑绿了」只能说明逻辑自洽，说明不了真机上录得到整夜。

**v3.8（2026-10-03：助眠音效换成打包实景录音）最近一次复跑：**

- `dart format .` → 无额外改动；`flutter analyze` → **No issues found**
- `flutter test` → **469/469 通过**（上一版 479；净减 10：删掉合成器的 `noise_synth_test.dart`，
  新增 `noise_asset_test.dart` 5 条，其余为既有用例的 import 与名称跟改）
- **变异验证**：把音效格宽度从「面板宽度 ÷ 条数」换回「屏幕宽度 ÷ 条数」，
  `test/noise_sheet_test.dart` 的「宽屏下面板限宽，五格仍是一行且不溢出」**立刻变红**；
  还原后复绿
- **素材生成管线逐条量过**（ffmpeg 9.0，`ebur128=peak=true`）：

  | 文件 | 时长 | 响度 | 真峰 | 循环点样本阶跃 / 该文件步进 p99 | 字节 |
  | --- | --- | --- | --- | --- | --- |
  | `forest.m4a` | 75.000 s | −22.1 LUFS | −3.0 dBFS | 2470 / 4031 | 745 KB |
  | `fire.m4a` | 71.000 s | −23.0 LUFS | −1.9 dBFS | 1632 / 5828 | 800 KB |
  | `ocean.m4a` | 75.000 s | −22.2 LUFS | −2.8 dBFS | 789 / 4208 | 742 KB |
  | `stream.m4a` | 75.000 s | −22.1 LUFS | −3.0 dBFS | 1532 / 4190 | 761 KB |
  | `wind.m4a` | 44.000 s | −22.3 LUFS | −5.2 dBFS | 122 / 1071 | 435 KB |

  合计 **3.40 MB**；**响度跨度 0.9 LU**（源素材是 14 LU）；真峰全部 ≤ −1.9 dBFS，无削波；
  接缝阶跃全部落在各自步进分布的 p99 以内，即听不出接缝。解码长度精确等于标称时长，
  说明 `m4a` 的 edit list 已裁掉 AAC priming，接缝处不会多出静音。
- **打包资源真能被解码并起播**（macOS，真平台）：
  `flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/noise_playback_test.dart -d macos` → **All tests passed**。
  这条覆盖的是 widget 测试一步都走不到的路径：`setAsset` → 资源包 → 平台解码器 →
  `ProcessingState.ready`（音量 0，不出声）。它同时证明了**素材确实打进了应用包**
  （pubspec 的 `assets/noise/` 写错的话，这里会以加载失败收场）。
- **尚未做**：**听感未核对**（五条的主观可用性、切换时 0.9 LU 的响度差、循环接缝是否可闻）；
  **素材授权未落实**（见「未实现」表）；5 格新布局**无截图核对**（只有几何断言）。

**v3.7（2026-10-03：DeepSeek 余额查询 / 连通性测试 / 详情页重新生成）最近一次复跑：**

- `dart format .` → 无额外改动；`flutter analyze` → **No issues found**
- `flutter test` → **479/479 通过**（上一版 424；本轮净增 55 条：`insight_service_test.dart`
  18 条、`insight_prompt_test.dart` 7 条、`sleep_insight_test.dart` 9 条、
  `insight_credentials_test.dart` 6 条、`app_cache_test.dart` 7 条，
  `pages_widget_test.dart` 补 5 条交互用例，`model_catalog_test.dart` 补 2 条能力表用例，
  另把配置页那条「标注未接入项」改写为「给出实测支持的动作」）
- **清除缓存在真实目录上验证过**（macOS，临时 `integration_test` 脚本，跑完已删）：
  `size()` 读出 8 个白噪音 WAV 共 **6.7 MB**（`du` 报 6.8 MB 磁盘占用，差值来自块对齐），
  > 2026-10-03 注：白噪音改成打包资源后不再进临时目录，这份读数的**内容**不再可复现
  > （`size()` / `clear()` 的语义本身没变）。留下的只有导出副本，未导出时读数为 0 B。
  `clear()` 之后目录里 **0 个文件**、再读为 `0 B`。同一次还顺手确认了 `getTemporaryDirectory()`
  在 macOS 上就是 `~/Library/Caches/<bundle id>`（与 `noise_player.dart` 的注释一致）。
- **钥匙串在真实平台上验证过**（macOS，临时 `integration_test` 脚本，跑完已删）：
  写 → 读 → 覆盖写 → 删全部通过；并且**换一个进程仍读得到**（先跑 `PHASE=write` 的进程写入，
  再用 `security find-generic-password -s flutter_secure_storage_service -a insight_api_key`
  确认条目真的进了系统钥匙串，最后跑 `PHASE=read` 的**另一个进程**读回同一串值）。
  「重启后仍在」这句话就是靠这一步成立的，不是靠推断。**未在 iOS / Android 实测**。
  macOS 走的是旧版钥匙串、**没有加** `keychain-access-groups`（见规格偏差 #8 里的取舍）。
- **开发期会遇到一次钥匙串授权框**，原因已查清并实测过：`flutter build macos --debug`
  产出的是临时签名（`codesign -dv` 报 `Signature=adhoc`、`TeamIdentifier=not set`），
  designated requirement 就是 **cdhash**，每重新编译一次就变一次，旧钥匙串条目的 ACL
  随之对不上。表现是「写入钥匙串之后又重编过」时，下次读会弹一次
  「想要使用您存储在钥匙串的…中的机密信息」，点**始终允许**即可（把新哈希加进 ACL）。
  用写入时的同一个二进制启动**不会弹**（已实测）。正常使用不会遇到这件事，
  只有开发期反复重建会遇到。
- **用户实机复测后补修两条**（第二次是靠读用户机器上的真实库定的性：`app_settings` 存着
  `deepseek / deepseek-v4-pro`、`insights.provider` 全部是 `demo` —— 设置一直是对的，
  缺的是**会话内存里的密钥**，而调试期间应用重启了几次）：
  1. 设置根页那一行改走 `resolveInsightSelection()` 并**说出密钥在不在**（「未填 API Key
     （重启后需重填）」），不再读裸列显示与事实不符的「未配置」；
  2. 详情页「重新生成」**按钮常驻**，跑不了时变灰 + 一句指名道姓的说明，点它不发请求。
- 回归用例：`sleep_insight_test.dart` 的「全新安装也照样给按钮」「没填 API Key 时按钮仍在
  但变灰」，`pages_widget_test.dart` 的两条根页副标题用例。
- **活体冒烟（用真实 key 打真接口，一次性脚本，跑完已删；脚本与仓库都不含该 key）**：
  余额读取成功、连通性通过、生成返回 `score=82` 与一段中文总结。这一条是本轮唯一能证明
  「地址、请求体、响应解析在真实服务商上确实成立」的证据——其余测试全部用 `MockClient`。
- **已变异验证**：`SleepEntry.scoreSource` 退回只看 `isUsable` → 「模型没给分时回退到
  本地估算」变红；连通性判定改成要求 `content` 非空 → 「推理模型正文为空也算连通」变红。
- **未实测**：OpenAI 的对话路径（与 DeepSeek 同一份代码，但没有 OpenAI 的 key）；
  Claude 的对话与余额（**刻意未实现**，见规格偏差 #46）。
- **未目视核对**：详情页常显的洞察区块、配置页三个动作按钮的浅色/深色观感与排版，
  以及 `¥` 读数在窄屏下的换行，**只有几何/结构断言**（同 v3.5 / v3.6 的待办）。

**上一版（v3.6，2026-10-03：确认弹窗改用 iOS 系统组件）复跑：**

- `dart format .` → 无额外改动；`flutter analyze` → **No issues found**
- `flutter test` → **424/424 通过**。本轮只重写 `test/confirm_dialog_test.dart`（仍是 7 条，
  断言对象从「自绘特征」换成「系统组件特征」：`CupertinoAlertDialog` 在位、取消/蒙层返回
  `false`、确认返回 `true`、取消在左确认在右、破坏性取 `danger` 非破坏性取 `accent`、
  深色下亮度跟随应用而非系统）。三处调用方一字未改，`pages_widget_test.dart` 与
  `record_edit_delete_test.dart` 里依赖文案/可见性的确认用例**直接复用、无需改动**。
  **已变异验证**：把实现退回 HEAD 的自绘版本，「系统组件」「破坏性取 danger」「深色亮度」
  3 条立刻变红，而 4 条返回语义/按钮次序的用例与实现无关、保持绿。
- **构建**：本轮**没有重跑任何构建**，只跑了 `flutter test` 与 `flutter analyze`。
- **未目视核对**：新弹窗底色是半透明材质叠在模糊背景上，浅色/深色下的实际观感与它同全仓
  其余玻璃材质的协调度**只有几何/结构断言**，需人工核对（同 v3.5 设置页的待办）。

**上一版（v3.5，2026-10-03：设置页信息架构重排 + 两个新二级页 + 开屏页）复跑：**

- `dart format .` → 无额外改动；`flutter analyze` → **No issues found**
- `flutter test` → **424/424 通过**（本轮净增 9 条：新增开屏 5 条；设置页那两组重写后
  净增 3 条——删掉 3 条随版式作废的旧用例，补上 6 条新的二级页用例；又补 1 条
  「下拉箭头贴右」的几何回归）
- 三条新断言做了**变异验证**，逐条确认能变红：
  - 把滑块 `_snap` 退回直接 `clamp`（去掉 0.5 小时吸附）→「按 0.5 小时吸附，两端不越界」
    报「滑块在 0.13 处落库 342 分钟，没有吸附到 0.5 小时」
  - 开屏收起条件去掉 `settingsAsync.isLoading` →「设置还没读到第一帧时，开屏不会先收起」
    报找不到 `SplashScreen`
  - 把声音检测的副标题换成原型那句「检测打鼾、梦话并生成洞察」→ 红线用例报找不到
    「尚未接入录音」
- **提醒相关的 9 条既有用例全部通过在**（挂载点从设置根页改到 `/settings/sleep`），
  行为一字未改：权限被拒回弹、开启时连同默认时刻落库、全量重排、`denied` 时的「去系统设置」、
  「删除全部本地数据」的会话收尾。
- **巡检脚本已按新文案更新**（`integration_test/app_screens_test.dart` 新增「外观」「睡眠设置」
  两步，导入/洞察两步改用新行名），`flutter analyze` 覆盖了它的编译；**未实跑**
  （要 `flutter drive` + 设备）。
- **目视核对（macOS，`flutter run -d macos`）**：**开屏页通过了**。深蓝渐变、两圈轨道环、
  星点、圆角图标（moon + 两道声波弧的描线都在）、`夜深`（宽字距）与`听见夜晚，看见睡眠`、
  底部进度条，逐项在位，与原型一致。证据图：`screenshots/v3.5-splash.png`（文案与进度条都在
  的那一帧）、`v3.5-splash-early.png`（只到轨道环与星点的早期帧，可见入场是从无到有）。
- **设置根页与「外观」「睡眠设置」两个新二级页仍未目视核对**：macOS 巡检跑到一半弹出了系统
  的「`night_sleep` 想访问『文稿』文件夹」授权框，它盖住了应用窗口，而本机没给 osascript
  辅助访问权限、点不掉系统对话框，抓到的帧全是那个弹框。这一条同时解释了由来已久的
  「巡检在 macOS 上跑不完」——**那多半不是脚本的问题**（见「界面截图巡检」新增的注意点）。
  行内下拉在 390px 与 iPad 横屏下的换行、自绘滑块的拖拽手感，因此**仍然只有几何与结构断言**。
- **已知项**：开屏挂在 `AppScaffold` 的 `Stack` 里，冷启动若有深链直达子页会被盖住
  （当前没有深链）。

**v3.4（2026-10-03：iPad 横屏下的两处弹层缺陷）最近一次复跑：**

- `dart format .` → 格式化改动文件；`flutter analyze` → **No issues found**
- `flutter test` → **415/415 通过**（v3.3 那次的 413 之后净增 2 条回归用例）
- 两条新回归都做了**变异验证**：把音效格宽度换回「屏幕宽度」→
  「宽屏下面板限宽，八格仍是四列两行且不溢出」报 1 行 8 格；把弹层浮起 24px 加回去 →
  「宽屏下面板限宽 560，但下沿仍贴屏幕底」报 `810 ≠ 834`
- **目视核对（使用方自验，iPad 横屏）**：音效格那一处已确认修好；弹层贴底那一处是同一轮
  提出后新改的，**本机只做了 1194×834 的 golden 渲染**（面板贴底、四列两行、音量条与定时
  chips 都在位），**未在真机重新核对**。**仍未覆盖**：真实 iPad 上的安全区取值、深浅两套
  主题、以及 iPhone 横屏。

**同日补丁（2026-10-03 晚：白噪音在 macOS 上放不出声——两处缺陷）最近一次复跑：**

- `dart format` / `flutter analyze` → **No issues found**
- `flutter test` → **413/413 通过**（未增删用例：两处修复都在平台侧，widget 测试用的是假
  播放器，本来也盖不到——这正是它们能漏出去的原因）
- `flutter drive --target=integration_test/noise_playback_test.dart -d macos` → **All tests
  passed**（真合成 → 真落盘 → 真起播，音量 0 不出声；**2026-10-03 当日的记录**，素材换成打包
  录音后这条链路已消失）。**并做了正反对照**：先清掉缓存目录
  （实测 `getTemporaryDirectory()` 返回时 `exists=false`，就是报错里那个路径），去掉
  `directory.create(recursive: true)` 那一行再跑，同一条用例报的正是截图里那句
  `无法生成音频：PathNotFoundException … errno = 2`；恢复后冷跑通过，缓存目录里落下
  `noise-fan.wav` 882,044 字节（20 秒 × 22050Hz × 16 位 + 44 字节头）。
- **巡检（`integration_test/app_screens_test.dart`，macOS）本轮跑了两次，都没跑完**：
  - 第一次**暴露了新加那一步自己的错**：`find.text('风扇')` 同时命中弹窗宫格与**底下那一屏**
    的常用白噪音四格（弹窗是叠上去的，下面那棵树还在），`ensureVisible` 抛
    `Bad state: Too many elements`，还把后面三步一起带塌
    （`TOUR skipped session-*`）。已改成用 `GridView` 限定范围——整个 `lib/` 里只有这个弹窗
    用 `GridView`。
  - 第二次跑到 00:5x 时**机器自动锁屏**：锁屏后不再产帧，每一步都在推帧的巡检随即停摆，
    日志停在 `request_data message is taking a long time to complete`。这条已记进
    「界面截图巡检」的注意点（**先 `caffeinate -d`**）。
  - 所以**巡检全趟通过这一条仍然没有被验证**——与 v3.0 / v3.2 / v3.3 那几条同类，
    继续挂在下面的「未验证」里。两次都没写库（`active_sessions` 为空、DB 文件时间戳未变）。

**v3.3（2026-10-03：会话页补「入睡前」态，记录起点挪进页内）最近一次复跑：**

- `dart format .` → `Formatted 122 files (6 changed)`（本轮改动的文件）
- `flutter analyze` → **No issues found**
- `flutter test` → **413/413 通过**（v3.2 那次的 400 之后，净增 13 条：新增 20 条、删掉 7 条
  被新语义取代的旧用例）。本轮新增/补测（新断言逐条做了变异验证）：
  - **入睡前态 10 条**（`test/session_setup_page_test.dart`）：hero 三段文案与「开始睡眠」按钮
    在位、旧的「没有正在进行的睡眠」空状态**不再存在**；**进页面不写库**；**点「开始睡眠」才
    写会话行**且 `startAtUtc` 就是按下的那一刻；草稿（场景 / 白噪音 / 音量）随行一次写进去；
    收起不写库、停掉试听、回上一页；草稿不跨页存活；闹钟权限被拒与通过两条；
    宽屏 1200 下两态都居中限宽 680
  - **数据 3 条**（`test/session_repository_test.dart`）：`start()` 一次写全草稿；
    不传时默认值不被新参数带偏；**首次并发读设置不炸**——最后这条是**既有缺陷**的回归
    （`getSettings()` 的「先读后插」在并发首读时撞 `UNIQUE constraint failed:
    app_settings.id`，正是入睡前态一帧两个读者稳定触发的）
  - **夜景组件 4 条**（`test/session_night_widgets_test.dart`）：入睡前变体多一行
    「夜景氛围 / 左右滑动切换」而进行中变体没有；选中卡是**绕中心** `scale(.98)`
    （订正照抄错层，见会话规格 §17.6）；另两条白噪音生命周期用例从会话页搬过来（那边
    的点按入口已被收紧掉）
  - **媒体查询 3 条**（`test/session_setup_page_test.dart`）：窄屏（375）常用白噪音四格**竖排**
    （标签在图标下方）、宽屏（430）并排；高屏（≥860）hero 撑到 285、矮屏更矮——这条挡的是
    「把 285 写死、不再看屏高」
  - **首页入口 1 条**（`test/pages_widget_test.dart`）：点「开始入睡」**只推入页面、不写会话行**，
    收起后库里仍为空（走真实路由，顺带覆盖 `app.dart` 注册的 `path: 'sleep/session'`）
- **本轮没有重跑任何构建**（`flutter build macos` / `flutter build ios`），也**没有重跑
  `flutter drive` 巡检**：巡检脚本已按新流程改写（入睡前那一屏 → 「完整设置」弹窗 →
  「开始睡眠」→ 长按/评星），但**一次都没执行过**，见「未验证」。
- 逐句核对了原型 `index.css` 的**最终生效层**（第 1730–1960 行那段
  `/* ── Immersive sleep controls ── */` 覆盖了前面第 1557 行起的同名规则），并借此订正了两处
  照抄错层：场景卡选中态（`scale(.98)` 而非 `translateY(-2px)`）与内容限宽（两态都是 680）。

**上一版（v3.2，2026-10-02：会话页照原型「睡眠进行中」态重建）复跑：**

- `dart format .` → 只有 `test/pages_widget_test.dart` 有**既存**的格式漂移（不属于本轮改动，
  已 `git checkout` 还原、未提交）；本轮改动的文件本身无需格式化
- `flutter analyze` → **No issues found**
- `flutter test` → **400/400 通过**（v3.0 那次的 337 之后，v3.1 与 v3.2 累计新增 63 条）。本轮
  新增/补测：夜景几何 19（`test/night_backdrop_test.dart` 16 + `test/night_scene_test.dart` 3，
  含「流星只在 `meteor` / `moon` / `galaxy` 三场景可见」这条**订正**）、月亮标记 6
  （`test/sleep_moon_mark_test.dart`，含「丢弃 `<filter>` 后不打印 unhandled element」）、
  会话页夜景 widget 7（`test/session_night_widgets_test.dart`：8 种场景、`disableAnimations`
  停表、弹窗九宫格与四档时长、**浅色应用主题下弹窗内仍是深色令牌**）、长按按钮 7
  （`test/hold_to_finish_button_test.dart`，含
  「**开启「减弱动态效果」时 1.5 秒守卫仍按真实时长计时**」这条**行为修复**的回归、
  「**按满触发后指针被取消，再短按仍给提示**」这条 `onPointerCancel` 复位的回归）、
  v4→v5 迁移 4（`test/schema_migration_test.dart` 的 `v4 → v5` 组）、场景持久化
  （`test/session_repository_test.dart`）与 `SleepSession.elapsedClockAt`
  （`test/sleep_session_test.dart`）；会话页自身补到 33 条
  （`test/sleep_session_page_test.dart`，含「浅色主题下会话页仍然是深色」这条**真的跑浅色主题**
  的回归）。新断言逐条做了变异验证。
- **构建**：本轮**没有重跑任何构建**（`flutter build macos` / `flutter build ios`），只跑了
  `flutter test` 与 `flutter analyze`。

**上一版（v3.0，2026-10-02：会话 + 回顾 + 起床闹钟 + 显示名）终审修复后复跑：**

- `dart format --set-exit-if-changed .` → 无改动
- `flutter analyze` → **No issues found**
- `flutter test` → **337/337 通过**。本轮新增/补测（未逐条列举，完整场景见规格第 9 章）：
  v3→v4 迁移 6（`test/schema_migration_test.dart`，含「重建后 `quality` 可空」
  「既有记录/阶段/片段/洞察/设置一行不动」「子表外键仍级联」「再次打开不重跑」）、
  会话领域 13（`test/sleep_session_test.dart`）、会话仓库 16
  （`test/session_repository_test.dart`，含 `finish` 不写阶段、时长守门、冷启动恢复）、
  会话页 widget 28（`test/sleep_session_page_test.dart`，含诚实文案在位、闹钟被拒回弹、
  白噪音收起/离开页面仍继续、闹钟胶囊已过起床时间不再说「还有 0h 0m」）、
  回顾页 10（`test/review_page_test.dart`）、会话闹钟（`test/reminder_scheduler_test.dart`
  的起床闹钟组、`test/reminder_sync_test.dart` 的会话闹钟组 7，含「调度器没就绪时不排
  9003」）、显示名 5（`test/app_display_name_test.dart`）；首页与手动补录页的改动落在
  `test/pages_widget_test.dart`。终审修复波另补「删除全部本地数据」的收尾断言
  （`test/reminder_settings_test.dart`：残留会话被清、9002/9003 重新推导、白噪音停掉）。
  **新断言逐条做了变异验证**（拆掉实现会真的变红）。
- 上一版（v2.9，2026-09-29）复跑记录：**238/238 通过**（当时从 176 起，逐步增至 216，终审修复波再补 1 至 217：
  schema v3 迁移 6（含 `record_id` 为空的洞察存活分支）、
  演示数据重装与幂等 2、冷启动播种兜底 4、图标取色 4、顶部渐变与安全区/错误分支留白 3、
  关于卡片居中与版本号 2、自绘确认弹窗 7（另有演示数据页的确认 1，落在 `pages_widget_test`）、
  删除图标 2、`PrimaryAction` 禁用态 10；
  v2.7 再补 4：标签条浮起量与页面底部留白同源、胶囊实测高度 65px（`test/tab_bar_inset_test.dart`）；
  v2.8 再补 12：底部模糊带的遮罩层级（套在 `BackdropFilter` 外面）与遮罩方向、模糊半径 14、
  填充 0→78% 且单调递增、高度 = 底部预留 + 20（含无安全区的 113）、宽屏不渲染、整条带不拦手势
  （`test/bottom_fade_test.dart`）；
  v2.9 再补 5：应用图标几何分平台断言（实体四角透明、中心不透明、实体包围盒 824×824 且四边留白 100、
  iOS 仍满幅、无 alpha 通道（色型 2）；另有一条覆盖七个尺寸——文件名与真实像素尺寸绑定、实体宽随尺寸
  等比、实体下方投影存在、圆角半径带宽。`test/app_icons_asset_test.dart`）；
  各测试文件覆盖的场景见
  [规格第 9 章](superpowers/specs/2026-09-28-night-sleep-design.md)）。
  本轮多处断言做了**变异验证**（拆掉实现会真的变红），不是「不可能失败的断言」

- **构建**：v2.5 那次 `flutter build macos --debug` / `flutter build ios --simulator --no-codesign`
  成功产物的记录仍适用；**本轮（v2.6）没有重跑任何构建**。因此本轮新增的
  `package_info_plus` 依赖虽然连 `macos/Flutter/GeneratedPluginRegistrant.swift` 一并提交了，
  但它在新构建里的原生注册、以及设置页版本号的实际取值**都没有在构建/运行中验证过**
  （测试里用的是包自带的 `setMockInitialValues`）
- **应用图标构建（v2.9）**：`flutter build macos --debug` 于 **2026-09-29** 成功，
  `build/macos/Build/Products/Debug/night_sleep.app/Contents/Resources/AppIcon.icns` 的时间戳为
  **2026-09-29 18:56:15**（源 PNG 为 18:12:25，确认本次重建吃到了新产物）。用 `iconutil` 把该
  `.icns` 抠出来量了 256px 那一档：色型 6、实体 206×206、四边留白各 25、**画布角与实体角 alpha 均为 0**、
  中心 255——即**构建产物里确实带着烘焙好的圆角**，不是只有源文件对。
  **但 Dock 里实际画出来的样子仍未经人眼确认**（本任务不做目视，见下「未验证」）——断言与量产物
  只能保证文件几何正确，保证不了 Dock 的绘制；清缓存步骤见 CHANGELOG 2.9
- **界面巡检**：
  - v2.5 那轮完整巡检（iOS 模拟器截图，浅色/深色各一遍，逐屏看过首页/记录/统计/设置/
    二级页/睡眠详情/助眠音效面板）的记录仍适用。
  - 本轮**只有任务 5（顶部渐变）真的跑了模拟器**：用临时巡览脚本（已删）依次切到四个一级页
    各下拉 300px，宿主机 `xcrun simctl io screenshot` 循环采样，iPhone 16 Pro、浅色与深色
    各看一遍，确认顶部硬分界消失、未滚动时标题不被状态栏压住。
  - **本轮其余新增/改动的界面没有做目视确认**：自绘确认弹窗（含浅色下卡片描边是否可见）、
    垃圾桶图标、禁用按钮的页内提示、关于卡片的居中与版本号行——这些只有几何/结构断言，
    没有截图核对。这是有意的取舍：有一位实现者曾在跑模拟器截图时卡死 600 秒，
    此后本轮禁止后续任务碰模拟器，目视集中留待下一轮。
  - v2.7（标签条浮起量 34pt → 20pt）**同样只有几何断言**：只截了一张模拟器截图用于确认
    改动前的现状，改完后没有再看一眼，实际观感需人工确认。
  - v2.8（底部模糊带）**已在 2026-09-29 下午补做目视核对**（iPhone 16 Pro 模拟器，手段沿用上节
    「界面截图巡检」：宿主机 `xcrun simctl io booted screenshot` 循环采样 +
    `flutter drive --target=integration_test/app_screens_test.dart`）。要看的三件事都通过：
    (1) **带子顶边（离屏幕底 121pt）没有硬边**——离带顶约 20pt 处的「最近记录」标题（离底约 91.7pt）
    在两套主题下都清晰，该处的有效 wash 只有约 9%（遮罩与填充在带顶附近都接近 0），越往屏幕底越重，
    是连续过渡；(2) **方向对**（越靠近屏幕底越实）——浅色统计页上胶囊下方那段的「平均时长」只剩
    很淡的残影，深色首页上胶囊下方的内容被洗到接近 `bgBase`（黑），而带子上方的内容
    （「推荐 7–9h」「雨声·海浪·篝火」）保持清晰；(3) **胶囊下半部没有发闷、没丢玻璃透感**——
    浅色下胶囊仍通透，深色下胶囊仍读作正常的玻璃条（`bgNavbar` 76% 填充主导）。
    **覆盖面（不是逐页逐屏核对）**：浅色看过首页（滚动后）、统计页、睡眠详情/助眠音效弹层
    （弹层盖在带子之上、**不被**底部带模糊，属预期行为）；**深色只看过首页静置态**。
    两条如实记下的偏差：**深色那一遍不是巡游览到的**——把模拟器切 dark 对 app 无效，因为 app 里存的
    外观偏好是「浅色」（`app_settings.theme_mode = 'light'`，这是正确行为、不是缺陷）；深色帧是把该
    偏好**临时**改成 dark、用 `flutter run` 起应用截的，截完已还原为 light（演示数据 5 条未受影响）；
    巡检中途在助眠音效面板**卡住不动**（95 秒内每帧完全相同），已终止——上节本来就记过
    `flutter drive` 这条通道在本机不可靠。
    证据图（`screenshots/`，**该目录在 `.gitignore` 里、未入库**，这三张只存在于本机工作树；
    均为 1206×460 的底部裁剪，来自同一次采样的原始帧，未重新生成或美化）：
    `screenshots/v2.8-light-home-scrolled.png`（浅色首页滚动后，「最近记录」清晰、其下化开）、
    `screenshots/v2.8-light-stats.png`（浅色统计页，最底部「平均时长」只剩残影）、
    `screenshots/v2.8-dark-home.png`（深色首页，胶囊下方洗到接近黑）。
  - v3.1（会话页重排）**已目视核对**（2026-10-02，iPhone 16 Pro 模拟器 iOS 18.3、深色、
    宿主机 `simctl` 每 1.3 秒采样）。看过的：**收合态整页**（圆环 → 圆形「结束」按钮 + 外圈
    进度环 → 「按住不放」→ 今晚的设定两个开关，鼾声那行注明「尚未接入录音，开关只保存偏好」
    → `白噪音 · 音量 50% 更多 ⌄`）；**按住中的进度环**（红色弧从 12 点顺时针扫到约 40%，
    松手退回）；**展开的白噪音区**（八宫格 + 音量 + 定时 + 说明**整块都在屏幕内**）；
    **按住到底后的评星弹层**（且跑完后「回顾」页确实多出一条 `来自：睡眠会话` 的记录）。
    **展开区落在屏幕外**这个问题正是这次目视发现的：点了「更多」只看到箭头翻面，内容全在
    折叠线以下（60m 那颗 chip 落在 1112.5，屏幕高 932），已按此加了自动滚动（见规格 §四）。
    一条如实记下的：第一遍用 `Future.delayed` 模拟按住时，环停在 40% 走不完——集成测试的
    live binding 里动画只在推帧时前进（见上节），改用推帧循环后才拍到了评星那一帧。
    会话页已补进常驻巡检脚本，**末尾一轮跑通**（`flutter drive`，02:34，`All tests passed`；
    只跳过 `settings-demo` 与 `detail-sheet` 两步，原因与本次改动无关）。
- **未验证（不得视为已完成）**：
  - **v3.0 新增的未验证项**（逐条不得当成已完成）：
    - **起床闹钟是否真的到点投递**：Dart 侧的调度契约（`scheduleOnce` 不重复、9003 不被
      `sync` 抹掉、`_resume` 映射）由测试钉住，但**「到点真的响了」需真机确认**——与下一条
      通知投递是同一类问题
    - **`timeSensitive` 当前并不会穿透专注模式**：iOS / macOS **请求**了
      `interruptionLevel: timeSensitive`，但工程里没有配套的 Time Sensitive
      Notifications entitlement（`ios/` 下没有任何 `.entitlements`，
      `macos/Runner/*.entitlements` 也没有
      `com.apple.developer.usernotifications.time-sensitive`），按 Apple 的规则该级别会被
      系统降级。**解锁需要**：加 entitlement、在 App ID 上开启该能力，并真机开专注模式实测
    - **宽屏（macOS 侧边栏）下的会话页与回顾页**：会话页是推入式全屏页，**没有在宽屏下逐屏
      核对版式**（不能默认窄屏版式拉伸后可用）
    - **Dock / 桌面 / 菜单栏显示名的实际观感**：`CFBundleDisplayName` 改成了「夜深」，
      但 plist 改了不等于系统重读了缓存；**没有人看过 Dock / 桌面实际画出来的名字**。
      另外 **macOS 菜单栏读的是 `CFBundleName`（工程里仍是 `night_sleep`），可能仍显示英文名**，
      需人工核对（`PRODUCT_NAME` 与构建路径不受影响）
    - **`integration_test/` 的「记录 → 回顾」改动没有跑过 `flutter drive`**：该目录不参与
      `flutter test`，本轮的「记录 Tab → 回顾」改名与相关巡检脚本改动**只做了静态检查**，
      需要人工跑一次 `flutter drive`（见「界面截图巡检」）确认巡检仍能走通
  - **v3.2 新增的未验证项**（逐条不得当成已完成）：
    - **夜景动画的观感、真机帧率与耗电未实测**：八套场景动画只用单测钉了「几何算式」与
      「减弱动态效果时停表」，**测试盖不住观感**，需在真机/模拟器上目视核对动画节律、是否
      掉帧、整夜挂着的耗电
    - **`flutter_svg` 丢弃 `<filter>` 导致的近似未目视核对**：月亮原本的外发光靠 SVG 的
      `<filter>`，`flutter_svg` 2.3 会**静默丢弃**它（已实测），改用轨道径向光晕近似——
      近似效果与原型的差距没有人看过
    - **`integration_test/` 不参与 `flutter test`**：本轮对巡检脚本的改动（走到会话页之后改用
      显式推帧、打开并收掉白噪音弹窗）**跑不到**，需人工 `flutter drive` 手动验——与上面
      v3.0 那条「记录 → 回顾」未跑 `flutter drive` 是同一类
    - **事件卡不叠 `backdrop-filter`（偏差 #34）的观感**：这是为整夜挂着省算力的取舍，实际
      读起来是否仍与原型接近，未目视核对
    - **`_RejectedSheet`（时长越界说明层）与评星弹窗在浅色应用主题下仍是浅色面板**（已知不一致）：
      这两块走 `AppSheet`、取**应用主题**，而会话页其余部分是页面自套的 `Theme(AppTheme.dark())`，
      所以浅色主题下会看到一次深浅跳变。本轮**刻意不动**：`AppSheet` 的外观是共享组件的职责，
      改它等于给全站换肤（与偏差 #32 同一理由）。见会话规格 §十三。
      （**白噪音弹窗不在此列**：它走 `showGeneralDialog` + `NightStyle`，并在 `pageBuilder` 里
      显式又包了一层 `Theme(AppTheme.dark())`，浅色主题下也是深色面板。）
  - **v3.3 新增的未验证项**（逐条不得当成已完成）：
    - **入睡前那一屏：已在 macOS 上看过一次，iOS 真机/模拟器仍未看。**
      2026-10-03 用 `flutter run -d macos`（真实 Impeller/Metal 引擎）起应用，在一个约 412pt 宽、
      约 890pt 高的窗口里把这一屏看全了：收起胶囊 / 「睡眠模式」/ 月亮轨道 / 晚安 /
      「准备好休息了吗？」 / 「放下今天，让夜晚慢下来。」/ deck 的夜景氛围选择器（流星夜选中态、
      横向滚动）/ 常用白噪音四格 / 白噪音（未开启）/ 起床闹钟（关，无时刻胶囊）/ 鼾声检测
      （带「尚未接入录音」那句）/ 渐变「开始睡眠」按钮 / 底部提示，**一屏内全部装得下，没有滚动**，
      `flutter run` 日志里**没有异常、没有 RenderFlex overflow**——deck 那层
      `backdrop-filter: blur(24) saturate(130%)`（`ImageFilter.compose` + 色彩矩阵）在真实引擎上
      没有报错。**仍未验证**：小屏（iPhone 那类 ~758pt 可用高度）下按钮与提示是否要滚动才够得着；
      深色观感之外的动效节律与整夜耗电。
    - **`integration_test/` 的巡检脚本改动未执行**：脚本已按新流程改写（入睡前 → 完整设置弹窗 →
      「开始睡眠」→ 长按 → 评星），但**没跑过 `flutter drive`**；与 v3.0 / v3.2 那两条同类
    - **「开始睡眠」按钮在真机首屏是否无需滚动就能点到**：入睡前那一屏比原先长（hero + 设定卡 +
      按钮 + 提示），测试用的是一块超高视口（2000pt），真机（852pt 上下）里按钮是否落在首屏内
      没人看过。若被折到屏幕外，用户要滚一下才能开始——这是本轮引入的真实风险
  - **通知投递**：没有真机 / 模拟器人工确认过「到点了真的会响」。Dart 侧的调度契约
    被测试钉住，但通知是否真的投递、前台是否展示、时区是否选对，都仍需人工确认
  - **系统分享面板**：导出经 `share_plus` 交付，面板的实际弹出与去向选择**没有实测过**；
    导出内容的字节（BOM、CRLF、RFC 4180 转义、不含本地路径与 `AppSettings`）由单元测试覆盖
  - **macOS 未签名调试构建的通知授权行为**：本机钥匙串里没有签名证书，权限可能拿不到或不持久。
    实现按 `permission()` 的真实返回降级（界面照实显示），但这一项只能人工验证
  - **`package_info_plus` 的实际返回值**：只验证过它的 API 形状与「取不到时不显示版本号」的
    降级分支；`version` / `buildNumber` 在**真机 macOS / iOS 上映射到 `CFBundleShortVersionString`
    / `CFBundleVersion` 的对应关系没有实测**（测试用 mock 注入）
  - **本轮 UI 的目视观感**：见上「界面巡检」——确认弹窗、垃圾桶、禁用按钮提示、关于卡片、
    标签条浮起量（v2.7）仍未经眼。底部模糊带（v2.8）已在 2026-09-29 看过一遍（浅色：首页滚动后 /
    统计页 / 详情与助眠音效弹层；深色：首页静置态），但**深色只有首页这一屏、没有逐页核对**，
    浅色下详情/音效弹层以外的二级页（设置、数据导入、洞察服务、演示数据）也未见，故仍有未覆盖面
  - **macOS Dock 图标的目视确认（v2.9）**：产物已重建、其几何也经像素核对（见上「应用图标构建」），
    但**没有人看过 Dock 里实际画出来的样子**——Dock 图标缓存、macOS 版本差异都可能在文件正确的前提下
    画出别的东西。**需人工确认后**才能把 v2.9 这条划掉
  - 真机交互、窄屏宽屏溢出检查：**尚未执行**
    （宽屏侧边栏布局只在 macOS 桌面构建里跑过，未逐屏核对）
  - **Android 构建：v3.11 已跑通**（2026-10-12，`assembleDebug`），平台目录已生成；
    但**装到设备上会怎样一律未验证**——见下方 v3.11 一节。
    **Web 构建：尚未执行**。
  - 外部服务、小米数据：未接入，不能视为已完成。**夜间录音已接入（v3.9）**，但真机整夜后台
    存活、切片阈值调参与界面目视**均未验证**（见 v3.9 那一节），不能当成已完成。
    助眠音效已实现（**2026-10-03 起是打包的实景录音**，此前为设备内合成）。
    **起播这条链路**已在 macOS 上由 `integration_test/noise_playback_test.dart` 跑通
    （旧版钉「合成 → 落盘 → 起播」，新版钉「打包资源 → 解码 → 起播」）；
    但**实际发声效果仍没有听过**——那条用例是音量 0，需要人工试听才知道像不像、
    五条之间的响度差与循环接缝听不听得出来
- **AI 模型列表**：DeepSeek 与 Anthropic 的模型 ID 已对照官方文档核实（2026-09-27），
  OpenAI 文档无法访问故未内置任何模型名，需用「获取可用模型」实时拉取
