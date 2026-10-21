package com.example.night_sleep

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.Executors

class AppUpdateHandler(private val activity: Activity) : MethodChannel.MethodCallHandler {
    private val executor = Executors.newSingleThreadExecutor()

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "install") {
            result.notImplemented()
            return
        }
        executor.execute {
            try {
                val file = File(requireNotNull(call.argument<String>("path"))).canonicalFile
                val folder = File(activity.cacheDir, "updates").canonicalFile
                require(file.parentFile == folder && file.name == "update.apk" && file.isFile) {
                    "安装包已失效，请重新下载。"
                }
                val digest = MessageDigest.getInstance("SHA-256")
                file.inputStream().use { input ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        digest.update(buffer, 0, count)
                    }
                }
                val actualHash = digest.digest().joinToString("") { "%02x".format(it.toInt() and 0xff) }
                require(actualHash == call.argument<String>("sha256")) {
                    "安装包校验失败，请重新下载。"
                }
                val manager = activity.packageManager
                @Suppress("DEPRECATION")
                val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    PackageManager.GET_SIGNING_CERTIFICATES
                } else {
                    PackageManager.GET_SIGNATURES
                }
                @Suppress("DEPRECATION")
                val archive = manager.getPackageArchiveInfo(file.path, flags)
                    ?: throw IllegalArgumentException("无法读取安装包，请重新下载。")
                @Suppress("DEPRECATION")
                val installed = manager.getPackageInfo(activity.packageName, flags)
                require(archive.packageName == activity.packageName &&
                    archive.versionName == call.argument<String>("version") &&
                    versionCode(archive) == call.argument<Number>("buildNumber")?.toLong() &&
                    versionCode(archive) > versionCode(installed)) {
                    "安装包版本不匹配，请重新检查更新。"
                }
                val archiveSigners = signatures(archive)
                require(archiveSigners.isNotEmpty() && archiveSigners == signatures(installed)) {
                    "当前应用与新版签名不同，无法覆盖安装。请先导出睡眠记录，再按官网说明迁移。"
                }
                activity.runOnUiThread {
                    try {
                        if (activity.isFinishing || activity.isDestroyed) {
                            result.error("activity_unavailable", "请返回应用后重试安装。", null)
                        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                            !manager.canRequestPackageInstalls()) {
                            activity.startActivity(Intent(
                                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:${activity.packageName}")
                            ))
                            result.success(false)
                        } else {
                            val uri = FileProvider.getUriForFile(
                                activity, "${activity.packageName}.updates", file
                            )
                            activity.startActivity(Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(uri, "application/vnd.android.package-archive")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            })
                            result.success(true)
                        }
                    } catch (error: Exception) {
                        result.error("installer_unavailable", "无法打开系统安装界面，请稍后重试。", null)
                    }
                }
            } catch (error: Exception) {
                activity.runOnUiThread {
                    result.error("invalid_apk", error.message ?: "安装包校验失败，请重新下载。", null)
                }
            }
        }
    }

    private fun versionCode(info: PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.longVersionCode
        else {
            @Suppress("DEPRECATION")
            info.versionCode.toLong()
        }

    private fun signatures(info: PackageInfo): Set<String> {
        val signers = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.signingInfo?.apkContentsSigners
        } else {
            @Suppress("DEPRECATION")
            info.signatures
        }
        return signers?.map { it.toCharsString() }?.toSet() ?: emptySet()
    }

    fun dispose() {
        executor.shutdown()
    }
}
