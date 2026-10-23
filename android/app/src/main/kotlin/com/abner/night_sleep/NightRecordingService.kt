package com.abner.night_sleep

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * 夜间录音的**前台服务**。
 *
 * 它本身不碰麦克风，一个采样都不采——**它只做一件事：让系统认为本应用「前台可见」**。
 * Android 9（API 28）起，只有前台应用、或带前台服务的应用才拿得到音频输入；否则
 * 应用照常运行，但录到的全是静音。Android 11（API 30）起，这个前台服务还必须声明
 * `microphone` 类型（清单里的 `android:foregroundServiceType="microphone"` + 权限）。
 *
 * 采集链路完全不动：PCM 仍然由 `record` 插件交给 Dart isolate，切片、落盘、清单全在
 * Dart 侧。所以本服务被系统杀掉 / 没起来，录音**不会**换一条链路，只会**收到静音**
 * ——那正是 `docs/verification-log.md` v3.19 记录的现象，也是 `NightRecordingState.silenced`
 * 那条状态存在的理由。
 *
 * ---- 三个刻意的选择 ----
 *
 * **① 通知渠道在第一次真要起服务时才建**（[onStartCommand] 里），不在
 * `Application.onCreate` 里建。没录过音的用户不该在系统设置的通知列表里看见一条
 * 他还没用过的功能。
 *
 * **② `IMPORTANCE_LOW`**：一个整夜要起停好几次（白噪音停了起一次、被抢占后再起一次）
 * 的通知，用 DEFAULT 会每次都「叮」一声，半夜把人吵醒。
 *
 * **③ `START_NOT_STICKY`**：进程被杀之后系统把服务拉起来时，**没有任何东西在录音**
 * ——Dart isolate 与 `AudioRecord` 都随进程一起没了。默认的 `START_STICKY` 会拉起一个
 * 空壳，通知栏上留一条「正在录制」而实际一个采样都不采，那正是本项目最不能有的
 * 「控件声称一个它并不具备的状态」（偏差 #7 / #31 一族）。
 *
 * ⚠️ **真机未验证**：本服务是否真能让 MI 9（API 30）上整夜录到真声音，只有装到机器上
 * 跑一整夜才知道。编译通过与单测通过都不等于这一条成立。
 */
class NightRecordingService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!promoteToForeground()) {
            // 抬成前台失败（权限被撤、类型不被允许…）：**立刻撤掉自己**，绝不留下一个
            // 既不是前台、又挂着「正在录制」通知的服务。Dart 侧这一刻已经拿到
            // `started`（`startForegroundService` 是异步返回的），所以它仍会去开流
            // ——那会退回到「收到数字静音」的老路上，界面 60 秒后如实说「麦克风被
            // 系统静音」。这不是理想结果，但它是**真话**，好过一条假的通知。
            stopSelf()
        }
        return START_NOT_STICKY
    }

    /**
     * 抬成前台服务。成功返回 true。
     *
     * **类型参数只在 API 30+ 传**：`ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE`
     * 是 API 30 才有的常量，往低版本传会抛 `IllegalArgumentException`——那会让一台
     * 本来好好的 API 24 机器直接起不来服务。
     */
    private fun promoteToForeground(): Boolean = try {
        ensureChannel()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            startForeground(
                NOTIFICATION_ID,
                buildNotification(),
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
            )
        } else {
            startForeground(NOTIFICATION_ID, buildNotification())
        }
        true
    } catch (t: Throwable) {
        Log.w(TAG, "起前台服务失败：${t.message}")
        false
    }

    override fun onDestroy() {
        // 撤掉通知。走 `stopService` 时系统一般会自己收走，但显式做一次能覆盖
        // 「服务被系统回收」那条路——那一条不该把一条「正在录制」留在通知栏里。
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        // 已存在时 `createNotificationChannel` 是空操作，重复调没有副作用。
        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = CHANNEL_DESCRIPTION
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    /**
     * 通知本身。
     *
     * 文案是**陈述**，不是承诺：「正在记录夜间声音」这句话为真，前提是 Dart 侧真的
     * 开着采集端——而接线顺序正是这么定的（Dart 先起服务、后开流；停的时候先停流、
     * 后撤服务），所以服务活着的这段时间里采集端确实活着。
     */
    private fun buildNotification(): Notification {
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(NOTIFICATION_TITLE)
            .setContentText(NOTIFICATION_TEXT)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setShowWhen(false)

        // 点通知回到应用。**用 `getLaunchIntentForPackage`（即启动器那条意图），
        // 不自己拼 `Intent(this, MainActivity::class.java)`**：清单里
        // `android:taskAffinity=""`（Flutter 模板配 `launchMode=singleTop` 的默认），
        // 自拼的意图少了 RESET_TASK_IF_NEEDED，能把同一个 Activity 开进两个任务里。
        // 启动器那条意图是系统自己产出的，行为与点桌面图标完全一致。
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        if (launch != null) {
            builder.setContentIntent(
                PendingIntent.getActivity(this, 0, launch, PendingIntent.FLAG_IMMUTABLE),
            )
        }
        return builder.build()
    }

    companion object {
        private const val TAG = "NightRecording"
        private const val NOTIFICATION_ID = 1001

        /** 渠道 id 一旦发布就别改：改了等于新建一个渠道，用户改过的设置会丢。 */
        private const val CHANNEL_ID = "night_sleep_recording"
        private const val CHANNEL_NAME = "夜间录音"
        private const val CHANNEL_DESCRIPTION = "会话期间采集声响时显示"

        private const val NOTIFICATION_TITLE = "正在记录夜间声音"
        private const val NOTIFICATION_TEXT = "夜深在采集声响片段，锁屏也会继续。"

        /**
         * 起服务。
         *
         * **必须在应用可见时调**（[NightAudioServiceHandler] 负责判），理由有两条，
         * 都是系统在拦：
         * - targetSdk ≥ 31 起，后台起前台服务直接抛 `ForegroundServiceStartNotAllowedException`；
         * - 而且就算硬起得来，后台状态下麦克风照样是静音的——白起一条通知。
         *
         * ⚠️ 本方法在 API 26+ 上会把 `startForeground` 的 5 秒时限一起带上：
         * 起来之后 5 秒内没有 [onStartCommand] 里那次 `startForeground`，系统会直接
         * 崩掉应用。所以 `onStartCommand` 里除了抬前台**什么都不该干**。
         */
        fun start(context: Context) {
            val intent = Intent(context, NightRecordingService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                // API 24 / 25 没有 `startForegroundService`，也还没有后台执行限制，
                // 直接 `startService` 即可。服务照样会抬成前台（只是不算「必须抬」）。
                context.startService(intent)
            }
        }

        /** 撤服务。没在跑的时候调它是空操作。 */
        fun stop(context: Context) {
            context.stopService(Intent(context, NightRecordingService::class.java))
        }
    }
}
