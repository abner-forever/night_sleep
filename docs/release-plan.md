# 官网与 Android 首版交付计划

## 范围与发布决策

- 官网代码从 `../sass-web` 整合到 `website/`，沿用 React、Vite 与二维码组件，按「夜深」实际功能重新设计。
- 网站只提供中文介绍、真实 Android 截图、功能边界、隐私说明和 Android 下载页。
- Flutter 与官网共用已公开的 `abner-forever/night_sleep` 仓库；官网源码位于 `website/`，仅部署 `website/dist/` 到 GitHub Pages，不另建仓库。
- Android 首版产物通过 Actions artifact 交付，不自动创建公开 Release。公开仓库的 Actions 日志及产物并非保密存储。
- 用户已于 2026-10-19 确认：先完成官网和内部 APK 构建；助眠录音与模型授权确认后才开放公开下载。
- iOS、macOS、Flutter Web 构建本次不发布。

## 实施步骤

1. 迁入网站源码，移除旧品牌、占位商店地址、虚构评价、价格、自动测量分期等描述。
2. 用现有真机截图和代码核实的功能介绍应用；检查桌面、手机和深浅主题。
3. 配置静态路径与下载页二维码；未发布 APK 时禁用 APK 下载，不生成虚假的 APK 链接。
4. 配置 GitHub Pages，发布实际可访问的网站。
5. 配置 Android CI：固定 Flutter 基线、Java、SDK，生成 Drift 代码，检查并构建 release APK，关闭演示数据。
6. 验证构建产物、版本、权限及签名；内部包使用明确标注的测试签名，不能作为长期公开分发签名。

## 公开 Android 下载的后续条件

- 确认或替换五条助眠录音的分发授权，补齐模型转换件许可证说明。
- 采用正式包名与长期保管的签名证书，在 GitHub Secrets 配置签名；不要提交私钥、口令或 `.jks`。
- 真机验证首次安装、空数据启动、录音权限、锁屏录音、通知、导出和升级覆盖。
- 将已验证 APK 放入公开 Release，维护 `website/public/download.json`；网站才开启 APK 下载与直链二维码。
