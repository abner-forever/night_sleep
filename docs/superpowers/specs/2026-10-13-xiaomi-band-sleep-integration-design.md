# 小米手环睡眠数据接入可行性设计

日期：2026-10-13
档位：**spec + plan**（新能力、新架构、影响产品语义）——**但本轮只结「可行性判定」这一层**，
实现计划等路径定案后另开（见 §八）。本文因此没有配套 plan。
状态：**判定已出，路径未定案。本轮不实现任何导入。**

上游规格：

- 总规格 `2026-09-28-night-sleep-design.md` §8 偏差 #4（不猜小米导入字段）、
  §9 测试矩阵、**§10 第 2 条**（需真实导出样本或官方接口文档）；
- `2026-09-28-export-and-reminders-design.md` §「不动现有的小米区块」；
- `2026-10-03-night-audio-recording-design.md`（鼾声/梦话只从录音来）。

总规格 §10 第 2 条从立项起就写着「需真实导出样本或官方接口文档」，`sleep_import_page.dart`
因此一直禁用、`README.md` 的「未实现」表里那一行也一直是「未接入」。本文结的是这笔账的
**上半截**：回答「那个真值从哪条管道进来」，并给出四条候选路径的真机实测取舍。

**本轮不写适配器、不启用导入按钮、不引入任何蓝牙依赖、不接小米账号。**
没做的事一律进 §九「未验证」，不得在文档或界面里被写成已完成——这是总规格 §8 立的规矩。

---

## 一、目标

一句话验收：**判定「小米手环 9 NFC 的睡眠阶段数据能否、以何种代价进入『夜深』」，落成
可执行的路径与取舍。**

交付物是**判定**，不是能力。判据 = 真机实测 + 公开资料交叉核对，两者都带出处，
且**实测优先于公开资料**（§三 有两处就是这么订正的）。

## 二、非目标（本轮不做，且已逐条记进 README「未实现」）

| 不做的事 | 为什么这一轮不做 | 留在界面上的是什么 |
| --- | --- | --- |
| **实现任何导入适配器** | 路径未定案，且四条路的字段可信度差别很大（§五） | 导入页保持禁用，文案仍是「适配器待接入」 |
| **启用「导入睡眠记录」按钮** | 偏差 #4 一字未改：拿到真实样本或官方字段说明之前不得猜测字段或伪造成功 | 按钮仍然禁用，点得动但只在本页给一句解释 |
| **引入蓝牙 / BLE 依赖** | 见 §四，BLE 路径已实测为不通 | 无 |
| **接入小米账号**（云端取数） | 合规未定（§六），且国行密码登录已被风控打死 | 无 |
| **申请小米开放平台权限** | 需要主体资质，不是本轮能定的事 | 无 |

## 三、环境事实（本轮真机实测）

真机：Xiaomi MI 9（`cepheus`，adb serial `e0e60672`），
**Android 11（API 30）/ MIUI 12.5.6 / arm64-v8a**。
设备：小米手环 9 NFC。判据一律是 `adb shell dumpsys bluetooth_manager` /
`adb shell pm list packages` 的原始输出。

| # | 事实 | 判据 |
| --- | --- | --- |
| 1 | 国行版小米运动健康的包名是 **`com.mi.health`**（v3.59.1），**不是** `com.xiaomi.wearable` | `pm list packages` 只有 `com.mi.health`；`/sdcard/Android/data/com.mi.health/files/log/` 下确有 `XiaomiFit.device.log`、`XiaomiFit.main.log`、`Transfer.device.log` |
| 2 | 设备名是 **`Xiaomi Smart Band 9 9EEF`**，**名字里没有 "NFC"** | `Bonded devices:` 行 |
| 3 | 手环是 **DUAL（双模）**，且 SDP 暴露 **`00001101`（Serial Port Profile）**、`00001124`（HID — 快门/媒体控制）与小米自定义 `cc353442-be58-4ea2-876e-11d8d6976366` | 同一段里的 `Service = …` 行 |
| 4 | **小米运动健康在 Android 上走经典蓝牙传数据**：`Connection Events` 里只有一条 `21:57:12 CLASSICAL-CONNECTED … status = Success`，**没有任何 `LE-CONNECTED`**；且 `GATT Client Map` → `Entries for mApps: 0`，无任何 App 持有 GATT 连接 | 同上 |
| 5 | 配对过程不顺：21:54 连挂两次（`BONDING → NONE`），21:57:10 第三次才 `BONDED` | `Bond Events` 段 |

BLE 侧只被用来**扫描发现**：`com.mi.health` 做了 9 次 LE 扫描、7244 条结果，连上之后即转入
RFCOMM。**这是本文最重要的一条实测**——它把「用 Flutter 的 BLE 插件直连手环」从「难」判定为
「不通」。

### 3.1 对公开资料的两处订正

1. **包名**：Gadgetbridge 官方文档与中文社区所有取密钥教程一律写
   `/sdcard/Android/data/com.xiaomi.wearable/files/log/`——那是**国际版** Mi Fitness 的包名。
   国行机器上该目录不存在，**照抄必失败**。本机实测路径是 `com.mi.health`。
2. **NFC 版会不会被 Gadgetbridge 认出来**：我在调研阶段推测「设备名带 NFC，
   Gadgetbridge 的正则 `^Xiaomi Smart Band 9 [0-9A-F]{4}$` 匹配不到」。
   **实测推翻**：手环广播名就是 `Xiaomi Smart Band 9 9EEF`，不带 "NFC"，正则能匹配。

### 3.2 BLE 侧探测：三轮，均未成功

第 4 条只说清了「官方 App 在 Android 上不用 BLE」。为了判定**手环的 BLE 侧到底开不开
GATT 协议通道**，另外写了一个一次性探针 APK（`aapt2` + `javac` + `d8` + `apksigner`
手搓，不走 gradle、不进本仓库），装到同一台机器上跑。**三轮全部失败**，且失败原因本身是结论：

| 轮次 | 做法 | 结果 |
| --- | --- | --- |
| 1 | BLE 扫描，找名字以 `Xiaomi Smart Band` 开头的设备 | **0 条扫描结果**，连周边的设备都没有 |
| 2 | 按已知 MAC 直连（跳过扫描） | 20 秒超时，`onConnectionStateChange` **完全没触发** |
| 3 | 先 `force-stop com.mi.health` 让手环空出来，扫描 15 秒 + 直连兜底 | 扫描仍是 0 条；直连仍超时 |

**原因一：手环与手机保持经典连接时，BLE 侧不广播。** 第 3 轮抓取窗口内，协议栈确实在处理
别的 BLE 设备的广播包（`54:48:e6:ec:60:03` / `7c:c2:94:17:79:db` / `ac:8c:46:26:a3:00`），
但手环地址 `08:16:d5:73:9e:ef` 在广播里出现 **0 次**。直连那一侧协议栈是受理了的
（`clientConnect() address=08:16:d5:73:9e:ef, isDirect=true, phy=1`），拿不到回应只能是因为
对端不在广播。

**原因二：MIUI 把 BLE 扫描结果对第三方 App 屏蔽。** 协议栈的扫描统计里，探针那条是
`Total number of results: 0`，而同一时间协议栈明明在处理别人的广播包。`adb install -g`、
`pm grant`、`cmd appops set`（含 `--uid`）都没能解开——`COARSE_LOCATION` 的
**Uid mode 始终是 `ignore`**。这是本机 ROM 层面的限制，与探针代码无关。

> **对将来任何蓝牙相关工作的含义**：在这台 MIUI 12.5.6 上，**第三方 App 的 BLE 扫描拿不到
> 结果**，除非绕开 MIUI 自己的权限管理（用户手动在系统设置里授予「定位」等）。
> 这条与探针无关，是本机环境事实。

顺带确认：`btif_get_device_type: Device [08:16:d5:73:9e:ef] type 3`——协议栈配置里它就是
**DUAL**，与 §三 第 3 条一致。

**结论：GATT 枚举没做成。** 手环 BLE 侧是否开放 miwear 协议通道，**仍然未知**（见 §九）。
要把这个问题问到底，得让手环脱离连接态（解绑）**并且**绕过 MIUI 的扫描屏蔽——
而「解绑之后手环是否就会在 BLE 侧广播」**本身也没验证过**，所以这一步连能不能成功都不确定。
（解绑不是不可逆的：它会让当前那把密钥作废、需要重新配对取新的，**手环本身不会锁死**，
本段先前写成「不可逆」是错的，2026-10-13 订正。）
**这些代价叠加起来超过了这个问题本身的价值。**

## 四、四条候选路径

| 路径 | 能拿到睡眠阶段？ | 代价 | 判定 |
| --- | --- | --- | --- |
| **① 自己写 Dart 协议栈直连** | 理论上可以 | 见下 | ❌ **实测已判死**（Android 侧）|
| **② Gadgetbridge 转发** | ✅ 设备实测的阶段（阈值解码） | 装 Gadgetbridge + 一次性密钥 | ⭕ **投入产出比最高** |
| **③ 小米云私有 API** | ✅ 最全：日汇总的深/浅/REM/清醒时长 + 逐段 `items[]` | 存账号凭据；协议风险 | ⚠️ 仅个人自用，**不得随应用分发** |
| **④ 官方开放平台** | ✅ 有正式字段文档 | 需主体资质 | ⏸️ 唯一「有据可依」，但门槛不在技术 |
| ~~系统健康库（Health Connect / Apple Health）~~ | ❌ 只有一整段睡眠 | 低 | 拿不到阶段，**不值得建管道** |

### 4.1 ① 为什么判死

小米手环 9 从上一代的 GATT 特征值通信**换成了经典蓝牙 SPP（RFCOMM）**
（Gadgetbridge PR #4118 原文："the Xiaomi Smart Band 9 was found to have switched from
characteristics communication … to SPP communication"）。§三 第 3、4 条在真机上确认了这一点。

由此：

- `flutter_blue_plus` / `flutter_reactive_ble` / `universal_ble` **全是 BLE-only**，
  `flutter_blue_plus` 的 README 原文写着 "❗ Bluetooth Classic is not supported ❗"。
  要在 Android 上碰它，必须先写 platform channel 把 RFCOMM 拉出来。
- **iOS 上第三方 App 没有 RFCOMM**（只能走 MFi/ExternalAccessory），这条路在 iOS 直接封死。
- 即便拉通了传输层，睡眠数据是 **MASS 分块文件下载（通道 5）+ 手写二进制解码**，
  而 Gadgetbridge 官方文档至今把 "Sleep stages (deep, rem)" 列在 **Missing** 里，
  `SleepStagesParser.java` 里好几个字节仍标着 `unknown`。
- **Dart/Flutter 生态里 miwear 协议的实现数量是零。** 已知参考实现只有
  Gadgetbridge（Java）、AstroBox-NG（Rust + 公开的 `.proto`，AGPL-3.0 + 强制署名）、
  以及一个 C# 移植。从零移植并按固件更新维护，工作量以月计。

**结论：不值得。** 这条不是「难」，是「即便做成，维护成本也压过收益」。

### 4.2 ② Gadgetbridge 转发 —— 推荐

Gadgetbridge 已经把这套经典蓝牙 + miwear 协议栈 + 睡眠解码全做好了（它是 Java 的成熟实现），
并且能**自动导出数据库**（设置 → 自动化 → 自动导出数据库），导出到用户可访问的目录。
「夜深」只需要用 SAF 读那个 SQLite。

- **优点**：不碰小米账号、不需要 root、阶段来自设备真实测量。
  §三 第 2 条已确认本机设备名能被 Gadgetbridge 的设备正则匹配。
- **代价**：装了 Gadgetbridge 就**不能同时用小米运动健康**（两者抢配对）。
- **待验证**：Gadgetbridge 对标准版（非 Active）手环 9 的睡眠阶段今天是否真的解得出来——
  官方文档说 Missing，但 `SleepStagesParser` 与相关修复提交已经存在，**状态是"部分且在动"**。
  这一条必须用真机跑一遍才算数（§九）。

### 4.3 ③ 小米云私有 API

`hlth.io.mi.com/app/v1/…`，国行账号可用，能拿到 `sleep` 记录：日汇总里有
`sleep_deep_duration` / `sleep_light_duration` / `sleep_rem_duration` / `sleep_awake_duration`，
原始 `sleep` 记录的 `value.items[]` 还带逐段的 `{start_time, end_time, state}`。

- **优点**：数据最全，且不需要额外 App、不需要经典蓝牙。
- **代价与风险**：需要保存用户的小米账号凭据；**国行密码登录已被风控打死**，
  只能走扫码/浏览器交握；登录常态化触发验证码（错误码 `87001`），失败多了会临时封号。
  小米账号使用协议 §2.2.4 写的是「未经小米同意，您直接或间接授权第三方使用您小米账号
  或获取您账号项下信息的行为无效」。
- **判定**：**仅个人自用**可以接受；**不得作为发布版特性**随应用分发。

### 4.4 ④ 官方开放平台

小米澎湃 OS 开发者平台（`dev.mi.com`）的「运动健康数据服务」，数据类型里确有
**`com.xiaomi.sleep.health`（睡眠记录）**，字段有正式文档——**这正是总规格 §10 第 2 条
要的「官方授权接口文档」**。

但两个门槛：

- **客户端 SDK 要求 HyperOS 4.0+**。本机是 MIUI 12.5.6 / Android 11，**跑不了**。
- 服务端订阅式接入历史上写着「只对小米生态链企业及合作伙伴正式开放」，
  个人开发者能否过审**未证实**。

**判定**：唯一同时满足「真实」与「有据可依」的路，但门槛是资质而非技术。
**值得先花一次尝试去申请**——申请结果本身就是一条信息。

## 五、红线：阶段映射现在是有毒的

**拿到阶段 ≠ 拿到可信的阶段。** 这一节是本文对总规格偏差 #10
（阶段环只在确有阶段数据时出现）最直接的影响。

小米自家文档就前后矛盾：服务端页写 `2=深睡 3=浅睡 4=REM 5=清醒`，
客户端 SDK 页写 `0=清醒 1=浅睡 2=深睡 3=REM 4=离床`，时长单位一处说分钟一处说秒。

更麻烦的是**当前最流行的几个开源实现映射是错的**：

- `flyice-juin/mi_fitness_cn` 与上游 `batareya16/MiFitnessHass`：**深/浅睡写反**；
- `binglua/mi-fitness-mcp-cn` 与 `HUAYUE1024/mi-fitness-mcp-cn`：**REM/清醒写反**；
- 修对的是 `shkyyy18/mi_fitness_data_bridge`（2026-09-23 改），依据是「社区从四条国区记录反推」。

**Gadgetbridge 那条也不干净**：它解小米阶段用的是设备私有的 `RAW_KIND` 值加阈值猜测
（`raw & 127`，`rem > 55` → REM、`deep > 42` → 深睡），官方 wiki 自己承认这套映射
「尚未完全文档化」。

**因此立一条硬要求**：任何一条路径落地时，**必须拿同一晚的数据跟小米运动健康 App 的画面
逐段对齐验证**，对不上就不许渲染。否则就是拿一个可能是错的映射，去画应用里最显眼的那个环——
这正是偏差 #10 要防的事。

## 六、合规

- 官方开放平台（④）是唯一能名正言顺写进产品的路。
- 私有云 API（③）只能个人自用。**随应用分发等于替他人获取账号数据**，
  而小米账号协议明确说此类授权「无效」。
- Gadgetbridge 转发（②）不涉及小米账号，合规上最干净；但 Gadgetbridge 对 miwear 的
  参考实现在 AstroBox 一侧是 AGPL-3.0 + 强制署名——**只读作参考、自己重写**是稳妥做法。

## 七、密钥这件事的记录

所有非云端路径（①②）都卡在同一把钥匙上：手环的配对密钥（`encryptKey`）。
它从小米运动健康的日志里取（§三 第 1 条的路径），或者由小米账号云端下发。

**2026-10-13 使用方裁定：暂不提取。** 本轮只做零风险的传输层实测。
这把密钥等于手环数据链的钥匙，这跟「扫一下广播包」不是一个量级的动作。

**代价到底在哪（本节 2026-10-13 订正过，原先写的「不可逆」是错的）**：

- **不是「不可逆」。** 解绑手环会让**当前那把密钥作废**、需要重新配对拿新的；
  恢复出厂还会换掉蓝牙 MAC。**手环本身不会锁死，随时可以重新绑回小米运动健康。**
  Gadgetbridge 官方流程的关键恰恰是「**配对取到密钥后不要解绑**，直接卸载/停用官方 App」
  ——踩的坑是「先解绑再卸载」，那样密钥就白取了。
- **真正的代价是共存性**：Gadgetbridge 与小米运动健康**不能在同一台手机上共存**（抢连接）。
  走 Gadgetbridge 就等于放弃小米运动健康这条日常通路。
- **另有一个已知缺陷**：解绑或恢复出厂后，Mi Fitness 有时**不把新密钥写进日志**
  （中文社区报告的 App 缺陷，非官方），需删日志或重装 App 再连一次才能重新取到。
  这才是「重新来一遍」真正烦人的地方。

（本轮曾尝试扫描该字段是否存在于日志中，被权限分类器拦下两次，理由正是「使用方批准的是
nRF Connect 侦察，不是从厂商 App 私有数据里提取凭据」。**拦截是对的，记录在此**，
以免下一轮有人以为那一步已经做过。）

## 八、推荐与下一步

**优先级：② Gadgetbridge 转发 > ④ 官方平台申请 > ③ 云 API（仅自用）> ① 自己写（不做）。**

下一步按顺序做，每一步都能独立否决后面的：

1. ~~**测 GATT**~~ **已尝试，未成功**（§3.2）。结论是：在手环与手机保持绑定的前提下问不出答案——
   手环在经典连接态下不在 BLE 侧广播，而 MIUI 又屏蔽第三方 App 的扫描结果。
   **继续追的代价（解绑手环 / 换设备）超过这个问题本身的价值**，因此**建议就此搁置**：
   反正 §4.1 已经判死，BLE 侧开不开都不改变 Android 方案。
2. **验 Gadgetbridge 对标准版手环 9 的睡眠解码**——它今天到底解不解得出深睡/REM。
   这条决定 ② 是否成立。
3. **试申请官方开放平台权限**——结果本身就是信息。

三条都跑完，才谈实现计划。**本文是活文档：路径定案后原地更新，不新开文件。**

## 九、未验证（本轮没做的事，不许当成已完成）

- **GATT 枚举没做成**（三轮尝试，见 §3.2）——手环 BLE 侧是否开放 miwear 协议通道
  **仍然未知**。已确证的只有：Android 官方 App 不用 BLE 传数据（§三 第 4 条）、
  手环在经典连接态下不在 BLE 侧广播、以及 MIUI 屏蔽第三方 App 的扫描结果。
  **「标准版 9 的 BLE 侧开着还是关着」这个判断本身仍是推断。**
- **没有提取配对密钥**（§七），因此**没有任何一条路径被真机跑通过**。
- **小米云 API 没有实测**——§4.3 的端点、字段、错误码全部来自公开项目与文档，
  置信度「很可能」而非「已确认」，且**多个流行实现的阶段映射是错的**（§五）。
- **官方开放平台没有申请**——`com.xiaomi.sleep.health` 存在与 HyperOS 4.0+ 门槛来自官方文档，
  但**个人开发者能否过审未证实**。
- **Gadgetbridge 未安装、未试连**——§4.2 的可行性基于其官方文档与源码，非本机实测。
- **Health Connect / Apple Health 只有时长、没有阶段**这一条来自第三方整合文档与用户实测，
  置信度「很可能」；且国行设备+国行账号疑似被区域锁挡在 Health Connect 之外，**未证实**。
- **手环睡眠数据与手机录音的时钟对齐没碰**——那是实现阶段的事。

## 十、对总规格的影响

- **§10 第 2 条「小米睡眠数据的真实导出文件样本或官方授权接口文档」——本条不关闭。**
  本轮把「从哪条管道进来」这件事查清了（本文），但**样本与官方文档仍未拿到**。
  参照 §10 第 3 条（助眠音效授权）的写法记一笔「部分进展」，**不关闭**。
- **§8 偏差 #4「不猜小米导入字段」——一字未改。** 导入按钮仍然禁用。
  本文反而给这条红线加了新依据：§五 证明「有字段可读」和「字段含义可信」是两件事，
  照抄现有开源实现会画错。
- **§8 偏差 #10「阶段环只在确有阶段数据时出现」——不变，但多了一条约束**：
  将来任何导入器写入阶段前，必须先做 §五 那条逐段对齐验证。
- **§9 测试矩阵——本轮无新增用例**（未改任何 Dart 代码）。

## 十一、出处

**真机实测**（§三、§七）：

- `adb shell dumpsys bluetooth_manager`、`adb shell pm list packages`、
  `adb shell ls /sdcard/Android/data/com.mi.health/files/log/`，
  2026-10-13，机 `e0e60672`。

**公开资料**（§四–§六，按引用顺序）：

- [Gadgetbridge PR #4118 — Xiaomi: add support for SPPv2 packet protocol](https://codeberg.org/Freeyourgadget/Gadgetbridge/pulls/4118)
- [Gadgetbridge issue #3930 — Xiaomi Smart Band 9（RE 主线，含 GATT 是否关闭的未决问题）](https://codeberg.org/Freeyourgadget/Gadgetbridge/issues/3930)
- [Gadgetbridge — Xiaomi protobuf 支持状态（Sleep stages 列为 Missing）](https://gadgetbridge.org/basics/topics/xiaomi-protobuf/)
- [Gadgetbridge issue #6101 — Export sleep stages and HRV to Health Connect（未实现）](https://codeberg.org/Freeyourgadget/Gadgetbridge/issues/6101)
- [Gadgetbridge — Huami/Xiaomi 服务端配对](https://gadgetbridge.org/basics/pairing/huami-xiaomi-server/)。
  **同时也是 §七 那处订正的出处**：官方流程写的是「配对取到密钥后**不要解绑**，直接卸载/停用
  官方 App」，以及「每次解绑都会使密钥失效」。另注意该页写的包名是国际版 `com.xiaomi.wearable`，
  国行机器上是 `com.mi.health`（见 §3.1）。
- [AstroBox-NG-Module-Pb — 公开的 miwear `.proto` 定义](https://github.com/AstralSightStudios/AstroBox-NG-Module-Pb)
- [shkyyy18/mi_fitness_data_bridge — 修正过的阶段映射](https://github.com/shkyyy18/mi_fitness_data_bridge)
- [flyice-juin/mi_fitness_cn](https://github.com/flyice-juin/mi_fitness_cn) 与 [binglua/mi-fitness-mcp-cn](https://github.com/binglua/mi-fitness-mcp-cn)（**两个映射写反的例子**）
- [小米澎湃 OS 开发者平台 — 业务介绍](https://dev.mi.com/xiaomihyperos/documentation/detail?pId=2325) / [客户端接入指南](https://dev.mi.com/xiaomihyperos/documentation/detail?pId=2332)
- [小米账号使用协议](https://static.account.xiaomi.com/html/agreement/user/zh_CN.html)
- [flutter_blue_plus（README 明写不支持 Bluetooth Classic）](https://github.com/chipweinberger/flutter_blue_plus)
- [Health Connect 可用性（Android 9+，13 及以下为独立 APK）](https://developer.android.com/health-and-fitness/health-connect/availability)
