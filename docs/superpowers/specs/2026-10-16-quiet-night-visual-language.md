# 静谧夜色 + 柔和晨光：视觉语言一轮

日期：2026-10-16
状态：已落地（v3.34）
上游规格：[2026-09-28-night-sleep-design.md](2026-09-28-night-sleep-design.md) §2 / §8、
[2026-10-15-sleep-data-browsing-design.md](2026-10-15-sleep-data-browsing-design.md)（§二 被本文取代）

变更史见 [`CHANGELOG.md`](../../../CHANGELOG.md)。

## 问题

使用方 2026-10-16 转来原型更新（Figma Make `hKbqp1qjtcNQmmiDtVvXpk`）与一份七条的设计说明，
要求「首页 / 回顾 / 统计一起改」，其中**统计页的「查看所有数据」页整体展示都变了，重新实现**。

七条原话是：拉开页面层级、增加睡眠状态色、首页增加结论、统一但区分圆角体系、强化字体性格、
给不同页面不同的情绪重心、增加非常克制的动态氛围。

## 零、先把「原型末层」定死（这一步走错过一次）

`index.css` 是**层层追加**的，同一个变量被反复覆盖。按**字节偏移**拉出顺序后，末层是这样的：

| 偏移 | 选择器 | 关键值 |
| --- | --- | --- |
| 39538 | `:root` | `--bg-base: #f4f5f8`、`--accent: #2674e8` |
| 40199 | `.theme-dark` | `--bg-base: #0f1118` |
| **58481** | **`.ios-app`** | **`--bg-base: #f2f2f7`、`--accent: #007aff`** |
| **59449** | **`.theme-dark.ios-app`** | **`--bg-base: #000000`、`--accent: #0a84ff`** |

后两层自带注释：**「This layer intentionally supersedes the Material refinement above」**。

**结论：底色、文字色、强调色、语义色、阶段色一个值都没变**，与本项目 `AppTokens` 逐值一致，
也与总规格 §2.1 的令牌表、偏差 #32 的结论一致。中间那层 `#f4f5f8` / `#2674e8` 是**被推翻的
Material 层**，不要照它改令牌。

变的是**材质分工**：末层在玻璃之外新加了「安静实体面」与「每页各自的 hero」两类表面，
并把首页、回顾、统计、设置四页的头部卡各自染上了不同的情绪。这才是本轮的全部内容。

> **留一条教训**：读这份 CSS 时，先按字节偏移确认层叠顺序再谈值。同一份文件里
> `--bg-base` 出现 8 次、`--accent` 9 次，取错了层会得出「配色整体换了」的错误结论。

## 不做什么

- **不换字体。** 原型的数字用 `Outfit`，本实现从建库起走系统字体 + tabular figures（§2.2 已定，
  使用方第 5 条也明说「不必换成很设计感的字体」）。所以第 5 条只落在**层级**上，不落在字体上。
- **不动圆角基数。** 保持 `card = 24` / `panel = group = 16`。第 4 条写的 28 / 20 来自**被推翻的
  那一层**（偏移 54482 / 54536），不是末层。本轮只新增两个半径：扁平列表容器 `18`、结论条 `14`。
- **不给首页补阶段环。** 新 hero 卡带光晕与星点，看上去比原来「满」得多，但偏差 #10 一字未改：
  深睡 / 浅睡 / REM 三块**只在该记录确有阶段数据时**出现。
- **不让结论条推断任何没测过的东西。** 它只说时长与近七日平均的差值（见 §三），
  不说「深睡表现不错」这类需要阶段或音频结论的话。
- **不为了好看动数据口径。** 平均时长分母、平均评分只计已评分、目标达成只算有记录的日子
  ——总规格 §5.2 三条原样沿用。

## 一、三层材质

原型末层把「卡片」拆成三种职责。三层的**共同点是都只有 1px `--glass-border` 描边**，
区别在填充与是否模糊：

| 层 | 原型类名 | 填充 | 模糊 | 阴影 | 用途 |
| --- | --- | --- | --- | --- | --- |
| **玻璃** | `.glass` / `.ios-list-group` | `--ios-material` | `blur(24px) saturate(155%)` | `inset 0 1px 0 var(--ios-specular)` + `--ios-shadow` | 弹层、标签条、侧边栏、需要「浮在氛围之上」的面 |
| **安静实体** | `.quiet-surface` `.home-utility-card` `.stats-metric-card` `.review-event-option` `.settings-surface` | `--ios-material-strong` | **无** | `0 5px 18px rgba(36,53,91,.055)`（深色 `rgba(28,28,30,.84)` + `0 8px 24px rgba(0,0,0,.16)`） | 功能卡、表单控件、列表容器 |
| **页面 hero** | 见 §二 | 各自的渐变 | 无 | 各自的阴影 | 每页**唯一**的强视觉区域 |

**落点**：`lib/core/widgets/quiet_surface.dart` 新增 `QuietSurface`（API 与 `GlassSurface` 对齐：
`child` / `borderRadius` / `padding` / `margin` / `onTap` / `semanticLabel` / `expandWidth`，
但**不接 `BackdropFilter`**）。

**为什么必须新增而不是给 `GlassSurface` 加参数**：`GlassSurface` 的整条绘制路径都套在
`ClipRRect → BackdropFilter` 里，还有一个 1px 顶部高光与 115° 斜向扫光。安静面**一样都不要**
——它的存在理由就是「不参与氛围」。用 `blur: 0` 关闭模糊会留下一层无用的 `BackdropFilter`，
而它在每一帧都要合成一次；列表里滚过的每张卡都背这个成本。

## 二、五张 hero 卡

每页有且只有一张，都是「这一页是什么情绪」的唯一载体。

### 2.1 首页 `SleepHeroCard`——夜色（深蓝紫 + 月晕 + 星光）

**这是一张自成一体的暗卡：浅色主题下它也是深的。** 它在局部把令牌整个换掉：

```dart
// 只在卡内生效，不写回 AppTokens
--text-primary:  rgba(250, 251, 255, .98)
--text-secondary: rgba(229, 234, 255, .78)
--text-muted:    rgba(218, 226, 255, .62)
--accent:         #91c8ff
--accent-soft:    rgba(137, 190, 255, .15)
--accent-violet:  #b7a9ff
--border:         rgba(207, 220, 255, .13)
--glass-border:   rgba(255, 255, 255, .14)
--bg-muted:       rgba(255, 255, 255, .07)   // 第 9 个，原型没有，见下
```

**第 9 个字段 `bgMuted` 是本实现补的，原型没覆盖它。** 无阶段那一支里，
三个 `—` 格的**底**取 `bgMuted`、**字**取 `textMuted`——照抄浅色那个 `#E9E9EF`，
得到的是「浅蓝白字压在浅灰底上」，等于看不见。而那一支恰恰是手写记录的常态路径
（任何一晚没有阶段数据都会走它）。所以把它一起换成 `rgba(255,255,255,.07)`。
**这是刻意的偏离，记在这里免得将来被当成抄错。**

底色三层叠：径向 `90% 80% at 92% 2%` 从 `rgba(104,136,238,.34)` 到 62% 透明；
径向 `80% 70% at 0% 100%` 从 `rgba(56,158,173,.16)` 到 68% 透明；
线性 `145deg` `#151d3c 0% → #20204a 48% → #102b3d 100%`。
描边 `1px rgba(218,228,255,.14)`，阴影 `inset 0 1px rgba(255,255,255,.16)` + `0 18px 42px rgba(40,57,112,.24)`。

**两件装饰**（都用 `Positioned` 画在内容之下、卡自己的圆角之内）：

- **月晕** `190×190`，`top: -76 / right: -54`，径向 `rgba(189,207,255,.28) → rgba(128,145,229,.07) 42% → transparent 70%`，
  **带呼吸动画**：`homeMoonGlow 5s ease-in-out infinite`，中点 `opacity .72` + `scale 1.08`。
  `MediaQuery.disableAnimations` 为真时不启动。
- **星点** 四点，`opacity .48`，位置 `12%/18%`、`72%/16%`、`90%/48%`、`56%/78%`，直径 1px（`white` .8/.65/.7/.52）。

**局部令牌怎么实现**：`AppTokens.of(context)` 是全局查找，卡内要改观只能另给一套。
做法与偏差 #32 对会话页的裁定同源——**收进这一页自己的常量**，`AppTokens` 一个字节不动。
约定不破：一个概念仍只有一处，只是这一处落在这一页。

### 2.2 回顾 `ReviewDurationHero`——柔和晨光

暖色：描边 = `accent` 13% 混 `--glass-border`；底色径向 `circle at 92% 4%` 从 `rgba(255,198,111,.18)`
到 36% 透明，叠线性 `145deg`（`accent-soft` 42% 混 `--ios-material-strong` → `--ios-material-strong`）；
阴影 `0 10px 28px rgba(39,57,96,.08)`；右下角另有 `108×108` 半径 999 的暖光团
`rgba(255,219,151,.28)` → 68% 透明（`top: -34 / right: -28`）。

深色：径向改 `rgba(224,155,86,.1)` → 38% 透明，底线改 `rgba(39,43,65,.92) → rgba(28,28,30,.9)`。

### 2.3 统计 `StatsDataHero`——冷净

描边 = `accent` 12% 混 `--glass-border`；底色线性 `180deg`（`accent-soft` 30% → 45% 透明）
叠 `--ios-material-strong`；阴影 `0 8px 26px rgba(36,53,91,.075)`。

### 2.4 统计评分卡 `StatsScoreCard`

描边 = `accentViolet` 18% 混 `--glass-border`；底色径向 `circle at 90% 8%`（`accentViolet` 18% → 42% 透明）
叠 `accent-soft` 38% 混 `--ios-material-strong`；阴影 `0 8px 24px rgba(69,70,153,.08)`。
深色：径向 `rgba(120,105,220,.18)` → 42% 透明，底 `rgba(32,32,38,.9)`。

### 2.5 设置目标卡 `SettingsGoalHero`

描边 = `accent` 15% 混 `--glass-border`；底色径向 `circle at 50% 0%`（`accent` 13% → 44% 透明）
叠 `--ios-material-strong`；半径 16；阴影 `0 8px 26px rgba(36,53,91,.07)`。

### 2.6 换算规则：`color-mix` 不等于 `Color.alphaBlend`

原型的底色大量写成 `color-mix(in srgb, X p%, Y)`。**这在 Flutter 里要一个新函数**
（`app_tokens.dart` 的 `colorMix`），不能拿 `Color.alphaBlend` 顶替——两者只有在
**`X` 完全不透明**时才相等：

- `alphaBlend` 的语义是「把 X 盖在 Y 上」，Y 的权重因此是 `1 − p·αX`；
- `color-mix` 是**按各自不透明度加权求平均**，Y 的权重就是 `1 − p`。

原型偏偏到处用 `--accent-soft`，而它**自带 alpha**（浅色 .12 / 深色 .20）。照
`alphaBlend` 写，每处带它的底纹都会浓约 8 倍。

| 原型写法 | Flutter |
| --- | --- |
| `color-mix(in srgb, X p%, transparent)` | `colorMix(X, p, Colors.transparent)` |
| `color-mix(in srgb, X p%, Y)`（Y 实色） | `colorMix(X, p, Y)` |
| 再把上面那层叠到某个实底上 | `Color.alphaBlend(上面那个结果, 实底)` —— **两步，不能合成一步** |

**这条是 2026-10-16 在真机上抓出来的**：全部数据页的 hero 底原本是一块饱和天蓝，
而设计里它只是一层几乎看不见的雾。回归方法：`test/color_mix_test.dart` 六条
（含「用 `alphaBlend` 顶替会明显更蓝更实」那条，已做变异验证——把 `colorMix`
改成 alphaBlend 语义，六条里红四条）。

## 三、超出原型的四项（使用方明确要求，原型末层没有）

这四条**不在原型里**，是本轮新增的产品决定，单独列出来免得将来被当成「原型有而没做」。

### 3.1 首页问候

原型那行眉题只有日期（`new Date().toLocaleDateString('zh-CN', …)`），没有称呼。
本轮把它变成**问候 + 日期**：`早安 · 9月27日 星期日`。时分界：

| 时段 | 文案 |
| --- | --- |
| 05:00–11:59 | `早安` |
| 12:00–17:59 | `午安` |
| 18:00–22:59 | `晚上好` |
| 23:00–04:59 | `夜深了` |

时间取 `homeNowProvider`（**已经存在**，测试靠它冻结「现在」），不另造时钟。

### 3.2 薄荷绿语义色

原型只把 `#86d8c6` 硬编码在一个圆点上（`.sleep-insight-mark`），没有成套的语义色。
本轮补一个令牌 **`AppTokens.good`**：浅色 `#2E9E83`（深底上才用原型那个 `#86d8c6`，
浅底上它对比度不够），深色 `#86D8C6`。

**只用在「达标 / 恢复良好」这一类正向判断上**：结论条的圆点、回顾页的「睡眠充足」、
统计页的达标率与充足天数。**不动 `durationBandColor`**——它现在把「健康」映射到品牌蓝
（`accent`），三页的柱子、时长数字都吃它，改它等于把整片图表重新染色，那不是这一条要的事
（第 2 条原话是「颜色只出现在评分、趋势变化、状态标签和图表中」，不是「把所有蓝的换成绿的」）。

### 3.3 回顾的命名状态

原型末层**仍是 1–5 星级**（`LogView.tsx` 里五颗 `IconStar`）。使用方要求换成更具感受性的状态。

**保留五个档位与它的 1–5 底层值**（`estimateScore` 的 35 分权重吃这个值，改档位数会让评分
口径跟着变），只把**标签**换掉，并把星形换成文字药丸：

| 值 | 旧标签 | 新标签 |
| --- | --- | --- |
| 1 | 极差 | 精疲力尽 |
| 2 | 较差 | 疲惫 |
| 3 | 一般 | 一般 |
| 4 | 良好 | 清醒 |
| 5 | 极好 | 精力充沛 |

**未选仍然是未选**：`quality` 可空、初始无选中（偏差 #26 的红线：不替用户说话）。
药丸上不预设任何一个。

**即时反馈**：选中后在该行右侧给一句反馈，与 `estimateScore` 的质量档同源、不另立一套：

| 值 | 反馈 |
| --- | --- |
| 1 | `今晚早点休息` |
| 2 | `要留意一下节律` |
| 3 | `还算平稳` |
| 4 | `状态不错` |
| 5 | `休息得很好` |

未选时**不显示这句**，也不显示占位符。

**影响面**：`QualityStars` 改名为 `QualityChoice`，三个调用点
（`review_page.dart` / `log_page.dart` / `quality_rating_sheet.dart`）一起换；
`SleepQuality.label` 的三个消费点（RecordCard 的 `Tag`、无障碍标签、详情弹层）跟着变。
**无障碍标签 `睡眠质量 精力充沛` 是测试点名的**，改名时一起重钉。

### 3.4 hero 月晕呼吸

就是 §2.1 那条动画。原型里它开着（`animation: homeMoonGlow 5s ease-in-out infinite`），
只在 `prefers-reduced-motion: reduce` 下关掉——**这不是偏差 #9 说的那层**：
#9 说的是早期那三团 `.liquid-orb`（`.liquid-orb{opacity:0}`，仍然不做）。
两处不是同一个元素，别混。

## 四、逐页落点

### 4.1 首页

| 区块 | 现在 | 改成 |
| --- | --- | --- |
| 眉题 | `9月27日 星期日` | `早安 · 9月27日 星期日`（§3.1） |
| 昨夜睡眠卡 | `GlassSurface(card)` | **`SleepHeroCard`**（§2.1）：光晕 + 星点 + **结论条** + 原有内容 |
| 结论条（新） | 无 | 见 4.1.1 |
| 近 7 日均时 / 助眠音效 | 两张 `GlassSurface(panel)` | `QuietSurface`（半径 16） |
| 最近记录 | 5 张独立 `RecordCard`（`GlassSurface(card)`） | **一个扁平列表容器**（半径 18），行间 1px 分隔线，行内不变 |

`RecordCard` 是 `public` 但**只被首页用**（`home_page.dart:293`），随本轮收成页内私有行组件。
行内内容保持原样（日期 + 质量 Tag + 鼾/话图标、床→日起止、右侧时长与 `估算/评分 N`、
阶段彩带与图例），只把「外框」从卡片换成列表行。

#### 4.1.1 首页结论条

原型把它放在 hero 卡内部、阶段块**之上**。内容分两行：

**第一行**（13px / w650，白 .94）——时长与近七日平均的差：

```
durationDelta === null            → 继续记录几晚，就能看到你的睡眠变化
|durationDelta| < 10              → 与近 7 日平均基本持平，节律很稳定
durationDelta > 0                 → 比近 7 日平均多睡了 {n} 分钟
否则                               → 比近 7 日平均少睡了 {|n|} 分钟
```

`durationDelta = round((昨夜时长 − 前七晚平均) × 60)`，**分母是 `records.slice(1,8)` 的实际条数**
（不足七晚就按实际条数；一条都没有时为 `null`）。近七日平均 `avg7` 的分母是
`min(总条数, 7)`——与统计页同一条「分母只计有记录的日子」的口径（§5.2）。
**「前七晚」不是「前六晚」**：`slice(1, 8)` 取的是下标 1 到 7。

**第二行**（11px，白 .52）——一句可执行的建议：

```
昨夜时长 >= 7 → 时长已达到建议目标，保持现在的睡眠节律
否则           → 今晚可以尝试提前半小时放下手机
```

圆点是 `good` 色（§3.2），`7×7`，外加两层光晕环。

**这一条不许写「深睡表现不错」这类话**：本应用没有可靠的阶段结论，
而 `notes` / 事件都是用户自己填的。结论条只说时长这一件真的测过的事。

### 4.2 回顾（`review_page.dart` 与 `log_page.dart` 两处表单）

| 区块 | 改成 |
| --- | --- |
| 时长预览卡 | `ReviewDurationHero`（§2.2） |
| 质量 | `QualityChoice` + 即时反馈（§3.3） |
| 事件四宫格 | `QuietSurface`，选中态用 `color-mix(事件色 11%, bgCard)` + 1.5px 事件色 38% 描边（原型 `.review-event-option`） |
| 时间三行 / 备注 | `QuietSurface`（`IosListGroup` 不再是玻璃） |
| 会话刚结束的横幅 | `review-session-banner`：38px 圆角图标底 + 「睡眠记录已完成 / 补充感受和事件，让回顾更准确。」 |

**回顾页（Tab）与手动补录页（`/log/new`）两处都要改**：它们是同一件事的两个宿主，
只改一处会让两屏长得不一样。手动补录页的日期 / 入睡 / 起床三行口径不变。

### 4.3 统计

| 区块 | 改成 |
| --- | --- |
| 时长柱状图卡 | `StatsDataHero`（§2.3） |
| 评分卡 | `StatsScoreCard`（§2.4） |
| 四项汇总卡 | `QuietSurface`（`.stats-metric-card`） |
| 梦话记录卡 | `QuietSurface` |
| 右上角入口 | 文案 `全部数据` → **`查看所有数据`**（照原型 `StatsView.tsx` 的按钮文案） |

### 4.4 设置

睡眠目标的滑块卡换 `SettingsGoalHero`（§2.5）；设置类分组列表与外观 / 睡眠设置两个二级页
的列表容器换成 `QuietSurface`。**根页只有导航行，控件仍在二级页**（偏差 #43 的红线不动）。

### 4.5 全部睡眠数据页——整体重做

原型 `StatsView.tsx` 的 `AllSleepData` 与现实现是两套形态，按原型重建。
**这一节取代** [2026-10-15-sleep-data-browsing-design.md](2026-10-15-sleep-data-browsing-design.md) §二。

#### 形态

1. 二级页外壳：返回胶囊 `统计` + 标题 `所有睡眠数据`
   （现实现是 `全部睡眠数据`；照原型改，入口按钮同步改成 `查看所有数据`）。
2. `SegmentedControl` **周 / 月 / 年**（现实现是 `按周 / 按月 / 按年`），**撑满宽度**（`expand: true`）。
3. **周期翻页行**：左右各一个 40×40 圆形按钮（底 `bgRaised`、箭头 `accent`），
   中间是周期标签（18px w700）+ `N 条睡眠记录`（12px muted）。
   初始锚点是**库里最新一条的醒来日**；翻页按周 / 月 / 年增减。
4. **汇总卡** `StatsDataHero`：
   - 左：`平均睡眠时长` 眉题 + 36px 数字 + `小时`（16px w600）；右：`已达到睡眠目标`（`good` 色）
     / 不足时 `目标 7 小时`（muted）。
   - **柱状图** 高 176：周 = 7 根（标签 `一二三四五六日`，柱顶写 `X.X`，柱宽上限 28）；
     月 = 当月天数（标签只在 1 号与逢五的日子写日期，柱宽上限 14）；
     年 = 12 根（标签 `N月`，值取当月**平均**时长）。
     高度 = `时长 / 10 × 100%`，有值最低 5%、无值画 1% 的 `bgMuted` 淡条（`opacity .45`）。
     柱色为 `durationBandColor`，`opacity .86`。
   - 底部三格（上边框 1px）：`平均评分`（`scoreBandColor`）/ `达标率 %` / `记录夜数`。
   - **分母口径全部沿用 §5.2**：平均时长分母是**本周期内的记录条数**；
     平均评分**只计已评分的记录**，一条都没评分时写 `—`；达标率 = 时长 ≥ 7h 的条数 / 总条数。
5. **记录列表**：标题行 `睡眠记录` + `按日期倒序`，下面一个 `QuietSurface` 容器（半径 24）、
   行间 1px 分隔线。每行：日期徽章（44×44、`accentSoft` 底、日号 + `M月`）、
   时长 `X.X 小时` + 质量标签、`HH:MM 入睡 · HH:MM 起床`、右侧评分、`›`。
   点一行开既有详情弹层。
6. **周期内无记录**：`这个周期还没有睡眠记录` / `可切换其他周期查看历史数据`。

#### 必须守住的三条（原型没有，但本仓的红线）

- **`估算 NN` / `评分 NN` 的区分不许省。** 原型行内只写 `{aiScore}分`，
  而 `SleepEntry.score` 可能是模型给的、也可能是本地规则按质量与时长估出来的（`isEstimated`）。
  照首页同一条口径写全（偏差 #47 一族：**估算顶着「评分」两个字出场就是把本地规则说成了模型结论**）。
- **演示数据要说出来。** 汇总卡那三个数字把合成的与真实的混在一起，
  周期内含演示记录时在卡内补一句「其中 N 条是演示数据，不是你的记录」（只有调试构建里会有）。
  **报的是「这个周期内」的条数，不是全库的**：卡里三个数字都是本周期的，
  报一个全库条数等于描述一个不在这屏上的集合。

**两处实现细节，都是实现时定的：**

- **月 / 年翻页把日归到 1 号**（`DateTime(y, m ± 1, 1)` / `DateTime(y ± 1, 1, 1)`）。
  锚点是「最新记录的醒来日」，可能是 31 号，`DateTime(2026, 10, 31)` 加一个月会**溢出**成
  12-01，向后翻就会跳过一个月。锚点落在周期内哪一天都得到同一个窗口，所以归到 1 号不影响语义。
- **柱顶数值只有周视图写**（`period === "week" ? value.toFixed(1) : ""`，原型如此）。
  月的柱位只分到十几像素，年那 12 根更要同时放下「12月」和数值，写不下；
  月视图的日期标签因此比周 / 年小一档（9px 对 10px），也都是原型的取值。
- **空库仍是整页空状态**（`还没有睡眠记录`），不是「这个周期没有记录」——
  一个记录都没有时，后者会让人以为是翻错了周期。

#### 领域改动

`sleep_history.dart` 从「一次分好全部组」改成「给一个锚点，算出一个周期窗口」：

```dart
enum HistoryGrouping { week('周'), month('月'), year('年') }   // 标签缩短，照原型

class HistoryWindow {
  final HistoryGrouping grouping;
  final DateTime anchor;        // 锚点（本地日历日）
  final DateTime startDay;      // 周期首日
  final DateTime endDay;        // 周期末日
  final List<SleepEntry> entries;   // 周期内记录，最新在前
  final double? averageHours;   // 分母 = entries.length
  final int? averageScore;      // 只计已评分，全无则 null
  final int sufficientCount;    // 时长 >= 7h 的条数
  String get label;             // 2026年10月 / 2026年 / 2026年10月12日 – 10月18日
  int get sufficientRate;       // sufficientCount / entries.length，空窗口为 0
}
HistoryWindow windowOf({required List<SleepEntry> allEntries,
                        required HistoryGrouping grouping, required DateTime anchor});
List<HistoryWindow> recentWindows(...);   // 见下
DateTime latestAnchor(List<SleepEntry> allEntries);
```

**保留**：周一起算、`DateTime(y, m, d - n)` 构造而不是 `subtract(Duration)`（夏令时）、
周标签带年份、跨年两端各带年份、平均分只计已评分、平均时长分母是记录条数。
**新增**：`startOf` / `endOf` 从私有静态方法提为可直接测的纯函数。

**翻页不设边界**：向前可以翻到没有记录的周期（界面如实显示「这个周期还没有睡眠记录」），
向后不越过「最新一条所在周期」。原型两边都能点，但向后翻到未来永远只有空周期——
**把上一个按钮在「已经是最新周期」时禁用**，这是本实现对原型的一处小偏差（记入总规格 §8）。

## 五、分层与落点

| 层 | 文件 | 职责 |
| --- | --- | --- |
| 令牌（改） | `lib/core/theme/app_tokens.dart` | 新增 `good` 色（§3.2） |
| 控件（新增） | `lib/core/widgets/quiet_surface.dart` | `QuietSurface` |
| 控件（新增） | `lib/core/widgets/hero_surface.dart` | `HeroSurface`：渐变 + 可选局部令牌 + 角光晕 + 星点，五张 hero 卡共用一份绘制路径 |
| 控件（改） | `lib/core/widgets/glass_surface.dart` | **不动** |
| 页面（改） | `lib/features/home/presentation/home_page.dart` | 问候、`SleepHeroCard` + 结论条、安静实体卡、扁平记录列表 |
| 页面（改） | `lib/features/home/domain/home_insight.dart`（新增） | 结论条的两句话（纯函数，可单测） |
| 页面（改） | `lib/features/log/presentation/review_page.dart`、`log_page.dart` | 晨光 hero、`QualityChoice`、安静实体面 |
| 控件（改） | `lib/features/sleep/presentation/widgets/quality_rating.dart` | `QualityStars` → `QualityChoice`，文字药丸 + 即时反馈 |
| 领域（改） | `lib/features/sleep/domain/sleep_quality.dart` | 五个标签改名（§3.3） |
| 页面（改） | `lib/features/stats/presentation/stats_page.dart` | 两张 hero 卡 + 安静实体汇总卡 + 入口文案 |
| 页面（重做） | `lib/features/stats/presentation/all_sleep_data_page.dart` | §4.5 |
| 领域（改） | `lib/features/sleep/domain/sleep_history.dart` | §4.5 的 `HistoryWindow` |
| 页面（改） | `lib/features/settings/presentation/**` | `SettingsGoalHero` + 安静实体列表 |

## 六、取舍

- **`AppTokens` 只加一个 `good`。** 其余颜色全部沿用。这一轮看下来最反直觉的一点是：
  改动这么大的观感变化，令牌值一个都不用动——变的全在**用哪些材质、怎么分层**上。
- **首页 hero 局部改令牌，全局不动。** 与偏差 #32 对会话页的裁定同源：这张卡整晚挂在夜色里，
  与主题无关。代价是「一个概念两处定义」的嫌疑，所以 §2.1 那张表就是它的唯一出处。
- **命名质量状态保住了 1–5 的底层值**，评分口径因此一个字节没变。
- **全部数据页加了图表**，推翻了 [2026-10-15-sleep-data-browsing-design.md](2026-10-15-sleep-data-browsing-design.md)
  「不做什么」里那条「不给这一页加图表」。理由与代价见该文件 §二 的订正段落——
  **数字漂移的风险靠「聚合成领域纯函数、两页共用」挡掉**，不靠「只留一套图表」。
- **原型向后翻页不设边界，本实现禁用「下一个」按钮**：未来永远没有记录，
  让一个必然通向空状态的按钮可点是白费一次点击。

## 七、测试矩阵

| 层 | 场景 | 落点 |
| --- | --- | --- |
| 单元 | 结论条：无前六晚 / 差 0 分钟 / 差 9 分钟（不足 10 分钟走「基本持平」）/ 多睡 / 少睡；两行建议按时长 7h 分岔 | `test/home_insight_test.dart` |
| 单元 | 问候：四个时段边界（04:59 / 05:00 / 11:59 / 12:00 / 17:59 / 18:00 / 22:59 / 23:00） | 同上 |
| 单元 | 周期窗口：周一起算、周日的记录不属于本周；跨年两端带年份；月 / 年窗口起止；锚点落在周期内的哪一天都得到同一窗口；空窗口的平均为 `null`、达标率为 0；平均评分只计已评分 | `test/sleep_history_test.dart` |
| 单元 | `SceneToken.good` 浅色深色两个值都在；`QualityChoice` 的五个标签与五句反馈和 `estimateScore` 的档位一一对应 | `test/sleep_quality_test.dart` |
| Widget | 首页：眉题是 `早安 · …`（时间冻结在上午）；hero 卡里有结论条的两行；近七日卡与记录列表**不再是玻璃**；无阶段记录时三块阶段格仍然不出现 | `test/pages_widget_test.dart`（首页组） |
| Widget | 质量选择：五个药丸、初始一个都不选中、点第 4 个出现「状态不错」且前三格不亮；未选时不显示反馈句；会话结束评星弹层同样如此 | `test/review_page_test.dart`、`test/pages_widget_test.dart` |
| Widget | 全部数据页：默认周视图与 `N 条睡眠记录`；翻到上一周期换标签；已是最新周期时「下一个」禁用；切月 / 切年换柱数与标签；汇总卡三个数字；未评分行不写评分也不写占位；估算行写「估算 N」；演示记录报数；空库是整页空状态、周期内无记录是周期空状态 | `test/all_sleep_data_page_test.dart` |
| Widget（真实路由） | 统计页点 `查看所有数据` → 落到 `/stats/all`，返回后仍在统计页 | `test/pages_widget_test.dart` |
| 几何 | 三页在 390×844 下无溢出（含 30 天柱状图与扁平列表）；各 harness 声明 `disableAnimations` 之后 `pumpAndSettle` 能收敛 | `test/pages_widget_test.dart` |

## 八、未验证

> **2026-10-16 补记：这一节原本列在第一位的就是「观感没有目视核对」，而真机上一看就
> 抓出了 §2.6 那个 `color-mix` 的 bug（三张 hero 的底都浓了约 8 倍）。**
> 下面几条里，已经在真机上核过的就地标出来了，**没核过的仍然是没核过的**。

- ~~**观感没有目视核对**~~ → **已核（真机 MI 9，浅色与深色各一轮）**：首页夜色 hero、
  回顾晨光 hero、统计冷净 hero 与评分卡、全部数据页 hero、扁平记录列表、五个质量药丸，
  都已截图核对，并据此修掉 §2.6 那处换算错误。
- ~~**宽屏（≥768px）与 iPad 上的样子没看过**~~ → **已核（使用方 2026-10-16 晚在平板上看过，
  没问题）**。同一轮使用方还报出「全部数据页当前周期无数据时兜底组件没居中」，
  已复现并修复（`EmptyState` 的 `SizedBox`，见 §4.5 末与验证记录）。
- **月晕呼吸的节奏未核对**：5 秒周期、`scale 1.08` 是照原型抄的参数，
  在真机上是否显得躁、浅色主题下会不会抢注意力，没有结论。
- **`good` 薄荷绿在浅色底上的对比度未实测**：`#2E9E83` 是按 WCAG AA 正文对比度选的，
  但只落在小字与圆点上，实际可读性没量过。
- **命名质量状态的替换是产品决定，不是原型决定**：原型末层仍是星级。
  换掉之后老用户（如果有）看到的措辞变了，这一点没有使用方以外的评审。
- 记录很多时（数千条）全部数据页的滚动性能仍未量过（这一条从 v3.31 起就在，本轮没改）。
- **首页 hero 卡在 320 宽下会溢出，没修。** 实测（测试字体）作息那一行超出 31–36px。
  三点必须一起记：① **这不是本轮引入的**——那一行的结构、字号、间距与可用的 116px
  是逐字搬过来的，改动之前同样溢出；② 绝大部分是**测试字体的账**（测试环境每个字都是
  12px 见方的方块，`23:14` 量出来 60px，真字体约 30px；真字体下这一行需要约 108px，
  116px 装得下）；③ 要真正修好只能让作息行随宽度缩放或换行，两种都会改掉 390 / 430 下
  **已经验干净**的样子。**没有在真机上量过**，所以既不敢说它真机没事，也没动它。
- **`QuietSurface` 与 `HeroSurface` 的观感没有目视核对**：安静实体面与玻璃卡同屏时的
  层次差、hero 渐变在深色主题下的浓度，都只有几何与结构断言。
