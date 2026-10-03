# 会话页「入睡前」setup 态实现计划

**Goal:** 照 Figma Make 原型 `SleepView` 的 **setup 分支**补齐「入睡前」页，并据此把
**记录起点**从「点首页按钮」挪到「点页内『开始睡眠』」：点首页「开始入睡」只进页面、
**不写会话行**；页内的场景 / 常用白噪音 / 白噪音完整设置 / 起床闹钟 / 鼾声检测都只是
草稿；按下「开始睡眠」才写会话行、开始计时。

**Architecture:** 不新增页面、不新增路由、不新增数据表。`/sleep/session` 一个路由两态：

```
activeSessionProvider == null  →  setup 态（草稿在页面 State 里，什么都不落库）
activeSessionProvider != null  →  active 态（v3.2 版式，本轮只做收紧）
```

设置的真源**不变**：风景 / 白噪音 / 音量 / 闹钟时刻与开关住**会话行**，鼾声偏好住
`AppSettings.soundRecordingEnabled`，白噪音「定时」仍在 `NoiseSessionController` 内存里。

**Tech Stack:** Flutter 3.47.5 / Dart 3 / Riverpod / Drift / go_router。

**设计出处（权威）：** 原型源码缓存 `/tmp/figma-make/App.tsx` 的 `SleepView`
（setup 分支 = 第 754–866 行；场景选择器 = 第 582–600 行）与 `/tmp/figma-make/index.css`
（**取最终生效层**：第 1730–1960 行那段 `/* ── Immersive sleep controls ── */` 覆盖了前面
第 1557 行起的同名规则）。规格原文见
`docs/superpowers/specs/2026-09-30-sleep-session-design.md` §十七。

---

## Global Constraints

- 界面文案、注释、文档**一律中文**；代码标识符英文。
- 令牌只有一处：会话页的暗色值继续从 `night_style.dart` 取（偏差 #32），
  新增的值也**必须**先落 `NightStyle` 再从 widget 取，**不在 widget 里写死色值**。
- 不碰 `lib/**/*.g.dart`（Drift 生成，已 gitignore）。
- **产品红线（一个字都不许改）：**
  - 鼾声行副标题必须逐字是 `'尚未接入录音，开关只保存偏好。'`。原型的
    「仅在本机识别并保存声音片段」是**我们不能说的话**（plan A 没接录音）。
  - 投递强度标注必须用 `ReminderScheduler.wakeAlarmDeliveryNote` 这份字面量，不另抄。
  - 时长守门 `(0, 24h]` 不落库、就地评星（可跳过）、丢弃会话、「收起」离开页面而会话
    继续跑（白噪音随之继续响）——全部原样保留。
- 设置只有一个真源：**不改** `AppSettings.soundRecordingEnabled` 这条；
  **不新建**任何「草稿表」——setup 的草稿活在页面 State 里，关掉页面就没了。

---

## 裁定（使用方，2026-10-02）

1. setup 态**照原型做**，记录起点挪到页内的「开始睡眠」。
2. active 态**照原型收紧**：白噪音行、起床闹钟行不再可点（设置只在 setup 做）——
   偏差 #29 / #30 **撤销**。
3. 首页主按钮改原型的「**开始入睡**」。

## 与原型的有意偏差（本轮新增，需写进规格偏差表）

| # | 原型 | 本实现 | 理由 |
| --- | --- | --- | --- |
| 35 | setup 鼾声行副标题「仅在本机识别并保存声音片段」 | 维持「尚未接入录音，开关只保存偏好。」 | plan A 没接录音（偏差 #7 是产品红线）。同源于 #31 |
| 36 | setup 默认：鼾声开、起床闹钟**开**且 07:30 | 鼾声取 `AppSettings.soundRecordingEnabled`（默认关）；闹钟默认**关**，时刻取设置里的起床提醒时刻，没有则 07:00（`SessionRepository.defaultWakeMinutes`） | 替用户排一个他没设过的真实通知、或默认打开一个我们并不具备的能力，都是「没有的东西显示成有」 |
| 37 | setup 的四格「常用白噪音」点选**不**试听、「完整设置」里点选才试听 | 两处都即选即播 | 控制器的语义就是「选中**并正在播放**」（偏差 #33 的同一个语义），再做第二套「只选中不出声」的状态等于多一个真源。收起页面会停掉试听 |
| 38 | setup 的播放时长有「整晚」 | 仍只有 15 / 30 / 45 / 60 | 既有裁定（§四 / §六）：整晚的噪音会一直占着录音通道，plan B 之后是硬冲突 |

## 订正（本轮顺带修的照抄错层）

- **场景卡选中态**：`.sleep-scene-choice.is-selected .sleep-scene-preview` 在最终生效层
  是 `transform: scale(.98)`（index.css:1789），早先那层 `translateY(-2px)`（index.css:1590）
  被它覆盖。现有实现照抄了早期那层，**改为 `scale(.98)`**（描边与光晕不变）。
- **内容限宽**：`.sleep-setup .sleep-mode-shell` 与 `.sleep-active .sleep-mode-shell`
  在最终生效层都是 `width: min(100%, 680px)`（index.css:1734 / 1915）；现有页面没有限宽，
  宽屏下会拉满。**两态一并居中限宽 680**。

---

## Task 1 数据层：`start()` 直接接收 setup 的草稿

**Files:** `lib/features/sleep/data/session_repository.dart`、`test/session_repository_test.dart`

**为什么：** 不然「开始睡眠」要写成 `start()` 再 `update(...)` 两笔，中间那一瞬库里
`noiseId` 是 `null` 而播放器已经在放——一个「库里说没放、实际在放」的假值。
`ActiveSessions` 本来就有这几列，一次性写进去最诚实。

**接口：**

```dart
Future<SleepSession> start({
  DateTime? now,
  int? wakeMinutes,
  bool alarmEnabled = false,
  String? sceneId,
  String? noiseId,
  double? noiseVolume,
});
```

- [ ] Step 1（先红）：`test/session_repository_test.dart` 加一组「start 一次写全草稿」：
  - 传 `alarmEnabled: true, sceneId: 'galaxy', noiseId: 'rain', noiseVolume: .35` →
    `load()` 读回来的四个字段逐一相等；
  - 不传时 → `alarmEnabled` 为 `false`、`sceneId`/`noiseId` 为 `null`
    （**反向护栏**：默认值不许被新参数带偏）；
  - `sceneId: NightScene.galaxy.id` 这种「库里是不认识的 id」由页面兜，仓库不管。
- [ ] Step 2：改 `start()`：`ActiveSessionsCompanion.insert(...)` 里补
  `alarmEnabled: Value(alarmEnabled)`、`sceneId: Value(sceneId)`、
  `noiseId: Value(noiseId)`、`noiseVolume: Value(noiseVolume ?? 0.5)`。
  注意 `noiseVolume` 列有 `withDefault(.5)`，不传时**显式写 .5** 与列默认一致。
- [ ] Step 3：`flutter test test/session_repository_test.dart`

## Task 2 场景选择器：加 setup 变体 + 订正选中态

**Files:** `lib/features/session/presentation/widgets/night_scene_picker.dart`、
`test/session_night_widgets_test.dart`

**接口：** `NightScenePicker({required scene, required onChanged, bool compact = true})`

- `compact: true`（active，现状不变）：浮在场景上的半透明卡、**无**标题行。
- `compact: false`（setup）：**不画卡片**（它住在 `sleep-control-deck` 里，deck 自带
  描边与模糊）、多一行标题：
  - 左侧 `AppIcons.sparkle(size: 15, ...)` + 「夜景氛围」（12 / w700 / `rgba(225,229,244,.72)`）
  - 右侧「左右滑动切换」（10 / `rgba(225,229,244,.32)`）
  - 标题行 padding `0 2 10`；列表 padding `5 16 10`（卡片可滚到 deck 边缘）

- [ ] Step 1（先红）：`test/session_night_widgets_test.dart` 加两条：
  - `compact: false` 时报出「夜景氛围」与「左右滑动切换」两个文案；`compact: true` 时两条都**不**在（反向护栏）；
  - 两张卡各自的选中态：断言选中卡的 `Transform` 是 `scale(.98)`（用
    `tester.widget<Transform>` 取 `transform` 矩阵的 `[0]` 与 `[5]` 约等于 .98），
    且**没有** y 位移（订正错层，防有人照早期那层改回 `translateY(-2px)`）。
- [ ] Step 2：实现 `compact` 分支；把 `NightSceneChoice` 的选中位移从
  `Matrix4.translationValues(0, selected ? -2 : 0, 0)` 改成
  `Matrix4.diagonal3Values(selected ? .98 : 1, selected ? .98 : 1, 1)`。
- [ ] Step 3：`flutter test test/session_night_widgets_test.dart test/night_scene_test.dart`

## Task 3 setup 视图 `SessionSetupBody`

**Files:** 新建 `lib/features/session/presentation/widgets/session_setup.dart`；
`lib/features/session/presentation/night_style.dart`（补新令牌）

**接口（presentational，草稿与副作用全在页面）：**

```dart
class SessionSetupBody extends StatelessWidget {
  const SessionSetupBody({
    required this.scene,                 // 草稿：当前选中的夜景
    required this.alarmEnabled,          // 草稿
    required this.wakeMinutes,           // 草稿
    required this.onSceneChanged,
    required this.onAlarmToggled,        // Future<void> Function(bool)  页面负责权限闸口
    required this.onWakeTimePicked,      // VoidCallback                 页面负责滚轮
    required this.onStart,
    required this.scrollController,
  });
}
```

结构与数值（**逐条取自最终生效层**，行号见文件头；新色值先进 `NightStyle`）：

```
收起胶囊            睡眠模式           ← kicker 11/w700/ls .14em/rgba(225,229,244,.5)
        ☾ 轨道 102
        晚安                          ← 13/w700/ls .14em/#9eaff3，距 h1 5
        准备好休息了吗？                ← 29/w700/ls -.04em（display 字体）
        放下今天，让夜晚慢下来。          ← 距上 7，14/rgba(225,229,244,.56)
┌────────────────────────────────┐   ← deck：圆角 28、描边 rgba(255,255,255,.10)、
│ ✦ 夜景氛围          左右滑动切换  │      渐变 145deg rgba(255,255,255,.09)→.04、
│ [八张 68 宽场景卡 →]             │      inset 0 1 rgba(255,255,255,.10)、
│────────────────────────────────│      blur(24) saturate(130%)、0 20 50 rgba(0,0,0,.16)
│ 常用白噪音            完整设置    │
│ [雨声][海浪][棕噪音][风扇]        │   ← 四格 min-height 47、圆角 14、gap 7
│────────────────────────────────│
│ ♪ 白噪音  雨声 · 35% · 45 分钟  › │   ← 控制行 min-height 61、padding 10/16
│ ⏰ 起床闹钟 轻柔唤醒… [07:30] [●] │      图标底板 35×35 圆角 12
│ 😴 鼾声检测 尚未接入录音…     [●] │
└────────────────────────────────┘
        [ ☾ 开始睡眠 ]               ← min-height 58、圆角 18、渐变 135deg
                                       #687fe2→#6962c7、阴影 0 12 30 rgba(68,80,164,.32)
     屏幕将保持暗色，轻触夜景即可切换氛围  ← 距上 11、11px、居中
```

- hero：`min-height 230`、padding `24 0 22`、居中。月亮用既有的
  `SleepMoonOrbit(size: 102)`（内部月亮按 `size * .79` 画，与原型 82/102 同口径）。
- 四格白噪音：从 `kNoiseOptions` 里按 id 取 `rain / ocean / brown / fan`
  （= 雨声 / 海浪 / 棕噪音 / 风扇，与原型 `sleepNoises` 同四项同序）。点已选中的那格 =
  取消选择（原型 `noiseId === sound.id ? null : sound.id`）。
- 白噪音控制行：副标题「`雨声 · 35% · 45 分钟`」，没选时「未开启」；右侧 chevron，
  整行可点 → `showNightNoiseSheet(context)`（既有弹窗，**不用改**）。
- 起床闹钟行：副标题「轻柔唤醒，不改变系统闹钟」/「本次睡眠不设闹钟」；时刻胶囊
  （宽 66、圆角 9、字 `#bdc9ff` num 12/w650、底 `rgba(126,145,233,.12)`）+ `IosToggle`。
- 鼾声检测行：`IosToggle`，副标题**红线文案**。
- 三行的行样式新建私有 `_SetupRow`（35×35 图标底板、min-height 61、分隔线
  `rgba(255,255,255,.07)` 且最后一行不画）——**不复用** active 的 `_EventRow`（那是 34×34）。

- [ ] Step 1：先在 `night_style.dart` 补令牌（deck 渐变/描边、控制行文案色、四格
  三色、kicker/hero 文案色、开始按钮渐变与阴影、时刻胶囊色）。**只加常量，不动既有值。**
- [ ] Step 2：写 `SessionSetupBody` 与私有 `_SetupRow` / `_QuickSoundTile` / `_StartButton`。
  全部文案逐字取自原型（晚安 / 准备好休息了吗？ / 放下今天，让夜晚慢下来。 / 夜景氛围 /
  左右滑动切换 / 常用白噪音 / 完整设置 / 白噪音 / 起床闹钟 / 鼾声检测 / 开始睡眠 /
  屏幕将保持暗色，轻触夜景即可切换氛围）。**鼾声副标题与「轻触夜景」之外，不许自创文案。**
- [ ] Step 3：`flutter analyze`（此时还没有测试，先保证编译与静态检查过）

## Task 4 页面接线：两态、草稿、开始睡眠

**Files:** `lib/features/session/presentation/sleep_session_page.dart`、
新建 `test/session_setup_page_test.dart`（从 `sleep_session_page_test.dart` 拆一条出去，
避免那个文件继续膨胀）

**接口与行为：**

```dart
// _SleepSessionPageState 新增草稿（只在 session == null 时有意义）
NightScene _draftScene = NightScene.fallback;   // 流星夜
bool _draftAlarm = false;                       // 见偏差 #36
int? _draftWakeMinutes;                         // 首帧后从 settings 取
```

- `build`：`session == null` → `SessionSetupBody(...)`；否则 `_SessionBody(...)`（不变）。
  背景 `NightBackdrop(scene:)` 在 setup 用 `_draftScene`、在 active 用会话行里的 scene。
- 首帧读一次草稿的闹钟默认值：`ref.read(databaseProvider).getSettings()` →
  `wakeReminderMinutes ?? SessionRepository.defaultWakeMinutes`、`alarmEnabled: false`
  （**只读一次，不 `watch`**——widget 测试的假时钟不推进，订阅 drift 流会留 pending timer，
  见 `.claude/skills/flutter-pitfalls`）。
- **开始睡眠**（`_beginSleep`）：
  1. 闹钟开着且 `!await ensureNotificationPermission(context, ref, target: '闹钟')` → **不写库**，
     开关由调用方弹回（与 active 态同一个闸口行为）；
  2. `await ref.read(sessionRepositoryProvider).start(wakeMinutes: _draftWakeMinutes,
     alarmEnabled: _draftAlarm, sceneId: _draftScene.id,
     noiseId: noise.activeId, noiseVolume: noise.volume, now: widget.now)`;
  3. `await syncAllReminders(...)`（与收尾同款：会话闹钟与日常提醒必须成对推导）；
  4. **不 pop、不 push**——写完行，`activeSessionProvider` 自己把页面翻到 active 态。
     白噪音早就由控制器在响（Task 3 的即选即播），这里不做第二次 `play`。
- **收起**（setup 态）：停掉试听 `await ref.read(noiseSessionControllerProvider).stop()`
  再 `pop()`；**不写任何行**。active 态的收起行为一个字节不改（会话继续跑、白噪音继续响）。
- 删除 `_NoSession`（「没有正在进行的睡眠」空状态）：无会话 = setup 态，这个状态不存在了。
- 两态内容都居中限宽 680（订正项）。

- [ ] Step 1（先红）：新建 `test/session_setup_page_test.dart`，`pumpPage` 复用
  `sleep_session_page_test.dart` 的既有一套（TestWidgetsFlutterBinding + 内存库 +
  `activeSessionProvider.overrideWith((ref) => null)` + `SessionRepository(数据库)`），
  加这几条：
  - **setup 态渲染**：报出「晚安」「准备好休息了吗？」「开始睡眠」「睡眠模式」，
    且**不**报「没有正在进行的睡眠」（旧空状态已被取代）；
  - **进页面不写库**：挂载后 `await database.activeSession()` 为 `null`；
  - **点「开始睡眠」才写库**：点一下 → 会话行存在，且 `startAtUtc` 等于注入的
    `now`、`sceneId` 等于当前草稿、`alarmEnabled` 为 false；
  - **选场景只改草稿**：点「银河」→ 页面背景换成银河（`NightBackdrop.scene` 断言），
    库里仍无会话行；点「开始睡眠」后会话行的 `sceneId` 才是 `galaxy`；
  - **收起不写库**：点「收起」→ `pop`（用 `NightSleepApp` + `push` 挂），库里仍为 `null`，
    且白噪音控制器 `isPlaying` 为 false；
  - **草稿不跨页存活**：收起再进，场景回到「流星夜」、四格无一选中（原型也是 unmount 即丢）；
  - **闹钟权限被拒时不写库**：注入被拒的权限假实现（照
    `sleep_session_page_test.dart:532` 那条的既有手法），点开→点「开始睡眠」→ 库里无行、
    没有会话。
- [ ] Step 2：改 `sleep_session_page_test.dart` 里那条「没有会话时不崩，显示空状态并可返回」
  （:349–370）→ 改成「没有会话时进 setup 态」（新用例在 Task 4 Step 1 已覆盖，
  这条删掉并在新文件里留同名语义）。
- [ ] Step 3：`flutter test test/session_setup_page_test.dart test/sleep_session_page_test.dart`

## Task 5 active 态照原型收紧

**Files:** `lib/features/session/presentation/widgets/session_events_card.dart`、
`test/sleep_session_page_test.dart`

- **白噪音行**：只在 `noise.activeId != null`（= 正在播放）时渲染，**去掉 `onTap`**。
  右侧仍是 `_SoundWave`。删除「未开启」态与「点这里选择助眠声音」（偏差 #29 撤销、
  #33 改写为「选中即播放、停止即取消选择，所以只有『在/不在』」）。
- **起床闹钟行**：只在 `session.alarmEnabled` 时渲染（照原型），**去掉 `_WakeTimeChip`
  与 `IosToggle`**，右侧改成 `_StateText('已设置')`，标题仍是「`07:30` 起床闹钟」；
  **副标题与投递强度标注原样保留**（`_alarmStatus` 与
  `ReminderScheduler.wakeAlarmDeliveryNote` 是产品红线，不许删）。
- **鼾声行**：不动（偏差 #31 保留：状态点会宣称一个我们并不具备的能力）。
- 因此 `_pickWakeTime` / `_toggleAlarm` / `ensureNotificationPermission` /
  `_resyncAlarm` 从本文件**移走**（权限闸口搬去 setup 的闹钟行）。
- [ ] Step 1（先红→改）：更新 `sleep_session_page_test.dart`：
  - 「事件卡四行常驻，点白噪音行打开底部弹窗」→ 拆成两条：
    ①未播放白噪音时**没有**白噪音行（`find.text('白噪音')` 为空）；
    ②播放中（`noise.select` 走一遍 / 注入控制器状态）白噪音行在，且**点它不弹窗**（弹窗断言为 0）；
  - 「闹钟关着时那一行说『本次睡眠不设闹钟』」→ 改成「闹钟关着时**没有**闹钟行」；
  - 「闹钟开着时报剩余时间，并带上后台投递的如实标注」→ 保留断言，去掉对开关/胶囊的断言；
  - 「闹钟开关被拒时回弹，且不写入会话的 alarmEnabled」→ 从本文件**移到**
    `session_setup_page_test.dart`，改成「setup 里闹钟开关被拒时不写库也不计入草稿」；
  - 「超过起床时间后闹钟行说『已过』…」「入睡与闹钟时刻都补零到两位」保留（只去掉对
    可点胶囊的断言）。
- [ ] Step 2：改 `SessionEventsCard`。
- [ ] Step 3：`flutter test test/sleep_session_page_test.dart test/session_night_widgets_test.dart`

## Task 6 入口与首页文案

**Files:** `lib/app/app.dart`、`lib/features/home/presentation/home_page.dart`、
`test/pages_widget_test.dart`

- `_startSleep`：删掉 `await start()`，只 `context.push('/sleep/session')`
  （方法改名 `_openSession`，注释写清「落库挪到页内『开始睡眠』」）。
- 首页主按钮与空状态行动按钮：`开始睡眠` → **`开始入睡`**（原型首页的文案）；
  副标题（无会话时）改为「**开启睡眠记录、白噪音与夜景氛围**」
  ——**不写原型那句「鼾声检测」**：plan A 没接录音，那是我们不能承诺的能力
  （用户 2026-10-02 认可照原型改文案，此处只避开这一处会与红线打架的三字）。
- [ ] Step 1（先红→改）：`pages_widget_test.dart`
  - :252–253、:307–313、:315–320 三处的 `'开始睡眠'` → `'开始入睡'`；
  - **「点『开始睡眠』会写入会话行」（:343–356）改成「点『开始入睡』只进页面、不写库」**：
    点完 `pumpAndSettle` 后 `expect(await database.activeSession(), isNull)`，
    并断言页面推入了会话页（`find.text('开始睡眠')` 出现在 setup 里）。
- [ ] Step 2：改代码。注意 `app.dart` 里可能留下未使用的 import（`session_repository`）。
- [ ] Step 3：`flutter test test/pages_widget_test.dart`

## Task 7 收尾：全量测试 + 文档

- [ ] `dart format .` → `flutter analyze` → `flutter test`（全量）
- [ ] `docs/superpowers/specs/2026-09-30-sleep-session-design.md`：新增 **§十七**
  （setup 态的结构、尺寸表、草稿生命周期、记录起点、「开始睡眠」的写库顺序）；
  §16.1 那句「我们没有 setup 态」**原地订正**；**偏差表**同步：新增 #35–#38、
  #29/#30 标记**撤销**（保留行、附撤销理由与回归方法）、#33 改写。
- [ ] `docs/superpowers/specs/2026-09-28-night-sleep-design.md`：第 5 章「会话页」一行、
  第 8 章偏差表（#29/#30/#33 + 新增 #35–#38）、第 9 章测试矩阵加 setup 的行。
- [ ] `README.md`：实现范围（首页入口 → setup → active）+ 验证记录（新增测试条数；
  并如实写明**未做目视核对**）。
- [ ] `CHANGELOG.md`：新增 **3.3**（2026-10-02）一节。
- [ ] 目视核对**不塞进本轮的实现任务**，留到最后一批：`flutter run -d macos` 看 setup 态
  月亮/选择器/deck 三段、点「开始睡眠」翻 active、收起不写库；截图按 README 的巡检方式存
  `screenshots/v3.3-*.png`。视截图结果决定是否需要回调。

---

## 执行期补记（2026-10-03）

计划在执行中改了三处，都是「按原计划做会做出错的东西」：

1. **Task 1 追加了一个既有缺陷的修复。** 入睡前态一帧里有**两个** `getSettings()` 读者
   （页面的起床草稿、setup 视图的鼾声偏好），而 `AppDatabase.getSettings()` 是「先读后插」——
   全新库上两个都看到「没有」→ 都去插 → 后一个撞 `UNIQUE constraint failed: app_settings.id`，
   整页炸掉。改成 `InsertMode.insertOrIgnore`，并在 `test/session_repository_test.dart` 加了
   并发回归。这不是本轮引入的缺陷，是本轮第一次让它有了稳定触发路径。
2. **Task 4 的「翻页」那条换了一种测法。** 用真的 `activeSessionProvider` 写一个 testWidgets
   会**留下 pending timer**（drift 的 `watch*`，`AutomatedTestWidgetsFlutterBinding` 拆树后
   直接断言失败——已实测，正是 `.claude/skills/flutter-pitfalls` 里记的那条）。改成不挂树的
   `ProviderContainer` 测「写下会话行 → provider 把新会话推上来」这条接线；页面那一半
   （provider 里有会话就渲染进行中态）由本仓库其余 widget 测试覆盖。
3. **Task 5 多留了一处渲染条件，比原型多。** 原型只在闹钟开着时渲染那一行；照抄的话，
   **没设闹钟又睡过头**的会话就再也看不到「已超过起床时间 · 请手动结束睡眠」这句唯一的动作
   指令（§16.5 特意把它挪到这一行的）。改成 `alarmEnabled || overdueAt(now)` 时渲染；此时右侧
   不写「已设置」（那是假话）。它说的是用户自己设的数，没有宣称任何我们不掌握的东西，
   所以不计入偏差表，规格 §17.4 里记了理由。

4. **收尾核对原型 CSS 时发现漏了同一层的两条媒体查询**（`@media (max-width: 390px)` 与
   `@media (min-height: 860px)`，index.css:1937 起）：窄屏 deck 内边距 16→13、常用白噪音四格
   改竖排；高屏 hero 230→285。它们与上面那些数值**同在「最终生效层」那一块里**——「查最终
   生效层」这件事得连媒体查询一起查，否则就是又一次读漏层。三条断言补进了
   `test/session_setup_page_test.dart`。

另外两处执行细节：

- **白噪音设置弹窗的入口现在只在入睡前态**，所以原来在会话页里靠点「白噪音」行驱动弹窗的
  三条用例中，「选中/再点一次」「倒计时到点」两条**搬到** `test/session_night_widgets_test.dart`
  （那边的夹具本来就带会话行，`pumpNoiseSheet` 顺手改成返回数据库），第三条与那边既有的
  「点完成关掉弹窗，白噪音继续响」重复，删掉。
- **巡检脚本按新流程改写了**（入睡前那一屏 → 「完整设置」弹窗 → 「开始睡眠」 → 长按/评星），
  但**没有执行过 `flutter drive`**（README 未验证项里记着）。
- **目视核对**做了 macOS 一遍（真实 Impeller 引擎、约 412×890pt 的窗口）：一屏装得下、
  日志无异常与 overflow。iOS 真机/模拟器仍未看。
