# 官网与 Android 首版交付计划

## 范围与发布决策

- 官网代码从 `../sass-web` 整合到 `website/`，保留原有渐变、柔光、卡片与动效，替换为「夜深」实际功能和截图。
- 网站只提供中文介绍、真实 Android 截图、功能边界、隐私说明和 Android 下载页。
- Flutter 与官网共用已公开的 `abner-forever/night_sleep` 仓库；官网源码位于 `website/`，仅部署 `website/dist/` 到 GitHub Pages，不另建仓库。
- Android 首版由 Actions 构建并核验，再作为标明测试签名的 GitHub Pre-release 发布；不自动把每次 CI 产物发布为 Release。
- 用户随后明确要求按免费、公开项目继续发布。该指令是本次发布决策，不代表已取得第三方素材授权证明；原有素材来源与授权说明继续保留。
- iOS、macOS、Flutter Web 构建本次不发布。

## 实施步骤

1. 迁入网站源码，移除旧品牌、占位商店地址、虚构评价、价格、自动测量分期等描述。
2. 用现有真机截图和代码核实的功能介绍应用；检查桌面、手机和深浅主题。
3. 配置静态路径与下载页二维码；未发布 APK 时禁用 APK 下载，不生成虚假的 APK 链接。
4. 配置 GitHub Pages，发布实际可访问的网站。
5. 配置 Android CI：固定 Flutter 基线、Java、SDK，生成 Drift 代码，检查并构建 release APK，关闭演示数据。
6. 验证构建产物、版本、权限及签名；试用包使用明确标注的测试签名，后续正式版采用稳定签名。

## 本次交付（2026-10-20）

- 官网已部署：`https://abner-forever.github.io/night_sleep/`。
- `v0.49.0-preview.1` 试用版：应用版本 `0.49.0+1`，Android 7.0+，95,617,457 字节；关闭演示数据，含 arm64、armv7、x86_64。
- CI 静态检查通过，888 项测试通过，APK v2 签名校验通过；下载后 SHA-256 再次匹配。
- SHA-256：`920693df0754823a44dfb71512ba170d2d730f166fed6862eed7c5fcf7d0fe35`。
- 下载页显示版本、体积、校验值、试用签名说明；二维码指向实际 APK。首页二维码仍指向下载页。

## 后续正式发布

- 确认或替换五条助眠录音的分发授权，补齐模型转换件许可证说明。
- 正式包名仍待确定；`0.49.0-beta.2+3` 起已配置长期签名，私钥通过 GitHub Secrets 加密保存，具体保管与恢复见 `android-signing.md`。
- 真机验证首次安装、空数据启动、录音权限、锁屏录音、通知、导出和升级覆盖。
- 官网直接读取公开 GitHub Releases，发布新 APK 后无需修改官网文件或重新部署。使用 Release 列表包含预发布；版本、附件大小、直链及 SHA-256 来自 GitHub。未上传完成或缺少校验值的附件不开放下载。

## 应用内更新

- 设置页「关于」进入二级页，展示品牌与运行包版本，并保留隐私协议、软件著作权和 APP 备案号入口。版本格式为 `0.49.0（Beta 2）`，不展示构建号、渠道等细项；备案与软著尚无实际登记信息，点击时提示。Android 在设置的关于行检查一次并标记新版；关于页点击版本号检查，没有新版时提示「当前是最新版」，发现新版后才弹出更新操作。
- 复用公开 GitHub Releases 与现有 `release.json`，不增加发布后台。按语义版本排序，并要求构建号递增；Beta / RC 接收后续测试版和正式版，正式版只接收正式版。仅公开且附件上传完整的版本参与更新。
- 用户在更新弹层选择「立即更新」后展示进度、支持取消；下载完成核对大小和 SHA-256，再由 Android 核对包名、版本与当前签名并打开系统安装器。需要安装来源授权时引导至系统设置，返回后点击版本号打开弹层并「继续安装」，复用已下载的文件；取消系统安装后可再次安装。
- APK 位于应用缓存 `updates/`，新下载自动替换旧文件；取消或失败删除未完成文件。清除缓存后再次安装会重新下载。覆盖更新保留本地数据，旧测试签名或 debug 包无法覆盖长期签名版本，会提示先导出再迁移。
- iOS 不请求 Android 更新接口；App Store 地址由 `appStoreUrlProvider` 预留，当前无真实地址时仅在点击版本号后提示「暂未开放 App Store 更新」，不展示独立占位入口。
- 验收包含版本筛选、元数据/下载完整性、取消重试、授权返回与页面状态测试；Android 真机下载、授权、安装覆盖及设备厂商差异仍需实际安装后验证。
- 隐私协议在官网 `/#/privacy` 维护，App 内使用系统 WebView 加载同一链接，支持随 App 配色、加载进度、失败／超时重试和返回。当前隐私联系邮箱为 `1661287843@qq.com`；协议依据本地记录、录音、洞察、更新、权限和导出行为说明，不代表已完成正式上架的全部隐私授权流程。官网部署后公开链接才生效。

## Beta 版本与后续自动发布

- `pubspec.yaml` 是唯一构建版本来源：`0.49.0-beta.1+2` 对应 Android `versionName=0.49.0-beta.1`、`versionCode=2`；后续如 `0.49.0-beta.2+3`。`versionCode` 必须大于所有已分发版本，包括正式版与其他渠道，不随版本名重置。
- APK 按 `night-sleep-<versionName>-android.apk` 命名，Actions Artifact 名额外包含构建号。CI 核验 APK 实际版本与源码一致、非 debuggable、签名有效，生成 SHA256SUMS、package-info、signature、release.json 和说明。
- 主分支 push 与 workflow_dispatch 仅构建。显式推送 `v<versionName>` 标签触发发布：全部检查通过、标签与包版本一致后，先建草稿并上传附件，再公开 Release。Beta / RC 标记为 Pre-release，禁止覆盖已存在的版本。
- 官网采用五分钟成功缓存；接口失败可回退一天内已验证缓存并提示，提供重试和官方 Release 页面入口。无缓存不伪造下载链接；不在前端配置 GitHub Token。
- 占位包名仍为 `com.example.night_sleep`。首个长期签名版本为 `0.49.0-beta.2+3`，旧测试签名包需先导出记录再卸载迁移；真机升级验证仍需单独完成。
- Beta 构建已在独立分支 `codex/android-beta-0.49.0-1` 完成（Actions run `39383819162`）：静态检查、应用测试、APK 构建及签名校验通过。下载后验证 `versionName=0.49.0-beta.1`、`versionCode=2`、95,617,461 字节，SHA-256 为 `ca77e22c2f06166dc113bc7999a020d77e1c22d7d1902551b5e0881d096ec4f4`。
- 首次本地验收阶段交付路径：`build/beta/0.49.0-beta.1/night-sleep-0.49.0-beta.1-android.apk`（构建产物不入库）。该阶段未创建公开 Beta Release、未部署官网；公开发布改用下述长期签名 Beta 2。

## 长期签名迁移（2026-10-20）

- 用户确认更换为项目自己的签名。已生成 RSA 4096 位 PKCS#12 密钥库，证书有效至 2054-03-07，公钥指纹为 `5faa548ec06acb039808c8d8fe361f0b2601c91599c8f74c981a170fdebb9851`。
- 本地密钥、口令及恢复副本位于被 Git 忽略的私密路径，GitHub Actions 四项 Repository Secrets 已配置。私钥与口令不进入 Git、Artifact 或 Release。
- release 构建不再回退到 debug 签名；CI 在构建前后核验固定证书指纹。工作流结束始终清理恢复的密钥，生成元数据标注 `signing=release`。
- 独立分支 `codex/android-release-signing` 用于实际签名构建验证。发布时将代码提交主分支并推送 `v0.49.0-beta.2` 标签，由标签工作流重新检查、构建并发布长期签名 Beta 2，官网独立部署后自动读取 Release。
- Actions run `39392010670` 已完成：签名恢复及指纹核对、应用静态检查和测试、release 编译、APK 签名核验、产物上传、私钥清理均成功；发布步骤未触发。
- 下载后再次核对：`0.49.0-beta.2+3`、95,617,461 字节、单一签名者 `Night Sleep Android Release`，APK SHA-256 为 `9c3df5c78e63fc8a38fa0361b22f91ca4660d97a5145e576762907d6026dd634`。交付文件为 `build/beta/0.49.0-beta.2/night-sleep-0.49.0-beta.2-android.apk`。
