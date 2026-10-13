package com.example.night_sleep

import android.app.Activity
import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.SystemClock
import android.util.Log
import android.view.Surface
import io.flutter.plugin.common.EventChannel
import kotlin.math.acos
import kotlin.math.atan2
import kotlin.math.sqrt

/**
 * `night_sleep/compass` 的 Android 实现。
 *
 * **它是 iOS 那套算法的逐项复刻**（`ios/Runner/AppDelegate.swift` 的
 * `CompassStreamHandler`），不是「用 Android 的现成办法做一个罗盘」。理由：
 * Dart 侧的契约把问题拆成了三样**互相独立**的物理量——一个绝对的方位角 +
 * 一个相对的角速度，再由 `CompassHeadingFilter` 做互补滤波。若改用
 * `TYPE_ROTATION_VECTOR` 的融合方位角配一个融合角速度，等于把滤波做了两遍，
 * 平白多出滞后，而滤波器还得反过来跟它斗。而且 `needsCalibration` 要的是
 * **磁力计自己**的校准状态，`TYPE_MAGNETIC_FIELD.accuracy` 正好就是它。
 *
 * 通道契约见 `lib/core/platform/compass.dart` 与
 * `lib/features/compass/domain/compass_heading.dart` 的 `CompassReading.fromMap`。
 * 除 `heading` 外的键**一个都不能缺**：缺了 `fromMap` 会抛，页面表现成
 * 「暂时无法读取传感器」。
 *
 * ---- 单位与符号，逐条对过 iOS ----
 *
 * | 字段 | 值 |
 * | --- | --- |
 * | `timestamp` | 秒。`SensorEvent.timestamp` 是**纳秒**，`SystemClock.elapsedRealtimeNanos()` 与它同一时基 |
 * | `tilt` | 度，0 = 平放屏幕朝上 |
 * | `fieldStrength` | 微特斯拉（Android 原生就是 µT，无需换算） |
 * | `accuracy` | **iOS 标度**：uncalibrated -1 / low 0 / medium 1 / high 2 |
 * | `rotationRate` | rad/s，绕竖直轴 |
 * | `heading` | 度 0..360，无效时**整个键不发**（绝不发 -1 / 0 之类哨兵） |
 */
class CompassStreamHandler(private val activity: Activity) :
    EventChannel.StreamHandler, SensorEventListener {

    private var sensorManager: SensorManager? = null
    private var magSensor: Sensor? = null
    private var gravSensor: Sensor? = null
    private var gyroSensor: Sensor? = null

    private var eventSink: EventChannel.EventSink? = null

    // 三个传感器**各自回调、时间不同**，所以要各存各自的最新值，发射时再合成。
    // 存的是拷贝出来的 float，**不是 `SensorEvent.values` 本身**——框架会复用那个数组。
    private var magValues: FloatArray? = null
    private var gravValues: FloatArray? = null
    private var gyroValues: FloatArray? = null
    private var magAccuracy: Int = SensorManager.SENSOR_STATUS_UNRELIABLE
    private var lastEmitNanos: Long = 0

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        val manager = activity.getSystemService(Context.SENSOR_SERVICE) as? SensorManager
        sensorManager = manager
        val mag = manager?.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD)
        val grav = manager?.getDefaultSensor(Sensor.TYPE_GRAVITY)

        // 磁力计或重力缺一不可：没有磁力计就没有罗盘；没有重力就定不出水平面。
        // 这是**致命**错误，必须发，而且 code 必须是 "unavailable"——
        // 页面正是按这个 code 才认出「设备没有传感器」而显示对的那句话。
        if (manager == null || mag == null || grav == null) {
            events?.error("unavailable", "此设备没有可用的罗盘传感器", null)
            return
        }
        magSensor = mag
        gravSensor = grav
        gyroSensor = manager.getDefaultSensor(Sensor.TYPE_GYROSCOPE)

        // 重入前先清干净：页面在后台会 cancel、回前台再 listen，不清的话
        // 恢复后的**第一条**读数可能是几分钟前的磁力计样本，而滤波器第一次
        // update 取的是原值——会闪出一个错误的方向。
        magValues = null
        gravValues = null
        gyroValues = null
        lastEmitNanos = 0

        // 三行分开写、不用 `&&` 串联：串联会短路，后面两个就注册不上了。
        val magOk = manager.registerListener(this, magSensor, SENSOR_US)
        val gravOk = manager.registerListener(this, gravSensor, SENSOR_US)
        // 陀螺仪缺席不是致命的：没有它只是少了「转动时更跟手」的预测，把
        // rotationRate 报 0 即可，滤波器退化成对磁力计做低通。**不要**因此不发数据。
        val gyroOk = gyroSensor?.let { manager.registerListener(this, it, SENSOR_US) } ?: true

        if (!(magOk && gravOk && gyroOk)) {
            manager.unregisterListener(this)
            // 这条用另一个 code：它不是「设备不行」，而是「这次没注册上」，
            // 页面显示「暂时无法读取传感器…稍后重试」并给出「重新连接」才是准确的。
            events?.error("sensor_error", "注册传感器失败", null)
        }
    }

    override fun onCancel(arguments: Any?) {
        stop()
        eventSink = null
    }

    /** 兜底反注册。引擎拆除时不一定送达 `cancel`，见 `MainActivity.onDestroy`。 */
    fun dispose() {
        stop()
        eventSink = null
    }

    private fun stop() {
        sensorManager?.unregisterListener(this)
        magValues = null
        gravValues = null
        gyroValues = null
        lastEmitNanos = 0
    }

    override fun onSensorChanged(event: SensorEvent?) {
        val e = event ?: return
        when (e.sensor.type) {
            Sensor.TYPE_MAGNETIC_FIELD -> {
                magValues = floatArrayOf(e.values[0], e.values[1], e.values[2])
                magAccuracy = e.accuracy
                return
            }
            Sensor.TYPE_GRAVITY -> {
                gravValues = floatArrayOf(e.values[0], e.values[1], e.values[2])
                return
            }
            Sensor.TYPE_GYROSCOPE -> {
                gyroValues = floatArrayOf(e.values[0], e.values[1], e.values[2])
                maybeEmit()
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit

    /**
     * 由**陀螺仪**驱动发射。
     *
     * 选它当节拍是因为它最快、且注册期间必定持续上报——这样 30 Hz 的节奏是稳的，
     * 页面那条 5 秒「未收到传感器数据」看门狗就不可能误触。磁力计在有的设备上
     * 会长时间不出新值，用它驱动会让页面无端报「未收到传感器数据」。
     */
    private fun maybeEmit() {
        val sink = eventSink ?: return
        val mag = magValues ?: return
        val grav = gravValues ?: return

        val now = SystemClock.elapsedRealtimeNanos()
        if (now - lastEmitNanos < EMIT_INTERVAL_NANOS) return
        lastEmitNanos = now

        try {
            sink.success(buildReading(mag, grav, gyroValues, now))
        } catch (t: Throwable) {
            // 回调跑在主 looper 上，逸出的异常会**直接杀掉进程**。
            // 这里一律丢掉这个样本，**绝不发 error**：Dart 侧是
            // `cancelOnError: true`，一个 error 会把流永久掐断，
            // 用户得手动点「重新连接」才能恢复。
            if (DEBUG_LOG) Log.d(TAG, "丢弃样本：${t.message}")
        }
    }

    private fun buildReading(
        m: FloatArray,
        g: FloatArray,
        omega: FloatArray?,
        nowNanos: Long,
    ): Map<String, Any> {
        val gLen = sqrt(g[0] * g[0] + g[1] * g[1] + g[2] * g[2])
        // 自由落体或无效样本：分母趋零会让 tilt 变 NaN，页面会印出「NaN°」。
        if (gLen < 0.1f * SensorManager.GRAVITY_EARTH) {
            throw IllegalStateException("gravity 样本无效（$gLen）")
        }

        // **这一行是与 iOS 唯一的符号差异。** Android 的 TYPE_GRAVITY 在平放屏幕
        // 朝上时报 Z = **+9.81**，而 CoreMotion 报 -1.0，两者反号。所以 iOS 写
        // `up = -normalize(gravity)`，这里写 `up = +normalize(gravity)`。
        //
        // 照抄 iOS 那个负号的后果很具体：平放时 upZ = -1 → tilt = acos(-1) = 180°，
        // 于是 `tilt < 60` 永不成立 → **heading 永远是 null**，页面永远停在
        // 「请将手机屏幕朝上，保持水平」，而手机明明就平放着。
        val ux = g[0] / gLen
        val uy = g[1] / gLen
        val uz = g[2] / gLen

        // 磁力计读数去掉竖直分量，剩下的就是指向磁北的水平分量。
        val projection = m[0] * ux + m[1] * uy + m[2] * uz
        val nx = m[0] - projection * ux
        val ny = m[1] - projection * uy
        val nz = m[2] - projection * uz
        val horizontal = sqrt(nx * nx + ny * ny + nz * nz)

        val strength = sqrt(m[0] * m[0] + m[1] * m[1] + m[2] * m[2])
        val tilt = acos(uz.coerceIn(-1f, 1f).toDouble()) * 180.0 / Math.PI

        // 绕竖直轴的角速度。**形式与 iOS 一致，不要「顺手」再翻一次符号。**
        // 方位角是罗盘方位（俯视顺时针增大）。平放朝北时 up = +Z(设备)，设备 +X = 东，
        // 顺时针转的旋转矢量指向 **下**（即 -up），于是 ω·up = -θ̇，取负号才得 +θ̇，
        // 滤波器 `heading + rotationRate * elapsed` 才会朝真值该去的方向预测。
        // 若符号反了，表现不是「不动」而是**转动时抖动、回弹**——很难查。
        val rotationRate = if (omega != null) {
            -(omega[0] * ux + omega[1] * uy + omega[2] * uz).toDouble()
        } else {
            0.0
        }

        val accuracy = iosAccuracy(magAccuracy)

        val reading = HashMap<String, Any>()
        reading["timestamp"] = nowNanos / 1e9
        reading["rotationRate"] = rotationRate
        reading["tilt"] = tilt
        reading["fieldStrength"] = strength.toDouble()
        reading["accuracy"] = accuracy

        // 三个门槛与 iOS 逐字一致：磁场太弱 / 手机太陡 / 未校准，都不发布方位。
        if (horizontal > 1.0f && tilt < 60.0 && accuracy != ACCURACY_UNCALIBRATED) {
            // east = north × up，与 iOS 同式（也等于 Android SDK 自己对 east 的定义）。
            val eastX = (ny * uz - nz * uy) / horizontal
            val eastY = (nz * ux - nx * uz) / horizontal
            val northX = nx / horizontal
            val northY = ny / horizontal
            val forward = forwardFor(displayRotation())
            val angle = atan2(
                (eastX * forward[0] + eastY * forward[1]).toDouble(),
                (northX * forward[0] + northY * forward[1]).toDouble(),
            ) * 180.0 / Math.PI
            reading["heading"] = (angle + 360.0) % 360.0
        }
        // heading 无效时**整个键不发**。发 0 会让「朝北时看着正常、朝别处纹丝不动」。

        if (DEBUG_LOG) {
            // 原始矢量也打出来：判断「读数带着硬铁偏置」还是「算法算错了」，
            // 靠的是把竖直分量与地理真值比（深圳纬度约 22.6°，磁倾角约 31°，
            // 总场约 45 µT ⇒ 水平 ≈39、竖直 ≈23）。只打 heading 是分辨不出来的。
            Log.d(
                TAG,
                "tilt=${"%.1f".format(tilt)} horiz=${"%.1f".format(horizontal)} " +
                    "vert=${"%.1f".format(sqrt((strength * strength - horizontal * horizontal).coerceAtLeast(0f)))} " +
                    "strength=${"%.1f".format(strength)} acc=$magAccuracy→$accuracy " +
                    "rate=${"%.3f".format(rotationRate)} heading=${reading["heading"]}\n" +
                    "    m=[${"%.1f".format(m[0])}, ${"%.1f".format(m[1])}, ${"%.1f".format(m[2])}] " +
                    "g=[${"%.2f".format(g[0])}, ${"%.2f".format(g[1])}, ${"%.2f".format(g[2])}]",
            )
        }
        return reading
    }

    /**
     * `forward` = **当前显示内容的顶边**在设备坐标系里的方向。
     *
     * 与 iOS 按 `interfaceOrientation` 取 forward 是一回事。应用没有锁方向
     * （清单里没有 `android:screenOrientation`，Dart 侧也没有
     * `setPreferredOrientations`），所以横屏时「屏幕顶边」是另一条物理边，
     * 必须折算。
     *
     * **每次发射都现读**，不能在 `onListen` 里读一次：清单的 `configChanges` 含
     * `orientation`，Activity 不会重建，中途转屏时缓存值会让方位角整整差 90°/180°。
     *
     * ⚠️ **90 / 270 这两支尚未在真机上确认过。** Android SDK 自己的
     * `remapCoordinateSystem` 文档里那个「把手机当机械罗盘用」的例子
     * （`ROTATION_90` 用 `AXIS_Y, AXIS_MINUS_X`）暗示的方向与下面这张表相反，
     * 即可能是这两支要互换。已按实测办法核对过（见 docs/verification-log.md），
     * 若将来发现横屏方位差 180°，**改这里的两行即可**。
     */
    private fun forwardFor(rotation: Int): FloatArray = when (rotation) {
        Surface.ROTATION_0 -> floatArrayOf(0f, 1f)
        Surface.ROTATION_90 -> floatArrayOf(1f, 0f)
        Surface.ROTATION_180 -> floatArrayOf(0f, -1f)
        Surface.ROTATION_270 -> floatArrayOf(-1f, 0f)
        else -> floatArrayOf(0f, 1f)
    }

    private fun displayRotation(): Int {
        val display = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            activity.display
        } else {
            @Suppress("DEPRECATION")
            activity.windowManager.defaultDisplay
        }
        return display?.rotation ?: Surface.ROTATION_0
    }

    /**
     * Android 的 `SensorEvent.accuracy` 换算到 **iOS 标度**。
     *
     * Android 是 UNRELIABLE 0 / LOW 1 / MEDIUM 2 / HIGH 3，iOS 是 -1 / 0 / 1 / 2，
     * 所以就是 `android - 1`——这样 Dart 侧 `accuracy < 1` 恰好只在
     * UNRELIABLE 与 LOW 上成立，与 iOS 的 uncalibrated / low 完全一致
     * （LOW 的意思是「需要结合环境重新校准」，正是「画 8 字」那条提示该出现的时候）。
     *
     * **注意 `else` 那一支不能省。** Android 还有一个
     * `SENSOR_STATUS_NO_CONTACT = -1`；朴素的 `accuracy - 1` 会把它变成 **-2**，
     * 而 Dart 的门槛写的是 `accuracy != uncalibrated`（即 != -1）——-2 不等于 -1，
     * 于是**一个「磁力计没接触」的读数会被当成有效方位发布出去**。
     */
    private fun iosAccuracy(raw: Int): Int = when (raw) {
        SensorManager.SENSOR_STATUS_UNRELIABLE -> ACCURACY_UNCALIBRATED
        SensorManager.SENSOR_STATUS_ACCURACY_LOW -> 0
        SensorManager.SENSOR_STATUS_ACCURACY_MEDIUM -> 1
        SensorManager.SENSOR_STATUS_ACCURACY_HIGH -> 2
        else -> ACCURACY_UNCALIBRATED
    }

    private companion object {
        const val TAG = "Compass"
        const val DEBUG_LOG = true
        const val ACCURACY_UNCALIBRATED = -1

        /** 与 iOS 的 `deviceMotionUpdateInterval = 1/30` 对齐。 */
        const val EMIT_INTERVAL_NANOS = 30_000_000L

        /** `SENSOR_DELAY_GAME` = 20000 µs。 */
        const val SENSOR_US = SensorManager.SENSOR_DELAY_GAME
    }
}
