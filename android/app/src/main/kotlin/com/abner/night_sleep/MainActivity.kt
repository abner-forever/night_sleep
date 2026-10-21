package com.abner.night_sleep

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private var compassHandler: CompassStreamHandler? = null
    private var appUpdateHandler: AppUpdateHandler? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        // **这一行必须留着。** 本工程用的是 embedding v2（清单里 `flutterEmbedding=2`），
        // 插件注册就发生在 `super.configureFlutterEngine` 的实现里
        // （`GeneratedPluginRegistrant.registerGeneratedPlugins`）。
        // 覆写时漏掉它 → 通知、录音、安全存储**全体静默失效**，
        // 编译期与运行期都不会有任何提示，只有功能悄悄不工作。
        super.configureFlutterEngine(flutterEngine)

        val updateHandler = AppUpdateHandler(this)
        appUpdateHandler = updateHandler
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "night_sleep/app_update")
            .setMethodCallHandler(updateHandler)

        // 本工程唯一一条手写的流式通道。名字与 iOS 侧、Dart 侧三处必须一致。
        val handler = CompassStreamHandler(this)
        compassHandler = handler
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, COMPASS_CHANNEL)
            .setStreamHandler(handler)

        // 夜间录音的前台服务开关。契约见 `lib/core/platform/night_audio_service.dart`。
        // 传 `applicationContext` 而不是 `this`：这个 handler 可能与引擎同寿，
        // 拿着 Activity 会把它连着一整个视图树一起留住。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, RECORDING_SERVICE_CHANNEL)
            .setMethodCallHandler(NightAudioServiceHandler(applicationContext))

        // Dart isolate 没了 → 采集端也就没了（Dart 侧的切片状态机与 `record` 插件的
        // `AudioRecord` 都在那一侧）。**这时候要撤服务，不能留着它**：留着就是通知栏上
        // 一条「正在录制」，而实际上一个采样都不采。
        //
        // **刻意不用 Activity 的 `onDestroy`：**Activity 会因配置变更重建
        // （清单 `configChanges` 只挡了 orientation 等几项，深色模式、字体缩放、
        // 分辨率变化仍会重建），而重建时 Dart isolate 还活着、录音还在跑——那一下
        // 撤服务会让整夜录音在用户切一次深色模式之后静静断掉。
        flutterEngine.addEngineLifecycleListener(object : FlutterEngine.EngineLifecycleListener {
            override fun onPreEngineRestart() = Unit

            override fun onEngineWillDestroy() {
                NightRecordingService.stop(applicationContext)
            }
        })
    }

    override fun onStart() {
        super.onStart()
        // 起前台服务的合法性闸口。`onStart` 而非 `onResume`：权限弹框、拉下通知抽屉
        // 都会走 pause，而那时应用还在屏幕上——用 pause 当「不可见」，用户一边看着
        // 界面一边被拒掉录音。
        AppVisibility.visible = true
    }

    override fun onStop() {
        // 应用离开屏幕（回到桌面、锁屏、被别的应用盖住）：此后**不许**再起前台服务，
        // 而且就算硬起，麦克风也是静音的。
        //
        // 注意这只挡「新起服务」，**不撤已经跑着的服务**——正在录的那一场要继续录，
        // 那正是这个功能存在的全部理由。
        AppVisibility.visible = false
        super.onStop()
    }

    override fun onDestroy() {
        // 兜底反注册：引擎拆除时不一定送达 EventChannel 的 `cancel`。
        // `dispose()` 是幂等的，正常路径下这里是空操作。
        compassHandler?.dispose()
        compassHandler = null
        appUpdateHandler?.dispose()
        appUpdateHandler = null
        super.onDestroy()
    }

    private companion object {
        const val COMPASS_CHANNEL = "night_sleep/compass"
        const val RECORDING_SERVICE_CHANNEL = "night_sleep/recording_service"
    }
}
