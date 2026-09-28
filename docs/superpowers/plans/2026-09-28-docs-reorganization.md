# 文档重组实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `PROJECT_SPEC.md` 迁入 `docs/superpowers/specs/`，拆出 `CHANGELOG.md`，并让 README / CLAUDE.md / 规格三者的重复内容各归一处。

**Architecture:** 先建新容器（CHANGELOG），再整体搬迁规格正文（纯移动，用 diff 证明逐字一致），然后在**已搬好的新文件上**做内容裁剪，最后更新散落各处的引用。顺序上把「移动」与「编辑」分开，这样移动那一步可以用 `diff` 精确证明无损。

**Tech Stack:** Markdown、git、grep/diff。**不涉及任何 Dart 代码改动。**

**设计依据:** `docs/superpowers/specs/2026-09-28-docs-reorganization-design.md`

## Global Constraints

- 文档一律中文；代码标识符保持英文。
- 文档间引用一律用**相对路径**，不用绝对路径，以便仓库整体移动。
- `docs/` 下新文件位于 `docs/superpowers/specs/`，到仓库根目录的相对路径是 `../../../`。
- 不改 `lib/`、`test/`、`integration_test/`、`tool/` 下任何文件。
- 不重写规格正文措辞。迁移时正文只允许三处差异：删头部变更史、§9 去逐项计数、改交叉引用。
- **重要前提**：本仓库当前只有一个提交，`PROJECT_SPEC.md`、`README.md`、`CLAUDE.md` 均**未被 git 跟踪**。因此不能用 `git mv`/`git rm` 处理它们，要用文件系统操作（`cp`、`rm`），再 `git add` 新路径。

---

### Task 1: 建立 CHANGELOG.md

**Files:**
- Create: `CHANGELOG.md`

**Interfaces:**
- Consumes: 无
- Produces: 根目录 `CHANGELOG.md`。Task 2 的规格头部会链接 `../../../CHANGELOG.md` 指向它。

- [ ] **Step 1: 先确认它还不存在**

Run: `ls CHANGELOG.md`
Expected: `No such file or directory`（确认是新建而非覆盖）

- [ ] **Step 2: 写入 CHANGELOG.md**

内容取自 `PROJECT_SPEC.md` 头部第 7–31 行的变更史段落，改为倒序的版本小节。**文字逐字沿用原文，不得改写或补写日期**（v2.0–v2.3 的原始记录里没有日期，就不要编）：

````markdown
# 变更记录

本文件记录「夜深」项目规格的版本变更。规格正文见
[docs/superpowers/specs/2026-09-28-night-sleep-design.md](docs/superpowers/specs/2026-09-28-night-sleep-design.md)。

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
````

- [ ] **Step 3: 校验**

Run: `grep -c "^## " CHANGELOG.md`
Expected: `5`

Run: `grep -n "^## " CHANGELOG.md`
Expected: 顺序为 `2.4（2026-09-28）`、`2.3`、`2.2`、`2.1`、`2.0`，最新的在最上面。

- [ ] **Step 4: 提交**

```bash
git add CHANGELOG.md
git commit -m "docs: 从规格头部拆出 CHANGELOG.md

变更史原本挂在 PROJECT_SPEC.md 开头，随版本增长会把规格正文越推越远。"
```

---

### Task 2: 搬迁 PROJECT_SPEC.md 到 specs/（纯移动）

**Files:**
- Create: `docs/superpowers/specs/2026-09-28-night-sleep-design.md`
- Delete: `PROJECT_SPEC.md`

**Interfaces:**
- Consumes: `CHANGELOG.md`（Task 1，头部链接指向它）
- Produces: 规格新路径 `docs/superpowers/specs/2026-09-28-night-sleep-design.md`。Task 3、4、5 都改这个文件或引用它。

**任务边界**：这一步**只**替换头部、删掉变更史，正文一个字不动。§9 的计数留到 Task 3。这样本步可以用 `diff` 干净地证明正文无损。

- [ ] **Step 1: 确认起点状态**

Run: `wc -l PROJECT_SPEC.md && head -3 PROJECT_SPEC.md`
Expected: `288 PROJECT_SPEC.md`，前三行为 `# 夜深：Flutter 睡眠记录 App 项目规格说明书`、空行、`> 版本：2.4（2026-09-28）`

- [ ] **Step 2: 复制到新路径**

```bash
mkdir -p docs/superpowers/specs
cp PROJECT_SPEC.md docs/superpowers/specs/2026-09-28-night-sleep-design.md
```

- [ ] **Step 3: 替换新文件的头部**

把新文件开头到 `## 1. 产品目标与交付原则` **之前**的整块（原第 1–32 行，即标题、`>` 引言块、五段变更史）替换为下面这块。注意保留原有的 Figma Make 原型链接：

````markdown
# 夜深：Flutter 睡眠记录 App 项目规格说明书

> 版本：2.4（2026-09-28）
> 用途：本项目的实现与验收基准。
> 设计原型：[Figma Make：睡眠记录 APP 设计](https://www.figma.com/make/hKbqp1qjtcNQmmiDtVvXpk/%E7%9D%A1%E7%9C%A0%E8%AE%B0%E5%BD%95APP%E8%AE%BE%E8%AE%A1)
> 变更史见 [CHANGELOG.md](../../../CHANGELOG.md)

## 1. 产品目标与交付原则
````

原头部第 2 行「用途：本目录 Flutter 项目的实现与验收基准」中的「本目录」不再成立，故改为「本项目」——这是头部替换的一部分，不算正文改动。

- [ ] **Step 4: 用 diff 证明正文逐字未变**

```bash
diff PROJECT_SPEC.md docs/superpowers/specs/2026-09-28-night-sleep-design.md
```

Expected: 差异**只**出现在文件头部（原文件的标题+引言块+变更史被替换）。从 `## 1. 产品目标与交付原则` 到文件末尾应当**没有任何差异行**。

若 `## 1.` 之后出现任何 `<` 或 `>` 行，说明复制或编辑出了偏差，停下修好再继续。

- [ ] **Step 5: 删除旧文件**

```bash
rm PROJECT_SPEC.md
```

- [ ] **Step 6: 校验旧路径已消失**

Run: `ls PROJECT_SPEC.md`
Expected: `No such file or directory`

Run: `grep -n "^## " docs/superpowers/specs/2026-09-28-night-sleep-design.md`
Expected: `## 1. 产品目标与交付原则` 至 `## 10. 尚需用户提供的外部资料`，共 10 个二级标题。

- [ ] **Step 7: 提交**

```bash
git add docs/superpowers/specs/2026-09-28-night-sleep-design.md
git commit -m "docs: PROJECT_SPEC.md 迁入 docs/superpowers/specs/

正文逐字保留，仅头部去掉变更史（已入 CHANGELOG.md）并改写用途说明。"
```

---

### Task 3: 规格 §9 去掉逐项用例计数

**Files:**
- Modify: `docs/superpowers/specs/2026-09-28-night-sleep-design.md`（第 9 章「测试与验收矩阵」表格）

**Interfaces:**
- Consumes: Task 2 产出的规格文件
- Produces: §9 只剩「场景 + 测试文件路径」，不再有 `（N 项）`。Task 5 压缩 README 验证记录时以此为依据。

**理由**：计数是 README 验证记录的职责，§9 的职责是「覆盖了哪些场景」。计数散在两处必然对不上。

- [ ] **Step 1: 先列出待改的行**

Run: `grep -n "项）" docs/superpowers/specs/2026-09-28-night-sleep-design.md`
Expected: 命中 §9 表格里的若干行，形如 `（2 项）`、`（14 项）`、`（9 项，含防止夹具空跑的自检）`、`（1 项，数据经 provider 覆盖而非 drift 流）`。

- [ ] **Step 2: 逐行删除计数括注**

对 §9 表格的每一行，删去计数括注；**若括注里还有非计数的说明，保留说明**：

| 改前 | 改后 |
| --- | --- |
| `✅ `test/sleep_math_test.dart`（2 项）` | `✅ `test/sleep_math_test.dart`` |
| `✅ `test/model_catalog_test.dart`（14 项）` | `✅ `test/model_catalog_test.dart`` |
| `✅ `test/app_sheet_test.dart`（9 项）` | `✅ `test/app_sheet_test.dart`` |
| `✅ `test/pages_widget_test.dart`（20 项）` | `✅ `test/pages_widget_test.dart`` |
| `✅ `test/sleep_score_test.dart`（12 项）` | `✅ `test/sleep_score_test.dart`` |
| `✅ `test/sleep_window_test.dart`（9 项）` | `✅ `test/sleep_window_test.dart`` |
| `✅ `test/sleep_statistics_test.dart`（11 项）` | `✅ `test/sleep_statistics_test.dart`` |
| `✅ `test/sleep_data_test.dart`（13 项）` | `✅ `test/sleep_data_test.dart`` |
| `✅ `test/schema_migration_test.dart`（9 项，含防止夹具空跑的自检）` | `✅ `test/schema_migration_test.dart`（含防止夹具空跑的自检）` |
| `✅ `test/segmented_control_test.dart`（4 项）` | `✅ `test/segmented_control_test.dart`` |
| `✅ `test/record_edit_delete_test.dart`（8 项）` | `✅ `test/record_edit_delete_test.dart`` |
| `✅ 同上（1 项，数据经 provider 覆盖而非 drift 流）` | `✅ 同上（数据经 provider 覆盖而非 drift 流）` |
| `✅ `test/noise_synth_test.dart`（15 项）` | `✅ `test/noise_synth_test.dart`` |
| `✅ `test/noise_sheet_test.dart`（6 项）` | `✅ `test/noise_sheet_test.dart`` |

**两处易错点**：

1. `test/pages_widget_test.dart` 在表里**出现两次**——一次带 `（20 项）`，一次不带。只改带计数的那行，另一行动不得。
2. §9 表格最后两行（`集成/真机`、`视觉检查`）的状态列里本来就没有计数括注，不要改动。

- [ ] **Step 3: 校验计数已清空**

Run: `grep -n "（[0-9]* 项" docs/superpowers/specs/2026-09-28-night-sleep-design.md`
Expected: 无输出（退出码 1）

Run: `grep -n "防止夹具空跑\|provider 覆盖" docs/superpowers/specs/2026-09-28-night-sleep-design.md`
Expected: 仍命中——证明非计数的说明被保留了，没有被一起删掉。

- [ ] **Step 4: 提交**

```bash
git add docs/superpowers/specs/2026-09-28-night-sleep-design.md
git commit -m "docs(spec): §9 覆盖矩阵去掉逐项用例计数

计数归 README 验证记录，§9 只管覆盖了哪些场景。"
```

---

### Task 4: 更新 CLAUDE.md（四处引用 + 去重）

**Files:**
- Modify: `CLAUDE.md:10, 15, 24, 31-52, 101`

**Interfaces:**
- Consumes: Task 1 的 `CHANGELOG.md`、Task 2 的规格新路径
- Produces: CLAUDE.md 不再引用 `PROJECT_SPEC.md`；不再复制 README 的网络/开关说明。

- [ ] **Step 1: 先确认待改位置**

Run: `grep -n "PROJECT_SPEC\|132\|DEMO_DATA\|flutter-io.cn\|GIT_CONFIG" CLAUDE.md`
Expected: 命中第 10、15、24、31–34、36–38、41–42、101 行附近。

- [ ] **Step 2: 改四处 `PROJECT_SPEC.md` 引用**

**第 10 行**，改前：
```
**动手前先读 `PROJECT_SPEC.md` 第 8 章「与原型的有意偏差」。** 里面 17 条都是刻意为之的，
```
改后：
```
**动手前先读 `docs/superpowers/specs/2026-09-28-night-sleep-design.md` 第 8 章「与原型的有意偏差」。**
里面 17 条都是刻意为之的，
```

**第 15 行**，改前：
```
新增或修改能力后，同步更新 `PROJECT_SPEC.md`（偏差表 / 测试矩阵）与 `README.md`（实现范围 / 验证记录）。
```
改后：
```
新增或修改能力后，同步更新该规格（偏差表 / 测试矩阵）与 `README.md`（实现范围 / 验证记录），
版本变更记入 `CHANGELOG.md`。
```

**第 101 行**，改前：
```
这四类 bug 各犯过至少一次，`PROJECT_SPEC.md` v2.2–v2.4 的变更记录就是它们的病历：
```
改后：
```
这四类 bug 各犯过至少一次，`CHANGELOG.md` 里 v2.2–v2.4 的变更记录就是它们的病历：
```

- [ ] **Step 3: 命令块去重**

把 `## 常用命令` 一节里、代码块之后的三个重复段落（演示数据开关、pub 镜像、iOS 构建代理）整体替换为一句指针，并把 `flutter test` 的注释去掉数字。

**改前**（`flutter test` 那一行）：
```
flutter test                     # 整套 132 项
```
**改后**：
```
flutter test                     # 整套测试
```

**改前**（代码块之后到「**不要改 `lib/**/*.g.dart`**」之前的全部内容，含三个小节）：
````
演示数据开关（默认 = `kDebugMode`，发布构建关）：

```bash
flutter run -d macos --dart-define=DEMO_DATA=true
flutter build macos --dart-define=DEMO_DATA=false
```

国内网络下 `pub get` / `build_runner` 需要镜像，否则卡在 pub.dev 超时：

```bash
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
```

iOS 构建另需代理（Flutter 3.47 走 SPM 解析插件，`sqlite3` 钩子还要从 GitHub Releases 下载库）。
完整前提、以及 `+/- 1` 的 `GIT_CONFIG_*` 变通，见 README「构建 iOS / macOS 的网络前提」。

```bash
flutter build ios --simulator --no-codesign    # 模拟器包，不需要签名
flutter build macos --debug
```
````

**改后**：
````
国内网络下的 pub 镜像、iOS / macOS 构建的网络前提与代理，以及演示数据开关 `DEMO_DATA`
（默认 = `kDebugMode`，发布构建关），见 README。
````

- [ ] **Step 4: 校验**

Run: `grep -n "PROJECT_SPEC" CLAUDE.md`
Expected: 无输出

Run: `grep -n "132\|flutter-io.cn\|GIT_CONFIG" CLAUDE.md`
Expected: 无输出

Run: `grep -n "CHANGELOG" CLAUDE.md`
Expected: 命中两处（第 15 行的更新约定、第 101 行的病历引用）

- [ ] **Step 5: 提交**

```bash
git add CLAUDE.md
git commit -m "docs(CLAUDE): 指向迁移后的规格路径，去掉与 README 重复的网络与开关说明"
```

---

### Task 5: 更新 README.md（引用 + 验证记录压缩）

**Files:**
- Modify: `README.md:3`、`README.md:187-207`（「验证记录」节的测试清单）

**Interfaces:**
- Consumes: Task 2 的规格新路径、Task 3 裁剪后的 §9
- Produces: `132` 这个数字在仓库中只剩 README 一处。

- [ ] **Step 1: 先确认待改位置**

Run: `grep -n "PROJECT_SPEC\|132\|_test.dart" README.md`
Expected: 命中第 3 行（`PROJECT_SPEC.md` 引用）、第 187 行（`132/132 通过`），以及第 188–207 行的逐文件清单。

- [ ] **Step 2: 更新第 3 行的规格引用**

**改前**：
```
「夜深」是一个中文、本地优先的睡眠记录 Flutter 应用。界面按 `PROJECT_SPEC.md` 第 2 章的
```
**改后**：
```
「夜深」是一个中文、本地优先的睡眠记录 Flutter 应用。界面按
`docs/superpowers/specs/2026-09-28-night-sleep-design.md` 第 2 章的
```

- [ ] **Step 3: 压缩验证记录里的测试清单**

**改前**：
```
- `flutter test` → **132/132 通过**
  - `sleep_math_test.dart` 2 项（跨午夜时长、统计分母）
  - `sleep_score_test.dart` 12 项（`estimateScore` 各时长档位、事件与质量权重、分档阈值）
  - `sleep_window_test.dart` 9 项（跨午夜/同日窗口、UTC 瞬时值、格式化往返）
  - `sleep_statistics_test.dart` 11 项（平均值分母、图表上下界、柱高钳制、计数口径）
  - `sleep_data_test.dart` 13 项（演示数据、CRUD 往返、醒来日归档、级联删除、不伪造内容）
  - `schema_migration_test.dart` 9 项（用**真实 v1 库文件**升级；含防止夹具空跑的自检）
  - `noise_synth_test.dart` 15 项（**波形层面**：确定性与八者互异、不削波、无直流、
    循环接缝连续、白/粉/棕噪过零率依次递减、雨与篝火瞬态更强、海浪包络起伏、
    森林含鸟鸣、WAV 头字段与钳制）
  - `noise_sheet_test.dart` 6 项（选中即交给播放器、再点停止、切换不重复 stop、
    播放失败如实报错且不显示为播放中、音量写回、关闭释放播放器）
  - `pages_widget_test.dart` 20 项（四页空状态与数据态、表单保存、设置写回、二次确认、
    二级页材质祖先与下划线、无阶段记录的主卡片、演示数据二级页、下拉不受裁剪）
  - `record_edit_delete_test.dart` 8 项（编辑/删除入口、演示数据不可编辑、表单预填、
    写回同一 id、不清空阶段、二次确认，以及走真实路由的端到端用例）
  - `app_sheet_test.dart` 9 项（蒙层独立淡入、点击把手关闭、下拉超阈值关闭、小幅下拉回弹、
    点击蒙层关闭、打开计数、不可关闭时忽略手势）
  - `model_catalog_test.dart` 14 项（模型列表解析、错误映射、密钥不外泄、无密钥不发请求、
    UTF-8 解码、内置列表核实日期）
  - `segmented_control_test.dart` 4 项（分段控件胶囊与分段同宽、位移成整数倍）
```
**改后**：
```
- `flutter test` → **132/132 通过**（各测试文件覆盖的场景见规格第 9 章）
```

**这是本计划中唯一会减少 README 信息量的一步。** 被删掉的是逐文件清单；等价的覆盖场景描述在规格第 9 章仍完整可查。删前请对照 Task 3 完成后的 §9 确认覆盖范围没有被漏掉，再动手。

- [ ] **Step 4: 校验**

Run: `grep -rn "132" --include="*.md" . | grep -v "^\./docs/"`
Expected: 只命中 `README.md` 一行（`132/132 通过`）

必须排除 `docs/`：本次的设计文档与这份计划文档为了说明「改前长什么样」，正文里**故意**引用了
`132` 这个旧数字。这是记录，不是重复——判断标准是「事实的归属」，不是字面量出现次数。

Run: `grep -n "PROJECT_SPEC" README.md`
Expected: 无输出

Run: `grep -n "_test.dart" README.md`
Expected: 无输出（逐文件清单已删；若还剩个别行，确认它们属于「界面截图巡检」等其它章节而非验证记录）

- [ ] **Step 5: 提交**

```bash
git add README.md
git commit -m "docs(README): 验证记录改为命令与结果，逐文件清单归规格 §9"
```

---

### Task 6: 终验

**Files:**
- 无改动（纯验证）

**Interfaces:**
- Consumes: Task 1–5 的全部产出
- Produces: 验收结论

- [ ] **Step 1: 旧文件名无残留引用**

Run: `grep -rn "PROJECT_SPEC" --include="*.md" .`
Expected: 只命中本次迁移的两份记录文档自身
（`docs/superpowers/specs/2026-09-28-docs-reorganization-design.md` 与
`docs/superpowers/plans/2026-09-28-docs-reorganization.md`）。其余任何位置出现即为失败。

- [ ] **Step 2: 目标结构就位**

Run: `ls -1 CHANGELOG.md README.md CLAUDE.md docs/superpowers/specs/*.md docs/superpowers/plans/*.md`
Expected: 五类文件都在；`PROJECT_SPEC.md` 不在其中。

- [ ] **Step 3: 证明没碰代码**

Run: `git log --oneline`
Expected: 本计划产生 5 个新提交，每个都只涉及 `.md` 文件。

Run: `git show --stat --oneline HEAD~4..HEAD`
Expected: 变更文件全部是 `.md`，没有 `lib/`、`test/`、`integration_test/`、`tool/` 下的路径。

- [ ] **Step 4: 代码基线未受影响**

Run: `flutter analyze`
Expected: `No issues found`

Run: `flutter test`
Expected: `All tests passed!`（本次未动代码，结果应与迁移前一致）

若 `flutter analyze` 因未装依赖而报错，先 `flutter pub get`；国内网络需镜像，见 README。
按规格「验收方式」第 5 条，本步的目的是**证明确实没动到代码**——若分析器或测试出现与迁移前不同的结果，说明改到了不该改的地方，必须停下排查。

- [ ] **Step 5: 无需提交**

本任务不产生文件改动。若 Step 1–3 全部符合预期，迁移完成。
