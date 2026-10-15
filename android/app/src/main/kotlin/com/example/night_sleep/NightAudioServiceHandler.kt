package com.example.night_sleep

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * 应用此刻可不可见（至少有一个 Activity 处于「已开始」状态）。
 *
 * 由 `MainActivity.onStart` / `onStop` 维护——**不用 `onResume` / `onPause`**：
 * 系统权限弹框、通知抽屉拉下来这些都会走 pause，而那时候应用其实还在屏幕上，
 * 拿着 pause 当「不可见」，用户一边看着界面一边被拒掉录音。
 *
 * 读它的是 [NightAudioServiceHandler]：起前台服务这件事只有在应用可见时才合法、
 * 才有意义。
 *
 * 状态是进程级的：Activity 会因配置变更重建（清单里 `configChanges` 含
 * `orientation` 等），重建过程中 `onStart` 会再走一次，把它置回 true。
 */
object AppVisibility {
    @Volatile
    var visible: Boolean = false
}

/**
 * `night_sleep/recording_service` 的 Android 实现。
 *
 * 只有两个方法，与 `lib/core/platform/night_audio_service.dart` 一一对应：
 * - `start` → 返回一个**字符串结果码**（`"started"` / `"notForeground"` /
 *   `"missingPermission"` / `"failed"`），Dart 侧照它决定「开流还是不开流」；
 * - `stop` → 撤服务，返回 null。
 *
 * **结果码一律用 `result.success(...)` 回，不用 `result.error(...)`。** 这不是风格问题：
 * Dart 侧把 `PlatformException` 当成「通道坏了」，把 `MissingPluginException` 当成
 * 「本平台没有这条通道」。用 `error` 回一个「应用不在前台」，Dart 那边只会看到
 * 「failed」——一条真正的原因就在信封里被抹掉了。
 *
 * 文案（给用户看的中文）**一律在 Dart 侧**，这里只回码。iOS 上根本没有这条通道，
 * 也就不存在一份需要同步维护的说法。
 */
class NightAudioServiceHandler(private val context: Context) : MethodChannel.MethodCallHandler {

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> result.success(startService())
            "stop" -> {
                NightRecordingService.stop(context)
                result.success(null)
            }
            // 不认识的 method 交给框架的默认实现（Dart 侧会收到
            // MissingPluginException，`NightAudioService` 把它归到 unsupported）。
            else -> result.notImplemented()
        }
    }

    /** 起服务，返回结果码。**这个方法不抛**。 */
    private fun startService(): String {
        // **闸口一：应用可见吗。** 两条理由：
        // - targetSdk ≥ 31 起，后台起前台服务抛 `ForegroundServiceStartNotAllowedException`；
        // - API 30 上不抛，但后台拿不到麦克风，服务起来了也只会收到数字静音。
        //
        // 这一句就是「白噪音倒计时到点时应用已经锁屏」那条路的闸口：Dart 的
        // `Timer.periodic` 在进程活着时照常到点，醒来就去起服务。当场回
        // `notForeground`，界面就如实写「应用不在前台 · 暂时无法开始录音」，
        // 而不是先写「录音中」再等 60 秒翻成「被系统静音」。
        if (!AppVisibility.visible) return CODE_NOT_FOREGROUND

        // **闸口二：权限。** 两条都在这里查，而不是留给系统抛异常——异常落到
        // `catch (Throwable)` 里就只剩一个 `failed`，Dart 侧分不出「该更新应用」
        // 还是「通道坏了」。
        //
        // `RECORD_AUDIO` 查的是**此刻是否持有**：targetSdk ≥ 34 时系统在创建服务
        // 那一刻自己会校验它（while-in-use 权限，应用在后台就不算持有），我们只是
        // 把同一件事提前问一遍好回一个准确的原因码。
        if (!holds(Manifest.permission.RECORD_AUDIO)) return CODE_MISSING_PERMISSION
        // `FOREGROUND_SERVICE_MICROPHONE` 是**安装期**权限（normal 级别，不弹框）：
        // 清单里声明过就持有，返回 denied 只可能是**装着的那个包不是这一版代码**
        // ——所以 Dart 侧那句文案说的是「请更新应用」，不是「你的设备不行」。
        //
        // ⚠️ **这个检查只在 API 34+ 做，低版本做了就是自毁。** 这条权限是 API 34
        // 才进系统的；在它之前（本项目的验证机 MI 9 就是 API 30）系统**不认识这个
        // 字符串**，`pm list permissions` 里根本没有它，而 `checkSelfPermission`
        // 对一个未定义的权限返回的就是 `PERMISSION_DENIED`——与「清单里没声明」
        // 长得一模一样。结果会是**每一次起录音都被判成 missingPermission**，
        // 应用从此一声不录，而界面说的是「请更新应用」。这不是理论风险：本机
        // `adb shell pm list permissions` 实测只有 `FOREGROUND_SERVICE` 与
        // `INSTANT_APP_FOREGROUND_SERVICE`，没有带 MICROPHONE 的那条。
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE &&
            !holds(Manifest.permission.FOREGROUND_SERVICE_MICROPHONE)
        ) {
            return CODE_MISSING_PERMISSION
        }

        return try {
            NightRecordingService.start(context)
            CODE_STARTED
        } catch (t: Throwable) {
            // 到这里说明不是「不可见」也不是「没权限」，多半是系统级的其它限制
            // （后台受限、服务数上限…）。**如实报 failed，不猜具体原因**：
            // Dart 侧收到 failed 会照旧开流——拿不到前台服务不等于录不了音，
            // 应用此刻还在前台时本来就录得下来。
            Log.w(TAG, "起前台服务失败：${t.message}")
            CODE_FAILED
        }
    }

    private fun holds(permission: String): Boolean =
        ContextCompat.checkSelfPermission(context, permission) ==
            PackageManager.PERMISSION_GRANTED

    companion object {
        private const val TAG = "NightRecording"

        /** 与 Dart 侧 `MethodChannelNightAudioService` 的码表逐字对应，改一处必须改两处。 */
        const val CODE_STARTED = "started"
        const val CODE_NOT_FOREGROUND = "notForeground"
        const val CODE_MISSING_PERMISSION = "missingPermission"
        const val CODE_FAILED = "failed"
    }
}
