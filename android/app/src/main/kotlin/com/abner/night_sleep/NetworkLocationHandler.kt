package com.abner.night_sleep

import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * 取一次「城市级」当前位置：只问系统的 **network provider**。
 *
 * **为什么不直接用 geolocator。** 它在 Android 上把 provider 选成了 GPS：
 * `LocationManagerClient.determineProvider()` 的顺序是
 * `passive → fused(仅 API 31+) → GPS → NETWORK`，只要 GPS provider 处于
 * 「可用」状态就永远轮不到 network。而 GPS 的「可用」并不代表「有信号」——
 * 在室内它一个 fix 都给不出来。实测小米 9（Android 11 / MIUI 12.5）上，
 * 走 geolocator 的每一条取位路径都稳定超时：
 *
 * ```
 * 融合定位 low / best      -> 超时（Google FLP 在境内不可用，但 GMS 包在，
 *                             插件不会回退 LocationManager）
 * LocationManager low/medium -> 超时（请求被系统标成 ACCURACY_BLOCK 并派给 gps）
 * 位置流 10s                -> 无事件
 * lastKnownPosition         -> 5 分钟前的 network 结果（2000m）
 * ```
 *
 * 同一台机器上直接问 network provider，**67ms** 就拿到刚采到的坐标
 * （`ageMs=4`，来自基站与 WiFi，精度约 2km）。城市级天气要的正是这个精度，
 * 精确到楼栋没有意义，反而多一次被拒的机会。
 *
 * 失败一律回 `null`，由 Dart 侧决定下一步：定位是天气卡片的旁路，
 * 这里不允许抛异常把整张卡片带下去。
 */
class NetworkLocationHandler(private val context: Context) : MethodChannel.MethodCallHandler {

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "current") {
            result.notImplemented()
            return
        }

        val timeoutMs = (call.argument<Int>("timeoutMs") ?: DEFAULT_TIMEOUT_MS).toLong()
        val manager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager

        if (!hasLocationPermission()) {
            result.success(null)
            return
        }
        if (!isProviderEnabled(manager, LocationManager.NETWORK_PROVIDER)) {
            result.success(null)
            return
        }

        requestNetworkLocation(manager, timeoutMs, result)
    }

    private fun hasLocationPermission(): Boolean {
        val coarse = context.checkSelfPermission(
            android.Manifest.permission.ACCESS_COARSE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED
        val fine = context.checkSelfPermission(
            android.Manifest.permission.ACCESS_FINE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED
        return coarse || fine
    }

    private fun isProviderEnabled(manager: LocationManager, provider: String): Boolean =
        try {
            manager.isProviderEnabled(provider)
        } catch (e: Exception) {
            false
        }

    private fun requestNetworkLocation(
        manager: LocationManager,
        timeoutMs: Long,
        result: MethodChannel.Result,
    ) {
        val handler = Handler(Looper.getMainLooper())
        val cancellationSignal = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            CancellationSignal()
        } else {
            null
        }
        var finished = false

        fun finish(location: Location?) {
            if (finished) return
            finished = true
            handler.removeCallbacksAndMessages(null)
            cancellationSignal?.cancel()
            if (location == null) {
                result.success(null)
                return
            }
            result.success(
                mapOf(
                    "latitude" to location.latitude,
                    "longitude" to location.longitude,
                    "accuracy" to location.accuracy.toDouble(),
                    "ageMs" to (System.currentTimeMillis() - location.time),
                ),
            )
        }

        // 超时不是错误：provider 一时给不出结果就交给上层兜底，界面该显示
        // 「无法获取位置」还是别的，由 Dart 侧统一决定。
        handler.postDelayed({ finish(null) }, timeoutMs)

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                manager.getCurrentLocation(
                    LocationManager.NETWORK_PROVIDER,
                    cancellationSignal,
                    context.mainExecutor,
                ) { location -> finish(location) }
            } else {
                @Suppress("DEPRECATION")
                manager.requestSingleUpdate(
                    LocationManager.NETWORK_PROVIDER,
                    object : LocationListener {
                        override fun onLocationChanged(location: Location) = finish(location)
                    },
                    Looper.getMainLooper(),
                )
            }
        } catch (e: SecurityException) {
            finish(null)
        } catch (e: IllegalArgumentException) {
            // provider 不存在或已被移除（个别 ROM 会禁掉 network provider）。
            finish(null)
        }
    }

    private companion object {
        /**
         * 8 秒。network provider 正常在百毫秒级返回；等这么久还没结果，
         * 基本可以认定这次拿不到了——再等只会让首页多空一会儿。
         */
        const val DEFAULT_TIMEOUT_MS = 8_000
    }
}
