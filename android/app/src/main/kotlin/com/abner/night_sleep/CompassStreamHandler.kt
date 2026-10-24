package com.abner.night_sleep

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
import kotlin.math.asin
import kotlin.math.atan2
import kotlin.math.sqrt

/**
 * `night_sleep/compass` 的 Android 实现。
 *
 * 对外契约与 iOS（`ios/Runner/AppDelegate.swift`）一致：一条绝对方位角 + 一个
 * 相对角速度，再由 Dart 侧的 `CompassHeadingFilter` 做互补滤波。
 *
 * **方位角优先取 `TYPE_ROTATION_VECTOR`，不是直接拿磁力计 + 重力投影。**
 * 2026-10-24 在 MI 9 上实测：手机静止、陀螺仪读数约 0 时，磁力计那一路的方位
 * 峰峰值 **14.6°**、标准差 **2.75°**（地磁水平分量只有 12.5 µT，硬铁干扰很重），
 * 页面上的指针会一直自己晃；换成旋转矢量后峰峰值 **0.068°**、标准差 **0.019°**。
 * 系统自带指南针用的也是旋转矢量。
 *
 * 旋转矢量缺席（少见）时退回磁力计 + 重力，功能不受影响，只是会和以前一样抖。
 * `needsCalibration` 仍取 **磁力计自己**的校准状态（`TYPE_MAGNETIC_FIELD.accuracy`），
 * 旋转矢量给不了这个。
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
 * | `tiltX` / `tiltY` | 度，设备 +X / +Y 轴抬起的角度（水平仪气泡用），正 = 右 / 上抬 |
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
    private var rvSensor: Sensor? = null

    private var eventSink: EventChannel.EventSink? = null

    // 几个传感器**各自回调、时间不同**，所以要各存各自的最新值，发射时再合成。
    // 存的是拷贝出来的 float，**不是 `SensorEvent.values` 本身**——框架会复用那个数组。
    private var magValues: FloatArray? = null
    private var gravValues: FloatArray? = null
    private var gyroValues: FloatArray? = null
    private var rvValues: FloatArray? = null
    private var rvTimestamp: Long = 0
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
        rvSensor = manager.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)

        // 重入前先清干净：页面在后台会 cancel、回前台再 listen，不清的话
        // 恢复后的**第一条**读数可能是几分钟前的磁力计样本，而滤波器第一次
        // update 取的是原值——会闪出一个错误的方向。
        magValues = null
        gravValues = null
        gyroValues = null
        rvValues = null
        rvTimestamp = 0
        lastEmitNanos = 0

        // 三行分开写、不用 `&&` 串联：串联会短路，后面两个就注册不上了。
        val magOk = manager.registerListener(this, magSensor, SENSOR_US)
        val gravOk = manager.registerListener(this, gravSensor, SENSOR_US)
        // 陀螺仪缺席不是致命的：没有它只是少了「转动时更跟手」的预测，把
        // rotationRate 报 0 即可，滤波器退化成对磁力计做低通。**不要**因此不发数据。
        val gyroOk = gyroSensor?.let { manager.registerListener(this, it, SENSOR_US) } ?: true
        // 旋转矢量同样缺席不致命：没有它退回「磁力计 + 重力」直接算方位（会抖，
        // 但能用）。见 [buildReading] 里两条来源的选择。
        val rvOk = rvSensor?.let { manager.registerListener(this, it, SENSOR_US) } ?: true

        if (!(magOk && gravOk && gyroOk && rvOk)) {
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
        rvValues = null
        rvTimestamp = 0
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
                // 重力也是发射节拍之一：水平仪看的是它，别让气泡只等陀螺仪。
                maybeEmit()
                return
            }
            Sensor.TYPE_GYROSCOPE -> {
                gyroValues = floatArrayOf(e.values[0], e.values[1], e.values[2])
                maybeEmit()
            }
            Sensor.TYPE_ROTATION_VECTOR -> {
                // 3 / 4 / 5 元都得原样留着：`getRotationMatrixFromVector` 两种长度都收，
                // 第四元是「方位角精度」，不能在这里截断。
                rvValues = e.values.clone()
                rvTimestamp = e.timestamp
                maybeEmit()
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit

    /**
     * 由传感器回调驱动发射（陀螺仪 / 旋转矢量 / 重力都会进来），统一约 60 Hz 限流。
     *
     * 只要有陀螺仪，节奏就是稳的，页面那条 5 秒「未收到传感器数据」看门狗就不可能
     * 误触。旋转矢量与重力再顶上来，是为了**没有陀螺仪的设备**也照样能发数据。
     */
    private fun maybeEmit() {
        val sink = eventSink ?: return
        val mag = magValues ?: return

        val now = SystemClock.elapsedRealtimeNanos()
        // 没有可用的旋转矢量时才需要重力来定水平面。
        if (!hasFreshRotationVector(now) && gravValues == null) return
        if (now - lastEmitNanos < EMIT_INTERVAL_NANOS) return
        lastEmitNanos = now

        try {
            sink.success(buildReading(mag, gravValues, gyroValues, now))
        } catch (t: Throwable) {
            // 回调跑在主 looper 上，逸出的异常会**直接杀掉进程**。
            // 这里一律丢掉这个样本，**绝不发 error**：Dart 侧是
            // `cancelOnError: true`，一个 error 会把流永久掐断，
            // 用户得手动点「重新连接」才能恢复。
            if (DEBUG_LOG) Log.d(TAG, "丢弃样本：${t.message}")
        }
    }

    /** 旋转矢量的时间戳与 `elapsedRealtimeNanos()` 同一时基，可直接相减。 */
    private fun hasFreshRotationVector(nowNanos: Long): Boolean {
        val rv = rvValues ?: return false
        if (rv.size < 3) return false
        return nowNanos >= rvTimestamp && nowNanos - rvTimestamp <= RV_STALE_NANOS
    }

    /**
     * 重力向量归一化成「上」方向；自由落体或无效样本返回 null。
     *
     * **这一处是与 iOS 唯一的符号差异。** Android 的 TYPE_GRAVITY 在平放屏幕朝上时
     * 报 Z = **+9.81**，而 CoreMotion 报 -1.0，两者反号。所以 iOS 写
     * `up = -normalize(gravity)`，这里写 `up = +normalize(gravity)`。
     *
     * 照抄 iOS 那个负号的后果很具体：平放时 upZ = -1 → tilt = acos(-1) = 180°，
     * 于是 `tilt < 60` 永不成立 → **heading 永远是 null**，页面永远停在
     * 「请将手机屏幕朝上，保持水平」，而手机明明就平放着。
     */
    private fun gravityUp(g: FloatArray?): FloatArray? {
        if (g == null) return null
        val length = sqrt(g[0] * g[0] + g[1] * g[1] + g[2] * g[2])
        if (length < 0.1f * SensorManager.GRAVITY_EARTH) return null
        return floatArrayOf(g[0] / length, g[1] / length, g[2] / length)
    }

    private fun buildReading(
        m: FloatArray,
        g: FloatArray?,
        omega: FloatArray?,
        nowNanos: Long,
    ): Map<String, Any> {
        val strength = sqrt(m[0] * m[0] + m[1] * m[1] + m[2] * m[2])
        val accuracy = iosAccuracy(magAccuracy)
        // 取一份局部引用：`rvValues` 是可变字段，直接读没法智能转换。
        val rotationVector = if (hasFreshRotationVector(nowNanos)) rvValues else null
        val rotation = rotationVector?.let {
            FloatArray(9).also { r -> SensorManager.getRotationMatrixFromVector(r, it) }
        }

        // ---- up：竖直向上（设备坐标系） ----
        //
        // **优先用重力，不用旋转矢量的 up。** 两者都是融合结果，重力这一路
        // 更平滑，水平仪气泡逐帧看不会带出姿态融合的细小台阶。
        // 重力缺席（少见）才退回旋转矢量的第三行。
        //
        // `getRotationMatrixFromVector` 得到的 R 把设备坐标映射到世界坐标
        // （X 东 / Y 北 / Z 上），第 3 行（R[6..8]）是世界「上」在设备坐标里的表示。
        val up = gravityUp(g)
            ?: rotation?.let { floatArrayOf(it[6], it[7], it[8]) }
            ?: throw IllegalStateException("没有可用的姿态样本")
        val ux = up[0]
        val uy = up[1]
        val uz = up[2]

        // ---- north：指向磁北的水平方向（设备坐标系） ----
        //
        // **手机静止时方位抖不抖，全靠旋转矢量。** 直接用磁力计 + 重力投影会把
        // 硬铁/软铁干扰原样算进方位：本机实测静止时峰峰值 14.6°、标准差 2.75°
        // （地磁水平分量只有 12.5 µT）。旋转矢量是系统融合后的姿态，第二行
        // （R[3..5]）就是世界「北」。旋转矢量缺席时才退回磁力计投影。
        val rawNorth = rotation?.let { floatArrayOf(it[3], it[4], it[5]) }
            ?: floatArrayOf(
                m[0], m[1], m[2]
            )
        // 统一去掉竖直分量：即便用了重力 up、拿的是旋转矢量的 north，也让它严格
        // 落在水平面里（两者来自同一世界坐标系，差异本就很小的）。
        val northProjection = rawNorth[0] * ux + rawNorth[1] * uy + rawNorth[2] * uz
        val nx = rawNorth[0] - northProjection * ux
        val ny = rawNorth[1] - northProjection * uy
        val nz = rawNorth[2] - northProjection * uz
        val northLength = sqrt(nx * nx + ny * ny + nz * nz)

        // 「磁场够不够强」这道门槛必须用**磁力计自己的水平分量（µT）**：
        // 旋转矢量的 north 是单位向量，拿它判断磁场强弱没有意义。
        val projection = m[0] * ux + m[1] * uy + m[2] * uz
        val magNorthX = m[0] - projection * ux
        val magNorthY = m[1] - projection * uy
        val magNorthZ = m[2] - projection * uz
        val magneticHorizontal =
            sqrt(magNorthX * magNorthX + magNorthY * magNorthY + magNorthZ * magNorthZ)

        val tilt = acos(uz.coerceIn(-1f, 1f).toDouble()) * 180.0 / Math.PI

        // 水平仪要的是「往哪边斜」：分别取 up 在设备 +X / +Y 上的分量。
        // 正值 = 右侧 / 顶部抬起，页面据此把气泡推向翘起的一侧。
        val tiltX = asin(ux.coerceIn(-1f, 1f).toDouble()) * 180.0 / Math.PI
        val tiltY = asin(uy.coerceIn(-1f, 1f).toDouble()) * 180.0 / Math.PI

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

        val reading = HashMap<String, Any>()
        reading["timestamp"] = nowNanos / 1e9
        reading["rotationRate"] = rotationRate
        reading["tilt"] = tilt
        reading["tiltX"] = tiltX
        reading["tiltY"] = tiltY
        reading["fieldStrength"] = strength.toDouble()
        reading["accuracy"] = accuracy

        // 三个门槛与 iOS 逐字一致：磁场太弱 / 手机太陡 / 未校准，都不发布方位。
        if (magneticHorizontal > 1.0f &&
            tilt < 60.0 &&
            accuracy != ACCURACY_UNCALIBRATED &&
            northLength > 1e-3f
        ) {
            // east = north × up，与 iOS 同式（也等于 Android SDK 自己对 east 的定义）。
            val eastX = (ny * uz - nz * uy) / northLength
            val eastY = (nz * ux - nx * uz) / northLength
            val northX = nx / northLength
            val northY = ny / northLength
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
                "src=${if (rotationVector != null) "rv" else "mag"} " +
                    "tilt=${"%.1f".format(tilt)} horiz=${"%.1f".format(magneticHorizontal)} " +
                    "vert=${"%.1f".format(sqrt((strength * strength - magneticHorizontal * magneticHorizontal).coerceAtLeast(0f)))} " +
                    "strength=${"%.1f".format(strength)} acc=$magAccuracy→$accuracy " +
                    "rate=${"%.3f".format(rotationRate)} heading=${reading["heading"]}\n" +
                    "    m=[${"%.1f".format(m[0])}, ${"%.1f".format(m[1])}, ${"%.1f".format(m[2])}] " +
                    "g=${g?.let { "[${"%.2f".format(it[0])}, ${"%.2f".format(it[1])}, ${"%.2f".format(it[2])}]" } ?: "无"}",
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

        /**
         * 每秒 60 条带格式化的日志，本身就会拖慢帧率；诊断时在本地临时改成
         * true，**不要把 true 提交上来**。
         */
        const val DEBUG_LOG = false
        const val ACCURACY_UNCALIBRATED = -1

        /**
         * 约 60 Hz。30 Hz 在 60 Hz 屏幕上转动时会一卡一卡；陀螺仪预测按 60 Hz
         * 推进，盘面就顺了。与 iOS 的 `deviceMotionUpdateInterval = 1/60` 对齐。
         */
        const val EMIT_INTERVAL_NANOS = 16_666_667L

        /** 旋转矢量超过这么久没更新就退回磁力计那一路（正常应在 20–50 ms 一帧）。 */
        const val RV_STALE_NANOS = 250_000_000L

        /**
         * `SENSOR_DELAY_FASTEST`。GAME 只有 50 Hz，页面就跟着 ~45 FPS；
         * 发射由 [EMIT_INTERVAL_NANOS] 限到 60 Hz，所以这里只是让数据够用。
         * 只在罗盘页在前台时注册，离开页面就反注册。
         */
        const val SENSOR_US = SensorManager.SENSOR_DELAY_FASTEST
    }
}
