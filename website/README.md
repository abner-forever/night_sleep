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

网站沿用原 `sass-web` 的玫瑰至暖橙渐变、柔光背景、卡片投影、滚动入场和鼠标视差。默认跟随系统，支持浅色、深色主题；文案依据当前应用，截图来自 `../docs/images/`，转换为 WebP。截图中包含演示数据，不表示每次启动都有这些记录。

## GitHub Pages

发布地址：`https://abner-forever.github.io/night_sleep/`。

仓库设置 `Settings → Pages → Source → GitHub Actions`。推送 `website/` 或官网工作流到 `main` 后，`.github/workflows/website.yml` 自动检查并部署 **仅 `website/dist/`**。

Vite 使用相对资源路径；HashRouter 提供 `/#/download` 下载页，直接打开或刷新不依赖服务端路由回退。不要把 `website/` 内容复制进 Flutter 的 `web/`。

## Android 下载与二维码

`public/download.json` 是唯一下载状态来源。尚未发布时：

```json
{ "available": false }
```

这时按钮禁用，二维码指向当前站点的下载页，并明确标注不是 APK 下载码。二维码使用页面实际地址，因此适配 GitHub Pages 子路径和本地预览。

公开发布已验证 APK 后，配置：

```json
{
  "available": true,
  "url": "https://github.com/abner-forever/night_sleep/releases/download/实际标签/night-sleep.apk",
  "version": "0.49.0",
  "sha256": "替换为该文件的64位SHA256",
  "size": 12345678
}
```

只接受 HTTPS APK 链接、有效版本号、文件大小和完整 SHA-256。元数据错误、请求失败或未发布时保持不可下载；不使用 App Store、Google Play 或第三方演示地址。发布后页面自动将按钮与二维码同步为 APK 直链。

当前提供 `v0.49.0-preview.1` Android 试用包，使用测试签名，本次安装包尚未完成真机安装和整夜录音验证。后续 CI 不自动发布 Release；核验产物并上传后再更新元数据。详见 `../docs/release-plan.md`。

## 迁移来源

由原 `../sass-web` 的 React / Vite 工程整合，保留原有设计与交互，以及二维码和主题能力。品牌改为「夜深」，移除原先与当前应用不符的睡眠测量承诺、商店占位链接、虚构评价和收费套餐。以本目录为后续维护入口。
