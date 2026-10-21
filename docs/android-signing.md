# Android 长期签名

夜深 release 构建统一使用项目专用的 RSA 4096 位签名。Beta 与正式版本共用此证书，不再使用 Android Debug 证书。当前 Android 包名为 `com.abner.night_sleep`，已替换旧占位包名 `com.example.night_sleep`；更换包名不需要重新生成签名密钥。

## 本地文件

- `android/signing/night-sleep-release.p12`：加密的 PKCS#12 密钥库，别名为 `night-sleep-release`。
- `android/key.properties`：本机构建配置，含密钥库路径、类型和口令。以上两项均已被 Git 忽略。
- `android/signing/night-sleep-signing-backup-2026-10-20.zip`：完整恢复副本，包含密钥库与口令文件。该备份包含完整签名权限，按私钥保管，只放入个人密码管理器或加密离线存储，不上传 Release、构建附件或公开网盘。
- `android/release-certificate.pem` 和 `android/release-certificate.sha256`：可公开的证书与指纹，可以提交仓库，不包含私钥。

证书 SHA-256：`5faa548ec06acb039808c8d8fe361f0b2601c91599c8f74c981a170fdebb9851`。

本地私密文件权限为 `0600`，目录为 `0700`。换电脑时，将恢复副本里的文件按原目录放回，再执行 release 构建。不要在日志、聊天或终端输出口令。丢失签名后，官网下载用户无法再用原身份正常覆盖升级，因此请另外保存一份加密备份。

## GitHub Actions

仓库 `Settings → Secrets and variables → Actions` 使用以下四个 Repository Secrets：

| Secret | 用途 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | 密钥库的 Base64 内容，必须通过 GitHub 公钥加密的 API 或官方 Secrets 界面提交 |
| `ANDROID_KEYSTORE_PASSWORD` | 密钥库口令 |
| `ANDROID_KEY_ALIAS` | `night-sleep-release` |
| `ANDROID_KEY_PASSWORD` | 密钥口令（本 PKCS#12 与密钥库口令一致） |

工作流通过 `tool/configure_android_signing.py` 恢复临时文件，并先用 keytool 导出公开证书核验指纹，构建结束后始终清理。签名配置缺失时 release 构建立即失败，不回退到 debug。日常 debug 构建仍使用开发调试证书，无需发布私钥。

产物打包时，`tool/android_release.py` 再次调用 apksigner 校验 APK，并要求唯一签名者与仓库固定指纹一致。`release.json` 标注 `signing=release` 及 `certificate_sha256`，签名详情和 SHA-256 随产物保存。只有非私密构建产物会进入 Actions Artifact / Release。

## 首次迁移

首个长期签名版本为 `0.49.0-beta.2+3`。此前 preview / beta.1 使用 Android Debug 签名，无法通过普通覆盖安装迁移到新证书。先导出记录，再卸载旧包、安装新版；卸载会清除本地数据。此后同包名、同证书且递增 versionCode 的版本才具备常规升级条件；真机升级覆盖仍需实测。

后续不要为每次构建生成新密钥，也不要随意替换本证书。若以后接入 Google Play App Signing，需另外规划商店应用签名密钥与上传密钥，并考虑与官网 APK 的签名一致性。

## 包名迁移（2026-10-21）

`0.49.0` 及之前的安装包使用 `com.example.night_sleep`。新包名 `com.abner.night_sleep` 在 Android 中属于另一个应用，无法覆盖升级旧包，旧应用的数据库、录音与设置不会自动迁移。两个包名可以分别安装；请在旧应用中导出需要保留的记录，确认备份后再决定是否卸载旧应用。当前导出功能用于保留数据，不代表新应用支持导入恢复。
