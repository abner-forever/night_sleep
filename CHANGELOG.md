# 变更记录

本文件记录「夜深」项目规格的版本变更。规格正文见
[docs/superpowers/specs/2026-09-28-night-sleep-design.md](docs/superpowers/specs/2026-09-28-night-sleep-design.md)。

## 3.25（2026-10-14）

**会话页的呈现方式从「推入式全屏页」改成「从底部升起的整屏面板」**——从底部升起，点「收起」或把顶部
标题行往下拉，面板滑走消失。

使用方原话是「点击开始入睡打开的这个睡眠页面，改成底部弹出展示，点击收起回到底部消失可以吗」。
四个决定当场拍板：**整屏升起、顶部不留缝**（视觉零改动）；**两态都走这个呈现**；关闭方式只有
「收起」与下拉（**不**点蒙层）；**下拉区是标题行整行**，且往下拉时后面露出的是首页。

### 改了什么

| 文件 | 改什么 |
| --- | --- |
| `lib/app/app.dart` | `/sleep/session` 由 `builder:` 换成 `pageBuilder:` + `CustomTransitionPage(opaque: false)`，竖向 `SlideTransition`（`AppDurations.standard` / `AppMotion.standardCurve`） |
| `lib/features/session/presentation/widgets/session_header.dart` | **新文件**：两态的标题行合并成一个「壳 + 中段」组件，下拉手势挂在**整行**上 |
| `lib/features/session/presentation/sleep_session_page.dart` | 跟手位移（`Transform.translate` + `AnimationController.unbounded`）、松手判定、`_collapseCurrentState` 按态分派、下拉时露出的模糊压暗层；删掉 `_StatusHeader` / `_PulseDot`（搬进新文件） |
| `lib/features/session/presentation/widgets/session_setup.dart` | `_header()` 换成 `SessionHeader.setup(...)`；**排版算式一个字没动** |
| `lib/core/widgets/app_sheet.dart` | 阈值提成公开常量 `kPanelDismissVelocity` / `kPanelDismissFraction`，与底部弹层共用一份 |
| `test/session_sheet_test.dart` | **新文件**，9 条 |

规格侧：总规格偏差表**新增 #56**，并原地更新 #24 / #28 / §2.4 页面表 / §9 测试矩阵；
会话规格 §四那一句「推入式全屏页」一并改写。

### 三个刻意的取舍

**① 保住 go_router 路由，没有换成 `showAppSheet`。** 这一页里有 `context.go('/')`（结束与丢弃
两条路径）和 `context.push('/log/new')`，而 **`go` 不会 pop 一个 dialog 路由**——结束会话会变成
「在一个仍然可见的弹层底下」导航到首页。保住路由还让两个测试夹具一个字都不用改（它们是按初始路由
挂载的）。

**② 标题行留在滚动视图里，没有提出来钉在顶部。** 提出来会让 `spaceBetween` 的间隙从 2 个变成 1 个、
hero 整体上移半个余量，`test/session_setup_page_test.dart` 那条「430×800 时 hero ≥ 210」当场红。
手势挂在那一行上就够——手势竞技场是**先 accept 的赢**，而标题行的竖直识别器比 `Scrollable` 的更深、
先入队。

**③ 补了一层模糊压暗的遮罩。** 方案里原本只写了跟手位移。没有它，往下拉时露出的首页是原样亮的，
而使用方选中的正是「模糊压暗」那一支。遮罩不随面板位移（跟着滑会像被拖进来），顺带让系统栏在
拖动全程保持深色。

### 验证

`dart format .` 无改动 / `flutter analyze` 无问题 / `flutter test` **637/637 通过**（新增 9 条）。
新用例做过**先红验证**：把 `pageBuilder` 换回 `builder:`，九条全红。

### 一个当天就被推翻的预判

方案把「漏写 `key: state.pageKey`」列为最高危，说漏了会「草稿被清、计时器重起」。**变异验证没有
复现**：去掉 `key` 之后 46 条会话用例一条没红——`Page.canUpdate` 比的是 `other.key == key`，
`null == null` 为真，在没有第二个无 key 页面竞争时路由照样复用。`key` 仍然加上（将来真出现无 key
的兄弟页时会配对错乱），但**这一条没有测试钉住**，已如实记入验证记录的未验证项。

## 3.24（2026-10-14）

**修掉 Android 构建里每次 `flutter run` 都必然复现的那个失败：Kotlin 增量编译缓存跨盘。**

失败长这样——`FAILURE: Build completed with 6 failures.`，每个 Kotlin 插件各一条：

```
Could not close incremental caches in …/build/<plugin>/kotlin/compileDebugKotlin/cacheable/caches-jvm/jvm/kotlin: …tab
```

本机 pub 缓存在 `C:`、工程在 `D:`，而增量编译缓存存的是源码根的**绝对路径**，两个盘建不出公共根。
**报错栈里真正说明问题的那行被截断在下面几层**——`Suppressed: … this and base files have different
roots: C:\…\Pub\Cache\… and D:\…\night_sleep\android`——所以旧版 README 把它猜成了「杀软占句柄」，
且据此推出一条错误结论（「`flutter build apk` 传不了 `-P`」）。两条这次一并订正。

### 改了什么

| 文件 | 改什么 |
| --- | --- |
| `android/gradle.properties` | 新增 `kotlin.incremental=false` 与 `kotlin.compiler.execution.strategy=in-process`，各带成因与「什么情况下可整体删掉」的注释 |
| `README.md` | 「构建 Android 的网络前提」订正两处错说法：成因是跨盘不是杀软；3.47.5 的 `flutter build` / `flutter run` **能**传 `-P, --android-project-arg` |

### 一个刻意的取舍

**这两行进了仓库**，与该节「解法都写在文档里、一行都没有进仓库」的既有政策相悖，是有意开的口子：
那批 `dl.google.com` 下载只是一次性前置，而这一个**每次 `flutter run` 都必然复现**。代价是单盘机器
和 CI 上白白关掉 Kotlin 增量编译，所以注释里写明了那一段可以整体删掉。

### 验证

`flutter clean` 之后**完全不带参数**重建（必须 clean——前一次构建用的就是这两个值，不 clean 的话
Gradle 会判成 UP-TO-DATE，等于什么都没验证）：`flutter build apk --debug` → **57.1s 成功**（此前
6 failures）；再 `flutter run -d e0e60672` → 32s 内出现 `Syncing files to device MI 9` 与
`A Dart VM Service on MI 9 is available at: …`，真机（MI 9 / Android 11 / MIUI 12.5.6）装上并渲染
正常、logcat 无 FATAL。本次改动**不含任何 Dart 代码**，故 `dart format` / `flutter analyze` /
`flutter test` 与它无关、未跑。

**没验证的**：`kotlin.incremental=false` 单独一条够不够（实测的是两条的组合）；单盘机器与 CI 上的
表现（按推断是可删的，但没有机器可试）。未验证项见 [`docs/verification-log.md`](docs/verification-log.md)。

## 3.23（2026-10-14）

**滚轮照着 iOS 闹钟重做交互：时刻列首尾相接、行距收紧到 36px、选中行压一条底色。**

使用方提了三件事（原话）：**「小时分钟可以循环展示吗，现在到底了就无法滚动了，体验不好」**、
**「1-2-3 之间的间距可以小一点，这样好滚一点」**、**「当前时间的高亮可以加一个背景色，整体参考
iOS 闹钟时间选择器的交互」**。

三件都落在 `WheelColumn` / `_WheelShell` 上，三个调用点（回顾页补录、睡眠设置页、会话页起床
闹钟）与两个选择器（时间 / 日期）一起受益。

### 改了什么

| 文件 | 改什么 |
| --- | --- |
| `lib/core/widgets/wheel_picker.dart` | `WheelColumn` 新增 `looping`；`itemExtent` 44 → **36**；循环列的下标不再夹在 `[0, n)` 内（`_wrap` 取值、`_nearest` 归位）；`onChanged` 对外仍只报一圈之内的下标。`_WheelShell` 里加选中底色（`Stack` 的底层，宽度贴合数字） |
| `lib/core/theme/app_tokens.dart` | 新增 `AppRadii.wheelHighlight = 12`（非原型，给底色横条用） |
| `AppTimePicker` / `AppDatePicker` | 时刻两列 `looping: true`；日期三列不循环 |
| `test/wheel_picker_test.dart` | 4 条 → 8 条（两条绕回、一条底色、一条「日期不循环」） |
| 规格 / README | §2 基准表那行改写、§8 加偏差 **#53 / #54 / #55**、§9 矩阵扩写；README「设计系统与外观」补一条滚轮交互；`CLAUDE.md` 偏差条数 53 → 56 |

### 四个刻意的取舍

1. **无限滚动落在 `childCount: null` 上，不是自己拼三段列表。** 视口据此把上下都当成无边界
   （`_minEstimatedScrollExtent` 是 `-∞`），两头都能滚；自己复制几份再悄悄归位也能做，但那要
   在滚动通知里做一次看不见的跳转，正好会踩上一条「build 期间 setState」。
2. **循环列的对外下标不越界。** 内部的 `_active` 会一直增长/变负（列首尾相接之后本来就「没有
   头尾」，硬夹回一圈反而要多做一次归位跳转），但 `onChanged` 报出去的永远是 `0..23` / `0..59`，
   `AppTimePicker` 那一层不必知道循环这回事。父层换值归位时取**最近的同值格子**：否则从 23 到
   0 值一样，用户看到的却是整圈飞转。
3. **日期不循环。** 「2024 年再往前」没有意义；而且只有循环列才画得出 13 月、2 月 31 日这类格子
   ——那是 #4 一族（没有的东西不许编）的红线。iOS 自己的日期轮盘也不循环。
4. **行距比 iOS 还紧。** iOS 系统闹钟自己的行距约 43pt，36 是使用方在这一版上明确要的密度，
   不是「照 iOS 抄」。底色同理：用令牌里的 `accentSoft`（标签条选中态同一支），不写死色值。

### 验证

`dart format`、`flutter analyze`（1 条**既有**问题：未跟踪的模板桩 `test/widget_test.dart`）、
`flutter test` **628 通过 / 1 失败**（失败的就是那个模板桩）。新增 4 条并做了两次变异验证：
把循环列的 `childCount` 报成有限 → 两条绕回用例变红（症状正是「滚到底就停住」）；换回 HEAD 的
原实现 → 三条多列一致性用例变红。

**离屏渲染目视过一遍**（临时 golden 测试 `--update-goldens` 落 PNG，看完即删）：浅色时间选择器
与深色日期选择器各一张，确认底色压在正中间那一行、宽度贴合数字而没有横贯弹层、三列对齐。
另外实测了循环列的甩动行程：400px 的一划在 600 / 1000 / 2500 / 6000 px·s⁻¹ 下分别是
13 / 17 / 38 / 60 格（含拖动本身的 11 格）——**与有界时是同一套 physics，一行没改**，区别只是
末端不再截断。未验证项见 [`docs/verification-log.md`](docs/verification-log.md)。

## 3.22（2026-10-14）

**时间选择器不再「选完分钟把小时弹回去」——滚轮各列的当前值改由 picker 自己持有。**

使用方报的症状很具体：**先滚小时、再滚分钟，点「完成」，小时回到原来的值；只滚小时反倒是对的**。

根因不在滚动，在父子之间那条**单行道**。`showAppSheet` 的 `pageBuilder` 拿到的是调用点构造好的
那一个 `child` 实例，弹层一打开，父层再 `setState` 也送不进来；而 `AppTimePicker` 是
`StatelessWidget`，两列 `onChanged` 闭包里的 `hour` / `minute` 是**上一次 build 解析出的常量**。
滚小时那次把草稿改对了（`08:00`），但 widget 不重建，接着滚分钟仍用旧的小时拼值（`23:30`）——
点「完成」提交的就是 `23:30`。只滚小时看不出问题，因为那一格没有被第二列覆盖。
三个调用点（回顾页补录、睡眠设置页、会话页起床闹钟）都是这个形状。

同一个缺陷在 `AppDatePicker` 上也在（先滚年再滚月，年被冲掉），一并修掉。

### 改了什么

| 文件 | 改什么 |
| --- | --- |
| `lib/core/widgets/wheel_picker.dart` | `AppTimePicker` / `AppDatePicker` 从 `StatelessWidget` 改为 `StatefulWidget`：`value` 降级为**初始值**，时分 / 年月日由 state 持有，各列的 `onChanged` 一律在**调用时**从 state 读另一列，`_select` 里值没变就直接返回 |
| `test/wheel_picker_test.dart` | 新增 4 条回归用例（见下） |
| 规格 §9 | 加一行测试矩阵（滚轮的多列一致性） |

### 三个刻意的取舍

1. **修在组件里，不修在调用点。** 调用点想推新值也推不进来——弹层捕获 `child` 是
   `showAppSheet` 的既定行为，要它们各自套一层 `StatefulBuilder` 等于三个地方各修一次，
   下一个调用者还会重新踩。「多列必须一致」这条不变量本来就属于 picker 自己。
2. **值没变就不出声。** `WheelColumn.didUpdateWidget` 里的 `jumpToItem`（列的行数变了、
   或父层换了值时会走到）会让 `ListWheelScrollView` **同步**回调 `onSelectedItemChanged`——
   等于在 build 期间又喊一次 `onChanged`，照单全收就是 `setState() called during build`。
   日列随月份收窄（31 行 → 28 行）时这条路径必然命中，是修日期选择器时才浮出来的。
3. **日列跟着年月重新生成。** 选完 1 月 31 日再滚到 2 月：草稿早就被截成 28 日了，轮子上
   却还列着 31 天。同一个根因（值不重建），顺手一起正过来。

### 验证

`dart format`（2 个文件，1 个改动）、`flutter analyze`（1 条**既有**问题：未跟踪的模板桩
`test/widget_test.dart` 引用不存在的 `MyApp`，与本次改动无关）、`flutter test` **624 通过 /
1 失败**（失败的就是那个模板桩）。新增 4 条：先滚小时再滚分钟、先滚分钟再滚小时、只滚小时、
先滚年再滚月（含日列行数）。**变异验证**：把 HEAD 的原实现换回来跑，三条核心用例全红且症状
逐字复现（`23:03` / `21:00` / `2026-02-28`），「只滚小时」那条仍然绿——与使用方描述完全一致。
细节与**未验证项**见 [`docs/verification-log.md`](docs/verification-log.md)。

## 3.21（2026-10-14）

**「删除记录」真的删掉录音了——此前它只删数据库里的行，音频留在盘上。**

3.19 那一轮在真机上把这个洞走了一遍：结束会话 → 详情页「删除记录」→ 确认框上写着
「声音事件都会被永久删除，此操作无法撤销」→ 点确认之后 **9 条 `sound_clips` 行全没了、
9 个 WAV 一个不少地留在盘上**。文件要等到**下一次冷启动**的孤儿清理才被扫掉，中间既不属于
任何记录、也没人删得掉它。

### 改了什么

| 文件 | 改什么 |
| --- | --- |
| `lib/features/sleep/data/clip_pruning.dart` | 新增 `deleteRecordWithRecordings()` 与 `deleteAllUserDataWithRecordings()`——同时握着库与文件仓库的入口 |
| `lib/core/database/app_database.dart` | 新增 `clipsFor(recordId)`：文件路径必须在删行**之前**读，`record_id` 一带 cascade 就再也问不出 `localUri` |
| `lib/features/sleep/data/sleep_repository.dart` | **删掉 `delete(id)` 与 `deleteAllUserData()`**，原位留注释说明为什么这里不能有 |
| `detail_sheet.dart`、`settings_page.dart` | 两个调用点改走新入口 |
| 规格 / README | 夜间录音规格 §十、主规格 M3 第 5 条与 §9 测试矩阵、README「回顾、补录、编辑与删除」与「现在能做什么」那两条 |

### 四个刻意的取舍

1. **不留「只删行」的入口。** `SleepRepository` 只持有 `AppDatabase`，它天然删不了文件——
   所以那两个方法不是改名，是**删掉**。留着就等于给同一个洞留下一次机会。
2. **顺序不能反**：先读文件路径 → 再删行 → 最后删文件。
3. **删全部数据要多收一类东西**：当前会话清单里那些**已经落盘、还没入库**的片段。会话行一删
   清单就跟着消失，它们会正好落进「谁也不认识」的缝里。
4. **先删库再删文件**：文件删失败会被 `deleteClip` 吞掉，留下一个孤儿（下次冷启动清掉）；
   反过来先删文件、中途失败，就留下一行指着不存在文件的记录——那是详情页当场会露馅的那种。

### 验证

`dart format .`、`flutter analyze`（No issues）、`flutter test` **620/620**（基线 616，新增 4 条：
`clip_pruning_test.dart` 三条——删一条带走自己的 / 不碰别人的 / 删全部时含会话清单里还没入库
的那一段；`record_edit_delete_test.dart` 一条，钉住**详情页那个入口真的走到了删文件**）。

**这一版踩到一个坑，记进 `flutter-pitfalls` skill 了**：`testWidgets` 的测试体跑在 FakeAsync
里，**真实文件 I/O 的 Future 永远不会完成**——那条 UI 用例第一版在测试体里直接
`Directory.createTemp` + `File.writeAsBytes`，一路挂到 10 分钟超时（不是失败，是挂住，日志只有
一行 `TimeoutException`）。skill 里此前只记了「平台通道的 Future 永不完成」，现在把
`dart:io` 这一类一起补上了。**改法**：UI 层用假仓库只记「谁被删了」（
`recording_settings_test.dart` 的既有手法），真删文件那一半留给普通 `test()`——那里没有假时钟。

## 3.20（2026-10-14）

**把「录不到」如实说出来：平台静音麦克风时，会话页不再写着「录音中」。**

承接 3.19 那条实测——Android 上一离开前台就静音录音端口、并持续交付零样本，而 `record`
插件一个中断都不报，所以应用手里的状态**确实是**「正在录」，界面照着它写了整夜。这一版
给采集端加了一条它能自己看见的判据，把假话改成真话。

### 改了什么

| 文件 | 改什么 |
| --- | --- |
| `lib/features/sleep/data/night_recorder.dart` | 新增 `NightRecordingState.silenced` 与两个常量（`kSilentMicRun` = 60 s、`kSilencedMicReason`）；`_rmsDbfs` 改成 `_analyseWindow`，**一次求和同时给出 dBFS 与「这一格是不是逐样本全零」**；新增 `_trackSilence()` 记账连续全零，攒够就翻状态、真声音一回来就翻回去；`stop()` 顺手把 `silenced` 也落回 `idle` |
| `lib/features/session/presentation/widgets/session_events_card.dart` | 那一行副标题多一个分支。灯不用改——它只认 `recording`，静音态自动不亮 |
| 规格 | 主规格 §8 加偏差 **#52**、§9 加两行测试矩阵；夜间录音规格 §十二第 1 条改写（存活成立、但录到的是静音）、§十三加 #52、新增 **§十四**（判据、裁定、以及「这条**不**解决什么」） |
| `README.md` | 「现在能做什么」会话页那节、以及「未实现」表里夜间录音行与 Android 缺口①按实测改写 |
| `CLAUDE.md` | 偏差条数 52 → 53 |

### 三个刻意的取舍

1. **判据是「逐样本全零」，不是「很安静」。** 真实麦克风永远有本底噪声（这台机器上这间房
   实测约 −55 dBFS）。1 LSB 的底噪**不算**，测试里专门有一条盯着它——把「安静」误判成
   「没在收音」，是在冤枉一个好好的麦克风。
2. **新开一态，不复用 `stopped`。** 流还活着、采样还在来、声音随时可能回来（实测回到前台
   就自动恢复）。这时候说「已停止」是假的，说「录音中」也是假的。也**不在这条路上停录**。
3. **不改那颗灯。** 它只认 `recording`，所以静音态自动不亮——偏差 #31 当初挡的就是
   「一盏写着正在聆听却没在听的灯」。

### 这条**不**解决什么

- **不让整夜录音变成能录。** 那要前台服务（`FOREGROUND_SERVICE_MICROPHONE`），清单里至今
  只有声明、`dumpsys activity services` 是空的。本轮一个字没动。
- **也没把「这一夜麦克风是死的」写进记录。** 第二天打开那条记录看到的仍然是「0 条声音
  事件」，与「一夜真的没出声」长得一样。要分开得给 `sleep_records` 加一列，是 schema v7 的事。

### 验证

`dart format .`、`flutter analyze`（No issues）、`flutter test` **616/616**（基线 609，
新增 7 条：`night_recorder_test.dart` 的「平台静音」组 5 条、`sleep_session_page_test.dart`
的状态灯 2 条——后者按 `NightStyle.liveDot` 的颜色找那颗灯，**改颜色就变红**）。
**都是在 Windows 上跑的，没有上真机**：这一版改的是「拿到零样本之后怎么办」，而真机上
那条链路 3.19 已经实测过。

## 3.19（2026-10-13）

**真机跑了一整晚的夜间录音：录音链路本身完好，但那 7 小时录到的是数字静音。
纯验收——Dart 与测试代码一行未动。**

使用方自己开着会话睡了一晚（2026-10-13 01:22:49 → 08:30:21，7h07m），落在 MI 9 上。这一轮把
库和音频拉下来离线复算，**链路自洽的部分全部对上了**：4 条 WAV 都是标准 44 字节头、
PCM/单声道/16 kHz/16 bit，`data` 长度与库里的 `duration_ms` 逐条相等；用源码里同一个
`_rmsDbfs` 与 `envelopeFor` 从音频反算，库里的 `waveform_envelope` 是它的**严格仿射像**
（落在文件内的 36–38 格逐格误差 ≤ 5.5e-16）——**没有编出来的柱子**。四条片段 id 的微秒尾数
全是 `00532`，说明 `_reset()` 只跑过一次，**麦克风从 01:22 到 08:30 一次起、中途没重启**。

但整夜只录到 4 段，真实音频只出现在前 ~30 秒——**08:30 那条片段的前 3 格（300 ms）是逐样本
全零，1600 个样本无一非零**，第 4 格起才是有本底噪声的真实音频。真实麦克风不会给出整格全零，
所以那是**平台交上来的静音**，不是一间安静的房间。

**机制用对照实验定案了**（真机上另起一个会话，读 `dumpsys media.audio_flinger`）：
那条轨道的 `Client = 22550` 就是本应用的 pid、`Port Id = 135`，所以日志里
`setRecordSilenced(general), portId:135, … silenced 1` **静音的正是我们的端口**。三次读数——
前台 `Sil = n`；灭屏 100 s 后 **`Sil = s`**，同时打出 `setRecordSilenced… silenced 1`；
唤醒 8 s 后回到 `n`。**而 `cmd appops get … RECORD_AUDIO` 全程是 `allow … (running)`**：
平台按下了静音键，却没告诉应用，`record` 插件也收不到任何中断。同一会话里，前台那 2.5 分钟
录到 7 段**全部是真实音频**（全零格 0 个），静音窗口里**一个新增文件都没有**。
原因清楚了，但「加前台服务能挡住它」**仍是推断**——`dumpsys activity services` 至今是空的。

**这条最要紧**：`record` 插件全程没报中断（流一直在吐零），所以 `NightRecordingController`
拿到的状态就是"正在录"，**界面说「录音中」是照着它手里的事实说的**——偏差 #7 挡的是
「控件声称一个它不具备的状态」，而这一次骗过应用的是平台。要不要在采集端加一条
「持续数字静音」的判定，留待定案。

顺带查明一件事、验证一条从未跑过的路，**都只记录、不改代码**：

- **「删除记录」只删行，不删音频——已端到端复现。** 先看到 3 个来历不明的孤儿文件
  （共 1.5 MB，库里没有对应行）。随后在对照实验里走了一遍完整路径：结束会话 → 详情页
  「删除记录」→ 确认框写着**「声音事件都会被永久删除，此操作无法撤销」** → 确认。
  **9 条 `sound_clips` 行全没了，9 个 WAV 一个不少地留在盘上**——那句承诺只做到一半。
- **孤儿清理（`deleteOrphanRecordings`）第一次被验证，而且是通过的。** 盘上堆到 16 个文件时
  冷启动一次：**16 → 4，被扫掉的正好是 12 个孤儿，留下的正好是库里有行的那 4 个**，
  多一个没留、少一个没删，日志里没有 `清理录音失败`。问题只是它**只在冷启动跑**。

完整判据、另外两条小问题（短片段包络尾格取自片段之外那一格、一条孤儿 WAV 的长度不是
100 ms 的整数倍）与**全部未验证项**（回放只验到走带起来、没验扬声器出声；前台服务方案没做；
iOS/macOS 一个字不适用）见 [`docs/verification-log.md`](docs/verification-log.md) 的 v3.19 条目。

**真机上做过的收尾**（使用方选「全清」后才做）：实验会话及其 12 个孤儿文件已删除，
昨晚那 4 段与那条 7h07m 的记录原样保留。

## 3.18（2026-10-13）

**README 按读者旅程重排——从「变更史合订本」回到「给人看的说明书」。纯文档改动，
Dart 与测试代码一行未动（只改了两处注释里的指针）。**

### 为什么改

使用方反馈 README「不像给人看的，看不懂密密麻麻的」。确诊四类问题：① 一份文档干三份活
（怎么跑 / 能干什么 / 疑难档案）；② 「当前实现范围」是 190 行的无结构 bullet 流，其中
「睡眠会话」单条就 30 行；③ 混入变更史与验收记录（25 行带版本标注、18 行带日期，节末还留着
两句验收数字）；④ 重复（助眠音效两条说同一件事、图标三处重叠）。

### 改了哪些地方

| 文件 | 改什么 |
| --- | --- |
| `README.md` | 章节按读者旅程重排，新增「本文导航」；「当前实现范围」改名**「现在能做什么」**并拆成 14 个小节；「罗盘」降为该节下的一个小节；两个构建节合并为**「构建网络前提」**下的两小节（**节名原样保留**）；「未实现」表由两列扩成「能力 / 已做到哪 / 还差什么」三列并瘦身；清掉全部版本标注与日期标注；引言扩写。**事实一条未丢** |
| `docs/verification-log.md` | 顶部新增**补录**一条：README「罗盘」节末尾那两句历史验收记录（`43 项` / `347/347`）**整条搬入、原文照录**——它们在全仓库仅此一份 |
| `CLAUDE.md` | 「构建网络前提」的节名指针随之更新 |
| `docs/superpowers/specs/2026-09-28-docs-reorganization-design.md` | 职责表 README 行按新章节名重写；补记 v3.18 重排；「非目标」里「不调整章节顺序」一句标注不再适用 |
| 另外三份规格 | 「当前实现范围」的行内指针补注新名 |
| `docs/superpowers/specs/2026-09-28-night-sleep-design.md` | §9 那句「在 README 记录…未验证能力」改指 `verification-log.md`（与 v3.17 对齐）；一处失效的「README 验证记录」指针改指该文档 |
| `lib/features/settings/data/model_catalog.dart`、`android/app/src/main/kotlin/.../CompassStreamHandler.kt` | 注释里两处失效的「见 README 验证记录」改指 `docs/verification-log.md` |

### 刻意不改的

- **两个构建小节的节名**——「构建 iOS / macOS 的网络前提」「构建 Android 的网络前提」还被
  `verification-log.md` 按名引用，换个说法就会打断那些指针。
- **「未实现」仍是表格**——19 处引用写的是「README『未实现』表」，改成小节会让指针字面失真。
- **`README.md` 里 8 组「全仓仅此一份」的事实**——罗盘的 iOS 行为与边界（读数含义、不算磁偏角、
  不申请定位权限、不生成假方向）、Xcode **16.2**（iOS 18.2 SDK）vs 真机 iOS **27.0**、
  `No valid code signing certificates were found`、SPM 构建日志串、NDK `28.2.13676358`、
  Gradle wrapper 哈希目录名、`264 KB/s` / `748 MB` / `android.jar 27 MB` 等实测数字——**逐字保留**。
- **`CHANGELOG.md` 旧条目与 `docs/superpowers/plans/*`**——同 v3.17：它们是当时的过程记录，
  里面的旧指针断不断无所谓。

### 「未验证」照旧不省

重排只动位置与措辞：**「未实现」表里每一条未验证项都还在**；两条搬进验证记录的罗盘数字带着
「移入的只是记录，别当成当前状态」的说明。

## 3.17（2026-10-13）

**验收记录从 `README.md` 里彻底搬走——README 不再保留任何一版，逐版记录的唯一位置是
[`docs/verification-log.md`](docs/verification-log.md)。纯文档改动，Dart 与测试代码一行未动。**

### 为什么改

v3.14 把「验证记录」从 README 拆出去时留了一条尾巴：**README 仍留最近一版**，理由是
「单看 README 也知道当前验到了哪一步」。使用方随后明确要求**全部搬走**——README 是
「怎么跑、能干什么」，连一版流水账都不该留。

所以本次把 README 里那一节**整节删除**（连同「本节只留最近一版」那段引言），
v3.16 的内容按倒序插进 `docs/verification-log.md` 的最上面。

### 改了哪些地方

| 文件 | 改什么 |
| --- | --- |
| `README.md` | **删掉整个「验证记录」节**；「项目结构」块补上 `docs/` 三个条目（其中点名 `verification-log.md`）；三处没带链接的「见「验证记录」vX」改成指向本文档的链接；「未实现」表的小米手环一行更新到 v3.16（Gadgetbridge 已配对成功） |
| `CLAUDE.md` | 「验收记录分两处」改为**「只有一处」**，并写明 README 里不再保留任何一版 |
| `docs/verification-log.md` | 开头那段「最近一版仍留在 README」改成 v3.17 的新说明 |
| 总规格与 `2026-09-30-sleep-session-design.md` | 7 + 1 处 `README「验证记录」` 的行内指针改为指向 `../../verification-log.md` |
| `2026-09-28-docs-reorganization-design.md` | 「文档职责」表里 `README.md` 与 `verification-log.md` 两行按 v3.17 改写 |

### 刻意不改的

- **`CHANGELOG.md` 自己的历史条目**——它们写的是当时那句「记在 README『验证记录』」，
  是记录，改了就是篡改。指针断不断无所谓，它们不是给读者导航用的。
- **`docs/superpowers/plans/*`**——同理，计划是当时的过程记录。
- 总规格里 `2026-09-28-export-and-reminders-design.md` 等把「往 README 验证记录里补」
  当成**待办描述**的句子，也属于历史语境，不动。

### 「未验证」照旧不省

这次搬的是**位置**，内容一份没删。最要紧的未验证项仍立在
[`docs/verification-log.md`](docs/verification-log.md) v3.16 顶部：
**Gadgetbridge 解不解得出睡眠阶段**。

## 3.16（2026-10-13）

**小米手环 9 接上 Gadgetbridge——配对、RFCOMM 连接、认证全部成功；睡眠阶段仍未验证。
纯文档改动，Dart 与测试代码一行未动，导入按钮仍然禁用。**

同日 3.15 之后继续做的一轮，把规格 §八 的下一步真跑了一遍。产物是
[可行性设计](docs/superpowers/specs/2026-10-13-xiaomi-band-sleep-integration-design.md)
原地新增 §3.3 与 §6.1，以及 README「验证记录」换成 v3.16（v3.15 挪进 `docs/verification-log.md`）。

### 打通的（三条判据，全来自 logcat）

```
Bond state changed  08:16:D5:73:9E:EF   BOND_BONDING → BOND_BONDED
BtBRQueue(0): Connected to RFCOMM socket for Xiaomi Smart Band 9 9EEF
XiaomiAuthService: Authenticated, further communications are encrypted
```

- **密钥是对的**——3.15 里从 `XiaomiFit.main.log` 取的那把 `encryptKey` 通过了认证
  （日志里有两个候选值，取最后出现的那个是对的）。
- **「手环 9 走经典蓝牙」现在有三条独立证据**：SDP 记录、官方 App 只发 `CLASSICAL-CONNECTED`、
  以及 Gadgetbridge 自己的 `BtBRQueue`。
- Gadgetbridge 用的是 `XiaomiSupport` + `MiBand9Coordinator`，**不是老款 Mi Band 那套**。

安装方式记一笔：从 Codeberg 官方 release 直链下载 0.95.1（中途断过一次，断点续传补齐），
验签（`CN=APKSignKey, OU=Gadgetbridge`，SHA-256 `01cce931…`）后 adb 安装。

### 四个坑（都写进规格 §3.3）

1. **MIUI 的 `force-stop` 压不住小米运动健康**——它有个 `com.mi.health:device` 子进程会被反复拉起，
   一直抢手环。最终 `pm disable-user` 停用。**这是「不能共存」的机制层解释。**
2. **手环不与手机配对时不广播**——从系统蓝牙删掉它之后就连 Gadgetbridge 也扫不到，
   **必须在手环上主动进「连接新手机」模式**才会重新广播。
3. **扫描列表里混着家电**——`midea`（美的，厂商 ID `1704`）被长按后 Gadgetbridge 拿老款
   `MiBandSupport` 去连、崩溃断开。**是选错设备，不是缺陷。**
4. 密钥用 `adb shell input text` 从文件直输，不手抄。

### 顺带推翻/确立的两件事

- **Health Connect 对本机是死的**：GMS / Play 商店 / GSF **全部被禁用**（`enabled=2`，GMS 零进程），
  而 Android 11 的 HC 依赖 Google Play 服务。但**代码级证据说小米会写阶段**——dex 里有
  `HealthConnectApi` / `HealthConnectSyncDao` / `PLATFORM_TO_SDK_SLEEP_STAGE_TYPE` / `STAGE_TYPE_AWAKE`，
  **有阶段映射表就说明在处理阶段**（代码证据，非实测）。
- **规格新增 §6.1：「自己用」与「给别人用」是两个卡点完全不同的问题。**
  ② 只可能是自己用的方案；要能分发只剩 ③（合规风险）或 ⑤（覆盖不了国行用户），**没有第三条**。
  好消息是两条路在应用里长得一样，**领域侧共用，先做自己用不白做**。

### 「未验证」照旧不省

**最要紧的一条仍然空着：Gadgetbridge 解不解得出睡眠阶段。** 数据库在 `/data/data/…`
（无 root 读不了），要等它导出到外部目录；手环里此刻有没有睡眠数据也不确定。
**这一条直接决定这条路走不走得下去**，也决定实现计划写不写得出来。
其余未验证项（云 API、官方平台申请、打开 GMS 再试 HC、时钟对齐）见规格 §九。

## 3.15（2026-10-13）

**新开[小米手环睡眠数据接入可行性设计](docs/superpowers/specs/2026-10-13-xiaomi-band-sleep-integration-design.md)，
把真机实测写进 README「验证记录」。纯文档改动，Dart 与测试代码一行未动，导入按钮仍然禁用。**

### 为什么要做这一轮

总规格 §10 第 2 条从立项起就写着「小米睡眠数据的真实导出文件样本或官方授权接口文档」，
`sleep_import_page.dart` 因此一直禁用、README「未实现」表里那一行一直是「未接入」。
这一轮把「那个真值从哪条管道进来」查清了：四条候选路径各自能拿到什么、代价是什么、哪条判死。

### 结论

- **自写 Dart 协议栈直连：判死。** 真机实测确认小米手环 9 走**经典蓝牙 SPP（RFCOMM）**——
  SDP 里有 `00001101`，Connection Events 只有一条 `CLASSICAL-CONNECTED`、**没有任何
  `LE-CONNECTED`**，`GATT Client Map` 的 `Entries for mApps: 0`。Flutter 的 BLE 插件
  （`flutter_blue_plus` / `flutter_reactive_ble` / `universal_ble`）全是 BLE-only；
  iOS 侧第三方 App 根本没有 RFCOMM。
- **推荐 Gadgetbridge 转发**（它已做好经典蓝牙 + miwear 协议栈 + 睡眠解码，且不碰小米账号），
  其次**申请官方开放平台**（`com.xiaomi.sleep.health` 有正式字段文档，但客户端 SDK 要
  HyperOS 4.0+，本机 MIUI 12.5.6 跑不了）。私有云 API **仅个人自用、不得随应用分发**。
- **两处对公开资料的订正**：国行版小米运动健康包名是 **`com.mi.health`** 而非
  `com.xiaomi.wearable`（Gadgetbridge 官方文档与中文社区教程一律写错，照抄必失败）；
  **NFC 版设备名不带 "NFC"**（广播名 `Xiaomi Smart Band 9 9EEF`），Gadgetbridge 的设备
  正则能匹配——这一条**推翻了本轮调研阶段自己的推测**。

### 红线状态

**§10 第 2 条不关闭**——样本与官方文档仍未拿到，只按第 3 条的写法记一笔「部分进展」。
**§8 偏差 #4「不猜小米导入字段」一字未改**，导入按钮仍然禁用。本轮反而给这条红线加了新依据：
公开实现里**多个流行项目的阶段映射是错的**（`mi_fitness_cn` 深浅睡写反、
`mi-fitness-mcp-cn` REM 与清醒写反），证明「有字段可读」和「字段含义可信」是两件事。

### BLE 侧探测：跑了三轮，没做成，但失败原因本身是结论

另写了一个一次性探针 APK（手搓 `aapt2`+`javac`+`d8`+`apksigner`，不走 gradle、不进仓库）
去问「手环 BLE 侧到底开不开 GATT」。三轮全败，原因两条，**都是本机环境事实而非代码问题**：

- **手环与手机保持经典连接时，BLE 侧不广播**——同一抓取窗口里协议栈收到 3 台其他 BLE 设备的
  广播，手环地址出现 **0 次**；按 MAC 直连也 20 秒超时。
- **MIUI 会把 BLE 扫描结果对第三方 App 屏蔽**（协议栈统计 `0 results`，
  `install -g` / `pm grant` / `cmd appops set --uid` 都解不开）。**这条对将来任何蓝牙相关
  工作都成立**，已写进规格 §3.2 的环境事实。

因此 **GATT 那条悬案仍未结**，只是现在知道它被什么挡着；继续追要先解绑手环**并且**绕过 MIUI
的扫描屏蔽，而「解绑后手环是否就会在 BLE 侧广播」本身也没验证过——
代价超过问题本身的价值，**建议搁置**。

### 一处订正：解绑手环**不是**不可逆

初稿把「解绑」写成「不可逆」，**这是错的**（使用方追问后查证订正）。准确情况：
解绑只会让**当前那把密钥作废**、需重新配对拿新的，恢复出厂还会换掉蓝牙 MAC——
**手环本身不会锁死，随时能绑回小米运动健康**。Gadgetbridge 官方流程的关键恰恰是
「配对取到密钥后**不要解绑**，直接卸载/停用官方 App」。

真正的代价是另两层：**① Gadgetbridge 与小米运动健康不能在同一台手机上共存**（抢连接）；
② 解绑或恢复出厂后 Mi Fitness 有时**不把新密钥写进日志**（社区报告的 App 缺陷），
要删日志或重装 App 才能重新取到。规格 §3.2 与 §七已就地订正。

### 「未验证」照旧不省

GATT 枚举（三轮未成）、配对密钥提取（本轮使用方裁定暂不提取）、Gadgetbridge 试连、
云 API 实测、官方平台申请——全部留在规格 §九与 README「验证记录」v3.15 的未验证清单里。

## 3.14（2026-10-13）

**把 `README.md` 的「验证记录」拆成 [`docs/verification-log.md`](docs/verification-log.md)，
README 只留最近一版 + 指向它的指针。** 纯文档改动，Dart 与测试代码一行未动。

### 为什么要拆

那一节到拆之前是 **584 行，占 1140 行 README 的 51%**，8 个版本条目、平均 73 行一版，
而且**只增不减**。README 的职责是「怎么跑、现在能干什么」，不该兼做逐版流水账；
两者的读者与更新频率本来就不一样。

**三处分工没有变**（v2.4 文档重组时定的，见
[文档重组设计](docs/superpowers/specs/2026-09-28-docs-reorganization-design.md)）：
README 记「怎么跑」、总规格 §9 记「哪些场景被覆盖」、验证记录记「某一次验收跑出了什么」。
这次只是把第三样的**存放位置**从 README 挪到 `docs/`，内容一份没删——
**「未验证」清单整份跟着搬过去了**，那是规格书「不得把没做过的事写成已完成」这条红线的凭据，
不许在搬家路上掉。

### 新的维护规则（已写进 `CLAUDE.md`）

本轮实跑结果与未验证项写进 `README.md` 的「验证记录」；写新一轮时，把**被顶下来的上一版**
挪进 `docs/verification-log.md`（按时间倒序，最新在最上面）。README 因此恒为「最近一版」，
有界且不必手工压缩。

### 引用怎么处理的

- **`README.md` 内部 3 处**「见「验证记录」」（v3.4 的录音、v3.6 的提醒投递、v3.9 的截图巡检）
  改成直链指向新文档——它们要说的事都在更早的版本条目里。
- **`CHANGELOG.md` 里的历史引用一律不改。** 它们写的是当时那句「记在 README「验证记录」」，
  改了就篡改了记录；而指针也不会断——README 那一节的第一行就写着完整记录在哪。
- `docs/superpowers/specs/2026-09-28-docs-reorganization-design.md` 的「职责边界」表加了
  一行给新文档，并把 README 那行的「最近验证记录」写实（原地更新，不新开规格）。
- 顺带：`test/compass_test.dart` 有一处**上一版遗留**的纯格式化改动（`dart format .` 把
  两行的 `expect` 合成一行，无行为变化）。不是这一轮改的，但既然 `dart format .` 每次都会
  重排它，就一并留着并在这里记一笔，免得下一个人以为是本版引入的。

## 3.13（2026-10-13）

**把 Android 的系统栏拉齐到 iOS 的语义：内容铺满整屏，状态栏与导航栏透明地浮在内容
之上。** 用户真机上报的两条——「顶部状态栏是灰色的（light 模式下）」「底部的安全区域
被截断，不像 iOS 那样的安全区适配」——都是同一条根因的两副面孔。顺带修掉标签条压在
手势条上的问题（那是把系统栏改成 transparent 之后**才暴露出来**的，见下）。

### 根因：两条都不是渲染问题，是样式没声明

到动手之前没有猜过一条，全是量的（判据与命令见规格 §6.1）：

- **顶部灰带**：引擎默认只申请到 `LAYOUT_FULLSCREEN`（`PlatformPlugin` 的
  `mEnabledOverlays = 0x500` = `LAYOUT_STABLE | LAYOUT_FULLSCREEN`）。内容其实**已经**
  画到顶了，是系统在**透明**状态栏背后自动加了一层对比度蒙层（Android 10+ 的
  `enforceStatusBarContrast`）。那层蒙层把状态栏那一条压成了 `(181,181,186)`，而紧挨着
  它的页面像素是 `(240,242,248)`——**比值约 0.75，即蒙层约 25% 黑**（真机采样读数，不是
  令牌值：浅色 `bgBase` 是 `0xFFF2F2F7`、`Atmosphere` 顶色是 `0xFFF6F8FF`，都对不上）。
- **底部黑带**：`mEnabledOverlays` 里**没有** `LAYOUT_HIDE_NAVIGATION`，导航栏那块被
  排除在内容区之外。实测 Flutter 内容区止于 `y=2296`（屏高 2340），黑带从那里起——
  也就是说 `MediaQuery.padding.bottom` 是 **0**。

### 改动

- 新增 `lib/core/platform/system_bars.dart`：`enableEdgeToEdge()`（`main()` 里**第一帧
  之前**调，Android 专属，`kIsWeb` 排在平台判断之前）+ `appSystemUiOverlayStyle(Brightness)`
  - `appSystemUiOverlayRegion`（挂在 `MaterialApp.builder` 上：那里在主题之内、路由之上下，
  `Theme.of(context)` 拿到的才是应用当前生效的明暗；各页自己的 `AnnotatedRegion` 又压在
  它上面，所以常暗的会话页照旧说话算数）。
- **不得用 `SystemUiOverlayStyle.light` / `.dark` 这两个预设**：它们把
  `systemNavigationBarColor` 写死成不透明黑（`0xFF000000`），黑带会原样回来。两个预设
  长得就像为此准备的，所以 `test/system_bars_test.dart` 专门钉了一条断言把这个坑记在案。
- **`*ContrastEnforced: false` 是顶部那条灰带的唯一解法**——只把颜色设成透明不够，蒙层照加。
- `sleep_session_page.dart` 那一层固定的 `SystemUiOverlayStyle.light` 换成同一份函数：
  否则进睡眠模式时导航栏会单独变回黑带（同一个预设坑）。
- **`tabBarFloat` 的回收量按平台分叉**（iOS 14 / Android 0），这是全工程唯一按平台分叉的
  布局常量。改成 transparent **之后**才量得出来：Android 的手势条贴在安全区**下沿**
  （16dp 里只有约 5dp 是空的），照搬 iOS 那 14 之后胶囊底边落在 `y≈2307`、手势条上沿在
  `y≈2312`，只差 5px——看着就是压在一起。改完胶囊底边在 `y=2296`（离底 44px，2.75 倍下正好 16dp，
  正是 `tabBarFloat` 算出来的），与手势条之间留出 14px。总规格偏差 #21 与 #51 已同步。

### 真机验证（Xiaomi MI 9 / Android 11 / MIUI 12.5.6，`e0e60672`）

**已验证**（改前 / 改后是同一台机器、同一个页面）：

- 顶部 `x=30` 一列采样：`y<75` 从 `(181,181,186)` 变成 `(241,241,248)` 一类的页面背景——
  灰带整条消失，浅色主题下状态栏图标仍是深色。
- 底部黑带消失，页面背景铺到 `y=2339`；胶囊底边 `y=2296`、手势条上沿 `y=2310`。
- 推入页（`外观`，走 `Subpage` 的 `SafeArea`）同样两条栏透明。
- **浅色应用主题下进常暗的会话页**：状态栏图标如期变白、背景铺到导航栏后面——
  这一条正面验证了「页面自己的 `AnnotatedRegion` 压过 `builder` 那一层」。
- **应用内切深色而系统仍是浅色**：状态栏与手势条图标双双变白。
- `flutter test` → **609/609 通过**（v3.12 是 592，净增 17）；`flutter analyze` 零问题。
  其中 `test/system_bars_test.dart` 10 条、`test/tab_bar_inset_test.dart` 由 4 条变 10 条
  （每条平台用例都改用 `TargetPlatformVariant` 写明平台，**不这么做 iOS 那一支永远不会被
  碰到**：`flutter_test` 会把 `defaultTargetPlatform` 恒钉成 android）。

### 一处「计划里说不许变、实际变了」的行为：iOS / macOS

计划的硬约束原文是「iOS / macOS 的行为一个字都不许变」。**没做到。**
`appSystemUiOverlayRegion` 挂在 `MaterialApp.builder` 上是无条件的，于是 iOS 的状态栏
前景色从「跟随**系统外观**」（改前全应用只有会话页一处 `AnnotatedRegion`）变成了
「跟随**应用主题**」。**那正是本意**——应用有自己独立的外观开关，系统栏若跟随系统，
深色的页面上会压出一排看不见的黑字——但当初写约束时没想清楚，而 **iOS / macOS 本轮
一次都没跑过**（全程 Windows + 一台 Android 真机）。如实记，未验证。

### 测试网：审查发现两个挂载点零覆盖，已补

独立审查（一份，末尾做一次）指出：**把 `app.dart` 的 `builder: appSystemUiOverlayRegion`
整行删掉，606 条全绿**；会话页那一层覆写同样零覆盖。两条都成立——原先的
`test/system_bars_test.dart` 各自搭一个 `MaterialApp` 测函数本身，对「挂没挂上去」一无所知。

补齐方式：新增 `test/system_bar_probe.dart`（探针，**不以 `_test.dart` 结尾所以不会被当用例跑**），
复刻 `RenderView._updateSystemChrome` 的取值路径——状态栏取屏幕水平中线与顶部的交点、
导航栏取与底部的交点，各取覆盖该点的最上面一层。于是断言的是**框架真会发给平台的样式**。
用它补了三条：真实 `NightSleepApp` 的两条栏都读得到样式、应用切深色时跟着翻、
常暗的会话页自己那一层压过应用那一层（外层刻意给浅色主题才区分得出来）。
**已变异验证**：删掉 `app.dart` 那一行 → 前两条红；把会话页换回
`SystemUiOverlayStyle.light` 预设 → 第三条红。另补了 `enableEdgeToEdge()` 的两条：
Android 上发出 `SystemUiMode.edgeToEdge`、iOS / macOS 上一次都不发（截 `SystemChannels.platform`）。

**未验证，不得当成已完成**：

- **API 29 以下的设备**：引擎的 `setSystemChromeEnabledSystemUIMode` 有 `SDK_INT >= 29`
  的门槛，`edgeToEdge` 在那些设备上是空操作，应维持旧样子。**本机只有 API 30 一台，没验过。**
- **API 35 及以上的设备**：`targetSdk` 是 36，而本轮用到的
  `setStatusBarColor` / `setNavigationBarColor` / `setStatusBarContrastEnforced`
  在 API 35 起是 deprecated no-op（引擎字节码里也有 `SDK_INT < 35` 的门槛）。
  预期结果一样（系统自己强制 edge-to-edge），但那是另一套系统行为，**没验过**。
- **iOS / macOS**：见上面那一节——状态栏样式的来源被改了，且**一次都没跑过**。
- **三键导航**：真机常年手势导航。三键导航安全区约 48dp，按本轮规则胶囊会整个让开它
  ——**这是推断，不是实测**。
- **横屏**：本轮只测竖屏。

## 3.12（2026-10-13）

**把罗盘接上 Android：新增一条手写的 Kotlin `EventChannel`，逐项复刻 iOS 那套算法；
`compass_page.dart` 一行未改。同时修掉 v3.11 遗留的 `.metadata` 平台列表被覆盖的问题。**

### Android 罗盘（`night_sleep/compass`）

- 新增 `android/app/src/main/kotlin/com/example/night_sleep/CompassStreamHandler.kt`：
  `TYPE_MAGNETIC_FIELD` + `TYPE_GRAVITY` + `TYPE_GYROSCOPE`，由**陀螺仪**驱动发射、
  限流 30 Hz（对齐 iOS 的 `1/30`），事件字段与 iOS 逐项对齐。
- `MainActivity.kt` 改为覆写 `configureFlutterEngine` 注册通道。**`super` 那一行是必须的**：
  embedding v2 下插件注册就在它的实现里，漏了会让通知、录音、安全存储**全体静默失效**，
  编译期与运行期都不报。另有 `onDestroy` 里的兜底反注销。
- `lib/core/platform/compass.dart`：判定放行 `TargetPlatform.android`；`CompassUnavailable`
  的文案由「请使用支持罗盘的 **iPhone** 打开此页面」改为「当前平台暂不支持罗盘」。
  **`kIsWeb` 必须留在平台判断之前**——Web 上 `defaultTargetPlatform` 报的是宿主机系统。
- **页面零改动**：`compass_page.dart` 早就分好了两支，Android 只要照 iOS 发
  `error(code: "unavailable")`，「此设备没有可用的罗盘传感器」那句就是白拿的。
- **不加清单条目**：读传感器不需要任何权限；`<uses-feature>` 只影响商店筛选、对运行时零作用。

### 与 iOS 唯一的符号差异（这一条若不改，罗盘永远是坏的）

Android 的 `TYPE_GRAVITY` 在平放屏幕朝上时报 Z = **+9.81**，CoreMotion 报 −1.0，两者**反号**。
所以 `up = +normalize(gravity)`（iOS 取负），而 `tilt` 与 `rotationRate = -(gyro·up)` 两式不变。
照抄 iOS 那个负号的后果很具体：平放时 `upZ = −1` → `tilt = 180°` → `tilt < 60` 永不成立 →
**`heading` 永远是 null**，页面永远停在「请将手机屏幕朝上，保持水平」，而手机明明就平放着。

`accuracy` 也必须换算：Android 是 `UNRELIABLE 0 / LOW 1 / MEDIUM 2 / HIGH 3`，iOS 是
`−1 / 0 / 1 / 2`，即 `ios = android − 1`。**`else` 那一支不能省**——Android 还有
`SENSOR_STATUS_NO_CONTACT = −1`，朴素的 `−1` 换算会得到 −2，而 Dart 的门槛是
`accuracy != uncalibrated`（≠ −1），−2 不等于 −1，于是**一个「磁力计没接触」的读数会被
当成有效方位发布出去**。

### 真机验证（Xiaomi MI 9 / Android 11 / MIUI 12.5.6，`e0e60672`）

**已验证**：

- 通道以约 30 Hz 稳定出数（`adb logcat -s Compass:D`）。
- 页面从「请使用支持罗盘的 iPhone…」变成实时读数：`51°` / `东北 · 艮山` / `当前方向 东北` /
  `手机倾斜 5°`，表盘随方位旋转。二十四山取档（51° → 艮，45–60）人工核对无误。
- **`tilt` 在平放时约 5°**——这一条正面验证了上面那个符号修正。
- `accuracy` 换算被实测走到（原始 `1` → 映射 `0`）。
- **磁场被污染时会正确地拒绝发布方位**：手机挨着笔记本时实测 259 µT（地磁只有 25–65 µT），
  页面显示校准提示而不给方向；挪开后降到 62–64 µT，方位随即出现。

**未解决，不得当成已验证**：

- 手机**证明过静止**（我们自己前后两次读数 12 秒内相差 0.2°、陀螺仪速率 0.000），
  我们读到 `48.3°`，而系统自带 `com.miui.compass` 读 `5°`——**差 43°**。
  两条相关但都不足以定案的观察：MIUI 自己在一分钟内从 `18°` 漂到 `5°`；
  **两个应用都独立地要求校准**。**假设**（是假设，不是结论）：磁力计的硬铁校准未建立，
  读数仍带着手机自身的磁偏置——实测竖直分量约为该纬度物理值的两倍
  （纬度约 22.6°、磁倾角约 31°：总场应 ≈45 µT、水平 ≈39、竖直 ≈23；实测水平 41.5、竖直 49）。
  **判据尚未跑**：把手机转过一个已知角度，看方位角是否同步变化——这能把「算法结构性错误」
  与「绝对校准偏差」分开。
- **横屏的 90°/270° 两个分支未验证**：这台机器的自动旋转是关的
  （`accelerometer_rotation=0`），`getRotation()` 恒为 `ROTATION_0`，物理转手机也不会进那个分支，
  只能靠改 `user_rotation` 来试。代码注释里已就地标明该不确定性。
- **完全没测**：macOS（按决定不做）、Web、以及没有磁力计的设备（模拟器应显示
  「此设备没有可用的罗盘传感器」）。

Kotlin 侧**没有任何单元测试**——本仓库没有 Kotlin 测试设施。Dart 侧新增 4 个用例，
**只钉得住键名、类型、null 与否和错误 code，钉不住任何数值**。

### 修掉 v3.11 的一处缺陷：`.metadata` 的平台列表被覆盖

`flutter create --platforms=android .` **不是「加一个平台」，而是把 `migration.platforms`
整体重写成只给的那些**——v3.11 那轮因此把 `ios` / `macos` / `web` 三条**删掉了**。
不影响构建，但记账错了、信息丢了。本轮用 `git checkout` 还原 HEAD 原值后**加回** `android`，
diff 只剩新增的三行。

**同源的暴露（未处理，待定）**：`unmanaged_files` 里只列了
`ios/Runner.xcodeproj/project.pbxproj`，而我们手改过的
`android/.../MainActivity.kt` 与 `AndroidManifest.xml` **没有这层保护**——
将来跑 `flutter migrate` 可能把手写的通道注册与清单改动冲掉。

### 构建 release 包：三个新踩到的坑

1. **直接调 `gradlew assembleRelease` 会失败**，报
   `GeneratedPluginRegistrant.java: 找不到符号 dev.flutter.plugins.integration_test`。
   那个注册文件是 **Flutter CLI 生成、且按构建模式过滤**的（release 排除 `dev_dependency`），
   绕过 CLI 就复用了上次 debug 留下的旧文件。**先跑一次 `flutter build apk --release`
   让它把注册文件重新生成对**，之后再回到 `gradlew`。
2. `flutter build apk` **传不了 `-Pkotlin.incremental=false`**，会撞上
   `Could not close incremental caches … .tab`（疑杀软占句柄）。
3. `flutter build apk` 需要 `FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`——
   引擎的 ABI jar 来自 `storage.googleapis.com/download.flutter.io`，**不在 `cn-mirrors.gradle`
   改写的三个域名里**。缺了它 `:app:compileDebugKotlin` 会**挂住十几分钟且一句错都不报**。
   诊断杀手锏是加 `--offline`：它把「挂住」立刻变成「明确说你缺哪个包」。

### 本轮仍未做（**不得视为已完成**）

- 上面那条 43° 的差异**未定案**；横屏轴映射未验证。
- `CompassStreamHandler.kt` 里 `DEBUG_LOG = true` **仍然开着**（30 Hz 打原始磁场与重力矢量）。
  它只影响罗盘页，但**正式发布前必须关掉或删掉**。
- release 包**用 debug 证书签名**，能侧载，**不能上架**。
- 后台 / 锁屏录音、`android:allowBackup` 两笔仍是 v3.11 的状态，见下。

## 3.11（2026-10-12）

**接入 Android 平台：生成 `android/` 目录，补齐通知重启与夜间录音所需的清单配置，打开 core
library desugaring。Dart 代码一行未改，`flutter test` 条数与上一版完全一致。**

### 平台目录与构建配置

- `android/` 用 `flutter create --platforms=android .` 生成（Flutter **3.47.5**，与
  `.metadata` 里记的 `create_revision` 同源），**不手写**——模板里的 AGP / Gradle / Kotlin
  版本跟着 SDK 走，手写的下一次升 SDK 就脱节。
- `.metadata` 的 `migration.platforms` 多一条 `android`；`analysis_options.yaml` 的
  analyzer 排除列表多一条 `android/**`（与既有的 `ios/` / `macos/` / `web/` 一致）。
  这两处是 `flutter create` 自己改的，不是手加的。
- **删掉了模板顺手塞进来的 `test/widget_test.dart`**：它引用不存在的 `MyApp`，
  留着会让 `flutter test` 直接失败。它不属于本工程。
- 构建参数**一个数字都没写死**：`compileSdk` / `minSdk` / `targetSdk` / `ndkVersion`
  继续取 `flutter.*`，因为**逐个核过全部插件的真实下界**——最高的是
  `flutter_local_notifications` 22.3.1 与 `record_android` 2.2.0，都要求
  compileSdk 36 / minSdk 24，而 Flutter 3.47.5 的模板默认正是 36 / 24，**恰好相等**。
- **core library desugaring 是这一轮唯一的 gradle 改动**，且必须开：
  `flutter_local_notifications` 10+ 的 README 明说「即使用不到排定通知也必须开」。
  开关（`isCoreLibraryDesugaringEnabled = true`）与依赖
  （`coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")`）**成对**，
  缺一个都编译不过。

### 清单：每一条都核过插件源码，不是照抄文档

`android/app/src/main/AndroidManifest.xml` 加了这几样、**故意不加**三样：

| 加 | `RECEIVE_BOOT_COMPLETED`、`ScheduledNotificationReceiver`、
`ScheduledNotificationBootReceiver`（四个 action）、`FOREGROUND_SERVICE`、
`FOREGROUND_SERVICE_MICROPHONE`、**`INTERNET`**；`android:label` 由 `night_sleep` 改为
**「夜深」**（与 iOS / macOS / Web 三端一致） |
| --- | --- |
| **不加** | `POST_NOTIFICATIONS`、`VIBRATE`（**核实**：确在 `flutter_local_notifications`
22.3.1 自己的 manifest 里，构建时合并）；`RECORD_AUDIO`（**核实**：确在 `record_android`
2.2.0 的 manifest 里）；`<service>`（**没有实现，声明一个指向不存在类的服务会直接编译失败**） |

**`INTERNET` 是差点漏掉的一条，值得单独说**：Flutter 模板只在 `src/debug/` 与
`src/profile/` 两个**变体清单**里带它（给 hot reload 用），**main 里没有**，
所以「拿模板逐行比对」根本发现不了；而本应用确实联网（洞察服务的模型列表 / 余额 /
连通性测试 / 生成洞察），且没有任何插件会把它合并进来。**漏了的后果只在 release 包发作**：
debug 一切正常，release 里所有洞察请求以 `SocketException` 失败，开发期看不出来。
这条由本轮末尾的独立审查提出，已核实并落地。

**订正了两处此前文档里没核过的推断**：上游规格与 README 都写着「接入 Android 时要补
`RECORD_AUDIO` 权限」——实测它由插件自带并合并，应用侧不声明。另外总规格 §10 第 6 条写着
「Android 的 `RECORD_AUDIO` 用途串随平台目录生成时一并补」——**「用途串」是 `Info.plist` 的
机制，Android 没有对应物**，这一条在 Android 上无从落地，也不需要。

### Android 启动图标（同日追加）

原计划把图标留作后续，使用方要求一并做掉。`tool/generate_app_icons.dart` 从「两个平台」扩到
「三个平台」，且 Android 一个平台就要**两套**：

- `mipmap-*/ic_launcher.png`（48/72/96/144/192）：满幅直角、无 alpha，给 **API < 26**。
  与 iOS 同一条渲染路径，也**不倒角**——API < 26 的启动器不套遮罩，倒了就是「方角套圆角」。
- `mipmap-anydpi-v26/ic_launcher.xml` + 两层位图：**自适应图标**，给 API ≥ 26。底铺满
  **108dp** 画布（纯渐变）、前景缩进中央 **72dp**（月亮与声波，四周透明），系统自己套遮罩。
  两套共用资源名 `ic_launcher`，所以清单里的 `android:icon` 一个字没改。

**做这块时踩到两个只有装到手机上才看得见的坑，都没放过**：

1. **主体按固定比例缩会被圆形遮罩切掉。** 源图墨迹几乎铺满 1024 画布，按「1024 → 72dp」
   缩进来，墨迹外接圆 691.5 > 可见区 682.7（超出 1.3%）——第二道声波的尾端会被切。
   改成**按墨迹外接圆定标**（让外接圆正好收进可见区），产物比 iOS 构图只小 1.3%。
   这条是被自己写的兜底断言顶出来的，不是一开始就想到的。
2. **主体本身就不在画布中心。** 源图墨迹中心在 (642,584)，比画布中心偏右下 130/72——
   那是给满幅方图（iOS / macOS）构的图。自适应前景必须**量出墨迹包围盒再重新居中**，
   否则在圆形遮罩里明显偏。

另外切图分成两份（底 / 主体），因为底里若混进主体，叠上前景会看到一大一小两个月亮。
切不出源图那句满幅 `<rect>` 时**当场失败**，不产出错图标。

**回归**：`test/app_icons_asset_test.dart` 加 4 条（共 9 条），钉住「墨迹全在中央 72dp 圆内
且居中」「背景层近白像素数为 0」等。**已做变异验证**：摘掉重新居中，断言立刻报
「最远 45.1 > 半径 36.0」。**iOS 与 macOS 的图标文件重跑后一个字节都没变**——
证明重构 `_writeAll`（抽出 `_writeOne`）没有碰坏原有两条渲染路径。
**仍未经目视**：产物只经像素级断言核对，**没有装到手机上真的看一眼**。

### 在安卓模拟器上实跑（同日追加）

用 Pixel 6 Pro / API 34（Android 14）的 AVD 实跑了一遍，**这是本轮唯一一次真机级验证**：

- `adb install` → `am start` 成功，**首页完整渲染**（讲解卡、圆环、最近记录、玻璃胶囊标签条、
  中文正常），**logcat 里该应用无任何 error / exception / fatal**。
- **图标在真实启动器里目视核对**：Pixel 桌面用**圆形遮罩**，我们的图标被正确套成圆形、
  **月牙与两声波完整可见、没被切、构图居中**——「墨迹落在中央 72dp 圆内」那条断言，
  现在有了模拟器层面的证据。同屏相册 / YouTube 显示的是旧式处理（缩小放白盘），
  **只有我们的图标铺满遮罩**，说明自适应图标这条路真的生效。
- `aapt2 dump badging` 复核：**`application-icon-<每个密度>` 都解析到
  `mipmap-anydpi-v26/ic_launcher.xml`**，系统在全部密度上取的都是自适应图标。
- **一处未解释的观感**：我们的图标最外圈约 1/4 半径处有一圈淡浅蓝亮环，同屏 Chrome 没有。
  已核实**不是产物的错**——用两层位图自己做合成 + 圆形遮罩，扫描线上没有亮环。
  成因未定（疑与启动器对**位图背景层**的处理或模拟器 GPU 渲染有关），**留作待查**：
  下一步可把背景层换成纯色 `@color` 看亮环是否消失。**没有把它写成「有意为之」。**
- **仍未验证**：真机（非模拟器）、通知真的到点投递、重启后重排、前台录音、后台录音。

### 刻意没做（**不得视为已完成**）

- **后台 / 锁屏录音仍然不能用**：权限声明了、**前台服务没有实现**。
  「声明了不等于能用」，这句话写进了清单注释与 README。
- **「去系统设置」在 Android 上点了没反应**：`app_settings.dart` 对非 iOS/macOS 退回
  `app-settings:`，Android 没有等价 scheme。这不因本轮改动**产生**，但**从本轮起 Android
  是「已支持平台」**，它就从「未生成平台的代码路径」升级成了一条真实的界面缺陷。
- ~~**罗盘未接 Android 传感器**~~ ——**v3.12（2026-10-13）已做**，见上。原文留档：
  当时判断「要接罗盘等于把 iOS 那套算法在 Kotlin 里重做一遍并真机校准，不是『接线』，
  是『新做一遍罗盘』」——**这个判断是对的**，v3.12 确实是新做了一遍。
- **`android:allowBackup` 保持 Android 默认（= 允许备份）**：`flutter_secure_storage` 的
  README 建议设成 `false`。本轮**没改**——它会静默改变产品语义（换机后没有数据可恢复），
  且 Dart 侧 `read()` 已用 `on Object { return null; }` 兜住「恢复后读不出密钥」这个异常，
  不构成缺陷。**但有一条要说清**：备份开着意味着**数据库与录音片段可能被上传到用户自己的
  Google Drive**，而应用对用户的承诺是「录音片段仅保存在本机，**不会上传**」。
  **这句话在 Android 上因此并不严格成立。** 三个可选处置写在规格 §5.4，**待使用方裁定**，
  本轮一个都没执行。
- **一律没有真机 / 模拟器验证**：构建通过、清单合并正确，**不等于通知会响、录音录得下来**。

详见 [安卓平台接入设计](docs/superpowers/specs/2026-10-12-android-platform-design.md)。

### 本机环境（不入库，但下一个在此工作区动手的人需要知道）

本机 PATH 上的 Flutter 是 **3.16.7 / Dart 3.2.4**，**解析不了本工程**
（`Because night_sleep requires SDK version >=3.3.0 <4.0.0, version solving failed`）。
本轮装了 **Flutter 3.47.5**（Dart 3.13.4）到 `C:\src\flutter-3.47.5`，**与旧 SDK 并存、
不改 PATH**。另：README 此前写「本工作区尚未安装 Android SDK」——**已订正，SDK 早就装了**。

## 3.10（2026-10-03）

**四处显示与交互修正：主按钮的顶边高光在圆角处溢出成白刺；会话页的状态栏在亮色主题下是黑的；
入睡前那一屏的按钮被底部安全区切掉一截；「清除缓存」缺一道二次确认。**

### 主按钮顶边高光溢出圆角（`PrimaryAction`）

用户报「深色模式下首页『开始入睡』顶部有一根白线，左上右上圆角处明显」；睡眠结束弹窗里的
按钮与回顾页的「保存补充」同病——三处都是同一个 `PrimaryAction`，改一处三处都好。

根因不是颜色而是**几何**：那条 `inset 0 1px rgba(255,255,255,.25)` 的镜面高光是一条 **1px 高的
直条**，而它要贴的是 16px 的圆角。`BoxDecoration` 的圆角在高度不够时会被压到 0.5px 以下
（等于直角），于是这条直条**两端顶到按钮的矩形边界**，横着伸出圆角之外；中间那截压在蓝渐变上
尚且含蓄，两端的溢出落在黑底上就成了两根白刺——「圆角处明显」正是这个。

修法是**裁**而不是删：给按钮的 `Container` 加 `clipBehavior: Clip.antiAlias`，子层（含高光）
一并裁进那个 `borderRadius` 里，高光从此止于圆角开始的地方。**高光本身按 2026-09-29 那轮的
结论保留**（启用态需要它，禁用态本来就不画它）。

像素级取证（黑底 1x 快照，本机 Flutter 实际渲染）：修前按钮左右上角**外侧**
（y = 顶边 +1，x = 左边界 +0…+10 与右边界 −10…0）是 `(48,48,48)` 的白灰条，修后同一批像素全部
归零；顶边正中那截 `(58,153,253)` 两版逐像素一致——**只有溢出的部分变了**。回归测试钉在
`test/primary_action_test.dart`：高光必须落在裁剪层之内，且裁剪路径排除左右上角之外的像素、
保留顶边正中（含变异验证：摘掉 `clipBehavior` 该条必红）。

### 会话页在亮色主题下的状态栏

会话页整页是夜景、主题由页面自套 `AppTheme.dark()`，但**系统状态栏跟的是应用主题**：
亮色主题下时间是黑字，压在满屏夜景上等于没有。整页外面包一层
`AnnotatedRegion<SystemUiOverlayStyle>` 固定成 `SystemUiOverlayStyle.light`——这一页常暗，
对两种主题一律取浅色前景。

### 入睡前那一屏：按钮被底部安全区切掉一截（用户报的）

用户报「底部安全区把开始睡眠按钮切掉一截」，并要「整体尽量在一个画面中、不要滚动」。

**根因不是安全区留白算错，而是这一屏比手机高。** 写死的 hero 285 + 卡片 ~399 + 按钮区 ~88
再加留白，在**扣掉安全区**（59 / 34）之后放不进 874 高的机器：可用只剩 781，而内容要 841。
其中 285 那一项还来自一条被误用的媒体查询——原型的 `@media (min-height: 860px)` 量的是
**浏览器视口**，照搬到 Flutter 里量的是**屏幕高度**：874 ≥ 860 于是白拿了高屏那一档，
真实可用高度只有 781。

改法两步：

1. **底部动作区（按钮 + 提示）钉在安全区之上、不参与滚动**——这是硬要求，任何机型上按钮
   都不会被切（实测按钮底边距 home indicator 上沿 36pt）。
2. **上半区（标签行 / hero / 卡片）拿剩下的高度，放不下时才滚动**；hero 的高度改成
   **按可用高度连续取值**（夹在 `[0, 285]`，挤的时候一路收到它自己的内容高度 ≈ 210），
   不再是二值判断。卡片按 410 预留，**宁可高估**：高估只是把 hero 的留白挪到它上下的
   间隙里（`spaceBetween` 分配，看不出差别），低估才会让卡片被滚到下面去。

实测（本机渲染，安全区 59 / 34）：`402×874`、`393×852`、`430×932` 上**滚动上限都是 0**
（一屏放下，一点不用滚）；`375×667`（SE）确实放不下，上半区可滚，按钮照样完整。
与原型的有意偏差记在会话规格 §17.2.1：**hero 的 `padding: 24 0 22` 改由「在拿到的高度里
居中」实现**（留白就是余量本身），以及**底部动作区不参与滚动**。

### 「清除缓存」补上二次确认（用户要求）

清缓存删的是可再生成的临时文件（导出副本那一类），原本点一下就直接删——它因此成了应用里
唯一一处「不可撤销的删除却没有确认」的动作。现在与另外四处删除一样过 `showConfirmDialog`，
`destructive: true`；文案把范围写死：「只删掉导出副本这类可以再生成的临时文件，睡眠记录与
录音片段都不会动。删除后无法恢复。」

### 实测数字

| 项 | 结果 |
| --- | --- |
| `flutter test` | **584/584 通过**（v3.9 的 578 之后净增 6 条：裁剪护栏 1、入睡前页的「底部安全区与一屏放下」组 4、清除缓存的取消 1） |
| `flutter analyze` | No issues found（中途出现过一条 `integration_test/` 的 `main` 未定义，来自 `lib/main.dart` 被整段注释掉的本地临时改动，与本节无关；使用方当场还原后复跑即无） |
| 目视 | 主按钮以黑底 1x/3x 快照逐像素核对（见上）；入睡前那一屏以**整页黑底快照**核对了 `402×874 / 393×852 / 390×844 / 430×932` 四档（三种比例下卡片三行与按钮都完整）。两份快照都是**一次性**用例拍完即删，没进版本库。**仍未在模拟器 / 真机上目视过** |

## 3.9（2026-10-03）

**夜间录音接入（plan B）：会话期间真实采集环境声音、按振幅切成「有声响的片段」，详情页可回放、
可手动标注——但真机整夜后台存活未验证。**

规格 M3 的核心项。设置页与会话页那个「鼾声/梦话记录」开关，从 plan A 起一直只保存偏好、
界面如实写着「尚未接入录音，开关只保存偏好」（偏差 #7）；这一版把中间那段补上，**偏差 #7
到此作废**（#31 / #35 / #44 同步作废）。**这一轮不做任何自动识别**：不分类、不转写、不生成结论
——录到的是「有声响的片段」，是鼾声还是梦话由用户听过之后自己标。

### 实测推翻的一条前提：不是 (a)/(b) 二选一，走第三条路

会话规格 §六 把切片路径列为「(a) 边录边分文件 / (b) 连续录临时文件后裁剪」，要求实测插件后
二选一。实测（读 `record` 7.1.1 与 `record_ios` 2.1.1 源码，非文档推断）后两条都不是：

- (b) 按原措辞「连续录一个临时文件」峰值存储会爆：16kHz 单声道 16-bit = 32 KB/s，8 小时
  **≈ 880 MB**；且 AAC 事后裁剪要解码重编码（得引 ffmpeg）。
- `AudioEncoder.pcm16bits` 在 iOS / macOS 都能**流式**输出，流是**裸小端 PCM16、没有容器头**。

于是走**第三条路**：PCM 流每 100ms 聚合一格 RMS、喂给切片纯函数，事件触发时把环形缓冲里的
前置 padding 按字节切出来、写成一个 WAV。它**只有事件落盘**（一晚几十 MB）、**不需要事后裁剪**，
拿到了 (a) 想要的低峰值存储，又没有 (a) 反复开关录音机带来的片段间隙与前置 padding 丢失。

### 改了什么

- **依赖**：`record: ^7.1.1`（PCM16 流式采集）、`url_launcher: ^6.3.2`（跳应用设置页）。
- **平台配置**：iOS `Info.plist` 加 `NSMicrophoneUsageDescription` 与 `UIBackgroundModes: [audio]`；
  macOS `Info.plist` 加 `NSMicrophoneUsageDescription`，两个 entitlements 都加
  `com.apple.security.device.audio-input`。**用途文案由使用方确认并落地**：
  「用于在夜间录制环境声音。录音片段仅保存在本机，不会上传；可在设置中随时删除，超过保留期限的
  片段会自动清理。」
- **schema v5 → v6**：加三列可空列、**不重建任何表**（都是 `addColumn`）——
  `active_sessions.clip_journal`（text）、`sound_clips.waveform_envelope`（text，JSON 数组）、
  `sound_clips.labeled_at_utc`（dateTime）。**两条下界不同**：`sound_clips` 两列从 v2 起就存在，
  写 `from >= 2 && from < 6`；`active_sessions` 是 v4 才建的表，写 `from >= 4 && from < 6`。
  这**订正了会话规格 §二「录音不需要改表」**（记入偏差 #48）。
- **采集参数**：16kHz 单声道 PCM16；`autoGain` / `echoCancel` / `noiseSuppress` **全关**——
  它们都会改变信号，开着等于让「实测包络」变成对处理链的测量。
- **切片**：`clip_segmentation.dart` 的 `ClipSegmenter`（增量状态机，唯一实现）＋ `segmentClips`
  （批处理薄包装，纯函数）＋ `envelopeFor`。默认参数：触发 −38 dBFS、结束 −45 dBFS（滞回）、
  静音 2s、前置 padding 500ms、最短 1s、最长 60s、合并间隔 1.5s。**这七个值全部没在真机上验证过。**
- **落盘**：不边录边开文件——把最近 **75 秒** PCM 留在有界环形缓冲里，切片定案时按字节偏移切出来
  写一个 WAV（一段一个文件），目录 `getApplicationSupportDirectory()/clips/`。
- **片段暂存**：会话进行中片段入不了库（`SoundClips.recordId` 是外键、指向还不存在的记录行），
  清单先进 `active_sessions.clip_journal`、**每录完一段更新一次**；`finish()` 在同一事务里把清单
  落成 `SoundClips` 行再删会话行。**App 被杀重启后清单还在。**
- **白噪音优先**：白噪音播放期间**不录音**，停了才开始（会话页显示「白噪音播放中 · 暂不录音」）。
  **这段空档是真的覆盖缺口**（记入偏差 #49）。
- **保留期限**：默认最近 **7 晚**（按醒来那天的本地日期归档，与 `SleepEntry.archiveDay` 同一口径）。
  超期删音频文件、`localUri` 置空、**行保留**；只清 `source='recording'`。启动时另删既不在库里、
  也不在会话清单里的孤儿文件。
- **标注**：详情页声音卡接**真的 `just_audio`** 回放（此前 `_togglePlayback` 只翻一个局部布尔、
  不出声），可标注为打鼾 / 梦话 / 杂音，写 `kind` 与 `labeledAtUtc`；**未标注的显示「待标注」，
  不显示「杂音」**。
- **界面**：会话页鼾声行副标题改为录音服务的**实际状态**（录音中 / 白噪音播放中 · 暂不录音 /
  停止原因），真在录时挂一颗小灯；设置页副标题改为「录下有声响的片段，由你听过之后自己标注」，
  新增占用与「删除全部录音」，打开开关前申请麦克风权限、被拒回弹并给「去系统设置」（新做
  `lib/core/platform/app_settings.dart`，**没有**复用通知那个入口）。
- **空状态措辞订正**：首页 hero 卡「全程安静」→「无声音片段」；详情页「声音记录 · 无异常 /
  全程安静，无异常声音」→「声音记录 · 无片段 / 这一晚没有声音片段 ＋ 可能是整夜安静，也可能是
  没有录音。」——原措辞把「跑过检测、结论是没有」与「根本没录」说成同一件事，使用方在 iPad 上
  就被它误导过。

### 实测数字

| 项 | 结果 |
| --- | --- |
| `flutter test` | **568/568 通过**（v3.8 的 469 之后净增 99 条） |
| `flutter analyze` | No issues found |
| `flutter build macos --debug` | 通过（证明插件、entitlement 与 `UIBackgroundModes` 接得上；**构建通过不等于录音可用**） |
| 新增测试文件 | `night_recorder_test.dart`(7)、`session_recording_test.dart`(10)、`clip_pruning_test.dart`(5)、`clip_segmentation_test.dart`(23)、`wav_file_test.dart`(18)、`sound_card_test.dart`(12)、`recording_settings_test.dart`(8)；`schema_migration_test.dart` 另加 v5→v6 五条与「旧库直升 v6」三条 |

切片纯函数、WAV 写入、采集端、会话接线、保留期限这些是**单测**，不是真机验证；跑绿了只能说明
逻辑自洽，说明不了真机上录得到整夜。

### 仍未了结的事项（**不得当成已完成**）

- **真机整夜后台存活没有验证过**：锁屏后 Dart isolate 是否持续收到 PCM、片段是否持续落盘——
  这是整条路的**前提**，而只有单测与构建通过。必须在真机上插电睡一晚、看片段的时间分布是否
  覆盖整夜。**这一条没过之前，夜间录音不能算完成。**
- **七个切片阈值没有调过**：默认值全是拍的，要用真实打鼾 / 梦话样本验证「安静房间不误触发、
  鼾声不被换气停顿切碎」。
- **界面目视没有核对**：会话页录音指示、设置页新增两行、声音卡标注三选，只有几何 / 结构断言。
- **Android 未落地**：平台目录仍未生成，`RECORD_AUDIO` / `FOREGROUND_SERVICE_MICROPHONE` /
  前台服务都只写在文档里。
- **白噪音的后台播放**仍未做（与录音正好相反；README 里两者措辞已分清）。
- **没有任何自动识别 / 转写 / AI 分析结论**（M3 第 3 条只落实了「回放 + 手动标注」这一半）——
  这是刻意的，不是待办。

### 审查后修正的五处（都发生在同一天，未发布）

落成之后做了一轮代码审查，抓到五个真缺陷。它们不是笔误，都是「某条路径从来没被走过」那一类：

1. **`stop()` 不收尾正在写的片段文件。** 切片在流里定案时是同步回调，写文件却是异步的；
   不把它们收起来等完，`finish()` 就会在最后一段还没落进清单时去读那一行会话——**一次会话
   只有一段时（比如整夜就响了一声），漏掉的就是全部**。改成 `_flush()` 末尾排空所有在写的片段。
2. **`discardRecordings` 先取清单快照、再 `stop()`。** 收尾那一刻才定案的片段不在快照里，
   它的文件永远不会被删，要等到下次启动的孤儿清理才被扫掉——与「用户丢掉这一晚，音频没有理由
   留着」正相反。改成**先停、再从库里读完整清单**。
3. **`mergeGap` 在出厂默认值下永远触发不了。** 它默认 1.5 秒，而「静音时长 − 前置 padding」
   恰好也是 1.5 秒，判据又是严格小于——合并窗口是空的。后果不是「少一个功能」，而是鼾声那
   2–3 秒的换气停顿会把一整段鼾声切成几十个碎片，**正是这条规则存在的理由**。默认值改为 3 秒
   （窗口 2.0–3.5 秒），并加了一条「用出厂默认参数也能把换气停顿并起来」的测试钉住它。
4. **`ClipDraft.fromJson` 的 `as String?` 会抛 `TypeError`。** 那一句在遇到半截写入或改坏的
   `clip_journal` 单元格时抛出的异常**不在** `jsonDecode` 的 try 里，会一路穿过
   `SessionRepository.load()` 抛给调用方；冷启动那条路径是 `unawaited` 调的，于是当晚的会话
   直接读不出来——正是这个类开头承诺「一行坏数据不该让整个会话读不出来」要挡的事。
5. **「删除全部录音」不清当前会话清单里的文件指针。** 会话行里那几条还没入库的片段，文件被删了
   而清单还指着它们，这一晚结束时会写进一条声称「可回放」的片段行，用户点下去才发现文件没了。
   现在删完全部录音会顺手把清单里的 `localUri` 清空（条目保留——声响确实发生过）。

一并收拾的还有：设置页那个开关写完偏好不叫录音重新对齐（**关掉之后麦克风会一直录到天亮**，
正是「已经关掉却还在录」那条最不能有的状态）、`RecordPcmInput` 每次起录都多挂一个插件状态流
监听且从不取消、「每读一个片段就把整块 2.4 MB 环形缓冲复制一遍」（改成按需只切那一段）、
`sleepEntriesProvider` 只订阅记录表而片段表是另一张表（标注 / 裁期 / 删除录音都不会让它重读）
——现在它同时订阅 `clipsProvider`，调用方那几处 `ref.invalidate` 降级为第二道保险。

## 3.8（2026-10-03）

**助眠音效由「设备内实时合成」改为「打包实景录音」，合成器整个删除——并回到一条尚未了结的待办。**

### 推翻的裁定

规格 §8 偏差 #5 当时写的是「设备内合成 8 种噪音，**不打包任何第三方音频**」，理由是
「与原型最接近，而且没有素材授权与署名负担」。使用方于 2026-10-03 提供了 7 个实景录音素材
并裁定替换，于是这条裁定被推翻，§10「尚需用户提供的外部资料」第 3 条**部分落实**。

**授权这一半没有落实。** 使用方对这批素材（爱给网 / aigei.com）的裁定是「尚未确认、
仅供个人试用」。因此：代码注释、`pubspec.yaml`、README 与规格 §3.1 全部如实标注，
界面里**刻意不放**「素材来源 / 致谢」页（那会读作授权已确认），规格 §10 第 3 条**不关闭**。
发布前必须确认可商用授权、换素材或退回合成。

### 改了什么

- **音效列表由 8 条改 5 条**：海浪 / 篝火 / 森林 / 溪流 / 风。素材没覆盖的白噪音、棕噪音、
  粉噪音、雨声、风扇**直接删掉**，不做「用溪流顶雨声」这类替代——标签与内容不符正是
  偏差 #3 / #7 / #33 那条红线要挡的事。
- **删除 `noise_synth.dart`**（DSP 合成器、WAV 编码、可复现随机数）与它的
  `noise_synth_test.dart`；新增 `noise_asset.dart`（`NoiseKind` 5 条 + 资源路径）与
  `noise_asset_test.dart`。`noise_player.dart` 改用 `setAsset`，删掉渲染、落盘与
  `clearCache` 三段。
- **新增 `tool/generate_noise_assets.dart`** 与 `assets/noise/` 下 5 条 `.m4a`
  （单声道 22.05 kHz 80 kbps，44–75 秒无缝循环，合 3.40 MB）。
- 新增两个图标 `AppIcons.stream`（水滴）与 `AppIcons.wind`（风线）；`rain` / `fan` 保留。
- 入睡前态「常用白噪音」四格由原型的 `['rain','ocean','brown','fan']` 改为
  `['ocean','fire','forest','wind']`——原型那四条里三个 id 已不存在。

### 实测（不是纸面推演）

| 项 | 结果 |
| --- | --- |
| 素材响度跨度 | **0.9 LU**（−22.1 ~ −23.0）；源素材是 14 LU |
| 真峰 | 全部 ≤ −1.9 dBFS，无削波 |
| 循环接缝 | 五条的循环点样本阶跃全部落在各自步进分布的 **p99 以内** |
| AAC priming | 解码长度精确等于标称时长，edit list 已裁掉 priming，接缝处无静音 |
| `flutter test` | 469/469 通过；变异验证（格子宽度换回屏幕宽度）已确认变红 |
| `flutter drive -d macos` | **All tests passed**——打包资源被平台解码到 `ProcessingState.ready`，证明素材确实进了应用包 |

### 仍未做

- **听感未核对**：五条的主观可用性、切换时的响度差、循环接缝是否可闻。
- **5 格新布局无截图核对**：只有几何断言（宽屏一行、不溢出，含变异验证）。
- **授权未落实**：见上，发布阻塞项。

## 3.7（2026-10-03）

**洞察服务从「只选服务商与模型」推进到真能查、能测、能生成——并订正偏差 #3 里一条已被推翻的前提。**

### 一条实测推翻的前提

偏差 #3 原文写「不显示余额」的理由是「**无服务商提供可调用的余额接口**」。2026-10-03
用真实 key 实测：

| 请求 | 结果 |
| --- | --- |
| `GET https://api.deepseek.com/models` | 200 |
| `GET https://api.deepseek.com/user/balance` | 200，`{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"…"}]}` |
| `POST https://api.deepseek.com/chat/completions`（`response_format: json_object`） | 200，`content` 是合法 JSON `{"score":88,"summary":"…"}` |
| 同一个接口 `max_tokens: 16` | 200，但 **`content` 是空串**，正文全在 `reasoning_content` |
| 错误 key | 401，且**响应体里带回 key 的掩码形式** |

所以：#3 的理由对 DeepSeek 不再成立，改写（原型那三个演示余额仍然不采用）；
「连通性测试不能要求正文非空」，否则推理模型永远测出失败；「生成必须给足 `max_tokens`
并用 JSON 模式」。

### 改了什么

- **余额查询**（`fetchProviderBalance`）：DeepSeek 上线「查询余额」，点一下现拉现显
  （`¥41.90` 这样的读数直接来自服务商）。金额**原样保留字符串**，不转 `double` 再格式化。
  OpenAI / Claude 没有可调用接口，维持「余额查询未接入」的灰胶囊。
- **连通性测试**（`pingProvider`）：用当前服务商 + 当前模型发一次 `max_tokens: 16` 的真实
  对话请求。判定是「200 且返回补全结构」，**正文为空也算连通**——界面上把这句话写出来了。
- **重新生成**（详情页）：睡眠详情「睡眠洞察」区块改为**常显**，任意一晚都可生成模型总结，
  走 JSON 模式拿 `{score, summary}`，落库（固定 id `'$recordId-insight'`，upsert）。
  **失败只在页内报错，不写库、不覆盖已有洞察。**
- **会话内密钥**：`insightApiKeyProvider` 把 API Key 从配置页的输入框提到会话内存，
  详情页因此拿到同一把钥匙。**仍然不落盘**，#8 那条红线未动。
- **Claude 不接连通性与生成**（偏差 #46）：Messages API 形状不同且没有 key 可实测，
  `chatUri` / `balanceUri` 留 `null`，界面如实标注——不写没跑过的代码。
- **顺手修掉一个会被本轮引爆的既有缺陷**：`SleepEntry.scoreSource` 此前只看 `isUsable`，
  「模型写了总结但没给分」的洞察会把评分整个吞掉（详情页评分环凭空消失）。现改为
  **只有带回评分的洞察才顶掉本地估算**。
- **用户实机报回后补修：详情页根本不给「重新生成」按钮。** 根因是同一个设置被读了两遍：
  `AppSettings.insightProvider` / `insightModel` 在全新安装时**就是 `null`**（用户从没被迫选过
  什么，DeepSeek 与其内置模型是设置页**显示的默认值**），而详情页读的是**裸列**——它看到 null
  就判定「未配置」，于是把按钮换成了「去配置」提示。一个已经填好 key、余额查询与连通性测试
  都跑通的用户因此看不到入口。修法是新增 `resolveInsightSelection()`：**同一份默认值解析**，
  配置页与详情页共用，两处再也不会对「选中的是哪个模型」有不同说法。同时把那句提示改成
  **指名差的是哪一样**（API Key / 可用模型 / 服务商不支持），不再只说「去配置」。
  回归用例：`全新安装（provider / model 都还是 null）也照样给按钮`。
- **第二次实机反馈后补修两条**（这次是查了用户机器上的真实库才定的性：`app_settings`
  存着 `deepseek / deepseek-v4-pro`，说明设置一直是对的；`insights.provider` 全部是
  `demo`，说明一次都没生成成功过——真正缺的是**密钥本身**，它在会话内存里，而调试期间
  重启了几次 app）：
  1. **设置根页那一行改走 `resolveInsightSelection()`，并把密钥状态说出来**：
     `${服务商} · ${模型}`，密钥不在时补「未填 API Key（重启后需重填）」。
     此前它读裸列、且对密钥只字不提，用户只会看到一句与事实不符的「未配置」。
  2. **详情页的「重新生成」按钮改为常驻**：跑不了时变灰，下方一句指名道姓的说明
     （差 API Key / 差可用模型 / 服务商不支持），点它不发请求。此前是「跑不了就整个
     不渲染」，用户填好了 key 也只看到一行字，分不清是自己没配对还是功能没做
     —— 这条被连着报回来两次。做法与 `PrimaryAction` 的禁用态一致：不假装可用，
     但把入口和原因都摆在明面上。

### API Key 接上平台安全存储（偏差 #8 落地）

前两条修完之后还剩最后一根刺：密钥只活在会话内存里，**每次重启都要重填**。这正是
规格 M4 第 3 条要求而当时只能如实标注「尚未接入」的那一半，本版补上。

- 引入 `flutter_secure_storage`（iOS / macOS 钥匙串、Android Keystore）。存储收在一个
  `InsightKeyStore` 接口后面，测试用内存替身，平台细节只有一处实现。
- **启动时在 `main()` 里 await 读一次**再交给 provider，而不是让 notifier 自己异步补：
  `Notifier.build()` 必须同步返回，异步补值会留下一个「输入框先空一下」的窗口。
- 写入去重（值没变不重复写钥匙串），**不用防抖 Timer**（会在 widget 测试里留下
  pending timer）；写失败被吞掉且**不记日志**——这一次运行照旧可用，只是下次启动要重填。
- 新增「清除密钥」入口：能存下来就得能删掉。
- **macOS 上刻意关掉 data protection keychain**（`usesDataProtectionKeychain: false`）：
  开着它就必须加 `keychain-access-groups`，而那需要 provisioning profile，插件 README
  写明加了之后**构建产物只能在构建它的那台 Mac 上启动**。本项目不跨应用共享，用不上。
- 规格同步：偏差 #8 改写、M4 第 3 条、§6 依赖表、§9 测试矩阵、README「未实现」表与
  「验证记录」。

**验证**：新增 `test/insight_credentials_test.dart` 6 条；`flutter analyze` 零问题；
`flutter test` **470/470**。另在 macOS 上跑了一次性 `integration_test` 做钥匙串往返
（写 / 读 / 覆盖写 / 删），并用 `security find-generic-password` 确认条目确实进了系统钥匙串，
**再另起一个进程读回同一串值**——「重启后仍在」由此成立。脚本跑完已删。

**一条实测出来的代价，已记进偏差 #8 与 README**：`flutter build macos --debug` 是**临时签名**
（`Signature=adhoc` / `TeamIdentifier=not set`），designated requirement 就是 cdhash，
**每重编一次哈希就变**，于是旧钥匙串条目的 ACL 对不上、下次读会弹一次系统授权框
（点「始终允许」即把新哈希写进 ACL）。已实测确认：用写入时的同一个二进制启动不弹框，
只有「写完之后又重编过」才弹。正常使用遇不到，开发期每次重建会遇到一次。

### 验证

- `dart format .` / `flutter analyze`（零问题）/ `flutter test` **459 项全绿**。
- 新增 3 个测试文件与 2 组 widget 用例；另有活体冒烟（临时脚本，跑完已删）：用真实 key
  打真接口，余额 `¥41.90`、连通性通过、生成返回 `score=82` 与一段中文总结。
- 变异验证：`scoreSource` 退回只看 `isUsable`、连通性判定改成要求非空正文，
  对应用例均变红。

### 设置页新增「清除缓存」（「关于」上方）

**清的是什么，先说清楚**：只清 `getTemporaryDirectory()` 下**可再生成的临时文件**——
白噪音的 8 个 WAV 循环（各约 860 KB，首次播放时合成）与导出时写给系统分享面板的
CSV / JSON 副本。**刻意不碰**三样东西，因为每一样都有自己的去处：睡眠记录 / 数据库与录音
走「删除全部本地数据」，钥匙串里的 API Key 走「清除密钥」。三条清理路径各自只干一件事，
否则用户点「清除缓存」时会以为自己的记录没了。

- 副标题显示**真实占用**；读不到就说「暂时读不到占用」，**绝不显示一个编出来的 `0 B`**
  （那会让人以为已经清干净了）。点完显示「已清除 6.7 MB 缓存。」并变成「暂无缓存」。
- 删除策略是**清空临时目录**，不是按文件名匹配：临时目录存在的前提就是里面的东西都能丢，
  而按前缀列的清单在写入方以后多写一种文件时会悄悄漏掉它。
- 用真实文件系统测真实实现（只把目录换成测试自己建的临时目录）；`FileAppCache` 为此
  留了一个只给测试用的目录注入口。**实测**：macOS 上 8 个 WAV 读出 6.7 MB，清完目录为空。

**未做**：Claude 的对话与余额；余额的持久化与历史曲线；发送前的「将要发送哪些数据」
逐项确认界面（见规格 §7）。

## 3.6（2026-10-03）

**确认弹窗改用 iOS 系统组件 `CupertinoAlertDialog`，推翻偏差 #20 里「不引入 `flutter/cupertino.dart`」的裁定。**

v2.6 起的实现是「按项目令牌自绘的 iOS 风格弹窗」——`showGeneralDialog` + `DecoratedBox` 卡片 +
手画的两条 0.5 发丝分隔线 + 手写转场。当时的理由成立且未变：`CupertinoAlertDialog` 自带系统配色，
会绕过 `AppTokens`，与「设计令牌只有一份」冲突。**这次按用户明确要求以系统组件为准**：布局、模糊
表面、圆角、0.3 分隔线、文字排版与 `1.3 → 1.0` 的弹簧转场全部交给 SDK。

代价如实记——**弹窗底色（半透明 `0xCCF2F2F2` / `0xCC2D2D2D`）、分隔线色（`CupertinoColors.separator`）、
圆角不再来自 `AppTokens`**。能接回令牌的都接回：亮度取 `Theme.of(context).brightness`（不取
`MediaQuery.platformBrightness`，否则外观设成深色时弹窗会是浅底）、`primaryColor → tokens.accent`、
两个动作的 `textStyle.color → accent` / `danger`（`CupertinoDialogAction.textStyle` 在系统色解析
**之后**才 merge，能盖掉写死的 `systemRed`）、蒙层色 `tokens.overlayScrim`。

**行为契约冻结**：`showConfirmDialog` 签名与返回值语义不变，三处调用方（删除记录 / 删除全部本地
数据 / 清除演示数据）一字未改；点蒙层仍可关闭且返回 `false`（系统默认 `barrierDismissible: false`，
这里显式传 `true` 保留原语义）。

`test/confirm_dialog_test.dart` 重写为钉「系统组件特征」，7 条；变异验证：退回自绘实现会让其中
3 条变红，4 条返回语义/按钮次序用例与实现无关、保持绿。

## 3.5（2026-10-03）

**照更新后的原型重排设置页，并补上冷启动的开屏页。**

使用方给出更新后的 Figma Make 原型，指明三处：设置页排版变了、睡眠数据与外观各自收进
二级页、新增开屏页。

### 一条改变了判断的事实：令牌没有变

原型 `index.css` 是分层覆盖的。早期那版「全站扁平原生风」（底色 `#f4f5f8`、`.glass` 不再
模糊/描边/投影、主按钮改纯色）**在最终生效层里又被推翻了**：末层的 `.ios-app .glass` /
`.ios-list-group` / `.primary-action` / `.ios-navigation-back` 都还原成玻璃材质与
`#0A84FF → #5856D6`，`:root` 最终值是 `--bg-base: #f2f2f7` / `#000000`、`--ios-material:
rgba(255,255,255,.66)`——**与 `AppTokens` 逐值一致**。所以本轮**一个新配色都不引入**。
主规格偏差 #32 里「新原型最终生效层把全站换成了扁平原生风」那句前提**据此订正**（它关于
会话页用页面局部常量的结论本身不变）。

### 设置页

根页从「六七个大区块平铺」改成四段导航式列表：**常用**（外观、睡眠设置、罗盘）、
**数据与智能**（睡眠数据导入、睡眠洞察）、**数据与隐私**（睡眠数据导出、删除全部本地数据、
演示数据）、**关于**（从大号居中卡片改成一行，版本号仍取 `PackageInfo`）。每行是
「图标底板 + 两行文案 + 右侧箭头」。

**外观**（`/settings/appearance`）与**睡眠设置**（`/settings/sleep`）是新二级页。外观的选择器
照原型从分段控件换成**行内下拉菜单**；睡眠目标从 ± 步进器换成**自绘滑块**（5–12h、步长 0.5）
加 7/8/9 快捷按钮——那个轨道是 `borderStrong → accent → borderStrong` 的**静态**渐变、
滑块是「3px accent 描边 + 实底填充」，Material `Slider` 的 `activeTrackColor` 口径表达不了。
自绘控件补齐了 `Semantics` 的 slider 动作与 0.5 小时的步长，否则读屏用不了。
**提醒的权限处理、写库与全量重排逻辑一字未改**，只是换了宿主页面。

原型根页没有、但本实现必须保留的四条入口（导出 / 删除全部本地数据 / 演示数据 / 罗盘）
记入偏差 #43；声音检测的副标题**不采用**原型那句「检测打鼾、梦话并生成洞察」（录音仍未接入），
记入偏差 #44。

**外观页的下拉箭头一度没有贴右**（使用方指出，与本版同批修掉）。行内版式没有 flex 子项，
而触发器靠 `minWidth` 撑出一截富余宽度，`Row` 默认左对齐会把这段宽度全留在右边——箭头于是
浮在文字后面、离右端 21.4px 而不是内边距的 12px。修法是行内版式显式
`MainAxisAlignment.spaceBetween`（原型 `.appearance-select-trigger` 的
`justify-content: space-between`）；竖排版式（洞察配置页用的那支）文字由 `Expanded` 吃满，
不受影响。回归：`test/pages_widget_test.dart`「外观页：下拉的箭头贴在触发器右端」量渲染出来的
矩形（已变异验证：改回左对齐报 21.4 ≠ 12）。

### 开屏页

冷启动一屏深蓝渐变 + 月亮 logo 描线 + 星点 + 「夜深 / 听见夜晚，看见睡眠」+ 底部进度条。
**时长定为 1.6 秒**（原型 3.2 秒）——原型那 3.2 秒是网页首屏加载的遮盖，原生应用在它之前
已有系统启动图；压缩办法是总时长对半砍、各元素的出场时刻仍照原型的百分比。原型的星点闪烁 /
光晕脉动 / 轨道环自转都是 `infinite`，这里一律改成在这条时间轴上能跑完的**有限形式**：
循环动画会让 `pumpAndSettle()` 永不收敛，挂真外壳的测试还会留下 pending timer。

收起条件是「时间轴播完 **且** `settings` 已读到第一帧」——只看计时器的话，异步流还没吐值
时外壳会先露出来、引导页随后再盖上去（「闪一下主界面再跳出引导」）。判据取
`AsyncValue.isLoading` 为假，成功与失败都算结论，**刻意不加兜底 Timer**（那会给每个挂真
外壳的测试留下 pending timer）。顺序与时长记入偏差 #41 / #42。iOS 的系统启动图与 web
manifest 底色一并从白 / `#0175C2` 改成开屏底色 `#07102D`，避免冷启动白闪。

顺带清掉死代码：`dur_bar.dart` 只有旧设置页一个调用点，换成滑块后即无人使用（规格 §3 的
映射表已同步删行）。

回归：`test/splash_screen_test.dart`（5 条）、`test/pages_widget_test.dart` 的设置页与二级页
两组（重写）、`test/reminder_settings_test.dart`（9 条，挂载点改到睡眠设置页）。三条新断言
做了变异验证（去掉滑块吸附 / 去掉开屏的 `settings` 条件 / 把诚实副标题换成原型文案，均变红）。
`flutter analyze` 零问题，`flutter test` 423/423 通过。**开屏页在 macOS 上目视核对通过**
（渐变 / 轨道环 / 星点 / logo 与两道声波 / 文案 / 进度条逐项在位）；设置根页与两个新二级页
**未核对**——巡检被系统的「`night_sleep` 想访问『文稿』文件夹」授权框盖住窗口，本机点不掉
系统对话框（这一条也一并记进了 README 的巡检注意点）。

## 3.4（2026-10-03）

**两处宽屏弹层缺陷（使用方在 iPad 横屏实测后提出）。**

1. **助眠音效弹窗的音效格按屏幕宽度算宽**（`noise_sheet.dart`）。格子宽度取的是
   `MediaQuery.sizeOf(context).width`，而面板在 ≥640px 时被 `_SheetHost` 限到 560px：
   iPad 横屏（1194）下每格被算成 271px，`Wrap` 一行只放得下一个，内容整体溢出 217px
   并被 `ClipRRect` 裁掉——音量条与定时 chips 完全够不着，看得见的只有一排巨格。
   改成按**面板自身**的可用宽度算（`LayoutBuilder`），并让面板内容在装不下时滚动
   （iPhone 横屏、iPad 分屏同理）。**格子公式与手机上的取值逐像素一致**（430 宽仍是 80px）。

2. **偏差 #40：底部弹层的宽屏浮起作废**。原型那条「宽屏浮起 24px、四角 26px」是桌面
   浏览器的规则，照搬到 iPad 横屏上会在面板下缘留出一条遮罩、且下沿是方角断面，面板
   看起来悬空断在屏幕底之上（使用方实测后裁定一律贴底）。现在**下沿一律贴屏幕底、只圆
   上方两角**，宽屏仍限宽 560px——iPhone / iPad / macOS 一致。规格 §2.2 与第 8 章 #40
   已同步。

回归：`test/noise_sheet_test.dart`「宽屏下面板限宽，八格仍是四列两行且不溢出」、
`test/app_sheet_test.dart`「宽屏下面板限宽 560，但下沿仍贴屏幕底」，两条都做了变异验证
（换回屏幕宽度算宽 / 把浮起加回去，分别报 1 行 8 格与 810 ≠ 834）。

## 3.3（2026-10-03）

**会话页补齐原型的另一半：入睡前（setup）态。记录起点随之从首页那颗按钮挪进页内。**

原型 `SleepView` 一直有 setup / active 两个分支，v3.2 只做了进行中那一半，并把 setup 态承担
的能力判给首页。这一版推翻那条裁定：**首页「开始入睡」只推入页面、什么都不写**，页内那颗
「开始睡眠」才写会话行——`startAtUtc` 就是按下的那一刻。于是「点进来看一眼又退出」不再留下
一段并不存在的睡眠。v3.2 的「没有正在进行的睡眠」空状态随之删除（没有会话 = 入睡前态）。

**入睡前那一屏**照原型最终生效层重建：晚安 / 准备好休息了吗？ / 放下今天，让夜晚慢下来。/
月亮轨道 102 / 夜景氛围选择器（多一行标题「左右滑动切换」）/ 常用白噪音四格（雨声·海浪·
棕噪音·风扇，点选即试听）/ 白噪音·起床闹钟·鼾声检测三行 / 「开始睡眠」渐变按钮 /「屏幕将
保持暗色，轻触夜景即可切换氛围」。**这一屏什么都不写库**：场景、闹钟开关与时刻都只是草稿，
收起再进来就回到初值；闹钟开关在拨动当场过通知权限闸口，被拒则回弹、给说明，但不拦着
开始这一晚。

**进行中那一屏照原型收紧为只回显**（偏差 #29 / #30 **撤销**）：没在放白噪音就没有白噪音行、
闹钟关着就没有闹钟行，两行都不再可点——睡前设定都在入睡前那一屏做完了。鼾声行保留开关
（#31 不变），闹钟行的副标题与投递强度标注原样保留。唯一比原型多的地方：**已经睡过头时，
即使没设闹钟也渲染那一行**——那句「已超过起床时间 · 请手动结束睡眠」是这一屏唯一会告诉
睡过头的人怎么做的话，因为没设闹钟就把它一起藏掉是能力倒退。

**新增偏差 #35–#38**：入睡前态的鼾声副标题沿用「尚未接入录音，开关只保存偏好。」（原型那句
宣称的识别能力并不存在）；两个默认值（鼾声、闹钟）不照原型抄（默认关，时刻取设置里的起床
提醒）；四格点选即试听（控制器只有「选中并正在播放」这一种语义）；播放时长仍没有「整晚」。
**#39** 记的是这一轮的核心改动：首页按钮只进页面——它不算偏离原型，是**回到原型**。

**顺手修掉两处照抄错层与一个既有缺陷**：场景卡选中态在最终生效层是 `transform: scale(.98)`
（早期那层 `translateY(-2px)` 被它覆盖，v3.2 抄错了），注意 CSS 绕中心缩放而 Flutter 的
`Container.transform` 绕左上角，`transformAlignment` 必须显式给；两态内容都居中限宽 680
（`min(100%, 680px)`，v3.2 漏了）；`AppDatabase.getSettings()` 的「先读后插」在并发首读时会撞
`UNIQUE constraint failed: app_settings.id`——入睡前态一帧里有两个读者，稳定触发，改成
`InsertMode.insertOrIgnore` 并加了回归。

两个断点也照**最终生效层**的媒体查询做了：窄屏（`max-width: 390px`）deck 的行内边距收到 13、
常用白噪音四格改竖排；高屏（`min-height: 860px`）hero 从 230 撑到 285。这两条是执行期最后
一遍核对原型 CSS 时才发现的——它们与上面那些规则同在那一层里，不能因为是媒体查询就跳过。

测试 413 条通过（v3.2 的 400 之后净增 13）；新增断言逐条做了变异验证。入睡前那一屏也在
macOS 上（真实 Impeller/Metal 引擎，约 412×890pt 的窗口）目视看过一次：一屏内装得下、
日志无异常与 overflow，deck 的模糊滤镜在真实引擎上没报错（证据：那一次的窗口截图）。
**没有重跑构建**，**iOS 真机/模拟器没看**，**巡检脚本改了但没跑过 `flutter drive`**——
后两条记在 README「验证记录」的未验证项里。

**同日补记：白噪音在 macOS 上放不出声——两处缺陷，都不是这一版引入的。**

在 macOS 上点「风扇」当场报 `无法生成音频：PathNotFoundException … errno = 2`。查下来是**两处
叠在一起**，且**都不是这一版的改动**——这条路径此前**从来没有被真正走过**：widget 测试用的是
假播放器，巡检只开弹窗、从不选声音，于是它从第一次提交起就是坏的。

1. **临时目录不建就写。** `getTemporaryDirectory()` 在 macOS 上返回
   `~/Library/Caches/<bundle id>`，而 `path_provider_foundation` 2.6.0 只保证
   `getApplicationSupportDirectory()` / `getApplicationCacheDirectory()` 会顺手建目录，
   **temp 这一支不建**（实测：返回时 `exists=false`，报错里那个路径就是它）。`_ensureFile`
   直接往里写就是 ENOENT。修法是写前 `directory.create(recursive: true)`——
   `export_sharer.dart` 里那次临时目录写入本来就带着这一行，所以导出一直没事。
2. **`await _audio.play()` 是死等。** `AudioPlayer.play()` 的 Future 要等「播放结束或被
   暂停/停止」才完成（`just_audio` 的公开契约，darwin 侧由 `pause:` / `complete` 兑现），
   而这里循环的是一个 20 秒的源，永远不会结束。实测 macOS 上 await 之后 6 秒仍不返回
   （此时 `playing=true`、`ProcessingState.ready`，声音早就出来了），一直等到 `stop()` 才放行。
   代价不只是慢：`_current` 永远赋不上、界面停在「没选中」；等用户点「关闭」把它放行，它
   反倒把状态翻成「正在播放」——一条彻头彻尾的假状态。改成起播请求发出即算数（`unawaited`），
   把「起播请求本身被拒绝」的错接到 `debugPrint`；真正能报给用户的失败仍在 `_ensureFile` 与
   `setFilePath` 那两步。**音频会话激活失败这一类 `just_audio` 自己会吞掉**（并让那个 Future
   永不完成），这里看不见，如实记在会话规格 §十三。

两处都用**同一条真机用例**钉住并做了正反对照：新增 `integration_test/noise_playback_test.dart`
（真合成 → 真落盘 → 真起播，音量 0 不出声），在 macOS 上 `flutter drive` 跑到 `All tests
passed`；去掉「建目录」那一行、并清掉缓存目录后，同一条用例报的正是用户截图里那句
`PathNotFoundException`。巡检脚本也补了一步**真的选中一个音**（`session-noise-play`），
并在失败文案出现时打印出来——它此前只开弹窗、从不选声音，等于这条路径一次都没走过。

**巡检这一轮跑了两次都没跑完，两次都记在 README「验证记录」里**：第一次是这一步自己写错了
（`find.text('风扇')` 会同时命中弹窗与底下那一屏的四格，`Too many elements`），改成用
`GridView` 限定范围；第二次跑到一半机器自动锁屏——锁屏后 Flutter 不产帧，每一步都在推帧的
巡检随即停摆。因此**巡检全趟通过仍未验证**，与 v3.0 / v3.2 / v3.3 那几条同类；顺带把
「跑巡检前先 `caffeinate -d`」写进了 README 的注意点。

**同日补记：iOS 工程随 Xcode 升到新格式，真机签名已配好（构建/工具链，非产品能力）。**

在 Xcode 里配开发团队时，工程被一并升级：`objectVersion` 54 → 60、`LastUpgradeCheck`
1510 → 1620，`Runner.xcscheme` 与 `Main.storyboard` 换成新版格式（storyboard 只重排了
XML，渲染结果不变）。新增 `DEVELOPMENT_TEAM = UK9L3XHV39`。**Xcode 顺手做了两处本意之外
的改动，已还原**：三处配置列表的默认配置被从 `Release` 改成 `Profile`（改回 `Release`），
并生成了一个空的 `Runner.entitlements`（连同 `CODE_SIGN_ENTITLEMENTS` 一起删除——空
entitlements 不挂任何能力，留着只会误导）。钥匙串里现有
`Apple Development: 1661287843@qq.com` 证书、Xcode 已登录该 Apple ID，README 的
「真机安装」及相关两处据此改写。**真机安装本身仍未实测。** 工程已是非旧版格式，
**旧版 Xcode 打不开**。

## 3.2（2026-10-02）

会话页按新原型（Figma Make 的 `SleepView`「睡眠进行中」态）重建。**范围只到这一页**：
新原型的最终生效层同时把全站换成了扁平原生风，那部分本轮**不做**（见偏差 #32）。

**整页换成夜景。** 底色是八种场景之一的暗色渐变 + 一层 67px 网点质感，上面浮着场景动画：
流星、极光、海浪、云层、萤火、银河、雨丝、星点闪烁，参数逐条抄自原型的 `@keyframes`。
八套动画由**一个** 60 秒循环的 `AnimationController` 驱动、全部画在一个 `CustomPaint` 里
——不给 34 颗星、18 条雨丝各建一个 widget。系统开了「减弱动态效果」时停表，只留静态层。
选中的场景写进会话行（schema v5 加 `active_sessions.scene_id`），收起页面再进来、
杀掉应用重开都还是同一个夜景。

**流星不只属于「流星夜」。** 原型的 `.sleep-meteors` 只在 aurora / ocean / cloud / firefly /
rain 五个场景被 `display: none`，所以 **`meteor` / `moon` / `galaxy` 三个场景都有流星**——月海
与银河是在底色 + 光晕之上再叠一层。规格 §16.3 的元素表原来只写了「流星夜」，本版一并**订正**。

**中央读数换了一套。** 日晷圆环（已过 ÷ 计划）换成月亮 + 当前时刻 + `HH:MM:SS` 秒表 +
「已进入睡眠模式」。秒表的小时不封顶——回绕会把「忘了结束、放了两天」藏成一个正常的
00:00。「已超过起床时间」不再单独一行，挪进起床闹钟那一行的副标题，口径仍只由模型出。

**中段并成一张「当前睡眠事件」卡**：开始睡眠 / 白噪音 / 起床闹钟 / 鼾声检测四行。
白噪音的完整设置（八宫格 + 音量 + 定时）从页内展开区改成**深色底部弹窗**，
点白噪音那一行打开；关掉弹窗、收起页面、离开会话页都继续响，这条生命周期一字未改。
事件卡**只有两态**——白噪音行是「未开启 / 播放中」，刻意不做原型那个「已停止」态：控制器的
`noiseId` 语义就是「选中**并正在播放**」（冷启动对账靠这条语义清掉假值），「播完」与「从未
选过」在界面上本就不可区分。事件卡也**不叠 `backdrop-filter`**（原型激活态有 `blur(18px)`）：
底下是每帧重绘的整屏动画，卡片上再叠一层会让该区域每帧重新模糊，而这一页要整夜挂着，
代价不划算。两处都写进偏差表（#33 / #34）。

**结束按钮从圆形改成全宽横向胶囊**，按下时填充条自左向右扫过。**按住时长仍是 1.5 秒**
（原型 1.6 秒，那 0.1 秒是 v3.1 的产品裁定）；按下即开始、松手未满取消、手指滑开作废、
短按只提示这些语义一条没动。

**顺带修了一处会「悄悄失效」的误触守卫。** 长按的 1.5 秒由 `AnimationController` 计时，
而 `AnimationBehavior.normal`（旧实现与 v3.1 的圆形按钮都是它）在系统开启「减弱动态效果」时
会把时长乘 0.05——**1.5 秒塌成 75ms，误触守卫等于不存在**，且填充条瞬间满格、失效还不可见。
现改用 `AnimationBehavior.preserve` 免疫（这条时长是承载语义的功能性反馈，不是装饰动画）。
回归见 `test/hold_to_finish_button_test.dart` 的「开启减弱动态效果时，1.5 秒守卫仍按真实时长计时」。

**会话页从此常暗**：整页包在 `Theme(AppTheme.dark())` 里，浅色主题下进去也是深色
（原型的睡眠模式就是这么设计的）。**共享组件不抄第二份色值**：页内的白噪音宫格 / 音量条 /
时长 chip / `IosToggle` 从 `AppTokens` 取深色值。**但白噪音弹窗得自己再包一层**——它走
`showGeneralDialog`，路由默认挂在 **root navigator** 下，**继承不到**会话页那层
`Theme(AppTheme.dark())`；于是弹窗的 `pageBuilder` 里显式再包一层深色 Theme，否则浅色应用主题下
弹窗外框是深的（走 `NightStyle`）、里面的共享控件却是浅的，深浅拼在一张面板上（回归用例：
浅色主题下推起弹窗，断言弹窗内 `Theme.of(context).brightness` 仍是 `dark`）。**已知不一致**：
时长越界说明层（`_RejectedSheet`）与评星弹窗仍走 `AppSheet`、取应用主题，所以浅色主题下这两块
仍是浅色面板；本轮刻意不动（`AppSheet` 的外观是共享组件的职责，改它等于给全站换肤），见规格 §十三。

**刻意保留、与原型不同的五处**（偏差 #28–#32）：「收起」入口、白噪音行常驻可点、
起床闹钟的开关与时刻编辑、鼾声行放开关而不是「正在聆听」的状态点、
这一页用页面局部的 `NightStyle` 而不是改 `AppTokens`。

`WakeDial` 与另外两个只服务旧版式的文件（`session_settings_section.dart`、
`session_noise_section.dart`）随之删除。数据语义一个没动：空状态、时长守门 `(0, 24h]`
不落库、就地评星、丢弃、闹钟重排全部原样。

## 3.1（2026-10-02）

会话页按使用方要求重排，并参考潮汐那类助眠应用的「按住起床」手感。

**结束方式改了。** 「结束睡眠」从页面底部的玻璃长条改成**圆环正下方的圆形按钮**：按住不放、
外圈进度环顺时针扫满 1.5 秒才生效；中途松手或手指滑开即作废，短按只给一句提示与轻震动。
进度**按下即开始**（用原始指针事件驱动，不走 `onLongPressStart` 的 500ms 超时），因此按住时
立刻有反馈。原规格里那句「结束会话只有『结束睡眠』一个入口，避免误触」的目的不变，手段由
「藏起来」换成「按住才生效」。

**两个设定开关从抽屉里搬出来常驻。** 起床闹钟与鼾声/梦话记录现在就在结束按钮下方，不再需要
先展开面板；原先收合态那个闹钟胶囊承担的三条信息（剩余时间、已关提示、投递强度标注）全部并进
「起床闹钟」这一行，同一件事只留一处显示。鼾声那一行的「尚未接入录音，开关只保存偏好」一字未改
（偏差 #7 仍然有效）。白噪音区（八宫格 + 音量 + 定时 + 后台播放限制说明）改为点摘要条展开，
带 `AnimatedSize` 高度动画，箭头旋转；**展开时圆环、结束按钮与常驻开关都不动**（旧版展开即藏起
圆环）。`SessionDrawer` 随之拆成 `SessionSettingsSection` 与 `SessionNoiseSection`。

**展开后自动滚进视野。** 摘要条本来就在页面底部，展开区又在它下方——第一轮实现点了「更多」
只看到箭头翻了个面，内容整块在屏幕外（模拟器上目视实测：定时那排 chip 落在 1112.5，屏幕高 932）。
现在等高度动画走完再 `animateTo(maxScrollExtent)`。这条是**目视验证抓出来的**：默认那块 2000 高的
测试视口把整页一次渲染完，widget 测试根本看不见屏幕外的问题；新的回归用例因此必须传真实手机尺寸
（`pumpSession(size:)`），摘掉 `_revealNoise()` 会让它变红（已变异验证）。

**会话页补进常驻界面巡检**（`integration_test/app_screens_test.dart`）：收合态、按住时的进度环、
展开的白噪音区、按住到底后的评星弹层。踩到的坑记在 README——集成测试的 live binding 里动画只在
推帧时前进，`Future.delayed` 等不出进度。

顺带修了巡检**两步既有的连带失守**：`goBack` 在没有上一页时调裸 `pop()`，把最后一页弹掉，
go_router 随即断言 `currentConfiguration.isNotEmpty` 并弄坏整棵树，后面每一步都报「找不到」。
现在改成 `popUntil(isFirst)` + `goHome`，一步失败只赔一步。会话页那几步因此放在首页步骤之后
（趁状态干净时走）——末尾按住结束会话，首页也就还原了。

不变量一个没动：空状态、时长守门 `(0, 24h]` 不落库、就地评星、丢弃、收起、白噪音生命周期
（收起展开区乃至离开会话页都继续响）。回归测试见 `test/sleep_session_page_test.dart`（新增
「没按满就松手不结束会话」「短按结束按钮只给提示」「展开白噪音区会自动把它滚进视野」三条）
与 `test/hold_to_finish_button_test.dart`。

## 3.0（2026-09-30）

睡前那一刻是唯一还带着真实信息的时刻。这一版把**采集起点**从「早晨回忆」挪到「睡前按一下」：
新增「开始睡眠」与会话页；「记录」Tab 改为「回顾」Tab（醒来后补感受）；手动录入降级为二级页；
起床闹钟接真实本地通知；应用显示名统一为「夜深」。对应规格 schema **v3 → v4**、偏差 #23–#27。

**显示名。** iOS / macOS / Web 三处都**配置**为「夜深」（`CFBundleDisplayName` / `title` /
manifest）。`PRODUCT_NAME` 与 `CFBundleName` 保持 `night_sleep` 不动——它们决定 macOS 的
`.app` 包名与可执行文件名，改成中文会把构建产物路径也变成中文。**Dock 与 iOS 桌面读的是
`CFBundleDisplayName`（已改）；macOS 菜单栏读的是 `CFBundleName`（仍为 `night_sleep`），
可能仍显示英文名，待人工核对。** 回归见 `test/app_display_name_test.dart`（5 条，含「构建路径
相关的名字仍是 `night_sleep`」的反向护栏）。

**会话。** 首页「开始睡眠」→ 推入式全屏会话页（`/sleep/session`）。日晷圆环画「已过时长 ÷
计划时长」，两个数都来自用户自己按下的时刻与设定的闹钟——**它不测量任何东西**。会话状态进新的
**单行表** `ActiveSessions`（主键固定 `'active'`，于是「同时两个会话」在结构上不可能），跨重启
存活。结束时**一个事务**里写记录（`source = 'session'`）并删会话行，就地评一次星（可跳过 =
质量留空）；时长不在 `(0, 24h]` 内**不落库**，让用户选手动补录或丢弃。白噪音（八宫格 + 音量 +
定时 15/30/45/60）的播放器提到了 **app 级**——收起抽屉乃至离开会话页都继续响。

**回顾。** `AppTab.log` 的 id 不变、label 从「记录」改为「回顾」：对最近一条**真实**记录补充
主观感受，记录头可点开选择器换一晚，**不改起止时刻**。手动录入降级为 `/log/new`（入口在回顾页
底部）——能力没消失，只是不再占标签位。**顺带修掉一处旧的默认值**：表单不再默认选中「良好」，
不选就不写质量（偏差 #26）。这需要把 `SleepRecords.quality` 改为**可空**，即 schema v4 的
`alterTable` 重建 `sleep_records`（本项目第一次重建一张有子表引用它的表，迁移后外键级联由测试
钉住）。

**起床闹钟。** 新 id `9003`，`scheduleOnce` **一次性**排定（不传 `matchDateTimeComponents`，
与每天重复的日常提醒是不同 API）。会话活跃且闹钟开启时**日常起床提醒 `9002` 让位**（就寝提醒
`9001` 不受影响），会话结束后按偏好排回；推导只有 `syncSessionAlarm` 一处，且**调度器
没就绪（`permission()` 为 `unsupported`）时不排 9003**，免得界面写着「已开」却不会响。
iOS / macOS **请求** `interruptionLevel: timeSensitive`（**但工程里没有配套的 Time Sensitive
Notifications entitlement，按当前产物该级别会被系统降级、穿不了专注模式**），Android 用
`inexactAllowWhileIdle`（刻意不申请精确闹钟权限、不用需 Apple 特批的 `critical`）。界面如实
标注「由系统通知投递；休眠模式下可能晚几分钟，强度不如系统闹钟」——收合态胶囊与抽屉里的闹钟
行共用同一份字面量。

**两处诚实的边界（不得当成已完成）：**

1. **会话不测量任何东西。** 没有阶段、没有鼾声判定、没有质量推断——两个时刻来自按钮，起床
   时间来自设定。会话产生的记录与手动记录一样，**没有睡眠阶段**。
2. **录音仍未接入，开关只存偏好。** 「鼾声/梦话记录」在设置页与会话页写的是同一个字段
   （`AppSettings.soundRecordingEnabled`，会话表刻意没有同名列），但**录音本身没有实现**，
   界面仍如实标注「尚未接入录音，开关只保存偏好」（偏差 #7 在夜间录音落地前仍然有效）。
   夜间录音（以及它需要的麦克风权限、后台录音、切片）排成独立的 plan B。

**未验证**（详见 README「验证记录」）：起床闹钟**真机到点投递**未实测；`timeSensitive`
因缺 Time Sensitive Notifications entitlement，**当前并不能穿透专注模式**（需加 entitlement
并在 App ID 上开启该能力）；宽屏（macOS 侧边栏）下的会话页/回顾页版式未经核对；Dock / 桌面
显示名的实际观感未确认，且 **macOS 菜单栏可能仍显示 `night_sleep`**；`integration_test/` 的
「记录 → 回顾」改名**没有跑过 `flutter drive`**（该目录不参与 `flutter test`）。

回归方法：`test/app_display_name_test.dart`（显示名）、`test/schema_migration_test.dart`
（v3→v4）、`test/session_repository_test.dart` / `test/sleep_session_test.dart`（会话领域与
仓库）、`test/sleep_session_page_test.dart`（会话页）、`test/review_page_test.dart`（回顾页）、
`test/reminder_scheduler_test.dart` / `test/reminder_sync_test.dart`（起床闹钟）。合并前的
最后一遍 `flutter test` **337/337 通过**，`flutter analyze` **No issues found**。

## 2.9（2026-09-29）

用户实机上报：**macOS Dock 里的图标是直角方块，没有圆角**。查下来不是「图标没做」——图标文件、
资源目录、Xcode 的 `ASSETCATALOG_COMPILER_APPICON_NAME` 全都对——而是规格里一条**错了的前提**：
`assets/branding/app-icon.svg` 的注释与偏差表 #16 都写着「去掉原图的 `rx="236"`，因为 **iOS 和
macOS** 都会自己套遮罩」。**macOS 不会。**

证据是把系统 app 的 `.icns` 抠出来量：Calculator 与 Notes 结果完全一致，`alpha>128` 的实体恰为
206/256 = **0.8047**，即 Apple 图标网格的 824/1024，且四边留白全等（25/256）。也就是说**圆角与
留白是烘焙在图标文件里的**，macOS 只负责原样绘制。两个平台此前吃同一批满幅直角像素：iOS 拿过去
套遮罩，正常；macOS 拿过去原样画，于是撑成一个方块。

因此生成拆成**两条渲染路径**（`iosIcons` / `macosIcons` 两张尺寸表本来就分开，改动只落在 macOS
分支）：iOS 一个字节不动；macOS 按 Apple 网格烘焙圆角与留白（实体 824×824 居中、四边留白 100、
半径 185.4）并加一层向下偏移的投影。落地的关键一处是**编码器**——原有的 `encodeOpaquePng` 写的是
PNG 色型 2（RGB，无 alpha），会把刚画出来的圆角透明直接抹掉；macOS 这条路改走新增的色型 6（RGBA）
编码器，`_resample` 也不能再画在不透明黑底上（否则四角被填黑）。「压掉 alpha」是针对 **iOS 提交**
的规则（App Store 拒收带 alpha 的应用图标），macOS 的圆角图标**必须有** alpha——两条规则分平台。

回归方法：独立资产断言 `test/app_icons_asset_test.dart`（4 条）——实体**自身**四角透明、中心不透明、
`alpha>128` 的实体包围盒 = 824×824 且四边留白 100、iOS 图标仍满幅且无 alpha 通道。

**已验证（2026-09-29）**：`test/app_icons_asset_test.dart` 4 条全绿，跑在普通 `flutter test` 里
（规格原写「断言随生成器放 `tool/`」——生成器不参与 `flutter test`，那样只在手动重生成时才执行，
已改为独立的资产断言）。变异验证起初**没咬住**：只断言画布角 `(0,0)` 与包围盒时，摘掉
`_rasteriseMacos` 的 `clipRRect` 后测试仍全绿——因为实体被内缩到 824×824 后画布角量到的本来就是
留白，而包围盒由最宽的那一行决定、圆角削的是四角。补上「实体自身四角透明 + 左边缘**内侧**中点
（`left + 1`，因为正好压在边界上的那一列带抗锯齿、1024 上实测 alpha 244）不透明（反向护栏）」后
重跑：注释掉 `clipRRect` 再重新生成，`macOS 1024` 与 `macOS 256` 两条立刻变红
（实体左上角 alpha 由 0 变 227 / 255），其余两条不动。恢复 `clipRRect` 后产物与变异体在 7 个
macOS PNG 中有 6 个不同（32/64/128/256/512/1024）；16px 上两者**逐字节相同**——那个尺寸下实体
已小到圆角被重采样糊平（四角实测 alpha 255），摘与不摘 clip 不改变任何像素。已确认恢复干净。
iOS 产物经 `git status --short ios/` 确认**逐字节未变**（15 张，色型仍是 2）。

**修复波（2026-09-29，终审后）**：终审发现 `_writeAll` 取的是 `ui.ImageByteFormat.rawRgba`，而它
返回**预乘** alpha；PNG 色型 6 规范要求**直乘**，于是渲染时 alpha 被乘第二次——所有半透明像素
（烘焙出的圆角轮廓、投影软边，正是这次改动的意义所在）都被压暗，alpha 越低越暗。已改为
`rawStraightRgba` 并重新生成：`(100,512)`（α244）由 `(84,163,231)` 变为 `(88,170,241)`，恰等于
原值除以 244/255，三通道比值一致，证明预乘已消除；`(99,512)`（α72）由 `(5,10,14)` 变为
`(18,35,50)`，可见越透明被压得越狠。iOS 路径整幅 alpha=255、两种格式等价，产物**逐字节未变**。
本波同时把资产断言从 4 条补到 **5 条**（新增：七个尺寸的文件名↔真实像素尺寸绑定、实体宽随尺寸等比、
实体下方投影存在、圆角半径带宽；已做变异验证——半径改 60 或删掉投影，新断言都会变红），并订正了
本文档与规格里两处与实物不符的措辞（「全部 7 个 PNG 都不同」应为 6 个；护栏取点是 `left + 1`
而非「左边缘中点」）。

**已知项**：Apple 在新系统上改了应用图标体系（改由系统套新遮罩），届时烘焙圆角有被二次遮罩的可能。
当前基线是 macOS 14，升级系统后需回头复核——这条留在偏差 #16，不当作已解决。

## 2.8（2026-09-29）

用户实机要求：**底部也加一条轻微的渐变模糊带**，让滚到标签条附近的内容糊掉。原型没有这个元素
（源文件未入库，无法核实；用户确认原型没有），因此计入偏差表 #22。

新增 `core/widgets/bottom_fade.dart` 的 `BottomFade`，是 `top_fade.dart` 的镜像，但**常驻**
（没有 `visible`，没有淡入淡出）。高度不写死：由 `AppShell` 按 `tabBarReserve(context) + 20` 推出
后传入（iPhone 16 Pro 上 121pt），标签条的浮起量再变时带子自动跟走。填充是 `bgBase` 从顶边 0
升到底边 78%，`blur(14)` 与顶部带同半径。

三处容易做反的地方在这次都被断言钉住了：**渐变整体要反向**（照抄顶部带会画出「上重下轻」的逆向带
且不报任何错）、**带子在 `Stack` 里排在 `_TabBar` 之前**（`BackdropFilter` 模糊的是它之前画好的
画面，排在后面会把玻璃胶囊自己糊掉）、**遮罩必须套在 `BackdropFilter` 外面**（套在里面只淡化填充、
模糊留一条硬边，顶部带犯过这个错）。回归方法：`test/bottom_fade_test.dart`，三种破坏各让对应用例
变红（已变异验证）。

**已知取舍**：带子画在胶囊之下，胶囊的 backdrop 会看到被洗过一遍的内容（有效 alpha 从胶囊顶边约
0.13 升到底边约 0.71），胶囊下半部因此比过去更「实」。这是本轮唯一靠断言判断不了的一项，需人工核对。
**已核对（2026-09-29，iPhone 16 Pro 模拟器）**：带子顶边（离屏幕底 121pt）无硬边、方向为「下重上轻」
（越靠屏底越实）、胶囊下半部未发闷。**覆盖面**：浅色看过首页（滚动后）/ 统计页 / 详情与助眠音效弹层，
**深色仅首页静置态**，未逐页逐屏核对；深色帧是把 `app_settings.theme_mode` 临时改为 dark 后截取，
截完已还原为 light。证据图见 `screenshots/v2.8-*.png`。

## 2.7（2026-09-29）

用户实机上报：**底部标签条离屏幕底边的间距偏大**。根因是浮起量照搬原型的
`bottom: max(12px, env(safe-area-inset-bottom))`：安全区底部那 34px 是留给系统手势的**整块**
空间，而 home indicator 本身只画在底部 8–13px，于是玻璃胶囊平白悬空一大截。改为
`max(12px, 安全区底部 − 14px)`（`app_shell.dart` 的 `tabBarFloat`）：iPhone 带 home indicator
时 34pt → **20pt**，胶囊底边仍高于指示条约 7pt；macOS / Web 等无安全区处仍是 12pt。

顺带拆掉同一处的一个隐患：浮起量此前在 `tabBarReserve`（页面底部留白）与 `_TabBar`
（胶囊实际位置）**各算了一遍**，单改一侧就会让最后一行压进玻璃、或让玻璃上方空出一条；
现在一处出、两处共用。改动还暴露了 `_tabBarHeight` 比实物多算 0.5px——`Border.all(width: 0.5)`
只贡献 1px，不是注释里写的「0.5 顶边 + 1 底边」，已按**实测渲染高度 65px** 订正。
回归方法：`test/tab_bar_inset_test.dart` 量渲染出来的胶囊矩形（把 `_tabBarFloatRelief`
归零必红，已变异验证）。

## 2.6（2026-09-29）

用户实机巡检上报 6 条，逐条定位根因后修复。**下面写的是「为什么坏」，不是「改了什么」**——
其中一条暴露了数据库在 v2 就留下的静默损坏，v3 的迁移会把它一并修好。

① **顶部渐变与状态栏之间有一条硬分界**。根因是 `app.dart` 的 `SafeArea(bottom: false)`
把整个外壳（连同 `TopFade`）下移了 `safeTop`，而 `TopFade` 全文不读 `MediaQuery`、
不知道安全区的存在；带内填充的第一个停点是满值 92% alpha，起点正好落在安全区下沿。
于是状态栏那段 `[0, safeTop]` 既无填充也无模糊，边界处出现 `0 → 0.92` 的硬跳变。
改为**外壳去掉顶部安全区缩进**，状态栏留白由各页滚动视图按新接口 `pageTopInset` 施加，
渐变带原点回到屏幕物理顶端。顺带补上规格要求、此前缺失的 `saturate(125%)`
（`ImageFilter` 没有内置的 saturate 构造器，本轮用 `alpha 0.04` 的 accent 叠加层近似；
也可用 `ColorFilter.matrix` 自行构造饱和度矩阵，经 `ImageFilter.compose` 与 blur 合成）与 320ms 时长。

② **清除演示数据后点「重新安装」毫无反应**（最严重）。根因有两层。数据层：
`Insights.recordId` **没有外键**（对照 stages/clips 都有 `ON DELETE CASCADE`），
`deleteDemoData()` 只删记录，洞察被留下成孤儿行；重装时 insights 用普通 `insert`、
id 是固定的 `demo-N-insight`，必然主键冲突，而异常从一个没有 handler 的事务里抛出，
`demo_data_page` 的 `onTap` 没有 try/catch → 界面零反馈。交互层：清除后的 provider 重载窗口里，
`demoCount` 仍读到旧值，安装行 `onTap` 仍是 `null`，而 `IosListItem` 在 `onTap == null` 时
**根本不创建 `GestureDetector`**，点击被彻底吞掉。修补：**给 `Insights` 补外键级联，
schema v3**；`DemoSeed.install` 四条写入路径全部改成 upsert（幂等才是根治）；
安装/清除加 try/catch + 页内反馈 + 忙碌态。**schema v3 的迁移会先删孤儿行、再重建
`insights`，因此自动修好用户那份已损坏的模拟器库**（`records=0 / insights=5`）——
正是它让冷启动在 `runApp` 之前抛异常。同一轮给冷启动的播种加了兜底：失败只记日志、
不再让应用死在 `runApp` 之前。

③ **设置页「关于」卡片文字没有居中，且版本号写死**。根因不是 `textAlign`：
`GlassSurface` 内部是个 `Stack`（默认 `StackFit.loose`），非 `Positioned` 的子项拿到宽松约束，
`Column` 于是收缩到最宽的「睡眠记录与分析」（约 98px），再被 `Stack` 的 `topStart` 贴到左边
——`crossAxisAlignment: center` 只在那个窄列内部起作用。这是 CLAUDE.md 记的
「`Stack`(loose) 按最大非 position 子项定尺寸」坑的又一实例。另发现版本号硬编码
`'v2.0.0'`，与 `pubspec.yaml` 的 `0.1.0+1` 对不上，改为读 `package_info_plus` 的真实构建值。

④ **导入页按钮上方一根白线 + 点击毫无反应**。白线**不在按钮上方的空隙里，而是按钮自身
1px 的顶边内高光**（像素级采样定位）——它是给启用态走的镜面高光，而全项目 3 处
`PrimaryAction` 只有这一处是禁用的。点击无反应的根因是 `onTap: null`，
`Pressable` 会把 `onTapDown/Cancel/Up/Tap` 四个回调**全部置 null**。改为可选地把
禁用外观与可点击拆开：高光/投影/触觉收进启用态，禁用态仍接住手势并在**页内**给出说明
（不能用全局 toast——二级页 push 在外壳之上，会被盖住）。

⑤ **删除图标与确认弹窗**（改动请求，**推翻规格偏差 #12**）。应用自身已经自相矛盾：
「删除记录」严格遵守 #12（纯文字、无图标），「删除全部数据」却借了播放控制的
**「停止」方块**凑数，语义完全对不上——用户看到的「风格不搭」正是这个矛盾。改为两处都用
**自绘的垃圾桶**。同时把应用内**三处**危险操作统一到**按令牌自绘的 iOS 风格确认弹窗**
（不引入 `flutter/cupertino.dart`，它自带系统配色、会绕过 `AppTokens`）；
第三处「清除演示数据」此前**根本没有二次确认，点一下就删**。偏差 #12 随之修订，新增偏差 #20。
（**后续变更**：v3.6 起确认弹窗改用系统 `CupertinoAlertDialog`，本条的「按令牌自绘」裁定被推翻，
见 3.6 条目与偏差 #20 现行版本。）

⑥ **深色模式下记录页的事件图标看不见**。根因是四个调用点漏传 `color:`，
`AppIcons.glyph` 退回硬编码的黑色，而该值被**文本替换进 SVG 的 `stroke`** 再交给
`SvgPicture.string`——颜色在构造那一刻就烤进去了，外面那圈 `IconTheme.merge` **从未起作用**
（`SvgPicture` 不读 `IconTheme`），选中/未选中两态都是黑的。改为把颜色真正传下去，
并**加**一条断言（`assert(color != null)`）：debug 下漏传即炸，让同类疏漏不再静默——**release 下
仍退回黑色**（`color ?? const Color(0xFF000000)` 保留着，与本轮修复前的行为一致）。

改动同步进规格（§2.2、§2.3、§5.1、§8 偏差 #12/#20、§9 测试矩阵）、`README.md`
（实现范围 / 验证记录）与 `CLAUDE.md`（schema v3）。**未验证项**（含本轮新增的
`package_info_plus` 真机取值、以及本轮多数界面改动未经目视）记在 README「验证记录」。

**终审修复波**（同一分支的复审修完后再交回）：把**洞察配置页**与**导出页**两处
「永远看不到的全局 toast」改为**页内**文案（洞察页的采样失败此前唯一的反馈路径，
用户看到的就是「点了没反应」）；订正三处不实注释（导出动作行那个**没有出处**的
「24 个图标」数字、`delete(insights)` 被说成「必要」的兜底、版本号被说成
「`initState` 取一次」）；删掉顶部渐变里冗余的一层 `IgnorePointer`；确认弹窗的
`CurvedAnimation` 改为 `animation.drive`（不再每次开关留下几十个陈旧 listener），
并把两条分隔线由 1px 改为 **0.5 发丝线**、与全仓其余分隔线同口径；迁移测试补上
`record_id` 为空的洞察存活分支（**含记录表为空**这个让 `IS NOT NULL` 守卫真正吃重的夹具）。
`CLAUDE.md` 的「测试注意」新增「迁移测试要用裸 DDL 冻结旧 schema + 双重防空跑自检」的模板。

## 2.5（2026-09-28）

M2 剩下的两块落地——**数据导出**与**就寝/起床提醒**，只剩小米导入仍被外部资料阻塞。

① **导出**：新增二级页 `/settings/export`。CSV 两张表（记录 16 列 + 阶段 6 列，
UTF-8 BOM、CRLF、RFC 4180 转义、按**入睡时刻升序**——不继承界面那个「最新在前」的倒序，
否则导出的格式会跟着界面排序悄悄变），JSON 为完整嵌套存档。字段名与 schema 对齐、
时间戳写 ISO-8601 UTC，为将来回灌留路。两个刻意的取舍：**不写 `localUri`**（改写成
`hasLocalAudio` 布尔，因为音频文件本身不进导出、路径只会悬空，而导出文件是要分享出去的），
**不导出 `AppSettings`**（设备偏好跨设备回灌会污染，顺带把 API Key 从结构上排除）。
演示记录一律不进文件并计数说明。经系统分享面板（`share_plus`）交付。

② **提醒**：就寝/起床接真实本地通知。`sync` 是**幂等全量重排**（固定 id 9001/9002
先取消再排），并在每次启动重排，因此调度与偏好没有各自独立的生命周期——少一个生命周期
就少一整类「开关开着却不响」。权限被拒时**不写入偏好**、开关回弹；权限为 `denied` 时
给出「去系统设置」入口；启动时若发现偏好为真而权限已是 `denied`（用户在应用之外撤销过），
把偏好写回 `false` 而不是留一个说谎的开关。回收**只认 `denied`，不认 `!= granted`**：
`unsupported` 可能只是一次偶发的时区查询失败，把它当成「授权被撤销」会在启动路径上
悄悄清空用户的提醒偏好。Android 用 `inexactAllowWhileIdle`，不申请精确闹钟权限。

新增依赖 `flutter_local_notifications` / `timezone` / `flutter_timezone` / `share_plus`，
**均不发起网络请求**，因此应用对外的请求仍然只有「获取可用模型」一处。
新增偏差 #18（原型没有导出）、#19（原型的提醒开关是纯装饰）。

## 2.4（2026-09-28）

一轮对着真机/桌面实机的修正，四个问题都出在「Flutter 与 CSS 语义不同」的地方：
① 顶部渐变的 `ShaderMask` 套在 `BackdropFilter` 里面，只遮住了填充、没遮住模糊，模糊留下硬边；
② 主按钮的 `inset 0 1px` 高光画在了内边距里，落在内容顶端成了一道穿过文字的杂线；
③ 标签条的底部留白加在滚动视图**外面**，形成一条遮住内容的不透明带；
④ `showGeneralDialog` 不像 `showDialog` 那样提供 `Material`，弹层内所有文字落到错误样式（黄色双下划线）。
前三条的根因都是「位置/层级的语义与直觉相反」，第 ④ 条与 v2.2 的二级页问题同源。

## 2.3

助眠音效从「只有状态机、不出声」变成**真的出声**——8 种声音在设备上实时合成
（偏差 #5 随之改写）；应用图标由 `assets/branding/app-icon.svg` 生成，脚本一次产出两个平台
的全部尺寸；补上 iOS 构建与其网络前提。新增偏差 #16、#17。

## 2.2

一轮对着实际观感的修正。修掉了三类**真实缺陷**：玻璃卡的 `boxShadow` 写在
自己的 `ClipRRect` 里被裁掉、推入的二级页没有 `Material`/背景/内边距、弹层打开计数在构建期
发通知。新增 `.ios-top-fade` 顶部渐变、弹层三套关闭手势、演示数据二级页、按服务商实时获取
模型列表。新增偏差 #13–#15。

## 2.1

补齐 M1 遗留下的两个缺口。① 编辑与删除记录的界面入口（`/log/edit` 路由 +
详情弹层底部操作），并明确保存时**不得替换已有阶段**、**不得改写 `createdAt`**；
② schema v1→v2 的迁移测试，改用真实 v1 库文件验证，此前 `onUpgrade` 分支从未被执行过。
新增偏差 #11、#12。

## 2.0

v1.0 的设计基准是**读错**的。原型 `index.css` 含多层互相覆盖的样式，早期那套
深紫液态玻璃（`#edf1fb` / `#101322` + 动态光晕）在文件后段被作者自己覆盖为 iOS 原生玻璃风格并
关闭了光晕。v1.0 记录的是早期值，且完全没有描述玻璃材质、圆角层级、导航形态与图标体系。
本版按**最终生效层**重写设计基准，并新增第 8 章记录与原型的有意偏差。
