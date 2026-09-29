# 修复轮设计（2026-09-29）

> 日期：2026-09-29
> 状态：已完成（2026-09-29 实现并验证；实际结果与偏离见文末「实际结果」）
> 范围：用户实机巡检上报的 6 个问题 + 4 项附带发现
> 设计基准：[夜深项目规格说明书](2026-09-28-night-sleep-design.md)。本文受其第 8 章产品红线约束，
> 且**要修订其中一条偏差**（见「规格改动清单」）。

## 问题来源

用户在一轮实机使用后上报 6 条。逐条调查后确认：**其中 4 条是缺陷**（根因均可定位到具体代码行），
**2 条是改动请求**（其中一条直接冲突规格偏差 #12）。调查期间另发现若干连带问题，一并记入。

调查过程中在**本机两个真实数据库**上取证（只读查询，未写入）：

| 库 | 记录 | 洞察 | schema | 状态 |
| --- | --- | --- | --- | --- |
| macOS 桌面（`~/Library/Containers/com.example.nightSleep/`） | 5（全部 `demo`） | 5 | v2 | 正常 |
| iOS 模拟器（`~/Library/Developer/CoreSimulator/Devices/35ED39A8-…/`） | **0** | **5** | v2 | **已损坏** |

两库的对比本身即问题 #2 的物证，详见该条。

---

## 1. 顶部渐变与安全区割裂（缺陷）

### 现象

一级页滚动超过 12px 后顶部的渐变带，在**状态栏/刘海那段安全区**与安全区下方之间有一条硬分界。

### 根因（已确认）

`app.dart:130` 的 `SafeArea(bottom: false)` 把整个 `AppShell`（连同 `TopFade`）整体下移了 `safeTop`。
`TopFade` 的 `y = 0` 是 Stack 的顶，而那个 Stack 此时已经下移到安全区下沿。

- `top_fade.dart` 全文**没有任何 `MediaQuery` / `padding` / `SafeArea`**——渐变带不知道安全区的存在。
- 状态栏区间 `[0, safeTop]` 因此**完全没有渐变带**（既无填充也无模糊），露的是 `Atmosphere` 背景。
- 带内填充渐变的**第一个停点是满值 92% alpha**，起点正好落在安全区下沿。

于是边界处出现 `0 → 0.92` 的硬跳变。

**`TopFade` 无法自我修正**：`SafeArea` 会对子树 `removePadding`，带内读到的 `padding.top` 是 0。

### 已排除的候选（均不成立）

- 填充四段比例被拉伸/挤压——stops 相对盒子自身 144px 计算，盒子未缩放
- 模糊层被安全区裁剪——不存在独立裁剪，`ClipRect` 只裁在带自身盒内
- 填充层与模糊层起点不同——二者同盒同起点
- 遮罩层级错误——`ShaderMask` 已正确地套在 `BackdropFilter` **外面**（此前修过）

### 影响面

`TopFade` 全项目**只在 `app_shell.dart:135` 一处挂载**，所以四个一级页（首页/记录/统计/设置）
共用同一个带，**都会出现**；只在手机宽度下（`!isWide`）。

**二级页没有这个问题**——`Subpage` 自己 `Scaffold + SafeArea`，根本不使用 `TopFade`。

### 修复方案（用户已裁定：视口也顶到物理顶端）

去掉 `AppShell` 的顶部安全区缩进，改由各页把 `safeTop` 作为滚动视图的顶部留白：

- 渐变带的原点回到**屏幕物理顶端**，与 CSS `top: 0; height: 144px` 对齐
- 滚动内容真正从状态栏下穿过，恢复 `top_fade.dart:8` 注释描述的设计意图
- 带的模糊层在整段 144px（含安全区）上都有内容可模糊，割裂自然消失

**波及面**：四个一级页的顶部留白计算都要跟着调。这是本方案比「只挪渐变带」代价大的地方，
也是它更彻底的地方。

### 一并补齐的规格偏差（用户已选）

- **`saturate(125%)` 缺失**：`top_fade.dart` 里没有任何 `ColorFilter`。项目在
  `glass_surface.dart:11-15` 已承认 `BackdropFilter` 只接受单个 `ImageFilter`、用叠加层近似饱和度，
  这里连近似都没做。**已核实为缺失**。
- **淡入时长**：实现用 `AppDurations.standard = 340ms`，规格写 320ms。**已核实**。

---

## 2. 演示数据删后重装无反应（缺陷，最严重）

### 现象

清除演示数据后，点「重新安装演示数据」界面**毫无反应**；过一会儿再点才「有反应」。

### 根因（已确认，含本机物证）

**`Insights.recordId` 没有外键**，导致 `deleteDemoData` 留下孤儿行，重装时主键冲突，
而异常被静默吞掉。

链条：

1. `Insights.recordId` 在 `app_database.dart:83` 只是 `text().nullable()()`，**没有 `.references(...)`**。
   对照 `SleepStageSegments.recordId` / `SoundClips.recordId` 都写了 `onDelete: KeyAction.cascade`。
   本机建表语句证实：`"record_id" TEXT NULL`，**无 `FOREIGN KEY`**。
2. `deleteDemoData()` 只删 `sleep_records`（`app_database.dart:303-306`）。stages/clips 靠级联跟着走，
   **insights 没有级联，被留下**。
3. 重装时 `DemoSeed.install` 对 insights 用**普通 `insert`**（`demo_seed.dart:88`），而 id 是固定的
   `demo-N-insight`（`demo_seed.dart` 内由 `demo-${i+1}` 派生）→ **主键必然冲突**。
   同一函数里 record 用的是 `insertOnConflictUpdate`（`demo_seed.dart:33-46`），所以**只有 insights 这一处会炸**。
4. 异常从 `db.transaction` 抛出，而 `demo_data_page.dart` 的 `onTap` **没有 try/catch**，
   toast 那行永远执行不到 → 界面零反馈。

**物证**：iOS 模拟器库 `records=0 insights=5`，5 条孤儿为 `demo-1-insight`…`demo-5-insight`，
`record_id` 指向 `demo-1`…`demo-5`——记录已删，洞察还在。

### 第二层机制：「第一次点击被吞」

清除后 provider 重载期间，Riverpod 处于 `AsyncLoading.copyWithPrevious`，`hasValue` 仍为 true，
`.valueOrNull` 仍得旧列表 → `demoCount` 仍是 5 → 安装行 `onTap` 仍是 `null`；
而 `IosListItem` 在 `onTap == null` 时**根本不创建 `GestureDetector`**（`ios_controls.dart:341-350`），
点击落在没有手势处理器的行上，被彻底吞掉。

> **诚实说明**：模拟器库 `records=0` 证明**重装从未成功过**。用户描述的「过一会儿再点才生效」
> 很可能是把「行恢复可点」当成了安装成功，或当时走的是设置页的「删除全部本地数据」
> （那条路径显式删了 insights，`app_database.dart:298`，不会留孤儿）。此点无法从现有证据判定。

### 连带风险：模拟器构建当前可能起不来（严重）

`main.dart:26-32` 冷启动时，若 `AppConfig.demoDataEnabled` 且**没有 demo 行**，
就 `await DemoSeed.install(database)`——**同样没有 try/catch**，且**抛在 `runApp` 之前**。

- macOS 库有 5 条 demo 行 → `hasDemo` 为真 → 跳过安装 → 正常
- 模拟器库记录数为 0 → `hasDemo` 为假 → 走安装 → 第一条洞察冲突 → **`runApp` 不会被调用**

**待核实**：异常是否真的导致白屏（而非被 Flutter 的错误处理吞掉后继续运行）。实现阶段第一件事就是验证。

### 修复方案

**（用户已裁定）加外键级联，schema v3。**

SQLite 无法给已有表直接加外键，必须重建表。drift 2.35.0 的 `Migrator.alterTable(TableMigration)`
正是为此设计的——**已核实**它内部会自行处理 `PRAGMA foreign_keys = OFF` 并在事后重建索引与触发器
（`drift-2.35.0/lib/src/runtime/query_builder/migration.dart:161`）。

**关键细节（已核实）**：项目只在 `beforeOpen` 里开外键，而 `beforeOpen` 跑在迁移**之后**，
所以迁移期间外键本就是关的——**孤儿行会被原样拷进新表**。因此迁移必须两步：

1. **先清孤儿**：删掉 `record_id` 指向不存在记录的 insights 行
2. **再重建表**：`m.alterTable(TableMigration(insights))`，新表带 `onDelete: cascade`

第 1 步顺带**自动修复用户那个已损坏的模拟器库**——升级后孤儿消失，冷启动不再冲突，
构建恢复正常。这是选外键方案（而非「只显式补删」）的主要收益。

### 配套修复（属本条问题范围，非新增功能）

- `demo_data_page.dart` 的安装/清除加 **try/catch + 失败提示**（消除「静默失败」这一失败模式本身）
- 加**忙碌态**，覆盖重载窗口内误点
- `DemoSeed.install` 改为**幂等**：stages/clips/insights 全部改用 `insertOnConflictUpdate`，
  与 record 一致。单靠外键只能修好「删 demo 后重装」这一条路径，幂等才是根治
- 顺带订正 `app_database.dart:292-294` 的**说谎注释**：它写「records (cascading to stages, clips
  **and insights**)」，而 insights 当时并不级联——正因为它不级联，方法体里才要单独补一句
  `delete(insights).go()`。改为 v3 后该注释才成立（但那时显式删除成为冗余，需一并处理）

---

## 3. 设置页版本号（缺陷 + 改动请求）

### 现象

设置页底部「关于」卡片的文字没有在卡片里水平居中。

### 根因（已确认）

不是 `textAlign`，也不是缺 `crossAxisAlignment`（`settings_page.dart:785` 那个 `Column`
已经默认 `center`）。

真正的原因是 **`GlassSurface` 内部是个 `Stack`（默认 `StackFit.loose` + `topStart`）**
（`glass_surface.dart:90-141`）：非 `Positioned` 子项只拿到宽松约束，于是 `Column` 在横轴上
**收缩到最宽子项**——这里最宽的是「睡眠记录与分析」，约 98px，而卡片内宽手机约 300px。
随后这个 98px 的窄列被 `Stack` 的 `topStart` **贴到左边**。
`crossAxisAlignment: center` 只在这 98px 内部起作用，不是在卡片里居中。

**这是 CLAUDE.md 已记录的「`Stack`(loose) 按最大非 position 子项定尺寸」坑的又一实例**——
`expandWidth` 修好了「卡片背景撑满」，但没修「卡片内在横轴上不自撑的子项被左锚定」。

**对照**：同页睡眠目标卡片之所以正常，是因为它的 `Column` 首个子项是 `Row`
（`settings_page.dart:271`），`Row` 默认 `mainAxisSize.max` 会横向自撑，`Column` 随之满宽。

> 调查中的一处订正：「删除全部本地数据」是**刻意左对齐**的 `Row`，不能作为居中的参照。

### 附带发现：版本号是硬编码的

`settings_page.dart:804` 写死 `'v2.0.0'`，而 `pubspec.yaml:4` 是 `version: 0.1.0+1`。

- 不跟随真实构建版本，发版时不会变
- **且当前就已经与 pubspec 对不上**

**（用户已选）改为读取真实版本**。拟引入 `package_info_plus`。
**已核实**：该包**不在本地 pub 缓存中**，需联网获取；本机 pub.dev **直连可达**（HTTP 200，约 5.3s）。
**实施约束**：不得设置 `PUB_HOSTED_URL`（README 明令，会把 `pubspec.lock` 里 129 条
`url: "https://pub.dev"` 改写成镜像地址，制造与依赖无关的巨型 diff）。

---

## 4. 导入页的白线与点击无反馈（缺陷 + 改动请求）

### 现象

「导入睡眠记录」按钮上方有一根白线；点击无任何反应。

### 白线根因（已确认，像素级取证）

白线**不在按钮上方的空隙里，而是按钮自身的 1px 顶边内高光**——
`app_basics.dart:278-291` 的 `Colors.white.withValues(alpha: 0.25)`。

对 `screenshots/light-06-import.png`（DPR = 3）采样：

- 按钮上方间隙整段是均匀卡片底色，**没有任何白线**
- 按钮顶部出现 3 设备像素高（= 1 逻辑像素）的亮带
- 反推完全吻合：`0.25·白 + 0.75·#0A84FF` 再按 60% 不透明叠到卡片上，与实测值一致

**位置本身是对的**（`app_basics.dart:271-273` 的注释说明过去那版「高光穿过文字」的 bug 已修）。
问题是这条 `inset 0 1px` 镜面高光是给**启用态**走的，而全项目 3 处 `PrimaryAction`
（`home_page.dart:116`、`onboarding_overlay.dart:175`、`sleep_import_page.dart:200`）
**只有这一处是禁用的**，于是高光成了按钮上最跳的元素。

**已排除**：`IosListGroup` 分隔线（本页未用）、`Container` 的 top 边框（全文件无任何 `Border`）、
`GlassSurface` 描边（在卡片外圈，且上方间隙无亮线）。

### 点击无反馈根因（已确认）

`sleep_import_page.dart:203` 是 `onTap: null`，`Pressable` 会把 `onTapDown/Cancel/Up/Tap`
**四个回调全部置 null**（`app_basics.dart:45-53`），手势被吞掉——无缩放、无震动、无回调。

### 修复方案

- **白线**：禁用态不画那条高光（`PrimaryAction` 增加状态感知，或把高光抽成参数）。
  不能简单删掉——启用态需要它。
- **反馈**：让按钮「**看起来是禁用的，但可点击并给出提示**」。**不能只把 `onTap` 填上**——
  `onTap` 一非空，`PrimaryAction` 立刻回到启用态视觉（`Opacity` 变 1、出现按压缩放与触觉），
  与「未实现/禁用」的规格语义冲突。需在组件层加独立参数（例如 `enabled: false` + 独立的 `onBlockedTap`）
  或在外层包手势。

### 反馈载体：**不能用全局 toast**（关键约束）

`ToastOverlay` 挂在 `AppScaffold` 里（`app.dart:146`），而二级页是 push 到外壳**之上**的，
会把它整个盖住。项目自己的测试已承认这点——`reminder_settings_test.dart:136-140` 明确写着
「测试树里没有 ToastOverlay……只能直接读 provider」，所有 toast 断言只读状态、不验可见性。

因此本页的反馈必须在 `Subpage` 内自带（页内常驻提示或页内浮层）。

**参考既有模式**：`demo_data_page.dart:100-113` 的「禁用 + 明确文字状态（`trailing: '已存在'`）」
是本项目对禁用控件的惯例。

---

## 5. 删除图标与 iOS 风格确认弹窗（改动请求，**冲突规格 #12**）

### 冲突声明

规格 §8 偏差 **#12** 原文：

> 原型图标集无垃圾桶 | 删除按钮为纯文字，不画图标补齐 | 设计的 24 个图标是固定集合；
> 自绘一个垃圾桶等于引入一套应用其余部分没有的图标语言。

本设计要求**修订该条**。用户的理由成立，且调查证实了一处**应用自身的矛盾**。

### 为什么用户的要求是对的

「删除全部本地数据」这一行**已经有图标了**：`settings_page.dart:763-764` 用的是
`AppIcons.stop`，即**播放控制的「停止」方块**（`app_icons.dart:31`，一个 `<rect rx="2">`）。
语义完全对不上——这就是「风格不搭」的来源。

而同一应用里「删除**记录**」严格遵守了 #12，是纯文字无图标，`detail_sheet.dart:413-415`
还专门写了注释解释「图标集里没有 bin，不为此发明图标」。

**即：一处遵守偏差、一处借语义不符的图标凑数，两者自相矛盾。** 用户看到的正是这个矛盾。

### 事实：原型图标集确无删除类图标（已核实）

28 个具名图标访问器中**不含**垃圾桶、叉号、减号、清扫类中的任何一个。
`stop`（停止）与 `check`（确认）是仅有的可对号入座者，语义均不匹配。

**所以必须新画，不是「启用已有」。**

> 顺带订正：规格写「24 个图标」，而实现里公有具名图标访问器实为 **28 个**（另有 `glyph` 渲染核心）。
> 该数字已过时，需一并订正。

### 用户已裁定的两项

1. **自绘删除图标**，风格与其它图标一致
2. **两处确认弹窗统一改为 iOS 风格**，**按项目令牌自绘**（不引入 `flutter/cupertino.dart`
   ——它自带系统配色与圆角，会绕过 `AppTokens`，与「设计令牌只有一份」的硬约定冲突）

### 确认弹窗现状（已核实）

应用内**只有两处**确认弹窗，且实现完全相同——`showDialog<bool>` + `AlertDialog`：

| 位置 | 入口 |
| --- | --- |
| `settings_page.dart:155`（`_confirmDeleteAll`） | 删除全部本地数据 |
| `detail_sheet.dart:61` | 删除单条记录 |

所以不存在「两种确认风格并存」的代码不一致；真正的不一致是**整个应用是 iOS/令牌体系，
唯独确认弹窗走了 Material 默认的 Android 外观**。

另发现**第三处口径不一致**：「清除演示数据」**根本没有二次确认，点一下就删**
（`demo_data_page.dart:113-127`）。

### 新建组件的约束

- 颜色/圆角/动效**一律从 `AppTokens` / `AppRadii` / `AppMotion` 取**，不写死色值
- **必须显式提供 `Material` 祖先**——项目已知坑：`showGeneralDialog` 不像 `showDialog` 那样
  自动包 `Material`，缺了它所有 `Text` 会落到**黄色双下划线**错误样式
  （`AppSheet` 与 `Subpage` 都已显式补上）
- `AppSheet` **不支持**居中确认框（它永远是底部贴边面板，无居中变体），不能直接复用

### 波及的测试（已核实）

- `test/pages_widget_test.dart:329-340`「删除全部数据前要求二次确认」
- `test/record_edit_delete_test.dart:298-327` 删除记录组
- `test/app_sheet_test.dart:113-145`（Material 祖先护栏）

**已核实**：这些断言依赖**文案与可见性**，不依赖 widget 类型——**只要文案不变**，
改用自绘组件通常仍能命中。真正会打破它们的是改文案或改动画时序。

### 一致性处理（用户已裁定）

- **「删除记录」也补上同一图标**。它现在严格遵守了偏差 #12（纯文字），补 = 更一致，
  但那是规格明确拒绝过的另一处——连同偏差 #12 一并修订
- **「删除全部数据」补 `tokens.danger` 语义色的图标底板**，与同页其它行（导入/提醒/声音/洞察/
  演示数据）一致。注意令牌里**只有 `danger`，没有 `dangerSoft`**，底板底色需现算低透明度
  （可参照 `detail_sheet.dart:416-421` 已有的 `tokens.danger.withValues(alpha: 0.12)`）

---

## 6. 深色模式事件图标不可见（缺陷）

### 现象

记录页四类事件开关（打鼾/说梦话/辗转难眠/噩梦）的图标在深色模式下呈黑色，看不清。

### 根因（已确认）

四个调用点**漏传 `color:`**（`log_page.dart:321 / 333 / 349 / 361`），于是
`AppIcons.glyph` 走了兜底的硬编码黑 `Color(0xFF000000)`（`app_icons.dart:91`），
该值被**文本替换进 SVG 的 `stroke` 属性**，再交给 `SvgPicture.string` 渲染。

- `SvgPicture` **不读 `IconTheme`**，所以 `log_page.dart:594-597` 那圈 `IconTheme.merge`
  **从未起过作用**
- 颜色在 `SvgPicture.string` **构造那一刻**就已写死进 SVG 文本，之后再包多少层都无效
- 因此**选中/未选中两态都是黑的**（只有文字与边框正常，反衬得更明显）

**已核实**：全库其余所有 `AppIcons.` 调用点都显式传了 `color:`，深色下均正常。
这不是系统性问题，是孤立疏漏。

### 附带发现：又一句说谎的注释

`log_page.dart:579-580` 声称「The icon arrives uncoloured; recolour it by rebuilding through
the same builder so the active state can tint it」——**该机制从未存在**。
这正是「未核实的事实被写成确定语气」的又一实例。

### 修复方案

把颜色**真正传给 `AppIcons.*`**：

- 未选中 → `tokens.textMuted`（与该行原意图一致）
- 选中 → 复用该 tile 已有的语义色（`accentBlue` / `accentViolet` / `caution` / `danger`，
  全部来自 `AppTokens`，已随主题切换）

### 兜底改为断言（用户已裁定）

把 `app_icons.dart:91` 的兜底黑**改为断言报错**，让同类疏漏不再静默。

**前置条件已核实**：全库 `AppIcons.*` 调用点共 **97 处**，其中**只有上述 4 处未传 `color:`**
（另一处命中是私有构造函数 `AppIcons._()` 的误报）。因此该断言不会误伤任何既有调用点，
且改完就会立刻暴露的正是这 4 处。

**注意**：内部调用者（`filledTabGlyph` 等）也必须传色，实现时需一并核对。

---

## 7. 附带发现（用户已选，全部纳入）

| 项 | 内容 |
| --- | --- |
| 版本号来源 | 见 §3。引入 `package_info_plus` 读真实构建版本 |
| 「清除演示数据」补二次确认 | 见 §5。它现在点一下直接删，与另两处口径不一致 |
| 「删除记录」补同一图标 | 见 §5 |
| 顶部渐变规格对齐 | 见 §1。补 `saturate(125%)` 近似，时长 340ms → 320ms |

### 另记（**未选入本轮**，仅备查）

- `settings_page.dart:822` 把太阳图标色写死为 `Color(0xFFC8B860)`，违反「不写死色值」
- `app_basics.dart:265` 把 accent 蓝写死为 `Color(0xFF007AFF)`（而非取 `tokens.accent`）
- 令牌里没有 `dangerSoft`，做 danger 底板需现算透明度

---

## 规格改动清单

按 CLAUDE.md 约定，本轮的改动必须同步进文档：

| 文档 | 改动 |
| --- | --- |
| `specs/2026-09-28-night-sleep-design.md` §8 | **修订偏差 #12**（自绘删除图标，推翻原「不补」）；新增偏差 #20（自绘 iOS 确认弹窗、未引入 cupertino、三处危险操作统一）；§2.3 图标数量口径改为「原型数量未核实，实现侧具名访问器 28→29（本轮加 `trash`）」——**不是把 24 直接改成 28** |
| 同上 §5.1 / §9 | 表结构补 `Insights` 外键；测试矩阵补本轮用例 |
| 同上 §2.2 | 顶部渐变的 `saturate(125%)` 与 320ms 落实为已验证 |
| `README.md` | 实现范围、验证记录（含未验证项） |
| `CHANGELOG.md` | 新增 2.6 条目 |

---

## 测试矩阵（本轮新增）

| 类型 | 场景 |
| --- | --- |
| 数据测试 | schema v2→v3 迁移：用**真实 v2 库文件**升级，校验孤儿 insights 被清除、外键生效、**复现用户那个 `records=0/insights=5` 的库可被修复**、重复打开不重跑 |
| 数据测试 | 删除演示数据后**重新安装成功**（当前必失败的那条路径） |
| 数据测试 | `DemoSeed.install` 幂等：连装两次结果一致，不留残留 |
| Widget | 演示数据页：安装失败时**有可见反馈**（不再是静默失败） |
| Widget | 记录页事件图标**未选中态取 `textMuted`、选中态取语义色**（防止漏传 `color:` 回归） |
| Widget | 自绘确认弹窗：无黄色下划线、有 `Material` 祖先、两处入口文案不变、取消/确认行为不变 |
| Widget | 关于卡片文字在卡片内水平居中（防 `Stack` 静缩回归） |
| Widget | 导入页：禁用态按钮无顶边高光；点击给出**页内可见**反馈 |

**迁移测试的既有教训**：`test/schema_migration_test.dart` 已建立「先用旧版 schema 建真实库文件、
再打开触发升级」的做法，并带**防止夹具空跑的自检**。本轮须照此办理，且自检必须能覆盖
「旧库里确实存在孤儿行」这一前提——否则用例会在一个本来就没有孤儿的库上通过。

---

## 非目标

- 不实现夜间录音、小米导入、AI 洞察调用（M3/M4 保持未开始）
- 不接入平台安全存储（API Key 仍只在内存）
- 不生成 `android/` 平台目录
- 不改动里程碑划分与「未实现」表的口径

---

## 待核实事项（**实现阶段第一步就要验证，不得当成已知**）

1. **冷启动异常是否真的白屏**：`main.dart` 的 `await DemoSeed.install` 抛出后，`runApp` 是否真的不执行
2. **`m.alterTable` 在本项目的 `beforeOpen` 时序下**是否行为如预期（外键在迁移期间的实际开关状态）
3. **重载窗口的实际时长**是否长到人可感知（影响「第一次点击被吞」的可复现性）
4. `package_info_plus` 在 macOS / iOS 两端的实际返回值与 `pubspec.yaml` 的对应关系
5. `PrimaryAction` 的禁用态改造是否会波及首页与引导页的既有观感

---

## 实际结果（2026-09-29 事后补记）

六条问题全部修复，`flutter analyze` 无问题、`flutter test` **216/216**（开工前 176）。逐条对账
（每条的根因已在 `CHANGELOG.md` 的 2.6 条目里写明，此处只记与本文设计有出入的地方）：

| 本文设计 | 实际落地 | 为什么变 |
| --- | --- | --- |
| §1 顶部渐变：外壳去掉顶部 `SafeArea`、各页补 `pageTopInset` | 按设计落地，另补 `saturate` 近似与 320ms | 计划初稿把填充渐变留作 `Stack` 的非 position 子项，无子节点的 `DecoratedBox` 在 `loose` 下会缩成 **0×0 静默消失**（实测确认），已改为 `Positioned.fill`——与设计里反复强调的 `BackdropFilter` 尺寸坑同源 |
| §2 外键级联 + 清孤儿，schema v3 | 按设计落地 | 迁移夹具的写法变了：计划给的 Dart 表类方案（`@DriftDatabase` + `_V2*`）**编译不过**且会引入代码生成、要动两个仓库级配置；改用同文件既有的 `extends AppDatabase` + 裸 DDL（零代码生成），把 v2 形态**冻成文本**——表类会随 `app_database.dart` 演进，将来改动即让夹具不再代表 v2、用例空跑通过 |
| §2 配套：`_install`/`_clear` 加 try/catch | 落地，且成功提示也从**看不到的全局 toast** 改成页内文案 | 二级页 push 在外壳之上，全局 `ToastOverlay` 永远被盖住——设计稿在别处已承认这点，却在成功路径上保留了一句无效调用 |
| §3 版本号读真实构建值 | 按设计落地，但 future 建在 `State` 的 `late final` 而非 `build` 里的 `FutureBuilder` | 写在 `build` 里每次重建都会退回等待态、闪掉一帧；而「进程级缓存」方案会在 `testWidgets` 的 FakeAsync 下永不完成（`dart:async` 按 future **创建时**的 zone 排微任务），实测炸过一次 |
| §5 确认弹窗「动作区中间一条 1px 分隔线」 | 竖线 + **内容区与按钮区之间的横线**都做了（终审波把两条线由 1px 改成 **0.5 发丝线**，与全仓其余分隔线同口径） | 措辞有歧义，标准 iOS alert 两条都有；横线才是最能定义该观感的元素 |
| §6 兜底改断言；身份「无法从 widget 树断言」 | 断言落地；**身份其实断言得到**，已补上并变异验证 | `SvgStringLoader` 的字符串确实私有，但 `SvgPicture.bytesLoader` 是**公开字段**、且 `SvgStringLoader` 实现了值相等。把垃圾桶换回停止方块，两条用例都会变红 |
| §4 / §5 的目视验证 | **只有任务 5 真的跑了模拟器截图**（顶部渐变，浅色/深色各一遍） | 一位实现者在跑模拟器截图时**卡死 600 秒**（它写的临时集成测试要点折叠线下方的行）。此后本轮禁止后续任务碰模拟器，其余界面改动只做几何/结构断言 + 离线栅格化。**这是本轮最明显的未完成项** |

### 待核实事项的对账

1. **冷启动异常是否真的白屏** —— **没能核实**。任务 1 的迁移会在打开坏库时先跑、把孤儿清掉，
   触发条件被前序任务消除，无法在真实坏库上复现；改为对兜底函数做故障注入测试
   （`test/demo_seed_startup_test.dart`，含变异验证）。**「抛出后 `runApp` 是否真的不执行」这一
   现象本身未被观察到**，只有「兜底在失败时不外抛」被测试证明。
2. **`m.alterTable` 时序** —— **已核实**。在用户真实坏库的副本上端到端跑通：
   `user_version 2→3`、`insights 5→0`、建表语句含 `ON DELETE CASCADE`，同一副本上重装演示数据成功。
   （原库文件未被触碰，`shasum` 前后一致。）
3. **重载窗口时长是否长到人可感知** —— 未专门测量。设计稿对此已有「无法从现有证据判定」的
   诚实说明，现状照旧；清除/安装的忙碌态已在实现里堵住误点。
4. **`package_info_plus` 的实际返回值** —— **API 形状已核实**（`version` / `buildNumber`，
   并发现 `setMockInitialValues` 这个官方测试注入口）；**真机 macOS / iOS 上的实际取值未核实**，
   测试用的是 mock。仍列为 README 的未验证项。
5. **`PrimaryAction` 禁用态是否波及首页/引导页** —— **组件级已核**（启用态的高光/投影/不透明度/
   点击/触觉逐项断言在改前改后都绿）；**引导页调用点没有目视确认**（它本就没有现成用例）。

