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

网站配色与 Flutter APP 对齐，采用蓝色至靛紫渐变、冷灰浅色底和黑色深色底；保留原 `sass-web` 的光斑面积与透明度、柔光背景、卡片投影、滚动入场和鼠标视差，光斑改为天蓝与靛紫。默认跟随系统，支持浅色、深色主题；文案依据当前应用，截图来自 `../docs/images/`，转换为 WebP。截图中包含演示数据，不表示每次启动都有这些记录。

## GitHub Pages

发布地址：`https://abner-forever.github.io/night_sleep/`。

仓库设置 `Settings → Pages → Source → GitHub Actions`。推送 `website/` 或官网工作流到 `main` 后，`.github/workflows/website.yml` 自动检查并部署 **仅 `website/dist/`**。

Vite 使用相对资源路径；HashRouter 提供 `/#/download` 下载页，直接打开或刷新不依赖服务端路由回退。官网独立维护，Flutter Web 工程已移除。

## Android 下载与二维码

官网直接请求公开接口 `GET https://api.github.com/repos/abner-forever/night_sleep/releases?per_page=30`，无需后端或访问令牌。使用列表接口是为了包含 Beta / RC 预发布版本；`releases/latest` 不包含预发布版本。按语义版本选择最新的有效 Android 包，不依赖 Release 创建顺序。

版本、直链、体积和 SHA-256 均来自 GitHub Release 及附件的 `digest`。只接受本仓库已公开、上传完成的 APK，要求版本化文件名和完整校验值；忽略草稿和没有可用附件的版本。首个 `0.49.0-preview.1` 旧包仅保留兼容。没有有效版本时禁用下载，二维码指向当前下载页。

页面在浏览器缓存成功结果 5 分钟；网络或匿名 API 限流时，最多使用 24 小时内已验证的缓存，并提示无法检查更新。没有缓存时提供重试与 GitHub Releases 入口。页面不嵌入 GitHub Token。

首页和下载页的二维码共用组件，中央使用应用图标，保留四模块白边并采用 H 级纠错；图标以 data URI 嵌入，保存 SVG 后也可完整显示。

发布新版本的流程：

1. 在根目录 `pubspec.yaml` 更新版本，例如 `0.49.0-beta.2+3`；每次对外分发递增 `+` 后的 Android `versionCode`。
2. 推送与包内版本一致的标签（例如 `v0.49.0-beta.2`）。Android Actions 检查、测试、构建并核验包内版本与签名，生成 `night-sleep-0.49.0-beta.2-android.apk`、校验文件及构建元数据。
3. 标签构建通过后，上传全部附件后公开 Release；Beta / RC 自动标记为 Pre-release。普通主分支 CI 与手动构建只保存 Actions Artifact，不自动发布。
4. 官网无需修改源码或重新构建；用户重新访问页面、缓存到期后会自动获取新版本。草稿阶段不会被官网读取，已有 Release 禁止覆盖。

官网保留 iOS 的 App Store 入口并标注「暂缓支持」。`0.49.0-beta.2+3` 起配置项目专用长期签名，早期测试签名版本需导出记录并卸载迁移；证书保管见 `../docs/android-signing.md`，真机验收边界见 `../docs/release-plan.md`。

## 迁移来源

由原 `../sass-web` 的 React / Vite 工程整合，保留原有设计与交互，以及二维码和主题能力。品牌改为「夜深」，移除原先与当前应用不符的睡眠测量承诺、商店占位链接、虚构评价和收费套餐。以本目录为后续维护入口。
