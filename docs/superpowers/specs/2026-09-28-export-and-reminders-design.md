# 导出与提醒设计

> 日期：2026-09-28
> 状态：待实施
> 范围：设置页新增「睡眠数据导出」子页；就寝/起床提醒接入真实本地通知
> 设计基准：[夜深项目规格说明书](2026-09-28-night-sleep-design.md)。本文不重复其第 8 章的产品红线，但受其约束——
> 不伪造数据、不让开关声称自己没有的能力、演示数据与真实数据隔离。

## 问题

规格 M2「提醒与本地数据导入/导出」列了三项，其中两项**没有外部依赖阻塞**，可以现在做完：

1. **就寝与起床提醒** —— 当前开关只写 `AppSettings`，不申请权限也不调度任何通知。
   这是 README「未实现」表里最容易被误读的一项：一个开着却什么都不会发生的开关。
2. **导出 CSV / JSON** —— 完全没有实现。用户目前的数据只能通过「删除全部本地数据」离开应用。

第三项（小米手环导入）需要真实导出样本或官方文档才能实现，本设计不动它，
设置页那一屏继续保持「按钮禁用 + 说明缺什么」的原样。

本设计完成后，M2 只剩小米导入一项未了。

## 非目标

- 不实现**导入**（含自家导出文件的回灌）。JSON 的字段设计为将来回灌留了路，但本轮不写解析器、
  不做「导入前预览条数、重复项与错误项」。
- 不实现锁屏控制、后台播放与录音（M3）。
- 不实现 AI 洞察调用与密钥安全存储（M4）。
- 不改动小米导入那一屏。
- 不申请麦克风权限。

## 新增依赖

| 包 | 版本 | 用途 | 不引入它的后果 |
| --- | --- | --- | --- |
| `flutter_local_notifications` | 22.3.1 | 本地通知的权限、调度与取消 | 得自己为 iOS/macOS 各写一份 `UNUserNotificationCenter` 接线 |
| `timezone` | 0.11.1 | `zonedSchedule` 的时区换算 | 无法按墙上时间重复 |
| `flutter_timezone` | 5.1.0 | 取设备 IANA 时区名 | `tz.local` 会停在 UTC，夏令时切换后提醒时刻整体漂一小时 |
| `share_plus` | 13.3.0 | 把导出文件交给系统分享面板 | 只剩「写到自己目录再让用户去找」，iOS 上基本找不到 |

**不引入 `url_launcher`。** 插件的 `IOSFlutterLocalNotificationsPlugin` 与
`MacOSFlutterLocalNotificationsPlugin` 都自带 `openAppNotificationSettings()`，
「去系统设置」直接用它，不必再为打开一个 URL 加依赖。

## 导出

### 分层

沿用项目的 `presentation / domain / data` 划分，把**可测的纯计算**与**不可测的平台调用**分开：

| 文件 | 职责 | 依赖 |
| --- | --- | --- |
| `features/settings/domain/sleep_export.dart` | 由 `List<SleepEntry>` 生成导出文件的内容与文件名 | 无。纯函数，无 IO、无插件 |
| `features/settings/data/export_sharer.dart` | `ExportSharer` 接口 + 默认实现：写临时目录、调系统分享面板 | `path_provider`、`share_plus` |
| `features/settings/presentation/export_page.dart` | 导出页 | Riverpod |

```dart
class ExportFile {
  const ExportFile({required this.fileName, required this.content, required this.mimeType});
  final String fileName;
  final String content;
  final String mimeType;
}

/// 日期取「醒来所在本地日期」当天的日期，用于文件名。
abstract final class SleepExporter {
  static List<ExportFile> csv(List<SleepEntry> entries, {required DateTime now});
  static List<ExportFile> json(List<SleepEntry> entries, {required DateTime now});
}

enum ShareOutcome { shared, dismissed, failed }

abstract interface class ExportSharer {
  Future<ShareOutcome> share({required List<ExportFile> files, required String subject});
}
```

`now` 由调用方传入而不是内部取 `DateTime.now()`，这样文件名与 `exportedAtUtc` 在测试里可断言。
两个生成函数都**不修改入参、不抛异常**：没有记录时返回结构完整、计数为 0 的文件，
「要不要允许导出」是页面的决定，不是生成器的。

`exportSharerProvider` 默认返回 `SystemExportSharer`（生产路径正常），测试用 provider override
换成假实现。这一层接口的存在理由很具体：`share_plus` 走平台通道，在 `testWidgets` 的 FakeAsync
里会挂死——与 `HapticFeedback` 同一个坑（见 CLAUDE.md「测试注意」）。widget 测试只验证
「交给 sharer 的内容对不对」，不验证分享面板本身。

### 数据来源与排除规则

导出**只取真实记录**：所有 `source == AppConfig.demoSource` 的行一律不进文件，
`excludedDemoCount` 记下被排除了几条。

演示之夜是合成的（阶段、转写、包络都是示例），把它们写进用户的备份等于往真实数据里掺假。
这与偏差 #6（演示数据只在 `DEMO_DATA` 下安装）和偏差 #11（演示数据不可编辑）是同一条原则：
演示数据可以看，但不能混进真实数据的任何出口。

调试构建里若**只有**演示数据，导出页如实显示「没有可导出的真实记录」，两个按钮禁用，
既不生成空文件，也不谎报成功。

### CSV 格式

两张表，各自是一个文件。**UTF-8 带 BOM**（`﻿` 前缀）——没有 BOM 时 Excel 打开中文是乱码；
行分隔用 `CRLF`。

`夜深-睡眠记录-YYYYMMDD.csv`，一行一晚：

| 列 | 来源 | 格式 |
| --- | --- | --- |
| 日期 | `entry.dateLabel` | `YYYY-MM-DD`（醒来所在本地日期） |
| 入睡时刻 | `entry.bedtimeLabel` | `HH:mm` |
| 醒来时刻 | `entry.wakeLabel` | `HH:mm` |
| 时区 | `entry.timeZoneId` | 录入时区名 |
| 时长(小时) | `durationMinutes / 60` | 两位小数，如 `8.25` |
| 时长(分钟) | `durationMinutes` | 整数 |
| 质量 | `entry.quality.value` | 1–5 |
| 打鼾 / 梦话 / 辗转 / 噩梦 | `entry.loggedEvents` | `是` / `否` |
| 备注 | `entry.notes` | 原文（转义见下） |
| 来源 | `entry.source` | `manual` / `import` |
| 记录ID | `entry.id` | |
| 最初记录时间 | `createdAtUtc` | 本地墙钟 `YYYY-MM-DD HH:mm` |
| 最后修改时间 | `updatedAtUtc` | 本地墙钟 `YYYY-MM-DD HH:mm` |

`夜深-睡眠阶段-YYYYMMDD.csv`，一行一段：

| 列 | 来源 |
| --- | --- |
| 记录ID | 所属记录的 `id`，用于与记录表关联 |
| 阶段 | `SleepStageType.label`（`清醒` / `浅睡` / `深睡` / `REM`） |
| 开始时间 | 本地墙钟 `YYYY-MM-DD HH:mm` |
| 结束时间 | 本地墙钟 `YYYY-MM-DD HH:mm` |
| 时长(分钟) | 段时长 |
| 来源 | 段的 `source` |

**分为两张表而不是把阶段压成「深睡/浅睡/REM 分钟」三列**：阶段分段的时间戳是阶段图的唯一来源，
压成合计就回不来了。记录表一行一晚，透视照样能做；要按段分析时阶段表就在手边。

**转义规则**：字段含 `,`、`"`、`\r`、`\n` 时用双引号包裹，内部的 `"` 写成 `""`。
备注是用户自由输入，最可能触发这一条。数值与时间列永不触发。

**时间一律本地墙钟**，时区单独成列——与规格「入睡/醒来存 UTC 瞬时值 + 录入时区，
墙上时间读取时派生」的口径一致。这样导出的表直接可读，而时间轴仍然可复原。

**行序按入睡时刻升序（最早的在前），由导出器自己排。**

不依赖 `sleepEntriesProvider` 交给它的顺序，虽然那正好是**倒序**。原因不是审美：
让导出格式继承界面的排序，等于把两者隐式绑在一起——将来 `SleepRepository.loadAll()`
一改排序（界面想换个呈现方式就会改），导出的文件会**静默**跟着变，而不变的那些行序断言
也测不出来。显式排序把这个耦合断开，顺带让 CSV 在表格软件里按时间轴自然展开
（日期列直接拿去画图、做透视都不用再排一次）。

JSON 用同一顺序，两种格式对同一份数据给出一致的读法。

### JSON 格式

`夜深-睡眠数据-YYYYMMDD.json`，完整嵌套：

```json
{
  "format": "night-sleep-export",
  "version": 1,
  "exportedAtUtc": "2026-09-28T14:03:11.000Z",
  "schemaVersion": 2,
  "recordCount": 12,
  "excludedDemoCount": 6,
  "records": [
    {
      "id": "…",
      "startAtUtc": "2026-09-27T14:30:00.000Z",
      "endAtUtc": "2026-09-27T22:45:00.000Z",
      "timeZoneId": "CST",
      "quality": 4,
      "notes": "…",
      "tags": [],
      "source": "manual",
      "loggedEvents": { "snore": true, "talk": false, "restless": false, "nightmare": false },
      "createdAtUtc": "…",
      "updatedAtUtc": "…",
      "stages": [
        { "stage": "deep", "startAtUtc": "…", "endAtUtc": "…", "source": "import" }
      ],
      "soundClips": [
        {
          "id": "…", "kind": "snore", "startedAtUtc": "…", "durationMs": 4200,
          "hasLocalAudio": false, "transcript": null, "analysis": null,
          "analysisStatus": "pending", "source": "recording"
        }
      ],
      "insight": null
    }
  ]
}
```

字段名与 schema 对齐，时间戳写 ISO-8601 UTC；`stages` / `soundClips` / `tags` 恒为数组，
不写 `null`，消费方少一个分支。`insight` 没有就是 `null`。

`stages` 的元素没有 `id`：领域模型 `SleepStageSegment` 只带阶段、起止与来源，
不携带数据库行 id（仓库组装聚合时就没往外传）。回灌时一条阶段段靠
所属记录 + 起止时间定位即可，为导出专门把行 id 一路透出来不值得。
`soundClips` 与 `insight` 的 `id` 保留，因为它们本来就是独立实体。

**不写派生值**：时长、阶段合计、占比都不进文件。规格已定「时长派生不存储」，
备份里塞一份派生快照只会多一个会过期的事实。

### 两个刻意的取舍

**一、不写 `localUri`，改写成 `hasLocalAudio` 布尔值。**
`SoundClips.localUri` 是设备上的绝对路径，含应用容器的 UUID。音频文件本身不进导出，
所以这个路径在被导出的文件里必然悬空；而导出文件又是要**分享出去**的（可能进邮件、进云盘），
把一个设备本地路径顺带捎出去没有必要。保留一个布尔量，回灌时能知道「这条片段原本有音频」，
足够。

**二、不导出 `AppSettings`。**
里面是设备偏好（主题模式、睡眠目标、服务商与模型选择），跨设备回灌只会污染目标设备的设置；
睡眠目标是「我的目标」而不是「这段时间的事实」，不属于备份内容。
顺带的效果是 API Key 被彻底排除在导出之外——虽然它本来就不存在 `AppSettings` 里
（见偏差 #8），这一条把它从「恰好不在」变成「结构上不可能在」。

### 文件交付

`SystemExportSharer` 把文件写到 `getTemporaryDirectory()/export/`，文件名即上文的名字，
同名覆盖；然后调 `SharePlus.instance.share(ShareParams(files: [...], subject: '夜深睡眠数据导出'))`。
把 `ShareResult.status` 映射成 `ShareOutcome`：`success` → `shared`，`dismissed` → `dismissed`，
其余 → `failed`。

**不做主动清理**：文件名带日期，同一天重复导出覆盖同一路径；临时目录由系统回收，
自己在启动时扫一遍删旧文件既多一份代码，也多一种「分享面板还开着、文件已被删掉」的边界情况。

文件名用中文（`夜深-睡眠记录-20260928.csv`）。界面文案全是中文，文件名跟着走更好认；
iOS/macOS/Android 的文件系统与分享面板都按 UTF-8 处理，没有兼容问题。

### 导出页

路由 `/settings/export`，声明为 `/` 的子路由（推入后盖住标签条，与另外三个二级页一致），
页面用 `core/widgets/subpage.dart` 的 `Subpage`，**不自己套 `Scaffold`**——
推入的路由什么都继承不到，这是二级页黑底与黄色下划线的成因（见偏差与 v2.2 病历）。

版面：

1. **将导出**卡片 —— 四个数字格：记录 / 阶段段 / 声音片段 / 洞察条数。
   下方一行灰字「已排除 N 条演示记录」，仅在 `N > 0` 时出现。
2. **两个动作**，同一 `IosListGroup` 内的两行 `IosListItem`，各自带 `onTap`
   （不能用 group 级 `onTap`——那会把整组变成同一个跳转目标）：
   - 「导出 CSV」/ 副标题「记录与阶段两张表，可用表格软件打开」
   - 「导出 JSON」/ 副标题「完整数据，含阶段、声音事件与洞察」
3. **说明**：不含音频文件本身；不含设置与密钥；文件交给系统分享面板，去向由你决定。

**导出行不加图标。** 设计的 24 个图标里没有表达「导出」的那一个，自绘一个就是引入一套
应用其余部分没有的图标语言——与偏差 #12（不补垃圾桶图标）同源。用纯文字 + chevron 的行。

**空状态**：没有可导出的真实记录时，数字格显示 0，两个动作行禁用并置灰
（`onTap: null` + 显式降级文字颜色），补一句「暂无可导出的记录」。
若被排除的演示记录大于 0，同时保留「已排除 N 条演示记录」，让用户明白数据不是丢了。

**失败**：写临时目录或分享抛错时，走 `app_toast.dart` 如实报错，不谎报成功。
`ShareOutcome.dismissed`（用户取消了分享面板）**不算失败**，不弹任何提示——那是正常操作。

### 设置页入口

在现有「睡眠数据导入」区块**之后**新增一个 section「睡眠数据导出」，
内含一行 → `/settings/export`。

**不动现有的小米区块**：它用 `IosListGroup` 的 group 级 `onTap` 实现整行可点，
把导出行塞进同一个 group 会让整组都变成跳转到导入页。

## 提醒

### 分层

`core/platform/reminders.dart`，与 `haptics.dart` 同层——平台能力的薄封装，不放在 feature 下。

```dart
enum ReminderPermission { granted, denied, unsupported }

/// 当前生效的提醒计划。`null` 表示该项关闭。
class ReminderPlan {
  const ReminderPlan({this.bedtimeMinutes, this.wakeMinutes});
  final int? bedtimeMinutes;
  final int? wakeMinutes;
}

/// 一条通知请求。`minutesOfDay` 是距本地午夜的分钟数。
class ReminderRequest {
  const ReminderRequest({
    required this.id,
    required this.minutesOfDay,
    required this.title,
    required this.body,
  });

  final int id;
  final int minutesOfDay;
  final String title;
  final String body;

  int get hour => minutesOfDay ~/ 60;
  int get minute => minutesOfDay % 60;
}

/// 抽象**类**而不是接口：`sync` 的幂等算法写在基类里，子类只提供两个原子动作。
abstract class ReminderScheduler {
  static const bedtimeId = 9001;
  static const wakeId = 9002;

  /// `plan` 要求存在的那组通知。纯函数，因此调度契约可单测。
  static List<ReminderRequest> requestsFor(ReminderPlan plan) { /* … */ }

  Future<void> initialize();
  Future<ReminderPermission> permission();
  Future<ReminderPermission> requestPermission();
  Future<void> openSystemSettings();

  @protected
  Future<void> cancel(int id);

  @protected
  Future<void> schedule(ReminderRequest request);

  /// 幂等的全量重排：先取消两个固定 id，再按计划排入。
  Future<void> sync(ReminderPlan plan) async {
    await cancel(bedtimeId);
    await cancel(wakeId);
    for (final request in requestsFor(plan)) {
      await schedule(request);
    }
  }
}
```

**为什么是抽象类而不是接口。** 幂等重排是这一块唯一容易写错、也最值得单测的逻辑。
把它放在基类、让子类只实现 `cancel` / `schedule` 两个原子动作，测试就能用一个
「记录调用序列」的假子类**测到真代码**——而不是碰平台通道、或者去测一个假实现自己。
写成接口的话，每个实现都得把这段算法抄一遍，于是它既测不到、又会各自漂移。

两个实现：

- `LocalReminderScheduler` —— 包 `flutter_local_notifications`
- `NoopReminderScheduler` —— Web 与测试用，`permission()` 返回 `unsupported`，其余是空操作

`reminderSchedulerProvider` 默认按平台选择，`main.dart` 里覆盖成具体实例
（与 `databaseProvider` 的处理方式一致）。测试覆盖成 `NoopReminderScheduler`
或一个记录调用的假实现。

### 幂等 sync

**`sync` 是全量重排，不是增量。** 固定两个通知 id：

```dart
const kBedtimeNotificationId = 9001;
const kWakeNotificationId = 9002;
```

`sync` 先 `cancel` 这两个 id，再按 plan 重新 `zonedSchedule`。触发点三处：

1. 提醒开关变化
2. 提醒时间变化
3. **每次应用启动**（`main()` 里 fire-and-forget）

第 3 条不是冗余。时区变更、系统清理已调度通知、重装、以及用户从系统设置里关掉再打开权限，
都会让「已调度的通知」与「数据库里的偏好」脱节。全量重排 + 启动时重排，
让两边**没有独立的生命周期**，从而不存在漂移。这类「开关说开着、其实不会响」的 bug
是这一块最难查的，与其加检测不如让它不可能发生。

启动时重排是 fire-and-forget：通知排不上不影响应用可用，失败只记不报。

### 权限流程

打开开关时按实际结果分岔：

| `requestPermission()` 返回 | 行为 |
| --- | --- |
| `granted` | 写入偏好（`bedtimeReminderEnabled` / `wakeReminderEnabled` = true）→ `sync` |
| `denied` | **不写库**，开关回弹到关，toast 说明原因 |
| `unsupported` | **不写库**，开关回弹到关，toast 说明本平台不支持 |

「不写库」是这一节的关键：规格要求「拒绝时设置状态与实际能力一致」。写一个开着但不会响的
偏好，就是在设置里留一个假状态。

**启动时的回收。** 偏好为真只可能来自一次成功授权，所以「偏好为真 + 当前权限不是 granted」
只可能是用户在系统设置里**撤销**了授权。启动时 `sync` 之前先查权限，遇到这种情况就把
两项偏好写回 `false`，界面上的开关随之回到关闭态并显示「去系统设置」那一行。

不这么做，撤销授权后应用会进入一个更糟的状态：开关看着是开的、设置里也写着开着，
而实际上永远不会响——这正是本轮要消灭的那类假状态，只是换了个入口进来。
回收之后用户想恢复，重新打开开关即可，代价是一次点击。

**「去系统设置」入口的显隐——无状态方案。**
插件在 Dart 侧只暴露 `checkPermissions().isEnabled`，**不区分「从未询问」与「已被拒绝」**
（实测：iOS 与 macOS 的原生实现都把 `authorizationStatus` 归约成了几个布尔量）。
要在 Dart 侧区分，就得在 `AppSettings` 加一列、把 schema 升到 v3、再写一次迁移测试——
为一个入口的显隐付一次数据库迁移不划算，而且这个标志位一旦与真实权限漂移就会说谎。

所以：**只要 `permission() != granted`，就在「提醒」区块下方渲染一行说明与可点的
「去系统设置」**，文案中性、不预设历史：

> 未获得通知权限。提醒开关打开后若收不到通知，请到这里允许「夜深」发送通知。

这样在任何历史下说的话都是真的，也不需要任何持久化状态。

`permission()` 的查询结果放进一个 `FutureProvider`，开关操作完成后 invalidate 它。

### 通知内容

| id | 时刻 | 标题 | 正文 |
| --- | --- | --- | --- |
| 9001 | `bedtimeReminderMinutes` | 到就寝时间了 | 该休息了，晚安。 |
| 9002 | `wakeReminderMinutes` | 早上好 | 记录一下昨晚睡得怎么样。 |

正文不写具体时长或目标值：那需要在通知里读取记录与设置，而通知内容在排版上只有一两行，
塞进数字反而难读。文案也不做任何医疗或健康承诺。

调度用 `matchDateTimeComponents: DateTimeComponents.time`，即每天在同一个**墙上时间**重复。

iOS/macOS 用 `DarwinNotificationDetails(presentAlert: true, presentBanner: true,
presentList: true, presentSound: true)`——前台收到时也要展示，否则应用开着就什么都看不到。

Android 用 `AndroidScheduleMode.inexactAllowWhileIdle`。
**刻意不用精确闹钟**：精确闹钟在 Android 14+ 需要 `SCHEDULE_EXACT_ALARM`（多一个权限申请流程）
或 `USE_EXACT_ALARM`（上架需审核），而「该睡了」这个提醒差几分钟完全无所谓。
用 inexact 换掉一整个权限分支是划算的。通知渠道 id `night_sleep_reminders`，名称「睡眠提醒」。

### 平台接线

| 平台 | 改动 |
| --- | --- |
| iOS | `ios/Runner/AppDelegate.swift` 的 `didFinishLaunchingWithOptions` 里加 `UNUserNotificationCenter.current().delegate = self`——不加则前台不展示通知。**不改 `Info.plist`**：本地通知的权限由 `UNUserNotificationCenter` 在运行时申请，不需要 `NS*UsageDescription` 键 |
| macOS | 同上，`macos/Runner/AppDelegate.swift` |
| Android | `AndroidManifest.xml` 加 `RECEIVE_BOOT_COMPLETED` 权限、`ScheduledNotificationReceiver` 与 `ScheduledNotificationBootReceiver` 两个 receiver。`POST_NOTIFICATIONS` 与 `VIBRATE` 由插件自己的 manifest 合并进来，不必重复声明。**当前不构建 Android，但一次性补齐**——留着不补，将来构建出来的就是一个「开关看着有效、实际不响」的包 |

不为通知申请任何新权限的 `Info.plist` 文案，这与规格 §7「未接入的能力不得申请权限」一致：
通知是**本轮接入**的，麦克风不是。

### 时区

`main()` 里在初始化调度器时：

```dart
tz.initializeTimeZones();
tz.setLocalLocation(tz.getLocation(await FlutterTimezone.getLocalTimezone()));
```

`initializeTimeZones()` 之后 `tz.local` 默认是 UTC，必须再设一次。取不到设备时区名时
`initialize()` 抛错，调度器退化为 `unsupported`，「去系统设置」那行按上表如实渲染——
不猜一个时区，也不在错误的时刻响。

## 测试

沿用项目现有的测试口径：**能纯测的纯测，碰平台的用 provider override 隔离，不订阅 drift 的
`watch*` 流**（FakeAsync 的假时钟不推进，拆解时留 pending timer）。

| 类型 | 场景 | 落点 |
| --- | --- | --- |
| 单元测试 | CSV：列序、BOM、CRLF、备注转义（逗号/引号/换行）、阶段中文标签、空集结构完整 | `test/sleep_export_test.dart` |
| 单元测试 | JSON：表头字段、字段名与 schema 对齐、`stages`/`soundClips`/`tags` 恒为数组、`insight` 为 null、不写派生值、**输出里搜不到 `localUri` 与任何文件路径** | 同上 |
| 单元测试 | 演示数据排除：`excludedDemoCount` 正确、演示行不出现在文件里 | 同上 |
| 单元测试 | 文件名与 `exportedAtUtc` 随传入的 `now` 变化（确定性） | 同上 |
| Widget 测试 | 导出页条数统计正确；无真实记录时数字为 0、两个动作禁用 | `test/export_page_test.dart` |
| Widget 测试 | 点「导出 CSV」→ 假 sharer 收到 2 个文件且内容正确；「导出 JSON」→ 1 个 | 同上 |
| Widget 测试 | 分享失败弹 toast；`dismissed` 不弹 | 同上 |
| Widget 测试 | 提醒开关：`denied` 时开关回弹且**数据库未被写入**；`granted` 时写入并按传入的 `ReminderPlan` 重排；`unsupported` 时同样不写库 | `test/reminder_settings_test.dart` |
| Widget 测试 | 权限不是 granted 时出现「去系统设置」入口且可点；已授予时不出现 | 同上 |
| 单元测试 | `sync` 幂等：连续两次调用产生相同的调度序列；空计划只取消不排入；`requestsFor` 只把开着的提醒变成请求 | `test/reminder_scheduler_test.dart` |

**不测**：真实通知投递、分享面板本身、iOS/macOS 前台展示行为。这些需要真机或模拟器人工验证，
结果记入 README 的「未验证」项，不写成已完成。

**「改提醒时间触发 `sync`」不单独做 widget 测试。** 它走的是与开关同一条 `_syncReminders`
路径，而单独测它要先驱动滚轮选择器（打开弹层、滚动、提交），成本明显高于它多覆盖的那一点。
这条路径的正确性由「开关时传入的 `ReminderPlan` 正确」那一例代表。

## 需同步更新的其他文档

| 文档 | 改动 |
| --- | --- |
| 规格 `2026-09-28-night-sleep-design.md` | §2.4 页面加导出页；§3 路由加 `/settings/export`；§4 M2 两项标为已完成、补导出与提醒的实现口径；§6 技术方案补四个依赖与「仍只有一处对外请求」；§8 新增两条偏差（**#18** 原型无导出，交付方式与文件形态自定；**#19** 原型的提醒开关是纯装饰，本实现接真实通知且权限被拒时不写库）；§9 测试矩阵补场景；§10 去掉已解决项。版本记入 `CHANGELOG.md` |
| `README.md` | 「未实现」表划掉两项；「当前实现范围」补导出与提醒；「验证记录」补本轮实跑结果与**未验证**项（真实通知投递、分享面板实测） |
| `CHANGELOG.md` | 新增一条版本记录 |

## 风险与已知问题

**风险：macOS 上通知需要应用被签名/位于 `/Applications` 才能稳定授权。**
本机调试构建未签名（见 README「真机安装」），通知权限可能拿不到或不持久。
这属于环境问题而非实现问题，按上表如实降级（`permission()` 返回非 granted 时界面照实显示），
并记入 README 未验证项。

**已知问题（本轮不修）：应用版本号没有单一来源。**
`pubspec.yaml` 是 `0.1.0+1`，设置页「关于」卡片硬编码 `v2.0.0`，两者对不上。
本轮导出文件的表头因此**不写 `appVersion`**，只写 `format` / `version` / `schemaVersion`——
为一个字段引入 `package_info_plus` 不划算，而写死一个可能不对的版本号比不写更糟。
统一版本号来源是独立的一件小事，另行处理。

**风险：`sync` 在应用启动时 fire-and-forget，抛错会被吞掉。**
这是有意的：排不上通知不该挡住应用启动。代价是失败静默，只能靠「去系统设置」那行的显隐
间接反映权限侧的问题。可接受。

## 验收方式

1. `dart format .`、`flutter analyze` 无问题。
2. `flutter test` 全绿，且新增测试文件的用例数记入 README。
3. `flutter build macos --debug` 与 `flutter build ios --simulator --no-codesign` 成功
   （证明新插件的原生接线没破坏构建）。
4. 手工核对：设置页点进导出页，条数与首页记录数一致；导出的 CSV 用带 BOM 的十六进制头
   （`EF BB BF`）确认；JSON 用 `grep` 确认不含 `localUri`、不含任何绝对路径。
5. 手工核对：开关提醒并授予权限后，`pendingNotificationRequests()` 能查到 9001/9002
   （在调试构建里临时打一条日志确认，不留代码）。
6. 不通过构建来声称通知投递、分享面板、小米导入已完成——三者都需要真机人工确认。
