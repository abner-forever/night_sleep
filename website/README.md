# 夜深官网

官网与 Flutter 共用 `abner-forever/night_sleep` 仓库。这个目录是独立的 React + Vite 静态网站，不构建 Flutter Web，也不需要接口服务。

## 本地运行

```sh
cd website
npm ci
npm run dev
```

```sh
npm run check
npm run build
npm run preview -- --host 127.0.0.1
```

网站结合 SaaS 展示风格与当前 Flutter APP 的视觉语言：浅蓝底、白色实体卡片、深蓝主题和纯蓝主按钮沿用应用配色；渐变标题、蓝紫柔光、设备展示光环、滚动入场和轻微鼠标视差保留官网的科技感。内容卡片使用更轻的投影、圆角与悬浮反馈，较强层次集中在设备展示及下载区。默认跟随系统，支持浅色、深色主题。首页和睡眠回顾展示当前应用截图；「应用预览」可切换概览、会话、声音面板、统计与设置，同时展示手机和 iPad 的实际布局，截图随网站主题切换。会话仍使用应用自身的独立深色界面。

## 截图维护

当前图片于 2026-10-23 从 iPhone 16 Pro 与 iPad Pro 11 英寸（M4）竖屏模拟器重新采集，包含演示数据；Flutter 截图不含原生状态栏与手势条。iPad 使用真实侧栏 / 宽屏界面，图片保持各自比例，不裁切成手机截图。

在仓库根目录运行 `integration_test/visual_upgrade_test.dart`，按根目录 README 的说明保存手机和平板深浅主题截图，再执行：

```sh
python3 tool/update_website_screenshots.py screenshots/<本轮目录>
```

转换脚本需要 Pillow。它从同一批原图更新 `docs/images/` 的精选 PNG 与本目录 `public/screenshots/` 的 WebP，手机宽 720、平板宽 1000，等比缩放。命名为 `<页面>.webp` / `<页面>-dark.webp`，iPad 文件增加 `ipad-` 前缀；页面映射见脚本的 `SCREENS`。界面更新后需同时检查官网深浅主题、窄屏和宽屏，避免图片缺失或设备比例失真。

## GitHub Pages

发布地址：`https://abner-forever.github.io/night_sleep/`。

仓库设置 `Settings → Pages → Source → GitHub Actions`，`github-pages` 环境允许 `beta` 和 `main` 部署。推送 `website/` 或官网工作流到任一分支后，`.github/workflows/website.yml` 自动检查并部署 **仅 `website/dist/`**；官网源码始终取自 `beta`，官网维护无需等待 App 正式发布。

Vite 使用相对资源路径；HashRouter 提供 `/#/download` 下载页，直接打开或刷新不依赖服务端路由回退。官网独立维护，Flutter Web 工程已移除。

## 隐私协议

完整协议由 `src/pages/PrivacyPolicy.jsx` 维护，入口在官网页脚，公开地址为 `https://abner-forever.github.io/night_sleep/#/privacy`。内容依据当前本地数据库、录音保留、可选洞察请求、权限、导出、更新及官网存储行为起草，隐私邮箱为 `1661287843@qq.com`，个人开发者暂按项目账号 `abner-forever` 标识；正式发布前需由运营者核实主体标识、联系方式和实际处理行为。

App 的“关于夜深 → 隐私协议”使用系统 WebView 打开同一页面，附加 `?app=1&theme=light`（或 `dark`）到 hash 路由后，以隐藏官网导航和页脚并匹配 App 主题。原生页提供返回、加载指示、失败与超时重试；外部政策和邮箱链接交给系统处理，不向网页暴露本地数据或 JavaScript 通道。

修改后需先部署官网，公开协议地址才会展示新内容。更新协议时同步维护更新／生效日期；涉及新增敏感信息、第三方或跨境处理时，还需核实相应告知与授权流程。

## Android 下载与二维码

官网主入口请求公开接口 `GET https://api.github.com/repos/abner-forever/night_sleep/releases/latest`，仅提供最新正式版；旁边的 Beta 入口请求 `GET https://api.github.com/repos/abner-forever/night_sleep/releases?per_page=30`，按语义版本筛选最新预发布包。无需后端或访问令牌，正式版不会被后续多个 Beta 挤出列表；尚无正式版时主入口明确提示，Beta 仍可单独下载。

版本、直链、体积和 SHA-256 均来自 GitHub Release 及附件的 `digest`。只接受本仓库已公开、上传完成的 APK，要求版本化文件名和完整校验值；忽略草稿和没有可用附件的版本。首个 `0.49.0-preview.1` 旧包仅保留兼容。没有有效版本时禁用下载，二维码指向当前下载页。

页面分别缓存两个渠道的成功结果 5 分钟；网络或匿名 API 限流时，最多使用 24 小时内已验证的对应渠道缓存，并提示无法检查更新。某一渠道成功不会延长另一渠道过期缓存。没有缓存时提供重试与 GitHub Releases 入口。页面不嵌入 GitHub Token。

首页和下载页的二维码共用组件，中央使用应用图标，保留四模块白边并采用 H 级纠错；图标以 data URI 嵌入，保存 SVG 后也可完整显示。

发布新版本的流程：

1. 日常将应用变更合并到 `beta` 并推送，自动发布 Beta。只有明确要求发布正式版时，才将 `beta` 合并到 `main` 并推送，自动发布正式包，随后同步回 `beta`。
2. Android Actions 根据发布历史和 Conventional Commits 自动计算版本、Beta 序号与全局构建号，检查、测试、构建并核验版本与长期签名；不需要修改 `pubspec.yaml` 或打标签。
3. 构建通过后，针对源码提交自动创建标签，仅上传 APK 和 App 检查更新所需的 `release.json`，再公开 Release；核验文件保留在 Actions Artifact，说明放在发布正文。Beta 标记为 Pre-release，正式版设为 Latest。重跑已发布提交不产生重复版本；详细规则见 `../docs/release-plan.md`。
4. 官网无需修改源码或重新构建；用户重新访问页面、缓存到期后会自动获取新版本。草稿阶段不会被官网读取，已有 Release 禁止覆盖。

官网保留 iOS 的 App Store 入口并标注「暂缓支持」。`0.49.0-beta.2+3` 起配置项目专用长期签名，早期测试签名版本需导出记录并卸载迁移；证书保管见 `../docs/android-signing.md`，真机验收边界见 `../docs/release-plan.md`。

## 迁移来源

由原 `../sass-web` 的 React / Vite 工程整合，保留原有设计与交互，以及二维码和主题能力。品牌改为「夜深」，移除原先与当前应用不符的睡眠测量承诺、商店占位链接、虚构评价和收费套餐。以本目录为后续维护入口。
